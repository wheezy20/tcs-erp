-- Admissions slice 5: reference numbering, stage transitions, notes and
-- document review (docs/admissions/PORT-PLAN.md, slice 5; decisions D-5a to
-- D-5l approved 2026-10-11, with D-5h changed to audit document status).
--
-- The first slice that lets staff change admissions data. Everything here is
-- a SECURITY DEFINER RPC or a trigger; no table grant or read policy changes,
-- so applications, notes and documents stay select-only for authenticated.
--
-- Numbering (D-5a, D-5e, D-5l):
--   INQ-YYYY-NNNN on insert, only for a row that starts at inquiry.
--   APP-YYYY-NNNN the first time the stage is anything past inquiry.
--   Never reassigned. YYYY is the year in Africa/Accra (UTC+0) at the
--   moment of assignment, so counters reset each year. Four digits minimum,
--   widening past 9999 (INQ-2026-10000), never truncated: plain lpad()
--   would truncate 10000 to 1000.
--   Assigned by a trigger, so every write path is numbered, including the
--   public intake in slices 8 and 9, which runs as service_role.
--   Counters start empty: nothing is imported from TCS OS.
--   A number comes from one atomic upsert that holds the counter row's lock
--   until commit, so concurrent callers get consecutive numbers, and a
--   rolled-back transaction gives its number back (no gap). A number already
--   held by a hand-entered row is skipped, so such a row can't wedge intake.
--   Student IDs (YYPPNNNN) are assigned in slice 6 with the same counter
--   (key STUDENT-YY-PP) and formatter (D-5f).
--
-- Stages (D-5b to D-5d): nothing ever leaves enrolled, for any caller,
-- enforced by trigger. Correcting a genuine mistake means disabling
-- applications_guard_update by hand as postgres. offer and enrolled are
-- reached only through slice 6.
--
-- Audit (D-5h, D-5i): stage changes write application_stage_changed and
-- document status changes write application_document_status_changed, both
-- by trigger and only when a signed-in staff member made the change (no
-- actor, no row, as for the other audit triggers). Neither row carries
-- names, file paths or health data.
--
-- Who may write: an active Manager, or an active Admissions Officer with the
-- application in scope. Auditor is read-only, Attendant and Accountant have
-- no admissions access. can_decide and can_view_health play no part here.
-- Out of scope and not found give the same error, so an officer can't probe
-- for applications outside their bands. No anon surface.

-- ------------------------------------------------------------ audit actions

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action = any (array[
  'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
  'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
  'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
  'admissions_capabilities_changed',
  'staff_advance_proposed', 'staff_advance_approved', 'staff_advance_rejected',
  'staff_advance_change_proposed', 'staff_advance_change_approved',
  'staff_advance_change_rejected',
  'employees_imported',
  'application_stage_changed', 'application_document_status_changed'
]));

-- ------------------------------------------------------------ counters

-- next_value is the next number to hand out. No privilege for any API role,
-- service_role included, and no policy: only the definer functions below
-- move a counter (D-5j). revoke all also removes TRUNCATE, which RLS
-- doesn't cover (the deposit_number_counters lesson).
create table public.admissions_reference_counters (
  key text primary key check (
    key ~ '^(INQ|APP)-[0-9]{4}$' or key ~ '^STUDENT-[0-9]{2}-0[1-9]$'
  ),
  next_value integer not null default 1 check (next_value >= 1)
);

alter table public.admissions_reference_counters enable row level security;
revoke all on table public.admissions_reference_counters from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ numbering helpers

-- The year a number belongs to, pinned to Africa/Accra so a session's
-- TimeZone setting can't shift it (D-5l).
create or replace function public._admissions_reference_year(p_at timestamptz default now())
returns integer
language sql
stable
set search_path = ''
as $$
  select extract(year from p_at at time zone 'Africa/Accra')::integer;
$$;

