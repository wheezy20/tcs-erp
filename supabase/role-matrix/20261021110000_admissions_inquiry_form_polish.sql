-- Probes for 20261021110000_admissions_inquiry_form_polish (admissions slice
-- 8b): public campus labels in either naming, the label guard, the options
-- shape and anon surface, the students current grade columns, and
-- submit_inquiry's new rules (religion and month lists, current grade or
-- prior schooling, current school, field paths in the error detail).
--
-- Each submit probe puts a valid payload in tcs.p during setup (as
-- postgres); the body changes one thing.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261021110000_admissions_inquiry_form_polish.sql

-- probe: L1 both campuses carry their public label, and their names are unchanged
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(name || '=' || coalesce(public_label, '-') order by name) from public.branches)
     is distinct from array['Annex=Annex (CK Road)', 'Main=Main Campus (Somey Down)'] then
    raise exception 'labels or names wrong: %', (select array_agg(name || '=' || coalesce(public_label, '-')) from public.branches);
  end if;
end $$;
-- as role:
select 1;

-- probe: L2 the label seeder labels both campuses whether the main one is called Main or Treasures Christian School
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.branches set public_label = null;
do $$ begin
  if public._admissions_seed_public_campus_labels() <> 2 then raise exception 'Main naming: not 2 labelled'; end if;
  if (select array_agg(coalesce(public_label, '-') order by name) from public.branches)
     is distinct from array['Annex (CK Road)', 'Main Campus (Somey Down)'] then raise exception 'Main naming: labels wrong'; end if;
end $$;
update public.branches set public_label = null;
update public.branches set name = 'Treasures Christian School' where name = 'Main';
do $$ begin
  if public._admissions_seed_public_campus_labels() <> 2 then raise exception 'hosted naming: not 2 labelled'; end if;
  if (select array_agg(name || '=' || coalesce(public_label, '-') order by name) from public.branches)
     is distinct from array['Annex=Annex (CK Road)', 'Treasures Christian School=Main Campus (Somey Down)'] then
    raise exception 'hosted naming: labels wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: L3 no signed-in role (or anon) can change a campus public label
-- expect: none
do $$ declare n integer;
begin
  update public.branches set public_label = 'Hacked' where name = 'Annex';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: L4 nor set one when adding a campus
-- expect: none
insert into public.branches (name, default_low_stock_threshold, public_label) values ('Probe Campus', 20, 'Probe');

-- probe: L5 the guard and the seeder are executable by no API role; helpers with fields too
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text; r text;
begin
  foreach f in array array['public.guard_branch_public_label()', 'public._admissions_seed_public_campus_labels()',
                           'public._public_invalid(text, text)', 'public._public_only_keys(jsonb, text[], text, text)',
                           'public._public_text(jsonb, text, text, integer, boolean, text)'] loop
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if has_function_privilege(r, f, 'execute') then raise exception '% can execute %', r, f; end if;
    end loop;
  end loop;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
             and proname in ('_public_invalid', '_public_only_keys', '_public_text') and pronargs in (1, 3, 5)) then
    raise exception 'an old helper signature is still there';
  end if;
end $$;
-- as role:
select 1;

-- probe: L6 anon surface unchanged: 170, and the options function keeps its grants
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable count is not 170';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname in ('set_admissions_public_applications', 'guard_branch_public_label',
                               '_admissions_seed_public_campus_labels', 'submit_inquiry')
             and has_function_privilege('anon', p.oid, 'execute')) then
    raise exception 'a slice 8b function is anon-executable';
  end if;
  if not has_function_privilege('anon', 'public.get_public_admissions_options()', 'execute') then
    raise exception 'options lost its anon grant';
  end if;
end $$;
-- as role:
select 1;

-- probe: L7 the options show labels, fall back to the name, and have exactly five keys
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.branches set public_label = null where name = 'Annex';
-- as role:
do $$ declare r jsonb := public.get_public_admissions_options();
begin
  if (select array_agg(k order by k) from jsonb_object_keys(r) k)
     is distinct from array['academic_years', 'applications_open', 'campuses', 'grades', 'intake_open'] then
    raise exception 'keys changed';
  end if;
  if (select array_agg(c ->> 'name' order by c ->> 'name') from jsonb_array_elements(r -> 'campuses') c)
     is distinct from array['Annex', 'Main Campus (Somey Down)'] then
    raise exception 'campus names wrong: %', r -> 'campuses';
  end if;
  if r::text ilike '%Treasures%' then raise exception 'internal name leaked'; end if;
