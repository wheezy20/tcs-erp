-- Golden payslip suite (slice 0). Holds create_payslip(), post_payroll_run()
-- and the run-exclusion flow to hand-derived figures, against the REAL
-- statutory rows (statutory_rates, paye_bands, overtime_tax_rates). Every
-- probe runs in a rolled-back transaction through scripts/role-matrix.sh.
-- Run all tiers: ./scripts/golden-payslips.sh
-- (after npx supabase db reset and ./scripts/seed-local-dev-staff.sh)
--
-- Rules:
--   * A red case is never fixed by editing its expected figure. Expected
--     figures change only through a confirmation gate (CLAUDE.md).
--   * A rate change adds new cases for the new effective date; the cases
--     here keep passing for their own months.
--   * Every payslip probe expects Manager,Accountant: create_payslip() is
--     gated by require_finance_writer(), so the other four roles are denied
--     by design, and the figures are only checked for the two that pass. A
--     wrong figure turns those two cells into "denied!", with ONE line
--     naming every field as exp=/got=, and <<WRONG on each wrong one.
--
-- Months: AUG = August 2026 (2025-01-01 band set, no overtime row),
-- SEP = September 2026 (2026-09-01 bands, no overtime row),
-- OCT = October 2026 (2026 bands and the 2026-10-01 overtime row).
-- Rates: SSNIT employee 0.5%, Tier 2 employee 5%, employer SSNIT 13%,
-- employer Tier 2 0, all on basic salary only; accountant confirmed (reported, written copy to be saved).
-- Gross = basic + overtime + all allowances. Deductions = PAYE + overtime
-- tax + SSNIT + Tier 2 + fines + IOU. Net = gross - deductions.
--
-- Fixtures are invented (90d0... ids); seeded data is not touched.
-- Status of each value: see each section header. The 2026-09-01 bands are
-- what applies to the first real payroll.


-- ==========================================================================
-- G0. Rate data pinned
-- If this fails, the statutory data itself changed: every figure below
-- needs review through a confirmation gate. It checks the sets by
-- effective date, so a later set added alongside doesn't break it.

-- probe: G0 rate data pinned
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create temp table golden_rates as select
  (select concat_ws(':', ssnit_employee_pct, ssnit_employer_pct, tier2_employee_pct, tier2_employer_pct)
     from public.statutory_rates where effective_from = date '2025-01-01') as rates,
  (select string_agg(concat_ws(':', lower_bound, upper_bound, rate), ' ' order by band_order)
     from public.paye_bands where effective_from = date '2025-01-01') as bands_2025,
  (select string_agg(concat_ws(':', lower_bound, upper_bound, rate), ' ' order by band_order)
     from public.paye_bands where effective_from = date '2026-09-01') as bands_2026,
  (select concat_ws(':', qualifying_annual_basic_max, overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
     from public.overtime_tax_rates where effective_from = date '2026-10-01') as overtime,
  (select count(*) from public.statutory_rates where effective_from > date '2025-01-01'
     and effective_from <= date '2026-10-01') as rates_between,
  (select count(*) from public.paye_bands where effective_from not in (date '2025-01-01', date '2026-09-01')
     and effective_from <= date '2026-10-01') as bands_between,
  (select count(*) from public.overtime_tax_rates where effective_from <= date '2026-10-01'
     and effective_from <> date '2026-10-01') as overtime_between;
grant select on golden_rates to anon, authenticated;
-- as role:
do $$
declare g golden_rates;
begin
  select * into g from golden_rates;
  if g.rates is distinct from '0.500:13.000:5.000:0.000'
     or g.bands_2025 is distinct from '0.00:490.00:0.000 490.00:600.00:5.000 600.00:730.00:10.000 730.00:3896.67:17.500 3896.67:19896.67:25.000 19896.67:50000.00:30.000 50000.00:35.000'
     or g.bands_2026 is distinct from '0.00:588.00:0.000 588.00:668.00:5.000 668.00:768.00:10.000 768.00:3668.00:17.500 3668.00:19668.00:25.000 19668.00:50000.00:30.000 50000.00:35.000'
     or g.overtime is distinct from '18000.00:50.00:5.000:10.000'
     or g.rates_between <> 0 or g.bands_between <> 0 or g.overtime_between <> 0 then
    raise exception 'G0: rate data changed, golden figures need review: rates=% bands_2025=% bands_2026=% overtime=% other rows effective by 2026-10-01: rates %, bands %, overtime %',
      g.rates, g.bands_2025, g.bands_2026, g.overtime, g.rates_between, g.bands_between, g.overtime_between;
  end if;
end $$;


-- ==========================================================================
-- S26. 2026-09-01 band set, September 2026 (statutory-derived)
-- Bands confirmed by Eyram 2026-09-29 against GRA. PAYE-only fixture
-- (pays_ssnit and pays_tier2 false) so taxable = basic and each band
-- edge is exact. Cumulative PAYE: 588 -> 0; 668 -> 80 x 5% = 4.00;
-- 768 -> 4 + 100 x 10% = 14.00; 3,668 -> 14 + 2,900 x 17.5% = 521.50;
-- 19,668 -> 521.50 + 16,000 x 25% = 4,521.50; 50,000 -> 4,521.50 +
-- 30,332 x 30% = 13,621.10; 60,000 -> 13,621.10 + 10,000 x 35% = 17,121.10.

-- probe: S26-1 PAYE-only, basic 588
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 588, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-1',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "588.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "588.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "0.00", "net_pay": "588.00"}');

-- probe: S26-2 PAYE-only, basic 668
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 668, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-2',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "668.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "668.00", "tax": "4.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "4.00", "net_pay": "664.00"}');

-- probe: S26-3 PAYE-only, basic 768
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-3', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 768, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-3',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "768.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "768.00", "tax": "14.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "14.00", "net_pay": "754.00"}');

-- probe: S26-4 PAYE-only, basic 3668
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3668, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-4',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "3668.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "3668.00", "tax": "521.50", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "521.50", "net_pay": "3146.50"}');

-- probe: S26-5 PAYE-only, basic 19668
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-5', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 19668, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-5',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "19668.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "19668.00", "tax": "4521.50", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "4521.50", "net_pay": "15146.50"}');

-- probe: S26-6 PAYE-only, basic 50000
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-6', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 50000, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-6',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "50000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "50000.00", "tax": "13621.10", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "13621.10", "net_pay": "36378.90"}');

-- probe: S26-7 PAYE-only, basic 60000
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-7', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 60000, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-7',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "60000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "60000.00", "tax": "17121.10", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "17121.10", "net_pay": "42878.90"}');

