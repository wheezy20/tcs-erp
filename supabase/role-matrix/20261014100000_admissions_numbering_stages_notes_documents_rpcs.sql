-- Role matrix for 20261014100000_admissions_numbering_stages_notes_documents, RPC file (admissions slice 5,
-- docs/admissions/PORT-PLAN.md): move_application_to_document_review,
-- set_application_stage, add_application_note, update_application_note and
-- set_application_document_status as each role, with officer capability
-- variants (bands, all_grades, can_decide only, can_view_health only),
-- unbanded and legacy grades, wrong stages and statuses, and the two audit
-- rows. A probe calling an RPC succeeds only if the call does, so the
-- expect line lists the roles allowed to make it. All fixture rows are
-- invented (ids 9e050000-...).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261014100000_admissions_numbering_stages_notes_documents_rpcs.sql

-- ================================================================ move_application_to_document_review (Manager, or an in-scope officer; from inquiry or application only)

-- probe: R1 Grade 3 inquiry, AO {primary}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R2 Grade 3, AO all_grades
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R2b Grade 3, AO {primary} with can_decide and can_view_health (capabilities don't matter)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, true);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R3 Grade 3, AO {jhs}
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R3b Grade 3, AO {preschool}
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R4 Grade 3, AO with no capability row
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R5 Grade 3, AO with can_decide only
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R6 Grade 3, AO with can_view_health only
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R7 Grade 11 (unbanded), AO with all three bands
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000002');

-- probe: R8 Grade 11, AO all_grades
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000002');

-- probe: R9 free-text Other, AO with all three bands
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000003');

-- probe: R10 free-text Other, AO all_grades
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000003');

-- probe: R11 legacy label 2027, AO with all three bands
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000004');

-- probe: R12 legacy label 2027, AO all_grades
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000004');

-- probe: R13 every staff member inactive
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
update public.staff set active = false where not protected;
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R14 refused from document_review
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'document_review' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R14 refused from offer
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'offer' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R14 refused from enrolled
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'enrolled' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R14 refused from rejected
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'rejected' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R14 refused from waitlisted
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'waitlisted' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R14 refused from offer_declined
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'offer_declined' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');

-- probe: R20 from application (Grade 3), AO {primary}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-000400000005');

-- probe: R21 an unknown id
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review('9e050000-0000-4000-8000-00040000004d');

-- probe: R22 a null id
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.move_application_to_document_review(null);

-- probe: R23 out of scope and not found give the same error
-- expect: anon,Attendant,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$
declare m1 text; m2 text;
begin
  begin perform public.move_application_to_document_review('9e050000-0000-4000-8000-000400000006'); exception when others then m1 := sqlerrm; end;
  begin perform public.move_application_to_document_review('9e050000-0000-4000-8000-00040000004d'); exception when others then m2 := sqlerrm; end;
  if m1 is distinct from m2 then raise exception 'different errors: % / %', m1, m2; end if;
end $$;

-- probe: R24 the move writes one stage audit row with the actor, and bumps updated_at
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set updated_at = '2020-01-01' where id = '9e050000-0000-4000-8000-000400000001';
-- as role:
do $$ begin
  perform public.move_application_to_document_review('9e050000-0000-4000-8000-000400000001');
  if (select count(*) from public.audit_log where action = 'application_stage_changed'
        and entity_id = '9e050000-0000-4000-8000-000400000001' and actor_id = auth.uid()
        and before = jsonb_build_object('stage', 'inquiry')
        and after->>'stage' = 'document_review' and after->>'application_reference' is not null
        and (select array_agg(k order by k) from jsonb_object_keys(after) k) = array['application_reference', 'stage']) <> 1
     or (select updated_at from public.applications where id = '9e050000-0000-4000-8000-000400000001') < now() - interval '1 minute' then
    raise exception 'audit row or updated_at wrong';
  end if;
end $$;

-- ================================================================ set_application_stage (Manager only)

-- probe: T1 inquiry to waitlisted, with an AO holding everything
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'waitlisted');

-- probe: T2 inquiry to application
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'application');

-- probe: T3 rejected back to application (D-5b)
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'rejected' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'application');

-- probe: T3b moving out of rejected writes an audit row
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'rejected' where id = '9e050000-0000-4000-8000-000400000001';
-- as role:
do $$ begin
  perform public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'application');
  if (select count(*) from public.audit_log where action = 'application_stage_changed'
        and entity_id = '9e050000-0000-4000-8000-000400000001' and before->>'stage' = 'rejected' and after->>'stage' = 'application') <> 1 then
    raise exception 'no audit row';
  end if;
end $$;

-- probe: T4 waitlisted to document_review
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'waitlisted' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'document_review');

-- probe: T5 offer_declined back to application
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'offer_declined' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'application');

