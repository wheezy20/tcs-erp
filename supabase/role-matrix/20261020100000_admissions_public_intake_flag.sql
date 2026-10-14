-- Probes for 20261020100000_admissions_public_intake_flag (admissions slice
-- 8, docs/admissions/PORT-PLAN.md): the public_intake_open column, the
-- Manager-only set_admissions_public_intake(boolean), its audit row, and who
-- reads the flag.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261020100000_admissions_public_intake_flag.sql

-- probe: I1 the column exists, not null, default false, and starts false
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admissions_settings'
      and column_name = 'public_intake_open' and data_type = 'boolean'
      and is_nullable = 'NO' and column_default = 'false'
  ) then raise exception 'column missing or changed'; end if;
  if (select public_intake_open from public.admissions_settings where id = 1) is not false then
    raise exception 'intake does not start closed';
  end if;
end $$;
-- as role:
select 1;

-- probe: I2 the RPC: security definer, search_path set, authenticated only (no anon, no public)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f regprocedure := 'public.set_admissions_public_intake(boolean)'::regprocedure;
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
  if has_function_privilege('authenticated', 'public.audit_admissions_settings()', 'execute') then
    raise exception 'authenticated can execute the trigger function';
  end if;
end $$;
-- as role:
select 1;

-- probe: I3 open public intake (Manager only)
-- expect: Manager
select public.set_admissions_public_intake(true);

-- probe: I4 close public intake (Manager only)
-- expect: Manager
update public.admissions_settings set public_intake_open = true where id = 1;
-- as role:
select public.set_admissions_public_intake(false);

-- probe: I5 setting the value it already has is refused, for everyone
-- expect: none
select public.set_admissions_public_intake(false);

-- probe: I6 null is refused, for everyone
-- expect: none
select public.set_admissions_public_intake(null);

-- probe: I7 a signed-in non-staff user is refused
-- expect: none
set local request.jwt.claims = '{"sub":"9e080000-0000-4000-8000-0000000000aa","role":"authenticated"}';
set local role authenticated;
select public.set_admissions_public_intake(true);

-- probe: I8 service_role can't use the RPC (it needs an active staff member)
-- expect: none
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.set_admissions_public_intake(true);

-- probe: I9 the Manager's change writes one admissions_settings_changed row with only the flag
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.audit_log where action = 'admissions_settings_changed';
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'role', 'authenticated')::text, true);
select public.set_admissions_public_intake(true);
select public.set_admissions_public_intake(false);
select set_config('request.jwt.claims', '', true);
do $$ begin
  if (select array_agg(before::text || '>' || after::text order by before::text)
      from public.audit_log where action = 'admissions_settings_changed')
     is distinct from array['{"public_intake_open": false}>{"public_intake_open": true}',
                            '{"public_intake_open": true}>{"public_intake_open": false}'] then
    raise exception 'audit rows wrong: %', (select array_agg(before::text || '>' || after::text) from public.audit_log where action = 'admissions_settings_changed');
  end if;
  if exists (select 1 from public.audit_log where action = 'admissions_settings_changed'
             and actor_id is distinct from (select id from public.staff where role = 'Manager' and active order by id limit 1)) then
    raise exception 'audit actor wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: I10 an offer expiry change still writes only offer_ttl_days (6b shape kept)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.audit_log where action = 'admissions_settings_changed';
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'role', 'authenticated')::text, true);
select public.set_admissions_offer_ttl_days(21);
select set_config('request.jwt.claims', '', true);
do $$ begin
  if (select array_agg(before::text || '>' || after::text) from public.audit_log where action = 'admissions_settings_changed')
     is distinct from array['{"offer_ttl_days": 14}>{"offer_ttl_days": 21}'] then
    raise exception 'ttl audit shape changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: I11 a service_role or postgres write to the flag is not audited (no actor)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.audit_log where action = 'admissions_settings_changed';
set local role service_role;
update public.admissions_settings set public_intake_open = true where id = 1;
reset role;
do $$ begin
  if exists (select 1 from public.audit_log where action = 'admissions_settings_changed') then
    raise exception 'audited without an actor';
  end if;
end $$;
-- as role:
select 1;

-- probe: I12 reading the flag through the table: Manager and Auditor only
-- expect: Manager,Auditor
do $$ begin
  if (select public_intake_open from public.admissions_settings where id = 1) is null then
    raise exception 'flag not visible';
  end if;
end $$;

-- probe: I13 no role can write the flag directly through the table
-- expect: none
do $$ declare n integer;
begin
  update public.admissions_settings set public_intake_open = true where id = 1;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;
