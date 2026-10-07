-- Golden staff advances suite (staff advances slice). Holds the automatic
-- repayment of staff advances in create_payslip(), their balances and the
-- payslip lines to hand-derived figures, through the same rolled-back
-- harness as payslips.sql. Run all tiers: ./scripts/golden-payslips.sh
--
-- Rules (as payslips.sql): a red case is never fixed by editing its expected
-- figure; PENDING cases stay commented out until confirmed.
--
-- Base: basic 3,100, all statutory deductions, 2026-09-01 bands (September
-- to December 2026): SSNIT 15.50, Tier 2 155.00, taxable 2,929.50, PAYE
-- 392.26, net before any advance 2,537.24 (as S26-FINE-IOU in payslips.sql).
-- Advance repayments come off after tax and don't reduce taxable income
-- (accountant confirmed (reported, written copy to be saved)). They join payslips.iou.
-- Account 1350 (Advances to Staff) is NOT confirmed by the accountant: the
-- posting cases are PENDING.
-- Fixture advances are inserted directly as Active (setup runs as postgres,
-- so they aren't audited and post no payout entry).


-- ==========================================================================
-- A. Automatic repayment
-- Advance 1,000 at 250 a month from September unless stated.

-- Taxable 2,929.50 and PAYE 392.26 unchanged; deductions 392.26 + 15.50 + 155 + 250 =
-- 812.76; net 2,287.24. Balance after 1,000 - 250 = 750.
-- probe: ADV-1 normal instalment 250
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-1', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "250.00", "total_deductions": "812.76", "net_pay": "2287.24"}');
  perform pg_temp.golden_adv_lines('ADV-1', v.id, '250.00/250.00/750.00');
  perform pg_temp.golden_adv_state('ADV-1', '90d00000-0000-0000-0000-0000000000e1', 'Active/750.00');
end $$;

-- Final instalment least(250, balance 100) = 100: deductions 392.26 + 15.50 + 155 +
-- 100 = 662.76, net 2,437.24; then Settled (computed) and December deducts nothing.
-- probe: ADV-2 600 at 250: 250, 250, then 100 settles; nothing after
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000001', 11, 2026);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001', 12, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 600, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_adv_lines('ADV-2 Sep', v.id, '250.00/250.00/350.00');
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a2', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_adv_lines('ADV-2 Oct', v.id, '250.00/250.00/100.00');
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a3', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-2 Nov', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "100.00", "total_deductions": "662.76", "net_pay": "2437.24"}');
  perform pg_temp.golden_adv_lines('ADV-2 Nov', v.id, '100.00/100.00/0.00');
  perform pg_temp.golden_adv_state('ADV-2 Nov', '90d00000-0000-0000-0000-0000000000e1', 'Settled/0.00');
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a4', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-2 Dec', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "562.76", "net_pay": "2537.24"}');
  perform pg_temp.golden_adv_lines('ADV-2 Dec', v.id, '');
end $$;

-- probe: ADV-3 paused advance not deducted
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-3', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Paused', timestamptz '2026-08-01 09:00:00+00');
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips; r text;
begin
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-3', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "562.76", "net_pay": "2537.24"}');
  perform pg_temp.golden_adv_lines('ADV-3', v.id, '');
  perform pg_temp.golden_adv_state('ADV-3', '90d00000-0000-0000-0000-0000000000e1', 'Paused/1000.00');
  select skip_reason into r from public.staff_advance_deduction_preview('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000a1');
  if r is distinct from 'Paused' then raise exception 'ADV-3: skip reason exp=Paused got=%', r; end if;
end $$;

-- Cancel only stops deductions; the balance stays outstanding (Eyram, decision d).
-- probe: ADV-4 cancelled advance not deducted, balance kept
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Cancelled', timestamptz '2026-08-01 09:00:00+00');
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-4', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "562.76", "net_pay": "2537.24"}');
  perform pg_temp.golden_adv_lines('ADV-4', v.id, '');
  perform pg_temp.golden_adv_state('ADV-4', '90d00000-0000-0000-0000-0000000000e1', 'Cancelled/1000.00');
