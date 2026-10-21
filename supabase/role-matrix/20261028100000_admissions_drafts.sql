-- Probes for 20261028100000_admissions_drafts (admissions slice 10,
-- checkpoint C1; docs/admissions/PORT-PLAN.md, slice 10): the two draft
-- tables have RLS and no API privilege; the helpers are granted to nobody;
-- the anon-executable count stays 170; the form state check refuses
-- health, documents, the declaration, the signature and media consent at
-- every level; the outbox takes a resume email only with no params, no
-- application, a recipient and its draft; staff email functions leave
-- resume emails out except one failed count; resume emails don't count
-- toward the confirmation cap; housekeeping wipes and deletes drafts and
-- purges resume rows after 7 days; the draft rate buckets.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261028100000_admissions_drafts.sql
-- Run the probe files before the Edge Function integration tests (they
-- commit rows).

-- probe: D1 structure: both tables have RLS, no policy and no API privilege; helpers granted to nobody; the count stays 170; the numbers
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text; p text; f text; n integer;
begin
  foreach f in array array['public.application_drafts', 'public.application_draft_links'] loop
    if not (select relrowsecurity from pg_class where oid = f::regclass) then raise exception '% RLS off', f; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = split_part(f, '.', 2)) then
      raise exception '% has a policy', f;
    end if;
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(r, f, p) then raise exception '% % % granted', f, r, p; end if;
      end loop;
    end loop;
  end loop;
  foreach f in array array['public._application_draft_lifetime()', 'public._application_draft_state_ok(jsonb)',
      'public._enqueue_admissions_emails(text, uuid, uuid, text[])', 'public._admissions_email_params_ok(text, jsonb)',
      'public.purge_admissions_housekeeping()', 'public._public_rate_limit_rule(text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.get_admissions_email_health()', 'execute')
     or not has_function_privilege('authenticated', 'public.get_admissions_email_health()', 'execute') then
    raise exception 'health grants wrong';
  end if;
  if has_function_privilege('anon', 'public.check_public_rate_limit(text, text)', 'execute')
     or has_function_privilege('authenticated', 'public.check_public_rate_limit(text, text)', 'execute')
     or not has_function_privilege('service_role', 'public.check_public_rate_limit(text, text)', 'execute') then
    raise exception 'rate limit grants wrong';
  end if;
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
  if exists (select proname from pg_proc where proname in ('get_admissions_email_health', 'purge_admissions_housekeeping',
      '_public_rate_limit_rule', 'check_public_rate_limit', '_admissions_email_params_ok', '_enqueue_admissions_emails')
      group by proname having count(*) > 1) then
    raise exception 'overloads';
  end if;
  if (select string_agg(b || '=' || r.max_count || '/' || r.window_length, ',' order by b)
      from unnest(array['draft_ip', 'draft_global', 'draft_use_ip', 'draft_live', 'draft_live_per_email', 'draft_links',
                        'draft_email_per_draft_total', 'draft_email_recipient_day']) b,
           public._public_rate_limit_rule(b) r)
     is distinct from 'draft_email_per_draft_total=10/60 days,'
       'draft_email_recipient_day=3/1 day,draft_global=100/01:00:00,draft_ip=10/01:00:00,draft_links=61/60 days,'
       'draft_live=2000/60 days,draft_live_per_email=3/60 days,draft_use_ip=60/01:00:00' then
    raise exception 'draft numbers wrong';
  end if;
  if (select sliding || '/' || ceiling || '/' || max_bytes from public._application_draft_lifetime())
     is distinct from '30 days/60 days/49152' then
    raise exception 'lifetime wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: D2 no JWT role can read a draft or a link directly
-- expect: none
insert into public.application_drafts (id, email, data, consented_at, expires_at)
values ('12000000-0000-4000-8000-000000000d01', 'seen@example.test', '{"campusId": "x"}', now(), now() + interval '30 days');
insert into public.application_draft_links (draft_id, token_hash)
values ('12000000-0000-4000-8000-000000000d01', repeat('d', 64));
-- as role:
do $$ begin
  if not exists (select 1 from public.application_drafts) and not exists (select 1 from public.application_draft_links) then
    raise exception 'no rows';
  end if;