-- Four digits minimum, never truncated past 9999.
create or replace function public._admissions_sequence_text(p_seq integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_seq < 10000 then lpad(p_seq::text, 4, '0') else p_seq::text end;
$$;

-- Takes the next number for a counter key in one atomic upsert. The row
-- lock it takes is held until commit, so concurrent callers queue and get
-- consecutive numbers; a new key's first insert races safely on the
-- primary key.
create or replace function public._next_admissions_sequence(p_key text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
begin
  if p_key is null or not (p_key ~ '^(INQ|APP)-[0-9]{4}$' or p_key ~ '^STUDENT-[0-9]{2}-0[1-9]$') then
    raise exception 'Unknown admissions counter key: %', p_key;
  end if;
  insert into public.admissions_reference_counters as c (key, next_value)
  values (p_key, 2)
  on conflict (key) do update set next_value = c.next_value + 1
  returning c.next_value - 1 into v_seq;
  return v_seq;
end;
$$;

-- The next unused INQ-YYYY-NNNN or APP-YYYY-NNNN. Skips a number a
-- hand-entered row already holds instead of failing on the unique column.
create or replace function public._next_admissions_reference(p_prefix text, p_year integer)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
begin
  if p_prefix is null or p_prefix not in ('INQ', 'APP') then
    raise exception 'Unknown admissions reference prefix: %', p_prefix;
  end if;
  loop
    v_ref := p_prefix || '-' || p_year::text || '-'
      || public._admissions_sequence_text(public._next_admissions_sequence(p_prefix || '-' || p_year::text));
    if p_prefix = 'INQ' then
      exit when not exists (select 1 from public.applications where inquiry_reference = v_ref);
    else
      exit when not exists (select 1 from public.applications where application_reference = v_ref);
    end if;
  end loop;
  return v_ref;
end;
$$;

-- ------------------------------------------------------------ applications triggers

-- BEFORE triggers fire in name order: assign, guard, set_updated_at.

create or replace function public.assign_application_references()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.stage = 'inquiry' and new.inquiry_reference is null then
    new.inquiry_reference := public._next_admissions_reference('INQ', public._admissions_reference_year());
  end if;
  if new.stage in ('application', 'document_review', 'offer', 'enrolled',
                   'waitlisted', 'rejected', 'offer_declined')
     and new.application_reference is null then
    new.application_reference := public._next_admissions_reference('APP', public._admissions_reference_year());
  end if;
  return new;
end;
$$;

create trigger applications_assign_references
  before insert or update on public.applications
  for each row execute function public.assign_application_references();

-- Nothing leaves enrolled, for any caller (D-5d). A signed-in caller can't
-- change or clear a reference once assigned; postgres and service_role can,
-- for hand corrections.
create or replace function public.guard_application_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.stage = 'enrolled' and new.stage is distinct from 'enrolled' then
    raise exception 'An enrolled application can''t change stage';
  end if;
  if auth.uid() is not null
     and ((old.inquiry_reference is not null and new.inquiry_reference is distinct from old.inquiry_reference)
       or (old.application_reference is not null and new.application_reference is distinct from old.application_reference)) then
    raise exception 'An application''s reference can''t be changed once assigned';
  end if;
  return new;
end;
$$;

create trigger applications_guard_update
  before update on public.applications
  for each row execute function public.guard_application_update();

create trigger applications_set_updated_at
  before update on public.applications
  for each row execute function public.set_updated_at();

-- application_stage_changed, only for a signed-in actor.
create or replace function public.audit_application_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
begin
  if v_actor is null or old.stage is not distinct from new.stage then
    return null;
  end if;
  v_branch := coalesce(new.branch_id, (select branch_id from public.staff where id = v_actor));
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'application_stage_changed', 'applications', new.id::text,
    jsonb_build_object('stage', old.stage),
    jsonb_build_object('stage', new.stage, 'application_reference', new.application_reference)
  );
  return null;
end;
$$;

create trigger applications_audit_stage
  after update of stage on public.applications
  for each row execute function public.audit_application_stage();

-- ------------------------------------------------------------ documents audit

-- application_document_status_changed (D-5h), only for a signed-in actor.
-- Carries the application reference, document type and the old and new
-- status; never the file path.
create or replace function public.audit_application_document_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
  v_reference text;
begin
  if v_actor is null or old.status is not distinct from new.status then
    return null;
  end if;
  select a.application_reference, coalesce(a.branch_id, (select branch_id from public.staff where id = v_actor))
    into v_reference, v_branch
  from public.applications a where a.id = new.application_id;
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'application_document_status_changed', 'application_documents', new.id::text,
    jsonb_build_object('status', old.status),
    jsonb_build_object('status', new.status, 'document_type', new.document_type,
                       'application_reference', v_reference)
  );
  return null;