end $$;

-- 250 + 100 = 350 in payslips.iou; deductions 912.76, net 2,187.24.
-- probe: ADV-5 two active advances, oldest approval first
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-5', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e2', '90d00000-0000-0000-0000-000000000001', 500, 100, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-15 09:00:00+00');
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-5', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "350.00", "total_deductions": "912.76", "net_pay": "2187.24"}');
  perform pg_temp.golden_adv_lines('ADV-5', v.id, '250.00/250.00/750.00 | 100.00/100.00/400.00');
end $$;

-- Prevents double counting: payslips.iou is either the manual IOU or the advance
-- repayments, never both. S26-IOU (no advance) still takes a manual IOU.
-- probe: ADV-6 manual IOU refused when an advance is deducted
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-6', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
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
select pg_temp.golden_refused('ADV-6',
  $q$select public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 50)$q$,
  'This employee has an active staff advance. Recover through the advance, or pause it first, instead of entering an IOU');


-- ==========================================================================
-- B. Drafts, order of months, never recalculated
--

-- probe: ADV-7 deleting a draft payslip restores the balance; regenerating matches
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-7', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  perform pg_temp.golden_adv_state('ADV-7 before', '90d00000-0000-0000-0000-0000000000e1', 'Active/750.00');
  perform public.delete_payslip((select id from public.payslips where payroll_run_id = '90d00000-0000-0000-0000-0000000000a1' and employee_id = '90d00000-0000-0000-0000-000000000001'));
  perform pg_temp.golden_adv_state('ADV-7 deleted', '90d00000-0000-0000-0000-0000000000e1', 'Active/1000.00');
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-7', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "250.00", "total_deductions": "812.76", "net_pay": "2287.24"}');
  perform pg_temp.golden_adv_lines('ADV-7', v.id, '250.00/250.00/750.00');
end $$;

-- September's draft repayment counts: October takes 250 more, balance 500.
-- probe: ADV-8 later draft month doesn't over-deduct
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-8', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a2', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-8', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "250.00", "total_deductions": "812.76", "net_pay": "2287.24"}');
  perform pg_temp.golden_adv_lines('ADV-8', v.id, '250.00/250.00/500.00');
end $$;

-- probe: ADV-9 backdated run after a later month is skipped
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-9', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000001', 11, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a3', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips; r text;
begin
  select skip_reason into r from public.staff_advance_deduction_preview('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000a2');
  if r is distinct from 'Already repaid in a later payroll month' then
    raise exception 'ADV-9: skip reason exp=Already repaid in a later payroll month got=%', r;
  end if;
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a2', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-9', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "562.76", "net_pay": "2537.24"}');
  perform pg_temp.golden_adv_lines('ADV-9', v.id, '');
end $$;

-- probe: ADV-10 not deducted before its first repayment month
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-10', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-10-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips; r text;
begin
  select skip_reason into r from public.staff_advance_deduction_preview('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-0000000000a1');
  if r is distinct from 'Repayments start October 2026' then
    raise exception 'ADV-10: skip reason exp=Repayments start October 2026 got=%', r;
  end if;
  v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
  perform pg_temp.golden_check('ADV-10', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "0.00", "total_deductions": "562.76", "net_pay": "2537.24"}');
end $$;

