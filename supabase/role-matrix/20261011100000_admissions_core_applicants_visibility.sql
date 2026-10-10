-- Role matrix for 20261011100000_admissions_core_applicants, VISIBILITY file (admissions slice 3a,
-- docs/admissions/PORT-PLAN.md): grade-scoped reads on families, guardians,
-- students, applications, application_emergency_contacts and
-- application_notes, the live grade move, de-duplication, and the three
-- visibility helpers. Each probe raises unless the stated rows are visible
-- (or, for helpers, the stated value holds), so the expect line lists the
-- roles for which the statement holds. All fixture rows are invented (ids
-- 9e030000-...); capability rows go on the accounts the harness
-- impersonates (role, active, lowest id).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261011100000_admissions_core_applicants_visibility.sql

-- ================================================================ grade scope on applications

-- probe: V1 Grade 3, no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V2 Grade 3, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V3 Grade 3, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V4 Grade 3, AO with {preschool}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V5 Grade 3, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V6 Grade 3, AO with can_decide and can_view_health but no scope
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V7 Grade 11 (unbanded), no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000005') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V8 Grade 11, AO with all three bands
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000005') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V9 Grade 11, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000005') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V10 free-text Other grade, AO with all three bands
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000006') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V11 free-text Other grade, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000006') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V12 stored ' grade  3 ' resolves to primary (O-2)
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
update public.applications set year_group_applied_for = ' grade  3 ' where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V13 an inactive AO sees nothing even with {primary}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
update public.staff set active = false where id = (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: V14 Attendant and Accountant holding can_view_health still see nothing
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- ================================================================ live grade move (mirrors test_grade_change_moves_application_between_coordinators_live)

-- probe: M1 Grade 6, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
update public.applications set year_group_applied_for = 'Grade 6' where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: M2 Grade 6 moved to Grade 7, AO with {primary} loses it
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
update public.applications set year_group_applied_for = 'Grade 6' where id = '9e030000-0000-4000-8000-000400000004';
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: M3 Grade 6 moved to Grade 7, AO with {jhs} gains it
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
update public.applications set year_group_applied_for = 'Grade 6' where id = '9e030000-0000-4000-8000-000400000004';
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: M4 Grade 6, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
update public.applications set year_group_applied_for = 'Grade 6' where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: M5 the move carries the family, guardian, student, contact and note with it
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
update public.applications set year_group_applied_for = 'Grade 6' where id = '9e030000-0000-4000-8000-000400000004';
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000002')
     or not exists (select 1 from public.guardians where id = '9e030000-0000-4000-8000-000200000003')
     or not exists (select 1 from public.students where id = '9e030000-0000-4000-8000-000300000004')
     or not exists (select 1 from public.application_emergency_contacts where id = '9e030000-0000-4000-8000-000500000001')
     or not exists (select 1 from public.application_notes where id = '9e030000-0000-4000-8000-000600000001') then
    raise exception 'related rows did not follow the move';
  end if;
end $$;

-- ================================================================ per-table reads on the Grade 3 family

-- probe: T families, no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000002') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T families, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000002') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T families, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000002') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T guardians, no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.guardians where id = '9e030000-0000-4000-8000-000200000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T guardians, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.guardians where id = '9e030000-0000-4000-8000-000200000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T guardians, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.guardians where id = '9e030000-0000-4000-8000-000200000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T students, no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.students where id = '9e030000-0000-4000-8000-000300000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T students, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.students where id = '9e030000-0000-4000-8000-000300000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T students, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.students where id = '9e030000-0000-4000-8000-000300000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T application_emergency_contacts, no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_emergency_contacts where id = '9e030000-0000-4000-8000-000500000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T application_emergency_contacts, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_emergency_contacts where id = '9e030000-0000-4000-8000-000500000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T application_emergency_contacts, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_emergency_contacts where id = '9e030000-0000-4000-8000-000500000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T application_notes, no capability rows
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_notes where id = '9e030000-0000-4000-8000-000600000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T application_notes, AO with {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_notes where id = '9e030000-0000-4000-8000-000600000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: T application_notes, AO with {jhs}
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_notes where id = '9e030000-0000-4000-8000-000600000001') then
    raise exception 'not visible';
  end if;
end $$;

-- ================================================================ de-duplication: family F1 (Grade 1, Nursery 1, Grade 8)

-- probe: D1 AO with {primary,preschool}: one family, two guardians, two children
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary}', false, false, false);
-- as role:
do $$
declare
  ao boolean := public.has_role(array['Admissions Officer']);
  f int; g int; s int; a int;