-- Taxable = 3,000 + 833 - 15 - 150 = 3,668.00, PAYE 521.50.
-- probe: S26-4b edge 3,668 via taxable allowance
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-4b', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-4b',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 833}]'::jsonb, 0, 0)),
  '{"gross_salary": "3833.00", "total_allowances": "833.00", "overtime_pay": "0.00", "taxable_income": "3668.00", "tax": "521.50", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.00", "tier2": "150.00", "ssnit_employer": "390.00", "fines": "0.00", "iou": "0.00", "total_deductions": "686.50", "net_pay": "3146.50"}');

-- Band set picked by month: 4 + 10 + 232 x 17.5% (40.60) = 54.60.
-- probe: S26-SEL PAYE-only, basic 1,000 (Sep: 2026 set)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-SEL', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1000, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-SEL',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "1000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "1000.00", "tax": "54.60", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "54.60", "net_pay": "945.40"}');

-- Taxable 2,000 - 10 - 100 = 1,890; PAYE 4 + 10 + 1,122 x 17.5% (196.35) = 210.35.
-- probe: S26-H basic 2,000, all deductions
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-H', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-H',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "2000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "1890.00", "tax": "210.35", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "10.00", "tier2": "100.00", "ssnit_employer": "260.00", "fines": "0.00", "iou": "0.00", "total_deductions": "320.35", "net_pay": "1679.65"}');

-- Taxable 3,100 + 500 - 15.50 - 155 = 3,429.50; PAYE 14 + 2,661.50 x 17.5%
-- (465.7625 -> 465.76) = 479.76. All allowances are taxable until the
-- accountant names an exemption (GRA policy).
-- probe: S26-ALW-T basic 3,100 + taxable allowance 500
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-ALW-T', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-ALW-T',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 500}]'::jsonb, 0, 0)),
  '{"gross_salary": "3600.00", "total_allowances": "500.00", "overtime_pay": "0.00", "taxable_income": "3429.50", "tax": "479.76", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "650.26", "net_pay": "2949.74"}');

-- National Service: pays_ssnit, pays_tier2 and pays_paye all false (decided
-- 2026-09-29). No deduction of any kind, no employer SSNIT. taxable_income is
-- NOT asserted: what a payslip shows as taxable income with no PAYE charged
-- is pending (see Q-NSS-ALW).
-- probe: S26-NSS National Service, basic 1,500
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-NSS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1500, date '2026-01-01', false, false, false);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-NSS',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "1500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "0.00", "net_pay": "1500.00"}');

-- taxable_income is NOT asserted: a payslip showing taxable income with no
-- PAYE charged is pending (see Q-NSS-ALW).
-- probe: S26-EXO PAYE-exempt only, basic 6,500
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-EXO', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 6500, date '2026-01-01', true, true, false);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-EXO',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "6500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "32.50", "tier2": "325.00", "ssnit_employer": "845.00", "fines": "0.00", "iou": "0.00", "total_deductions": "357.50", "net_pay": "6142.50"}');


-- ==========================================================================
-- S26-HI. High earners (statutory-derived)
-- No SSNIT contribution ceiling: no ceiling known to the accountant
-- (accountant confirmed (reported, written copy to be saved)).

-- Taxable 25,000 - 125 - 1,250 = 23,625; PAYE 4,521.50 + 3,957 x 30% (1,187.10) = 5,708.60.
-- probe: S26-HI25 basic 25,000 (30% band)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-HI25', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 25000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-HI25',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "25000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "23625.00", "tax": "5708.60", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "125.00", "tier2": "1250.00", "ssnit_employer": "3250.00", "fines": "0.00", "iou": "0.00", "total_deductions": "7083.60", "net_pay": "17916.40"}');

-- Taxable 60,000 - 300 - 3,000 = 56,700; PAYE 13,621.10 + 6,700 x 35% (2,345.00) = 15,966.10.
-- probe: S26-HI60 basic 60,000 (35% band)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-HI60', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 60000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-HI60',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "60000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "56700.00", "tax": "15966.10", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "300.00", "tier2": "3000.00", "ssnit_employer": "7800.00", "fines": "0.00", "iou": "0.00", "total_deductions": "19266.10", "net_pay": "40733.90"}');


-- ==========================================================================
-- S26-D. Fines, IOU and rounding
-- accountant confirmed (reported, written copy to be saved): fines and IOU repayments come off after tax and do
-- not reduce taxable income; no cap on total deductions. A PAYE amount of
-- exactly half a pesewa rounds up. Base: basic 3,100 -> SSNIT 15.50,
-- Tier 2 155.00, taxable 2,929.50, PAYE 14 + 2,161.50 x 17.5%
-- (378.2625 -> 378.26) = 392.26.

-- probe: S26-FINE basic 3,100, fines 100
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-FINE', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-FINE',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 100, 0)),
  '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "100.00", "iou": "0.00", "total_deductions": "662.76", "net_pay": "2437.24"}');

-- probe: S26-IOU basic 3,100, IOU 250
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-IOU', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-IOU',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 250)),
  '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "250.00", "total_deductions": "812.76", "net_pay": "2287.24"}');

-- probe: S26-FINE-IOU basic 3,100, fines 100 + IOU 250
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-FINE-IOU', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-FINE-IOU',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 100, 250)),
  '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "100.00", "iou": "250.00", "total_deductions": "912.76", "net_pay": "2187.24"}');

-- Taxable 3,000 + 500 - 15 - 150 = 3,335; band 4 = 2,567 x 17.5% = 449.225,
-- a tie, rounds up to 449.23; PAYE 14 + 449.23 = 463.23.
-- probe: S26-TIE half-pesewa PAYE rounds up
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S26-TIE', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S26-TIE',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 500}]'::jsonb, 0, 0)),
  '{"gross_salary": "3500.00", "total_allowances": "500.00", "overtime_pay": "0.00", "taxable_income": "3335.00", "tax": "463.23", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.00", "tier2": "150.00", "ssnit_employer": "390.00", "fines": "0.00", "iou": "0.00", "total_deductions": "628.23", "net_pay": "2871.77"}');


