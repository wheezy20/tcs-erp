-- Probes for 20261024100000_admissions_application_uploads (admissions
-- slice 9a, checkpoint 1; docs/admissions/PORT-PLAN.md, slice 9, D-9a,
-- D-9e, D-9f, D-9g, D-9h, D-9l): the upload session and reservation tables
-- have no API privileges, the four upload RPCs are service_role only and
-- refuse every other caller even with a mistaken grant, the numbers live
-- in _public_rate_limit_rule, the open-reservation cap and per-session
-- file count hold, the sweep claims only expired unused reservations, and
-- the public options carry the required document types (fee proof for
-- every grade) without adding an anon-executable function.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261024100000_admissions_application_uploads.sql

-- probe: U1 no API role holds any privilege on the two upload tables (TRUNCATE included), RLS on
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare t text; r text; p text;
begin
  foreach t in array array['public.application_upload_sessions', 'public.application_upload_reservations'] loop
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(r, t, p) then raise exception '% holds % on %', r, p, t; end if;
      end loop;
    end loop;
    if not (select relrowsecurity from pg_class where oid = t::regclass) then raise exception 'RLS off on %', t; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = split_part(t, '.', 2)) then
      raise exception '% has a policy', t;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: U2 the four upload RPCs: definer, pinned search_path, service_role only; helpers granted to nobody
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  foreach f in array array['public.open_application_upload_session()',
                           'public.reserve_application_upload(text, text, text)',
                           'public.claim_expired_application_uploads(integer)',
                           'public.finish_application_upload_cleanup(uuid[])'] loop
    if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception '% not definer', f; end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=public']) then
      raise exception '% has no search_path', f;
    end if;
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% grants wrong', f;
    end if;
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f::regprocedure and a.grantee = 0) then
      raise exception 'public can execute %', f;
    end if;
  end loop;
  foreach f in array array['public._application_required_document_types(uuid)',
                           'public._application_upload_capacity_check()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: U3 the anon-executable count stays 170, and no new upload function is among them
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare n integer;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
  if exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
               and p.proname in ('open_application_upload_session', 'reserve_application_upload',
                                 'claim_expired_application_uploads', 'finish_application_upload_cleanup',
                                 '_application_required_document_types', '_application_upload_capacity_check')) then
    raise exception 'an upload function is anon-executable';
  end if;
end $$;
-- as role:
select 1;

-- probe: U4 the numbers live in one place, the slice 8 ones unchanged
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(b || '=' || r.max_count || '/' || coalesce(r.window_length::text, 'none') order by b)
      from unnest(array['application_email', 'inquiry_email', 'submit_global', 'submit_ip', 'upload_global',
                        'upload_ip', 'upload_open_reservations', 'upload_session_files']) b,
           lateral public._public_rate_limit_rule(b) r)
     is distinct from array['application_email=5/1 day', 'inquiry_email=5/1 day', 'submit_global=200/01:00:00',
                            'submit_ip=20/01:00:00', 'upload_global=100/01:00:00', 'upload_ip=10/01:00:00',
                            'upload_open_reservations=400/00:30:00', 'upload_session_files=8/06:00:00'] then
    raise exception 'rate limit numbers changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: U5 any JWT role opening an upload session directly is denied
-- expect: none
update public.admissions_settings set public_applications_open = true where id = 1;
-- as role:
select public.open_application_upload_session();

