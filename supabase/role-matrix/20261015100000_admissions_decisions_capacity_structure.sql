-- Role matrix for 20261015100000_admissions_decisions_capacity, STRUCTURE file (admissions slice 6a,
-- docs/admissions/PORT-PLAN.md): function grants and settings, the exact 169
-- anon-executable count, the exact 33-value audit list (this file owns the
-- exact list from slice 6a on), the five-value offer response check, trigger
-- names, select-only table grants, direct writes denied, and the two SQL
-- helpers' behaviour. Catalog probes raise on failure and expect every role.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261015100000_admissions_decisions_capacity_structure.sql

-- ================================================================ functions: grants and settings

-- probe: S1 helpers and trigger functions are executable by neither anon nor authenticated
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._require_admissions_decider()', 'public._admissions_grade_id(text)', 'public._offer_effective_response(text, timestamptz)', 'public._admissions_capacity_warning(uuid, boolean)', 'public.audit_application_decision()', 'public.audit_admissions_capacity()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception '% is executable', f;
    end if;
  end loop;
end $$;

-- probe: S2 the five RPCs: not anon; authenticated and service_role yes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public.record_decision(uuid, text, text)', 'public.change_decision(uuid, text, text)', 'public.create_admissions_capacity(text, uuid, uuid, integer)', 'public.update_admissions_capacity(uuid, integer)', 'public.delete_admissions_capacity(uuid)'] loop
    if has_function_privilege('anon', f, 'execute')
       or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception 'grants wrong on %', f;
    end if;
  end loop;
end $$;

-- probe: S3 none of the eleven functions carries a PUBLIC grant
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._require_admissions_decider()', 'public._admissions_grade_id(text)', 'public._offer_effective_response(text, timestamptz)', 'public._admissions_capacity_warning(uuid, boolean)', 'public.audit_application_decision()', 'public.audit_admissions_capacity()', 'public.record_decision(uuid, text, text)', 'public.change_decision(uuid, text, text)', 'public.create_admissions_capacity(text, uuid, uuid, integer)', 'public.update_admissions_capacity(uuid, integer)', 'public.delete_admissions_capacity(uuid)'] loop
    if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where p.oid = f::regprocedure and a.grantee = 0) then
      raise exception '% is granted to PUBLIC', f;
    end if;
  end loop;
end $$;

-- probe: S3b helpers and trigger functions are not executable by service_role either
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._require_admissions_decider()', 'public._admissions_grade_id(text)', 'public._offer_effective_response(text, timestamptz)', 'public._admissions_capacity_warning(uuid, boolean)', 'public.audit_application_decision()', 'public.audit_admissions_capacity()'] loop
    if has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by service_role', f;
    end if;
  end loop;
end $$;

-- probe: S4 definers pin search_path=public; the two SQL helpers are invoker with an empty search_path
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._require_admissions_decider()', 'public._admissions_capacity_warning(uuid, boolean)', 'public.audit_application_decision()', 'public.audit_admissions_capacity()', 'public.record_decision(uuid, text, text)', 'public.change_decision(uuid, text, text)', 'public.create_admissions_capacity(text, uuid, uuid, integer)', 'public.update_admissions_capacity(uuid, integer)', 'public.delete_admissions_capacity(uuid)'] loop
    if not (select prosecdef and coalesce('search_path=public' = any (proconfig), false) from pg_proc where oid = f::regprocedure) then
      raise exception '% lost security definer or its search_path', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc where oid in ('public._admissions_grade_id(text)'::regprocedure, 'public._offer_effective_response(text, timestamptz)'::regprocedure)
             and (prosecdef or not coalesce('search_path=""' = any (proconfig), false))) then
    raise exception 'SQL helper settings wrong';
  end if;
  if (select provolatile from pg_proc where oid = 'public._offer_effective_response(text, timestamptz)'::regprocedure) is distinct from 'v' then
    raise exception '_offer_effective_response must be volatile (clock_timestamp)';
  end if;
  if (select provolatile from pg_proc where oid = 'public._admissions_grade_id(text)'::regprocedure) is distinct from 's' then
    raise exception '_admissions_grade_id must be stable';
  end if;
end $$;

-- probe: S5 anon can still execute exactly 169 public functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 169 then
    raise exception 'anon-executable count changed';
  end if;
end $$;

-- probe: S5b each new function exists exactly once (no stray overloads)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare n text;
begin
  foreach n in array array['_require_admissions_decider', '_admissions_grade_id', '_offer_effective_response', '_admissions_capacity_warning', 'record_decision', 'change_decision', 'create_admissions_capacity', 'update_admissions_capacity', 'delete_admissions_capacity', 'audit_application_decision', 'audit_admissions_capacity'] loop
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = n) <> 1 then
      raise exception 'overload count wrong for %', n;
    end if;
  end loop;
end $$;

-- ================================================================ constraints