-- The payslip and its repayment keep 250 after the advance changes (setup applies the
-- change directly). Read-only check, so the Auditor passes too.
-- probe: ADV-11 draft payslip not recalculated after instalment change and pause
-- expect: Manager,Accountant,Auditor
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-11', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
update public.staff_advances set instalment = 300, status = 'Paused' where id = '90d00000-0000-0000-0000-0000000000e1';
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  select * into v from public.payslips where id = (select id from public.payslips where payroll_run_id = '90d00000-0000-0000-0000-0000000000a1' and employee_id = '90d00000-0000-0000-0000-000000000001');
  perform pg_temp.golden_check('ADV-11', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "250.00", "total_deductions": "812.76", "net_pay": "2287.24"}');
  perform pg_temp.golden_adv_lines('ADV-11', v.id, '250.00/250.00/750.00');
end $$;

-- probe: ADV-12 posted payslip not recalculated after cancel
-- expect: Manager,Accountant,Auditor
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-12', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
update public.employees set employment_status = 'Suspended'
where employment_status = 'Active' and id not in ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-000000000002', '90d00000-0000-0000-0000-000000000003');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
select 1 from public.submit_payroll_run_for_review('90d00000-0000-0000-0000-0000000000a1');
select 1 from public.post_payroll_run('90d00000-0000-0000-0000-0000000000a1');
update public.staff_advances set instalment = 300, status = 'Cancelled' where id = '90d00000-0000-0000-0000-0000000000e1';
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
create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
    into v_got from public.staff_advance_payslip_lines(p_payslip);
  if v_got is distinct from p_exp then
    raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
language plpgsql as $f$
declare v_got text;
begin
  select display_status || '/' || balance into v_got
    from public.staff_advance_summary() where id = p_advance;
  if v_got is distinct from p_exp then
    raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
  end if;
end $f$;
-- as role:
do $$
declare v public.payslips;
begin
  select * into v from public.payslips where id = (select id from public.payslips where payroll_run_id = '90d00000-0000-0000-0000-0000000000a1' and employee_id = '90d00000-0000-0000-0000-000000000001');
  perform pg_temp.golden_check('ADV-12', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "0.00", "iou": "250.00", "total_deductions": "812.76", "net_pay": "2287.24"}');
  perform pg_temp.golden_adv_lines('ADV-12', v.id, '250.00/250.00/750.00');
end $$;


-- ==========================================================================
-- C. Refused inputs (2 dp and non-negative rules, 20261007110000)
--

-- probe: ADV-R1 propose_staff_advance refuses amount 100.005
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R1', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R1',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 100.005, 50, date '2026-10-01', date '2026-09-01', 'Cash')$q$,
  'Advance amount must have at most 2 decimal places (got 100.005)');

-- probe: ADV-R2 propose_staff_advance refuses amount -100
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R2', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R2',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', -100, 50, date '2026-10-01', date '2026-09-01', 'Cash')$q$,
  'Advance amount cannot be negative (got -100)');

-- probe: ADV-R3 propose_staff_advance refuses amount 0
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R3', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R3',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 0, 50, date '2026-10-01', date '2026-09-01', 'Cash')$q$,
  'The amount advanced must be more than 0');

-- probe: ADV-R4 propose_staff_advance refuses instalment 25.005
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R4', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R4',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 100, 25.005, date '2026-10-01', date '2026-09-01', 'Cash')$q$,
  'Monthly instalment must have at most 2 decimal places (got 25.005)');

-- probe: ADV-R5 propose_staff_advance refuses instalment -25
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R5', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R5',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 100, -25, date '2026-10-01', date '2026-09-01', 'Cash')$q$,
  'Monthly instalment cannot be negative (got -25)');

-- probe: ADV-R6 propose_staff_advance refuses instalment above the amount
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R6', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R6',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 100, 150, date '2026-10-01', date '2026-09-01', 'Cash')$q$,
  'The monthly instalment cannot be more than the amount advanced');

-- probe: ADV-R8 repayments starting before the payout month refused
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R8', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
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
select pg_temp.golden_refused('ADV-R8',
  $q$select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-08-01', date '2026-09-01', 'Cash')$q$,
  'Repayments cannot start before the month the advance is paid out');