-- probe: U6 any JWT role reserving an upload directly is denied
-- expect: none
update public.admissions_settings set public_applications_open = true where id = 1;
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('e', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
select public.reserve_application_upload(repeat('e', 64), 'application_fee_proof', 'pdf');

-- probe: U7 any JWT role claiming or finishing a sweep directly is denied
-- expect: none
-- as role:
select public.claim_expired_application_uploads(5);

-- probe: U8 any JWT role finishing a sweep directly is denied
-- expect: none
-- as role:
select public.finish_application_upload_cleanup(array[gen_random_uuid()]);

-- probe: U9 even with grants added by mistake, anon and every signed-in caller are refused by the guard
-- expect: none
update public.admissions_settings set public_applications_open = true where id = 1;
-- A live session, so a reservation would go through if the guard were missing.
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('e', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
grant execute on function public.open_application_upload_session() to anon, authenticated;
grant execute on function public.reserve_application_upload(text, text, text) to anon, authenticated;
grant execute on function public.claim_expired_application_uploads(integer) to anon, authenticated;
grant execute on function public.finish_application_upload_cleanup(uuid[]) to anon, authenticated;
-- as role:
do $$ declare ok integer := 0;
begin
  begin perform public.open_application_upload_session(); ok := ok + 1; exception when others then null; end;
  begin perform public.reserve_application_upload(repeat('e', 64), 'application_fee_proof', 'pdf'); ok := ok + 1;
  exception when others then null; end;
  begin perform public.claim_expired_application_uploads(5); ok := ok + 1; exception when others then null; end;
  begin perform public.finish_application_upload_cleanup(array[gen_random_uuid()]); ok := ok + 1;
  exception when others then null; end;
  -- Any call that went through makes the probe succeed, which the
  -- expect: none line turns into a MISMATCH.
  if ok > 0 then return; end if;
  raise exception 'all four refused';
end $$;

-- probe: U10 service_role: closed applications refuse a session and a reservation (TCS03)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = false where id = 1;
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('f', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  begin perform public.open_application_upload_session(); raise exception 'session opened while closed';
  exception when sqlstate 'TCS03' then null; end;
  begin perform public.reserve_application_upload(repeat('f', 64), 'application_fee_proof', 'pdf');
    raise exception 'reserved while closed';
  exception when sqlstate 'TCS03' then null; end;
end $$;

-- probe: U11 service_role: a session returns a 64-hex token once, keeps only its sha256, lives 6 hours, 8 files
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare s jsonb; v_hash text; v_life interval;
begin
  s := public.open_application_upload_session();
  if (s->>'session_token') !~ '^[0-9a-f]{64}$' or (s->>'max_files')::int <> 8 then raise exception 'bad session %', s; end if;
  if (select array_agg(k order by k) from jsonb_object_keys(s) k) <> array['expires_at', 'max_files', 'session_token'] then
    raise exception 'extra keys %', s;
  end if;
  reset role;
  if exists (select 1 from public.application_upload_sessions where token_hash = s->>'session_token') then
    raise exception 'raw token stored';
  end if;
  select expires_at - created_at into v_life from public.application_upload_sessions
  where token_hash = encode(sha256(convert_to(s->>'session_token', 'UTF8')), 'hex');
  if v_life is null or v_life < interval '5 hours 59 minutes' or v_life > interval '6 hours 1 minute' then
    raise exception 'lifetime %', v_life;
  end if;
end $$;

-- probe: U12 service_role: a reservation's path is made by the server and the reservation ends with its session
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('1', 64), 'UTF8')), 'hex'), now() + interval '3 hours');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare r jsonb;
begin
  r := public.reserve_application_upload(repeat('1', 64), 'proof_of_vaccination', 'jpeg');
  if (r->>'storage_path') <> 'uploads/' || (r->>'reservation_id') || '/proof_of_vaccination.jpeg' then
    raise exception 'path %', r;
  end if;
  reset role;
  if (r->>'expires_at')::timestamptz <> (select expires_at from public.application_upload_sessions
                                         where token_hash = encode(sha256(convert_to(repeat('1', 64), 'UTF8')), 'hex')) then
    raise exception 'reservation outlives its session';
  end if;
end $$;

