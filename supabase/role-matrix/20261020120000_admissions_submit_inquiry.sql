-- Probes for 20261020120000_admissions_submit_inquiry (admissions slice 8,
-- docs/admissions/PORT-PLAN.md): submit_inquiry is service_role only, it
-- refuses while intake is closed, it takes grade, year and campus only as
-- ids from the active lists, it counts 5 per guardian email per day, and it
-- returns only INQ references.
--
-- Each probe puts a valid payload in the transaction-local setting
-- tcs.p during setup (as postgres), changes one thing, and the body reads
-- it back. Refusals are checked by SQLSTATE: TCS22 invalid, TCS03 closed,
-- TCS29 email limit.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261020120000_admissions_submit_inquiry.sql

-- probe: Q1 submit_inquiry: definer, search_path, returns text[], service_role only; helpers granted to nobody
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  if not (select prosecdef from pg_proc where oid = 'public.submit_inquiry(jsonb)'::regprocedure) then
    raise exception 'not security definer';
  end if;
  if not exists (select 1 from pg_proc where oid = 'public.submit_inquiry(jsonb)'::regprocedure
                 and proconfig @> array['search_path=public']) then raise exception 'no search_path'; end if;
  if (select prorettype from pg_proc where oid = 'public.submit_inquiry(jsonb)'::regprocedure) <> 'text[]'::regtype then
    raise exception 'return type changed';
  end if;
  if has_function_privilege('anon', 'public.submit_inquiry(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.submit_inquiry(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.submit_inquiry(jsonb)', 'execute') then
    raise exception 'submit_inquiry grants wrong';
  end if;
  foreach f in array array['public._public_invalid(text, text)', 'public._public_only_keys(jsonb, text[], text, text)',
                           'public._public_text(jsonb, text, text, integer, boolean, text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
             where p.proname in ('submit_inquiry', '_public_invalid', '_public_only_keys', '_public_text')
               and p.pronamespace = 'public'::regnamespace and a.grantee = 0) then
    raise exception 'public can execute a slice 8 submit function';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname in ('submit_inquiry', '_public_invalid', '_public_only_keys', '_public_text')) <> 4 then
    raise exception 'stray overload';
  end if;
end $$;
-- as role:
select 1;

-- probe: Q2 every JWT role is denied, with intake open and a valid payload
-- expect: none
update public.admissions_settings set public_intake_open = true where id = 1;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'q2@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
select public.submit_inquiry(current_setting('tcs.p')::jsonb);

-- probe: Q3 a signed-in non-staff user is denied
-- expect: none
update public.admissions_settings set public_intake_open = true where id = 1;
-- as role:
set local request.jwt.claims = '{"sub":"9e080000-0000-4000-8000-0000000000aa","role":"authenticated"}';
set local role authenticated;
select public.submit_inquiry('{}'::jsonb);

-- probe: Q4 even with a grant added by mistake, anon and every signed-in caller are refused
-- expect: none
update public.admissions_settings set public_intake_open = true where id = 1;
grant execute on function public.submit_inquiry(jsonb) to authenticated, anon;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'q4@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
select public.submit_inquiry(current_setting('tcs.p')::jsonb);

