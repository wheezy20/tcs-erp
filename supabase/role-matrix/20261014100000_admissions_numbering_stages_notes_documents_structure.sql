-- Role matrix for 20261014100000_admissions_numbering_stages_notes_documents, STRUCTURE file (admissions slice 5,
-- docs/admissions/PORT-PLAN.md): the counters table locked to every API
-- role, function grants and settings, triggers, the 31-value audit list,
-- the counter key check, and unchanged table grants. Catalog probes raise
-- on failure and expect every role; direct counter access expects none.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261014100000_admissions_numbering_stages_notes_documents_structure.sql

-- ================================================================ counters table: locked to every API role

-- probe: A1 counters: RLS on, no policy, no privilege for anon, authenticated or service_role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare r text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.admissions_reference_counters'::regclass)
     or exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'admissions_reference_counters') then
    raise exception 'RLS or policy wrong';
  end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_table_privilege(r, 'public.admissions_reference_counters', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception '% holds a privilege on the counters', r;
    end if;
  end loop;
end $$;

-- probe: A2 select on the counters is denied
-- expect: none
insert into public.admissions_reference_counters (key, next_value) values ('INQ-2098', 5);
-- as role:
select * from public.admissions_reference_counters;

-- probe: A2 insert on the counters is denied
-- expect: none
insert into public.admissions_reference_counters (key, next_value) values ('INQ-2098', 5);
-- as role:
insert into public.admissions_reference_counters (key, next_value) values ('INQ-2099', 1);

-- probe: A2 update on the counters is denied
-- expect: none
insert into public.admissions_reference_counters (key, next_value) values ('INQ-2098', 5);
-- as role:
update public.admissions_reference_counters set next_value = 1;

-- probe: A2 delete on the counters is denied
-- expect: none
insert into public.admissions_reference_counters (key, next_value) values ('INQ-2098', 5);
-- as role:
delete from public.admissions_reference_counters;

-- probe: A2 truncate on the counters is denied
-- expect: none
insert into public.admissions_reference_counters (key, next_value) values ('INQ-2098', 5);
-- as role:
truncate public.admissions_reference_counters;

-- probe: A2b service_role can't read or write the counters
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
set local role service_role;
do $$ begin
  perform 1 from public.admissions_reference_counters;
  raise exception 'service_role read the counters';
exception when insufficient_privilege then null; end $$;
do $$ begin
  insert into public.admissions_reference_counters (key) values ('INQ-2097');
  raise exception 'service_role wrote the counters';
exception when insufficient_privilege then null; end $$;
reset role;
-- as role:
select 1;

-- ================================================================ functions, grants and triggers

-- probe: A3 helpers and trigger functions are executable by neither anon nor authenticated
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._admissions_reference_year(timestamptz)', 'public._admissions_sequence_text(integer)', 'public._next_admissions_sequence(text)', 'public._next_admissions_reference(text, integer)', 'public.assign_application_references()', 'public.guard_application_update()', 'public.audit_application_stage()', 'public.audit_application_document_status()', 'public._require_admissions_writer()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception '% is executable', f;
    end if;
  end loop;
end $$;

-- probe: A3b the five RPCs: not anon; authenticated and service_role yes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public.move_application_to_document_review(uuid)', 'public.set_application_stage(uuid, text)', 'public.add_application_note(uuid, text)', 'public.update_application_note(uuid, text)', 'public.set_application_document_status(uuid, text)'] loop
    if has_function_privilege('anon', f, 'execute')
       or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception 'grants wrong on %', f;
    end if;
  end loop;
end $$;

-- probe: A3c definers pin search_path=public; the two SQL helpers pin an empty search_path; the guard is invoker
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (select 1 from pg_proc where oid in ('public._next_admissions_sequence(text)'::regprocedure, 'public._next_admissions_reference(text, integer)'::regprocedure, 'public.assign_application_references()'::regprocedure, 'public.audit_application_stage()'::regprocedure, 'public.audit_application_document_status()'::regprocedure, 'public._require_admissions_writer()'::regprocedure, 'public.move_application_to_document_review(uuid)'::regprocedure, 'public.set_application_stage(uuid, text)'::regprocedure, 'public.add_application_note(uuid, text)'::regprocedure, 'public.update_application_note(uuid, text)'::regprocedure, 'public.set_application_document_status(uuid, text)'::regprocedure)
             and (not prosecdef or not coalesce('search_path=public' = any (proconfig), false))) then
    raise exception 'a definer lost security definer or its search_path';
  end if;
  if exists (select 1 from pg_proc where oid in ('public._admissions_reference_year(timestamptz)'::regprocedure,
                                               'public._admissions_sequence_text(integer)'::regprocedure)
             and (prosecdef or not coalesce('search_path=""' = any (proconfig), false))) then
    raise exception 'SQL helper settings wrong';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.guard_application_update()'::regprocedure) then
    raise exception 'guard should be invoker';
  end if;
end $$;

-- probe: A3d anon can still execute exactly 170 public functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable count changed';
  end if;
end $$;

-- probe: A4 triggers: applications still has these four (7b1's structure S4 owns the exact list), one audit trigger on documents, notes unchanged
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(tgname::text order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.applications'::regclass)
     @> array['applications_assign_references', 'applications_audit_stage', 'applications_guard_update', 'applications_set_updated_at'] is not true then
    raise exception 'applications triggers wrong';
  end if;
  if (select array_agg(tgname::text) from pg_trigger where not tgisinternal and tgrelid = 'public.application_documents'::regclass)
     is distinct from array['application_documents_audit_status'] then
    raise exception 'documents triggers wrong';
  end if;
  if (select array_agg(tgname::text) from pg_trigger where not tgisinternal and tgrelid = 'public.application_notes'::regclass)
     is distinct from array['application_notes_set_identity'] then
    raise exception 'notes triggers wrong';
  end if;
end $$;

-- probe: A5 the audit action list still holds all 31 slice 5 values (the newest slice pins the exact list)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not coalesce((select array_agg(m[1] order by m[1]) from pg_constraint c,
        regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') m
      where c.conname = 'audit_log_action_check')
     @> array['admissions_capabilities_changed', 'application_document_status_changed', 'application_stage_changed', 'discount_applied', 'employee_approved', 'employee_created', 'employee_reactivated', 'employee_rejected', 'employee_suspended', 'employees_imported', 'expense_voided', 'invoice_voided', 'pay_config_amended_and_approved', 'pay_config_approved', 'pay_config_exemptions_changed', 'pay_config_proposed', 'pay_config_rejected', 'payroll_run_approved', 'payroll_run_exclusion_added', 'payroll_run_exclusion_removed', 'payroll_run_rejected', 'payroll_run_submitted', 'return_processed', 'sale_voided', 'staff_advance_approved', 'staff_advance_change_approved', 'staff_advance_change_proposed', 'staff_advance_change_rejected', 'staff_advance_proposed', 'staff_advance_rejected', 'vat_override'], false) then
    raise exception 'audit action list wrong';
  end if;
end $$;

-- probe: A6 counter keys: INQ/APP-YYYY and STUDENT-YY-0P accepted, others refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.admissions_reference_counters (key) values ('INQ-2096'), ('APP-2096'), ('STUDENT-96-03');
do $$ begin
  insert into public.admissions_reference_counters (key) values ('INQ-96');
  raise exception 'not refused';
exception when check_violation then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  insert into public.admissions_reference_counters (key) values ('FOO-2096');
  raise exception 'not refused';
exception when check_violation then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  insert into public.admissions_reference_counters (key) values ('STUDENT-96-10');
  raise exception 'not refused';
exception when check_violation then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  insert into public.admissions_reference_counters (key) values ('STUDENT-2096-03');
  raise exception 'not refused';
exception when check_violation then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  insert into public.admissions_reference_counters (key) values ('APP-2096-0001');
  raise exception 'not refused';
exception when check_violation then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
-- as role:
select 1;

-- probe: A7 applications, notes and documents: authenticated still select only, one policy each
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare t text;
begin
  foreach t in array array['public.applications', 'public.application_notes', 'public.application_documents'] loop
    if has_table_privilege('authenticated', t, 'INSERT,UPDATE,DELETE,TRUNCATE')
       or (select count(*) from pg_policies where schemaname || '.' || tablename = t) <> 1 then
      raise exception 'grants or policies changed on %', t;
    end if;
  end loop;
end $$;

-- probe: A8 no delete RPC for notes or documents; notes have edited_at
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
             and proname ~ '(delete|remove).*(note|document)|(note|document).*(delete|remove)') then
    raise exception 'a delete function exists';
  end if;
  if not exists (select 1 from pg_attribute where attrelid = 'public.application_notes'::regclass
                 and attname = 'edited_at' and not attisdropped) then
    raise exception 'edited_at missing';
  end if;
end $$;
