-- Role matrix for 20261018100000_admissions_grade_correction, STRUCTURE
-- file (admissions slice 7b1, docs/admissions/PORT-PLAN.md): grants and
-- settings of the two new functions, the exact 170 anon-executable count,
-- the exact 37-value audit list (this file owns the exact list from slice
-- 7b1 on), the grade audit trigger, the offers column grant, the band and
-- code equivalence the screens rely on, and the grade correction's lock by
-- source (S5; 6b's S13 covers the accept and enrol paths, which take the
-- full lock order).
-- Catalog probes raise on failure and expect every role.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261018100000_admissions_grade_correction_structure.sql

-- probe: S1 grants: the RPC for authenticated and service_role only; the trigger function for nobody; no PUBLIC
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare f text;
begin
  f := 'public.correct_application_grade(uuid, uuid)';
  if has_function_privilege('anon', f, 'execute')
     or not has_function_privilege('authenticated', f, 'execute')
     or not has_function_privilege('service_role', f, 'execute') then
    raise exception 'grants wrong on %', f;
  end if;
  f := 'public.audit_application_grade()';
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception '% is executable', f;
  end if;
  foreach f in array array['public.correct_application_grade(uuid, uuid)', 'public.audit_application_grade()'] loop
    if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where p.oid = f::regprocedure and a.grantee = 0) then
      raise exception '% is granted to PUBLIC', f;
    end if;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname = split_part(split_part(f, '.', 2), '(', 1)) <> 1 then
      raise exception 'overload count wrong for %', f;
    end if;
    if not (select prosecdef and coalesce('search_path=public' = any (proconfig), false)
            from pg_proc where oid = f::regprocedure) then
      raise exception '% lost security definer or its search_path', f;
    end if;
  end loop;
end $$;

-- probe: S2 the audit action list has exactly the 40 values
-- (37 until 20261026100000_hr_staff_numbers added position_staff_class_changed,
-- staff_number_issued and staff_number_retired)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(m[1] order by m[1]) from pg_constraint c,
        regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') m
      where c.conname = 'audit_log_action_check')
     is distinct from array['admissions_academic_year_changed', 'admissions_capabilities_changed', 'admissions_capacity_changed', 'admissions_settings_changed', 'application_decision_changed', 'application_document_status_changed', 'application_grade_corrected', 'application_offer_changed', 'application_stage_changed', 'discount_applied', 'employee_approved', 'employee_created', 'employee_reactivated', 'employee_rejected', 'employee_suspended', 'employees_imported', 'expense_voided', 'invoice_voided', 'pay_config_amended_and_approved', 'pay_config_approved', 'pay_config_exemptions_changed', 'pay_config_proposed', 'pay_config_rejected', 'payroll_run_approved', 'payroll_run_exclusion_added', 'payroll_run_exclusion_removed', 'payroll_run_rejected', 'payroll_run_submitted', 'position_staff_class_changed', 'return_processed', 'sale_voided', 'staff_advance_approved', 'staff_advance_change_approved', 'staff_advance_change_proposed', 'staff_advance_change_rejected', 'staff_advance_proposed', 'staff_advance_rejected', 'staff_number_issued', 'staff_number_retired', 'vat_override'] then
    raise exception 'audit action list wrong';
  end if;
end $$;

-- probe: S2b the two new audit actions insert; a near miss is refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select s.branch_id, s.id, 'application_grade_corrected', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select s.branch_id, s.id, 'admissions_academic_year_changed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
do $$ begin
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
  select s.branch_id, s.id, 'application_grade_changed', 'x', 'y' from public.staff s where s.role = 'Manager' limit 1;
  raise exception 'not refused';
exception when check_violation then null; end $$;

-- probe: S3 anon can still execute exactly 170 public functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable count changed';
  end if;
end $$;