end $$;

-- probe: D3 the state check: a realistic form state and {} pass; health, documents, signature, agreed and media consent are refused at the top and when tucked inside the child; unknown keys, a third guardian, a nested object and the size cap are refused by the table too
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare ok jsonb := '{
    "guardians": [{"surname": "Mensah", "firstName": "Ama", "relationship": "mother", "religion": "Christian",
                   "address": "1 Ring Road", "townCity": "Accra", "phone": "+233590000001", "email": "a@example.test"}],
    "secondSameAddress": false,
    "child": {"fullName": "Kojo", "dateOfBirth": "03/02/2019", "gender": "male", "nationality": "Ghanaian",
              "sameAddress": true, "address": "", "townCity": "", "postalCode": "", "country": "Ghana",
              "currentGrade": "", "currentSchool": "", "previousSchoolLocation": "", "gradeId": "", "academicYear": "",
              "month": ""},
    "campusId": "", "emergency": {"name": "", "relationship": "", "phone": ""},
    "wantsScholarship": false, "scholarshipDetails": ""}'::jsonb;
  bad jsonb; refused integer := 0;
begin
  if not public._application_draft_state_ok(ok) or not public._application_draft_state_ok('{}') then
    raise exception 'a good state refused';
  end if;
  foreach bad in array array[
    ok || '{"health": {"hasMedical": true}}', ok || '{"health": {}}',
    ok || '{"documents": []}', ok || '{"signature": "Ama"}', ok || '{"agreed": true}', ok || '{"mediaConsent": true}',
    jsonb_set(ok, '{child,medical}', '"asthma"'), jsonb_set(ok, '{child,hasMedical}', 'true'),
    jsonb_set(ok, '{emergency,allergies}', '"nuts"'), jsonb_set(ok, '{guardians,0,signature}', '"Ama"'),
    jsonb_set(ok, '{child,fullName}', '{"x": 1}'), jsonb_set(ok, '{campusId}', '{"x": 1}'),
    jsonb_set(ok, '{guardians}', (ok -> 'guardians') || (ok -> 'guardians') || (ok -> 'guardians')),
    ok || '{"unknown": 1}', '[]'::jsonb, '"text"'::jsonb]::jsonb[] loop
    if public._application_draft_state_ok(bad) then raise exception 'accepted %', bad; end if;
    begin
      insert into public.application_drafts (email, data, consented_at, expires_at)
      values ('t@example.test', bad, now(), now() + interval '1 day');
      raise exception 'table took %', bad;
    exception when check_violation then refused := refused + 1;
    end;
  end loop;
  begin
    insert into public.application_drafts (email, data, consented_at, expires_at)
    values ('t@example.test', jsonb_build_object('scholarshipDetails', repeat('x', 49200)), now(), now() + interval '1 day');
    raise exception 'oversized taken';
  exception when check_violation then refused := refused + 1;
  end;
  -- A wiped draft holds no email; a draft with data must have one.
  begin
    insert into public.application_drafts (email, data, consented_at, expires_at)
    values (null, '{"campusId": "x"}', now(), now() + interval '1 day');
    raise exception 'data without an email taken';
  exception when check_violation then refused := refused + 1;
  end;
  if refused <> 18 then raise exception 'refused %', refused; end if;
end $$;
-- as role:
select 1;

