-- Role matrix for 20261008100000_staff_advances (the three staff advance
-- tables, their read functions and the propose / approve / reject /
-- withdraw functions) and 20261008110000_create_payslip_staff_advances.
-- Run: ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261008100000_staff_advances.sql
--
-- Expected access (approved by Eyram 2026-10-07): Manager and Accountant
-- propose and withdraw; only a Manager approves or rejects (own proposals
-- included); Manager, Accountant and Auditor read; nobody writes the
-- tables directly; anon can execute none of the new functions. The deduction
-- figures are in supabase/golden/staff-advances.sql.
--
-- Fixtures: employee 90d0...01 (Active, basic 3,100), advance 90d0...e1,
-- change request 90d0...f1. A "foreign" proposal is one proposed by the dev
-- Attendant, so neither the Manager nor the Accountant owns it.

-- ============================================================ A. propose and withdraw

-- probe: A1 propose_staff_advance
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
-- as role:
select public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash');

-- probe: A2 propose then withdraw own proposal
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
-- as role:
do $$
declare v public.staff_advances;
begin
  v := public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 1000, 250,
    date '2026-10-01', date '2026-09-01', 'Cash');
  v := public.withdraw_staff_advance_proposal(v.id);
  if v.status <> 'Rejected' or v.rejection_reason <> 'Withdrawn by proposer' then
    raise exception 'A2: status exp=Rejected (Withdrawn by proposer) got=% (%)', v.status, v.rejection_reason;
  end if;
end $$;

-- probe: A3 withdraw someone else's proposal
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, proposed_by)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash',
  (select id from public.staff where role = 'Attendant' and active order by id limit 1));
-- as role:
select public.withdraw_staff_advance_proposal('90d00000-0000-0000-0000-0000000000e1');

-- ============================================================ B. approve and reject

-- probe: B1 approve_staff_advance posts the payout entry
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash');
-- as role:
do $$
declare v public.staff_advances;
begin
  v := public.approve_staff_advance('90d00000-0000-0000-0000-0000000000e1');
  if v.status <> 'Active' or v.reviewed_by is distinct from auth.uid() then
    raise exception 'B1: status exp=Active got=%, reviewed_by not the approver', v.status;
  end if;
  if not exists (select 1 from public.journal_entries
                 where source_table = 'staff_advances' and source_id = v.id::text) then
    raise exception 'B1: no payout journal entry';
  end if;
end $$;

-- probe: B2 reject_staff_advance
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash');
-- as role:
select public.reject_staff_advance('90d00000-0000-0000-0000-0000000000e1', 'matrix');

-- probe: B3 Manager approves their own proposal, both names kept
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
-- as role:
do $$
declare v public.staff_advances;
begin
  v := public.propose_staff_advance('90d00000-0000-0000-0000-000000000001', 1000, 250,
    date '2026-10-01', date '2026-09-01', 'Cash');
  v := public.approve_staff_advance(v.id);
  if v.proposed_by is distinct from auth.uid() or v.reviewed_by is distinct from auth.uid() then
    raise exception 'B3: proposer and approver not both recorded';
  end if;
end $$;

-- ============================================================ C. changes

-- probe: C1 propose_staff_advance_change (pause)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
-- as role:
select public.propose_staff_advance_change('90d00000-0000-0000-0000-0000000000e1', 'Pause');

-- probe: C2 approve_staff_advance_change applies it
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
insert into public.staff_advance_change_requests (id, advance_id, kind, new_instalment)
values ('90d00000-0000-0000-0000-0000000000f1', '90d00000-0000-0000-0000-0000000000e1', 'Instalment', 300);
-- as role:
do $$
declare v numeric;
begin
  perform public.approve_staff_advance_change('90d00000-0000-0000-0000-0000000000f1');
  select instalment into v from public.staff_advances where id = '90d00000-0000-0000-0000-0000000000e1';
  if v <> 300 then raise exception 'C2: instalment exp=300 got=%', v; end if;
end $$;

-- probe: C3 reject_staff_advance_change
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
insert into public.staff_advance_change_requests (id, advance_id, kind)
values ('90d00000-0000-0000-0000-0000000000f1', '90d00000-0000-0000-0000-0000000000e1', 'Cancel');
-- as role:
select public.reject_staff_advance_change('90d00000-0000-0000-0000-0000000000f1', 'matrix');

-- probe: C4 propose then withdraw own change
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
-- as role:
do $$
declare v public.staff_advance_change_requests;
begin
  v := public.propose_staff_advance_change('90d00000-0000-0000-0000-0000000000e1', 'Cancel');
  perform public.withdraw_staff_advance_change(v.id);