begin
  select count(*) into f from public.families where id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into g from public.guardians where family_id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into s from public.students where id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  select count(*) into a from public.applications where student_id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  if (f, g, s, a) is distinct from (case when ao then (1, 2, 2, 2) else (1, 2, 3, 3) end) then
    raise exception 'counts (family, guardians, students, applications) = (%, %, %, %)', f, g, s, a;
  end if;
end $$;

-- probe: D2 AO with {primary,jhs}: the Nursery 1 child is hidden
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary,jhs}', false, false, false);
-- as role:
do $$
declare
  ao boolean := public.has_role(array['Admissions Officer']);
  f int; g int; s int; a int;
begin
  select count(*) into f from public.families where id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into g from public.guardians where family_id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into s from public.students where id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  select count(*) into a from public.applications where student_id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  if (f, g, s, a) is distinct from (case when ao then (1, 2, 2, 2) else (1, 2, 3, 3) end) then
    raise exception 'counts (family, guardians, students, applications) = (%, %, %, %)', f, g, s, a;
  end if;
end $$;
do $$ begin
  if exists (select 1 from public.students where id = '9e030000-0000-4000-8000-000300000002') and public.has_role(array['Admissions Officer']) then
    raise exception 'out-of-band sibling visible';
  end if;
end $$;

-- probe: D3 AO with {preschool}: family and both guardians, no sibling leak
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, false);
-- as role:
do $$
declare
  ao boolean := public.has_role(array['Admissions Officer']);
  f int; g int; s int; a int;
begin
  select count(*) into f from public.families where id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into g from public.guardians where family_id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into s from public.students where id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  select count(*) into a from public.applications where student_id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  if (f, g, s, a) is distinct from (case when ao then (1, 2, 1, 1) else (1, 2, 3, 3) end) then
    raise exception 'counts (family, guardians, students, applications) = (%, %, %, %)', f, g, s, a;
  end if;
end $$;

-- probe: D4 AO with all three bands: three bands still give one family
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
do $$
declare
  ao boolean := public.has_role(array['Admissions Officer']);
  f int; g int; s int; a int;
begin
  select count(*) into f from public.families where id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into g from public.guardians where family_id = '9e030000-0000-4000-8000-000100000001';
  select count(*) into s from public.students where id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  select count(*) into a from public.applications where student_id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000300000003');
  if (f, g, s, a) is distinct from (case when ao then (1, 2, 3, 3) else (1, 2, 3, 3) end) then
    raise exception 'counts (family, guardians, students, applications) = (%, %, %, %)', f, g, s, a;
  end if;
end $$;

-- probe: D5 AO with {primary}: a family whose only child is Grade 8 is hidden
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
delete from public.students where id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000001') then
    raise exception 'not visible';
  end if;
