-- Admissions slice 6a: decisions and capacity (docs/admissions/PORT-PLAN.md,
-- slice 6, split into 6a and 6b; decisions D-6a to D-6p approved 2026-10-12,
-- with D-6j changed to a withdrawn offer response).
--
-- Like slice 5, everything is a SECURITY DEFINER RPC or a trigger. No table
-- grant or read policy changes: decisions, offers and capacity stay
-- select-only for authenticated.
--
-- Decisions (D-6f, D-6j, D-6k):
--   record_decision creates the single decision and refuses when one exists;
--   change_decision changes it and refuses when none exists. Never an upsert.
--   Both need the decide capability, held explicitly by a Manager too
--   (D-2f), and an Admissions Officer needs the application in scope.
--   Neither works at inquiry or enrolled.
--   waitlisted and rejected move the stage to match (TCS OS Decision.save,
--   models.py:418-445); accepted never moves the stage.
--   A decision leaving accepted withdraws a pending offer (response
--   withdrawn), and is refused once the parent has accepted the offer.
--   Offers are created only in 6b, so in 6a that branch only meets offers
--   made by hand.
--
-- Capacity (D-3c, D-6c, D-6o): a warning, never a block. It's returned by
--   both decision RPCs when the resulting decision is accepted and the
--   accepted count for the application's year, grade and campus is strictly
--   greater than the capacity row's figure. Applications at offer_declined,
--   and those whose offer is declined, withdrawn or past its expiry, don't
--   count. A Manager's warning gives the figures; an officer's gives none,
--   because officers can't read capacity. Campus rules aren't checked here
--   (3b decision (f): slice 9's submit RPC only).
--   Capacity rows are created, changed and deleted by Manager-only RPCs.
--
-- Audit (D-6n): application_decision_changed when the decision type is set
-- or changes (a notes-only edit writes no row), and admissions_capacity_changed
-- for every capacity insert, change and delete. Only for a signed-in actor.
-- No names, notes or health data; the decision row carries the application
-- reference.
--
-- No anon surface: every new function is revoked from public and anon.

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
  'application_stage_changed', 'application_document_status_changed',
  'application_decision_changed', 'admissions_capacity_changed'
]));

-- ------------------------------------------------------------ offer responses

-- withdrawn (D-6j): the decision left accepted while the offer was pending.
-- It counts like declined everywhere, and the offer link is dead.
alter table public.application_offers drop constraint application_offers_response_check;
alter table public.application_offers add constraint application_offers_response_check
  check (response in ('pending', 'accepted', 'declined', 'expired', 'withdrawn'));

-- ------------------------------------------------------------ helpers

-- An active Manager or Admissions Officer holding can_decide. Role first,
-- then the capability, so an Auditor gets the read-only message.
create or replace function public._require_admissions_decider()
returns public.staff
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
begin
  v_staff := public._require_admissions_writer();
  if not public.has_admissions_capability('decide') then
    raise exception 'You need the admissions decide permission to do this';
  end if;
  return v_staff;
end;
$$;

