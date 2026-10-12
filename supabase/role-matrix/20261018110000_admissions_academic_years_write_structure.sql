-- Structure probes for 20261018110000_admissions_academic_years_write
-- (admissions slice 7b2, docs/admissions/PORT-PLAN.md): grants, security
-- definer, the audit trigger, the unchanged capacity signature and the
-- anon-executable count.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261018110000_admissions_academic_years_write_structure.sql

-- probe: S1 the new functions: security definer, search_path set, no anon or public execute
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  foreach f in array array['public._require_admissions_year_manager()', 'public.add_admissions_academic_year(text)', 'public.set_admissions_academic_year_active(text, boolean)', 'public.audit_admissions_academic_year()', 'public.create_admissions_capacity(text, uuid, uuid, integer)'] loop
    if not (select prosecdef from pg_proc where oid = f::regprocedure) then
      raise exception '% is not security definer', f;
    end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=public']) then
      raise exception '% has no search_path', f;
    end if;
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'anon can execute %', f;
    end if;
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f::regprocedure and a.grantee = 0) then
      raise exception 'public can execute %', f;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: S2 authenticated executes the two RPCs and capacity creation, never the helper or the trigger function
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  foreach f in array array['public.add_admissions_academic_year(text)', 'public.set_admissions_academic_year_active(text, boolean)', 'public.create_admissions_capacity(text, uuid, uuid, integer)'] loop
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'authenticated cannot execute %', f;
    end if;
  end loop;
  foreach f in array array['public._require_admissions_year_manager()', 'public.audit_admissions_academic_year()'] loop
    if has_function_privilege('authenticated', f, 'execute') then
      raise exception 'authenticated can execute %', f;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: S3 the audit trigger: exactly one, after insert or update of is_active, row level
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(tgname::text order by tgname) from pg_trigger
      where tgrelid = 'public.admissions_academic_years'::regclass and not tgisinternal)
     is distinct from array['admissions_academic_years_audit'] then
    raise exception 'trigger list changed';
  end if;
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'public.admissions_academic_years'::regclass
      and t.tgname = 'admissions_academic_years_audit'
      and t.tgfoid = 'public.audit_admissions_academic_year()'::regprocedure
      and t.tgenabled = 'O'
      and pg_get_triggerdef(t.oid) like '%AFTER INSERT OR UPDATE OF is_active ON public.admissions_academic_years FOR EACH ROW%'
  ) then
    raise exception 'audit trigger missing or changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: S4 the audit CHECK still allows the action (7b1 S2 owns the exact list)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.audit_log'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%''admissions_academic_year_changed''%'
  ) then
    raise exception 'action missing from the audit CHECK';
  end if;
end $$;
-- as role:
select 1;

-- probe: S5 one overload each, capacity creation keeps its 6a argument list
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare n text;
begin
  foreach n in array array['add_admissions_academic_year', 'set_admissions_academic_year_active', 'create_admissions_capacity', '_require_admissions_year_manager', 'audit_admissions_academic_year'] loop
    if (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
        where s.nspname = 'public' and p.proname = n) <> 1 then
      raise exception '% is not exactly one function', n;
    end if;
  end loop;
  if pg_get_function_identity_arguments('public.create_admissions_capacity(text, uuid, uuid, integer)'::regprocedure)
     <> 'p_academic_year text, p_grade_id uuid, p_branch_id uuid, p_capacity integer' then
    raise exception 'capacity signature changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: S6 table grants unchanged: authenticated select only, nothing for anon
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if has_table_privilege('anon', 'public.admissions_academic_years', 'select,insert,update,delete') then
    raise exception 'anon holds a privilege';
  end if;
  if has_table_privilege('authenticated', 'public.admissions_academic_years', 'insert,update,delete,truncate') then
    raise exception 'authenticated holds a write privilege';
  end if;
  if not has_table_privilege('authenticated', 'public.admissions_academic_years', 'select') then
    raise exception 'authenticated lost select';
  end if;
end $$;
-- as role:
select 1;

-- probe: S7 anon-executable function count in public stays 169
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare v integer;
begin
  select count(*) into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if v <> 169 then raise exception 'anon-executable count is %', v; end if;
end $$;
-- as role:
select 1;
