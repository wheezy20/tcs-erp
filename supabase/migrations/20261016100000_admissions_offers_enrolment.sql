-- Admissions slice 6b: offers, the enrolment gate and student IDs
-- (docs/admissions/PORT-PLAN.md, slice 6; decisions D-6a to D-6p approved
-- 2026-10-12, with D-6j changed to a withdrawn offer response).
--
-- Like 6a, everything is a SECURITY DEFINER RPC or a trigger. Offers,
-- decisions and students stay select-only for authenticated. The one new
-- table, admissions_settings, is select-only too.
--
-- Offers (D-6a, D-6b, D-6e, D-6m):
--   generate_offer needs an accepted decision (the decision, not the stage)
--   and no offer row; it mints a 32-byte token, stores only its SHA-256
--   hash, and returns the raw token once. reset_offer always mints a new
--   token, so the old link finds nothing; it's refused once the parent has
--   accepted. record_offer_response records a reply the parent gave staff.
--   All three need the decide capability, and scope for an officer.
--
-- Expiry (D-6l): computed, never written by a read path. Every RPC here
--   reads the effective response (_offer_effective_response) and refuses an
--   expired offer. Only settle_expired_offers, service_role only, writes
--   expired and moves the stage from offer to offer_declined. It has no
--   actor, so no audit row. Slice 12 schedules it.
--
-- Enrolment (D-6d, D-6g, D-6h, D-6i): mark_enrolled is Manager only, no
--   capability. It needs stage offer, an accepted decision and an offer
--   whose effective response is accepted. A student without an ID gets
--   YYPPNNNN: YY the Africa/Accra calendar year at enrolment, PP the grade's
--   classification code, NNNN from the STUDENT-YY-PP counter (D-5f). An
--   unbanded or legacy grade is refused. A student who has an ID keeps it;
--   a second enrolment for one student in one academic year is refused.
--   The enrolment stage audit row carries the student ID.
--
-- Lock order, for every path that can accept an offer or enrol (and for
--   slice 11's respond_to_offer): the application, then the decision, then
--   the offer, then the student, then the counter. Everything is re-checked
--   under those locks: scope, stage, the decision still accepted, the offer
--   still pending and in date. change_decision (6a) takes the application,
--   the decision and the offer in the same order, so neither can leave a
--   changed decision with an accepted offer. The expiry sweep takes only
--   the application and the offer, in that order, which is safe because the
--   application lock comes first everywhere.
--
-- Audit (D-6n): application_offer_changed (never the token or its hash) and
--   admissions_settings_changed, signed-in actor only. The list goes from 33
--   to 35 values.
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
  'application_decision_changed', 'admissions_capacity_changed',
  'application_offer_changed', 'admissions_settings_changed'
]));

-- ------------------------------------------------------------ settings

-- One row (id 1). Slice 8 adds its own columns here.
create table public.admissions_settings (
  id integer primary key default 1 check (id = 1),
  offer_ttl_days integer not null default 14 check (offer_ttl_days between 1 and 90),
  updated_at timestamptz not null default now()
);

insert into public.admissions_settings (id) values (1);

create trigger admissions_settings_set_updated_at
  before update on public.admissions_settings
  for each row execute function public.set_updated_at();

alter table public.admissions_settings enable row level security;

create policy admissions_settings_select on public.admissions_settings
  for select using (public.has_role(array['Manager', 'Auditor']));

-- No insert or delete for anyone through the API: the row is the setting.
revoke all on table public.admissions_settings from public, anon, authenticated, service_role;
grant select on table public.admissions_settings to authenticated;
grant select, update on table public.admissions_settings to service_role;

-- ------------------------------------------------------------ helpers

-- The grade's classification code (01 to 04), or null for an unbanded or
-- free-text grade. Same normalisation as _admissions_grade_id().
create or replace function public._admissions_grade_code(p_grade text)
returns text
language sql
stable
set search_path = ''
as $$
  select g.classification_code
  from public.admissions_grades g
  where g.id = public._admissions_grade_id(p_grade);