-- probe: U13 service_role: unknown, expired or closed session, a staff-only type, an odd extension are refused (TCS22)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
insert into public.application_upload_sessions (token_hash, created_at, expires_at)
values (encode(sha256(convert_to(repeat('2', 64), 'UTF8')), 'hex'), now() - interval '7 hours', now() - interval '1 hour');
insert into public.application_upload_sessions (token_hash, expires_at, closed_at)
values (encode(sha256(convert_to(repeat('3', 64), 'UTF8')), 'hex'), now() + interval '1 hour', now());
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('4', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare c record; n integer := 0;
begin
  for c in select * from (values
    (repeat('9', 64), 'application_fee_proof', 'pdf'),
    (repeat('2', 64), 'application_fee_proof', 'pdf'),
    (repeat('3', 64), 'application_fee_proof', 'pdf'),
    ('not-a-token', 'application_fee_proof', 'pdf'),
    (null, 'application_fee_proof', 'pdf'),
    (repeat('4', 64), 'passport_photo', 'pdf'),
    (repeat('4', 64), 'other', 'pdf'),
    (repeat('4', 64), 'application_fee_proof', 'heic'),
    (repeat('4', 64), 'application_fee_proof', 'PDF'),
    (repeat('4', 64), 'application_fee_proof', 'html'),
    (repeat('4', 64), null, 'pdf')) v (t, d, e) loop
    begin
      perform public.reserve_application_upload(c.t, c.d, c.e);
      raise exception 'accepted % % %', c.t, c.d, c.e;
    exception when sqlstate 'TCS22' then n := n + 1; end;
  end loop;
  if n <> 11 then raise exception 'only % refused', n; end if;
end $$;

-- probe: U14 service_role: the ninth reservation in one session is refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('5', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare i integer;
begin
  for i in 1 .. 8 loop perform public.reserve_application_upload(repeat('5', 64), 'previous_report', 'pdf'); end loop;
  begin
    perform public.reserve_application_upload(repeat('5', 64), 'previous_report', 'pdf');
    raise exception 'ninth file accepted';
  exception when sqlstate 'TCS22' then null; end;
end $$;

-- probe: U15 service_role: 400 fresh empty reservations (under 30 minutes) block a session and a reservation (TCS29); used or cleaned ones don't count
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
delete from public.application_upload_reservations;
insert into public.application_upload_sessions (id, token_hash, expires_at)
values ('99999999-0000-4000-8000-000000000015', encode(sha256(convert_to(repeat('6', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
select '99999999-0000-4000-8000-000000000015', 'previous_report', 'pdf', now() + interval '1 hour' from generate_series(1, 399);
insert into public.application_upload_reservations (session_id, document_type, extension, expires_at, consumed_at)
select '99999999-0000-4000-8000-000000000015', 'previous_report', 'pdf', now() + interval '1 hour', now() from generate_series(1, 5);
insert into public.application_upload_reservations (session_id, document_type, extension, expires_at, cleaned_at)
select '99999999-0000-4000-8000-000000000015', 'previous_report', 'pdf', now() - interval '1 hour', now() from generate_series(1, 5);
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('7', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  -- 399 open: the 400th fits.
  perform public.reserve_application_upload(repeat('7', 64), 'previous_report', 'pdf');
  begin perform public.reserve_application_upload(repeat('7', 64), 'previous_report', 'pdf'); raise exception '401st reserved';
  exception when sqlstate 'TCS29' then null; end;
  begin perform public.open_application_upload_session(); raise exception 'session opened at the cap';
  exception when sqlstate 'TCS29' then null; end;
end $$;

-- probe: U16 service_role: the sweep claims only unused reservations expired over 30 minutes, once, within its limit
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.application_upload_reservations;
insert into public.application_upload_sessions (id, token_hash, created_at, expires_at)
values ('99999999-0000-4000-8000-000000000016', repeat('a', 64), now() - interval '8 hours', now() - interval '2 hours');
insert into public.application_upload_reservations (id, session_id, document_type, extension, created_at, expires_at, consumed_at, cleaned_at, cleanup_claimed_at)
select id, session_id, document_type, extension, now() - interval '7 hours', expires_at, consumed_at, cleaned_at, cleanup_claimed_at
from (values
  ('16000000-0000-4000-8000-000000000001'::uuid, '99999999-0000-4000-8000-000000000016'::uuid, 'previous_report', 'pdf', now() - interval '2 hours', null::timestamptz, null::timestamptz, null::timestamptz),
  ('16000000-0000-4000-8000-000000000002', '99999999-0000-4000-8000-000000000016', 'previous_report', 'pdf', now() - interval '10 minutes', null, null, null),
  ('16000000-0000-4000-8000-000000000003', '99999999-0000-4000-8000-000000000016', 'previous_report', 'pdf', now() - interval '2 hours', now() - interval '3 hours', null, null),
  ('16000000-0000-4000-8000-000000000004', '99999999-0000-4000-8000-000000000016', 'previous_report', 'pdf', now() - interval '2 hours', null, now(), now()),
  ('16000000-0000-4000-8000-000000000005', '99999999-0000-4000-8000-000000000016', 'previous_report', 'pdf', now() - interval '2 hours', null, null, now() - interval '2 minutes'),
  ('16000000-0000-4000-8000-000000000006', '99999999-0000-4000-8000-000000000016', 'previous_report', 'png', now() - interval '3 hours', null, null, now() - interval '20 minutes'),
  ('16000000-0000-4000-8000-000000000007', '99999999-0000-4000-8000-000000000016', 'previous_report', 'pdf', now() + interval '1 hour', null, null, null)
) v (id, session_id, document_type, extension, expires_at, consumed_at, cleaned_at, cleanup_claimed_at);
-- Expired 2 hours ago but made only 1 hour ago (late in its session): its
-- signed upload token may still be live, so it must not be claimed yet.
insert into public.application_upload_reservations (id, session_id, document_type, extension, created_at, expires_at)
values ('16000000-0000-4000-8000-000000000008', '99999999-0000-4000-8000-000000000016', 'previous_report', 'pdf',
        now() - interval '1 hour', now() - interval '2 hours');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare got uuid[];
begin
  select array_agg(c.reservation_id order by c.reservation_id) into got from public.claim_expired_application_uploads(50) c;
  if got is distinct from array['16000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000006']::uuid[] then
    raise exception 'claimed %', got;
  end if;
  if exists (select 1 from public.claim_expired_application_uploads(50)) then raise exception 'claimed twice'; end if;
  begin perform public.claim_expired_application_uploads(51); raise exception 'limit 51 accepted';
  exception when raise_exception then if sqlerrm like 'limit%' then raise; end if; end;
  begin perform public.claim_expired_application_uploads(0); raise exception 'limit 0 accepted';
  exception when raise_exception then if sqlerrm like 'limit%' then raise; end if; end;
end $$;

-- probe: U17 service_role: finishing marks only claimed, expired, unused reservations
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.application_upload_reservations;
insert into public.application_upload_sessions (id, token_hash, created_at, expires_at)
values ('99999999-0000-4000-8000-000000000017', repeat('b', 64), now() - interval '8 hours', now() - interval '2 hours');
insert into public.application_upload_reservations (id, session_id, document_type, extension, created_at, expires_at, consumed_at, cleanup_claimed_at)
select id, session_id, document_type, extension, now() - interval '7 hours', expires_at, consumed_at, cleanup_claimed_at
from (values
  ('17000000-0000-4000-8000-000000000001'::uuid, '99999999-0000-4000-8000-000000000017'::uuid, 'previous_report', 'pdf', now() - interval '2 hours', null::timestamptz, now()),
  ('17000000-0000-4000-8000-000000000002', '99999999-0000-4000-8000-000000000017', 'previous_report', 'pdf', now() - interval '2 hours', null, null),
  ('17000000-0000-4000-8000-000000000003', '99999999-0000-4000-8000-000000000017', 'previous_report', 'pdf', now() - interval '2 hours', now() - interval '3 hours', now()),
  ('17000000-0000-4000-8000-000000000004', '99999999-0000-4000-8000-000000000017', 'previous_report', 'pdf', now() + interval '1 hour', null, now())
) v (id, session_id, document_type, extension, expires_at, consumed_at, cleanup_claimed_at);
insert into public.application_upload_reservations (id, session_id, document_type, extension, created_at, expires_at, cleanup_claimed_at)
values ('17000000-0000-4000-8000-000000000005', '99999999-0000-4000-8000-000000000017', 'previous_report', 'pdf',
        now() - interval '1 hour', now() - interval '2 hours', now());
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare n integer;
begin
  n := public.finish_application_upload_cleanup(array['17000000-0000-4000-8000-000000000001', '17000000-0000-4000-8000-000000000002',
    '17000000-0000-4000-8000-000000000003', '17000000-0000-4000-8000-000000000004',
    '17000000-0000-4000-8000-000000000005']::uuid[]);
  if n <> 1 then raise exception 'marked %', n; end if;
  reset role;
  if (select array_agg(id order by id) from public.application_upload_reservations where cleaned_at is not null)
     is distinct from array['17000000-0000-4000-8000-000000000001']::uuid[] then
    raise exception 'wrong rows cleaned';
  end if;
end $$;

-- probe: U18 a reservation can't be both used and cleaned, and its path can't be written
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.application_upload_sessions (id, token_hash, expires_at)
values ('99999999-0000-4000-8000-000000000018', repeat('c', 64), now() + interval '1 hour');
do $$ begin
  begin
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at, consumed_at, cleaned_at)
    values ('99999999-0000-4000-8000-000000000018', 'previous_report', 'pdf', now(), now(), now());
    raise exception 'used and cleaned accepted';
  exception when check_violation then null; end;
  begin
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at, storage_path)
    values ('99999999-0000-4000-8000-000000000018', 'previous_report', 'pdf', now(), 'uploads/x/previous_report.pdf');
    raise exception 'client path accepted';
  exception when generated_always or feature_not_supported or syntax_error then null; end;
end $$;
-- as role:
select 1;

-- probe: U19 service_role: the upload buckets count; the email bucket and the caps can't be hit from outside
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.public_rate_limits;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare i integer; b text;
begin
  for i in 1 .. 10 loop
    if not public.check_public_rate_limit('upload_ip', repeat('c', 64)) then raise exception 'hit % refused', i; end if;
  end loop;
  if public.check_public_rate_limit('upload_ip', repeat('c', 64)) then raise exception '11th allowed'; end if;
  if not public.check_public_rate_limit('upload_global') then raise exception 'global refused'; end if;
  begin perform public.check_public_rate_limit('upload_ip'); raise exception 'upload_ip without a key accepted';
  exception when raise_exception then if sqlerrm like '%accepted' then raise; end if; end;
  begin perform public.check_public_rate_limit('upload_global', repeat('c', 64)); raise exception 'upload_global with a key accepted';
  exception when raise_exception then if sqlerrm like '%accepted' then raise; end if; end;
  foreach b in array array['application_email', 'inquiry_email', 'upload_open_reservations', 'upload_session_files'] loop
    begin perform public.check_public_rate_limit(b, repeat('c', 64)); raise exception '% accepted', b;
    exception when raise_exception then if sqlerrm like '% accepted' then raise; end if; end;
  end loop;
end $$;

-- probe: U20 required documents: fee proof first for every active grade, vaccination exactly where the grade needs it, and the options carry the same list
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
do $$ declare g jsonb; v_flag boolean;
begin
  if jsonb_array_length(public.get_public_admissions_options()->'grades') = 0 then raise exception 'no grades'; end if;
  for g in select * from jsonb_array_elements(public.get_public_admissions_options()->'grades') loop
    if (select array_agg(k order by k) from jsonb_object_keys(g) k) <> array['id', 'name', 'position', 'required_document_types'] then
      raise exception 'grade keys %', g;
    end if;
    if g->'required_document_types'->>0 <> 'application_fee_proof' then raise exception 'fee proof not first for %', g->>'name'; end if;
    v_flag := g->'required_document_types' ? 'proof_of_vaccination';
    if jsonb_array_length(g->'required_document_types') <> (case when v_flag then 2 else 1 end) then
      raise exception 'odd list for %', g->>'name';
    end if;
  end loop;
end $$;

-- probe: U21 the helper matches each grade's vaccination flag, inactive grades included
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (select 1 from public.admissions_grades g
             where public._application_required_document_types(g.id) is distinct from
                   case when g.is_preschool_vaccination_required
                        then array['application_fee_proof', 'proof_of_vaccination']
                        else array['application_fee_proof'] end) then
    raise exception 'helper disagrees with the grade flag';
  end if;
  if public._application_required_document_types(gen_random_uuid()) is not null then raise exception 'unknown grade got a list'; end if;
  if not exists (select 1 from public.admissions_grades where is_preschool_vaccination_required) then
    raise exception 'no preschool grade to test';
  end if;
end $$;
-- as role:
select 1;

-- probe: U22 the admissions-documents bucket still has no write policy
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
do $$ begin
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
             and coalesce(qual, '') || coalesce(with_check, '') like '%admissions-documents%') then
    raise exception 'a write policy exists for admissions-documents';
  end if;
end $$;

-- probe: U23 anon and every staff role can't write a file into admissions-documents directly
-- expect: none
-- as role:
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'uploads/probe/previous_report.pdf');

-- probe: U24 service_role: 400 reservations with files block a reservation and a session, expired ones awaiting the sweep included (TCS29)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
delete from public.application_upload_reservations;
insert into public.application_upload_sessions (id, token_hash, created_at, expires_at)
values ('99999999-0000-4000-8000-000000000024', repeat('d', 64), now() - interval '7 hours', now() + interval '1 hour');
-- 200 live and 200 expired, all made 2 hours ago (past the 30 minute window), each with its file.
insert into public.application_upload_reservations (session_id, document_type, extension, created_at, expires_at)
select '99999999-0000-4000-8000-000000000024', 'previous_report', 'pdf', now() - interval '2 hours',
       case when i <= 200 then now() + interval '1 hour' else now() - interval '1 hour' end
from generate_series(1, 400) i;
insert into storage.objects (bucket_id, name)
select 'admissions-documents', storage_path from public.application_upload_reservations
where session_id = '99999999-0000-4000-8000-000000000024';
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('8', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  begin perform public.reserve_application_upload(repeat('8', 64), 'previous_report', 'pdf'); raise exception 'reserved at the cap';
  exception when sqlstate 'TCS29' then null; end;
  begin perform public.open_application_upload_session(); raise exception 'session opened at the cap';
  exception when sqlstate 'TCS29' then null; end;
end $$;

-- probe: U25 service_role: many empty reservations older than 30 minutes don't block, live or expired
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_applications_open = true where id = 1;
delete from public.application_upload_reservations;
insert into public.application_upload_sessions (id, token_hash, created_at, expires_at)
values ('99999999-0000-4000-8000-000000000025', repeat('e', 64), now() - interval '7 hours', now() + interval '1 hour');
insert into public.application_upload_reservations (session_id, document_type, extension, created_at, expires_at)
select '99999999-0000-4000-8000-000000000025', 'previous_report', 'pdf', now() - interval '31 minutes',
       case when i <= 600 then now() + interval '1 hour' else now() - interval '1 hour' end
from generate_series(1, 1000) i;
-- 399 with files, so the next one is the 400th place.
insert into public.application_upload_reservations (session_id, document_type, extension, created_at, expires_at)
select '99999999-0000-4000-8000-000000000025', 'financial_clearance', 'pdf', now() - interval '2 hours', now() + interval '1 hour'
from generate_series(1, 399);
insert into storage.objects (bucket_id, name)
select 'admissions-documents', storage_path from public.application_upload_reservations
where document_type = 'financial_clearance';
insert into public.application_upload_sessions (token_hash, expires_at)
values (encode(sha256(convert_to(repeat('9', 64), 'UTF8')), 'hex'), now() + interval '1 hour');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  perform public.open_application_upload_session();
  perform public.reserve_application_upload(repeat('9', 64), 'previous_report', 'pdf');
  -- That fresh empty reservation is the 400th counted place.
  begin perform public.reserve_application_upload(repeat('9', 64), 'previous_report', 'pdf'); raise exception '401st reserved';
  exception when sqlstate 'TCS29' then null; end;
end $$;