-- probe: Q5 service_role: a valid inquiry creates the family, guardians, students and inquiry applications, and returns only INQ refs in order
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
delete from public.admissions_reference_counters;
delete from public.audit_log where entity_table = 'applications';
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'other', 'referral_source_other', ' Radio ', 'comments', ' Hello ',
  'guardians', jsonb_build_array(
    jsonb_build_object('surname', ' Mensah ', 'first_name', 'Ama', 'relationship', 'mother', 'religion', 'Christian',
      'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', ' Q5@Example.TEST '),
    jsonb_build_object('surname', 'Mensah', 'first_name', 'Kwame', 'relationship', 'father', 'religion', 'Christian',
      'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000001', 'email', 'kwame@example.test')),
  'students', jsonb_build_array(
    jsonb_build_object('full_name', 'Esi Mensah', 'date_of_birth', '2022-05-06',
      'prior_schooling', 'not_yet_in_school', 'grade_id', (select id from public.admissions_grades where name = 'Nursery 1'),
      'academic_year', '2027/2028', 'campus_id', '00000000-0000-0000-0000-000000000002', 'month_of_enrollment', 'January'),
    jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03', 'current_school', 'N/A',
      'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare v_refs text[]; v_year text := to_char(clock_timestamp() at time zone 'Africa/Accra', 'YYYY');
begin
  v_refs := public.submit_inquiry(current_setting('tcs.p')::jsonb);
  if v_refs is distinct from array['INQ-' || v_year || '-0001', 'INQ-' || v_year || '-0002'] then
    raise exception 'refs wrong: %', v_refs;
  end if;
  perform set_config('tcs.refs', v_refs::text, true);
end $$;
reset role;
do $$ declare v_refs text[] := current_setting('tcs.refs')::text[];
begin
  if (select f.referral_source || '|' || f.referral_source_other || '|' || f.comments
      from public.families f join public.students s on s.family_id = f.id
      join public.applications a on a.student_id = s.id where a.inquiry_reference = v_refs[1]) <> 'other|Radio|Hello' then
    raise exception 'family wrong';
  end if;
  if (select array_agg(g.surname || '|' || g.email || '|' || g.relationship order by g.first_name)
      from public.guardians g join public.students s on s.family_id = g.family_id
      join public.applications a on a.student_id = s.id where a.inquiry_reference = v_refs[1])
     is distinct from array['Mensah|q5@example.test|mother', 'Mensah|kwame@example.test|father'] then
    raise exception 'guardians wrong';
  end if;
  if (select array_agg(s.full_name || '|' || s.date_of_birth || '|' || a.stage || '|' || a.year_group_applied_for || '|'
                       || a.academic_year || '|' || a.month_of_enrollment || '|' || coalesce(a.branch_id::text, '-')
                       || '|' || (a.application_reference is null)::text order by a.inquiry_reference)
      from public.applications a join public.students s on s.id = a.student_id
      where a.inquiry_reference = any (v_refs))
     is distinct from array[
       'Esi Mensah|2022-05-06|inquiry|Nursery 1|2027/2028|January|00000000-0000-0000-0000-000000000002|true',
       'Kofi Mensah|2019-02-03|inquiry|Grade 1|2026/2027|September|-|true'] then
    raise exception 'students or applications wrong';
  end if;
  if (select count(distinct s.family_id) from public.applications a join public.students s on s.id = a.student_id
      where a.inquiry_reference = any (v_refs)) <> 1 then raise exception 'children split across families'; end if;
  if exists (select 1 from public.audit_log where entity_table = 'applications') then
    raise exception 'service_role insert audited';
  end if;
end $$;

-- probe: Q6 service_role: closed intake refuses with TCS03 and writes and counts nothing
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = false where id = 1;
delete from public.public_rate_limits;
select set_config('tcs.families', (select count(*)::text from public.families), true);
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'q6@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  begin
    perform public.submit_inquiry(current_setting('tcs.p')::jsonb);
    raise exception 'accepted while closed';
  exception when sqlstate 'TCS03' then null;
  end;
end $$;
reset role;
do $$ begin
  if (select count(*)::text from public.families) <> current_setting('tcs.families') then raise exception 'rows written'; end if;
  if exists (select 1 from public.public_rate_limits) then raise exception 'counted while closed'; end if;
end $$;

-- probe: Q7 service_role: every invalid shape is refused with TCS22 and writes nothing
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
update public.admissions_grades set is_active = false where name = 'Grade 9';
update public.admissions_academic_years set is_active = false where label = '2027/2028';
select set_config('tcs.families', (select count(*)::text from public.families), true);
select set_config('tcs.g1', (select id::text from public.admissions_grades where name = 'Grade 1'), true);
select set_config('tcs.g9', (select id::text from public.admissions_grades where name = 'Grade 9'), true);
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'q7@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$
declare
  p jsonb := current_setting('tcs.p')::jsonb;
  g jsonb := p -> 'guardians' -> 0;
  s jsonb := p -> 'students' -> 0;
  bad jsonb[];
  b jsonb;
  i integer := 0;
begin
  bad := array[
    -- free text for grade, year or campus
    jsonb_set(p, '{students,0}', s || '{"year_group_applied_for": "Grade 1"}'),
    jsonb_set(p, '{students,0,grade_id}', '"Grade 1"'),
    jsonb_set(p, '{students,0,grade_id}', '"00000000-0000-0000-0000-000000000000"'),
    jsonb_set(p, '{students,0,grade_id}', to_jsonb(current_setting('tcs.g9'))),
    jsonb_set(p, '{students,0,academic_year}', '"2027/2028"'),
    jsonb_set(p, '{students,0,academic_year}', '"2099/2100"'),
    jsonb_set(p, '{students,0,academic_year}', '"Next year"'),
    jsonb_set(p, '{students,0}', s || '{"campus_id": "Main"}'),
    jsonb_set(p, '{students,0}', s || '{"campus_id": "00000000-0000-0000-0000-0000000000ff"}'),
    jsonb_set(p, '{students,0}', s || '{"campus_id": "00000000-0000-0000-0000-000000000002"}'),
    jsonb_set(p, '{students,0}', s || '{"branch_id": "00000000-0000-0000-0000-000000000001"}'),
    jsonb_set(p, '{students,0,grade_id}', '7'),
    -- counts
    jsonb_set(p, '{guardians}', '[]'),
    jsonb_set(p, '{guardians}', jsonb_build_array(g, g, g)),
    jsonb_set(p, '{students}', '[]'),
    jsonb_set(p, '{students}', jsonb_build_array(s, s, s, s, s, s)),
    p - 'students',
    jsonb_set(p, '{guardians}', '{}'),
    -- fields
    jsonb_set(p, '{guardians,0,phone}', '"0000000000"'),
    jsonb_set(p, '{guardians,0,phone}', '"+1234567"'),
    jsonb_set(p, '{guardians,0,phone}', '"+1234567890123456"'),
    jsonb_set(p, '{guardians,0,phone}', '"+233000ABC000"'),
    jsonb_set(p, '{guardians,0,email}', '"not-an-email"'),
    jsonb_set(p, '{guardians,0,surname}', '"   "'),
    jsonb_set(p, '{guardians,0}', g - 'religion'),
    jsonb_set(p, '{guardians,0,relationship}', '"aunt"'),
    jsonb_set(p, '{guardians,0,surname}', to_jsonb(repeat('x', 256))),
    jsonb_set(p, '{guardians,0}', g || '{"id": "x"}'),
    jsonb_set(p, '{students,0,date_of_birth}', '"2999-01-01"'),
    jsonb_set(p, '{students,0,date_of_birth}', '"2019-02-30"'),
    jsonb_set(p, '{students,0,date_of_birth}', '"03/02/2019"'),
    jsonb_set(p, '{students,0,month_of_enrollment}', '""'),
    jsonb_set(p, '{students,0}', s || '{"current_grade": "KG 2"}'),
    jsonb_set(p, '{referral_source}', '"tv"'),
    jsonb_set(p, '{referral_source}', '"other"'),
    jsonb_set(p, '{comments}', to_jsonb(repeat('x', 10001))),
    jsonb_set(p, '{comments}', '{"a": 1}'),
    p || '{"family_id": "x"}',
    '[]'::jsonb,
    '"x"'::jsonb
  ];
  foreach b in array bad loop
    i := i + 1;
    begin
      perform public.submit_inquiry(b);
      raise exception 'case % accepted', i;
    exception when sqlstate 'TCS22' then null;
    end;
  end loop;
end $$;
reset role;
do $$ begin
  if (select count(*)::text from public.families) <> current_setting('tcs.families') then raise exception 'rows written'; end if;
end $$;

-- probe: Q8 service_role: the sixth inquiry for one email in a day is refused with TCS29; case and a second guardian don't dodge it
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
delete from public.public_rate_limits;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'limit@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$
declare
  p jsonb := current_setting('tcs.p')::jsonb;
  g jsonb := p -> 'guardians' -> 0;
  i integer;
begin
  -- An invalid submission first: it must not count.
  begin
    perform public.submit_inquiry(jsonb_set(p, '{guardians,0,phone}', '"bad"'));
  exception when sqlstate 'TCS22' then null;
  end;
  for i in 1 .. 5 loop
    perform public.submit_inquiry(p);
  end loop;
  begin
    perform public.submit_inquiry(jsonb_set(p, '{guardians,0,email}', '"LIMIT@Example.test"'));
    raise exception 'sixth accepted';
  exception when sqlstate 'TCS29' then null;
  end;
  begin
    perform public.submit_inquiry(jsonb_set(p, '{guardians}',
      jsonb_build_array(jsonb_set(g, '{email}', '"other@example.test"'), g)));
    raise exception 'sixth accepted as second guardian';
  exception when sqlstate 'TCS29' then null;
  end;
  -- A different email still gets through.
  perform public.submit_inquiry(jsonb_set(p, '{guardians,0,email}', '"fresh@example.test"'));
end $$;
reset role;
do $$ begin
  if (select count from public.public_rate_limits where bucket = 'inquiry_email'
      and key_hash = encode(sha256(convert_to('limit@example.test', 'UTF8')), 'hex')) <> 5 then
    raise exception 'email count not 5';
  end if;
  if exists (select 1 from public.public_rate_limits where key_hash like '%@%') then raise exception 'raw email stored'; end if;
end $$;

-- probe: Q9 service_role: no de-duplication (D-8c parity); the same inquiry twice makes two families
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
select set_config('tcs.families', (select count(*)::text from public.families), true);
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'twice@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.submit_inquiry(current_setting('tcs.p')::jsonb);
select public.submit_inquiry(current_setting('tcs.p')::jsonb);
reset role;
do $$ begin
  if (select count(*) from public.families) <> current_setting('tcs.families')::integer + 2 then
    raise exception 'not two new families';
  end if;
end $$;

-- probe: Q10 service_role: phone edges (D-9d): 8 and 15 digits pass, spaces and dashes are stripped and the cleaned form stored; 7, 16, no plus and letters refused with TCS22
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'phone@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'N/A', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'), 'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$
declare
  p jsonb := current_setting('tcs.p')::jsonb;
  ph text;
  refs text[];
  stored text[] := '{}';
begin
  foreach ph in array array['+12345678', '+123456789012345', ' +233 00-000 0000 '] loop
    refs := public.submit_inquiry(jsonb_set(p, '{guardians,0,phone}', to_jsonb(ph)));
    stored := stored || (select g.phone from public.guardians g join public.students s on s.family_id = g.family_id
                         join public.applications a on a.student_id = s.id where a.inquiry_reference = refs[1]);
  end loop;
  if stored is distinct from array['+12345678', '+123456789012345', '+233000000000'] then
    raise exception 'stored phones wrong: %', stored;
  end if;
  foreach ph in array array['+1234567', '+1234567890123456', '0000000000', '+233000ABC000'] loop
    begin
      perform public.submit_inquiry(jsonb_set(p, '{guardians,0,phone}', to_jsonb(ph)));
      raise exception 'phone % accepted', ph;
    exception when sqlstate 'TCS22' then null;
    end;
  end loop;
end $$;
