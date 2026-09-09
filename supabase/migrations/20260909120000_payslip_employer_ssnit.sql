-- Employer SSNIT contribution (TCS ERP — closes the go-live-checklist gap).
--
-- Until now create_payslip() computed only the employee side of SSNIT
-- (0.5%). The employer's 13% was never computed, stored, or posted, so the
-- P&L understated staffing cost and 2310 SSNIT Payable was understated.
-- This migration:
--   1. adds payslips.ssnit_employer — a plain snapshot column (NOT a
--      Postgres generated column: it's derived from statutory_rates, which
--      a generated column can't read), filled once by create_payslip() at
--      generation time and never recomputed, same discipline as ssnit /
--      tax / tier2;
--   2. adds account 5145 Employer SSNIT Contribution (Expenses) — kept
--      separate from 5140 Salaries & Wages Expense so "true staff cost =
--      5140 + 5145" stays visible, the same split-for-visibility the chart
--      already uses (5000 vs 5210, 5120 vs 5130);
--   3. updates create_payslip() to compute and store it, gated on the same
--      pays_ssnit exemption flag as the employee side;
--   4. extends post_payroll_run() to post it: Dr 5145 / Cr 2310 for the
--      run's total employer contribution, on top of the existing
--      employee-side Cr 2310 — both portions owe to the same payable, from
--      opposite sides of the transaction.
--
-- Existing payslips keep ssnit_employer = 0 (the column default). Snapshot
-- discipline means they are NOT backfilled; regenerate a Draft-run payslip
-- if you want it to pick up the employer figure. Runs already Posted are
-- immutable and stay as posted.

alter table public.payslips
  add column ssnit_employer numeric(12, 2) not null default 0;

-- New expense account. accounts.created_by is nullable since
-- 20260819090000, so new chart rows go in the migration (idempotent), not
-- seed.sql (which never runs on a real deployment).
insert into public.accounts (code, name, category, subtype, description)
values
  ('5145', 'Employer SSNIT Contribution', 'Expenses', 'Operating Expense',
   'The employer''s 13% SSNIT contribution on staff basic salaries. Kept separate from 5140 Salaries & Wages Expense so total cost of employment (5140 + 5145) is visible on its own.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- create_payslip(): unchanged signature (plain create or replace, no
-- overload risk). Only change vs the 20260909090000 version: compute
-- v_ssnit_employer from v_rates.ssnit_employer_pct on the same pays_ssnit
-- condition as the employee side, and store it on the new column.
-- ---------------------------------------------------------------------
create or replace function public.create_payslip(
  p_payroll_run_id uuid,
  p_staff_id uuid,
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
  v_config public.staff_pay_config;
  v_rates public.statutory_rates;
  v_run_date date;
  v_overtime_pay numeric;
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
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  select * into v_run from public.payroll_runs where id = p_payroll_run_id;
  if v_run is null then
    raise exception 'Payroll run % not found', p_payroll_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Payroll run % is already posted and cannot take new payslips', v_run.id;
  end if;

  v_run_date := make_date(v_run.year, v_run.month, 1);

  -- Current pay config for this staff member as of the run's month.
  select * into v_config
  from public.staff_pay_config
  where staff_id = p_staff_id
    and effective_from <= v_run_date
    and (effective_to is null or effective_to >= v_run_date)
  order by effective_from desc
  limit 1;

  if v_config is null then
    raise exception 'No pay config found for staff % as of %', p_staff_id, v_run_date;
  end if;

  -- Latest statutory rates effective on/before the run date.
  select * into v_rates
  from public.statutory_rates
  where effective_from <= v_run_date
  order by effective_from desc
  limit 1;

  if v_rates is null then
    raise exception 'No statutory_rates configured effective on or before %', v_run_date;
  end if;

  v_overtime_pay := coalesce(p_overtime_hours, 0) * coalesce(p_overtime_rate, 0);

  -- Sum allowances, tracking taxable vs non-taxable separately.
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

  -- SSNIT (employee side) and Tier 2, on basic salary, only if this staff
  -- member actually participates (National Service etc. would have both
  -- flags false). The employer's SSNIT contribution rides the same
  -- pays_ssnit flag — an exempt staff member generates neither side.
  if v_config.pays_ssnit then
    v_ssnit := round(v_config.basic_salary * v_rates.ssnit_employee_pct / 100, 2);
    v_ssnit_employer := round(v_config.basic_salary * v_rates.ssnit_employer_pct / 100, 2);
  end if;
  if v_config.pays_tier2 then
    v_tier2 := round(v_config.basic_salary * v_rates.tier2_employee_pct / 100, 2);
  end if;

  -- Taxable income: basic + overtime + taxable allowances, minus the
  -- employee's SSNIT + Tier 2 (both pre-tax per standard treatment). The
  -- employer contribution never touches the employee, so it is NOT in this
  -- figure or in net pay.
  v_taxable_income := v_config.basic_salary + v_overtime_pay + v_total_taxable_allowances - v_ssnit - v_tier2;
  if v_taxable_income < 0 then
    v_taxable_income := 0;
  end if;

  -- Graduated PAYE, only if this staff member pays it. Bands are
  -- cumulative thresholds; each band's slice is taxed at its own rate.
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

  v_total_deductions := v_tax + v_tier2 + v_ssnit + coalesce(p_fines, 0) + coalesce(p_iou, 0);
  v_net_pay := v_gross_salary - v_total_deductions;

  insert into public.payslips (
    payroll_run_id, staff_id, staff_pay_config_id,
    basic_salary, overtime_hours, overtime_rate, overtime_pay,
    total_allowances, total_earning, gross_salary, taxable_income,
    tax, tier2, ssnit, ssnit_employer, fines, iou, total_deductions, net_pay
  ) values (
    p_payroll_run_id, p_staff_id, v_config.id,
    v_config.basic_salary, coalesce(p_overtime_hours, 0), coalesce(p_overtime_rate, 0), v_overtime_pay,
    v_total_allowances, v_total_earning, v_gross_salary, v_taxable_income,
    v_tax, v_tier2, v_ssnit, v_ssnit_employer, coalesce(p_fines, 0), coalesce(p_iou, 0), v_total_deductions, v_net_pay
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

-- ---------------------------------------------------------------------
-- post_payroll_run(): add the employer SSNIT contribution to the entry.
-- Only change vs the 20260909110000 version: sum ssnit_employer, and when
-- it's non-zero add
--   Dr 5145 Employer SSNIT Contribution   Σ ssnit_employer
--   Cr 2310 SSNIT Payable (employer)       Σ ssnit_employer
-- on top of the existing employee-side Cr 2310. This is a self-balancing
-- pair, so the entry stays balanced: Dr (gross + ssnit_employer) =
-- Cr (net + ssnit_emp + ssnit_er + tier2 + paye + iou + fines).
-- ---------------------------------------------------------------------
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
  v_fines numeric := 0;
  v_iou numeric := 0;
  v_net numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_entry public.journal_entries;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Payroll run % is already posted', p_run_id;
  end if;

  select
    count(*),
    coalesce(sum(gross_salary), 0),
    coalesce(sum(ssnit), 0),
    coalesce(sum(ssnit_employer), 0),
    coalesce(sum(tier2), 0),
    coalesce(sum(tax), 0),
    coalesce(sum(fines), 0),
    coalesce(sum(iou), 0),
    coalesce(sum(net_pay), 0)
  into v_count, v_gross, v_ssnit, v_ssnit_employer, v_tier2, v_paye, v_fines, v_iou, v_net
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
  set status = 'Posted', posted_at = now()
  where id = p_run_id;

  return v_entry;
end;
$$;
