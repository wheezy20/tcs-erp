-- Probes for 20261020110000_public_rate_limits (admissions slice 8,
-- docs/admissions/PORT-PLAN.md, D-8d): the counter table has no API
-- privileges, check_public_rate_limit is service_role only, the limits
-- hold, and only hashes can be stored.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261020110000_public_rate_limits.sql

-- probe: R1 no API role holds any privilege on public_rate_limits (TRUNCATE included), RLS on
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text; p text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      if has_table_privilege(r, 'public.public_rate_limits', p) then
        raise exception '% holds % on public_rate_limits', r, p;
      end if;
    end loop;
  end loop;
  if not (select relrowsecurity from pg_class where oid = 'public.public_rate_limits'::regclass) then
    raise exception 'RLS off';
  end if;
end $$;
-- as role:
select 1;

-- probe: R2 check_public_rate_limit: definer, search_path, service_role only; helpers granted to nobody
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  if not (select prosecdef from pg_proc where oid = 'public.check_public_rate_limit(text, text)'::regprocedure) then
    raise exception 'not security definer';
  end if;
  if not exists (select 1 from pg_proc where oid = 'public.check_public_rate_limit(text, text)'::regprocedure
                 and proconfig @> array['search_path=public']) then raise exception 'no search_path'; end if;
  if has_function_privilege('anon', 'public.check_public_rate_limit(text, text)', 'execute')
     or has_function_privilege('authenticated', 'public.check_public_rate_limit(text, text)', 'execute')
     or not has_function_privilege('service_role', 'public.check_public_rate_limit(text, text)', 'execute') then
    raise exception 'check_public_rate_limit grants wrong';
  end if;
  foreach f in array array['public._public_rate_limit_rule(text)', 'public._public_rate_limit_hit(text, text)',
                           'public._require_public_service_caller()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
             where p.oid in ('public.check_public_rate_limit(text, text)'::regprocedure,
                             'public._public_rate_limit_rule(text)'::regprocedure,
                             'public._public_rate_limit_hit(text, text)'::regprocedure)
               and a.grantee = 0) then
    raise exception 'public can execute a rate limit function';
  end if;
end $$;
-- as role:
select 1;

-- probe: R3 the numbers live in one place: 20/hour IP, 200/hour global, 5/day email
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(b || '=' || r.max_count || '/' || r.window_length::text order by b)
      from unnest(array['inquiry_email', 'submit_global', 'submit_ip']) b,
           lateral public._public_rate_limit_rule(b) r)
     is distinct from array['inquiry_email=5/1 day', 'submit_global=200/01:00:00', 'submit_ip=20/01:00:00'] then
    raise exception 'rate limit numbers changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: R4 any JWT role calling check_public_rate_limit directly is denied
-- expect: none
select public.check_public_rate_limit('submit_ip', repeat('a', 64));

-- probe: R5 a signed-in non-staff user is denied
-- expect: none
set local request.jwt.claims = '{"sub":"9e080000-0000-4000-8000-0000000000aa","role":"authenticated"}';
set local role authenticated;
select public.check_public_rate_limit('submit_global');

-- probe: R6 even with a grant added by mistake, anon and every signed-in caller are refused
-- expect: none
grant execute on function public.check_public_rate_limit(text, text) to authenticated, anon;
-- as role:
select public.check_public_rate_limit('submit_ip', repeat('b', 64));

-- probe: R7 service_role: 20 hits from one IP hash pass, the 21st is refused, another hash passes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.public_rate_limits;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare i integer;
begin
  for i in 1 .. 20 loop
    if not public.check_public_rate_limit('submit_ip', repeat('c', 64)) then raise exception 'hit % refused', i; end if;
  end loop;
  if public.check_public_rate_limit('submit_ip', repeat('c', 64)) then raise exception '21st hit allowed'; end if;
  if public.check_public_rate_limit('submit_ip', repeat('c', 64)) then raise exception '22nd hit allowed'; end if;
  if not public.check_public_rate_limit('submit_ip', repeat('d', 64)) then raise exception 'other key refused'; end if;
end $$;

-- probe: R8 service_role: the global cap refuses the 201st hit in the window
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.public_rate_limits;
insert into public.public_rate_limits (bucket, key_hash, window_start, count)
values ('submit_global', 'global', date_bin(interval '1 hour', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00'), 199);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  if not public.check_public_rate_limit('submit_global') then raise exception '200th refused'; end if;
  if public.check_public_rate_limit('submit_global') then raise exception '201st allowed'; end if;
end $$;

-- probe: R9 an old window doesn't count against the current one, and old rows are cleared
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.public_rate_limits;
insert into public.public_rate_limits (bucket, key_hash, window_start, count) values
  ('submit_ip', repeat('e', 64), date_bin(interval '1 hour', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00') - interval '1 hour', 500),
  ('submit_ip', repeat('f', 64), clock_timestamp() - interval '3 days', 500);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  if not public.check_public_rate_limit('submit_ip', repeat('e', 64)) then raise exception 'previous window counted'; end if;
end $$;
reset role;
do $$ begin
  if exists (select 1 from public.public_rate_limits where key_hash = repeat('f', 64)) then raise exception 'old row kept'; end if;
end $$;

-- probe: R10 a raw IP is refused as a key, by the function and by the table
-- expect: none
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.check_public_rate_limit('submit_ip', '203.0.113.7');

-- probe: R11 the table refuses a raw IP even from postgres (checked in setup, as postgres)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  begin
    insert into public.public_rate_limits (bucket, key_hash, window_start, count)
    values ('submit_ip', '203.0.113.7', now(), 1);
  exception when check_violation then return;
  end;
  raise exception 'the table stored a raw IP';
end $$;
-- as role:
select 1;

-- probe: R12 uppercase hex, a short hash and the global key on submit_ip are refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare ok integer := 0; k text;
begin
  foreach k in array array[repeat('A', 64), repeat('a', 63), 'global'] loop
    begin
      perform public.check_public_rate_limit('submit_ip', k);
      ok := ok + 1;
    exception when others then null;
    end;
  end loop;
  if ok > 0 then raise exception '% accepted', ok; end if;
end $$;

-- probe: R13 the email bucket and unknown buckets can't be reached through the public entry point
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare ok integer := 0; b text;
begin
  foreach b in array array['inquiry_email', 'draft', 'lead', ''] loop
    begin
      perform public.check_public_rate_limit(b, repeat('a', 64));
      ok := ok + 1;
    exception when others then null;
    end;
  end loop;
  if ok > 0 then raise exception '% accepted', ok; end if;
end $$;

-- probe: R14 submit_global takes no key
-- expect: none
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.check_public_rate_limit('submit_global', repeat('a', 64));
