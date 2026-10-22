-- Role matrix for 20261016100000_admissions_offers_enrolment, STRUCTURE file (admissions slice 6b,
-- docs/admissions/PORT-PLAN.md): grants and settings of the
-- twelve new functions, the exact 170 anon-executable count, the exact
-- 35-value audit list (owned from slice 7b1 on by that slice's structure file),
-- triggers, admissions_settings and the offer status view's shape and
-- grants, the helpers' behaviour, the token minting by source, and the lock
-- order and re-checks by source (S13: a single session can't race itself).
-- Catalog probes raise on failure and expect every role.
-- All fixture rows are invented (ids 9e06b000-...). Capabilities are set
-- inside each probe's rolled-back setup.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261016100000_admissions_offers_enrolment_structure.sql

-- probe: S1 helpers and trigger functions: no execute for anon, authenticated or service_role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._admissions_grade_code(text)', 'public._next_admissions_student_id(text, integer)', 'public._settle_offer_expiry(uuid)', 'public.guard_student_id()', 'public.audit_application_offer()', 'public.audit_admissions_settings()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable', f;
    end if;
  end loop;
end $$;

-- probe: S2 staff RPCs: not anon; authenticated and service_role yes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public.generate_offer(uuid)', 'public.reset_offer(uuid)', 'public.record_offer_response(uuid, text)', 'public.mark_enrolled(uuid)', 'public.set_admissions_offer_ttl_days(integer)'] loop
    if has_function_privilege('anon', f, 'execute')
       or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception 'grants wrong on %', f;
    end if;
  end loop;
end $$;

-- probe: S2b settle_expired_offers: service_role only
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if has_function_privilege('anon', 'public.settle_expired_offers()', 'execute')
     or has_function_privilege('authenticated', 'public.settle_expired_offers()', 'execute')
     or not has_function_privilege('service_role', 'public.settle_expired_offers()', 'execute') then
    raise exception 'sweep grants wrong';
  end if;
end $$;

-- probe: S3 none of the twelve functions carries a PUBLIC grant
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._admissions_grade_code(text)', 'public._next_admissions_student_id(text, integer)', 'public._settle_offer_expiry(uuid)', 'public.guard_student_id()', 'public.audit_application_offer()', 'public.audit_admissions_settings()', 'public.generate_offer(uuid)', 'public.reset_offer(uuid)', 'public.record_offer_response(uuid, text)', 'public.mark_enrolled(uuid)', 'public.set_admissions_offer_ttl_days(integer)', 'public.settle_expired_offers()'] loop
    if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where p.oid = f::regprocedure and a.grantee = 0) then
      raise exception '% is granted to PUBLIC', f;
    end if;
  end loop;
end $$;

-- Changed in slice 11 (20261031100000/20261031110000): generate_offer and reset_offer no longer mint a
-- token, so they no longer need extensions on their search_path.
-- probe: S4 definers pin search_path; invoker helpers
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  foreach f in array array['public._next_admissions_student_id(text, integer)', 'public._settle_offer_expiry(uuid)', 'public.audit_application_offer()', 'public.audit_admissions_settings()', 'public.audit_application_stage()', 'public.record_offer_response(uuid, text)', 'public.mark_enrolled(uuid)', 'public.set_admissions_offer_ttl_days(integer)', 'public.settle_expired_offers()'] loop
    if not (select prosecdef and coalesce('search_path=public' = any (proconfig), false) from pg_proc where oid = f::regprocedure) then
      raise exception '% lost security definer or its search_path', f;
    end if;
  end loop;
  foreach f in array array['public.generate_offer(uuid)', 'public.reset_offer(uuid)'] loop
    if not (select prosecdef and coalesce('search_path=public' = any (proconfig), false) from pg_proc where oid = f::regprocedure) then
      raise exception '% lost security definer or its search_path', f;
    end if;
  end loop;
  if (select prosecdef or not coalesce('search_path=""' = any (proconfig), false) or provolatile <> 's'
      from pg_proc where oid = 'public._admissions_grade_code(text)'::regprocedure) then
    raise exception '_admissions_grade_code settings wrong';
  end if;
  if (select prosecdef or not coalesce('search_path=public' = any (proconfig), false)
      from pg_proc where oid = 'public.guard_student_id()'::regprocedure) then
    raise exception 'guard_student_id settings wrong';
  end if;
end $$;

-- probe: S5 anon can still execute exactly 170 public functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable count changed';
  end if;
end $$;

-- probe: S5b each new or replaced function exists exactly once
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare n text;
begin
  foreach n in array array['_admissions_grade_code', '_next_admissions_student_id', '_settle_offer_expiry', 'guard_student_id', 'audit_application_offer', 'audit_admissions_settings', 'generate_offer', 'reset_offer', 'record_offer_response', 'mark_enrolled', 'set_admissions_offer_ttl_days', 'settle_expired_offers', 'audit_application_stage', '_offer_effective_response'] loop
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = n) <> 1 then
      raise exception 'overload count wrong for %', n;
    end if;
  end loop;
