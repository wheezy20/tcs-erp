-- HR expansion, Phase 4 of 5: document generation (Appointment Letter,
-- Probation Letter, Contract). See docs/CONSTRAINTS.md's "HR expansion
-- beyond payroll" section for the phase plan and docs/DESIGN.md for the
-- design rationale.
--
-- Generalized from the originally-planned single-purpose "employee
-- contracts" table into `employee_generated_documents`, since all three
-- document kinds share identical lifecycle mechanics (Draft -> Issued ->
-- Superseded, old versions archived not deleted) and an identical
-- generation mechanism (an HTML template with merge-field placeholders,
-- rendered client-side via jsPDF's doc.html(), uploaded to a private
-- bucket). Named distinctly from `employee_documents` (20260920, for
-- candidate-uploaded scans) — these are system-generated official
-- records, a different kind of thing.
--
-- No recruitment-stage trigger exists in this system and none is added
-- here — all three are generated on demand from the employee profile
-- whenever HR judges it's the right moment, never tied to an automatic
-- status transition.

-- =====================================================================
-- 1. positions.is_teaching — the one new fact needed to make "Teaching
--    vs Non-Teaching auto-detected from position" real. Nothing on
--    `positions` distinguished job function before this.
-- =====================================================================
alter table public.positions add column is_teaching boolean not null default false;

-- One-time backfill for whatever positions already exist: anything with
-- "TEACH" in the name is obviously a teaching role (Head Teacher, Class
-- Teacher, Subject Teacher, Teaching Assistant, ...) — a safe default so
-- existing staff don't all silently classify as Non-Teaching until HR
-- manually reviews all sixteen-odd rows. HR can override any individual
-- one afterward via the same Positions list on Payroll Setup.
update public.positions set is_teaching = true where name ilike '%teach%';

-- =====================================================================
-- 2. contract_templates: one editable HTML body per document kind.
--    Seeded with real starter prose (standard Ghanaian school HR letter
--    language) using {{field_name}} merge-field placeholders, so HR
--    edits/refines an existing letter rather than starting from a blank
--    textarea. Editing a template never touches an already-Issued
--    document — that's a frozen, already-rendered PDF in storage by
--    then; only future generations pick up a template change.
-- =====================================================================
create table public.contract_templates (
  id uuid primary key default gen_random_uuid(),
  category text not null unique check (category in (
    'Appointment Letter', 'Probation Letter', 'Contract-Teaching', 'Contract-Non-Teaching'
  )),
  html_body text not null default '',
  updated_by uuid references public.staff (id) on delete set null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.contract_templates enable row level security;

create policy contract_templates_select on public.contract_templates
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy contract_templates_update on public.contract_templates
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));

grant select, update on public.contract_templates to authenticated;
grant select, insert, update, delete on public.contract_templates to service_role;
-- No insert/delete grant to authenticated at all: the four categories
-- are fixed (the check constraint enumerates them) and seeded below —
-- there's nothing to add or remove, only edit.

create or replace function public.set_contract_template_updated()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then new.updated_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger contract_templates_set_updated
before update on public.contract_templates
for each row execute function public.set_contract_template_updated();

insert into public.contract_templates (category, html_body) values
('Appointment Letter', $tpl$<div style="font-family: Arial, sans-serif; font-size: 12pt; line-height: 1.6;">
<p>{{company_name}}<br/>{{company_address}}<br/>{{company_phone}} &middot; {{company_email}}</p>
<p style="text-align:right;">{{issue_date}}</p>
<p>Dear {{employee_name}},</p>
<h3 style="text-align:center; text-decoration: underline;">LETTER OF APPOINTMENT</h3>
<p>We are pleased to confirm your appointment to the position of <strong>{{position}}</strong> in the {{department}} department of {{company_name}}, on a {{employment_type}} basis, with effect from <strong>{{start_date}}</strong>.</p>
<p>Your appointment is subject to a probationary period ending on <strong>{{probation_end_date}}</strong>, during which either party may terminate the appointment by giving the notice required under the applicable labour laws of Ghana.</p>
<p>Your basic salary will be <strong>GH&#8373; {{basic_salary}}</strong> per month, payable by {{payment_method}}, subject to the standard statutory deductions (SSNIT, Income Tax) and any other deductions required by law.</p>
<p>You will be required to observe the rules, regulations, and code of conduct of {{company_name}} as may be communicated to you from time to time.</p>
<p>Please sign and return the duplicate of this letter as a token of your acceptance of the above terms.</p>
<p>We welcome you to the {{company_name}} family and look forward to a mutually rewarding relationship.</p>
<p>Yours faithfully,</p>
<p>_____________________<br/>For: {{company_name}}</p>
</div>$tpl$),

