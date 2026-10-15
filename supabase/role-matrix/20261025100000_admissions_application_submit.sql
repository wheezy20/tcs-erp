-- Probes for 20261025100000_admissions_application_submit (admissions
-- slice 9a, checkpoint 2; docs/admissions/PORT-PLAN.md, slice 9, D-9b,
-- D-9c, D-9e, D-9i, D-9j): submit_application is service_role only and
-- refuses every other caller even with a mistaken grant; it checks only the
-- applications switch; it refuses a submission with any required document
-- (the fee proof for every grade) missing, not reserved in this session,
-- not at the exact reserved path, not stored, or whose bytes don't match
-- its extension; it matches families, students and applications without
-- ever overwriting them, flags what matched, keeps health out of the
-- snapshot, counts the per-email limit, answers a repeat with the same
-- reference, and always answers with the APP reference alone. The match
-- flags table is read like application_documents and written by nobody.
--
-- Each value probe builds its own fixture as postgres (an open switch, a
-- live upload session, reservations with stored objects, a valid payload)
-- and then submits as service_role, as the Edge Function does. The
-- fixture block is the same in every probe that uses it.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261025100000_admissions_application_submit.sql
-- Run the probe files before the Edge Function integration tests (they
-- commit rows).

-- probe: A1 submit_application: definer, pinned search_path, (jsonb, text, jsonb) returns text, service_role only; helpers granted to nobody
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  f := 'public.submit_application(jsonb, text, jsonb)';
  if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception 'not definer'; end if;
  if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=public']) then
    raise exception 'no search_path';
  end if;
  if (select prorettype::regtype::text from pg_proc where oid = f::regprocedure) <> 'text' then
    raise exception 'does not return text';
  end if;
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or not has_function_privilege('service_role', f, 'execute') then
    raise exception 'grants wrong';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f::regprocedure and a.grantee = 0) then
    raise exception 'public can execute';
  end if;
  if (select count(*) from pg_proc where proname = 'submit_application') <> 1 then raise exception 'overloads'; end if;
  foreach f in array array['public._public_bool(jsonb, text, text, text)', 'public._public_phone_ok(text)',
                           'public._application_kind_for_extension(text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: A2 match flags table: RLS on, one select policy, select for authenticated only, nothing for anon or service_role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text; p text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.application_match_flags'::regclass) then
    raise exception 'RLS off';
  end if;
  if (select array_agg(policyname || ':' || cmd) from pg_policies
      where schemaname = 'public' and tablename = 'application_match_flags')
     is distinct from array['application_match_flags_select:SELECT'] then
    raise exception 'policies changed';
  end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      if has_table_privilege(r, 'public.application_match_flags', p) <> (r = 'authenticated' and p = 'select') then
        raise exception '% % wrong', r, p;
      end if;
    end loop;
  end loop;
  -- The sessions table still has no API privilege after the new column.
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_table_privilege(r, 'public.application_upload_sessions', 'select')
       or has_table_privilege(r, 'public.application_upload_sessions', 'update') then
      raise exception '% can touch upload sessions', r;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: A3 the anon-executable count stays 170, and submit_application is not among them
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare n integer;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
  if has_function_privilege('anon', 'public.submit_application(jsonb, text, jsonb)', 'execute') then
    raise exception 'submit_application is anon-executable';
  end if;
end $$;
-- as role:
select 1;

-- probe: A4 any JWT role calling submit_application directly with a valid submission is denied
-- expect: none
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
-- as role:
select pg_temp.sub(b) from fx;

-- probe: A5 even with grants added by mistake, anon and every signed-in caller are refused by the guard
-- expect: none
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
grant execute on function public.submit_application(jsonb, text, jsonb) to anon, authenticated;
-- as role:
select pg_temp.sub(b) from fx;

-- probe: A6 flags read: Manager, Auditor and an in-scope officer (no health capability) see a flag
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9a250000-0000-4000-8000-000000000001');
insert into public.students (id, family_id, full_name) values
  ('9a250000-0000-4000-8000-000000000002', '9a250000-0000-4000-8000-000000000001', 'Flag Child');
insert into public.applications (id, student_id, stage, academic_year, year_group_applied_for) values
  ('9a250000-0000-4000-8000-000000000003', '9a250000-0000-4000-8000-000000000002', 'application', '2026/2027', 'Grade 3');
insert into public.application_match_flags (application_id, family_matched, student_matched, outcome)
values ('9a250000-0000-4000-8000-000000000003', true, false, 'new_application');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_match_flags
                 where application_id = '9a250000-0000-4000-8000-000000000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: A7 flags read: an officer outside the band sees nothing; Manager and Auditor still do
-- expect: Manager,Auditor
insert into public.families (id) values ('9a250000-0000-4000-8000-000000000001');
insert into public.students (id, family_id, full_name) values
  ('9a250000-0000-4000-8000-000000000002', '9a250000-0000-4000-8000-000000000001', 'Flag Child');
insert into public.applications (id, student_id, stage, academic_year, year_group_applied_for) values
  ('9a250000-0000-4000-8000-000000000003', '9a250000-0000-4000-8000-000000000002', 'application', '2026/2027', 'Grade 3');