end $$;

-- probe: S6 the audit action list still holds the 35 values (7b1's structure file owns the exact list)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(m[1] order by m[1]) from pg_constraint c,
        regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') m
      where c.conname = 'audit_log_action_check')
     @> array['admissions_capabilities_changed', 'admissions_capacity_changed', 'admissions_settings_changed', 'application_decision_changed', 'application_document_status_changed', 'application_offer_changed', 'application_stage_changed', 'discount_applied', 'employee_approved', 'employee_created', 'employee_reactivated', 'employee_rejected', 'employee_suspended', 'employees_imported', 'expense_voided', 'invoice_voided', 'pay_config_amended_and_approved', 'pay_config_approved', 'pay_config_exemptions_changed', 'pay_config_proposed', 'pay_config_rejected', 'payroll_run_approved', 'payroll_run_exclusion_added', 'payroll_run_exclusion_removed', 'payroll_run_rejected', 'payroll_run_submitted', 'return_processed', 'sale_voided', 'staff_advance_approved', 'staff_advance_change_approved', 'staff_advance_change_proposed', 'staff_advance_change_rejected', 'staff_advance_proposed', 'staff_advance_rejected', 'vat_override'] is not true then
    raise exception 'audit action list wrong';
  end if;
end $$;

-- probe: S6b the two new audit actions insert; a near miss is refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select s.branch_id, s.id, 'application_offer_changed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select s.branch_id, s.id, 'admissions_settings_changed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
do $$ begin
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
  select s.branch_id, s.id, 'application_offer_reset', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
  raise exception 'not refused';
exception when check_violation then null; end $$;

-- probe: S7 triggers on offers, settings and students
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(tgname::text) from pg_trigger where not tgisinternal and tgrelid = 'public.application_offers'::regclass)
     is distinct from array['application_offers_audit'] then
    raise exception 'offers triggers wrong';
  end if;
  if (select array_agg(tgname::text order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.admissions_settings'::regclass)
     is distinct from array['admissions_settings_audit', 'admissions_settings_set_updated_at'] then
    raise exception 'settings triggers wrong';
  end if;
  if (select array_agg(tgname::text) from pg_trigger where not tgisinternal and tgrelid = 'public.students'::regclass)
     is distinct from array['students_guard_student_id'] then
    raise exception 'students triggers wrong';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'application_offers_audit' and pg_get_triggerdef(oid) ~ 'AFTER INSERT OR UPDATE ON public.application_offers FOR EACH ROW EXECUTE FUNCTION audit_application_offer\(\)') then
    raise exception 'offers audit trigger definition wrong';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'admissions_settings_audit' and pg_get_triggerdef(oid) ~ 'AFTER UPDATE ON public.admissions_settings FOR EACH ROW EXECUTE FUNCTION audit_admissions_settings\(\)') then
    raise exception 'settings audit trigger definition wrong';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'students_guard_student_id' and pg_get_triggerdef(oid) ~ 'BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION guard_student_id\(\)') then
    raise exception 'student ID guard definition wrong';
  end if;
end $$;