end $$;
do $$ begin
  if not exists (select 1 from public.guardians where id = '9e030000-0000-4000-8000-000200000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: D6 orphan family F5: Manager and Auditor only, not even all_grades
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000005') then
    raise exception 'not visible';
  end if;
end $$;
do $$ begin
  if not exists (select 1 from public.guardians where id = '9e030000-0000-4000-8000-000200000006') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: D7 a student with no application: Manager and Auditor only
-- expect: Manager,Auditor
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
delete from public.applications where id = '9e030000-0000-4000-8000-000400000004';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.students where id = '9e030000-0000-4000-8000-000300000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: D8 one student with Grade 1 and Grade 8 applications, AO with {jhs}: student once, Grade 1 hidden
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
delete from public.students where id in ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000300000002');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values ('9e030000-0000-4000-8000-000400000007', '9e030000-0000-4000-8000-000300000003', '2028/2029', 'Grade 1');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$
declare ao boolean := public.has_role(array['Admissions Officer']);
begin
  if (select count(*) from public.students where id = '9e030000-0000-4000-8000-000300000003') <> 1
     or not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000003')
     or not exists (select 1 from public.families where id = '9e030000-0000-4000-8000-000100000001')
     or (select count(*) from public.guardians where family_id = '9e030000-0000-4000-8000-000100000001') <> 2 then
    raise exception 'student, Grade 8 application, family or guardians missing';
  end if;
  if ao and exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000007') then
    raise exception 'out-of-band application of a visible student is visible';
  end if;
  if not ao and not exists (select 1 from public.applications where id = '9e030000-0000-4000-8000-000400000007') then
    raise exception 'Grade 1 application missing for a full reader';
  end if;
end $$;

-- ================================================================ helpers

-- probe: H admissions_application_visible is true in scope
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not public.admissions_application_visible('9e030000-0000-4000-8000-000400000004') then raise exception 'false'; end if;
end $$;

-- probe: H admissions_application_visible is false out of scope and for Attendant and Accountant
-- expect: Attendant,Accountant,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if public.admissions_application_visible('9e030000-0000-4000-8000-000400000004') then raise exception 'true'; end if;
end $$;

-- probe: H admissions_application_visible is not executable by anon
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
select public.admissions_application_visible('9e030000-0000-4000-8000-000400000004');

-- probe: H admissions_student_visible is true in scope
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not public.admissions_student_visible('9e030000-0000-4000-8000-000300000004') then raise exception 'false'; end if;
end $$;

-- probe: H admissions_student_visible is false out of scope and for Attendant and Accountant
-- expect: Attendant,Accountant,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if public.admissions_student_visible('9e030000-0000-4000-8000-000300000004') then raise exception 'true'; end if;
end $$;

-- probe: H admissions_student_visible is not executable by anon
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
select public.admissions_student_visible('9e030000-0000-4000-8000-000300000004');

-- probe: H admissions_family_visible is true in scope
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not public.admissions_family_visible('9e030000-0000-4000-8000-000100000002') then raise exception 'false'; end if;
end $$;

-- probe: H admissions_family_visible is false out of scope and for Attendant and Accountant
-- expect: Attendant,Accountant,Admissions Officer
insert into public.families (id, referral_source, comments) values
  ('9e030000-0000-4000-8000-000100000001', 'website', 'Invented fixture'), ('9e030000-0000-4000-8000-000100000002', '', ''), ('9e030000-0000-4000-8000-000100000003', '', ''),
  ('9e030000-0000-4000-8000-000100000004', '', ''), ('9e030000-0000-4000-8000-000100000005', 'other', '');
insert into public.guardians (id, family_id, first_name, surname, email, phone, relationship) values
  ('9e030000-0000-4000-8000-000200000001', '9e030000-0000-4000-8000-000100000001', 'Ama', 'Fixture', 'ama@example.test', '+233200000001', 'mother'),
  ('9e030000-0000-4000-8000-000200000002', '9e030000-0000-4000-8000-000100000001', 'Kofi', 'Fixture', 'kofi@example.test', '+233200000002', 'father'),
  ('9e030000-0000-4000-8000-000200000003', '9e030000-0000-4000-8000-000100000002', 'Esi', 'Fixture', 'esi@example.test', '+233200000003', 'guardian'),
  ('9e030000-0000-4000-8000-000200000004', '9e030000-0000-4000-8000-000100000003', 'Yaw', 'Fixture', 'yaw@example.test', '+233200000004', 'father'),
  ('9e030000-0000-4000-8000-000200000005', '9e030000-0000-4000-8000-000100000004', 'Adwoa', 'Fixture', 'adwoa@example.test', '+233200000005', 'mother'),
  ('9e030000-0000-4000-8000-000200000006', '9e030000-0000-4000-8000-000100000005', 'Kwesi', 'Fixture', 'kwesi@example.test', '+233200000006', 'other');
insert into public.students (id, family_id, full_name) values
  ('9e030000-0000-4000-8000-000300000001', '9e030000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e030000-0000-4000-8000-000300000002', '9e030000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e030000-0000-4000-8000-000300000003', '9e030000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e030000-0000-4000-8000-000300000004', '9e030000-0000-4000-8000-000100000002', 'Child Four Fixture'),
  ('9e030000-0000-4000-8000-000300000005', '9e030000-0000-4000-8000-000100000003', 'Child Five Fixture'), ('9e030000-0000-4000-8000-000300000006', '9e030000-0000-4000-8000-000100000004', 'Child Six Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e030000-0000-4000-8000-000400000001', '9e030000-0000-4000-8000-000300000001', '2027/2028', 'Grade 1'), ('9e030000-0000-4000-8000-000400000002', '9e030000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e030000-0000-4000-8000-000400000003', '9e030000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'), ('9e030000-0000-4000-8000-000400000004', '9e030000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3'),
  ('9e030000-0000-4000-8000-000400000005', '9e030000-0000-4000-8000-000300000005', '2027/2028', 'Grade 11'), ('9e030000-0000-4000-8000-000400000006', '9e030000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_emergency_contacts (id, application_id, name, relationship, phone) values
  ('9e030000-0000-4000-8000-000500000001', '9e030000-0000-4000-8000-000400000004', 'Aunt Fixture', 'aunt', '+233200000007');
insert into public.application_notes (id, application_id, content) values
  ('9e030000-0000-4000-8000-000600000001', '9e030000-0000-4000-8000-000400000004', 'Invented note');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
do $$ begin
  if public.admissions_family_visible('9e030000-0000-4000-8000-000100000002') then raise exception 'true'; end if;
end $$;

-- probe: H admissions_family_visible is not executable by anon
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
select public.admissions_family_visible('9e030000-0000-4000-8000-000100000002');
