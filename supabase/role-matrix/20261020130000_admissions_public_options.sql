-- Probes for 20261020130000_admissions_public_options (admissions slice 8,
-- docs/admissions/PORT-PLAN.md): get_public_admissions_options() is the one
-- new anon-executable function (169 to 170), it is read only, and it
-- returns exactly intake_open, active grades, campuses with their accepted
-- grades, and active years.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261020130000_admissions_public_options.sql

-- probe: O1 every role, anon included, can read the options
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
select public.get_public_admissions_options();

-- probe: O2 definer, search_path, stable (read only), no arguments, granted to anon, authenticated and service_role only
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f regprocedure := 'public.get_public_admissions_options()'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = f) then raise exception 'not security definer'; end if;
  if not exists (select 1 from pg_proc where oid = f and proconfig @> array['search_path=public']) then
    raise exception 'no search_path';
  end if;
  if (select provolatile from pg_proc where oid = f) <> 's' then raise exception 'not stable'; end if;
  if (select pronargs from pg_proc where oid = f) <> 0 then raise exception 'takes arguments'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'get_public_admissions_options') <> 1 then
    raise exception 'stray overload';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then
    raise exception 'granted to public';
  end if;
  if not (has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute')
          and has_function_privilege('service_role', f, 'execute')) then
    raise exception 'grant missing';
  end if;
end $$;
-- as role:
select 1;

-- probe: O3 anon can execute exactly 170 public functions, and the only slice 8 one is get_public_admissions_options
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable count is not 170';
  end if;
  if (select array_agg(p.proname::text order by p.proname) from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('get_public_admissions_options', 'submit_inquiry', 'check_public_rate_limit',
                          'set_admissions_public_intake', 'audit_admissions_settings', '_public_rate_limit_rule',
                          '_public_rate_limit_hit', '_require_public_service_caller', '_public_invalid',
                          '_public_only_keys', '_public_text')
        and has_function_privilege('anon', p.oid, 'execute'))
     is distinct from array['get_public_admissions_options'] then
    raise exception 'slice 8 anon surface changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: O4 the result has exactly the four keys, and campus and grade entries exactly their fields
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r jsonb := public.get_public_admissions_options();
begin
  if (select array_agg(k order by k) from jsonb_object_keys(r) k)
     is distinct from array['academic_years', 'applications_open', 'campuses', 'grades', 'intake_open'] then
    raise exception 'top-level keys changed';
  end if;
  if exists (select 1 from jsonb_array_elements(r -> 'grades') g
             -- required_document_types added by slice 9a (20261024100000, the approved options change).
             where (select array_agg(k order by k) from jsonb_object_keys(g) k) is distinct from array['id', 'name', 'position', 'required_document_types']) then
    raise exception 'grade fields changed';
  end if;
  if exists (select 1 from jsonb_array_elements(r -> 'campuses') c
             where (select array_agg(k order by k) from jsonb_object_keys(c) k) is distinct from array['accepted_grade_ids', 'id', 'name']) then
    raise exception 'campus fields changed';
  end if;
  if jsonb_typeof(r -> 'intake_open') <> 'boolean' then raise exception 'intake_open not boolean'; end if;
end $$;

-- probe: O5 only active grades and years; campus rules narrow the accepted grades; the flag is reported
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_grades set is_active = false where name = 'Grade 9';
update public.admissions_academic_years set is_active = false where label = '2027/2028';
update public.admissions_settings set public_intake_open = true where id = 1;
select set_config('tcs.annex', (select jsonb_agg(id order by position)::text from public.admissions_grades
  where name in ('Pre Nursery', 'Nursery 1')), true);
-- as role:
do $$ declare r jsonb := public.get_public_admissions_options();
begin
  if r -> 'intake_open' <> 'true'::jsonb then raise exception 'flag not reported'; end if;
  if r -> 'academic_years' <> '["2026/2027"]'::jsonb then raise exception 'years wrong: %', r -> 'academic_years'; end if;
  if jsonb_array_length(r -> 'grades') <> 13
     or exists (select 1 from jsonb_array_elements(r -> 'grades') g where g ->> 'name' = 'Grade 9') then
    raise exception 'inactive grade listed';
  end if;
  if (select c -> 'accepted_grade_ids' from jsonb_array_elements(r -> 'campuses') c where c ->> 'name' = 'Annex (CK Road)')
     is distinct from current_setting('tcs.annex')::jsonb then
    raise exception 'Annex grades wrong';
  end if;
  if jsonb_array_length((select c -> 'accepted_grade_ids' from jsonb_array_elements(r -> 'campuses') c where c ->> 'name' = 'Main Campus (Somey Down)')) <> 13 then
    raise exception 'Main should accept every active grade';
  end if;
end $$;

-- probe: O6 closed intake reads as false; nothing about capacity, settings or applicants leaks
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e080000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e080000-0000-4000-8000-000300000001', '9e080000-0000-4000-8000-000100000001', 'Leak Probe Child');
-- as role:
do $$ declare t text := public.get_public_admissions_options()::text;
begin
  if (public.get_public_admissions_options() -> 'intake_open') <> 'false'::jsonb then raise exception 'not closed'; end if;
  if t ilike '%Leak Probe%' or t ilike '%capacity%' or t ilike '%offer_ttl%' or t ilike '%@%' then
    raise exception 'leaks: %', t;
  end if;
end $$;