('Probation Letter', $tpl$<div style="font-family: Arial, sans-serif; font-size: 12pt; line-height: 1.6;">
<p>{{company_name}}<br/>{{company_address}}</p>
<p style="text-align:right;">{{issue_date}}</p>
<p>Dear {{employee_name}},</p>
<h3 style="text-align:center; text-decoration: underline;">CONFIRMATION OF PROBATIONARY TERMS</h3>
<p>Further to your appointment as <strong>{{position}}</strong> in the {{department}} department with effect from <strong>{{start_date}}</strong>, this letter confirms that you remain on probation until <strong>{{probation_end_date}}</strong> ({{probation_duration_months}} months from your date of employment).</p>
<p>During this period, your performance and conduct will be reviewed to determine your suitability for confirmation in the role. Your current basic salary of <strong>GH&#8373; {{basic_salary}}</strong> per month remains unchanged during this period.</p>
<p>Should your performance be found satisfactory, you will receive a separate letter confirming your permanent appointment on or shortly after {{probation_end_date}}.</p>
<p>Yours faithfully,</p>
<p>_____________________<br/>For: {{company_name}}</p>
</div>$tpl$),

('Contract-Teaching', $tpl$<div style="font-family: Arial, sans-serif; font-size: 12pt; line-height: 1.6;">
<h2 style="text-align:center;">CONTRACT OF EMPLOYMENT &mdash; TEACHING STAFF</h2>
<p>{{company_name}}<br/>{{company_address}}</p>
<p>This Contract of Employment is made on {{issue_date}} between {{company_name}} ("the Employer") and {{employee_name}} ("the Employee").</p>
<ol>
<li><strong>Position:</strong> {{position}}, {{department}} department.</li>
<li><strong>Nature of employment:</strong> {{employment_type}}.</li>
<li><strong>Duration:</strong> Commencing {{start_date}}. Contract end date: {{contract_end_date}}.</li>
<li><strong>Probation:</strong> A probationary period applies until {{probation_end_date}}.</li>
<li><strong>Remuneration:</strong> A basic salary of GH&#8373; {{basic_salary}} per month, paid by {{payment_method}}, subject to statutory deductions.</li>
<li><strong>Qualifications on file:</strong> {{qualifications}}.</li>
<li><strong>Duties:</strong> The Employee shall perform the duties of a teacher as assigned by the school administration, in accordance with the Ghana Education Service curriculum and the school's academic calendar.</li>
<li><strong>Termination:</strong> This contract may be terminated by either party in accordance with the Labour Act, 2003 (Act 651) of Ghana.</li>
</ol>
<p>By signing below, the Employee acknowledges having read, understood, and accepted the terms of this Contract.</p>
<p>_____________________ (Employer) &nbsp;&nbsp;&nbsp; _____________________ (Employee)</p>
</div>$tpl$),