-- ==========================================================================
-- S25. 2025-01-01 band set: current behaviour, not confirmed correct, August 2026
-- The accountant said only that the new (2026) bands apply from now.
-- These cases pin the engine's current behaviour for months before
-- September 2026. Cumulative PAYE: 490 -> 0; 600 -> 110 x 5% = 5.50;
-- 730 -> 5.50 + 130 x 10% = 18.50; 3,896.67 -> 18.50 + 3,166.67 x 17.5%
-- (554.16725 -> 554.17) = 572.67; 19,896.67 -> + 16,000 x 25% = 4,572.67;
-- 50,000 -> + 30,103.33 x 30% (9,030.999 -> 9,031.00) = 13,603.67;
-- 60,000 -> + 10,000 x 35% = 17,103.67.

-- probe: S25-1 PAYE-only, basic 490
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 490, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-1',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "490.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "490.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "0.00", "net_pay": "490.00"}');

-- probe: S25-2 PAYE-only, basic 600
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 600, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-2',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "600.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "600.00", "tax": "5.50", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "5.50", "net_pay": "594.50"}');

-- probe: S25-3 PAYE-only, basic 730
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-3', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 730, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-3',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "730.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "730.00", "tax": "18.50", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "18.50", "net_pay": "711.50"}');

-- probe: S25-4 PAYE-only, basic 3896.67
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3896.67, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-4',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "3896.67", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "3896.67", "tax": "572.67", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "572.67", "net_pay": "3324.00"}');

-- probe: S25-5 PAYE-only, basic 19896.67
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-5', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 19896.67, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-5',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "19896.67", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "19896.67", "tax": "4572.67", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "4572.67", "net_pay": "15324.00"}');

-- probe: S25-6 PAYE-only, basic 50000
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-6', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 50000, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-6',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "50000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "50000.00", "tax": "13603.67", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "13603.67", "net_pay": "36396.33"}');

-- probe: S25-7 PAYE-only, basic 60000
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-7', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 60000, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-7',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "60000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "60000.00", "tax": "17103.67", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "17103.67", "net_pay": "42896.33"}');

-- probe: S25-4b edge 3,896.67 via taxable allowance
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-4b', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-4b',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 1061.67}]'::jsonb, 0, 0)),
  '{"gross_salary": "4061.67", "total_allowances": "1061.67", "overtime_pay": "0.00", "taxable_income": "3896.67", "tax": "572.67", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.00", "tier2": "150.00", "ssnit_employer": "390.00", "fines": "0.00", "iou": "0.00", "total_deductions": "737.67", "net_pay": "3324.00"}');

-- 5.50 + 13.00 + 270 x 17.5% (47.25) = 65.75 (54.60 under the 2026 set).
-- probe: S25-SEL PAYE-only, basic 1,000 (Aug: 2025 set)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-SEL', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1000, date '2026-01-01', false, false, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-SEL',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "1000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "1000.00", "tax": "65.75", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "65.75", "net_pay": "934.25"}');

-- PAYE 5.50 + 13.00 + 1,160 x 17.5% (203.00) = 221.50.
-- probe: S25-H basic 2,000, all deductions
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN S25-H', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'S25-H',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "2000.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "1890.00", "tax": "221.50", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "10.00", "tier2": "100.00", "ssnit_employer": "260.00", "fines": "0.00", "iou": "0.00", "total_deductions": "331.50", "net_pay": "1668.50"}');


-- ==========================================================================
-- E. Overtime, October 2026 (Eyram-given figures)
-- Overtime concession (2026-10-01 row: basic x 12 at most 18,000; 5% up to
-- 50% of basic, 10% above; out of the PAYE base; worked from the overtime
-- as shown on the payslip). Normal PAYE rates for non-qualifying staff:
-- accountant confirmed (reported, written copy to be saved).

-- Taxable 1,200 - 6 - 60 = 1,134 (overtime excluded); PAYE 4 + 10 + 366 x 17.5%
-- (64.05) = 78.05; OT tax 400 x 5% = 20.00 (cap 600).
-- probe: E-A qualifying: basic 1,200, OT 4 x 100
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN E-A', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'E-A',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "1600.00", "total_allowances": "0.00", "overtime_pay": "400.00", "taxable_income": "1134.00", "tax": "78.05", "overtime_tax": "20.00", "overtime_concession": true, "ssnit": "6.00", "tier2": "60.00", "ssnit_employer": "156.00", "fines": "0.00", "iou": "0.00", "total_deductions": "164.05", "net_pay": "1435.95"}');

-- OT tax 600 x 5% + 200 x 10% = 30.00 + 20.00 = 50.00.
-- probe: E-B larger: basic 1,200, OT 8 x 100
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN E-B', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'E-B',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 8, 100, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "2000.00", "total_allowances": "0.00", "overtime_pay": "800.00", "taxable_income": "1134.00", "tax": "78.05", "overtime_tax": "50.00", "overtime_concession": true, "ssnit": "6.00", "tier2": "60.00", "ssnit_employer": "156.00", "fines": "0.00", "iou": "0.00", "total_deductions": "194.05", "net_pay": "1805.95"}');

-- 22,800 > 18,000. Taxable 1,900 + 400 - 9.50 - 95 = 2,195.50; PAYE 14 +
-- 1,427.50 x 17.5% (249.8125 -> 249.81) = 263.81.
-- probe: E-C non-qualifying: basic 1,900, OT 4 x 100
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN E-C', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'E-C',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "2300.00", "total_allowances": "0.00", "overtime_pay": "400.00", "taxable_income": "2195.50", "tax": "263.81", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "9.50", "tier2": "95.00", "ssnit_employer": "247.00", "fines": "0.00", "iou": "0.00", "total_deductions": "368.31", "net_pay": "1931.69"}');

-- Shown as 141.30; OT tax 141.30 x 5% = 7.065 -> 7.07 (7.06 from the unrounded).
-- probe: E-M rounding: OT 3.5 x 40.37 = 141.295
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN E-M', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'E-M',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 3.5, 40.37, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "1341.30", "total_allowances": "0.00", "overtime_pay": "141.30", "taxable_income": "1134.00", "tax": "78.05", "overtime_tax": "7.07", "overtime_concession": true, "ssnit": "6.00", "tier2": "60.00", "ssnit_employer": "156.00", "fines": "0.00", "iou": "0.00", "total_deductions": "151.12", "net_pay": "1190.18"}');


-- ==========================================================================
-- E-R. Non-qualifying overtime at the printed figure: accountant confirmed (reported, written copy to be saved)
-- For staff outside the concession, overtime enters the PAYE base at the
-- amount printed on the payslip, round(hours x rate, 2), not the exact
-- product. Both cases land on a half pesewa that changes PAYE.