-- probe: S4 the grade audit trigger: after update of the grade column only, on applications
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(tgname::text order by tgname) from pg_trigger where not tgisinternal and tgrelid = 'public.applications'::regclass)
     is distinct from array['applications_assign_references', 'applications_audit_grade', 'applications_audit_stage', 'applications_guard_update', 'applications_set_updated_at'] then
    raise exception 'applications triggers wrong';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'applications_audit_grade'
                 and pg_get_triggerdef(oid) ~ 'AFTER UPDATE OF year_group_applied_for ON public.applications FOR EACH ROW EXECUTE FUNCTION audit_application_grade\(\)') then
    raise exception 'grade audit trigger definition wrong';
  end if;
end $$;

-- probe: S5 correct_application_grade: role, then scope, then the application lock with every state check under it; no other lock
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare d text; p_role int; p_scope int; p_lock int;
begin
  d := pg_get_functiondef('public.correct_application_grade(uuid, uuid)'::regprocedure);
  p_role := position('if v_staff.role <> ''Manager'' then' in d);
  p_scope := position('not public.admissions_application_visible(p_application_id)' in d);
  p_lock := position('select * into v_app from public.applications where id = p_application_id for update' in d);
  if p_role = 0 or p_scope < p_role then raise exception 'scope checked before the role'; end if;
  if p_lock = 0 or p_lock < p_scope then raise exception 'application not locked after the scope check'; end if;
  if position('admissions_grade_visible(v_app.year_group_applied_for)' in d) < p_lock then
    raise exception 'scope not re-checked under the lock';
  end if;
  if position('v_app.stage = ''enrolled''' in d) < p_lock then raise exception 'stage checked before the lock'; end if;
  if position('public._admissions_grade_id(v_app.year_group_applied_for) is not null' in d) < p_lock then
    raise exception 'narrow rule checked before the lock';
  end if;
  if position('v_app.branch_id' in d) < p_lock then raise exception 'campus rules checked before the lock'; end if;
  if (select count(*) from regexp_matches(d, 'for update', 'gi')) <> 1 then
    raise exception 'takes a lock other than the application';
  end if;
  if d ~ 'application_decisions|application_offers|public\.students|_next_admissions_student_id|reference_counters' then
    raise exception 'touches a row outside the application';
  end if;
end $$;

-- probe: S6 a grade's band is null exactly when it has no student ID code (the screens show the band, mark_enrolled reads the code)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$
declare v text;
begin
  foreach v in array array['Grade 3', 'Nursery 1', 'Grade 9', 'Grade 11', '2027', 'Other', 'Year 13 (typed)'] loop
    if (public.admissions_grade_band(v) is null) <> (public._admissions_grade_code(v) is null) then
      raise exception 'band and code disagree for [%]', v;
    end if;
  end loop;
  if exists (select 1 from public.admissions_grades where (band is null) <> (classification_code is null)) then
    raise exception 'a grade row has a band without a code or the reverse';
  end if;
end $$;

-- probe: S7 offers: authenticated selects exactly the six non-token columns, with no table-level select
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare c text;
begin
  if has_table_privilege('authenticated', 'public.application_offers', 'SELECT') then
    raise exception 'table-level select still granted';
  end if;
  if has_column_privilege('authenticated', 'public.application_offers', 'token_hash', 'SELECT') then
    raise exception 'token_hash readable';
  end if;
  foreach c in array array['id', 'application_id', 'sent_at', 'expires_at', 'response', 'responded_at'] loop
    if not has_column_privilege('authenticated', 'public.application_offers', c, 'SELECT') then
      raise exception '% not readable', c;
    end if;
  end loop;
  if (select count(*) from pg_attribute where attrelid = 'public.application_offers'::regclass and attnum > 0 and not attisdropped) <> 7 then
    raise exception 'application_offers columns changed: grant any new column explicitly';
  end if;
  if has_any_column_privilege('anon', 'public.application_offers', 'SELECT')
     or has_table_privilege('authenticated', 'public.application_offers', 'INSERT,UPDATE,DELETE,TRUNCATE')
     or not has_table_privilege('service_role', 'public.application_offers', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'other offers grants changed';
  end if;
end $$;