-- probe: D4 the outbox checks: a resume email needs params {}, no application, a recipient and its draft; no other kind may name a draft; the event key matches the kind
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.application_drafts (id, email, data, consented_at, expires_at)
values ('12000000-0000-4000-8000-000000000d02', 'r@example.test', '{}', now(), now() + interval '30 days');
do $$ declare d uuid := '12000000-0000-4000-8000-000000000d02'; refused integer := 0; v text;
begin
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, draft_id)
  values ('draft:' || d || ':1', 'draft_resume', 'r@example.test', '{}', '{}', d);
  foreach v in array array[
    $q$('draft:%1$s:2', 'draft_resume', 'r@example.test', '{}', '{"token": "abc"}', '%1$s')$q$,
    $q$('draft:%1$s:3', 'draft_resume', 'r@example.test', '{}', '{"link": "https://x"}', '%1$s')$q$,
    $q$('draft:%1$s:4', 'draft_resume', 'r@example.test', '{}', '{}', null)$q$,
    $q$('draft:%1$s:5', 'draft_resume', null, '{}', '{}', '%1$s')$q$,
    $q$('draft:%1$s:6', 'draft_resume', 'r@example.test', array[gen_random_uuid()], '{}', '%1$s')$q$,
    $q$('inquiry:%1$s', 'draft_resume', 'r@example.test', '{}', '{}', '%1$s')$q$,
    $q$('draft:%1$s:7', 'inquiry_parent', 'r@example.test', array[gen_random_uuid()],
        '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}', null)$q$,
    $q$('inquiry:%1$s', 'inquiry_parent', 'r@example.test', array[gen_random_uuid()],
        '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}', '%1$s')$q$,
    $q$('inquiry:%1$s', 'inquiry_parent', 'r@example.test', '{}',
        '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}', null)$q$] loop
    begin
      execute format('insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, draft_id) values '
        || v, d);
      raise exception 'taken: %', v;
    exception when check_violation or not_null_violation then refused := refused + 1;
    end;
  end loop;
  if refused <> 9 then raise exception 'refused %', refused; end if;
  -- The old kinds still pass.
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params)
  values ('inquiry:' || gen_random_uuid(), 'inquiry_parent', 'r@example.test', array[gen_random_uuid()],
          '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}');
end $$;
-- as role:
select 1;

-- probe: D5 list_admissions_emails leaves resume emails out; requeue can't touch one
-- expect: Manager
insert into public.application_drafts (id, email, data, consented_at, expires_at)
values ('12000000-0000-4000-8000-000000000d03', 'r@example.test', '{}', now(), now() + interval '30 days');
insert into public.admissions_email_outbox (id, event_key, kind, recipient_email, application_ids, params, draft_id, status)
values ('12000000-0000-4000-8000-000000000e01', 'draft:12000000-0000-4000-8000-000000000d03:1', 'draft_resume',
        'r@example.test', '{}', '{}', '12000000-0000-4000-8000-000000000d03', 'failed');
insert into public.admissions_email_outbox (id, event_key, kind, recipient_email, application_ids, params, status)
values ('12000000-0000-4000-8000-000000000e02', 'inquiry:' || gen_random_uuid(), 'inquiry_parent', 'q@example.test',
        array[gen_random_uuid()],
        '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}', 'failed');
-- as role:
do $$ begin
  if exists (select 1 from public.list_admissions_emails(null, 500) where kind = 'draft_resume') then
    raise exception 'a resume email is listed';
  end if;
  if not exists (select 1 from public.list_admissions_emails('failed', 500) where id = '12000000-0000-4000-8000-000000000e02') then
    raise exception 'the confirmation email is not listed';
  end if;
  if public.requeue_admissions_emails(array['12000000-0000-4000-8000-000000000e01', '12000000-0000-4000-8000-000000000e02']::uuid[]) <> 1 then
    raise exception 'requeue count';
  end if;
end $$;
reset role;
do $$ begin
  if (select status from public.admissions_email_outbox where id = '12000000-0000-4000-8000-000000000e01') <> 'failed' then
    raise exception 'resume email requeued';
  end if;
end $$;

-- probe: D6 get_admissions_email_health: the old counts leave resume emails out; draft_failed counts failed resume emails only; Manager and Auditor
-- expect: Manager,Auditor
insert into public.application_drafts (id, email, data, consented_at, expires_at)
values ('12000000-0000-4000-8000-000000000d04', 'r@example.test', '{}', now(), now() + interval '30 days');
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, draft_id, status)
select 'draft:12000000-0000-4000-8000-000000000d04:' || n, 'draft_resume', 'r@example.test', '{}', '{}',
       '12000000-0000-4000-8000-000000000d04', s