('Contract-Non-Teaching', $tpl$<div style="font-family: Arial, sans-serif; font-size: 12pt; line-height: 1.6;">
<h2 style="text-align:center;">CONTRACT OF EMPLOYMENT &mdash; NON-TEACHING STAFF</h2>
<p>{{company_name}}<br/>{{company_address}}</p>
<p>This Contract of Employment is made on {{issue_date}} between {{company_name}} ("the Employer") and {{employee_name}} ("the Employee").</p>
<ol>
<li><strong>Position:</strong> {{position}}, {{department}} department.</li>
<li><strong>Nature of employment:</strong> {{employment_type}}.</li>
<li><strong>Duration:</strong> Commencing {{start_date}}. Contract end date: {{contract_end_date}}.</li>
<li><strong>Probation:</strong> A probationary period applies until {{probation_end_date}}.</li>
<li><strong>Remuneration:</strong> A basic salary of GH&#8373; {{basic_salary}} per month, paid by {{payment_method}}, subject to statutory deductions.</li>
<li><strong>Qualifications on file:</strong> {{qualifications}}.</li>
<li><strong>Duties:</strong> The Employee shall perform the duties of {{position}} as assigned by the school administration.</li>
<li><strong>Termination:</strong> This contract may be terminated by either party in accordance with the Labour Act, 2003 (Act 651) of Ghana.</li>
</ol>
<p>By signing below, the Employee acknowledges having read, understood, and accepted the terms of this Contract.</p>
<p>_____________________ (Employer) &nbsp;&nbsp;&nbsp; _____________________ (Employee)</p>
</div>$tpl$)
on conflict (category) do nothing;

-- =====================================================================
-- 3. employee-generated-documents storage bucket: private from
--    creation, same policy shape as onboarding-documents (20260920) —
--    Manager/Accountant/Auditor read, Manager/Accountant write. PDF
--    only (this bucket never holds candidate-uploaded scans).
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('employee-generated-documents', 'employee-generated-documents', false, 5242880, array['application/pdf'])
on conflict (id) do nothing;

create policy "employee_generated_documents_select" on storage.objects
for select
to authenticated
using (bucket_id = 'employee-generated-documents' and public.has_role(array['Manager', 'Accountant', 'Auditor']));

create policy "employee_generated_documents_insert" on storage.objects
for insert
to authenticated
with check (bucket_id = 'employee-generated-documents' and public.has_role(array['Manager', 'Accountant']));

create policy "employee_generated_documents_update" on storage.objects
for update
to authenticated
using (bucket_id = 'employee-generated-documents' and public.has_role(array['Manager', 'Accountant']))
with check (bucket_id = 'employee-generated-documents' and public.has_role(array['Manager', 'Accountant']));

create policy "employee_generated_documents_delete" on storage.objects
for delete
to authenticated
using (bucket_id = 'employee-generated-documents' and public.has_role(array['Manager', 'Accountant']));

-- =====================================================================
-- 4. employee_generated_documents: the generalized lifecycle table.
--    RPC-only writes (no direct RLS write policy at all), same "no
--    hand-editable legal record" shape as employees/employee_pay_config.
-- =====================================================================
create table public.employee_generated_documents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete restrict,
  document_kind text not null check (document_kind in (
    'Appointment Letter', 'Probation Letter', 'Contract-Teaching', 'Contract-Non-Teaching'
  )),
  version integer not null check (version > 0),
  status text not null default 'Draft' check (status in ('Draft', 'Issued', 'Superseded')),
  storage_path text not null,
  -- Snapshot of every field value actually merged into this version's
  -- PDF — the historical record of what it said, independent of
  -- whatever the employee's live data or the template says today.
  merge_data jsonb not null,
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now(),
  issued_by uuid references public.staff (id) on delete set null,
  issued_at timestamptz,
  superseded_at timestamptz,
  -- Typed-name e-signature acceptance, recorded by HR after receiving a
  -- signature by any means (paper, verbal, email) — not a self-service
  -- signing flow. "Where relevant" in practice means Contracts; nothing
  -- stops recording it on the other kinds too, but no UI encourages it.
  acceptance_signature_name text,
  accepted_at timestamptz,
  unique (employee_id, document_kind, version)
);
create index employee_generated_documents_employee_id_idx
  on public.employee_generated_documents (employee_id);

-- At most one currently-Issued document per employee per kind — old
-- ones must be Superseded before a new one can be promoted, enforced
-- here, not just in the issuing RPC's own logic.
create unique index employee_generated_documents_one_issued_idx
  on public.employee_generated_documents (employee_id, document_kind)
  where status = 'Issued';

