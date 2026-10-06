-- Concessionary overtime tax (GRA overtime rule): the engine only.
--
-- For an employee whose qualifying annual income is at or under a threshold,
-- overtime is taxed on its own and kept out of the graduated PAYE base: one
-- rate on overtime up to a share of monthly basic salary, a second rate on
-- the excess. Everyone else keeps today's treatment (overtime is ordinary
-- income on the graduated bands).
--
-- Rules decided by Eyram (2026-10-06); accountant approval reported by
-- Eyram, written copy to be saved (docs/CONSTRAINTS.md):
--   * the threshold test is on basic salary only: that month's basic x 12,
--     before SSNIT and Tier 2, with overtime and allowances excluded;
--   * "not more than": a basic of exactly threshold / 12 qualifies, and
--     overtime of exactly the cap share stays at the lower rate;
--   * the cap is a share of that month's basic salary;
--   * an employee exempt from PAYE (pays_paye = false, which includes
--     National Service staff) pays no overtime tax either;
--   * extra-class payments are entered as overtime.
--
-- This migration holds no statutory number. The threshold, the cap share
-- and both rates live in overtime_tax_rates rows, effective-dated and picked
-- by payroll month like paye_bands. It adds no row: with the table empty,
-- create_payslip() computes exactly what it did before. The first row (the
-- confirmed figures and effective date) is its own migration,
-- 20261006110000_overtime_tax_rates_2026.sql.
--
-- Existing payslips keep overtime_tax = 0 and overtime_concession = false
-- (the column defaults), which is what they were computed under. Snapshot
-- discipline: nothing is backfilled, and a Draft payslip only picks up the
-- new rule if it is deleted and generated again. Posted runs stay as posted.

-- ============================================================ 1. config table

-- One row per effective date (the statutory_rates shape). create_payslip()
-- uses the row with the latest effective_from on or before the first day of
-- the payroll month. No row for a month means no concession that month.
create table public.overtime_tax_rates (
  id uuid primary key default gen_random_uuid(),
  effective_from date not null unique,
  qualifying_annual_basic_max numeric(12, 2) not null check (qualifying_annual_basic_max >= 0),
  overtime_cap_pct_of_basic numeric(5, 2) not null
    check (overtime_cap_pct_of_basic between 0 and 100),
  rate_within_cap_pct numeric(5, 3) not null check (rate_within_cap_pct between 0 and 100),
  rate_above_cap_pct numeric(5, 3) not null check (rate_above_cap_pct between 0 and 100),
  created_at timestamptz not null default now()
);

-- Same access as paye_bands and statutory_rates: Manager, Accountant and
-- Auditor read; Manager and Accountant write; anon nothing.
alter table public.overtime_tax_rates enable row level security;

create policy overtime_tax_rates_select on public.overtime_tax_rates
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

create policy overtime_tax_rates_insert on public.overtime_tax_rates
for insert with check (public.has_role(array['Manager', 'Accountant']));

create policy overtime_tax_rates_update on public.overtime_tax_rates
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));

create policy overtime_tax_rates_delete on public.overtime_tax_rates
for delete using (public.has_role(array['Manager', 'Accountant']));

revoke all on public.overtime_tax_rates from anon, authenticated;
grant select, insert, update, delete on public.overtime_tax_rates to authenticated;
grant select, insert, update, delete on public.overtime_tax_rates to service_role;

-- ============================================================ 2. payslip columns

-- overtime_tax is a snapshot like tax and ssnit_employer. overtime_concession
-- records that the concession was applied to this payslip's overtime, so a
-- zero overtime_tax can be told apart from "not qualifying", "exempt" or
-- "no rule that month" (all of which also leave overtime_tax at 0).
alter table public.payslips
  add column overtime_tax numeric(12, 2) not null default 0,
  add column overtime_concession boolean not null default false,
  add constraint payslips_overtime_tax_check check (overtime_tax >= 0),
  add constraint payslips_overtime_tax_concession_check
    check (overtime_concession or overtime_tax = 0);

-- ============================================================ 3. create_payslip()

-- Unchanged signature (plain create or replace, no overload risk). Changes
-- vs the 20260909130000 version:
--   * looks up the overtime_tax_rates row for the run's month;
--   * decides the concession: a row exists, pays_paye, overtime as shown
--     on the payslip > 0, and basic x 12 at or under the threshold;
--   * when it applies, leaves overtime out of taxable_income and computes
--     overtime_tax from the overtime amount as stored on the payslip
--     (rounded to 2 dp), each part rounded to 2 dp; it joins
--     total_deductions;
--   * stores overtime_tax and overtime_concession.
-- Gross, total earning, SSNIT and Tier 2 are computed exactly as before.
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

  v_overtime_pay := coalesce(p_overtime_hours, 0) * coalesce(p_overtime_rate, 0);

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
    v_tier2, v_ssnit, v_ssnit_employer, coalesce(p_fines, 0), coalesce(p_iou, 0),
    v_total_deductions, v_net_pay
  )
  returning * into v_payslip;

  insert into public.payslip_allowances (payslip_id, allowance_type_id, amount)
  select
    v_payslip.id,
    (elem->>'allowance_type_id')::uuid,
    coalesce((elem->>'amount')::numeric, 0)
  from jsonb_array_elements(coalesce(p_allowances, '[]'::jsonb)) as elem;

  return v_payslip;