from (values (1, 'failed'), (2, 'failed'), (3, 'pending'), (4, 'suppressed'), (5, 'expired')) v (n, s);
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, status)
select 'inquiry:' || gen_random_uuid(), 'inquiry_parent', 'q@example.test', array[gen_random_uuid()],
       '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}', s
from unnest(array['failed', 'pending', 'pending', 'suppressed', 'expired']) s;
-- as role:
do $$ declare h record; begin
  select * into h from public.get_admissions_email_health();
  if (h.waiting, h.failed, h.suppressed, h.expired, h.draft_failed) is distinct from (2, 1, 1, 1, 2) then
    raise exception 'counts %', h;
  end if;
end $$;

-- probe: D7 resume emails to an address don't count toward its 4 confirmation emails a day
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.afx(emails) builds an open switch, a live upload
-- session with a stored fee proof, and a valid payload.
create function pg_temp.afx(p_emails text[], p_child text default 'Draft Cap Child')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_id uuid; v_p text;
  v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_sid, 'application_fee_proof', 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
  insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Probe Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('token', v_tok,
    'sniffed', jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf')),
    'payload', jsonb_build_object(
      'guardians', v_g,
      'student', jsonb_build_object('full_name', p_child, 'date_of_birth', '2018-05-01', 'gender', 'female',
        'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
        'grade_id', (select id from public.admissions_grades where name = 'Grade 3')::text,
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      'campus_id', (select id from public.branches where name = 'Main')::text,
      'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
      'health_info', jsonb_build_object('has_medical_conditions', false),
      'documents', jsonb_build_array(jsonb_build_object('document_type', 'application_fee_proof',
        'reservation_id', v_id, 'path', v_p)),
      'declaration_signature_name', 'Guardian One', 'declaration_agreed', true));
end $f$;
insert into public.application_drafts (id, email, data, consented_at, expires_at)
values ('12000000-0000-4000-8000-000000000d05', 'cap@example.test', '{}', now(), now() + interval '30 days');
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, draft_id, status, sent_at)
select 'draft:12000000-0000-4000-8000-000000000d05:' || n, 'draft_resume', 'cap@example.test', '{}', '{}',
       '12000000-0000-4000-8000-000000000d05', 'sent', now()
from generate_series(1, 5) n;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.afx(array['cap@example.test']);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.ref', public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed'), true) from fx;
reset role;
do $$ begin
  if (select status from public.admissions_email_outbox
      where kind = 'application_parent' and params -> 'references' -> 0 ->> 'reference' = current_setting('tcs.ref'))
     is distinct from 'pending' then
    raise exception 'the confirmation email was suppressed by resume emails';
  end if;
end $$;

-- probe: D8 housekeeping: wipes expired live drafts and drops their pending resume emails, keeps unexpired ones, deletes drafts 30 days after expiry or submission with their links, purges resume rows after 7 days whatever their status, and keeps the old keys
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.application_drafts (id, email, data, consented_at, created_at, expires_at, submitted_at) values
  ('12000000-0000-4000-8000-000000000f01', 'live@example.test', '{"campusId": "a"}', now(), now() - interval '1 day', now() + interval '1 day', null),
  ('12000000-0000-4000-8000-000000000f02', 'gone@example.test', '{"campusId": "b"}', now(), now() - interval '31 days', now() - interval '1 hour', null),
  ('12000000-0000-4000-8000-000000000f03', null, '{}', now(), now() - interval '62 days', now() - interval '31 days', null),
  ('12000000-0000-4000-8000-000000000f04', null, '{}', now(), now() - interval '60 days', now() - interval '29 days', null),
  ('12000000-0000-4000-8000-000000000f05', null, '{}', now(), now() - interval '40 days', now() - interval '10 days', now() - interval '31 days'),
  ('12000000-0000-4000-8000-000000000f06', null, '{}', now(), now() - interval '40 days', now() + interval '10 days', now() - interval '29 days');