-- Taxable 1,900 + 100.13 - 9.50 - 95 = 1,895.63; PAYE 4 + 10 + 1,127.63 x 17.5%
-- (197.33525 -> 197.34) = 211.34 (211.33 from the unrounded 100.125).
-- probe: E-R1 non-qualifying OT 2.5 x 40.05 = 100.125 -> 100.13 (was Q-OT-UNR)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN E-R1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'E-R1',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 2.5, 40.05, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "2000.13", "total_allowances": "0.00", "overtime_pay": "100.13", "taxable_income": "1895.63", "tax": "211.34", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "9.50", "tier2": "95.00", "ssnit_employer": "247.00", "fines": "0.00", "iou": "0.00", "total_deductions": "315.84", "net_pay": "1684.29"}');

-- 4,500 x 12 = 54,000 > 18,000: no concession. Taxable 4,500 + 30.08 - 22.50 -
-- 225 = 4,282.58; PAYE 4 + 10 + 507.50 + 614.58 x 25% (153.645 -> 153.65) =
-- 675.15 (675.14 from the unrounded 30.075).
-- probe: E-R2 non-qualifying OT 1.5 x 20.05 = 30.075 -> 30.08, Oct (row exists)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN E-R2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 4500, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'E-R2',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 1.5, 20.05, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "4530.08", "total_allowances": "0.00", "overtime_pay": "30.08", "taxable_income": "4282.58", "tax": "675.15", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "22.50", "tier2": "225.00", "ssnit_employer": "585.00", "fines": "0.00", "iou": "0.00", "total_deductions": "922.65", "net_pay": "3607.43"}');


-- ==========================================================================
-- P. TCS OS parity (ERP-confirmed)
-- The parity FIGURE is confirmed; the 2025 band set it runs under is not
-- (current behaviour, see S25).
-- Emmanuel Ansah, basic 6,500, net 5,008.37: the TCS OS payroll parity
-- figure (docs/CONSTRAINTS.md). It holds under the 2025 set only, so it
-- runs in August 2026 (2025-01-01 band set: current behaviour, not confirmed correct).

-- PAYE 5.50 + 13.00 + 554.17 + 2,245.83 x 25% (561.4575 -> 561.46) = 1,134.13.
-- probe: P-EMM25 Emmanuel, basic 6,500, Aug 2026
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN P-EMM25', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 6500, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 8, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'P-EMM25',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "6500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "6142.50", "tax": "1134.13", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "32.50", "tier2": "325.00", "ssnit_employer": "845.00", "fines": "0.00", "iou": "0.00", "total_deductions": "1491.63", "net_pay": "5008.37"}');

-- Derived under the 2026 set, not a parity figure: 4 + 10 + 507.50 +
-- 2,474.50 x 25% (618.625 -> 618.63) = 1,140.13.
-- probe: P-EMM26 same, Sep 2026 (derived, not parity)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN P-EMM26', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 6500, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'P-EMM26',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "6500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "6142.50", "tax": "1140.13", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "32.50", "tier2": "325.00", "ssnit_employer": "845.00", "fines": "0.00", "iou": "0.00", "total_deductions": "1497.63", "net_pay": "5002.37"}');


-- ==========================================================================
-- X. Runs: exclusion, review and posting (statutory-derived)
-- Setup makes only the fixture employees Active (rolled back), generates the
-- payslips as the dev Manager and submits the run. post_payroll_run() is
-- Manager-only. The overtime-tax credit to 2330 appears only when the run
-- has overtime tax.

-- GA-X1 working: A (basic 1,200, OT 4 x 100) + C (basic 1,900, OT 4 x 100);
-- X (basic 2,000) excluded. Gross 1,600 + 2,300 = 3,900; net 1,435.95 +
-- 1,931.69 = 3,367.64; SSNIT 6 + 9.50 = 15.50; employer 156 + 247 = 403;
-- Tier 2 60 + 95 = 155; PAYE 78.05 + 263.81 = 341.86; OT tax 20.00.
-- Debits 3,900 + 403 = 4,303.00 = credits. Entry dated 2026-10-31.
-- probe: GA-X1 Oct run, one excluded, posted
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN X1 A', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'GOLDEN X1 C', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000002', 1900, date '2026-01-01', true, true, true);
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'GOLDEN X1 X (excluded)', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000003', 2000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
update public.employees set employment_status = 'Suspended'
where employment_status = 'Active' and id not in ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-000000000002', '90d00000-0000-0000-0000-000000000003');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 4, 100);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000002', 4, 100);
select 1 from public.exclude_employee_from_run('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000003', 'golden exclusion');
select 1 from public.submit_payroll_run_for_review('90d00000-0000-0000-0000-0000000000a1');
create function pg_temp.golden_check_lines(p_case text, p_entry text, p_exp text) returns void
language plpgsql as $f$
declare v_got text; v_dr numeric; v_cr numeric;
begin
  select string_agg(concat_ws(':', a.code, l.debit, l.credit, l.description), ' | ' order by l.position),
         sum(l.debit), sum(l.credit)
    into v_got, v_dr, v_cr
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  where l.entry_id = p_entry;
  if v_got is distinct from p_exp or v_dr <> v_cr then
    raise exception '%: lines exp=[%] got=[%] debits=% credits=%', p_case, p_exp, v_got, v_dr, v_cr;
  end if;
end $f$;
-- as role:
do $$
declare v_entry public.journal_entries; n int; x int;
begin
  v_entry := public.post_payroll_run('90d00000-0000-0000-0000-0000000000a1');
  select count(*), count(*) filter (where employee_id = '90d00000-0000-0000-0000-000000000003') into n, x
    from public.payslips where payroll_run_id = '90d00000-0000-0000-0000-0000000000a1';
  if n <> 2 or x <> 0 or v_entry.entry_date <> date '2026-10-31' then
    raise exception 'GA-X1: payslips exp=2 got=%; excluded employee payslips exp=0 got=%; entry date exp=2026-10-31 got=%', n, x, v_entry.entry_date;
  end if;
  perform pg_temp.golden_check_lines('GA-X1', v_entry.id,
    '5140:3900.00:0.00:Gross pay — October 2026 | 2300:0.00:3367.64:Net pay payable — October 2026 | 2310:0.00:15.50:SSNIT withheld — October 2026 | 5145:403.00:0.00:Employer SSNIT contribution — October 2026 | 2310:0.00:403.00:Employer SSNIT contribution — October 2026 | 2320:0.00:155.00:Tier 2 withheld — October 2026 | 2330:0.00:341.86:PAYE withheld — October 2026 | 2330:0.00:20.00:Overtime tax withheld — October 2026');
end $$;