-- The admissions_grades row for a grade label, or null. Same normalisation
-- as admissions_grade_band() (case and extra whitespace ignored).
create or replace function public._admissions_grade_id(p_grade text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select g.id
  from public.admissions_grades g
  where lower(g.name) = regexp_replace(regexp_replace(lower(p_grade), '^\s+|\s+$', '', 'g'), '\s+', ' ', 'g');
$$;

-- The response as it stands right now: a pending offer past its expiry is
-- expired, whether or not anything has written that yet (computed, never
-- stored). Strictly after expires_at, as TCS OS (models.py:474-482).
-- clock_timestamp(), not now(): now() is frozen at the transaction's start
-- and goes stale after a lock wait.
create or replace function public._offer_effective_response(p_response text, p_expires_at timestamptz)
returns text
language sql
volatile
set search_path = ''
as $$
  select case
    when p_response = 'pending' and p_expires_at is not null and clock_timestamp() > p_expires_at
      then 'expired'
    else p_response
  end;
$$;

-- The capacity warning for an application, or null. No capacity row for its
-- exact year text, grade and campus (a null campus matches only a
-- null-campus row) means no warning, as does a grade that resolves to no
-- admissions grade. Warns only when the count is strictly greater than the
-- capacity. p_reveal_figures: a Manager sees the numbers, an officer doesn't.
create or replace function public._admissions_capacity_warning(p_application_id uuid, p_reveal_figures boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_grade public.admissions_grades;
  v_capacity integer;
  v_count integer;
  v_label text;
begin
  select * into v_app from public.applications where id = p_application_id;
  if not found then return null; end if;
  select * into v_grade from public.admissions_grades where id = public._admissions_grade_id(v_app.year_group_applied_for);
  if not found then return null; end if;
  select c.capacity into v_capacity
  from public.admissions_capacity c
  where c.academic_year = v_app.academic_year
    and c.grade_id = v_grade.id
    and c.branch_id is not distinct from v_app.branch_id;
  if not found then return null; end if;

  select count(*) into v_count
  from public.applications a
  join public.application_decisions d on d.application_id = a.id and d.decision_type = 'accepted'
  left join public.application_offers o on o.application_id = a.id
  where a.academic_year = v_app.academic_year
    and a.branch_id is not distinct from v_app.branch_id
    and public._admissions_grade_id(a.year_group_applied_for) = v_grade.id
    and a.stage <> 'offer_declined'
    and (o.id is null
         or public._offer_effective_response(o.response, o.expires_at) not in ('declined', 'expired', 'withdrawn'));

  if v_count <= v_capacity then
    return null;
  end if;
  v_label := v_grade.name || ' (' || v_app.academic_year
    || coalesce(', ' || (select b.name from public.branches b where b.id = v_app.branch_id), '') || ')';
  if p_reveal_figures then
    return format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.',
                  v_label, v_count, v_capacity);
  end if;
  return format('Capacity warning: %s is now over its planned capacity. Ask a Manager.', v_label);
end;
$$;

-- ------------------------------------------------------------ decision RPCs

-- Creates the decision. Refused when one exists (use change_decision).
-- Checks, in order: role, decide capability, scope, arguments, then under
-- the application row lock: scope again, stage, no existing decision.
create or replace function public.record_decision(p_application_id uuid, p_decision_type text, p_notes text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_app public.applications;
  v_notes text := btrim(coalesce(p_notes, ''));
begin
  v_staff := public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  if p_decision_type is null or p_decision_type not in ('accepted', 'waitlisted', 'rejected') then
    raise exception 'A decision must be accepted, waitlisted or rejected';
  end if;
  if char_length(v_notes) > 10000 then
    raise exception 'Decision notes can be at most 10,000 characters';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage in ('inquiry', 'enrolled') then
    raise exception 'A decision can''t be recorded while the application is at %', v_app.stage;
  end if;
  if exists (select 1 from public.application_decisions where application_id = p_application_id) then
    raise exception 'A decision has already been recorded for this application; change it instead';
  end if;

  insert into public.application_decisions (application_id, decision_type, notes)
  values (p_application_id, p_decision_type, v_notes);

  if p_decision_type in ('waitlisted', 'rejected') and v_app.stage <> p_decision_type then
    update public.applications set stage = p_decision_type where id = p_application_id
    returning * into v_app;
  end if;

  return jsonb_build_object(
    'decision_type', p_decision_type,
    'stage', v_app.stage,
    'capacity_warning', case when p_decision_type = 'accepted'
      then public._admissions_capacity_warning(p_application_id, v_staff.role = 'Manager') end
  );
end;
$$;

-- Changes the existing decision. Refused when there is none, when nothing
-- changes, and at inquiry or enrolled. Leaving accepted: a pending offer is
-- withdrawn; an offer the parent accepted blocks the change; a declined,
-- withdrawn or expired offer is left as it is (D-6j).
create or replace function public.change_decision(p_application_id uuid, p_decision_type text, p_notes text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
  v_notes text := btrim(coalesce(p_notes, ''));
  v_withdrawn boolean := false;
begin
  v_staff := public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  if p_decision_type is null or p_decision_type not in ('accepted', 'waitlisted', 'rejected') then
    raise exception 'A decision must be accepted, waitlisted or rejected';
  end if;
  if char_length(v_notes) > 10000 then
    raise exception 'Decision notes can be at most 10,000 characters';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage in ('inquiry', 'enrolled') then
    raise exception 'A decision can''t be changed while the application is at %', v_app.stage;
  end if;
  select * into v_decision from public.application_decisions
  where application_id = p_application_id for update;
  if not found then
    raise exception 'No decision has been recorded for this application yet';
  end if;
  if v_decision.decision_type = p_decision_type and v_decision.notes = v_notes then
    raise exception 'The decision is already % with these notes', p_decision_type;
  end if;

  if v_decision.decision_type = 'accepted' and p_decision_type <> 'accepted' then
    select * into v_offer from public.application_offers
    where application_id = p_application_id for update;
    if found then
      if v_offer.response = 'accepted' then
        raise exception 'The parent has accepted the offer, so the decision can''t be changed';
      end if;
      if public._offer_effective_response(v_offer.response, v_offer.expires_at) = 'pending' then
        update public.application_offers set response = 'withdrawn' where id = v_offer.id;
        v_withdrawn := true;
      end if;
    end if;
  end if;

  update public.application_decisions set decision_type = p_decision_type, notes = v_notes
  where id = v_decision.id;

  if p_decision_type in ('waitlisted', 'rejected') and v_app.stage <> p_decision_type then
    update public.applications set stage = p_decision_type where id = p_application_id
    returning * into v_app;
  end if;

  return jsonb_build_object(
    'decision_type', p_decision_type,
    'stage', v_app.stage,
    'offer_withdrawn', v_withdrawn,
    'capacity_warning', case when p_decision_type = 'accepted'
      then public._admissions_capacity_warning(p_application_id, v_staff.role = 'Manager') end
  );
end;
$$;

-- ------------------------------------------------------------ capacity RPCs

-- Manager only (no capability needed). The year is stored trimmed and
-- matched as exact text (D-6o).
create or replace function public.create_admissions_capacity(
  p_academic_year text, p_grade_id uuid, p_branch_id uuid, p_capacity integer
)
returns public.admissions_capacity
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_year text := btrim(coalesce(p_academic_year, ''));
  v_row public.admissions_capacity;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change admissions capacity';
  end if;
  if v_year = '' or char_length(v_year) > 50 then
    raise exception 'The academic year must be 1 to 50 characters';
  end if;
  if p_grade_id is null or not exists (select 1 from public.admissions_grades where id = p_grade_id) then
    raise exception 'Grade not found';
  end if;
  if p_branch_id is not null and not exists (select 1 from public.branches where id = p_branch_id) then
    raise exception 'Campus not found';
  end if;
  if p_capacity is null or p_capacity < 0 or p_capacity > 100000 then
    raise exception 'Capacity must be a whole number from 0 to 100,000';
  end if;
  begin
    insert into public.admissions_capacity (academic_year, grade_id, branch_id, capacity)
    values (v_year, p_grade_id, p_branch_id, p_capacity)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'A capacity for this year, grade and campus already exists';
  end;
  return v_row;
end;
$$;

-- Manager only. Only the figure changes; the year, grade and campus don't
-- (delete and create to change them).
create or replace function public.update_admissions_capacity(p_id uuid, p_capacity integer)
returns public.admissions_capacity
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_row public.admissions_capacity;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change admissions capacity';
  end if;
  if p_capacity is null or p_capacity < 0 or p_capacity > 100000 then
    raise exception 'Capacity must be a whole number from 0 to 100,000';
  end if;
  select * into v_row from public.admissions_capacity where id = p_id for update;
  if not found then
    raise exception 'Capacity not found';
  end if;
  if v_row.capacity = p_capacity then
    raise exception 'The capacity is already %', p_capacity;
  end if;
  update public.admissions_capacity set capacity = p_capacity where id = p_id
  returning * into v_row;
  return v_row;
end;
$$;

-- Manager only.
create or replace function public.delete_admissions_capacity(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change admissions capacity';
  end if;
  perform 1 from public.admissions_capacity where id = p_id for update;
  if not found then
    raise exception 'Capacity not found';
  end if;
  delete from public.admissions_capacity where id = p_id;
end;
$$;

-- ------------------------------------------------------------ audit triggers

-- application_decision_changed, only for a signed-in actor, and only when
-- the decision type is set or changes. No notes in the payload.
create or replace function public.audit_application_decision()
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
  if v_actor is null then return null; end if;
  if tg_op = 'UPDATE' and old.decision_type is not distinct from new.decision_type then
    return null;
  end if;
  select a.application_reference, coalesce(a.branch_id, (select branch_id from public.staff where id = v_actor))
    into v_reference, v_branch
  from public.applications a where a.id = new.application_id;
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'application_decision_changed', 'application_decisions', new.id::text,
    case when tg_op = 'UPDATE' then jsonb_build_object('decision_type', old.decision_type) end,
    jsonb_build_object('decision_type', new.decision_type, 'application_reference', v_reference)
  );
  return null;
end;
$$;

create trigger application_decisions_audit
  after insert or update of decision_type on public.application_decisions
  for each row execute function public.audit_application_decision();

-- admissions_capacity_changed, only for a signed-in actor: every insert,
-- every change of the figure, every delete. Grade and campus by name.
create or replace function public.audit_admissions_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_row public.admissions_capacity := case when tg_op = 'DELETE' then old else new end;
  v_branch uuid;
begin
  if v_actor is null then return null; end if;
  if tg_op = 'UPDATE' and old is not distinct from new then
    return null;
  end if;
  v_branch := coalesce(v_row.branch_id, (select branch_id from public.staff where id = v_actor));
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'admissions_capacity_changed', 'admissions_capacity', v_row.id::text,
    case when tg_op <> 'INSERT' then jsonb_build_object(
      'academic_year', old.academic_year,
      'grade', (select name from public.admissions_grades where id = old.grade_id),
      'campus', (select name from public.branches where id = old.branch_id),
      'capacity', old.capacity) end,
    case when tg_op <> 'DELETE' then jsonb_build_object(
      'academic_year', new.academic_year,
      'grade', (select name from public.admissions_grades where id = new.grade_id),
      'campus', (select name from public.branches where id = new.branch_id),
      'capacity', new.capacity) end
  );
  return null;
end;
$$;

create trigger admissions_capacity_audit
  after insert or update or delete on public.admissions_capacity
  for each row execute function public.audit_admissions_capacity();

-- ------------------------------------------------------------ grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. Helpers and trigger functions
-- get no grant at all; the five RPCs are for signed-in staff.
revoke execute on function public._require_admissions_decider() from public, anon, authenticated;
revoke execute on function public._admissions_grade_id(text) from public, anon, authenticated;
revoke execute on function public._offer_effective_response(text, timestamptz) from public, anon, authenticated;
revoke execute on function public._admissions_capacity_warning(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.audit_application_decision() from public, anon, authenticated;
revoke execute on function public.audit_admissions_capacity() from public, anon, authenticated;

revoke execute on function public.record_decision(uuid, text, text) from public, anon;
revoke execute on function public.change_decision(uuid, text, text) from public, anon;
revoke execute on function public.create_admissions_capacity(text, uuid, uuid, integer) from public, anon;
revoke execute on function public.update_admissions_capacity(uuid, integer) from public, anon;
revoke execute on function public.delete_admissions_capacity(uuid) from public, anon;
grant execute on function public.record_decision(uuid, text, text) to authenticated, service_role;
grant execute on function public.change_decision(uuid, text, text) to authenticated, service_role;
grant execute on function public.create_admissions_capacity(text, uuid, uuid, integer) to authenticated, service_role;
grant execute on function public.update_admissions_capacity(uuid, integer) to authenticated, service_role;
grant execute on function public.delete_admissions_capacity(uuid) to authenticated, service_role;