-- probe: S6 the audit action list has exactly the 33 values
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(m[1] order by m[1]) from pg_constraint c,
        regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') m
      where c.conname = 'audit_log_action_check')
     is distinct from array['admissions_capabilities_changed', 'admissions_capacity_changed', 'application_decision_changed', 'application_document_status_changed', 'application_stage_changed', 'discount_applied', 'employee_approved', 'employee_created', 'employee_reactivated', 'employee_rejected', 'employee_suspended', 'employees_imported', 'expense_voided', 'invoice_voided', 'pay_config_amended_and_approved', 'pay_config_approved', 'pay_config_exemptions_changed', 'pay_config_proposed', 'pay_config_rejected', 'payroll_run_approved', 'payroll_run_exclusion_added', 'payroll_run_exclusion_removed', 'payroll_run_rejected', 'payroll_run_submitted', 'return_processed', 'sale_voided', 'staff_advance_approved', 'staff_advance_change_approved', 'staff_advance_change_proposed', 'staff_advance_change_rejected', 'staff_advance_proposed', 'staff_advance_rejected', 'vat_override'] then
    raise exception 'audit action list wrong';
  end if;
end $$;

-- probe: S6b the two new audit actions insert; a near miss is refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select s.branch_id, s.id, 'application_decision_changed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select s.branch_id, s.id, 'admissions_capacity_changed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
do $$ begin
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
  select s.branch_id, s.id, 'application_decision_removed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
  raise exception 'not refused';
exception when check_violation then null; end $$;

