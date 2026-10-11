-- Role matrix for 20261013100000_admissions_health_documents_storage, VISIBILITY file (admissions slice 4,
-- docs/admissions/PORT-PLAN.md): reads of application_health_info,
-- application_documents and files in the admissions-documents bucket, and
-- every write path denied. Read probes raise unless the stated row or file
-- is visible (or the count holds), so the expect line lists the roles for
-- which the statement holds; SV6, SV7 and SV10 raise if something IS
-- visible, so they expect every role. Write probes expect none; storage
-- update and delete probes raise when no row is affected, because RLS hides
-- rows silently, and the delete probe switches off the storage delete guard
-- first so only RLS decides. All fixture rows and files are invented (ids
-- 9e040000-...); files are storage.objects rows with no bytes.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261013100000_admissions_health_documents_storage_visibility.sql

-- ================================================================ health rows (D-4a: can_view_health AND in scope; Manager and Auditor need the capability too)

-- probe: HV1 Grade 3, no capability rows
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV2 Grade 3, health on all five, AO {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV3 Grade 3, health on Manager only
-- expect: Manager
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV4 Grade 3, health on Auditor only
-- expect: Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV5 Grade 3, health on all five, AO {preschool} (out of band)
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV6 Nursery 1, health on all five, AO {preschool}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000002') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV7 Grade 3, AO {primary} without health, Manager and Auditor with health
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV8 Grade 3, AO with health only (no bands, no all_grades)
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV9 Grade 11 (unbanded), AO with all three bands, health on all five
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV10 Grade 11, AO with all_grades and health
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV11a legacy label '2027', AO with all three bands and health
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000005') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV11b legacy label '2027', AO with all_grades and health
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000005') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV11c free-text Other, AO with all three bands and health
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000006') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV11d free-text Other, AO with all_grades and health
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000006') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV13 Grade 3, AO {primary} with can_decide but no health; Manager and Auditor with health
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV14 Grade 3, Manager and AO with can_decide, nobody has health
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV15 Grade 3 moved to Grade 7, health on all five, AO {primary} loses it
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');

update public.applications set year_group_applied_for = 'Grade 7' where id = '9e040000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV15b Grade 3 moved to Grade 7, health on all five, AO {jhs} gains it
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');

update public.applications set year_group_applied_for = 'Grade 7' where id = '9e040000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: HV16 AO {primary} with health sees exactly 1 health row
-- expect: Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, true);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_health_info where id in ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000a00000006');
  if c <> 1 then raise exception 'count %', c; end if;
end $$;

-- probe: HV17 health on all five: Manager and Auditor see all 6
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Auditor' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_health_info where id in ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000a00000006');
  if c <> 6 then raise exception 'count %', c; end if;
end $$;

-- ================================================================ document rows (scope only, no health capability; D-4j)

-- probe: DV1 Grade 3, no capability rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV2 Grade 3, AO {primary} without health; Attendant and Accountant with health
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true),
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV3 Grade 3, AO {preschool}
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV4 Nursery 1, AO {primary}
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000002') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV5 Grade 11, AO with all three bands
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV6 Grade 11, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV6 legacy '2027', AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000005') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV6 free-text Other, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000006') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV7 Grade 3, AO with health only
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV8 Grade 3 moved to Grade 7, AO {primary} loses it
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');

update public.applications set year_group_applied_for = 'Grade 7' where id = '9e040000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_documents where id = '9e040000-0000-4000-8000-000d00000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DV9a AO {primary} sees exactly 1 document row
-- expect: Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_documents where id in ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000d00000006');
  if c <> 1 then raise exception 'count %', c; end if;
end $$;

-- probe: DV9b Manager and Auditor see all 6 document rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_documents where id in ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000d00000006');
  if c <> 6 then raise exception 'count %', c; end if;
end $$;

-- ================================================================ files in admissions-documents (readable only through a visible row with exactly that path)