-- GA-X2 working: one employee, basic 2,000 (as S26-H), no overtime: no
-- overtime-tax line. Debits 2,000 + 260 = 2,260.00 = credits.
-- probe: GA-X2 Sep run, no OT tax line
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN X2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
update public.employees set employment_status = 'Suspended'
where employment_status = 'Active' and id not in ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-000000000002', '90d00000-0000-0000-0000-000000000003');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001');
select 1 from public.submit_payroll_run_for_review('90d00000-0000-0000-0000-0000000000a1');
create function pg_temp.golden_check_lines(p_case text, p_entry text, p_exp text) returns void
language plpgsql as $f$
declare v_got text; v_dr numeric; v_cr numeric;
begin
  select string_agg(concat_ws(':', a.code, l.debit, l.credit, l.description), ' | ' order by l.position),
         sum(l.debit), sum(l.credit)
    into v_got, v_dr, v_cr
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  where l.entry_id = p_entry;
  if v_got is distinct from p_exp or v_dr <> v_cr then
    raise exception '%: lines exp=[%] got=[%] debits=% credits=%', p_case, p_exp, v_got, v_dr, v_cr;
  end if;
end $f$;
-- as role:
do $$
declare v_entry public.journal_entries;
begin
  v_entry := public.post_payroll_run('90d00000-0000-0000-0000-0000000000a1');
  perform pg_temp.golden_check_lines('GA-X2', v_entry.id,
    '5140:2000.00:0.00:Gross pay — September 2026 | 2300:0.00:1679.65:Net pay payable — September 2026 | 2310:0.00:10.00:SSNIT withheld — September 2026 | 5145:260.00:0.00:Employer SSNIT contribution — September 2026 | 2310:0.00:260.00:Employer SSNIT contribution — September 2026 | 2320:0.00:100.00:Tier 2 withheld — September 2026 | 2330:0.00:210.35:PAYE withheld — September 2026');
end $$;

-- GA-X3: an Active, configured employee with neither a payslip nor an
-- exclusion blocks submission. Passes only if the refusal is that one;
-- the four roles without finance access fail on their role guard instead.
-- probe: GA-X3 unaccounted employee blocks submit
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN X3 paid', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'GOLDEN X3 unaccounted', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000002', 2000, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
update public.employees set employment_status = 'Suspended'
where employment_status = 'Active' and id not in ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-000000000002', '90d00000-0000-0000-0000-000000000003');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001');
-- as role:
do $$
begin
  begin
    perform public.submit_payroll_run_for_review('90d00000-0000-0000-0000-0000000000a1');
  exception when others then
    if sqlerrm like 'These active employees have neither a payslip nor an exclusion%' then
      return;
    end if;
    raise;
  end;
  raise exception 'GA-X3: submit accepted a run with an unaccounted active employee';
end $$;


-- ==========================================================================
-- V. Input precision: more than 2 dp refused (Eyram's owner decision 2026-10-07: refuse, do not round)
-- Money and hours inputs with more than 2 decimal places are refused by the
-- database, with the message the form shows; nothing is rounded silently.
-- One refusal per field and per write path; a refusal case passes only on
-- that exact message (roles without access fail on their usual guard).
-- Then 2 dp inputs still work, and are stored at scale 2.

-- probe: V-SAL-1 basic salary 1500.005 via propose_employee
-- expect: Manager,Accountant
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-SAL-1',
  $q$select public.propose_employee('GOLDEN V-SAL-1', '00000000-0000-0000-0000-000000000001', p_basic_salary => 1500.005)$q$,
  'Basic salary must have at most 2 decimal places (got 1500.005)');

-- probe: V-SAL-2 basic salary 2000.125 via propose_pay_config_change
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-SAL-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-SAL-2',
  $q$select public.propose_pay_config_change('90d00000-0000-0000-0000-000000000001', date '2026-11-01', 2000.125, null, null, true, true, true)$q$,
  'Basic salary must have at most 2 decimal places (got 2000.125)');

-- probe: V-SAL-3 basic salary 2000.125 via approve_employee
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-SAL-3', 'Pending Approval');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye, approval_status)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true, 'Pending Approval');
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-SAL-3',
  $q$select public.approve_employee('90d00000-0000-0000-0000-000000000001', 2000.125)$q$,
  'Basic salary must have at most 2 decimal places (got 2000.125)');

-- probe: V-SAL-4 basic salary 2100.125 via approve_pay_config
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-SAL-4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.employee_pay_config (id, employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye, approval_status)
values ('90d00000-0000-0000-0000-0000000000c1', '90d00000-0000-0000-0000-000000000001', 2100, date '2026-11-01', true, true, true, 'Pending Approval');
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-SAL-4',
  $q$select public.approve_pay_config('90d00000-0000-0000-0000-0000000000c1', 2100.125)$q$,
  'Basic salary must have at most 2 decimal places (got 2100.125)');

-- V-ALW-1: the trigger runs before row-level security, so every signed-in role
-- gets the decimal message on a 3 dp insert; RLS still refuses a valid 2 dp
-- insert by Attendant, Auditor and Admissions Officer (V-OK-3). anon has no grant.
-- probe: V-ALW-1 standing allowance 100.125, direct insert
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-ALW-1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-ALW-1',
  $q$insert into public.employee_allowances (employee_id, allowance_type_id, default_amount, effective_from) values ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000b1', 100.125, date '2026-01-01')$q$,
  'Allowance amount must have at most 2 decimal places (got 100.125)');

-- V-ALW-2: for roles without write access, RLS makes the update match no row,
-- so nothing changes; they show as denied ("accepted") here.
-- probe: V-ALW-2 standing allowance updated to 100.125
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-ALW-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
insert into public.employee_allowances (id, employee_id, allowance_type_id, default_amount, effective_from)
values ('90d00000-0000-0000-0000-0000000000d1', '90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000b1', 100, date '2026-01-01');
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-ALW-2',
  $q$update public.employee_allowances set default_amount = 100.125 where id = '90d00000-0000-0000-0000-0000000000d1'$q$,
  'Allowance amount must have at most 2 decimal places (got 100.125)');

-- probe: V-PS-1 overtime hours 2.555
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-1',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 2.555, 40, '[]'::jsonb, 0, 0)$q$,
  'Overtime hours must have at most 2 decimal places (got 2.555)');

-- probe: V-PS-2 overtime rate 40.005
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-2',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 2, 40.005, '[]'::jsonb, 0, 0)$q$,
  'Overtime rate must have at most 2 decimal places (got 40.005)');

