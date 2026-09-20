-- HR expansion, Phase 2 of 5: document storage for onboarding uploads
-- (national ID, certificates, photo, etc.) — see docs/CONSTRAINTS.md's
-- "HR expansion beyond payroll" section for the full phase plan.
--
-- Applies the receipts-bucket lesson (20260918110000) from day one instead
-- of retrofitting it: a private bucket + RLS-gated `createSignedUrls()`,
-- never `public = true` + `getPublicUrl()`. These documents (ID numbers,
-- certificates, photos) are materially more sensitive than a receipt, so
-- there's no "start public, fix later" phase here at all.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'onboarding-documents',
  'onboarding-documents',
  false,
  10485760, -- 10 MiB — certificates/IDs scanned as PDF run larger than a receipt photo.
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do nothing;

-- Same command-scoped policy shape as receipts_select/insert/update/delete:
-- Manager/Accountant/Auditor read, Manager/Accountant write.
create policy "onboarding_documents_select" on storage.objects
for select
to authenticated
using (bucket_id = 'onboarding-documents' and public.has_role(array['Manager', 'Accountant', 'Auditor']));

create policy "onboarding_documents_insert" on storage.objects
for insert
to authenticated
with check (bucket_id = 'onboarding-documents' and public.has_role(array['Manager', 'Accountant']));

create policy "onboarding_documents_update" on storage.objects
for update
to authenticated
using (bucket_id = 'onboarding-documents' and public.has_role(array['Manager', 'Accountant']))
with check (bucket_id = 'onboarding-documents' and public.has_role(array['Manager', 'Accountant']));

create policy "onboarding_documents_delete" on storage.objects
for delete
to authenticated
using (bucket_id = 'onboarding-documents' and public.has_role(array['Manager', 'Accountant']));

-- NOT built yet, on purpose: an `anon` INSERT policy scoped to a valid,
-- unexpired, unused token embedded in the object path (planned shape:
-- onboarding/{token}/{filename}), so a candidate filling out Phase 3's
-- public onboarding form can upload straight to this bucket without an
-- ERP login. That policy's `with check` would need to look up the token
-- in a table that doesn't exist yet (`onboarding_tokens`, arriving in
-- Phase 3) — referencing it now wouldn't create a silently-inert policy,
-- it would fail this migration outright (undefined table). So this is
-- held, not stubbed: no anon access to this bucket exists until Phase 3
-- adds both the token table and this policy together, in the same
-- migration, so the policy is never live without its dependency.

-- employee_documents: one row per uploaded file. Deliberately flat, no
-- versioning/state machine here — that belongs to Phase 4's contract
-- lifecycle (Draft/Issued/Superseded), a genuinely different shape and a
-- separate table. This table is for the onboarding personal documents
-- named in the original scope: ID, certificates, photo.
create table public.employee_documents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete restrict,
  document_type text not null check (document_type in ('National ID', 'Certificate', 'Photo', 'Other')),
  storage_path text not null,
  uploaded_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  notes text
);

create index employee_documents_employee_id_idx on public.employee_documents (employee_id);

-- Same server-forced-identity shape as set_recorded_by() / set_issued_by():
-- one function per distinct column name, so a client can never claim an
-- upload was someone else's.
create or replace function public.set_employee_document_uploaded_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.uploaded_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger employee_documents_set_uploaded_by
before insert on public.employee_documents
for each row execute function public.set_employee_document_uploaded_by();

alter table public.employee_documents enable row level security;

-- Exactly the employee_allowances shape: not approval-gated, same
-- Manager/Accountant/Auditor read, Manager/Accountant write split as
-- everywhere else in this module.
create policy employee_documents_select on public.employee_documents
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy employee_documents_insert on public.employee_documents
for insert with check (public.has_role(array['Manager', 'Accountant']));
create policy employee_documents_update on public.employee_documents
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));
create policy employee_documents_delete on public.employee_documents
for delete using (public.has_role(array['Manager', 'Accountant']));

grant select, insert, update, delete on public.employee_documents to authenticated;
grant select, insert, update, delete on public.employee_documents to service_role;
