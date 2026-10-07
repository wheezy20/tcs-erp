-- Golden payslip suite, TCS OS hand-computed tier (decision D-0c).
-- These cases come from TCS OS's hand-computed tests (backend/modules/hr/
-- tests.py), re-derived independently for slice 0. They are a DIFFERENT
-- TIER from payslips.sql: TCS OS hand-computed, not ERP-confirmed. A red
-- case here means "differs from TCS OS's hand computation", which is
-- weaker evidence than a red statutory or parity case.
-- Run: ./scripts/golden-payslips.sh (runs both files).
--
-- All run in August 2026 (2025-01-01 band set: current behaviour, not confirmed correct).
-- Same harness and failure format as payslips.sql.


-- ==========================================================================
-- H. TCS OS hand-computed, not ERP-confirmed

-- Taxable 6,500 - 325 = 6,175; PAYE 5.50 + 13.00 + 554.17 + 2,278.33 x 25%
-- (569.5825 -> 569.58) = 1,142.25.
-- probe: H1 no SSNIT, basic 6,500
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN H1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 6500, date '2026-01-01', false, true, true);
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
  'H1',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "6500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "6175.00", "tax": "1142.25", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "0.00", "tier2": "325.00", "ssnit_employer": "0.00", "fines": "0.00", "iou": "0.00", "total_deductions": "1467.25", "net_pay": "5032.75"}');

-- Taxable 6,500 - 32.50 = 6,467.50; PAYE 572.67 + 2,570.83 x 25%
-- (642.7075 -> 642.71) = 1,215.38.
-- probe: H2 no Tier 2, basic 6,500
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN H2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 6500, date '2026-01-01', true, false, true);
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
  'H2',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "6500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "6467.50", "tax": "1215.38", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "32.50", "tier2": "0.00", "ssnit_employer": "845.00", "fines": "0.00", "iou": "0.00", "total_deductions": "1247.88", "net_pay": "5252.12"}');

-- taxable_income is NOT asserted (pending in payslips.sql, Q-NSS-ALW).
-- probe: H3 no PAYE, basic 6,500
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN H3', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 6500, date '2026-01-01', true, true, false);
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
  'H3',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "6500.00", "total_allowances": "0.00", "overtime_pay": "0.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "32.50", "tier2": "325.00", "ssnit_employer": "845.00", "fines": "0.00", "iou": "0.00", "total_deductions": "357.50", "net_pay": "6142.50"}');

-- Employer SSNIT 400 x 13% = 52.00 is ERP-derived; TCS OS doesn't assert it.
-- probe: H4 low salary, basic 400
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN H4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 400, date '2026-01-01', true, true, true);
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
  'H4',
  to_jsonb(public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0)),
  '{"gross_salary": "400.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "378.00", "tax": "0.00", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "2.00", "tier2": "20.00", "ssnit_employer": "52.00", "fines": "0.00", "iou": "0.00", "total_deductions": "22.00", "net_pay": "378.00"}');