insert into public.application_match_flags (application_id, family_matched, student_matched, outcome)
values ('9a250000-0000-4000-8000-000000000003', true, false, 'new_application');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_match_flags
                 where application_id = '9a250000-0000-4000-8000-000000000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: A8 no role can insert, update or delete a flag
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9a250000-0000-4000-8000-000000000001');
insert into public.students (id, family_id, full_name) values
  ('9a250000-0000-4000-8000-000000000002', '9a250000-0000-4000-8000-000000000001', 'Flag Child');
insert into public.applications (id, student_id, stage, academic_year, year_group_applied_for) values
  ('9a250000-0000-4000-8000-000000000003', '9a250000-0000-4000-8000-000000000002', 'application', '2026/2027', 'Grade 3');
insert into public.application_match_flags (application_id, family_matched, student_matched, outcome)
values ('9a250000-0000-4000-8000-000000000003', true, false, 'new_application');
-- as role:
do $$ declare ok integer := 0;
begin
  begin
    insert into public.application_match_flags (application_id, family_matched, student_matched, outcome)
    values ('9a250000-0000-4000-8000-000000000003', false, false, 'new_application');
    ok := ok + 1;
  exception when others then null; end;
  begin
    update public.application_match_flags set outcome = 'possible_duplicate';
    ok := ok + 1;
  exception when others then null; end;
  begin
    delete from public.application_match_flags;
    ok := ok + 1;
  exception when others then null; end;
  if ok > 0 then raise exception '% writes went through', ok; end if;
end $$;

-- probe: A9 service_role: applications closed refuses (TCS03) and writes and counts nothing; the enquiries switch plays no part
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
insert into fx select pg_temp.fx(p_email => 'second.parent@example.com');
update public.admissions_settings set public_applications_open = false, public_intake_open = true where id = 1;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b1 jsonb; b2 jsonb; n integer;
begin
  select b into b1 from fx where b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'probe.parent@example.com';
  select b into b2 from fx where b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'second.parent@example.com';
  perform pg_temp.refused(b1, 'TCS03', 'closed applications, enquiries open');
  reset role;
  select count(*) into n from public.guardians where email like '%parent@example.com';
  if n <> 0 then raise exception 'wrote % guardians', n; end if;
  if exists (select 1 from public.public_rate_limits where bucket = 'application_email') then
    raise exception 'counted while closed';
  end if;
  update public.admissions_settings set public_applications_open = true, public_intake_open = false where id = 1;
  set local role service_role;
  if pg_temp.sub(b2) !~ '^APP-[0-9]{4}-[0-9]{4,}$' then raise exception 'refused with enquiries closed'; end if;
end $$;

-- probe: A10 service_role: a new family gets everything written, the APP reference alone comes back, no IP, no flag
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_types => array['application_fee_proof', 'previous_report']);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; ref text; a public.applications; s public.application_upload_sessions; n integer;
begin
  select fx.b into b from fx;
  ref := pg_temp.sub(b);
  if ref !~ '^APP-[0-9]{4}-[0-9]{4,}$' then raise exception 'answer %', ref; end if;
  reset role;
  select * into a from public.applications where application_reference = ref;
  if a.stage <> 'application' or a.inquiry_reference is not null or a.year_group_applied_for <> 'Grade 3'
     or a.academic_year <> '2026/2027' or a.month_of_enrollment <> 'September'
     or a.branch_id <> '00000000-0000-0000-0000-000000000001' or not a.declaration_agreed
     or a.declaration_signature_name <> 'Ama Mensah' or a.declaration_agreed_at is null
     or a.declaration_ip_address is not null then
    raise exception 'application %', row_to_json(a);
  end if;
  if (select count(*) from public.guardians g join public.students st on st.family_id = g.family_id
      where st.id = a.student_id and g.email = 'probe.parent@example.com' and g.phone = '+233590000000') <> 1 then
    raise exception 'guardian not written';
  end if;
  if not exists (select 1 from public.students st where st.id = a.student_id and st.full_name = 'Probe Child'
                 and st.gender = 'female' and st.nationality = 'Ghanaian' and st.current_school = 'Little Stars'
                 and st.current_grade_id = (select id from public.admissions_grades where name = 'Grade 2')
                 and st.prior_schooling is null and st.current_grade = '') then
    raise exception 'student not written';
  end if;
  if (select count(*) from public.application_emergency_contacts where application_id = a.id
      and name = 'Kofi Mensah' and phone = '+233240000000') <> 1 then
    raise exception 'emergency contact';
  end if;
  if not exists (select 1 from public.application_health_info where application_id = a.id
                 and has_medical_conditions and medical_conditions_details = 'HEALTH-SENTINEL asthma'
                 and not has_allergies_or_dietary_requirements) then
    raise exception 'health';
  end if;
  if (select array_agg(d.document_type || ':' || d.status || ':' || (d.storage_path = r.storage_path) order by d.document_type)
      from public.application_documents d
      join public.application_upload_reservations r on r.storage_path = d.storage_path
      where d.application_id = a.id and d.uploaded_at is not null and r.consumed_at is not null)
     is distinct from array['application_fee_proof:pending_review:true', 'previous_report:pending_review:true'] then
    raise exception 'documents';
  end if;
  select * into s from public.application_upload_sessions
  where token_hash = encode(sha256(convert_to(b ->> 'token', 'UTF8')), 'hex');
  if s.closed_at is null or s.submitted_application_id <> a.id then raise exception 'session not closed'; end if;
  if exists (select 1 from public.application_match_flags) then raise exception 'flag for a new family'; end if;
  select count(*) into n from public.public_rate_limits where bucket = 'application_email';
  if n <> 1 then raise exception 'email counted % times', n; end if;