-- probe: V-PS-3 payslip allowance 100.125
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-3',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 100.125}]'::jsonb, 0, 0)$q$,
  'Allowance amount must have at most 2 decimal places (got 100.125)');

-- probe: V-PS-4 fines 10.005
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-4',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 10.005, 0)$q$,
  'Fines must have at most 2 decimal places (got 10.005)');

-- probe: V-PS-5 IOU 20.255
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-5',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 20.255)$q$,
  'IOU must have at most 2 decimal places (got 20.255)');

-- probe: V-PS-6 fines 10.00001 (would round onto 10.00)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-6',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 10.00001, 0)$q$,
  'Fines must have at most 2 decimal places (got 10.00001)');

-- probe: V-PS-7 allowance as the string 1e-3
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-7',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": "1e-3"}]'::jsonb, 0, 0)$q$,
  'Allowance amount must have at most 2 decimal places (got 0.001)');

-- probe: V-PS-8 overtime hours NaN
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'V-PS-8',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 'NaN'::numeric, 40, '[]'::jsonb, 0, 0)$q$,
  'Overtime hours is not a valid amount (got NaN)');

-- Not qualifying (22,800 > 18,000). OT 50.0625 -> 50.06; gross 1,900 + 50.06 + 100.12 =
-- 2,050.18; taxable 2,050.18 - 9.50 - 95 = 1,945.68; PAYE 4 + 10 + 1,177.68 x 17.5%
-- (206.094 -> 206.09) = 220.09; deductions 220.09 + 9.50 + 95 + 10.05 + 20.25 = 354.89.
-- probe: V-OK-1 2 dp inputs: OT 1.25 x 40.05, allowance 100.12, fines 10.05, IOU 20.25
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-OK-1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'V-OK-1',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 1.25, 40.05, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 100.12}]'::jsonb, 10.05, 20.25)),
  '{"gross_salary": "2050.18", "total_allowances": "100.12", "overtime_pay": "50.06", "taxable_income": "1945.68", "tax": "220.09", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "9.50", "tier2": "95.00", "ssnit_employer": "247.00", "fines": "10.05", "iou": "20.25", "total_deductions": "354.89", "net_pay": "1695.29"}');

-- V-OK-2: basic salary 1500.25 and 1500 are accepted and stored as 1500.25 / 1500.00.
-- probe: V-OK-2 basic salary 2 dp accepted, stored at scale 2
-- expect: Manager,Accountant
-- as role:
do $$
declare a text; b text;
begin
  perform public.propose_employee('GOLDEN V-OK-2 A', '00000000-0000-0000-0000-000000000001', p_basic_salary => 1500.25);
  perform public.propose_employee('GOLDEN V-OK-2 B', '00000000-0000-0000-0000-000000000001', p_basic_salary => 1500);
  select c.basic_salary::text into a from public.employee_pay_config c
    join public.employees e on e.id = c.employee_id where e.name = 'GOLDEN V-OK-2 A';
  select c.basic_salary::text into b from public.employee_pay_config c
    join public.employees e on e.id = c.employee_id where e.name = 'GOLDEN V-OK-2 B';
  if a is distinct from '1500.25' or b is distinct from '1500.00' then
    raise exception 'V-OK-2: stored exp=1500.25 got=%; exp=1500.00 got=%', a, b;
  end if;
end $$;

-- V-OK-3: standing allowances 100.12 and 100 are accepted and stored as 100.12 / 100.00.
-- probe: V-OK-3 standing allowance 2 dp accepted, stored at scale 2
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-OK-3', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
-- as role:
do $$
declare a text; b text;
begin
  insert into public.employee_allowances (employee_id, allowance_type_id, default_amount, effective_from)
  values ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000b1', 100.12, date '2026-01-01'), ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000b2', 100, date '2026-01-01');
  select default_amount::text into a from public.employee_allowances where employee_id = '90d00000-0000-0000-0000-000000000001' and allowance_type_id = '90d00000-0000-0000-0000-0000000000b1';
  select default_amount::text into b from public.employee_allowances where employee_id = '90d00000-0000-0000-0000-000000000001' and allowance_type_id = '90d00000-0000-0000-0000-0000000000b2';
  if a is distinct from '100.12' or b is distinct from '100.00' then
    raise exception 'V-OK-3: stored exp=100.12 got=%; exp=100.00 got=%', a, b;
  end if;
end $$;


-- ==========================================================================
-- N. Negative inputs refused (Eyram's owner decision 2026-10-07: negative amounts and hours refused)
-- Negative amounts and hours are refused on all seven payroll inputs; zero is
-- still allowed, basic salary included (the schema has allowed a zero basic
-- salary since 20260908070000). The basic-salary RPCs refuse a negative
-- salary with their own existing messages before the trigger is reached.

-- probe: N-SAL-1 basic salary -100 via propose_employee
-- expect: Manager,Accountant
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-SAL-1',
  $q$select public.propose_employee('GOLDEN N-SAL-1', '00000000-0000-0000-0000-000000000001', p_basic_salary => -100)$q$,
  'Basic salary cannot be negative');

-- probe: N-SAL-2 basic salary -100 via propose_pay_config_change
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN N-SAL-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-SAL-2',
  $q$select public.propose_pay_config_change('90d00000-0000-0000-0000-000000000001', date '2026-11-01', -100, null, null, true, true, true)$q$,
  'Basic salary must be zero or more');

-- probe: N-SAL-3 basic salary -100 via approve_employee
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-SAL-3', 'Pending Approval');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye, approval_status)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true, 'Pending Approval');
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-SAL-3',
  $q$select public.approve_employee('90d00000-0000-0000-0000-000000000001', -100)$q$,
  'Basic salary cannot be negative');

-- probe: N-SAL-4 basic salary -100 via approve_pay_config
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN N-SAL-4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.employee_pay_config (id, employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye, approval_status)
values ('90d00000-0000-0000-0000-0000000000c1', '90d00000-0000-0000-0000-000000000001', 2100, date '2026-11-01', true, true, true, 'Pending Approval');
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-SAL-4',
  $q$select public.approve_pay_config('90d00000-0000-0000-0000-0000000000c1', -100)$q$,
  'Basic salary cannot be negative');

-- N-ALW-1: as V-ALW-1, the trigger runs before row-level security, so every
-- signed-in role gets the message; nothing is written. anon has no grant.
-- probe: N-ALW-1 standing allowance -50, direct insert
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN N-ALW-1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-ALW-1',
  $q$insert into public.employee_allowances (employee_id, allowance_type_id, default_amount, effective_from) values ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000b1', -50, date '2026-01-01')$q$,
  'Allowance amount cannot be negative (got -50)');