end;
$$;

create trigger application_documents_audit_status
  after update of status on public.application_documents
  for each row execute function public.audit_application_document_status();

-- ------------------------------------------------------------ notes column

-- Set when a note is edited, so an edit doesn't silently erase that the
-- note changed (D-5g).
alter table public.application_notes add column edited_at timestamptz;

-- ------------------------------------------------------------ writer guard

-- Active Manager or Admissions Officer. Same messages as the other role
-- guards (DESIGN.md).
create or replace function public._require_admissions_writer()
returns public.staff
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
begin
  v_staff := public.require_staff();
  if v_staff.role = 'Auditor' then
    raise exception 'Auditor is read-only and cannot perform this action';
  end if;
  if v_staff.role not in ('Manager', 'Admissions Officer') then
    raise exception 'This action is not available to your role';
  end if;
  return v_staff;
end;
$$;

-- ------------------------------------------------------------ RPCs

-- Manager, or an Admissions Officer with the application in scope. Only from
-- inquiry or application, re-checked under the row lock.
create or replace function public.move_application_to_document_review(p_application_id uuid)
returns public.applications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
begin
  perform public._require_admissions_writer();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage not in ('inquiry', 'application') then
    raise exception 'Cannot move to Document Review: currently at ''%'', not Inquiry or Application.', v_app.stage;
  end if;
  update public.applications set stage = 'document_review' where id = p_application_id
  returning * into v_app;
  return v_app;
end;
$$;

-- Manager only. Targets application, document_review, waitlisted and
-- rejected; never out of offer or enrolled (D-5b, D-5c).
create or replace function public.set_application_stage(p_application_id uuid, p_stage text)
returns public.applications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_app public.applications;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change an application''s stage directly';
  end if;
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  if p_stage is null or p_stage not in ('inquiry', 'application', 'document_review', 'offer',
                                        'enrolled', 'waitlisted', 'rejected', 'offer_declined') then
    raise exception 'Unknown stage: %', p_stage;
  end if;
  if p_stage in ('offer', 'enrolled', 'offer_declined') then
    raise exception 'An application reaches % only through the offer and enrolment steps', p_stage;
  end if;
  if p_stage = 'inquiry' then
    raise exception 'An application can''t be moved back to Inquiry';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.stage in ('offer', 'enrolled') then
    raise exception 'An application at % can''t be moved here', v_app.stage;
  end if;
  if v_app.stage = p_stage then
    raise exception 'The application is already at %', p_stage;
  end if;
  update public.applications set stage = p_stage where id = p_application_id
  returning * into v_app;
  return v_app;
end;
$$;

-- Manager, or an in-scope Admissions Officer. Author and time are set by the
-- note identity trigger (3a). No delete RPC exists (D-5g).
create or replace function public.add_application_note(p_application_id uuid, p_content text)
returns public.application_notes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_content text := btrim(coalesce(p_content, ''));
  v_note public.application_notes;