alter table public.employee_generated_documents enable row level security;

create policy employee_generated_documents_select on public.employee_generated_documents
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

grant select on public.employee_generated_documents to authenticated;
grant select, insert, update, delete on public.employee_generated_documents to service_role;

-- =====================================================================
-- 5. RPCs.
-- =====================================================================

-- p_document_kind is the caller's 3-way intent — 'Appointment Letter',
-- 'Probation Letter', or 'Contract'. For 'Contract', this function
-- resolves Teaching vs Non-Teaching itself from the employee's current
-- position, server-side — never trusted from the client, so a stale
-- frontend cache of the positions list can't misfile a contract.
create or replace function public.generate_employee_document(
  p_employee_id uuid,
  p_document_kind text,
  p_storage_path text,
  p_merge_data jsonb
)
returns public.employee_generated_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resolved_kind text;
  v_is_teaching boolean;
  v_next_version integer;
  v_doc public.employee_generated_documents;
begin
  perform public.require_finance_writer();

  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'Employee not found.';
  end if;

  if p_document_kind = 'Contract' then
    select p.is_teaching into v_is_teaching
    from public.employees e
    join public.positions p on p.name = e.position
    where e.id = p_employee_id;

    v_resolved_kind := case when coalesce(v_is_teaching, false)
      then 'Contract-Teaching' else 'Contract-Non-Teaching' end;
  elsif p_document_kind in ('Appointment Letter', 'Probation Letter') then
    v_resolved_kind := p_document_kind;
  else
    raise exception 'Unknown document kind: %', p_document_kind;
  end if;

  select coalesce(max(version), 0) + 1 into v_next_version
  from public.employee_generated_documents
  where employee_id = p_employee_id and document_kind = v_resolved_kind;

  insert into public.employee_generated_documents (
    employee_id, document_kind, version, storage_path, merge_data
  ) values (
    p_employee_id, v_resolved_kind, v_next_version, p_storage_path, p_merge_data
  ) returning * into v_doc;

  return v_doc;
end;
$$;

create or replace function public.issue_employee_document(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_kind text;
  v_status text;
begin
  perform public.require_finance_writer();

  select employee_id, document_kind, status into v_employee_id, v_kind, v_status
  from public.employee_generated_documents where id = p_document_id;

  if v_employee_id is null then
    raise exception 'Document not found.';
  end if;
  if v_status <> 'Draft' then
    raise exception 'Only a Draft can be issued.';
  end if;

  -- Demote the current Issued one (if any) first — the partial unique
  -- index forbids two Issued rows for the same employee+kind at once,
  -- so this must happen before the promotion below, not after.
  update public.employee_generated_documents
  set status = 'Superseded', superseded_at = now()
  where employee_id = v_employee_id and document_kind = v_kind and status = 'Issued';

  update public.employee_generated_documents
  set status = 'Issued', issued_at = now(), issued_by = auth.uid()
  where id = p_document_id;
end;
$$;

create or replace function public.discard_draft_document(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_finance_writer();

  delete from public.employee_generated_documents
  where id = p_document_id and status = 'Draft';

  if not found then
    raise exception 'Only a Draft can be discarded — an Issued or Superseded document is a permanent record.';
  end if;
end;
$$;

create or replace function public.record_document_acceptance(
  p_document_id uuid, p_signature_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(p_signature_name), '');
begin
  perform public.require_finance_writer();

  if v_name is null then
    raise exception 'A signature name is required.';
  end if;

  update public.employee_generated_documents
  set acceptance_signature_name = v_name, accepted_at = now()
  where id = p_document_id;

  if not found then
    raise exception 'Document not found.';
  end if;
end;
$$;

grant execute on function public.generate_employee_document(uuid, text, text, jsonb)
  to authenticated, service_role;
grant execute on function public.issue_employee_document(uuid) to authenticated, service_role;
grant execute on function public.discard_draft_document(uuid) to authenticated, service_role;
grant execute on function public.record_document_acceptance(uuid, text) to authenticated, service_role;