-- N-ALW-2: as V-ALW-2, other roles' update matches no row under RLS.
-- probe: N-ALW-2 standing allowance updated to -50
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN N-ALW-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 2000, date '2026-01-01', true, true, true);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
insert into public.employee_allowances (id, employee_id, allowance_type_id, default_amount, effective_from)
values ('90d00000-0000-0000-0000-0000000000d1', '90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000b1', 100, date '2026-01-01');
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-ALW-2',
  $q$update public.employee_allowances set default_amount = -50 where id = '90d00000-0000-0000-0000-0000000000d1'$q$,
  'Allowance amount cannot be negative (got -50)');

-- probe: N-PS-1 overtime hours -2
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-PS-1',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', -2, 40, '[]'::jsonb, 0, 0)$q$,
  'Overtime hours cannot be negative (got -2)');

-- probe: N-PS-2 overtime rate -40
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-PS-2',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 2, -40, '[]'::jsonb, 0, 0)$q$,
  'Overtime rate cannot be negative (got -40)');

-- probe: N-PS-3 payslip allowance -100
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-PS-3',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": -100}]'::jsonb, 0, 0)$q$,
  'Allowance amount cannot be negative (got -100)');

-- probe: N-PS-4 fines -10
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-PS-4',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, -10, 0)$q$,
  'Fines cannot be negative (got -10)');

-- probe: N-PS-5 IOU -20
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-PS-5',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, -20)$q$,
  'IOU cannot be negative (got -20)');

-- probe: N-PS-6 fines -0.01 (smallest negative)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN V-PS', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_refused(p_case text, p_sql text, p_msg text) returns void
language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_msg then
      return;
    end if;
    raise;
  end;
  raise exception '%: accepted, expected refusal: %', p_case, p_msg;
end $f$;
-- as role:
select pg_temp.golden_refused(
  'N-PS-6',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, -0.01, 0)$q$,
  'Fines cannot be negative (got -0.01)');

-- N-OK-1: basic salary 0 is accepted and stored as 0.00.
-- probe: N-OK-1 basic salary zero accepted
-- expect: Manager,Accountant
-- as role:
do $$
declare a text;
begin
  perform public.propose_employee('GOLDEN N-OK-1', '00000000-0000-0000-0000-000000000001', p_basic_salary => 0);
  select c.basic_salary::text into a from public.employee_pay_config c
    join public.employees e on e.id = c.employee_id where e.name = 'GOLDEN N-OK-1';
  if a is distinct from '0.00' then
    raise exception 'N-OK-1: stored exp=0.00 got=%', a;
  end if;
end $$;

-- SSNIT, Tier 2 and employer SSNIT are % of a zero basic: 0. Taxable 500 is inside
-- the 0% band (up to 588): PAYE 0. Net 500.
-- probe: N-OK-2 basic 0, taxable allowance 500 (allowance-only pay)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN N-OK-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 0, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable, position) values
  ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
  ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
language plpgsql as $f$
declare
  k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
begin
  foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
    'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
    'iou', 'total_deductions', 'net_pay'] loop
    continue when not (p_exp ? k);
    v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
      when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
      when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
      when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
      when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
    v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
                 else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
    v_ok := coalesce(v_ok, false);
    v_bad := v_bad or not v_ok;
    v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
      coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
  end loop;
  select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
    where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
      'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
      'iou', 'total_deductions', 'net_pay']);
  if k is not null then
    raise exception '%: unknown expected key(s): %', p_case, k;
  end if;
  if v_bad then
    raise exception '%: %', p_case, rtrim(v_line, '; ');
  end if;
end $f$;
-- as role:
select pg_temp.golden_check(
  'N-OK-2',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 500}]'::jsonb, 0, 0)),
  '{"gross_salary": "500.00", "total_allowances": "500.00", "overtime_pay": "0.00", "taxable_income": "500.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "0.00", "net_pay": "500.00"}');


-- ==========================================================================
-- PENDING. Not asserted until the accountant confirms (D-0b)
-- Inputs and expected values are written down; uncomment a case only after
-- a confirmation gate. Base basic 3,100: SSNIT 15.50, Tier 2 155.00,
-- employer 403.00, taxable 2,929.50, PAYE 392.26.

-- PENDING (non-taxable allowances: the accountant said only 'subject to GRA policy'; all
-- allowances stay taxable until he names an exemption): not asserted until confirmed.
-- -- probe: Q-ALW-N non-taxable allowance 500
-- -- expect: Manager,Accountant
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN Q-ALW-N', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- insert into public.allowance_types (id, branch_id, name, taxable, position) values
--   ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
--   ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
-- create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
-- language plpgsql as $f$
-- declare
--   k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
-- begin
--   foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
--     'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
--     'iou', 'total_deductions', 'net_pay'] loop
--     continue when not (p_exp ? k);
--     v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
--       when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
--       when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
--       when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
--       when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
--     v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
--                  else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
--     v_ok := coalesce(v_ok, false);
--     v_bad := v_bad or not v_ok;
--     v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
--       coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
--   end loop;
--   select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
--     where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
--       'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
--       'iou', 'total_deductions', 'net_pay']);
--   if k is not null then
--     raise exception '%: unknown expected key(s): %', p_case, k;
--   end if;
--   if v_bad then
--     raise exception '%: %', p_case, rtrim(v_line, '; ');
--   end if;
-- end $f$;
-- -- as role:
-- select pg_temp.golden_check(
--   'Q-ALW-N',
--   to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b2", "amount": 500}]'::jsonb, 0, 0)),
--   '{"gross_salary": "3600.00", "total_allowances": "500.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "562.76", "net_pay": "3037.24"}');