end $$;

-- probe: C5 withdraw someone else's change
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
insert into public.staff_advance_change_requests (id, advance_id, kind, proposed_by)
values ('90d00000-0000-0000-0000-0000000000f1', '90d00000-0000-0000-0000-0000000000e1', 'Cancel',
  (select id from public.staff where role = 'Attendant' and active order by id limit 1));
-- as role:
select public.withdraw_staff_advance_change('90d00000-0000-0000-0000-0000000000f1');

-- ============================================================ D. reads

-- probe: D1 read the three tables and the three read functions
-- expect: Manager,Accountant,Auditor
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from, pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
insert into public.staff_advance_change_requests (id, advance_id, kind)
values ('90d00000-0000-0000-0000-0000000000f1', '90d00000-0000-0000-0000-0000000000e1', 'Pause');
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001');
-- as role:
do $$
begin
  if not exists (select 1 from public.staff_advances) then raise exception 'no advances visible'; end if;
  if not exists (select 1 from public.staff_advance_change_requests) then raise exception 'no change requests visible'; end if;
  if not exists (select 1 from public.staff_advance_repayments) then raise exception 'no repayments visible'; end if;
  if not exists (select 1 from public.staff_advance_summary('90d00000-0000-0000-0000-000000000001')) then
    raise exception 'summary empty';
  end if;
  if not exists (select 1 from public.staff_advance_deduction_preview('90d00000-0000-0000-0000-000000000001',
                 '90d00000-0000-0000-0000-0000000000a1')) then
    raise exception 'preview empty';
  end if;
  if not exists (select 1 from public.staff_advance_payslip_lines(
                 (select id from public.payslips where payroll_run_id = '90d00000-0000-0000-0000-0000000000a1'))) then
    raise exception 'payslip lines empty';
  end if;
end $$;

-- ============================================================ E. no direct writes

-- probe: E1 direct insert into staff_advances
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
-- as role:
insert into public.staff_advances (employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status)
values ('90d00000-0000-0000-0000-000000000001', 1000, 250, date '2026-10-01', date '2026-09-01', 'Cash', 'Active');

-- probe: E2 direct update of staff_advances
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash');
-- as role:
update public.staff_advances set status = 'Active' where id = '90d00000-0000-0000-0000-0000000000e1';

-- probe: E3 direct delete from staff_advances
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash');
-- as role:
delete from public.staff_advances where id = '90d00000-0000-0000-0000-0000000000e1';

-- probe: E4 direct insert into staff_advance_change_requests
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
-- as role:
insert into public.staff_advance_change_requests (advance_id, kind)
values ('90d00000-0000-0000-0000-0000000000e1', 'Cancel');

-- probe: E5 direct insert into staff_advance_repayments
-- expect: none
-- as role:
insert into public.staff_advance_repayments (advance_id, payslip_id, amount, instalment_due)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-0000000000b9', 10, 10);

-- probe: E6 the internal change-check helper
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MATRIX ADV', 'Active');
insert into public.staff_advances (id, employee_id, amount, instalment, first_repayment_month,
  disbursed_on, disbursement_method, status, reviewed_at)
values ('90d00000-0000-0000-0000-0000000000e1', '90d00000-0000-0000-0000-000000000001', 1000, 250,
  date '2026-10-01', date '2026-09-01', 'Cash', 'Active', now());
-- as role:
select public._staff_advance_change_problem(a, 'Pause', null)
from public.staff_advances a where a.id = '90d00000-0000-0000-0000-0000000000e1';

-- ============================================================ F. anon surface

-- probe: F1 anon can execute none of the new functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
do $$
declare f text;
begin
  foreach f in array array[
    'public.staff_advance_summary(uuid)', 'public.staff_advance_deduction_preview(uuid, uuid)',
    'public.staff_advance_payslip_lines(uuid)',
    'public.propose_staff_advance(uuid, numeric, numeric, date, date, text, uuid, text)',
    'public.approve_staff_advance(uuid)', 'public.reject_staff_advance(uuid, text)',
    'public.withdraw_staff_advance_proposal(uuid)',
    'public.propose_staff_advance_change(uuid, text, numeric, text)',
    'public.approve_staff_advance_change(uuid)', 'public.reject_staff_advance_change(uuid, text)',
    'public.withdraw_staff_advance_change(uuid)',
    'public._staff_advance_change_problem(public.staff_advances, text, numeric)',
    'public.staff_advances_freeze()', 'public.audit_staff_advances()',
    'public.audit_staff_advance_change_requests()'] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'anon can execute %', f;
    end if;
  end loop;
end $$;