-- probe: T5b document_review to rejected
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'document_review' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'rejected');

-- probe: T6 target offer is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000005', 'offer');

-- probe: T6 target enrolled is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000005', 'enrolled');

-- probe: T6 target offer_declined is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000005', 'offer_declined');

-- probe: T6 target inquiry is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000005', 'inquiry');

-- probe: T10 an unknown stage is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'accepted');

-- probe: T11 a null stage is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', null);

-- probe: T12 the same stage is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000005', 'application');

-- probe: T13 nothing leaves enrolled
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'enrolled' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'application');

-- probe: T14 nothing leaves offer here
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.applications set stage = 'offer' where id = '9e050000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-000400000001', 'rejected');

-- probe: T15 an unknown application
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.set_application_stage('9e050000-0000-4000-8000-00040000004d', 'rejected');

-- ================================================================ add_application_note (Manager, or an in-scope officer)

-- probe: NO1 Grade 3, AO {primary}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', 'Invented staff note');

-- probe: NO2 Grade 3, AO {jhs}
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', 'Invented staff note');

-- probe: NO3 Grade 3, AO with no capability row
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', 'Invented staff note');

-- probe: NO4 Grade 3, AO with can_decide only
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', 'Invented staff note');

-- probe: NO5 Grade 11, AO with all three bands
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000002', 'Invented staff note');

-- probe: NO6 Grade 11, AO all_grades
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000002', 'Invented staff note');

-- probe: NO7 a blank note is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', '   ');

-- probe: NO8 a note over 10,000 characters is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', repeat('x', 10001));

-- probe: NO8b the RPC itself refuses 10,001 characters with its own message
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  perform public.add_application_note('9e050000-0000-4000-8000-000400000001', repeat('x', 10001));
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'A note can be at most 10,000 characters' then raise; end if;
end $$;

-- probe: NO9 a note of exactly 10,000 characters is accepted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-000400000001', repeat('x', 10000));

-- probe: NO10 the author is the caller, the time is now and the content is trimmed
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$
declare n public.application_notes;
begin
  n := public.add_application_note('9e050000-0000-4000-8000-000400000001', '  Invented trimmed note  ');
  if n.author_id is distinct from auth.uid() or n.created_at < now() - interval '1 minute'
     or n.content <> 'Invented trimmed note' or n.edited_at is not null then
    raise exception 'note identity or content wrong';
  end if;
end $$;

-- probe: NO11 an unknown application
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.add_application_note('9e050000-0000-4000-8000-00040000004d', 'Invented staff note');

-- ================================================================ update_application_note (the author only, while active and in scope)

-- probe: NU1 own note, AO {primary}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.update_application_note((select id from public.application_notes where author_id = auth.uid() and id::text like '9e050000-%'), 'Invented edit');

-- probe: NU2 own note after the AO loses scope ({jhs})
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
select public.update_application_note((select id from public.application_notes where author_id = auth.uid() and id::text like '9e050000-%'), 'Invented edit');

-- probe: NU3 someone else's note (the Auditor's)
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.update_application_note('9e050000-0000-4000-8000-000600000004', 'Invented edit');

-- probe: NU4 a note with no author
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.update_application_note('9e050000-0000-4000-8000-000600000009', 'Invented edit');

-- probe: NU5 an edit changes only the content and edited_at
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$
declare b public.application_notes; a public.application_notes;
begin
  select * into b from public.application_notes where id = (select id from public.application_notes where author_id = auth.uid() and id::text like '9e050000-%');
  a := public.update_application_note(b.id, '  Invented edit  ');
  if a.content <> 'Invented edit' or a.edited_at is null or a.author_id is distinct from b.author_id
     or a.created_at is distinct from b.created_at or a.application_id is distinct from b.application_id then
    raise exception 'edit changed more than content and edited_at';
  end if;
end $$;

-- probe: NU6 the author deactivated can't edit
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
update public.staff set active = false where id = (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1);
-- as role:
select public.update_application_note((select id from public.application_notes where author_id = auth.uid() and id::text like '9e050000-%'), 'Invented edit');

-- probe: NU7 a blank edit is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.update_application_note((select id from public.application_notes where author_id = auth.uid() and id::text like '9e050000-%'), '');

-- probe: NU8 an unknown note
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.update_application_note('9e050000-0000-4000-8000-00060000004d', 'Invented edit');

-- ================================================================ set_application_document_status (Manager, or an in-scope officer; audited)

-- probe: D1 pending_review to approved, AO {primary}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');

-- probe: D2 AO {jhs}
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');

-- probe: D3 AO with no capability row
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');

-- probe: D4 AO with can_view_health only
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');

-- probe: D5 AO with can_decide only
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');