$$;

-- The next unused YYPPNNNN for a classification code and a calendar year.
-- Takes the STUDENT-YY-PP counter's row lock until commit. Skips a number a
-- hand-entered student already holds.
create or replace function public._next_admissions_student_id(p_code text, p_year integer)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yy text;
  v_id text;
begin
  if p_code is null or p_code !~ '^0[1-9]$' then
    raise exception 'Unknown student ID classification: %', p_code;
  end if;
  if p_year is null or p_year < 2000 then
    raise exception 'Unknown student ID year: %', p_year;
  end if;
  v_yy := lpad((p_year % 100)::text, 2, '0');
  loop
    v_id := v_yy || p_code
      || public._admissions_sequence_text(public._next_admissions_sequence('STUDENT-' || v_yy || '-' || p_code));
    exit when not exists (select 1 from public.students where student_id = v_id);
  end loop;
  return v_id;
end;
$$;

-- Settles one offer that has run out: locks the application, then the
-- offer, and re-checks under the locks that it's still pending and past its
-- expiry. Writes expired and moves the stage from offer to offer_declined.
-- Returns whether it settled anything. Called only by settle_expired_offers.
create or replace function public._settle_offer_expiry(p_application_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_offer public.application_offers;
begin
  select * into v_app from public.applications where id = p_application_id for update;
  if not found then return false; end if;
  select * into v_offer from public.application_offers
  where application_id = p_application_id for update;
  if not found or v_offer.response <> 'pending'
     or public._offer_effective_response(v_offer.response, v_offer.expires_at) <> 'expired' then
    return false;
  end if;
  update public.application_offers set response = 'expired' where id = v_offer.id;
  if v_app.stage = 'offer' then
    update public.applications set stage = 'offer_declined' where id = p_application_id;
  end if;
  return true;
end;
$$;

-- ------------------------------------------------------------ offer status view

-- Offers without token_hash, with the response as it stands right now.
-- security_invoker, so the offers select policy decides who sees which row.
-- The expiry rule is written out here rather than calling
-- _offer_effective_response(), which has no grant for authenticated.
create view public.application_offer_status with (security_invoker = true) as
select
  o.id,
  o.application_id,
  o.sent_at,
  o.expires_at,
  o.response,
  o.responded_at,
  case
    when o.response = 'pending' and o.expires_at is not null and clock_timestamp() > o.expires_at
      then 'expired'
    else o.response
  end as effective_response
from public.application_offers o;

revoke all on table public.application_offer_status from public, anon, authenticated, service_role;
grant select on table public.application_offer_status to authenticated, service_role;

-- ------------------------------------------------------------ offer RPCs

-- Creates the offer. Checks, in order: role, decide capability, scope, then
-- under the application lock: scope again, stage, then the decision (locked)
-- is accepted, then no offer exists. Returns the raw token once.
create or replace function public.generate_offer(p_application_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_app public.applications;
  v_decision public.application_decisions;
  v_ttl integer;
  v_token text;
  v_sent timestamptz;
  v_offer public.application_offers;
begin
  perform public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage not in ('application', 'document_review', 'waitlisted', 'rejected') then
    raise exception 'An offer can''t be generated while the application is at %', v_app.stage;
  end if;
  select * into v_decision from public.application_decisions
  where application_id = p_application_id for update;
  if not found or v_decision.decision_type <> 'accepted' then
    raise exception 'An offer needs an accepted decision';
  end if;
  if exists (select 1 from public.application_offers where application_id = p_application_id) then
    raise exception 'An offer already exists for this application; reset it instead';
  end if;

  select offer_ttl_days into v_ttl from public.admissions_settings where id = 1;
  v_token := encode(gen_random_bytes(32), 'hex');
  v_sent := clock_timestamp();
  insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response)
  values (p_application_id, encode(digest(v_token, 'sha256'), 'hex'), v_sent,
          v_sent + make_interval(days => v_ttl), 'pending')
  returning * into v_offer;

  update public.applications set stage = 'offer' where id = p_application_id
  returning * into v_app;

  return jsonb_build_object(
    'token', v_token,
    'sent_at', v_offer.sent_at,
    'expires_at', v_offer.expires_at,
    'stage', v_app.stage
  );
end;
$$;

-- Replaces the offer's token (D-6b), so the old link finds nothing, and
-- starts a new pending offer with a fresh expiry. Allowed on a pending
-- (including expired), declined, expired or withdrawn offer; refused once
-- the parent has accepted (D-6m). Needs the decision still accepted. Moves
-- the stage back to offer. Returns the raw token once.
create or replace function public.reset_offer(p_application_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
  v_ttl integer;
  v_token text;
  v_sent timestamptz;
begin
  perform public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage in ('inquiry', 'enrolled') then
    raise exception 'An offer can''t be reset while the application is at %', v_app.stage;
  end if;
  select * into v_decision from public.application_decisions
  where application_id = p_application_id for update;
  if not found or v_decision.decision_type <> 'accepted' then
    raise exception 'An offer needs an accepted decision';
  end if;
  select * into v_offer from public.application_offers
  where application_id = p_application_id for update;
  if not found then
    raise exception 'No offer exists for this application; generate one instead';
  end if;
  if v_offer.response = 'accepted' then
    raise exception 'The parent has accepted the offer, so it can''t be reset';
  end if;

  select offer_ttl_days into v_ttl from public.admissions_settings where id = 1;
  v_token := encode(gen_random_bytes(32), 'hex');
  v_sent := clock_timestamp();
  update public.application_offers
  set token_hash = encode(digest(v_token, 'sha256'), 'hex'),
      sent_at = v_sent,
      expires_at = v_sent + make_interval(days => v_ttl),
      response = 'pending',
      responded_at = null
  where id = v_offer.id
  returning * into v_offer;

  if v_app.stage <> 'offer' then
    update public.applications set stage = 'offer' where id = p_application_id
    returning * into v_app;
  end if;

  return jsonb_build_object(
    'token', v_token,
    'sent_at', v_offer.sent_at,
    'expires_at', v_offer.expires_at,
    'stage', v_app.stage
  );
end;
$$;

-- A reply the parent gave staff (D-6e): accepted or declined. Under the
-- locks (application, decision, offer) it re-checks scope, the stage, that
-- the decision is still accepted, and that the offer is still pending and
-- in date. declined moves the stage to offer_declined.
create or replace function public.record_offer_response(p_application_id uuid, p_response text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
  v_effective text;
begin
  perform public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  if p_response is null or p_response not in ('accepted', 'declined') then
    raise exception 'An offer response must be accepted or declined';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage <> 'offer' then
    raise exception 'An offer response can''t be recorded while the application is at %', v_app.stage;
  end if;
  select * into v_decision from public.application_decisions
  where application_id = p_application_id for update;
  if not found or v_decision.decision_type <> 'accepted' then
    raise exception 'The decision is no longer accepted';
  end if;
  select * into v_offer from public.application_offers
  where application_id = p_application_id for update;
  if not found then
    raise exception 'No offer exists for this application';
  end if;
  v_effective := public._offer_effective_response(v_offer.response, v_offer.expires_at);
  if v_effective = 'expired' then
    raise exception 'The offer has expired; reset it to send a new one';
  end if;
  if v_effective <> 'pending' then
    raise exception 'The offer has already been %', v_effective;
  end if;

  update public.application_offers set response = p_response, responded_at = clock_timestamp()
  where id = v_offer.id;

  if p_response = 'declined' then
    update public.applications set stage = 'offer_declined' where id = p_application_id
    returning * into v_app;
  end if;

  return jsonb_build_object('response', p_response, 'stage', v_app.stage);
end;
$$;

-- ------------------------------------------------------------ enrolment

-- Manager only (D-6d). Under the locks (application, decision, offer,
-- student, then the counter inside _next_admissions_student_id) it re-checks
-- the stage, the accepted decision, the accepted offer, and that the student
-- isn't already enrolled in this academic year.
create or replace function public.mark_enrolled(p_application_id uuid)
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
  v_student public.students;
  v_code text;
  v_assigned boolean := false;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can mark an application enrolled';
  end if;
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found then
    raise exception 'Application not found';
  end if;
  if v_app.stage <> 'offer' then
    raise exception 'Only an application at offer can be enrolled; this one is at %', v_app.stage;
  end if;
  select * into v_decision from public.application_decisions
  where application_id = p_application_id for update;
  if not found or v_decision.decision_type <> 'accepted' then
    raise exception 'Enrolment needs an accepted decision';
  end if;
  select * into v_offer from public.application_offers
  where application_id = p_application_id for update;
  if not found or public._offer_effective_response(v_offer.response, v_offer.expires_at) <> 'accepted' then
    raise exception 'Enrolment needs an offer the parent has accepted';
  end if;
  v_code := public._admissions_grade_code(v_app.year_group_applied_for);
  if v_code is null then
    raise exception 'The grade applied for has no student ID classification; correct the grade before enrolling';
  end if;
  select * into v_student from public.students where id = v_app.student_id for update;
  if exists (select 1 from public.applications
             where student_id = v_app.student_id and academic_year = v_app.academic_year
               and stage = 'enrolled' and id <> p_application_id) then
    raise exception 'This student is already enrolled for %', v_app.academic_year;
  end if;

  if v_student.student_id is null then
    update public.students
    set student_id = public._next_admissions_student_id(v_code, public._admissions_reference_year(clock_timestamp()))
    where id = v_student.id
    returning * into v_student;
    v_assigned := true;
  end if;

  update public.applications set stage = 'enrolled' where id = p_application_id
  returning * into v_app;

  return jsonb_build_object(
    'stage', v_app.stage,
    'student_id', v_student.student_id,
    'student_id_assigned', v_assigned
  );
end;
$$;

-- ------------------------------------------------------------ settings RPC

-- Manager only (D-6a). Applies to offers generated or reset from now on.
create or replace function public.set_admissions_offer_ttl_days(p_days integer)
returns public.admissions_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_row public.admissions_settings;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change the offer expiry';
  end if;
  if p_days is null or p_days < 1 or p_days > 90 then
    raise exception 'The offer expiry must be a whole number of days from 1 to 90';
  end if;
  select * into v_row from public.admissions_settings where id = 1 for update;
  if v_row.offer_ttl_days = p_days then
    raise exception 'The offer expiry is already % days', p_days;
  end if;
  update public.admissions_settings set offer_ttl_days = p_days where id = 1
  returning * into v_row;
  return v_row;
end;
$$;

-- ------------------------------------------------------------ expiry sweep

-- service_role only (D-6l): no staff member can call it, and it refuses a
-- signed-in caller even if a grant is ever added by mistake. Settles every
-- pending offer past its expiry, one application at a time. Returns how
-- many it settled.
create or replace function public.settle_expired_offers()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_application_id uuid;
  v_count integer := 0;
begin
  if auth.uid() is not null then
    raise exception 'This action is not available to your role';
  end if;
  for v_application_id in
    select o.application_id from public.application_offers o
    where o.response = 'pending' and o.expires_at is not null and o.expires_at < clock_timestamp()
    order by o.expires_at
  loop
    if public._settle_offer_expiry(v_application_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- ------------------------------------------------------------ student ID guard

-- A signed-in caller can't change or clear a student ID once assigned
-- (mark_enrolled only fills an empty one). postgres and service_role can,
-- for hand corrections.
create or replace function public.guard_student_id()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and old.student_id is not null
     and new.student_id is distinct from old.student_id then
    raise exception 'A student ID can''t be changed once assigned';
  end if;
  return new;
end;
$$;

create trigger students_guard_student_id
  before update on public.students
  for each row execute function public.guard_student_id();

-- ------------------------------------------------------------ audit triggers

-- application_stage_changed (slice 5), now carrying the student ID when the
-- stage becomes enrolled (D-6i).
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
      || case when new.stage = 'enrolled'
           then jsonb_build_object('student_id', (select s.student_id from public.students s where s.id = new.student_id))
           else '{}'::jsonb end
  );
  return null;
end;
$$;

-- application_offer_changed, only for a signed-in actor: an offer created,
-- its response changed, or its token replaced. Never the token or its hash;
-- token_replaced says only that a reset happened.
create or replace function public.audit_application_offer()
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
  if tg_op = 'UPDATE' and old.response is not distinct from new.response
     and old.token_hash is not distinct from new.token_hash
     and old.expires_at is not distinct from new.expires_at then
    return null;
  end if;
  select a.application_reference, coalesce(a.branch_id, (select branch_id from public.staff where id = v_actor))
    into v_reference, v_branch
  from public.applications a where a.id = new.application_id;
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'application_offer_changed', 'application_offers', new.id::text,
    case when tg_op = 'UPDATE' then jsonb_build_object('response', old.response, 'expires_at', old.expires_at) end,
    jsonb_build_object(
      'response', new.response,
      'expires_at', new.expires_at,
      'token_replaced', tg_op = 'UPDATE' and old.token_hash is distinct from new.token_hash,
      'application_reference', v_reference)
  );
  return null;
end;
$$;

create trigger application_offers_audit
  after insert or update on public.application_offers
  for each row execute function public.audit_application_offer();

-- admissions_settings_changed, only for a signed-in actor, when the TTL
-- changes.
create or replace function public.audit_admissions_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
begin
  if v_actor is null or old.offer_ttl_days is not distinct from new.offer_ttl_days then
    return null;
  end if;
  v_branch := (select branch_id from public.staff where id = v_actor);
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'admissions_settings_changed', 'admissions_settings', new.id::text,
    jsonb_build_object('offer_ttl_days', old.offer_ttl_days),
    jsonb_build_object('offer_ttl_days', new.offer_ttl_days)
  );
  return null;
end;
$$;

create trigger admissions_settings_audit
  after update on public.admissions_settings
  for each row execute function public.audit_admissions_settings();

-- ------------------------------------------------------------ grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. Helpers and trigger functions
-- get no grant at all; the five staff RPCs are for signed-in staff; the
-- sweep is service_role only.
revoke execute on function public._admissions_grade_code(text) from public, anon, authenticated;
revoke execute on function public._next_admissions_student_id(text, integer) from public, anon, authenticated;
revoke execute on function public._settle_offer_expiry(uuid) from public, anon, authenticated;
revoke execute on function public.guard_student_id() from public, anon, authenticated;
revoke execute on function public.audit_application_offer() from public, anon, authenticated;
revoke execute on function public.audit_admissions_settings() from public, anon, authenticated;

revoke execute on function public.generate_offer(uuid) from public, anon;
revoke execute on function public.reset_offer(uuid) from public, anon;
revoke execute on function public.record_offer_response(uuid, text) from public, anon;
revoke execute on function public.mark_enrolled(uuid) from public, anon;
revoke execute on function public.set_admissions_offer_ttl_days(integer) from public, anon;
grant execute on function public.generate_offer(uuid) to authenticated, service_role;
grant execute on function public.reset_offer(uuid) to authenticated, service_role;
grant execute on function public.record_offer_response(uuid, text) to authenticated, service_role;
grant execute on function public.mark_enrolled(uuid) to authenticated, service_role;
grant execute on function public.set_admissions_offer_ttl_days(integer) to authenticated, service_role;

revoke execute on function public.settle_expired_offers() from public, anon, authenticated;
grant execute on function public.settle_expired_offers() to service_role;