end $$;

-- probe: A11 service_role: Annex refuses Grade 3; Main takes it
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_campus => 'Annex');
insert into fx select pg_temp.fx(p_campus => 'Main', p_email => 'main.parent@example.com');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b1 jsonb; b2 jsonb;
begin
  select b into b1 from fx where b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'probe.parent@example.com';
  select b into b2 from fx where b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'main.parent@example.com';
  perform pg_temp.refused(b1, 'TCS22', 'Annex with Grade 3');
  if pg_temp.sub(b2) !~ '^APP-' then raise exception 'Main refused'; end if;
end $$;

-- probe: A12 service_role: Nursery 1 without vaccination proof refuses; with it passes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_grade => 'Nursery 1');
insert into fx select pg_temp.fx(p_grade => 'Nursery 1', p_types => array['application_fee_proof', 'proof_of_vaccination'],
                                 p_email => 'vacc.parent@example.com');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b1 jsonb; b2 jsonb;
begin
  select b into b1 from fx where b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'probe.parent@example.com';
  select b into b2 from fx where b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'vacc.parent@example.com';
  perform pg_temp.refused(b1, 'TCS22', 'Nursery 1 without vaccination proof');
  if pg_temp.sub(b2) !~ '^APP-' then raise exception 'with vaccination proof refused'; end if;
end $$;

-- probe: A13 service_role: every other document but no fee proof refuses, and writes and counts nothing (D-9e)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_grade => 'Nursery 1',
  p_types => array['proof_of_vaccination', 'financial_clearance', 'previous_report']);
insert into fx select pg_temp.fx(p_email => 'g3.parent@example.com', p_types => array['previous_report']);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare c record;
begin
  for c in select b from fx loop
    perform pg_temp.refused(c.b, 'TCS22', 'no fee proof');
  end loop;
  reset role;
  if exists (select 1 from public.guardians where email like '%parent@example.com')
     or exists (select 1 from public.application_documents where storage_path like 'uploads/%')
     or exists (select 1 from public.public_rate_limits where bucket = 'application_email')
     or exists (select 1 from public.application_upload_reservations where consumed_at is not null)
     or exists (select 1 from public.application_upload_sessions where closed_at is not null) then
    raise exception 'a refused submission left something behind';
  end if;
end $$;