-- probe: ADV-R7 instalment change to 10.005 refused
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-R7', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
  'Active', timestamptz '2026-08-01 09:00:00+00');
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
select pg_temp.golden_refused('ADV-R7',
  $q$select public.propose_staff_advance_change('90d00000-0000-0000-0000-0000000000e1', 'Instalment', 10.005)$q$,
  'Monthly instalment must have at most 2 decimal places (got 10.005)');


-- ==========================================================================
-- PENDING. Not asserted until confirmed
--

-- PENDING (account 1350 for advance recovery, as Q-POST-3 in payslips.sql): not asserted until confirmed.
-- -- Debits 3,100 + 403 = 3,503.00 = credits 2,287.24 + 15.50 + 403 + 155 + 392.26 + 250.
-- -- probe: ADV-P1 run posting credits the repayment to 1350
-- -- expect: Manager
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-P1', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
--   disbursed_on, disbursement_method, status, reviewed_at)
-- values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
--   'Active', timestamptz '2026-08-01 09:00:00+00');
-- update public.employees set employment_status = 'Suspended'
-- where employment_status = 'Active' and id not in ('90d00000-0000-0000-0000-000000000001', '90d00000-0000-0000-0000-000000000002', '90d00000-0000-0000-0000-000000000003');
-- select set_config('request.jwt.claims', json_build_object('sub',
--   (select id from public.staff where role = 'Manager' and active order by id limit 1),
--   'role', 'authenticated')::text, true);
-- select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 0, 0);
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
--   perform pg_temp.golden_check_lines('ADV-P1', v_entry.id,
--     '5140:3100.00:0.00:Gross pay — September 2026 | 2300:0.00:2287.24:Net pay payable — September 2026 | 2310:0.00:15.50:SSNIT withheld — September 2026 | 5145:403.00:0.00:Employer SSNIT contribution — September 2026 | 2310:0.00:403.00:Employer SSNIT contribution — September 2026 | 2320:0.00:155.00:Tier 2 withheld — September 2026 | 2330:0.00:392.26:PAYE withheld — September 2026 | 1350:0.00:250.00:Staff advance recovery — September 2026');
-- end $$;
-- 
-- PENDING (account 1350 for staff advances): not asserted until confirmed.
-- -- probe: ADV-P2 approval posts the payout Dr 1350 / Cr 1000
-- -- expect: Manager
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-P2', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
--   disbursed_on, disbursement_method)
-- values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-10-01', date '2026-09-01', 'Cash');
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
-- declare v_entry text;
-- begin
--   perform public.approve_staff_advance('90d00000-0000-0000-0000-0000000000e1');
--   select id into v_entry from public.journal_entries where source_table = 'staff_advances' and source_id = '90d00000-0000-0000-0000-0000000000e1';
--   perform pg_temp.golden_check_lines('ADV-P2', v_entry,
--     '1350:1000.00:0.00:Staff advance to GOLDEN ADV-P2 | 1000:0.00:1000.00:Staff advance paid out (Cash)');
-- end $$;
-- 
-- PENDING (the net-pay cap: Eyram's default, built, not yet confirmed by the accountant): not asserted until confirmed.
-- -- Fines 2,400: room 3,100 - (392.26 + 15.50 + 155 + 2,400) = 137.24, so 137.24 is taken,
-- -- net 0.00, and the 112.76 shortfall stays on the balance (1,000 - 137.24 = 862.76).
-- -- probe: ADV-P3 instalment above what net pay allows takes only that
-- -- expect: Manager,Accountant
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-P3', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
--   disbursed_on, disbursement_method, status, reviewed_at)
-- values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
--   'Active', timestamptz '2026-08-01 09:00:00+00');
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
-- create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
-- language plpgsql as $f$
-- declare v_got text;
-- begin
--   select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
--     into v_got from public.staff_advance_payslip_lines(p_payslip);
--   if v_got is distinct from p_exp then
--     raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
--   end if;
-- end $f$;
-- create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
-- language plpgsql as $f$
-- declare v_got text;
-- begin
--   select display_status || '/' || balance into v_got
--     from public.staff_advance_summary() where id = p_advance;
--   if v_got is distinct from p_exp then
--     raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
--   end if;
-- end $f$;
-- -- as role:
-- do $$
-- declare v public.payslips;
-- begin
--   v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 2400, 0);
--   perform pg_temp.golden_check('ADV-P3', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "2400.00", "iou": "137.24", "total_deductions": "3100.00", "net_pay": "0.00"}');
--   perform pg_temp.golden_adv_lines('ADV-P3', v.id, '137.24/250.00/862.76');
-- end $$;
-- 
-- PENDING (the net-pay cap and its oldest-approval-first order: Eyram's default, not yet confirmed): not asserted until confirmed.
-- -- As ADV-P3 with a second, later-approved advance (500 at 100): the 137.24 room goes to the
-- -- older advance; the newer one gets nothing this month (no repayment row, balance 500).
-- -- probe: ADV-P4 two advances, net pay covers part of one: the oldest approval is repaid first
-- -- expect: Manager,Accountant
-- insert into public.employees (id, branch_id, name, employment_status) values
--   ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'GOLDEN ADV-P4', 'Active');
-- insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
--   pays_ssnit, pays_tier2, pays_paye)
-- values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
-- insert into public.payroll_runs (id, branch_id, month, year)
-- values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
--   disbursed_on, disbursement_method, status, reviewed_at)
-- values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-09-01', date '2026-08-01', 'Cash',
--   'Active', timestamptz '2026-08-01 09:00:00+00');
-- insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
--   disbursed_on, disbursement_method, status, reviewed_at)
-- values ('90d00000-0000-0000-0000-0000000000e2', '90d00000-0000-0000-0000-000000000001', 500, 100, date '2026-09-01', date '2026-08-01', 'Cash',
--   'Active', timestamptz '2026-08-15 09:00:00+00');
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
-- create function pg_temp.golden_adv_lines(p_case text, p_payslip uuid, p_exp text) returns void
-- language plpgsql as $f$
-- declare v_got text;
-- begin
--   select coalesce(string_agg(amount || '/' || instalment_due || '/' || balance_after, ' | '), '')
--     into v_got from public.staff_advance_payslip_lines(p_payslip);
--   if v_got is distinct from p_exp then
--     raise exception '%: advance lines exp=[%] got=[%]', p_case, p_exp, v_got;
--   end if;
-- end $f$;
-- create function pg_temp.golden_adv_state(p_case text, p_advance uuid, p_exp text) returns void
-- language plpgsql as $f$
-- declare v_got text;
-- begin
--   select display_status || '/' || balance into v_got
--     from public.staff_advance_summary() where id = p_advance;
--   if v_got is distinct from p_exp then
--     raise exception '%: advance status/balance exp=[%] got=[%]', p_case, p_exp, v_got;
--   end if;
-- end $f$;
-- -- as role:
-- do $$
-- declare v public.payslips;
-- begin
--   v := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb, 2400, 0);
--   perform pg_temp.golden_check('ADV-P4', to_jsonb(v), '{"gross_salary": "3100.00", "total_allowances": "0.00", "overtime_pay": "0.00", "taxable_income": "2929.50", "tax": "392.26", "overtime_tax": "0.00", "overtime_concession": false, "ssnit": "15.50", "tier2": "155.00", "ssnit_employer": "403.00", "fines": "2400.00", "iou": "137.24", "total_deductions": "3100.00", "net_pay": "0.00"}');
--   perform pg_temp.golden_adv_lines('ADV-P4', v.id, '137.24/250.00/862.76');
--   perform pg_temp.golden_adv_state('ADV-P4 second', '90d00000-0000-0000-0000-0000000000e2', 'Active/500.00');
-- end $$;
-- 
