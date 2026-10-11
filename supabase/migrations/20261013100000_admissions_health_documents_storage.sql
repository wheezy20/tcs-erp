-- Admissions slice 4: application health answers, document metadata and the
-- private admissions-documents bucket (docs/admissions/PORT-PLAN.md, slice 4;
-- decisions D-4a, D-4c to D-4m and the new reads approved 2026-10-11).
--
-- application_health_info and application_documents port TCS OS's
-- HealthInfo and Document (models.py:546-617). Both are select-only for
-- staff, like 3a and 3b: no insert/update/delete grant or policy, and no
-- write RPC in this slice (slice 5 reviews documents, slice 9 creates rows
-- and uploads files). There is no document read function: the table's own
-- select policy already returns metadata only.
--
-- Who reads what:
--   health rows: Manager, Auditor and Admissions Officer, only while they
--     hold can_view_health AND the application is visible to them
--     (D-4a: the capability intersected with band scope, so Manager and
--     Auditor need the capability too). can_decide plays no part.
--   document rows: Manager, Auditor, and an Admissions Officer in scope;
--     no health capability needed (D-4j).
--   files in admissions-documents: readable (so signable) only when a
--     visible application_documents row has exactly that storage_path. A
--     file with no row is readable by nobody. No role can insert, update or
--     delete files through a policy; uploads come later through the
--     Storage API with service_role or a signed upload URL (slice 9).
-- Attendant, Accountant and anon read nothing, even holding can_view_health.
--
-- Health reads are not audited in Phase 2 (D-4c). Auditing them would mean
-- reading health only through a SECURITY DEFINER RPC instead of this
-- select policy, so the last good moment to revisit that is before slice 7a
-- builds on the table.
--
-- No new function, no trigger, no anon surface.

-- ------------------------------------------------------------ health answers

-- One row per application, only once health questions are answered (D-4m).
create table public.application_health_info (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.applications (id) on delete cascade,
  has_learning_or_physical_needs boolean not null default false,
  -- 2,000 characters each (D-4e); the slice 9 form must use the same limit.
  learning_or_physical_needs_details text not null default ''
    check (char_length(learning_or_physical_needs_details) <= 2000),
  has_medical_conditions boolean not null default false,
  medical_conditions_details text not null default ''
    check (char_length(medical_conditions_details) <= 2000),
  has_allergies_or_dietary_requirements boolean not null default false,
  allergies_dietary_details text not null default ''
    check (char_length(allergies_dietary_details) <= 2000)
);

-- ------------------------------------------------------------ documents

create table public.application_documents (
  id uuid primary key default gen_random_uuid(),
  -- Restrict, not cascade (D-4f): deleting an application must not drop the
  -- only record of which files in the bucket belong to it.
  application_id uuid not null references public.applications (id) on delete restrict,
  -- TCS OS's eight types (models.py:547-556).
  document_type text not null check (document_type in (
    'proof_of_vaccination', 'financial_clearance', 'previous_report', 'application_fee_proof',
    'proof_of_funds', 'passport_photo', 'birth_certificate', 'other'
  )),
  -- The object's name in admissions-documents. Unique, because the file
  -- policy finds the row by exact path: a shared path would let a row on a
  -- visible application expose another application's file. Slice 9 mints
  -- the real path shape; this is a loose floor.
  storage_path text unique check (
    char_length(storage_path) <= 500
    and storage_path ~ '^[A-Za-z0-9._/-]+$'
    and storage_path !~ '\.\.'
    and storage_path !~ '^/'
    and storage_path !~ '/$'
    and lower(storage_path) ~ '\.(pdf|jpg|jpeg|png)$'
  ),
  status text not null default 'required'
    check (status in ('required', 'pending_review', 'approved', 'rejected')),
  uploaded_at timestamptz,
  -- A file and its upload time come together, and anything past "required"
  -- has a file.
  constraint application_documents_upload_pair_check
    check ((storage_path is null) = (uploaded_at is null)),
  constraint application_documents_file_for_status_check
    check (status = 'required' or storage_path is not null)
);

create index application_documents_application_id_idx on public.application_documents (application_id);

-- ------------------------------------------------------------ RLS

alter table public.application_health_info enable row level security;
alter table public.application_documents enable row level security;

-- Select only. The role list is explicit so a later change to
-- has_admissions_capability() can't widen these reads to another role.
create policy application_health_info_select on public.application_health_info
  for select using (
    public.has_role(array['Manager', 'Auditor', 'Admissions Officer'])
    and public.has_admissions_capability('health')
    and public.admissions_application_visible(application_id)
  );

create policy application_documents_select on public.application_documents
  for select using (
    public.has_role(array['Manager', 'Auditor', 'Admissions Officer'])
    and public.admissions_application_visible(application_id)
  );

-- ------------------------------------------------------------ grants

revoke all on table public.application_health_info from anon, authenticated;
revoke all on table public.application_documents from anon, authenticated;

grant select on table public.application_health_info to authenticated;
grant select on table public.application_documents to authenticated;

grant select, insert, update, delete on table public.application_health_info to service_role;
grant select, insert, update, delete on table public.application_documents to service_role;

-- ------------------------------------------------------------ bucket

-- Private from the first insert (the receipts lesson, 20260918110000).
-- do update, not do nothing: if the bucket ever exists already (say,
-- created by hand in the dashboard as public), this puts it back to
-- private with the right limits. 10 MiB; PDF, JPEG and PNG only, no HEIC
-- (D-4g, TCS OS storage.py:30).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'admissions-documents',
  'admissions-documents',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Read only, and only through a visible document row with exactly this
-- path. The subquery runs under the caller's own RLS on
-- application_documents, so the file rule can't drift from the row rule.
-- No insert, update or delete policy for this bucket.
create policy "admissions_documents_select" on storage.objects
for select
to authenticated
using (
  bucket_id = 'admissions-documents'
  and exists (
    select 1 from public.application_documents d
    where d.storage_path = objects.name
  )
);