-- probe: A14 service_role: an unreserved id, another session's reservation, a type or path mismatch, a repeated type, too many or no documents refuse
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_types => array['application_fee_proof', 'previous_report']);
insert into fx select pg_temp.fx(p_email => 'other.parent@example.com');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; o jsonb; d0 jsonb; d1 jsonb;
begin
  select fx.b into b from fx where fx.b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'probe.parent@example.com';
  select fx.b into o from fx where fx.b -> 'payload' -> 'guardians' -> 0 ->> 'email' = 'other.parent@example.com';
  d0 := b -> 'payload' -> 'documents' -> 0;
  d1 := b -> 'payload' -> 'documents' -> 1;
  -- unreserved id
  perform pg_temp.refused(jsonb_set(b, '{payload,documents,0,reservation_id}', to_jsonb(gen_random_uuid()::text)),
                          'TCS22', 'unreserved id');
  -- another session's fee proof, with its own sniff
  perform pg_temp.refused(jsonb_set(jsonb_set(b, '{payload,documents,0}', o -> 'payload' -> 'documents' -> 0),
                                    '{sniffed}', (b -> 'sniffed') || (o -> 'sniffed')),
                          'TCS22', 'another session''s reservation');
  -- type mismatch: the previous report's reservation claimed as the fee proof
  perform pg_temp.refused(jsonb_set(jsonb_set(b, '{payload,documents,0,document_type}', '"previous_report"'),
                                    '{payload,documents,1,document_type}', '"application_fee_proof"'),
                          'TCS22', 'type mismatch');
  -- payload path differs from the reservation's
  perform pg_temp.refused(jsonb_set(b, '{payload,documents,0,path}', to_jsonb(d1 ->> 'path')),
                          'TCS22', 'path mismatch');
  -- a repeated type
  perform pg_temp.refused(jsonb_set(b, '{payload,documents}', jsonb_build_array(d0, d0)), 'TCS22', 'repeated type');
  -- five documents
  perform pg_temp.refused(jsonb_set(b, '{payload,documents}', jsonb_build_array(d0, d1, d1, d1, d1)),
                          'TCS22', 'five documents');
  -- none
  perform pg_temp.refused(jsonb_set(b, '{payload,documents}', '[]'), 'TCS22', 'no documents');
  perform pg_temp.refused(b #- '{payload,documents}', 'TCS22', 'documents key missing');
  -- an extra key on a document
  perform pg_temp.refused(jsonb_set(b, '{payload,documents,0,file_path}', '"x"'), 'TCS22', 'extra document key');
  -- and the untouched submission still goes through
  if pg_temp.sub(b) !~ '^APP-' then raise exception 'valid submission refused'; end if;
end $$;

-- probe: A15 service_role: a reserved path whose object doesn't exist refuses
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
-- storage.objects guards deletes, so the object is moved off the path instead.
update storage.objects set name = name || '.moved' where bucket_id = 'admissions-documents'
  and name = (select b -> 'payload' -> 'documents' -> 0 ->> 'path' from fx);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  perform pg_temp.refused((select b from fx), 'TCS22', 'no stored object');
end $$;

-- probe: A16 service_role: the byte check: missing, unknown, wrong kind or wrong path refuse; each extension with its kind passes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; c record; ext text; res uuid; p text; k text; ref text;
begin
  select fx.b into b from fx;
  perform pg_temp.refused(jsonb_set(b, '{sniffed}', '[]'), 'TCS22', 'no sniff');
  perform pg_temp.refused(jsonb_set(b, '{sniffed,0,kind}', '"unknown"'), 'TCS22', 'unknown kind');
  perform pg_temp.refused(jsonb_set(b, '{sniffed,0,kind}', '"png"'), 'TCS22', 'png bytes in a pdf');
  perform pg_temp.refused(jsonb_set(b, '{sniffed,0,path}', '"uploads/x/application_fee_proof.pdf"'),
                          'TCS22', 'sniff of another path');
  perform pg_temp.refused(jsonb_set(b, '{sniffed,0,reservation_id}', to_jsonb(gen_random_uuid()::text)),
                          'TCS22', 'sniff of another reservation');
  perform pg_temp.refused(jsonb_set(b, '{sniffed}', 'null'), 'TCS22', 'sniff null');
  perform pg_temp.refused(jsonb_set(b, '{sniffed}', '{}'), 'TCS22', 'sniff not an array');
  -- A refusal uses nothing up.
  reset role;
  if exists (select 1 from public.application_upload_reservations where consumed_at is not null) then
    raise exception 'refusal consumed a reservation';
  end if;
  -- Each extension with its own kind, and the jpeg kind refused for a png.
  for c in select * from (values ('pdf', 'pdf', true), ('jpg', 'jpeg', true), ('jpeg', 'jpeg', true),
                                 ('png', 'png', true), ('png', 'jpeg', false), ('jpg', 'pdf', false)) v (e, kind, ok) loop
    reset role;
    b := pg_temp.fx(p_email => 'kind.' || c.e || '.' || c.kind || '@example.com');
    res := (b -> 'payload' -> 'documents' -> 0 ->> 'reservation_id')::uuid;
    update public.application_upload_reservations set extension = c.e where id = res returning storage_path into p;
    update storage.objects set name = p where bucket_id = 'admissions-documents'
      and name = b -> 'payload' -> 'documents' -> 0 ->> 'path';
    b := jsonb_set(jsonb_set(jsonb_set(b, '{payload,documents,0,path}', to_jsonb(p)), '{sniffed,0,path}', to_jsonb(p)),
                   '{sniffed,0,kind}', to_jsonb(c.kind));
    set local role service_role;
    if c.ok then
      if pg_temp.sub(b) !~ '^APP-' then raise exception '% with % refused', c.e, c.kind; end if;
    else
      perform pg_temp.refused(b, 'TCS22', c.e || ' with ' || c.kind);
    end if;
  end loop;
end $$;

-- probe: A17 service_role: expired, used or cleaned reservations, a closed or expired session, a bad token refuse
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; res uuid; th text; c text;
begin
  select fx.b into b from fx;
  res := (b -> 'payload' -> 'documents' -> 0 ->> 'reservation_id')::uuid;
  th := encode(sha256(convert_to(b ->> 'token', 'UTF8')), 'hex');
  foreach c in array array['expired', 'consumed', 'cleaned', 'closed', 'session_expired'] loop
    reset role;
    if c = 'expired' then
      update public.application_upload_reservations set expires_at = now() - interval '1 minute' where id = res;
    elsif c = 'consumed' then
      update public.application_upload_reservations set consumed_at = now() where id = res;
    elsif c = 'cleaned' then
      update public.application_upload_reservations set cleaned_at = now(), cleanup_claimed_at = now() where id = res;
    elsif c = 'closed' then
      update public.application_upload_sessions set closed_at = now() where token_hash = th;
    else
      update public.application_upload_sessions set expires_at = now() - interval '1 minute',
        created_at = now() - interval '7 hours' where token_hash = th;
    end if;
    set local role service_role;
    perform pg_temp.refused(b, 'TCS22', c);
    reset role;
    update public.application_upload_reservations
    set expires_at = now() + interval '1 hour', consumed_at = null, cleaned_at = null, cleanup_claimed_at = null
    where id = res;
    update public.application_upload_sessions set closed_at = null, created_at = now(),
      expires_at = now() + interval '1 hour' where token_hash = th;
  end loop;
  set local role service_role;
  perform pg_temp.refused(jsonb_set(b, '{token}', to_jsonb(repeat('0', 64))), 'TCS22', 'unknown token');
  perform pg_temp.refused(jsonb_set(b, '{token}', '"not-a-token"'), 'TCS22', 'malformed token');
  perform pg_temp.refused(b #- '{token}', 'TCS22', 'no token');
  if pg_temp.sub(b) !~ '^APP-' then raise exception 'restored submission refused'; end if;
end $$;

-- probe: A18 service_role: a matched inquiry is advanced, keeps its INQ, gains an APP; nothing else of the family changes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
insert into public.families (id) values ('9a250000-0000-4000-8000-000000000011');
insert into public.guardians (family_id, surname, first_name, relationship, religion, address, town_city, phone, email)
values ('9a250000-0000-4000-8000-000000000011', 'Mensah', 'Ama', 'mother', 'Christian', '1 Probe Road', 'Accra',
        '+233590000000', 'Probe.Parent@Example.com');
insert into public.students (id, family_id, full_name, date_of_birth, current_school) values
  ('9a250000-0000-4000-8000-000000000012', '9a250000-0000-4000-8000-000000000011', 'PROBE child ', '2018-05-01', 'Old School');
insert into public.applications (id, student_id, stage, academic_year, year_group_applied_for) values
  ('9a250000-0000-4000-8000-000000000013', '9a250000-0000-4000-8000-000000000012', 'inquiry', '2026/2027', 'Grade 3');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare ref text; inq text; a public.applications; f public.application_match_flags;
begin
  reset role;
  select inquiry_reference into inq from public.applications where id = '9a250000-0000-4000-8000-000000000013';
  set local role service_role;
  ref := pg_temp.sub((select b from fx));
  reset role;
  select * into a from public.applications where id = '9a250000-0000-4000-8000-000000000013';
  if a.stage <> 'application' or a.inquiry_reference is distinct from inq or a.application_reference <> ref
     or a.branch_id is null or a.declaration_agreed_at is null or a.declaration_ip_address is not null then
    raise exception 'not advanced %', row_to_json(a);
  end if;
  if (select count(*) from public.applications x join public.students s on s.id = x.student_id
      where s.full_name ilike '%probe child%') <> 1 then
    raise exception 'a second application was made';
  end if;
  if (select count(*) from public.guardians where email = 'probe.parent@example.com') <> 1
     or (select count(*) from public.guardians where family_id = '9a250000-0000-4000-8000-000000000011') <> 1
     or (select count(*) from public.students where full_name ilike '%probe child%') <> 1 then
    raise exception 'family, guardians or student added';
  end if;
  if (select current_school from public.students where id = '9a250000-0000-4000-8000-000000000012') <> 'Old School' then
    raise exception 'student updated';
  end if;
  select * into f from public.application_match_flags where application_id = a.id;
  if f.outcome is distinct from 'inquiry_advanced' or not f.family_matched or not f.student_matched
     or f.matched_application_id is not null
     or f.differences -> 'student' ->> 'current_school' is distinct from 'Little Stars' then
    raise exception 'flag %', row_to_json(f);
  end if;
  if not exists (select 1 from public.application_health_info where application_id = a.id) then
    raise exception 'no health row';
  end if;
end $$;

-- probe: A19 service_role: a match past inquiry (enrolled, offer, rejected) is left untouched; a new flagged application is made
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into public.families (id) values ('9a250000-0000-4000-8000-000000000021');
insert into public.guardians (family_id, surname, first_name, relationship, phone, email)
values ('9a250000-0000-4000-8000-000000000021', 'Mensah', 'Ama', 'mother', '+233590000000', 'probe.parent@example.com');
insert into public.students (id, family_id, full_name, date_of_birth, student_id) values
  ('9a250000-0000-4000-8000-000000000022', '9a250000-0000-4000-8000-000000000021', 'Probe Child', '2018-05-01', '26030001');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare st text; old public.applications; after public.applications; ref text; a public.applications;
  f public.application_match_flags;
begin
  foreach st in array array['enrolled', 'offer', 'rejected'] loop
    reset role;
    delete from public.application_match_flags;
    delete from public.application_health_info;
    delete from public.application_emergency_contacts;
    delete from public.application_documents;
    delete from public.applications;
    insert into public.applications (student_id, stage, academic_year, year_group_applied_for, branch_id)
    values ('9a250000-0000-4000-8000-000000000022', st, '2026/2027', 'Grade 3', '00000000-0000-0000-0000-000000000001')
    returning * into old;
    insert into fx select pg_temp.fx();
    set local role service_role;
    ref := pg_temp.sub((select b from fx order by ctid desc limit 1));
    reset role;
    select * into after from public.applications where id = old.id;
    if row_to_json(after)::text <> row_to_json(old)::text then raise exception '% application changed', st; end if;
    if (select student_id from public.students where id = '9a250000-0000-4000-8000-000000000022') <> '26030001' then
      raise exception 'student id changed';
    end if;
    select * into a from public.applications where application_reference = ref;
    if a.id = old.id or a.stage <> 'application' or a.student_id <> old.student_id then
      raise exception '% no new application', st;
    end if;
    select * into f from public.application_match_flags where application_id = a.id;
    if f.outcome is distinct from 'possible_duplicate' or f.matched_application_id is distinct from old.id
       or not f.student_matched then
      raise exception '% flag %', st, row_to_json(f);
    end if;
    if not exists (select 1 from public.application_health_info where application_id = a.id)
       or not exists (select 1 from public.application_emergency_contacts where application_id = a.id)
       or not exists (select 1 from public.application_documents where application_id = a.id) then
      raise exception '% new application incomplete', st;
    end if;
  end loop;
end $$;

-- probe: A20 service_role: a matched family gains and changes no guardian; differences are recorded; the snapshot refuses health keys
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
insert into public.families (id, created_at) values
  ('9a250000-0000-4000-8000-000000000031', now() - interval '2 days'),
  ('9a250000-0000-4000-8000-000000000032', now() - interval '1 day');
-- Two families share the email; only the newer one holds this child.
insert into public.guardians (family_id, surname, first_name, relationship, phone, email) values
  ('9a250000-0000-4000-8000-000000000031', 'Mensah', 'Ama', 'mother', '+233200000000', 'probe.parent@example.com'),
  ('9a250000-0000-4000-8000-000000000032', 'Mensah', 'Ama', 'mother', '+233200000000', 'probe.parent@example.com');
insert into public.students (id, family_id, full_name, date_of_birth) values
  ('9a250000-0000-4000-8000-000000000033', '9a250000-0000-4000-8000-000000000032', 'Probe Child', '2018-05-01');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; ref text; a public.applications; f public.application_match_flags; g jsonb;
begin
  select fx.b into b from fx;
  -- A second guardian with an email the family doesn't have.
  b := jsonb_set(b, '{payload,guardians}', (b -> 'payload' -> 'guardians')
       || jsonb_build_array(jsonb_set(b -> 'payload' -> 'guardians' -> 0, '{email}', '"new.guardian@example.com"')));
  ref := pg_temp.sub(b);
  reset role;
  select * into a from public.applications where application_reference = ref;
  if a.student_id <> '9a250000-0000-4000-8000-000000000033' then raise exception 'joined the wrong family or student'; end if;
  if (select count(*) from public.guardians where email in ('probe.parent@example.com', 'new.guardian@example.com')) <> 2
     or exists (select 1 from public.guardians where email = 'probe.parent@example.com'
                and (phone <> '+233200000000' or address <> '')) then
    raise exception 'guardians added or changed';
  end if;
  select * into f from public.application_match_flags where application_id = a.id;
  if f.outcome is distinct from 'new_application' or not f.family_matched or not f.student_matched then
    raise exception 'flag %', row_to_json(f);
  end if;
  g := f.differences -> 'guardians';
  if jsonb_array_length(g) <> 2
     or g -> 0 ->> 'email' <> 'probe.parent@example.com' or (g -> 0 ->> 'new')::boolean
     or g -> 0 -> 'fields' ->> 'phone' <> '+233590000000' or g -> 0 -> 'fields' ->> 'address' <> '1 Probe Road'
     or g -> 0 -> 'fields' ? 'email'
     or g -> 1 ->> 'email' <> 'new.guardian@example.com' or not (g -> 1 ->> 'new')::boolean then
    raise exception 'differences %', f.differences;
  end if;
  begin
    update public.application_match_flags set differences = '{"health_info": {"x": 1}}' where id = f.id;
    raise exception 'a health key was stored';
  exception when check_violation then null; end;
  begin
    update public.application_match_flags set differences = '{"student": {"medical_conditions_details": "x"}}' where id = f.id;
    raise exception 'a health field was stored under student';
  exception when check_violation then null; end;
end $$;

-- probe: A21 service_role: new, matched family, advanced inquiry and duplicate all answer with only an APP reference
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_email => 'one@example.com', p_child => 'Child One');
insert into fx select pg_temp.fx(p_email => 'one@example.com', p_child => 'Child Two');
insert into fx select pg_temp.fx(p_email => 'one@example.com', p_child => 'Child Two');
insert into fx select pg_temp.fx(p_email => 'three@example.com', p_child => 'Child Three');
insert into public.families (id) values ('9a250000-0000-4000-8000-000000000041');
insert into public.guardians (family_id, surname, first_name, relationship, phone, email)
values ('9a250000-0000-4000-8000-000000000041', 'X', 'Y', 'mother', '+233200000000', 'three@example.com');
insert into public.students (id, family_id, full_name, date_of_birth) values
  ('9a250000-0000-4000-8000-000000000042', '9a250000-0000-4000-8000-000000000041', 'Child Three', '2018-05-01');
insert into public.applications (student_id, stage, academic_year, year_group_applied_for) values
  ('9a250000-0000-4000-8000-000000000042', 'inquiry', '2026/2027', 'Grade 3');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare c record; ref text; outcomes text[] := '{}';
begin
  for c in select b from fx order by ctid loop
    ref := pg_temp.sub(c.b);
    if ref !~ '^APP-[0-9]{4}-[0-9]{4,}$' then raise exception 'answer %', ref; end if;
    reset role;
    outcomes := outcomes || coalesce((select f.outcome from public.application_match_flags f
                                      join public.applications a on a.id = f.application_id
                                      where a.application_reference = ref), 'new_family');
    set local role service_role;
  end loop;
  if outcomes <> array['new_family', 'new_application', 'possible_duplicate', 'inquiry_advanced'] then
    raise exception 'outcomes %', outcomes;
  end if;
end $$;

-- probe: A22 service_role: health answers live only in the health row, never in the flag
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
insert into fx select pg_temp.fx();
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare c record; ref text;
begin
  for c in select b from fx order by ctid loop
    ref := pg_temp.sub(c.b);
  end loop;
  reset role;
  if (select count(*) from public.application_health_info where medical_conditions_details like 'HEALTH-SENTINEL%') <> 2 then
    raise exception 'health not written for both';
  end if;
  if not exists (select 1 from public.application_match_flags) then raise exception 'second submission not flagged'; end if;
  if exists (select 1 from public.application_match_flags where differences::text like '%HEALTH-SENTINEL%'
             or differences::text like '%medical%') then
    raise exception 'health in the snapshot';
  end if;
end $$;

-- probe: A23 service_role: the sixth application for an email in a day refuses and counts nothing more; case and a second guardian don't dodge it; enquiries untouched
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx(p_child => 'Limit ' || i) from generate_series(1, 8) i;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare c record; i integer := 0; n integer; b jsonb;
begin
  for c in select fx.b from fx order by ctid limit 5 loop
    perform pg_temp.sub(c.b);
  end loop;
  select fx.b into b from fx order by ctid offset 5 limit 1;
  perform pg_temp.refused(jsonb_set(b, '{payload,guardians,0,email}', '"PROBE.Parent@example.com"'), 'TCS29', 'sixth, upper case');
  select fx.b into b from fx order by ctid offset 6 limit 1;
  b := jsonb_set(b, '{payload,guardians}', jsonb_build_array(
         jsonb_set(b -> 'payload' -> 'guardians' -> 0, '{email}', '"fresh@example.com"'),
         b -> 'payload' -> 'guardians' -> 0));
  perform pg_temp.refused(b, 'TCS29', 'sixth, as the second guardian');
  reset role;
  select max(count) into n from public.public_rate_limits where bucket = 'application_email';
  if n <> 5 then raise exception 'count %', n; end if;
  if exists (select 1 from public.public_rate_limits where bucket = 'application_email'
             and key_hash = encode(sha256(convert_to('fresh@example.com', 'UTF8')), 'hex')) then
    raise exception 'a refused submission kept its count';
  end if;
  if exists (select 1 from public.public_rate_limits where bucket = 'inquiry_email') then
    raise exception 'enquiry limit touched';
  end if;
  if (select count(*) from public.students where full_name like 'Limit %') <> 5 then raise exception 'not five'; end if;
end $$;

-- probe: A24 service_role: field rules refuse with the field path (religion, current grade, dates, phones, health text, keys, declaration, IP)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; c record; d text;
begin
  select fx.b into b from fx;
  for c in select * from (values
    ('{payload,guardians,0,religion}', '"Atheist"', 'guardians.0.religion'),
    ('{payload,guardians,0,phone}', '"0590000000"', 'guardians.0.phone'),
    ('{payload,guardians,0,phone}', '"+233 590000000"', 'guardians.0.phone'),
    ('{payload,guardians,0,phone}', '"+2330590000000"', 'guardians.0.phone'),
    ('{payload,guardians,0,email}', '"not-an-email"', 'guardians.0.email'),
    ('{payload,guardians,0,relationship}', '"aunt"', 'guardians.0.relationship'),
    ('{payload,guardians,0,ip}', '"1.2.3.4"', 'guardians.0'),
    ('{payload,student,date_of_birth}', '"01/05/2018"', 'student.date_of_birth'),
    ('{payload,student,date_of_birth}', '"2999-01-01"', 'student.date_of_birth'),
    ('{payload,student,gender}', '"x"', 'student.gender'),
    ('{payload,student,nationality}', '""', 'student.nationality'),
    ('{payload,student,prior_schooling}', '"not_yet_in_school"', 'student.current_grade_id'),
    ('{payload,student,current_grade_id}', '""', 'student.current_grade_id'),
    ('{payload,student,current_school}', '""', 'student.current_school'),
    ('{payload,student,month_of_enrollment}', '"March"', 'student.month_of_enrollment'),
    ('{payload,student,grade_id}', '"Grade 3"', 'student.grade_id'),
    ('{payload,student,academic_year}', '"2030/2031"', 'student.academic_year'),
    ('{payload,student,current_grade}', '"Grade 2"', 'student'),
    ('{payload,campus_id}', '"Main"', 'campus_id'),
    ('{payload,campus_id}', '""', 'campus_id'),
    ('{payload,emergency_contact,phone}', '"12345"', 'emergency_contact.phone'),
    ('{payload,emergency_contact,name}', '""', 'emergency_contact.name'),
    ('{payload,health_info,medical_conditions_details}', to_jsonb(repeat('a', 2001))::text, 'health_info.medical_conditions_details'),
    ('{payload,health_info,medical_conditions_details}', '""', 'health_info.medical_conditions_details'),
    ('{payload,health_info,has_allergies_or_dietary_requirements}', '"yes"', 'health_info.has_allergies_or_dietary_requirements'),
    ('{payload,declaration_agreed}', 'false', 'declaration_agreed'),
    ('{payload,declaration_agreed}', '"true"', 'declaration_agreed'),
    ('{payload,declaration_signature_name}', '"  "', 'declaration_signature_name'),
    ('{payload,declaration_agreed_at}', '"2026-01-01"', ''),
    ('{payload,declaration_ip_address}', '"1.2.3.4"', ''),
    ('{payload,guardians}', '[{}, {}, {}]', 'guardians')
  ) v (path, val, field) loop
    begin
      perform pg_temp.sub(jsonb_set(b, c.path::text[], c.val::jsonb));
      raise exception 'accepted % = %', c.path, left(c.val, 40);
    exception when sqlstate 'TCS22' then
      get stacked diagnostics d = pg_exception_detail;
      if d <> c.field then raise exception '% gave field "%" not "%"', c.path, d, c.field; end if;
    end;
  end loop;
  -- Not yet in school with no current school is fine, and a +44 phone too.
  b := jsonb_set(jsonb_set(jsonb_set(b, '{payload,student,prior_schooling}', '"not_yet_in_school"'),
                           '{payload,student,current_grade_id}', '""'), '{payload,student,current_school}', '""');
  b := jsonb_set(b, '{payload,emergency_contact,phone}', '"+442079460958"');
  if pg_temp.sub(b) !~ '^APP-' then raise exception 'valid variant refused'; end if;
  reset role;
  if exists (select 1 from public.applications where declaration_ip_address is not null) then
    raise exception 'an IP was stored';
  end if;
end $$;

-- probe: A25 service_role: a repeat with a used session returns the same reference and writes and counts nothing
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
insert into fx select pg_temp.fx();
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; r1 text; r2 text; before text; after text;
begin
  select fx.b into b from fx;
  r1 := pg_temp.sub(b);
  reset role;
  select (select count(*) from public.applications) || '/' || (select count(*) from public.families) || '/'
         || (select count(*) from public.application_documents) || '/' || (select sum(count) from public.public_rate_limits)
         || '/' || (select count(*) from public.application_health_info) into before;
  set local role service_role;
  r2 := pg_temp.sub(b);
  if r2 is distinct from r1 then raise exception 'repeat answered % not %', r2, r1; end if;
  reset role;
  select (select count(*) from public.applications) || '/' || (select count(*) from public.families) || '/'
         || (select count(*) from public.application_documents) || '/' || (select sum(count) from public.public_rate_limits)
         || '/' || (select count(*) from public.application_health_info) into after;
  if after <> before then raise exception 'repeat wrote: % then %', before, after; end if;
end $$;

-- probe: A26 service_role: for every active grade the options list equals the helper, fee proof first, and a submission missing any one required type refuses
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: an open switch, a live upload session with one reservation and
-- one stored object per type, and a valid payload for it. fx(b) holds the
-- bundle {token, sniffed, payload}; pg_temp.sub(b) submits it.
create function pg_temp.fx(p_grade text default 'Grade 3', p_campus text default 'Main',
  p_types text[] default array['application_fee_proof'], p_email text default 'probe.parent@example.com',
  p_child text default 'Probe Child', p_dob date default date '2018-05-01')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_docs jsonb := '[]';
  v_sn jsonb := '[]'; t text; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  foreach t in array p_types loop
    insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
    values (v_sid, t, 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
    insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
    v_docs := v_docs || jsonb_build_array(jsonb_build_object('document_type', t, 'reservation_id', v_id, 'path', v_p));
    v_sn := v_sn || jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf'));
  end loop;
  return jsonb_build_object('token', v_tok, 'sniffed', v_sn, 'payload', jsonb_build_object(
    'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
      'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
      'phone', '+233590000000', 'email', p_email)),
    'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
      'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
      'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    'campus_id', (select id from public.branches where name = p_campus)::text,
    'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
    'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
    'documents', v_docs,
    'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.sub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
-- Refused with this SQLSTATE, or fail.
create function pg_temp.refused(b jsonb, p_state text, p_what text) returns void language plpgsql as $f$
begin
  begin
    perform pg_temp.sub(b);
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception '% raised % (%) instead of %', p_what, sqlstate, sqlerrm, p_state;
  end;
  raise exception '% was accepted', p_what;
end $f$;
create temp table fx (b jsonb);
grant select on fx to public;
select 1;
-- as role:
do $$ declare g record; req text[]; t text; b jsonb; opt jsonb;
begin
  reset role;
  opt := public.get_public_admissions_options();
  for g in select * from public.admissions_grades where is_active loop
    req := public._application_required_document_types(g.id);
    if req[1] <> 'application_fee_proof' then raise exception '% fee proof not first', g.name; end if;
    if (select e -> 'required_document_types' from jsonb_array_elements(opt -> 'grades') e where e ->> 'id' = g.id::text)
       <> to_jsonb(req) then
      raise exception '% options differ from the helper', g.name;
    end if;
    foreach t in array req loop
      reset role;
      b := pg_temp.fx(p_grade => g.name, p_types => array_remove(req, t), p_email => 'miss.' || t || '@example.com');
      if cardinality(array_remove(req, t)) = 0 then
        b := jsonb_set(b, '{payload,documents}', '[]');
      end if;
      set local role service_role;
      set local request.jwt.claims = '{"role":"service_role"}';
      perform pg_temp.refused(b, 'TCS22', g.name || ' without ' || t);
    end loop;
  end loop;
end $$;