-- probe: D6 Grade 11 document, AO with all three bands
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000003', 'approved');

-- probe: D6b Grade 11 document, AO all_grades
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000003', 'approved');

-- probe: D7 approved to rejected
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.application_documents set status = 'approved' where id = '9e050000-0000-4000-8000-000d00000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'rejected');

-- probe: D7b rejected back to pending_review
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.application_documents set status = 'rejected' where id = '9e050000-0000-4000-8000-000d00000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'pending_review');

-- probe: D7c pending_review to rejected
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'rejected');

-- probe: D8 a document with no file is refused with a clear message
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  perform public.set_application_document_status('9e050000-0000-4000-8000-000d00000002', 'approved');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'No file has been uploaded for this document' then raise; end if;
end $$;

-- probe: D9 target required is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'required');

-- probe: D10 an unknown status is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'lost');

-- probe: D11 the same status is refused
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'pending_review');

-- probe: D12 only the status changes
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$
declare b public.application_documents; a public.application_documents;
begin
  select * into b from public.application_documents where id = '9e050000-0000-4000-8000-000d00000001';
  a := public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');
  if a.status <> 'approved' or a.storage_path is distinct from b.storage_path or a.uploaded_at is distinct from b.uploaded_at
     or a.document_type <> b.document_type or a.application_id <> b.application_id then
    raise exception 'more than the status changed';
  end if;
end $$;

-- probe: D13 the audit row carries only the reference, type, old and new status (no path), and the actor
-- expect: Manager
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
-- as role:
do $$ begin
  perform public.set_application_document_status('9e050000-0000-4000-8000-000d00000001', 'approved');
  if (select count(*) from public.audit_log where action = 'application_document_status_changed'
        and entity_table = 'application_documents' and entity_id = '9e050000-0000-4000-8000-000d00000001' and actor_id = auth.uid()
        and before = jsonb_build_object('status', 'pending_review')
        and after = jsonb_build_object('status', 'approved', 'document_type', 'birth_certificate',
              'application_reference', (select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000005'))
        and after->>'application_reference' is not null) <> 1 then
    raise exception 'document audit row wrong';
  end if;
end $$;

-- probe: D14 an unknown document
-- expect: none
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
select public.set_application_document_status('9e050000-0000-4000-8000-000d0000004d', 'approved');

-- probe: D15 a status change with no signed-in actor writes no audit row
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e050000-0000-4000-8000-000300000002', '9e050000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e050000-0000-4000-8000-000300000003', '9e050000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e050000-0000-4000-8000-000300000004', '9e050000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e050000-0000-4000-8000-000300000005', '9e050000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e050000-0000-4000-8000-000300000006', '9e050000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values
  ('9e050000-0000-4000-8000-000400000001', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000002', '9e050000-0000-4000-8000-000300000002', '2027/2028', 'Grade 11', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000003', '9e050000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000004', '9e050000-0000-4000-8000-000300000004', '2027/2028', '2027', 'inquiry'),
  ('9e050000-0000-4000-8000-000400000005', '9e050000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'application'),
  ('9e050000-0000-4000-8000-000400000006', '9e050000-0000-4000-8000-000300000006', '2027/2028', 'Grade 8', 'inquiry');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e050000-0000-4000-8000-000d00000001', '9e050000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000005/d1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e050000-0000-4000-8000-000d00000002', '9e050000-0000-4000-8000-000400000005', 'passport_photo', null, 'required', null),
  ('9e050000-0000-4000-8000-000d00000003', '9e050000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e050000-0000-4000-8000-000400000002/d3.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into public.application_notes (id, application_id, author_id, content) values
  ('9e050000-0000-4000-8000-000600000001', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Attendant' and active order by id limit 1), 'Invented note by Attendant'),
  ('9e050000-0000-4000-8000-000600000002', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Manager' and active order by id limit 1), 'Invented note by Manager'),
  ('9e050000-0000-4000-8000-000600000003', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Accountant' and active order by id limit 1), 'Invented note by Accountant'),
  ('9e050000-0000-4000-8000-000600000004', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Auditor' and active order by id limit 1), 'Invented note by Auditor'),
  ('9e050000-0000-4000-8000-000600000005', '9e050000-0000-4000-8000-000400000001', (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), 'Invented note by Admissions Officer'),
  ('9e050000-0000-4000-8000-000600000009', '9e050000-0000-4000-8000-000400000001', null, 'Invented note, no author');
update public.application_documents set status = 'approved' where id = '9e050000-0000-4000-8000-000d00000001';
do $$ begin
  if not (not exists (select 1 from public.audit_log where entity_id = '9e050000-0000-4000-8000-000d00000001')) then raise exception 'audit row without an actor'; end if;
end $$;
-- as role:
select 1;