end $$;

-- probe: L8 a student can't have both a current grade and a prior schooling value
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e0b0000-0000-4000-8000-000100000001');
do $$ begin
  begin
    insert into public.students (family_id, full_name, current_grade_id, prior_schooling)
    values ('9e0b0000-0000-4000-8000-000100000001', 'Both',
            (select id from public.admissions_grades where name = 'Grade 1'), 'not_yet_in_school');
    raise exception 'both stored';
  exception when check_violation then null;
  end;
  begin
    insert into public.students (family_id, full_name, prior_schooling)
    values ('9e0b0000-0000-4000-8000-000100000001', 'Odd', 'homeschool');
    raise exception 'unknown prior schooling stored';
  exception when check_violation then null;
  end;
  begin
    insert into public.students (family_id, full_name, prior_schooling)
    values ('9e0b0000-0000-4000-8000-000100000001', 'Creche', 'creche_or_daycare');
    raise exception 'creche_or_daycare stored';
  exception when check_violation then null;
  end;
end $$;
-- as role:
select 1;

-- probe: L9 service_role: refusals with TCS22 and the right field path
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
update public.admissions_grades set is_active = false where name = 'Grade 9';
select set_config('tcs.g9', (select id::text from public.admissions_grades where name = 'Grade 9'), true);
select set_config('tcs.g1', (select id::text from public.admissions_grades where name = 'Grade 1'), true);
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'l9@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'Little Stars', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
    'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$
declare
  p jsonb := current_setting('tcs.p')::jsonb;
  s jsonb := p -> 'students' -> 0;
  cases jsonb[];
  fields text[];
  i integer;
  v_detail text;
begin
  cases := array[
    jsonb_set(p, '{guardians,0,religion}', '"Catholic"'),
    jsonb_set(p, '{guardians,0,religion}', '"christian"'),
    jsonb_set(p, '{students,0,month_of_enrollment}', '"April"'),
    jsonb_set(p, '{students,0,month_of_enrollment}', '"January (Limited Admissions)"'),
    jsonb_set(p, '{students,0}', s || '{"prior_schooling": "not_yet_in_school"}'),
    jsonb_set(p, '{students,0}', (s - 'current_grade_id')),
    jsonb_set(p, '{students,0}', (s - 'current_grade_id') || '{"prior_schooling": "homeschool"}'),
    jsonb_set(p, '{students,0,current_grade_id}', to_jsonb(current_setting('tcs.g9'))),
    jsonb_set(p, '{students,0,current_grade_id}', '"KG 2"'),
    jsonb_set(p, '{students,0}', (s - 'current_grade_id') || '{"current_grade": "KG 2"}'),
    jsonb_set(p, '{students,0}', (s - 'current_grade_id') || '{"prior_schooling": "not_yet_in_school"}'),
    jsonb_set(p, '{students,0}', (s - 'current_grade_id') || '{"prior_schooling": "creche_or_daycare"}'),
    jsonb_set(p, '{students,0}', s - 'current_school'),
    jsonb_set(p, '{guardians,0,surname}', '""')
  ];
  fields := array[
    'guardians.0.religion', 'guardians.0.religion',
    'students.0.month_of_enrollment', 'students.0.month_of_enrollment',
    'students.0.current_grade_id', 'students.0.current_grade_id', 'students.0.current_grade_id',
    'students.0.current_grade_id', 'students.0.current_grade_id',
    'students.0',
    'students.0.current_school', 'students.0.current_grade_id', 'students.0.current_school',
    'guardians.0.surname'
  ];
  for i in 1 .. array_length(cases, 1) loop
    begin
      perform public.submit_inquiry(cases[i]);
      raise exception 'case % accepted', i;
    exception when sqlstate 'TCS22' then
      get stacked diagnostics v_detail = pg_exception_detail;
      if v_detail is distinct from fields[i] then
        raise exception 'case %: field % not %', i, v_detail, fields[i];
      end if;
    end;
  end loop;
end $$;

