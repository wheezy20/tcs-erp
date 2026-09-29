-- Role matrix for 20260929130000_admissions_officer_role (admissions slice
-- 1b-ii, docs/admissions/PORT-PLAN.md). The Admissions Officer reads
-- branches, its own staff row and list_staff_names(), and nothing in
-- finance, payroll, HR or storage. The store tables, write policies and
-- require_writable_role() RPCs are covered by the 1b-i regression file
-- (20260929110000_allowlist_guards_regression.sql), re-run with this
-- column.
--
-- Every denial reads a row that exists (seeded or an invented fixture), so
-- "no rows visible" is RLS, not an empty table. Fixture ids start
-- 9e1b0000-, apart from the PAYE probes' 9e260000-; payroll fixtures use
-- 2090 so they can't meet a real or PAYE-probe run. Every probe is rolled
-- back by scripts/role-matrix.sh.
--
-- The signup probes test the handle_new_staff_signup trigger itself, which
-- isn't role-dependent: the assertion runs in the postgres setup (a failure
-- shows as SETUP FAILED) and the role part is a no-op every role passes.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20260929130000_admissions_officer_role.sql

-- ================================================================ staff

-- probe: staff: sees exactly its own row
-- expect: Admissions Officer
do $$ begin
  if (select count(*) from public.staff) <> 1
     or not exists (select 1 from public.staff where id = auth.uid()) then
    raise exception 'sees % staff rows', (select count(*) from public.staff);
  end if;
end $$;

-- probe: staff: sees other staff rows
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin
  if not exists (select 1 from public.staff where id is distinct from auth.uid()) then
    raise exception 'no other staff visible';
  end if;
end $$;

-- probe: list_staff_names() sees every name
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from public.list_staff_names()) < 5 then
    raise exception 'expected every staff name';
  end if;
end $$;

-- probe: branches: reads Main and Annex
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from public.branches) <> 2 then raise exception 'expected 2 branches'; end if;
end $$;

-- probe: branches: update (can_write)
-- expect: Attendant,Manager
do $$ declare n int; begin
  update public.branches set name = name where name = 'Annex';
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- ================================================================ finance

-- probe: read accounts
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.accounts) then raise exception 'no rows visible'; end if; end $$;

-- probe: read expenses
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.expenses) then raise exception 'no rows visible'; end if; end $$;

-- probe: read bank_accounts
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.bank_accounts) then raise exception 'no rows visible'; end if; end $$;

-- probe: read journal_entries
-- expect: Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
select public.post_journal_entry(current_date, 'officer probe', '',
  jsonb_build_array(
    jsonb_build_object('account_id', (select id from public.accounts where code = '1000'), 'debit', 1, 'credit', 0, 'description', ''),
    jsonb_build_object('account_id', (select id from public.accounts where code = '3000'), 'debit', 0, 'credit', 1, 'description', '')),
  null);
-- as role:
do $$ begin if not exists (select 1 from public.journal_entries) then raise exception 'no rows visible'; end if; end $$;

-- ================================================================ payroll

-- probe: read employee_pay_config
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.employee_pay_config) then raise exception 'no rows visible'; end if; end $$;

-- probe: read paye_bands
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.paye_bands) then raise exception 'no rows visible'; end if; end $$;

-- probe: read payroll_runs
-- expect: Manager,Accountant,Auditor
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e1b0000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 2090);
-- as role:
do $$ begin if not exists (select 1 from public.payroll_runs) then raise exception 'no rows visible'; end if; end $$;

-- probe: read payslips
-- expect: Manager,Accountant,Auditor
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e1b0000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Probe Payee', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from) values
  ('9e1b0000-0000-0000-0000-000000000001', 1000, date '2090-01-01');
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e1b0000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 2090);
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
select public.create_payslip('9e1b0000-0000-0000-0000-0000000000a1', '9e1b0000-0000-0000-0000-000000000001');
-- as role:
do $$ begin if not exists (select 1 from public.payslips) then raise exception 'no rows visible'; end if; end $$;

-- probe: create_payslip
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e1b0000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Probe Payee', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from) values
  ('9e1b0000-0000-0000-0000-000000000001', 1000, date '2090-01-01');
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e1b0000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 2090);
-- as role:
select public.create_payslip('9e1b0000-0000-0000-0000-0000000000a1', '9e1b0000-0000-0000-0000-000000000001');

-- ================================================================ HR

-- probe: read employees
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.employees) then raise exception 'no rows visible'; end if; end $$;