-- PENDING (non-taxable allowances, as Q-ALW-N): not asserted until confirmed.
-- -- probe: Q-ALW-MIX taxable 500 + non-taxable 300
-- -- expect: Manager,Accountant
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN Q-ALW-MIX', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- insert into public.allowance_types (id, branch_id, name, taxable, position) values
--   ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
--   ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
-- create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
-- language plpgsql as $f$
-- declare
--   k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
-- begin
--   foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
--     'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
--     'iou', 'total_deductions', 'net_pay'] loop
--     continue when not (p_exp ? k);
--     v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
--       when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
--       when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
--       when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
--       when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
--     v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
--                  else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
--     v_ok := coalesce(v_ok, false);
--     v_bad := v_bad or not v_ok;
--     v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
--       coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
--   end loop;
--   select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
--     where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
--       'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
--       'iou', 'total_deductions', 'net_pay']);
--   if k is not null then
--     raise exception '%: unknown expected key(s): %', p_case, k;
--   end if;
--   if v_bad then
--     raise exception '%: %', p_case, rtrim(v_line, '; ');
--   end if;
-- end $f$;
-- -- as role:
-- select pg_temp.golden_check(
--   'Q-ALW-MIX',
--   to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 500}, {"allowance_type_id": "90d00000-0000-0000-0000-0000000000b2", "amount": 300}]'::jsonb, 0, 0)),
--   '{"gross_salary": "3900.00", "total_allowances": "800.00", "overtime_pay": "0.00", "taxable_income": "3429.50", "tax": "479.76", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "650.26", "net_pay": "3249.74"}');

-- PENDING (the National Service payslip showing taxable income 1,800 with no PAYE): not asserted until confirmed.
-- -- probe: Q-NSS-ALW National Service + allowance 300
-- -- expect: Manager,Accountant
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN Q-NSS-ALW', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 1500, date '2026-01-01', false, false, false);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- insert into public.allowance_types (id, branch_id, name, taxable, position) values
--   ('90d00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Golden taxable allowance', true, 900),
--   ('90d00000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'Golden non-taxable allowance', false, 901);
-- create function pg_temp.golden_check(p_case text, p_got jsonb, p_exp jsonb) returns void
-- language plpgsql as $f$
-- declare
--   k text; v_label text; v_line text := ''; v_bad boolean := false; v_ok boolean;
-- begin
--   foreach k in array array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
--     'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
--     'iou', 'total_deductions', 'net_pay'] loop
--     continue when not (p_exp ? k);
--     v_label := case k when 'gross_salary' then 'gross' when 'total_allowances' then 'allowances'
--       when 'overtime_pay' then 'OT pay' when 'taxable_income' then 'taxable' when 'tax' then 'PAYE'
--       when 'overtime_tax' then 'OT tax' when 'overtime_concession' then 'concession'
--       when 'ssnit' then 'SSNIT' when 'tier2' then 'Tier 2' when 'ssnit_employer' then 'employer SSNIT'
--       when 'iou' then 'IOU' when 'total_deductions' then 'deductions' when 'net_pay' then 'net' else k end;
--     v_ok := case when jsonb_typeof(p_exp -> k) = 'boolean' then (p_got ->> k) = (p_exp ->> k)
--                  else (p_got ->> k)::numeric = (p_exp ->> k)::numeric end;
--     v_ok := coalesce(v_ok, false);
--     v_bad := v_bad or not v_ok;
--     v_line := v_line || format('%s exp=%s got=%s%s; ', v_label, p_exp ->> k,
--       coalesce(p_got ->> k, 'null'), case when v_ok then '' else ' <<WRONG' end);
--   end loop;
--   select string_agg(key, ', ') into k from jsonb_object_keys(p_exp) key
--     where key <> all (array['gross_salary', 'total_allowances', 'overtime_pay', 'taxable_income',
--       'tax', 'overtime_tax', 'overtime_concession', 'ssnit', 'tier2', 'ssnit_employer', 'fines',
--       'iou', 'total_deductions', 'net_pay']);
--   if k is not null then
--     raise exception '%: unknown expected key(s): %', p_case, k;
--   end if;
--   if v_bad then
--     raise exception '%: %', p_case, rtrim(v_line, '; ');
--   end if;
-- end $f$;
-- -- as role:
-- select pg_temp.golden_check(
--   'Q-NSS-ALW',
--   to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[{"allowance_type_id": "90d00000-0000-0000-0000-0000000000b1", "amount": 300}]'::jsonb, 0, 0)),
--   '{"gross_salary": "1800.00", "total_allowances": "300.00", "overtime_pay": "0.00", "taxable_income": "1800.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "0.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "0.00", "net_pay": "1800.00"}');

-- PENDING (posting accounts for fines, 4910, and IOU, 1350): not asserted until confirmed.
-- Working: basic 3,100, fines 100, IOU 250 (as S26-FINE-IOU). Debits 3,100 + 403 =
-- 3,503.00 = credits 2,187.24 + 15.50 + 403 + 155 + 392.26 + 250 + 100.
-- -- probe: Q-POST-3 fines and IOU posting accounts
-- -- expect: Manager
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN Q-POST-3', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- update public.employees set employment_status = 'Suspended'
-- where employment_status = 'Active' and id not in ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-000000000002', '90d00000-0000-0000-0000-000000000003');
-- select set_config('request.jwt.claims', json_build_object('sub',
--   (select id from public.staff where role = 'Manager' and active order by id limit 1),
--   'role', 'authenticated')::text, true);
-- select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 100, 250);
-- select 1 from public.submit_payroll_run_for_review('90d00000-0000-0000-0000-0000000000a1');
-- create function pg_temp.golden_check_lines(p_case text, p_entry text, p_exp text) returns void
-- language plpgsql as $f$
-- declare v_got text; v_dr numeric; v_cr numeric;
-- begin
--   select string_agg(concat_ws(':', a.code, l.debit, l.credit, l.description), ' | ' order by l.position),
--          sum(l.debit), sum(l.credit)
--     into v_got, v_dr, v_cr
--   from public.journal_lines l join public.accounts a on a.id = l.account_id
--   where l.entry_id = p_entry;
--   if v_got is distinct from p_exp or v_dr <> v_cr then
--     raise exception '%: lines exp=[%] got=[%] debits=% credits=%', p_case, p_exp, v_got, v_dr, v_cr;
--   end if;
-- end $f$;
-- -- as role:
-- do $$
-- declare v_entry public.journal_entries;
-- begin
--   v_entry := public.post_payroll_run('90d00000-0000-0000-0000-0000000000a1');
--   perform pg_temp.golden_check_lines('Q-POST-3', v_entry.id,
--     '5140:3100.00:0.00:Gross pay — September 2026 | 2300:0.00:2187.24:Net pay payable — September 2026 | 2310:0.00:15.50:SSNIT withheld — September 2026 | 5145:403.00:0.00:Employer SSNIT contribution — September 2026 | 2310:0.00:403.00:Employer SSNIT contribution — September 2026 | 2320:0.00:155.00:Tier 2 withheld — September 2026 | 2330:0.00:392.26:PAYE withheld — September 2026 | 1350:0.00:250.00:Staff advance recovery — September 2026 | 4910:0.00:100.00:Staff fines recovered — September 2026');
-- end $$;
--
