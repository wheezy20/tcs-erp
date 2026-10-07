-- create_payslip deducts staff advances (20261008100000).
--
-- Unchanged signature, security definer and search_path (plain create or
-- replace, no overload, grants untouched). Changes vs the 20261007100000
-- version, nothing else:
--   * after every other deduction, each eligible staff advance (Active, due
--     this month, not already repaid in a later month, balance > 0; see
--     staff_advance_deduction_preview) is repaid by least(instalment,
--     balance), oldest approval first, capped so net pay can't go below
--     zero. The cap is Eyram's default, PENDING the accountant's
--     confirmation (docs/CONSTRAINTS.md);
--   * the repayments are added to payslips.iou and total_deductions, after
--     tax and without touching taxable income (accountant confirmed,
--     reported by Eyram 2026-10-07, written copy to be saved), and recorded
--     in staff_advance_repayments against the payslip (deleted with it);
--   * a manual IOU (p_iou) on a payslip that deducts an advance is refused,
--     so the two can never double count.
-- A payslip for an employee with no eligible advance is computed exactly as
-- before. Existing payslips are not recalculated.

create or replace function public.create_payslip(
  p_payroll_run_id uuid,
  p_employee_id uuid,
  p_overtime_hours numeric default 0,
  p_overtime_rate numeric default 0,
  p_allowances jsonb default '[]'::jsonb,
  p_fines numeric default 0,
  p_iou numeric default 0
)
returns public.payslips
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
  v_emp_status text;
  v_config public.employee_pay_config;
  v_rates public.statutory_rates;
  v_ot_rates public.overtime_tax_rates;
  v_has_ot_rates boolean;
  v_run_date date;
  v_overtime_pay numeric;
  v_overtime_concession boolean := false;
  v_overtime_tax numeric := 0;
  v_overtime_taxed numeric;
  v_overtime_cap numeric;
  v_overtime_within_cap numeric;
  v_total_taxable_allowances numeric := 0;
  v_total_allowances numeric := 0;
  v_total_earning numeric;
  v_gross_salary numeric;
  v_taxable_income numeric;
  v_tax numeric := 0;
  v_tier2 numeric := 0;
  v_ssnit numeric := 0;
  v_ssnit_employer numeric := 0;
  v_total_deductions numeric;
  v_net_pay numeric;
  v_payslip public.payslips;
  v_band record;
  v_remaining numeric;
  v_band_amount numeric;
  v_alw jsonb;
  v_alw_type_id uuid;
  v_alw_amount numeric;
  v_allowance_taxable boolean;
  v_capacity numeric;
  v_take numeric;
  v_loans_total numeric := 0;
  v_loans jsonb := '[]'::jsonb;
  v_adv record;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules; Auditor is read-only.
  perform public.require_finance_writer();

  select * into v_run from public.payroll_runs where id = p_payroll_run_id;
  if v_run is null then
    raise exception 'Payroll run % not found', p_payroll_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Payroll run % is already posted and cannot take new payslips', v_run.id;
  end if;

  select employment_status into v_emp_status from public.employees where id = p_employee_id;
  if v_emp_status is null then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp_status <> 'Active' then
    raise exception 'Employee % is not active (status: %) and cannot be paid', p_employee_id, v_emp_status;
  end if;

  v_run_date := make_date(v_run.year, v_run.month, 1);

  -- Current APPROVED pay config for this employee as of the run's month.
  select * into v_config
  from public.employee_pay_config
  where employee_id = p_employee_id
    and approval_status = 'Active'
    and effective_from <= v_run_date
    and (effective_to is null or effective_to >= v_run_date)
  order by effective_from desc
  limit 1;

  if v_config is null then
    raise exception 'No approved pay config for employee % as of %', p_employee_id, v_run_date;
  end if;

  select * into v_rates
  from public.statutory_rates
  where effective_from <= v_run_date
  order by effective_from desc
  limit 1;

  if v_rates is null then
    raise exception 'No statutory_rates configured effective on or before %', v_run_date;
  end if;

  -- Unlike statutory_rates, a missing row is not an error: months before
  -- the first row keep the old treatment.
  select * into v_ot_rates
  from public.overtime_tax_rates
  where effective_from <= v_run_date
  order by effective_from desc
  limit 1;
  v_has_ot_rates := found;

  -- The overtime figure printed on the payslip (accountant confirmed,
  -- reported 2026-10-07): every use below reads this rounded amount.
  v_overtime_pay := round(coalesce(p_overtime_hours, 0) * coalesce(p_overtime_rate, 0), 2);

  for v_alw in select * from jsonb_array_elements(coalesce(p_allowances, '[]'::jsonb)) loop
    v_alw_type_id := (v_alw->>'allowance_type_id')::uuid;
    v_alw_amount := coalesce((v_alw->>'amount')::numeric, 0);

    select taxable into v_allowance_taxable
    from public.allowance_types where id = v_alw_type_id;
    if v_allowance_taxable is null then
      raise exception 'Unknown allowance type %', v_alw_type_id;
    end if;

    v_total_allowances := v_total_allowances + v_alw_amount;
    if v_allowance_taxable then
      v_total_taxable_allowances := v_total_taxable_allowances + v_alw_amount;
    end if;
  end loop;

  v_total_earning := v_config.basic_salary + v_overtime_pay + v_total_allowances;
  v_gross_salary := v_total_earning;

  -- Employee SSNIT + Tier 2, and the employer's 13% SSNIT, all on basic
  -- salary and all gated on pays_ssnit / pays_tier2.
  if v_config.pays_ssnit then
    v_ssnit := round(v_config.basic_salary * v_rates.ssnit_employee_pct / 100, 2);
    v_ssnit_employer := round(v_config.basic_salary * v_rates.ssnit_employer_pct / 100, 2);
  end if;
  if v_config.pays_tier2 then
    v_tier2 := round(v_config.basic_salary * v_rates.tier2_employee_pct / 100, 2);
  end if;

  -- Concessionary overtime tax, worked from the overtime figure the payslip
  -- shows (overtime_pay is numeric(12,2)), not the unrounded hours x rate
  -- (Eyram, 2026-10-06). PAYE keeps its existing rounding. The qualifying
  -- test is basic salary only, annualised as that month's basic x 12,
  -- overtime and allowances excluded.
  v_overtime_taxed := round(v_overtime_pay, 2);
  v_overtime_concession := v_has_ot_rates
    and v_config.pays_paye
    and v_overtime_taxed > 0
    and v_config.basic_salary * 12 <= v_ot_rates.qualifying_annual_basic_max;

  if v_overtime_concession then
    v_overtime_cap := round(v_config.basic_salary * v_ot_rates.overtime_cap_pct_of_basic / 100, 2);
    v_overtime_within_cap := least(v_overtime_taxed, v_overtime_cap);
    v_overtime_tax :=
      round(v_overtime_within_cap * v_ot_rates.rate_within_cap_pct / 100, 2)
      + round((v_overtime_taxed - v_overtime_within_cap) * v_ot_rates.rate_above_cap_pct / 100, 2);
  end if;

  -- Concessionary overtime is taxed above, so it stays out of the PAYE base.
  v_taxable_income := v_config.basic_salary
    + case when v_overtime_concession then 0 else v_overtime_pay end
    + v_total_taxable_allowances - v_ssnit - v_tier2;
  if v_taxable_income < 0 then
    v_taxable_income := 0;
  end if;

  if v_config.pays_paye then
    v_remaining := v_taxable_income;
    for v_band in
      select * from public.paye_bands
      where effective_from <= v_run_date
        and effective_from = (
          select max(effective_from) from public.paye_bands where effective_from <= v_run_date
        )
      order by band_order asc
    loop
      exit when v_remaining <= 0;
      v_band_amount := least(
        v_remaining,
        coalesce(v_band.upper_bound, v_remaining + v_band.lower_bound) - v_band.lower_bound
      );
      if v_band_amount > 0 then
        v_tax := v_tax + round(v_band_amount * v_band.rate / 100, 2);
        v_remaining := v_remaining - v_band_amount;
      end if;
    end loop;
  end if;

  v_total_deductions := v_tax + v_overtime_tax + v_tier2 + v_ssnit
    + coalesce(p_fines, 0) + coalesce(p_iou, 0);

  -- Staff advances (20261008100000): each eligible advance is repaid by
  -- least(instalment, balance), oldest approval first, after every other
  -- deduction and capped so net pay can't go below zero (the cap is a
  -- PENDING rule: Eyram's default, not yet confirmed by the accountant).
  -- The repayments join payslips.iou, which post_payroll_run credits to
  -- 1350. Advances are locked so two payslips can't both spend a balance.
  perform 1 from public.staff_advances
  where employee_id = p_employee_id and status = 'Active'
  for update;
  v_capacity := greatest(0, v_gross_salary - v_total_deductions);
  for v_adv in
    select * from public.staff_advance_deduction_preview(p_employee_id, p_payroll_run_id)
    where skip_reason is null and due > 0
    order by ord
  loop
    if coalesce(p_iou, 0) <> 0 then
      raise exception 'This employee has an active staff advance. Recover through the advance, or pause it first, instead of entering an IOU';
    end if;
    v_take := least(v_adv.due, v_capacity);
    if v_take > 0 then
      v_loans := v_loans || jsonb_build_object(
        'advance_id', v_adv.advance_id, 'amount', v_take, 'instalment_due', v_adv.due);
      v_loans_total := v_loans_total + v_take;
      v_capacity := v_capacity - v_take;
    end if;
  end loop;
  v_total_deductions := v_total_deductions + v_loans_total;

  v_net_pay := v_gross_salary - v_total_deductions;

  insert into public.payslips (
    payroll_run_id, employee_id, employee_pay_config_id,
    basic_salary, overtime_hours, overtime_rate, overtime_pay,
    total_allowances, total_earning, gross_salary, taxable_income,
    tax, overtime_tax, overtime_concession,
    tier2, ssnit, ssnit_employer, fines, iou, total_deductions, net_pay
  ) values (
    p_payroll_run_id, p_employee_id, v_config.id,
    v_config.basic_salary, coalesce(p_overtime_hours, 0), coalesce(p_overtime_rate, 0), v_overtime_pay,
    v_total_allowances, v_total_earning, v_gross_salary, v_taxable_income,
    v_tax, v_overtime_tax, v_overtime_concession,
    v_tier2, v_ssnit, v_ssnit_employer, coalesce(p_fines, 0), coalesce(p_iou, 0) + v_loans_total,
    v_total_deductions, v_net_pay
  )
  returning * into v_payslip;

  insert into public.payslip_allowances (payslip_id, allowance_type_id, amount)
  select
    v_payslip.id,
    (elem->>'allowance_type_id')::uuid,
    coalesce((elem->>'amount')::numeric, 0)
  from jsonb_array_elements(coalesce(p_allowances, '[]'::jsonb)) as elem;

  insert into public.staff_advance_repayments (advance_id, payslip_id, amount, instalment_due)
  select (l->>'advance_id')::uuid, v_payslip.id, (l->>'amount')::numeric, (l->>'instalment_due')::numeric
  from jsonb_array_elements(v_loans) as l;

  return v_payslip;
end;
$$;