begin
  perform public._require_admissions_writer();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  if v_content = '' then
    raise exception 'A note can''t be blank';
  end if;
  if char_length(v_content) > 10000 then
    raise exception 'A note can be at most 10,000 characters';
  end if;
  insert into public.application_notes (application_id, content)
  values (p_application_id, v_content)
  returning * into v_note;
  return v_note;
end;
$$;

-- The note's author only, while still an active writer with the application
-- in scope. Changes the content and edited_at, nothing else.
create or replace function public.update_application_note(p_note_id uuid, p_content text)
returns public.application_notes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_content text := btrim(coalesce(p_content, ''));
  v_note public.application_notes;
begin
  perform public._require_admissions_writer();
  if v_content = '' then
    raise exception 'A note can''t be blank';
  end if;
  if char_length(v_content) > 10000 then
    raise exception 'A note can be at most 10,000 characters';
  end if;
  select * into v_note from public.application_notes where id = p_note_id for update;
  if not found or not public.admissions_application_visible(v_note.application_id) then
    raise exception 'Note not found';
  end if;
  if v_note.author_id is distinct from auth.uid() then
    raise exception 'Only the note''s author can edit it';
  end if;
  update public.application_notes set content = v_content, edited_at = now() where id = p_note_id
  returning * into v_note;
  return v_note;
end;
$$;

-- Manager, or an in-scope Admissions Officer. Moves between pending_review,
-- approved and rejected; never to required, and never on a document with no
-- file. Audited by trigger (D-5h).
create or replace function public.set_application_document_status(p_document_id uuid, p_status text)
returns public.application_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.application_documents;
begin
  perform public._require_admissions_writer();
  if p_status is null or p_status not in ('pending_review', 'approved', 'rejected') then
    raise exception 'A document''s status can only be set to pending review, approved or rejected';
  end if;
  select * into v_doc from public.application_documents where id = p_document_id for update;
  if not found or not public.admissions_application_visible(v_doc.application_id) then
    raise exception 'Document not found';
  end if;
  if v_doc.status = 'required' then
    raise exception 'No file has been uploaded for this document';
  end if;
  if v_doc.status = p_status then
    raise exception 'The document is already %', p_status;
  end if;
  update public.application_documents set status = p_status where id = p_document_id
  returning * into v_doc;
  return v_doc;
end;
$$;

-- ------------------------------------------------------------ grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. Helpers and trigger functions
-- get no grant at all; the five RPCs are for signed-in staff.
revoke execute on function public._admissions_reference_year(timestamptz) from public, anon, authenticated;
revoke execute on function public._admissions_sequence_text(integer) from public, anon, authenticated;
revoke execute on function public._next_admissions_sequence(text) from public, anon, authenticated;
revoke execute on function public._next_admissions_reference(text, integer) from public, anon, authenticated;
revoke execute on function public.assign_application_references() from public, anon, authenticated;
revoke execute on function public.guard_application_update() from public, anon, authenticated;
revoke execute on function public.audit_application_stage() from public, anon, authenticated;
revoke execute on function public.audit_application_document_status() from public, anon, authenticated;
revoke execute on function public._require_admissions_writer() from public, anon, authenticated;

revoke execute on function public.move_application_to_document_review(uuid) from public, anon;
revoke execute on function public.set_application_stage(uuid, text) from public, anon;
revoke execute on function public.add_application_note(uuid, text) from public, anon;
revoke execute on function public.update_application_note(uuid, text) from public, anon;
revoke execute on function public.set_application_document_status(uuid, text) from public, anon;
grant execute on function public.move_application_to_document_review(uuid) to authenticated, service_role;
grant execute on function public.set_application_stage(uuid, text) to authenticated, service_role;
grant execute on function public.add_application_note(uuid, text) to authenticated, service_role;
grant execute on function public.update_application_note(uuid, text) to authenticated, service_role;
grant execute on function public.set_application_document_status(uuid, text) to authenticated, service_role;