-- probe: SV1 Grade 3 file, no capability rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV2 Grade 3 file, AO {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV3 Grade 3 file, AO {preschool}
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV4 Grade 11 file, AO with all three bands
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV5a Grade 11 file, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV5b legacy '2027' file, AO with all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV6 a file with no document row is invisible to everyone
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000009/orphan.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000009/orphan.pdf') then
    raise exception 'visible';
  end if;
end $$;

-- probe: SV7a a file named like a row's path plus a suffix is invisible
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdfx');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdfx') then
    raise exception 'visible';
  end if;
end $$;

-- probe: SV7b a file whose name differs from a row's path only by case is invisible
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'PENDING/9E040000-0000-4000-8000-000400000001/DOC1.PDF');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'PENDING/9E040000-0000-4000-8000-000400000001/DOC1.PDF') then
    raise exception 'visible';
  end if;
end $$;

-- probe: SV7c a file whose name is a strict prefix of a row's path is invisible
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1') then
    raise exception 'visible';
  end if;
end $$;

-- probe: SV8 Grade 3 moved to Grade 7: the file follows, AO {primary} loses it
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');

update public.applications set year_group_applied_for = 'Grade 7' where id = '9e040000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: SV9a AO {primary} sees exactly 1 file
-- expect: Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from storage.objects where bucket_id = 'admissions-documents' and name like 'pending/9e040000-%';
  if c <> 1 then raise exception 'count %', c; end if;
end $$;

-- probe: SV9b Manager and Auditor see all 6 files
-- expect: Manager,Auditor
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$
declare c int;
begin
  select count(*) into c from storage.objects where bucket_id = 'admissions-documents' and name like 'pending/9e040000-%';
  if c <> 6 then raise exception 'count %', c; end if;
end $$;