-- probe: S7 the offer response check holds exactly the five values
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(m[1] order by m[1]) from pg_constraint c,
        regexp_matches(pg_get_constraintdef(c.oid), '''([a-z]+)''::text', 'g') m
      where c.conname = 'application_offers_response_check')
     is distinct from array['accepted', 'declined', 'expired', 'pending', 'withdrawn'] then
    raise exception 'response check wrong';
  end if;
end $$;

-- probe: S7b withdrawn is accepted and maybe is refused on application_offers.response
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
-- as role:
reset role;
insert into public.application_offers (application_id, token_hash, response) values ('9e060000-0000-4000-8000-000400000001', md5('a') || md5('b'), 'withdrawn');
do $$ begin
  update public.application_offers set response = 'maybe';
  raise exception 'not refused';
exception when check_violation then null; end $$;
do $$ begin
  update public.application_offers set response = 'cancelled';
  raise exception 'not refused';
exception when check_violation then null; end $$;

-- ================================================================ triggers and tables

-- probe: S8 triggers: decisions has the audit and identity triggers, capacity the audit trigger, offers none
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(tgname::text order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.application_decisions'::regclass)
     is distinct from array['application_decisions_audit', 'application_decisions_set_identity'] then
    raise exception 'decisions triggers wrong';
  end if;
  if (select array_agg(tgname::text) from pg_trigger where not tgisinternal and tgrelid = 'public.admissions_capacity'::regclass)
     is distinct from array['admissions_capacity_audit'] then
    raise exception 'capacity triggers wrong';
  end if;
  if exists (select 1 from pg_trigger where not tgisinternal and tgrelid = 'public.application_offers'::regclass) then
    raise exception 'offers gained a trigger';
  end if;
end $$;

-- probe: S8b trigger definitions: after, per row, the right events
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'application_decisions_audit' and pg_get_triggerdef(oid) ~ 'AFTER INSERT OR UPDATE OF decision_type ON public.application_decisions FOR EACH ROW EXECUTE FUNCTION audit_application_decision\(\)') then
    raise exception 'decisions audit trigger definition wrong';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'admissions_capacity_audit' and pg_get_triggerdef(oid) ~ 'AFTER INSERT OR DELETE OR UPDATE ON public.admissions_capacity FOR EACH ROW EXECUTE FUNCTION audit_admissions_capacity\(\)') then
    raise exception 'capacity audit trigger definition wrong';
  end if;
end $$;

-- probe: S9 decisions, offers and capacity: authenticated select only, one select policy each, anon nothing
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare t text;
begin
  foreach t in array array['public.application_decisions', 'public.application_offers', 'public.admissions_capacity'] loop
    if has_table_privilege('authenticated', t, 'INSERT,UPDATE,DELETE,TRUNCATE')
       or not has_table_privilege('authenticated', t, 'SELECT')
       or has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then
      raise exception 'grants changed on %', t;
    end if;
    if (select count(*) from pg_policies where schemaname || '.' || tablename = t) <> 1
       or (select cmd from pg_policies where schemaname || '.' || tablename = t) <> 'SELECT' then
      raise exception 'policies changed on %', t;
    end if;
    if not (select relrowsecurity from pg_class where oid = t::regclass) then
      raise exception 'RLS off on %', t;
    end if;
  end loop;
end $$;

-- probe: S10 direct insert on application_decisions is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
insert into public.application_decisions (application_id, decision_type) values ('9e060000-0000-4000-8000-000400000001', 'rejected');

-- probe: S10 direct update on application_decisions is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
update public.application_decisions set decision_type = 'rejected';

-- probe: S10 direct delete on application_decisions is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
delete from public.application_decisions;

-- probe: S10 direct insert on application_offers is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
insert into public.application_offers (application_id, token_hash) values ('9e060000-0000-4000-8000-000400000001', md5('z') || md5('y'));

-- probe: S10 direct update on application_offers is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
update public.application_offers set response = 'withdrawn';

-- probe: S10 direct delete on application_offers is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
delete from public.application_offers;

-- probe: S10 direct insert on admissions_capacity is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
insert into public.admissions_capacity (academic_year, grade_id, capacity) select '2030/2031', id, 1 from public.admissions_grades limit 1;

-- probe: S10 direct update on admissions_capacity is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
update public.admissions_capacity set capacity = 9;

-- probe: S10 direct delete on admissions_capacity is denied for every role
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
-- as role:
delete from public.admissions_capacity;

-- ================================================================ SQL helpers

-- probe: S11 _admissions_grade_id agrees with admissions_grade_band for every grade and its case and whitespace variants
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$
declare g record; v text; n int := 0;
begin
  for g in select id, name, band from public.admissions_grades loop
    foreach v in array array[g.name, upper(g.name), lower(g.name), '  ' || g.name || '  ', replace(g.name, ' ', '    '), E'\t' || g.name || E'\n'] loop
      if public._admissions_grade_id(v) is distinct from g.id then
        raise exception 'grade id wrong for [%]', v;
      end if;
      if public.admissions_grade_band(v) is distinct from g.band then
        raise exception 'band disagrees for [%]', v;
      end if;
      n := n + 1;
    end loop;
  end loop;
  if n < 60 then raise exception 'too few grades checked: %', n; end if;
end $$;

-- probe: S11b _admissions_grade_id is null where admissions_grade_band is null
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$
declare v text;
begin
  foreach v in array array['Grade 11', '2027', '', ' ', 'Other: Year 13', 'Grade', 'Grade3'] loop
    if public._admissions_grade_id(v) is not null then raise exception 'expected null for [%]', v; end if;
    if public.admissions_grade_band(v) is not null then raise exception 'band not null for [%]', v; end if;
  end loop;
  if public._admissions_grade_id(null) is not null then raise exception 'null input gave a grade'; end if;
end $$;

-- probe: S12 _offer_effective_response: only a pending offer past its expiry reads as expired
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$ begin
  if public._offer_effective_response('pending', now() - interval '1 second') is distinct from 'expired' then raise exception 'past pending not expired'; end if;
  if public._offer_effective_response('pending', now() + interval '1 hour') is distinct from 'pending' then raise exception 'future pending changed'; end if;
  if public._offer_effective_response('pending', null) is distinct from 'pending' then raise exception 'no-expiry pending changed'; end if;
  if public._offer_effective_response('accepted', now() - interval '1 day') is distinct from 'accepted' then raise exception 'accepted rewritten'; end if;
  if public._offer_effective_response('declined', now() - interval '1 day') is distinct from 'declined' then raise exception 'declined rewritten'; end if;
  if public._offer_effective_response('withdrawn', now() - interval '1 day') is distinct from 'withdrawn' then raise exception 'withdrawn rewritten'; end if;
  if public._offer_effective_response('expired', now() + interval '1 day') is distinct from 'expired' then raise exception 'expired rewritten'; end if;
  if public._offer_effective_response(null, now()) is not null then raise exception 'null response rewritten'; end if;
end $$;

-- probe: S12b _offer_effective_response uses the live clock, not the transaction start
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$
declare t timestamptz := now() + interval '100 milliseconds';
begin
  perform pg_sleep(0.4);
  if public._offer_effective_response('pending', t) is distinct from 'expired' then
    raise exception 'frozen clock: an offer that expired during this transaction still reads pending';
  end if;
end $$;

-- ================================================================ race guards (a single session can't race itself, so the lock and the re-check are pinned by source)

-- probe: S13 both decision RPCs lock the application row, then re-check scope under the lock
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text; d text;
begin
  foreach f in array array['public.record_decision(uuid, text, text)', 'public.change_decision(uuid, text, text)'] loop
    d := pg_get_functiondef(f::regprocedure);
    if d !~ 'select \* into v_app from public\.applications where id = p_application_id for update' then
      raise exception '% does not lock the application row', f;
    end if;
    if (select count(*) from regexp_matches(d, 'admissions_grade_visible\(v_app\.year_group_applied_for\)', 'g')) <> 1 then
      raise exception '% does not re-check scope under the lock', f;
    end if;
    if d !~ 'admissions_application_visible\(p_application_id\)' then
      raise exception '% lost the first scope check', f;
    end if;
    if position('for update' in d) > position('v_app.stage in' in d) then
      raise exception '% locks after the stage check', f;
    end if;
  end loop;
  d := pg_get_functiondef('public.change_decision(uuid, text, text)'::regprocedure);
  if d !~ 'from public\.application_decisions\s+where application_id = p_application_id for update'
     or d !~ 'from public\.application_offers\s+where application_id = p_application_id for update' then
    raise exception 'change_decision does not lock the decision and offer rows';
  end if;
end $$;
