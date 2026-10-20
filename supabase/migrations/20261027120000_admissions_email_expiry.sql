-- Admissions slice 12, migration 3: a maximum age for queued emails
-- (decided by Eyram 2026-10-20, before checkpoint C3 closed).
--
-- A pending email older than 48 hours when the worker claims it is marked
-- expired and never sent. Age counts from created_at, or from a Manager's
-- retry (requeued_at) when there is one, so a deliberate retry of an old
-- failed email still sends. A lapsed lease counts as waiting. This stops a
-- backlog going out all at once when MAIL_MODE is switched to live after
-- hosted tests, and stops late emails after a long outage. Expired is
-- final: Retry only takes failed rows.
--
-- Changes: the status check gains 'expired'; claim_admissions_emails
-- expires old rows before it claims (under the same advisory lock);
-- list_admissions_emails accepts the new status; get_admissions_email_health
-- gains an expired count (return type changes, so it is dropped first);
-- the housekeeping purge keeps expired rows 180 days, like failed ones.
-- Nothing else changes and no grant widens.

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_status_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_status_check
  check (status in ('pending', 'sending', 'sent', 'failed', 'suppressed', 'expired'));

-- The maximum age of a queued email.
create or replace function public._admissions_email_max_age()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '48 hours';
$$;

create or replace function public.claim_admissions_emails(p_limit integer, p_daily_ceiling integer)
returns table (
  id uuid,
  kind text,
  recipient_email text,
  params jsonb,
  claim_token uuid,
  attempts integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used integer;
  v_room integer;
begin
  perform public._require_public_service_caller();
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'p_limit must be between 1 and 50';
  end if;
  if p_daily_ceiling is null or p_daily_ceiling < 1 then
    raise exception 'p_daily_ceiling must be at least 1';
  end if;

  -- One claimer at a time keeps the ceiling exact.
  perform pg_advisory_xact_lock(hashtextextended('admissions_email_claim', 0));

  -- Too old to send: a row waiting longer than the maximum age (counted
  -- from a Manager's retry when there is one) is expired, never sent. A
  -- lapsed lease counts as waiting.
  update public.admissions_email_outbox o
  set status = 'expired', claim_token = null, claimed_at = null
  where (o.status = 'pending'
         or (o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes'))
    and coalesce(o.requeued_at, o.created_at) < clock_timestamp() - public._admissions_email_max_age();

  update public.admissions_email_outbox o
  set status = 'failed', claim_token = null, claimed_at = null, last_error_class = 'timeout'
  where o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes'
    and o.attempts >= 6;

  select count(*) into v_used from public.admissions_email_outbox o
  where (o.status = 'sent' and o.sent_at > clock_timestamp() - interval '24 hours')
     or (o.status = 'sending' and o.claimed_at >= clock_timestamp() - interval '5 minutes');
  v_room := greatest(0, least(p_limit, p_daily_ceiling - v_used));

  update public.admissions_email_worker w
  set last_run_at = clock_timestamp(),
      ceiling_reached_at = case
        when v_room = 0 and exists (
          select 1 from public.admissions_email_outbox o
          where o.status = 'pending' and o.next_attempt_at <= clock_timestamp())
        then clock_timestamp() else null end
  where w.id;

  if v_room = 0 then
    return;
  end if;

  return query
  with c as (
    select o.id from public.admissions_email_outbox o
    where (o.status = 'pending' and o.next_attempt_at <= clock_timestamp())
       or (o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes')
    order by o.next_attempt_at, o.created_at
    limit v_room
    for update skip locked
  )
  update public.admissions_email_outbox o
  set status = 'sending', claim_token = gen_random_uuid(), claimed_at = clock_timestamp(),
      attempts = o.attempts + 1
  from c where o.id = c.id
  returning o.id, o.kind, o.recipient_email, o.params, o.claim_token, o.attempts;
end;
$$;

create or replace function public.list_admissions_emails(p_status text default null, p_limit integer default 200)
returns table (
  id uuid,
  kind text,
  recipient_masked text,
  "references" text[],
  application_ids uuid[],
  status text,
  attempts integer,
  last_error_class text,
  last_http_status integer,
  created_at timestamptz,
  next_attempt_at timestamptz,
  sent_at timestamptz,
  requeued_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_role(array['Manager', 'Auditor']) then
    raise exception 'Only a Manager or Auditor can see the email log';
  end if;
  if p_status is not null and p_status not in ('pending', 'sending', 'sent', 'failed', 'suppressed', 'expired') then
    raise exception 'Unknown status: %', p_status;
  end if;
  return query
  select o.id, o.kind, public._admissions_mask_email(o.recipient_email),
         array(select r ->> 'reference' from jsonb_array_elements(o.params -> 'references') r),
         o.application_ids, o.status, o.attempts, o.last_error_class, o.last_http_status,
         o.created_at, o.next_attempt_at, o.sent_at, o.requeued_at
  from public.admissions_email_outbox o
  where p_status is null or o.status = p_status
  order by o.created_at desc, o.id
  limit greatest(1, least(coalesce(p_limit, 200), 500));
end;
$$;

drop function public.get_admissions_email_health();

create or replace function public.get_admissions_email_health()
returns table (
  waiting integer,
  failed integer,
  suppressed integer,
  expired integer,
  last_run_at timestamptz,
  last_success_at timestamptz,
  ceiling_reached_at timestamptz,
  config_error boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_role(array['Manager', 'Auditor']) then
    raise exception 'Only a Manager or Auditor can see the email log';
  end if;
  return query
  select
    (select count(*)::integer from public.admissions_email_outbox o where o.status in ('pending', 'sending')),
    (select count(*)::integer from public.admissions_email_outbox o where o.status = 'failed'),
    (select count(*)::integer from public.admissions_email_outbox o where o.status = 'suppressed'),
    (select count(*)::integer from public.admissions_email_outbox o where o.status = 'expired'),
    w.last_run_at, w.last_success_at, w.ceiling_reached_at,
    exists (select 1 from public.admissions_email_outbox o
            where o.status in ('pending', 'failed') and o.last_error_class = 'config')
  from public.admissions_email_worker w where w.id;
end;
$$;

create or replace function public.purge_admissions_housekeeping()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reservations integer;
  v_sessions integer;
  v_emails integer;
  v_runs integer;
begin
  perform public._require_public_service_caller();

  delete from public.application_upload_reservations r
  using public.application_upload_sessions s
  where r.session_id = s.id
    and s.expires_at < clock_timestamp() - interval '30 days'
    and (r.consumed_at is not null or r.cleaned_at is not null);
  get diagnostics v_reservations = row_count;

  delete from public.application_upload_sessions s
  where s.expires_at < clock_timestamp() - interval '30 days'
    and not exists (select 1 from public.application_upload_reservations r where r.session_id = s.id);
  get diagnostics v_sessions = row_count;

  delete from public.admissions_email_outbox o
  where (o.status = 'sent' and o.created_at < clock_timestamp() - interval '90 days')
     or (o.status in ('failed', 'suppressed', 'expired') and o.created_at < clock_timestamp() - interval '180 days');
  get diagnostics v_emails = row_count;

  delete from cron.job_run_details d where d.end_time < clock_timestamp() - interval '7 days';
  get diagnostics v_runs = row_count;

  return jsonb_build_object(
    'reservations', v_reservations, 'sessions', v_sessions,
    'emails', v_emails, 'cron_runs', v_runs
  );
end;
$$;

revoke execute on function public._admissions_email_max_age() from public, anon, authenticated, service_role;
revoke execute on function public.get_admissions_email_health() from public, anon;
grant execute on function public.get_admissions_email_health() to authenticated;