end;
$$;

-- ============================================================ 4. post_payroll_run()

-- Unchanged signature. Only change vs the 20260909150000 version: the run's
-- total overtime_tax is credited to 2330 PAYE Payable as its own line,
-- after the PAYE line. A run with no overtime tax posts exactly the same
-- entry as before (zero-amount lines are omitted, as for every other line).
create or replace function public.post_payroll_run(p_run_id uuid)
returns public.journal_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
  v_entry_date date;
  v_period text;
  v_count integer := 0;
  v_gross numeric := 0;
  v_ssnit numeric := 0;
  v_ssnit_employer numeric := 0;
  v_tier2 numeric := 0;
  v_paye numeric := 0;
  v_overtime_tax numeric := 0;
  v_fines numeric := 0;
  v_iou numeric := 0;
  v_net numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_entry public.journal_entries;
begin
  -- Approval and posting are one step, so this is Manager-only now
  -- (an Accountant gets the run to 'Ready for Review'; a Manager approves).
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve and post a payroll run';
  end if;

  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_run.status = 'Posted' then
    raise exception 'Payroll run % is already posted', p_run_id;
  end if;
  if v_run.status <> 'Ready for Review' then
    raise exception 'Submit the run for review before it can be approved (status: %)', v_run.status;
  end if;

  select
    count(*),
    coalesce(sum(gross_salary), 0),
    coalesce(sum(ssnit), 0),
    coalesce(sum(ssnit_employer), 0),
    coalesce(sum(tier2), 0),
    coalesce(sum(tax), 0),
    coalesce(sum(overtime_tax), 0),
    coalesce(sum(fines), 0),
    coalesce(sum(iou), 0),
    coalesce(sum(net_pay), 0)
  into v_count, v_gross, v_ssnit, v_ssnit_employer, v_tier2, v_paye, v_overtime_tax,
    v_fines, v_iou, v_net
  from public.payslips
  where payroll_run_id = p_run_id;

  if v_count = 0 then
    raise exception 'Payroll run % has no payslips to post', p_run_id;
  end if;
  if v_net <= 0 then
    raise exception 'Total net pay for run % must be positive to post (got %)', p_run_id, v_net;
  end if;

  -- Last calendar day of the run's month — pay is accrued at period end.
  v_entry_date := (make_date(v_run.year, v_run.month, 1) + interval '1 month' - interval '1 day')::date;
  v_period := to_char(make_date(v_run.year, v_run.month, 1), 'FMMonth YYYY');

  v_lines := v_lines
    || jsonb_build_object(
      'account_id', public.account_id_by_code('5140'),
      'debit', v_gross, 'credit', 0, 'description', 'Gross pay — ' || v_period
    )
    || jsonb_build_object(
      'account_id', public.account_id_by_code('2300'),
      'debit', 0, 'credit', v_net, 'description', 'Net pay payable — ' || v_period
    );

  if v_ssnit > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2310'),
      'debit', 0, 'credit', v_ssnit, 'description', 'SSNIT withheld — ' || v_period
    );
  end if;
  if v_ssnit_employer > 0 then
    v_lines := v_lines
      || jsonb_build_object(
        'account_id', public.account_id_by_code('5145'),
        'debit', v_ssnit_employer, 'credit', 0,
        'description', 'Employer SSNIT contribution — ' || v_period
      )
      || jsonb_build_object(
        'account_id', public.account_id_by_code('2310'),
        'debit', 0, 'credit', v_ssnit_employer,
        'description', 'Employer SSNIT contribution — ' || v_period
      );
  end if;
  if v_tier2 > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2320'),
      'debit', 0, 'credit', v_tier2, 'description', 'Tier 2 withheld — ' || v_period
    );
  end if;
  if v_paye > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2330'),
      'debit', 0, 'credit', v_paye, 'description', 'PAYE withheld — ' || v_period
    );
  end if;
  if v_overtime_tax > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2330'),
      'debit', 0, 'credit', v_overtime_tax, 'description', 'Overtime tax withheld — ' || v_period
    );
  end if;
  if v_iou > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('1350'),
      'debit', 0, 'credit', v_iou, 'description', 'Staff advance recovery — ' || v_period
    );
  end if;
  if v_fines > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('4910'),
      'debit', 0, 'credit', v_fines, 'description', 'Staff fines recovered — ' || v_period
    );
  end if;

  v_entry := public._post_journal_entry_rows(
    v_run.branch_id,
    v_entry_date,
    'Payroll — ' || v_period,
    p_run_id::text,
    v_lines,
    'payroll_runs',
    p_run_id::text
  );

  update public.payroll_runs
  set status = 'Posted', posted_at = now(),
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_run_id;

  return v_entry;
end;
$$;
