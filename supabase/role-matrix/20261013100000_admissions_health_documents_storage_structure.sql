-- Role matrix for 20261013100000_admissions_health_documents_storage, STRUCTURE file (admissions slice 4,
-- docs/admissions/PORT-PLAN.md): grants and policy shape on the two tables,
-- the bucket settings and the single file policy, the checks (legal values
-- accepted, bad values refused) and delete behaviour. Structural probes do
-- their work as postgres in setup or read the catalog, and raise on
-- failure, so they expect every role. The bucket's size and type limits
-- and the public endpoint are only enforced by the Storage API, so
-- test-runner checks those over HTTP against the local stack. All fixture
-- rows are invented (ids 9e040000-...).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261013100000_admissions_health_documents_storage_structure.sql

-- ================================================================ grants, RLS and policy shape

-- probe: A1 anon has no privilege; authenticated select only; service_role full; RLS on; one select policy each
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare t text;
begin
  foreach t in array array['public.application_health_info', 'public.application_documents'] loop
    if has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'anon holds a privilege on %', t;
    end if;
    if not has_table_privilege('authenticated', t, 'SELECT')
       or has_table_privilege('authenticated', t, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'authenticated privileges wrong on %', t;
    end if;
    if not (has_table_privilege('service_role', t, 'SELECT') and has_table_privilege('service_role', t, 'INSERT')
            and has_table_privilege('service_role', t, 'UPDATE') and has_table_privilege('service_role', t, 'DELETE')) then
      raise exception 'service_role privileges wrong on %', t;
    end if;
    if not (select relrowsecurity from pg_class where oid = t::regclass) then
      raise exception 'RLS off on %', t;
    end if;
    if (select count(*) from pg_policies where schemaname || '.' || tablename = t) <> 1
       or exists (select 1 from pg_policies where schemaname || '.' || tablename = t and cmd <> 'SELECT') then
      raise exception 'policies wrong on %', t;
    end if;
  end loop;
end $$;

-- probe: A3 the predicates the policies call are security definer with search_path pinned
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (
    select 1 from pg_proc
    where oid in ('public.admissions_application_visible(uuid)'::regprocedure,
                  'public.admissions_grade_visible(text)'::regprocedure,
                  'public.has_admissions_capability(text)'::regprocedure,
                  'public.has_role(text[])'::regprocedure)
      and (not prosecdef or not coalesce('search_path=public' = any (proconfig), false))
  ) then
    raise exception 'a predicate lost security definer or its search_path';
  end if;
end $$;

-- probe: A4 no triggers on either table
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (select 1 from pg_trigger where not tgisinternal
             and tgrelid in ('public.application_health_info'::regclass, 'public.application_documents'::regclass)) then
    raise exception 'unexpected trigger';
  end if;
end $$;

-- ================================================================ bucket and file policy

-- probe: B1 the bucket is private, 10 MiB, PDF/JPEG/PNG only (checked as postgres: storage.buckets has RLS)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select (public, file_size_limit, (select array_agg(m order by m) from unnest(allowed_mime_types) m))
        from storage.buckets where id = 'admissions-documents')
     is distinct from (false, 10485760::bigint, array['application/pdf', 'image/jpeg', 'image/png']) then
    raise exception 'bucket settings wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: B2 exactly one admissions-documents policy, SELECT to authenticated; every storage.objects policy is bucket-scoped
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and coalesce(qual, '') || coalesce(with_check, '') like '%admissions-documents%') <> 1
     or not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and qual like '%admissions-documents%' and cmd = 'SELECT' and roles = array['authenticated']::name[]) then
    raise exception 'admissions-documents policies wrong';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and coalesce(qual, '') || coalesce(with_check, '') not like '%bucket_id%') then
    raise exception 'an unscoped storage.objects policy exists';
  end if;
end $$;

-- probe: B3 the file policy goes through application_documents
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and qual like '%admissions-documents%' and qual like '%application_documents%') then
    raise exception 'file policy does not reference application_documents';
  end if;
end $$;

-- probe: B4 neither table is published to realtime
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
             and schemaname = 'public' and tablename in ('application_health_info', 'application_documents')) then
    raise exception 'published to realtime';
  end if;
end $$;