-- probe: S8 admissions_settings: one row, default 14, RLS on, one select policy, grants
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$ begin
  if (select count(*) from public.admissions_settings) <> 1
     or (select offer_ttl_days from public.admissions_settings where id = 1) <> 14 then
    raise exception 'settings row wrong';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.admissions_settings'::regclass) then
    raise exception 'RLS off';
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'admissions_settings') <> 1
     or (select cmd from pg_policies where schemaname = 'public' and tablename = 'admissions_settings') <> 'SELECT' then
    raise exception 'policies wrong';
  end if;
  if has_table_privilege('authenticated', 'public.admissions_settings', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated', 'public.admissions_settings', 'SELECT')
     or has_table_privilege('anon', 'public.admissions_settings', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role', 'public.admissions_settings', 'INSERT,DELETE,TRUNCATE')
     or not has_table_privilege('service_role', 'public.admissions_settings', 'SELECT,UPDATE') then
    raise exception 'grants wrong';
  end if;
end $$;

-- probe: S8b settings: a second row and a TTL of 0 or 91 are refused; 1 and 90 accepted
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$ begin
  insert into public.admissions_settings (id) values (2);
  raise exception 'not refused';
exception when check_violation then null; end $$;
do $$ begin
  update public.admissions_settings set offer_ttl_days = 0;
  raise exception 'not refused';
exception when check_violation then null; end $$;
do $$ begin
  update public.admissions_settings set offer_ttl_days = 91;
  raise exception 'not refused';
exception when check_violation then null; end $$;
update public.admissions_settings set offer_ttl_days = 1;
update public.admissions_settings set offer_ttl_days = 90;

-- probe: S9 the offer status view: invoker, no token_hash, select-only grants
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not coalesce((select 'security_invoker=true' = any (reloptions) from pg_class where oid = 'public.application_offer_status'::regclass), false) then
    raise exception 'view is not security_invoker';
  end if;
  if (select array_agg(attname::text order by attnum) from pg_attribute
      where attrelid = 'public.application_offer_status'::regclass and attnum > 0 and not attisdropped)
     is distinct from array['id', 'application_id', 'sent_at', 'expires_at', 'response', 'responded_at', 'effective_response',
                            'response_source', 'link_generation'] then  -- the last two from slice 11
    raise exception 'view columns wrong';
  end if;
  if pg_get_viewdef('public.application_offer_status'::regclass) ~ 'token' then
    raise exception 'view mentions the token';
  end if;
  if has_table_privilege('authenticated', 'public.application_offer_status', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or not has_table_privilege('authenticated', 'public.application_offer_status', 'SELECT')
     or has_table_privilege('anon', 'public.application_offer_status', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
    raise exception 'view grants wrong';
  end if;
end $$;

-- probe: S10 view effective_response agrees with _offer_effective_response row by row
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 second', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '1 hour', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', null, 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000004');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000004', '9e06b000-0000-4000-8000-000100000004', 'Child 4 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000004', '9e06b000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000004', encode(extensions.digest('seed4', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 day', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000005');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000005', '9e06b000-0000-4000-8000-000100000005', 'Child 5 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000005', '9e06b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000005', encode(extensions.digest('seed5', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 day', 'declined');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000006');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000006', '9e06b000-0000-4000-8000-000100000006', 'Child 6 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000006', '9e06b000-0000-4000-8000-000300000006', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000006', encode(extensions.digest('seed6', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 day', 'withdrawn');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000007');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000007', '9e06b000-0000-4000-8000-000100000007', 'Child 7 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000007', '9e06b000-0000-4000-8000-000300000007', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000007', encode(extensions.digest('seed7', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '1 day', 'expired');
-- as role:
reset role;
do $$ begin
  if (select count(*) from public.application_offer_status) < 7 then raise exception 'rows missing'; end if;
  if exists (select 1 from public.application_offer_status v join public.application_offers o on o.id = v.id
             where v.effective_response is distinct from public._offer_effective_response(o.response, o.expires_at)
                or v.response is distinct from o.response) then
    raise exception 'view disagrees with the helper';
  end if;
  if (select array_agg(effective_response order by application_id) from public.application_offer_status
      where application_id::text like '9e06b000%')
     is distinct from array['expired', 'pending', 'pending', 'accepted', 'declined', 'withdrawn', 'expired'] then
    raise exception 'effective responses wrong';
  end if;
end $$;

-- probe: S11 _admissions_grade_code: every grade's code with case and whitespace variants; null when unbanded
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$
declare g record; v text;
begin
  for g in select name, classification_code from public.admissions_grades loop
    foreach v in array array[g.name, upper(g.name), '  ' || g.name || '  ', replace(g.name, ' ', '   ')] loop
      if public._admissions_grade_code(v) is distinct from g.classification_code then
        raise exception 'code wrong for [%]', v;
      end if;
    end loop;
  end loop;
  foreach v in array array['Grade 11', '2027', 'Other: Year 13', ''] loop
    if public._admissions_grade_code(v) is not null then raise exception 'expected null for [%]', v; end if;
  end loop;
  if public._admissions_grade_code('Grade 3') <> '03' or public._admissions_grade_code('Nursery 1') is null then
    raise exception 'fixture codes wrong';
  end if;
end $$;

-- probe: S12 _next_admissions_student_id: YYPPNNNN from the counter, skips a held number, refuses a bad code
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', '27030002');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
-- as role:
reset role;
do $$ begin
  if public._next_admissions_student_id('03', 2027) <> '27030001' then raise exception 'first id wrong'; end if;
  if public._next_admissions_student_id('03', 2027) <> '27030003' then raise exception 'held number not skipped'; end if;
  if public._next_admissions_student_id('01', 2027) <> '27010001' then raise exception 'codes share a counter'; end if;
  if public._next_admissions_student_id('03', 2105) <> '05030001' then raise exception 'year not two digits'; end if;
  if (select next_value from public.admissions_reference_counters where key = 'STUDENT-27-03') <> 4 then
    raise exception 'counter wrong';
  end if;
  begin
    perform public._next_admissions_student_id(null, 2027);
    raise exception 'null code not refused';
  exception when others then if sqlerrm not like 'Unknown student ID classification%' then raise; end if;
  end;
  begin
    perform public._next_admissions_student_id('10', 2027);
    raise exception 'code 10 not refused';
  exception when others then if sqlerrm not like 'Unknown student ID classification%' then raise; end if;
  end;
end $$;

-- probe: S12b _next_admissions_student_id widens past 9999, never truncates
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
insert into public.admissions_reference_counters (key, next_value) values ('STUDENT-27-04', 9999);
do $$ begin
  if public._next_admissions_student_id('04', 2027) <> '27049999' then raise exception '9999 wrong'; end if;
  if public._next_admissions_student_id('04', 2027) <> '270410000' then raise exception '10000 wrong'; end if;
end $$;

-- probe: S14 students, offers, decisions: still select-only for authenticated
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare t text;
begin
  foreach t in array array['public.students', 'public.application_offers', 'public.application_decisions', 'public.applications'] loop
    if has_table_privilege('authenticated', t, 'INSERT,UPDATE,DELETE,TRUNCATE')
       or not (has_table_privilege('authenticated', t, 'SELECT')
                or (t = 'public.application_offers'
                    and has_column_privilege('authenticated', t, 'application_id', 'SELECT')))
       or has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then
      raise exception 'grants changed on %', t;
    end if;
  end loop;
end $$;

-- Changed in slice 11 (20261031100000/20261031110000): the copy link is retired (D-11d). Offer tokens are
-- minted only by issue_offer_link at send time, which the slice 11 probes pin.
-- probe: S15 generate_offer and reset_offer mint no token and store no hash
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text; d text;
begin
  foreach f in array array['public.generate_offer(uuid)', 'public.reset_offer(uuid)'] loop
    d := pg_get_functiondef(f::regprocedure);
    if d ~ 'gen_random_bytes' or d ~ 'digest\(' or d ~ 'v_token' then
      raise exception '% still mints or hashes a token', f;
    end if;
  end loop;
end $$;

-- correct_application_grade (7b1) is not in this list on purpose: it takes only the
-- application lock, which 20261018100000_admissions_grade_correction_structure.sql S5 pins.
-- probe: S13 accept and enrol paths: lock application, decision, offer, student, counter; re-check under the locks
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare
  f text; d text;
  p_app int; p_dec int; p_off int; p_stu int; p_cnt int;
begin
  foreach f in array array['public.generate_offer(uuid)', 'public.reset_offer(uuid)', 'public.record_offer_response(uuid, text)', 'public.mark_enrolled(uuid)'] loop
    d := pg_get_functiondef(f::regprocedure);
    p_app := position('select * into v_app from public.applications where id = p_application_id for update' in d);
    p_dec := position(E'from public.application_decisions\n  where application_id = p_application_id for update' in d);
    if p_app = 0 then raise exception '% does not lock the application', f; end if;
    if p_dec = 0 or p_dec < p_app then raise exception '% does not lock the decision after the application', f; end if;
    if position('v_decision.decision_type <> ''accepted''' in d) < p_dec then
      raise exception '% does not check the decision under its lock', f;
    end if;
    if position('v_app.stage' in d) < p_app then raise exception '% checks the stage before the lock', f; end if;
    if f <> 'public.mark_enrolled(uuid)' then
      if d !~ 'admissions_application_visible\(p_application_id\)' then raise exception '% lost the first scope check', f; end if;
      if position('admissions_grade_visible(v_app.year_group_applied_for)' in d) < p_app then
        raise exception '% does not re-check scope under the lock', f;
      end if;
    end if;
  end loop;
  foreach f in array array['public.reset_offer(uuid)', 'public.record_offer_response(uuid, text)', 'public.mark_enrolled(uuid)'] loop
    d := pg_get_functiondef(f::regprocedure);
    p_dec := position(E'from public.application_decisions\n  where application_id = p_application_id for update' in d);
    p_off := position(E'from public.application_offers\n  where application_id = p_application_id for update' in d);
    if p_off = 0 or p_off < p_dec then raise exception '% does not lock the offer after the decision', f; end if;
  end loop;
  d := pg_get_functiondef('public.record_offer_response(uuid, text)'::regprocedure);
  p_off := position(E'from public.application_offers\n  where application_id = p_application_id for update' in d);
  if position('v_effective := public._offer_effective_response(v_offer.response, v_offer.expires_at)' in d) < p_off
     or position('if v_effective <> ''pending''' in d) < p_off then
    raise exception 'record_offer_response does not re-check pending and expiry under the offer lock';
  end if;
  d := pg_get_functiondef('public.mark_enrolled(uuid)'::regprocedure);
  p_off := position(E'from public.application_offers\n  where application_id = p_application_id for update' in d);
  p_stu := position('select * into v_student from public.students where id = v_app.student_id for update' in d);
  p_cnt := position('public._next_admissions_student_id(' in d);
  if position('_offer_effective_response(v_offer.response, v_offer.expires_at) <> ''accepted''' in d) < p_off then
    raise exception 'mark_enrolled does not check the offer under its lock';
  end if;
  if p_stu = 0 or p_stu < p_off then raise exception 'mark_enrolled does not lock the student after the offer'; end if;
  if p_cnt = 0 or p_cnt < p_stu then raise exception 'mark_enrolled takes the counter before the student lock'; end if;
  if position('stage = ''enrolled'' and id <> p_application_id' in d) < p_stu then
    raise exception 'mark_enrolled checks for a same-year enrolment before the student lock';
  end if;
  if position('v_student.student_id is null' in d) < p_stu then
    raise exception 'mark_enrolled reads the student ID before the student lock';
  end if;
  d := pg_get_functiondef('public._settle_offer_expiry(uuid)'::regprocedure);
  p_app := position('from public.applications where id = p_application_id for update' in d);
  p_off := position(E'from public.application_offers\n  where application_id = p_application_id for update' in d);
  if p_app = 0 or p_off < p_app then raise exception '_settle_offer_expiry lock order wrong'; end if;
  if position('v_offer.response <> ''pending''' in d) < p_off then
    raise exception '_settle_offer_expiry does not re-check under the offer lock';
  end if;
end $$;