-- probe: read employee_documents
-- expect: Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.employee_documents (employee_id, document_type, storage_path)
values ((select id from public.employees order by id limit 1), 'Other', 'probe/9e1b-officer.pdf');
-- as role:
do $$ begin if not exists (select 1 from public.employee_documents) then raise exception 'no rows visible'; end if; end $$;

-- probe: read employee_onboarding_tokens
-- expect: Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.employee_onboarding_tokens (id, employee_id, token_hash, expires_at)
values ('9e1b0000-0000-0000-0000-0000000000c1', (select id from public.employees order by id limit 1),
        'probe-9e1b-token-hash', now() + interval '1 day');
-- as role:
do $$ begin if not exists (select 1 from public.employee_onboarding_tokens) then raise exception 'no rows visible'; end if; end $$;

-- probe: read employee_onboarding_submissions
-- expect: Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.employee_onboarding_tokens (id, employee_id, token_hash, expires_at)
values ('9e1b0000-0000-0000-0000-0000000000c1', (select id from public.employees order by id limit 1),
        'probe-9e1b-token-hash', now() + interval '1 day');
insert into public.employee_onboarding_submissions (employee_id, token_id)
values ((select id from public.employees order by id limit 1), '9e1b0000-0000-0000-0000-0000000000c1');
-- as role:
do $$ begin if not exists (select 1 from public.employee_onboarding_submissions) then raise exception 'no rows visible'; end if; end $$;

-- probe: read employee_onboarding_tasks
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.employee_onboarding_tasks) then raise exception 'no rows visible'; end if; end $$;

-- probe: read onboarding_checklist_items
-- expect: Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.onboarding_checklist_items) then raise exception 'no rows visible'; end if; end $$;

-- ================================================================ storage

-- probe: storage read receipts
-- expect: Manager,Accountant,Auditor
insert into storage.objects (bucket_id, name) values ('receipts', 'probe/9e1b-officer.pdf');
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'receipts') then raise exception 'no rows visible'; end if;
end $$;

-- probe: storage read onboarding-documents
-- expect: Manager,Accountant,Auditor
insert into storage.objects (bucket_id, name) values ('onboarding-documents', 'probe/9e1b-officer.pdf');
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'onboarding-documents') then raise exception 'no rows visible'; end if;
end $$;

-- probe: storage read employee-generated-documents
-- expect: Manager,Accountant,Auditor
insert into storage.objects (bucket_id, name) values ('employee-generated-documents', 'probe/9e1b-officer.pdf');
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'employee-generated-documents') then raise exception 'no rows visible'; end if;
end $$;

-- probe: storage insert receipts
-- expect: Manager,Accountant
insert into storage.objects (bucket_id, name) values ('receipts', 'probe/9e1b-officer-upload.pdf');

-- probe: storage insert onboarding-documents
-- expect: Manager,Accountant
insert into storage.objects (bucket_id, name) values ('onboarding-documents', 'probe/9e1b-officer-upload.pdf');

-- probe: storage insert employee-generated-documents
-- expect: Manager,Accountant
insert into storage.objects (bucket_id, name) values ('employee-generated-documents', 'probe/9e1b-officer-upload.pdf');

-- ================================================================ signup trigger

-- probe: signup with role Admissions Officer lands as that role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('9e1b0000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'probe-officer@tcs.test',
        '{"name":"Probe Officer","role":"Admissions Officer"}');
do $$ begin
  if (select role from public.staff where id = '9e1b0000-0000-0000-0000-0000000000b1')
     is distinct from 'Admissions Officer' then
    raise exception 'officer signup did not land as Admissions Officer';
  end if;
end $$;
-- as role:
select 1;

-- probe: signup with an unlisted role is rejected
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  begin
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values ('9e1b0000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'probe-janitor@tcs.test',
            '{"name":"Probe Janitor","role":"Janitor"}');
    raise exception 'unlisted role was accepted';
  exception when others then
    if sqlerrm <> 'Unknown staff role: Janitor' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: signup with no role still defaults to Attendant
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('9e1b0000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'probe-norole@tcs.test', '{"name":"Probe No Role"}');
do $$ begin
  if (select role from public.staff where id = '9e1b0000-0000-0000-0000-0000000000b3')
     is distinct from 'Attendant' then
    raise exception 'missing role did not default to Attendant';
  end if;
end $$;
-- as role:
select 1;

-- probe: staff_role_check refuses an unlisted role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  begin
    update public.staff set role = 'Janitor' where role = 'Attendant' and not protected;
    raise exception 'check constraint accepted Janitor';
  exception when check_violation then null;
  end;
end $$;
-- as role:
select 1;
