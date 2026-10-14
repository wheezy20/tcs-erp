-- Probes for 20261021100000_admissions_public_applications_flag (admissions
-- slice 8b): the public applications switch, its Manager-only audited
-- setter, who reads it, and its independence from the public inquiries
-- switch (public_intake_open).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261021100000_admissions_public_applications_flag.sql

-- probe: P1 the column exists, not null, default false, and starts false
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admissions_settings'
      and column_name = 'public_applications_open' and data_type = 'boolean'
      and is_nullable = 'NO' and column_default = 'false'
  ) then raise exception 'column missing or changed'; end if;
  if (select public_applications_open from public.admissions_settings where id = 1) is not false then
    raise exception 'applications do not start closed';
  end if;
end $$;
-- as role:
select 1;

-- probe: P2 the setter: security definer, search_path, authenticated only (no anon, no public), one overload
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f regprocedure := 'public.set_admissions_public_applications(boolean)'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = f) then raise exception 'not security definer'; end if;
  if not exists (select 1 from pg_proc where oid = f and proconfig @> array['search_path=public']) then
    raise exception 'no search_path';
  end if;
  if has_function_privilege('anon', f, 'execute') then raise exception 'anon can execute'; end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then
    raise exception 'public can execute';
  end if;
  if not has_function_privilege('authenticated', f, 'execute') then raise exception 'authenticated cannot execute'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname = 'set_admissions_public_applications') <> 1 then raise exception 'stray overload'; end if;
end $$;
-- as role:
select 1;

-- probe: P3 open public applications (Manager only; anon and every other role refused)
-- expect: Manager
select public.set_admissions_public_applications(true);

-- probe: P4 close public applications (Manager only)
-- expect: Manager
update public.admissions_settings set public_applications_open = true where id = 1;
-- as role:
select public.set_admissions_public_applications(false);

-- probe: P5 setting the value it already has is refused, for everyone
-- expect: none
select public.set_admissions_public_applications(false);

-- probe: P6 null is refused, for everyone
-- expect: none
select public.set_admissions_public_applications(null);

-- probe: P7 a signed-in non-staff user is refused
-- expect: none
set local request.jwt.claims = '{"sub":"9e080000-0000-4000-8000-0000000000aa","role":"authenticated"}';
set local role authenticated;
select public.set_admissions_public_applications(true);

-- probe: P8 service_role can't use the setter (it needs an active staff member)
-- expect: none
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.set_admissions_public_applications(true);

-- probe: P9 each switch writes admissions_settings_changed holding only its own field
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.audit_log where action = 'admissions_settings_changed';
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'role', 'authenticated')::text, true);
select public.set_admissions_public_applications(true);
select public.set_admissions_public_intake(true);
select set_config('request.jwt.claims', '', true);
do $$ begin
  if (select array_agg(before::text || '>' || after::text order by after::text)
      from public.audit_log where action = 'admissions_settings_changed')
     is distinct from array['{"public_applications_open": false}>{"public_applications_open": true}',
                            '{"public_intake_open": false}>{"public_intake_open": true}'] then
    raise exception 'audit rows wrong: %', (select array_agg(before::text || '>' || after::text) from public.audit_log where action = 'admissions_settings_changed');
  end if;
end $$;
-- as role:
select 1;

-- probe: P10 flipping one switch never changes the other
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'role', 'authenticated')::text, true);
select public.set_admissions_public_applications(true);
do $$ begin
  if (select public_intake_open from public.admissions_settings where id = 1) then raise exception 'applications opened inquiries'; end if;
end $$;
select public.set_admissions_public_intake(true);
select public.set_admissions_public_applications(false);
do $$ begin
  if not (select public_intake_open from public.admissions_settings where id = 1) then raise exception 'closing applications closed inquiries'; end if;
end $$;
select public.set_admissions_public_intake(false);
select public.set_admissions_public_applications(true);
do $$ begin
  if not (select public_applications_open from public.admissions_settings where id = 1) then raise exception 'state wrong'; end if;
end $$;
select set_config('request.jwt.claims', '', true);
-- as role:
select 1;

-- probe: P11 applications closed does not close inquiries: submit_inquiry still works
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true, public_applications_open = false where id = 1;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'p11@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'Little Stars', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
    'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.submit_inquiry(current_setting('tcs.p')::jsonb);

-- probe: P12 applications open does not open inquiries: submit_inquiry refuses with TCS03
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = false, public_applications_open = true where id = 1;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'p12@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'Little Stars', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
    'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  begin
    perform public.submit_inquiry(current_setting('tcs.p')::jsonb);
    raise exception 'accepted with inquiries closed';
  exception when sqlstate 'TCS03' then null;
  end;
end $$;

-- probe: P13 the public options report the two switches separately
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = false, public_applications_open = true where id = 1;
-- as role:
do $$ declare r jsonb := public.get_public_admissions_options();
begin
  if r -> 'intake_open' <> 'false'::jsonb or r -> 'applications_open' <> 'true'::jsonb then
    raise exception 'switches not reported separately: % %', r -> 'intake_open', r -> 'applications_open';
  end if;
end $$;

-- probe: P14 reading the switch through the table: Manager and Auditor only
-- expect: Manager,Auditor
do $$ begin
  if (select public_applications_open from public.admissions_settings where id = 1) is null then
    raise exception 'switch not visible';
  end if;
end $$;

-- probe: P15 no role can write the switch directly through the table
-- expect: none
do $$ declare n integer;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;