-- probe: B5 the upsert form the migration uses (replayed here, not the migration itself) puts a bucket made public back to private
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
update storage.buckets set public = true, file_size_limit = 1, allowed_mime_types = array['image/heic'] where id = 'admissions-documents';
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('admissions-documents', 'admissions-documents', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
do $$ begin
  if (select (public, file_size_limit) from storage.buckets where id = 'admissions-documents') is distinct from (false, 10485760::bigint) then
    raise exception 'not restored';
  end if;
end $$;
-- as role:
select 1;

-- ================================================================ checks (run as postgres in setup)

-- probe: C1 legal values are accepted
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
insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000400000001', 'proof_of_vaccination', 'pending/9e040000-0000-4000-8000-000400000001/t0.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'financial_clearance', 'pending/9e040000-0000-4000-8000-000400000001/t1.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'previous_report', 'pending/9e040000-0000-4000-8000-000400000001/t2.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'application_fee_proof', 'pending/9e040000-0000-4000-8000-000400000001/t3.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'proof_of_funds', 'pending/9e040000-0000-4000-8000-000400000001/t4.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'passport_photo', 'pending/9e040000-0000-4000-8000-000400000001/t5.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'birth_certificate', 'pending/9e040000-0000-4000-8000-000400000001/t6.pdf', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000001', 'other', 'pending/9e040000-0000-4000-8000-000400000001/t7.pdf', 'pending_review', now());
insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values
  ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/s1.jpg', 'approved', now()),
  ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/s2.JPEG', 'rejected', now()),
  ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/s3.png', 'pending_review', now()),
  ('9e040000-0000-4000-8000-000400000002', 'passport_photo', null, 'required', null),
  ('9e040000-0000-4000-8000-000400000002', 'passport_photo', null, 'required', null);
update public.application_health_info set learning_or_physical_needs_details = repeat('x', 2000), medical_conditions_details = repeat('y', 2000),
  allergies_dietary_details = repeat('z', 2000), has_medical_conditions = true where id = '9e040000-0000-4000-8000-000a00000001';
-- as role:
select 1;

-- probe: C2 refused: health details over 2000 characters
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
do $$ begin
  update public.application_health_info set medical_conditions_details = repeat('x', 2001) where id = '9e040000-0000-4000-8000-000a00000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a null health flag
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
do $$ begin
  update public.application_health_info set has_allergies_or_dietary_requirements = null where id = '9e040000-0000-4000-8000-000a00000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a second health row for one application
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
do $$ begin
  insert into public.application_health_info (application_id) values ('9e040000-0000-4000-8000-000400000001');
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a health row for an unknown application
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
do $$ begin
  insert into public.application_health_info (application_id) values (gen_random_uuid());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: an unknown document type
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'report_card', 'pending/9e040000-0000-4000-8000-000400000002/a.pdf', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: an unknown status
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/a.pdf', 'lost', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a duplicate storage_path
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000001/doc1.pdf', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a path with ..
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/../9e040000-0000-4000-8000-000400000002/a.pdf', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a path with a leading slash
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', '/pending/9e040000-0000-4000-8000-000400000002/a.pdf', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a path ending in a slash
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/a.pdf/', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a path over 500 characters
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', repeat('a', 497) || '.pdf', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a blank path
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', '', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a .heic file
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/a.heic', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: an .exe file
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/a.exe', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a path with a space
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/a b.pdf', 'pending_review', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: approved with no file
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', null, 'approved', null);
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a path with no upload time
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', 'pending/9e040000-0000-4000-8000-000400000002/a.pdf', 'pending_review', null);
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: an upload time with no path
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
do $$ begin
  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at) values ('9e040000-0000-4000-8000-000400000002', 'other', null, 'required', now());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: a document for an unknown application
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
do $$ begin
  insert into public.application_documents (application_id, document_type) values (gen_random_uuid(), 'other');
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation or unique_violation then null;
end $$;
-- as role:
select 1;

-- ================================================================ delete behaviour

-- probe: C3 deleting an application removes its health row
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
delete from public.application_documents where application_id = '9e040000-0000-4000-8000-000400000001';
delete from public.applications where id = '9e040000-0000-4000-8000-000400000001';
do $$ begin
  if exists (select 1 from public.application_health_info where id = '9e040000-0000-4000-8000-000a00000001') then raise exception 'health row left behind'; end if;
end $$;
-- as role:
select 1;

-- probe: C4 an application with a document can't be deleted (D-4f)
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
do $$ begin
  delete from public.applications where id = '9e040000-0000-4000-8000-000400000001';
  raise exception 'application with a document was deleted';
exception when foreign_key_violation then null; end $$;
-- as role:
select 1;

-- probe: C5 the FKs are declared: documents restrict, health cascade
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select confdeltype from pg_constraint where conrelid = 'public.application_documents'::regclass and contype = 'f') <> 'r'
     or (select confdeltype from pg_constraint where conrelid = 'public.application_health_info'::regclass and contype = 'f') <> 'c' then
    raise exception 'on delete behaviour wrong';
  end if;
end $$;