-- probe: SV10 a receipts file at a document row's path doesn't make an admissions file appear
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
set local storage.allow_delete_query = 'true';
delete from storage.objects where bucket_id = 'admissions-documents' and name like 'pending/9e040000-%';
insert into storage.objects (bucket_id, name) values ('receipts', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf');
-- as role:
do $$
declare c int;
begin
  select count(*) into c from storage.objects where bucket_id = 'admissions-documents' and name like 'pending/9e040000-%';
  if c <> 0 then raise exception 'count %', c; end if;
end $$;

-- ================================================================ writes are denied for every role, including Manager

-- probe: W1 insert a health row
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
delete from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001';
-- as role:
insert into public.application_health_info (application_id) values ('9e040000-0000-4000-8000-000400000001');

-- probe: W2 update a health row
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
update public.application_health_info set has_medical_conditions = true;

-- probe: W3 delete a health row
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
delete from public.application_health_info;

-- probe: W4 insert a document row
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
insert into public.application_documents (application_id, document_type) values ('9e040000-0000-4000-8000-000400000001', 'other');

-- probe: W5 update a document row
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
update public.application_documents set status = 'approved';

-- probe: W6 delete a document row
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
delete from public.application_documents;

-- probe: W7 insert a health row as an AO holding all_grades, health and can_decide
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
delete from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
insert into public.application_health_info (application_id) values ('9e040000-0000-4000-8000-000400000001');

-- probe: SW1 insert a file into admissions-documents
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000009/new.pdf');

-- probe: SW2 insert a file at an existing row's path
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
set local storage.allow_delete_query = 'true';
delete from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf';
-- as role:
insert into storage.objects (bucket_id, name) values ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf');

-- probe: SW3 rename a file (raises if no row changes)
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$
declare n int;
begin
  update storage.objects set name = name || '.moved' where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no rows affected'; end if;
end $$;

-- probe: SW4 delete a file with the storage delete guard off (raises if no row goes)
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
set local storage.allow_delete_query = 'true';
do $$
declare n int;
begin
  delete from storage.objects where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no rows affected'; end if;
end $$;

-- probe: SW5 move an admissions file into receipts
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
-- as role:
do $$
declare n int;
begin
  update storage.objects set bucket_id = 'receipts' where bucket_id = 'admissions-documents' and name = 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no rows affected'; end if;
end $$;

-- probe: SW6 move a receipts file into admissions-documents (Manager can update receipts)
-- expect: none
insert into public.families (id) values ('9e040000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e040000-0000-4000-8000-000300000001', '9e040000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e040000-0000-4000-8000-000300000002', '9e040000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e040000-0000-4000-8000-000300000003', '9e040000-0000-4000-8000-000100000001', 'Child 3 Fixture'),
  ('9e040000-0000-4000-8000-000300000004', '9e040000-0000-4000-8000-000100000001', 'Child 4 Fixture'),
  ('9e040000-0000-4000-8000-000300000005', '9e040000-0000-4000-8000-000100000001', 'Child 5 Fixture'),
  ('9e040000-0000-4000-8000-000300000006', '9e040000-0000-4000-8000-000100000001', 'Child 6 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e040000-0000-4000-8000-000400000001', '9e040000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e040000-0000-4000-8000-000400000002', '9e040000-0000-4000-8000-000300000002', '2027/2028', 'Nursery 1'),
  ('9e040000-0000-4000-8000-000400000003', '9e040000-0000-4000-8000-000300000003', '2027/2028', 'Grade 8'),
  ('9e040000-0000-4000-8000-000400000004', '9e040000-0000-4000-8000-000300000004', '2027/2028', 'Grade 11'),
  ('9e040000-0000-4000-8000-000400000005', '9e040000-0000-4000-8000-000300000005', '2027/2028', '2027'),
  ('9e040000-0000-4000-8000-000400000006', '9e040000-0000-4000-8000-000300000006', '2027/2028', 'Other: Year 13');
insert into public.application_health_info (id, application_id, has_allergies_or_dietary_requirements, allergies_dietary_details) values
  ('9e040000-0000-4000-8000-000a00000001', '9e040000-0000-4000-8000-000400000001', true, 'Invented allergy 1'),
  ('9e040000-0000-4000-8000-000a00000002', '9e040000-0000-4000-8000-000400000002', true, 'Invented allergy 2'),
  ('9e040000-0000-4000-8000-000a00000003', '9e040000-0000-4000-8000-000400000003', true, 'Invented allergy 3'),
  ('9e040000-0000-4000-8000-000a00000004', '9e040000-0000-4000-8000-000400000004', true, 'Invented allergy 4'),
  ('9e040000-0000-4000-8000-000a00000005', '9e040000-0000-4000-8000-000400000005', true, 'Invented allergy 5'),
  ('9e040000-0000-4000-8000-000a00000006', '9e040000-0000-4000-8000-000400000006', true, 'Invented allergy 6');
insert into public.application_documents (id, application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000d00000001', '9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000002', '9e040000-0000-4000-8000-000400000002', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000003', '9e040000-0000-4000-8000-000400000003', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000004', '9e040000-0000-4000-8000-000400000004', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000005', '9e040000-0000-4000-8000-000400000005', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf', 'pending_review', '2026-10-01 09:00+00'),
  ('9e040000-0000-4000-8000-000d00000006', '9e040000-0000-4000-8000-000400000006', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf', 'pending_review', '2026-10-01 09:00+00');
insert into storage.objects (bucket_id, name) values
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000002/doc2.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000003/doc3.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000004/doc4.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000005/doc5.pdf'),
  ('admissions-documents', 'pending/9e040000-0000-4000-8000-000400000006/doc6.pdf');
insert into storage.objects (bucket_id, name) values ('receipts', '9e040000-receipt.pdf');
-- as role:
do $$
declare n int;
begin
  update storage.objects set bucket_id = 'admissions-documents' where bucket_id = 'receipts' and name = '9e040000-receipt.pdf';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no rows affected'; end if;
end $$;