insert into public.application_draft_links (draft_id, token_hash) values
  ('12000000-0000-4000-8000-000000000f03', repeat('3', 64)), ('12000000-0000-4000-8000-000000000f05', repeat('5', 64)),
  ('12000000-0000-4000-8000-000000000f01', repeat('1', 64));
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, draft_id, status, created_at, sent_at)
values
  ('draft:12000000-0000-4000-8000-000000000f01:1', 'draft_resume', 'live@example.test', '{}', '{}', '12000000-0000-4000-8000-000000000f01', 'sent', now() - interval '8 days', now() - interval '8 days'),
  ('draft:12000000-0000-4000-8000-000000000f01:2', 'draft_resume', 'live@example.test', '{}', '{}', '12000000-0000-4000-8000-000000000f01', 'pending', now() - interval '8 days', null),
  ('draft:12000000-0000-4000-8000-000000000f01:3', 'draft_resume', 'live@example.test', '{}', '{}', '12000000-0000-4000-8000-000000000f01', 'sent', now() - interval '6 days', now() - interval '6 days'),
  ('draft:12000000-0000-4000-8000-000000000f02:1', 'draft_resume', 'gone@example.test', '{}', '{}', '12000000-0000-4000-8000-000000000f02', 'pending', now() - interval '1 hour', null);
-- as role:
reset role;
select set_config('request.jwt.claims', '', true);
do $$ declare r jsonb; begin
  r := public.purge_admissions_housekeeping();
  if (r ->> 'draft_emails')::int <> 3 or (r ->> 'drafts_wiped')::int <> 1 or (r ->> 'drafts_deleted')::int <> 2 then
    raise exception 'counts %', r;
  end if;
  if not (r ?& array['reservations', 'sessions', 'emails', 'cron_runs']) then raise exception 'old keys %', r; end if;
  if (select array_agg(right(id::text, 3) order by id) from public.application_drafts
      where id::text like '12000000-0000-4000-8000-000000000f0%')
     is distinct from array['f01', 'f02', 'f04', 'f06'] then
    raise exception 'wrong drafts kept';
  end if;
  if (select (email, data) from public.application_drafts where id = '12000000-0000-4000-8000-000000000f02')
     is distinct from (null::text, '{}'::jsonb) then
    raise exception 'expired draft not wiped';
  end if;
  if (select (email, data) from public.application_drafts where id = '12000000-0000-4000-8000-000000000f01')
     is distinct from ('live@example.test'::text, '{"campusId": "a"}'::jsonb) then
    raise exception 'live draft touched';
  end if;
  if (select count(*) from public.application_draft_links where token_hash in (repeat('3', 64), repeat('5', 64))) <> 0 then
    raise exception 'links of deleted drafts kept';
  end if;
  if (select array_agg(event_key) from public.admissions_email_outbox where kind = 'draft_resume')
     is distinct from array['draft:12000000-0000-4000-8000-000000000f01:3'] then
    raise exception 'wrong resume rows kept';
  end if;
end $$;

-- probe: D9 check_public_rate_limit takes the draft buckets: the IP ones need a hex key, the global one takes none
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare n integer := 0; begin
  if not public.check_public_rate_limit('draft_ip', repeat('a', 64)) then raise exception 'draft_ip'; end if;
  if not public.check_public_rate_limit('draft_use_ip', repeat('a', 64)) then raise exception 'draft_use_ip'; end if;
  if not public.check_public_rate_limit('draft_global') then raise exception 'draft_global'; end if;
  begin perform public.check_public_rate_limit('draft_ip'); exception when others then n := n + 1; end;
  begin perform public.check_public_rate_limit('draft_global', repeat('a', 64)); exception when others then n := n + 1; end;
  begin perform public.check_public_rate_limit('draft_live', repeat('a', 64)); exception when others then n := n + 1; end;
  if n <> 3 then raise exception 'refused %', n; end if;
  for i in 2 .. 10 loop perform public.check_public_rate_limit('draft_ip', repeat('b', 64)); end loop;
  if not public.check_public_rate_limit('draft_ip', repeat('b', 64)) then raise exception 'tenth refused'; end if;
  if public.check_public_rate_limit('draft_ip', repeat('b', 64)) then raise exception 'eleventh allowed'; end if;
end $$;
-- as role:
select 1;