-- probe: L10 service_role: accepted shapes are stored as the cleaned, structured values
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(
    jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
      'religion', 'Prefer not to say', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'l10@example.test'),
    jsonb_build_object('surname', 'Mensah', 'first_name', 'Kwame', 'relationship', 'father',
      'religion', 'Traditional', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000001', 'email', 'l10b@example.test')),
  'students', jsonb_build_array(
    jsonb_build_object('full_name', 'A Not Yet', 'date_of_birth', '2024-05-14',
      'prior_schooling', 'not_yet_in_school', 'grade_id', (select id from public.admissions_grades where name = 'Pre Nursery'),
      'academic_year', '2026/2027', 'month_of_enrollment', 'January'),
    jsonb_build_object('full_name', 'B From Creche', 'date_of_birth', '2023-05-14', 'current_school', 'Happy Days Creche',
      'current_grade_id', (select id from public.admissions_grades where name = 'Pre Nursery'),
      'grade_id', (select id from public.admissions_grades where name = 'Nursery 1'),
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
    jsonb_build_object('full_name', 'C Graded', 'date_of_birth', '2019-02-03', 'current_school', 'Little Stars',
      'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
      'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
      'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.refs', public.submit_inquiry(current_setting('tcs.p')::jsonb)::text, true);
reset role;
do $$ declare v_refs text[] := current_setting('tcs.refs')::text[];
begin
  if (select array_agg(s.full_name || '|' || s.current_school || '|' || s.current_grade || '|'
                       || coalesce(g.name, '-') || '|' || coalesce(s.prior_schooling, '-') || '|' || a.month_of_enrollment
                       order by s.full_name)
      from public.applications a join public.students s on s.id = a.student_id
      left join public.admissions_grades g on g.id = s.current_grade_id
      where a.inquiry_reference = any (v_refs))
     is distinct from array[
       'A Not Yet|||-|not_yet_in_school|January',
       'B From Creche|Happy Days Creche||Pre Nursery|-|September',
       'C Graded|Little Stars||Kindergarten 2|-|September'] then
    raise exception 'stored students wrong';
  end if;
  if (select array_agg(gu.religion order by gu.first_name) from public.guardians gu
      join public.students s on s.family_id = gu.family_id
      join public.applications a on a.student_id = s.id
      where a.inquiry_reference = v_refs[1])
     is distinct from array['Prefer not to say', 'Traditional'] then
    raise exception 'religions wrong';
  end if;
end $$;

-- probe: L11 service_role: every religion in the list is accepted
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = true where id = 1;
select set_config('tcs.p', jsonb_build_object(
  'referral_source', 'website',
  'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
    'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233000000000', 'email', 'x@example.test')),
  'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah', 'date_of_birth', '2019-02-03',
    'current_school', 'Little Stars', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
    'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
    'academic_year', '2026/2027', 'month_of_enrollment', 'September'))
)::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare p jsonb := current_setting('tcs.p')::jsonb; r text; n integer := 0;
begin
  foreach r in array array['Christian', 'Muslim', 'Traditional', 'Other', 'Prefer not to say'] loop
    n := n + 1;
    perform public.submit_inquiry(jsonb_set(jsonb_set(p, '{guardians,0,religion}', to_jsonb(r)),
      '{guardians,0,email}', to_jsonb('rel' || n || '@example.test')));
  end loop;
end $$;

-- probe: L12 closed inquiries say enquiry (TCS03 message)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_settings set public_intake_open = false where id = 1;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare m text;
begin
  begin
    perform public.submit_inquiry('{}'::jsonb);
  exception when sqlstate 'TCS03' then
    get stacked diagnostics m = message_text;
    if m <> 'Online enquiries are closed' then raise exception 'message: %', m; end if;
    return;
  end;
  raise exception 'not refused';
end $$;

-- probe: L13 a role allowed to edit branches (can_write: Manager, Attendant) can still change other columns; only the label is guarded
-- expect: Manager,Attendant
do $$ declare n integer;
begin
  update public.branches set name = 'Annex Renamed', default_low_stock_threshold = 21 where name = 'Annex';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'no row updated'; end if;
  if (select public_label from public.branches where name = 'Annex Renamed') is distinct from 'Annex (CK Road)' then
    raise exception 'label changed';
  end if;
end $$;
