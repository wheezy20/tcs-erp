-- Admissions slice 12, migration 1 of 2: the transactional email outbox.
--
-- A public submission writes its outbox rows in the same transaction as
-- the record, so there is never an email without a record or a record
-- without its email. The admissions-worker Edge Function (service role,
-- secret-gated) claims due rows, sends them through Resend and records the
-- result. Migration 2 schedules it with pg_cron and pg_net.
--
-- What a row holds: the kind, the recipient (null for the staff alert,
-- whose address is a function secret the worker reads at send time), the
-- applications it is about, and a small params object with only the
-- references, the grade names and the academic years (and, for the staff
-- alert, whether a family matched). A check refuses anything else, so no
-- name, health answer or document name can be stored. The body is built
-- by the worker from fixed templates when it sends.
--
-- Who gets the parent email (decided 2026-10-16):
--   every guardian email typed into the form, then every guardian email
--   already on record for the family, de-duplicated, at most 4. For an
--   enquiry the family is always new, so the two sets are the same. For a
--   matched application the real parent on record always hears about it,
--   and a typed address that is not on record gets the same email, so the
--   emails sent never reveal whether a family exists.
--   At most 4 parent emails per address in 24 hours (email_recipient_day
--   in _public_rate_limit_rule). More are stored as suppressed and never
--   sent; the submission and its response are unchanged.
-- One staff alert per submission event.
--
-- Retries: a claim counts as an attempt. A failed attempt waits 1, 5, 15,
-- 60, then 240 minutes; the sixth failure marks the row failed. A 400 or
-- 422 from the provider fails the row at once. A claim is a 5 minute lease;
-- a lapsed lease is claimed again and the worker sends with the same
-- Idempotency-Key (the row id), which Resend honours for 24 hours.
--
-- Staff see status without parent data: no API role has any privilege on
-- these tables. Manager and Auditor read a list with masked recipients and
-- a health summary through definer functions; anyone who can see an
-- application sees its confirmation status (no address); only a Manager
-- can retry a failed row, recorded on the row (requeued_by, requeued_at).
-- Provider error text is never stored, only a class and the HTTP status.
--
-- The worker secret is made here, in Vault, and no person ever handles it.
-- The worker URL is set once by hand with set_admissions_worker_url().

-- ------------------------------------------------------------ the numbers

-- Unchanged apart from email_recipient_day, a cap (never stored as a hit):
-- at most 4 parent emails to one address in 24 hours.
create or replace function public._public_rate_limit_rule(
  p_bucket text,
  out max_count integer,
  out window_length interval
)
language sql
immutable
set search_path = ''
as $$
  select r.max_count, r.window_length
  from (values
    ('submit_ip', 20, interval '1 hour'),
    ('submit_global', 200, interval '1 hour'),
    ('inquiry_email', 5, interval '1 day'),
    ('application_email', 5, interval '1 day'),
    ('upload_ip', 10, interval '1 hour'),
    ('upload_global', 100, interval '1 hour'),
    ('upload_session_files', 8, interval '6 hours'),
    ('upload_open_reservations', 400, interval '30 minutes'),
    ('email_recipient_day', 4, interval '1 day')
  ) as r (bucket, max_count, window_length)
  where r.bucket = p_bucket;
$$;

-- The wait after a failed attempt, or null when no attempt is left.
create or replace function public._admissions_email_retry_delay(p_attempts integer)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case p_attempts
    when 1 then interval '1 minute'
    when 2 then interval '5 minutes'
    when 3 then interval '15 minutes'
    when 4 then interval '60 minutes'
    when 5 then interval '240 minutes'
  end;
$$;

-- ------------------------------------------------------------ params check

-- True only for the shapes the templates read. Parent emails carry only
-- references; the staff alert also carries family_matched and, for an
-- application, the match outcome.
create or replace function public._admissions_email_params_ok(p_kind text, p_params jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_refs jsonb;
  v_r jsonb;
  v_prefix text;
  v_allowed text[];
begin
  if p_params is null or jsonb_typeof(p_params) <> 'object' then
    return false;
  end if;
  if p_kind in ('inquiry_parent', 'application_parent', 'inquiry_staff') then
    v_allowed := array['references'];
  elsif p_kind = 'application_staff' then
    v_allowed := array['references', 'family_matched', 'outcome'];
  else
    return false;
  end if;
  if (p_params - v_allowed) <> '{}'::jsonb then
    return false;
  end if;

  v_prefix := case when p_kind like 'inquiry%' then 'INQ' else 'APP' end;
  v_refs := p_params -> 'references';
  if v_refs is null or jsonb_typeof(v_refs) <> 'array'
     or jsonb_array_length(v_refs) not between 1 and 20
     or (v_prefix = 'APP' and jsonb_array_length(v_refs) <> 1) then
    return false;
  end if;
  for v_r in select value from jsonb_array_elements(v_refs) loop
    if jsonb_typeof(v_r) <> 'object'
       or (v_r - array['reference', 'grade', 'academic_year']) <> '{}'::jsonb
       or jsonb_typeof(v_r -> 'reference') is distinct from 'string'
       or jsonb_typeof(v_r -> 'grade') is distinct from 'string'
       or jsonb_typeof(v_r -> 'academic_year') is distinct from 'string'
       or (v_r ->> 'reference') !~ ('^' || v_prefix || '-[0-9]{4}-[0-9]{4,}$')
       or char_length(v_r ->> 'grade') not between 1 and 100
       or char_length(v_r ->> 'academic_year') not between 1 and 20 then
      return false;
    end if;
  end loop;

  if p_kind = 'application_staff' then
    if jsonb_typeof(p_params -> 'family_matched') is distinct from 'boolean' then
      return false;
    end if;
    if p_params ? 'outcome' and (p_params ->> 'outcome') is distinct from null
       and (p_params ->> 'outcome') not in ('new_application', 'inquiry_advanced', 'possible_duplicate') then
      return false;
    end if;
  end if;
  return true;
end;
$$;

-- ------------------------------------------------------------ tables

create table public.admissions_email_outbox (
  id uuid primary key default gen_random_uuid(),
  -- 'inquiry:<family id>' or 'application:<application id>'; with kind and
  -- recipient it is unique, so the same event can never queue twice.
  event_key text not null check (event_key ~ '^(inquiry|application):[0-9a-f-]{36}$'),
  kind text not null check (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff')),
  recipient_email text check (
    recipient_email is null
    or (char_length(recipient_email) <= 254
        and recipient_email = lower(recipient_email)
        and recipient_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
  ),
  -- The applications this email is about, in form order. Not a foreign key
  -- (an array can't be one); a deleted application leaves a harmless id.
  application_ids uuid[] not null check (cardinality(application_ids) between 1 and 20),
  params jsonb not null,
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'failed', 'suppressed')),
  attempts integer not null default 0 check (attempts between 0 and 6),
  next_attempt_at timestamptz not null default now(),
  claim_token uuid,
  claimed_at timestamptz,
  last_error_class text check (last_error_class in (
    'network', 'timeout', 'rate_limited', 'provider_error', 'invalid_recipient', 'config', 'conflict', 'other'
  )),
  last_http_status integer check (last_http_status between 100 and 599),
  provider_message_id text check (char_length(provider_message_id) <= 200),
  requeued_by uuid references public.staff (id),
  requeued_at timestamptz,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  constraint admissions_email_outbox_params_check check (public._admissions_email_params_ok(kind, params)),
  constraint admissions_email_outbox_recipient_check check (
    (kind like '%_parent' and recipient_email is not null)
    or (kind like '%_staff' and recipient_email is null)
  ),
  constraint admissions_email_outbox_claim_check check (
    (status = 'sending') = (claim_token is not null and claimed_at is not null)
  ),
  constraint admissions_email_outbox_sent_check check ((status = 'sent') = (sent_at is not null)),
  constraint admissions_email_outbox_event_unique unique nulls not distinct (event_key, kind, recipient_email)
);

create index admissions_email_outbox_due_idx on public.admissions_email_outbox (next_attempt_at)
  where status in ('pending', 'sending');
create index admissions_email_outbox_recipient_idx on public.admissions_email_outbox (recipient_email, created_at)
  where recipient_email is not null;
create index admissions_email_outbox_application_idx on public.admissions_email_outbox using gin (application_ids);
create index admissions_email_outbox_created_idx on public.admissions_email_outbox (created_at);

alter table public.admissions_email_outbox enable row level security;
revoke all on table public.admissions_email_outbox from public, anon, authenticated, service_role;

-- One row: where the worker lives and what it last reported.
create table public.admissions_email_worker (
  id boolean primary key default true check (id),
  -- https only, so the secret header never travels in clear text; plain
  -- http is allowed only for the local Docker stack's own host names.
  worker_url text check (char_length(worker_url) <= 500 and (
    worker_url ~ '^https://[^[:space:]]+$'
    or worker_url ~ '^http://(kong|localhost|127\.0\.0\.1|host\.docker\.internal)(:[0-9]+)?/[^[:space:]]*$')),
  last_run_at timestamptz,
  last_success_at timestamptz,
  ceiling_reached_at timestamptz
);
insert into public.admissions_email_worker (id) values (true);

alter table public.admissions_email_worker enable row level security;
revoke all on table public.admissions_email_worker from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ worker secret

-- 32 random bytes as hex, made once per database. No file holds it.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'admissions_worker_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'admissions_worker_secret',
      'Shared by the pg_cron jobs and the admissions-worker Edge Function'
    );
  end if;
end;
$$;

-- Service role only: the worker reads the secret and compares it with the
-- request header in constant time. Null when the secret is missing.
create or replace function public.admissions_worker_secret()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  perform public._require_public_service_caller();
  select nullif(s.decrypted_secret, '') into v_secret
  from vault.decrypted_secrets s where s.name = 'admissions_worker_secret';
  return v_secret;
end;
$$;

-- Set once by hand (SQL editor or psql as postgres). No API role can call it.
create or replace function public.set_admissions_worker_url(p_url text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._require_public_service_caller();
  update public.admissions_email_worker set worker_url = nullif(btrim(p_url), '') where id;
end;
$$;

-- ------------------------------------------------------------ enqueue

-- Masks an address for staff screens: j•••@g•••.com.
create or replace function public._admissions_mask_email(p_email text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_email is null then null
    when position('@' in p_email) < 2 then '•••'
    else left(p_email, 1) || '•••@'
      || left(split_part(p_email, '@', 2), 1) || '•••'
      || coalesce('.' || nullif(substring(split_part(p_email, '@', 2) from '\.([^.]+)$'), ''), '')
  end;
$$;

-- Called only from submit_inquiry and submit_application, inside their
-- transaction, after every write. p_event is 'inquiry' (p_family_id names
-- the new family; every application in it is listed, in reference order,
-- which is form order) or 'application' (p_application_id). p_typed_emails
-- are the guardian emails as submitted, already lowercased.
create or replace function public._enqueue_admissions_emails(
  p_event text,
  p_family_id uuid,
  p_application_id uuid,
  p_typed_emails text[]
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_event_key text;
  v_app_ids uuid[];
  v_refs jsonb;
  v_staff_params jsonb;
  v_recipients text[];
  v_email text;
  v_cap integer;
  v_window interval;
  v_recent integer;
begin
  if p_event = 'inquiry' then
    v_event_key := 'inquiry:' || p_family_id;
    select array_agg(a.id order by char_length(a.inquiry_reference), a.inquiry_reference),
           jsonb_agg(jsonb_build_object(
             'reference', a.inquiry_reference,
             'grade', a.year_group_applied_for,
             'academic_year', a.academic_year) order by char_length(a.inquiry_reference), a.inquiry_reference)
      into v_app_ids, v_refs
    from public.applications a
    join public.students s on s.id = a.student_id
    where s.family_id = p_family_id and a.inquiry_reference is not null;
    v_staff_params := jsonb_build_object('references', v_refs);
  elsif p_event = 'application' then
    v_event_key := 'application:' || p_application_id;
    select array[a.id],
           jsonb_build_array(jsonb_build_object(
             'reference', a.application_reference,
             'grade', a.year_group_applied_for,
             'academic_year', a.academic_year))
      into v_app_ids, v_refs
    from public.applications a where a.id = p_application_id;
    select jsonb_build_object(
             'references', v_refs,
             'family_matched', coalesce(f.family_matched, false),
             'outcome', f.outcome)
      into v_staff_params
    from (select 1) one
    left join public.application_match_flags f on f.application_id = p_application_id;
  else
    raise exception 'Unknown admissions email event: %', p_event;
  end if;
  if v_app_ids is null then
    raise exception 'No application to email about';
  end if;

  -- Typed addresses first, then the family's guardians on record, at most
  -- 4. An address that would fail the table check is skipped, never
  -- allowed to abort the submission.
  select array_agg(e order by first_pos)
    into v_recipients
  from (
    select e, min(pos) as first_pos
    from (
      select lower(btrim(t.e)) as e, t.pos
      from unnest(coalesce(p_typed_emails, '{}')) with ordinality as t (e, pos)
      union all
      select g.email, 100 + row_number() over (order by g.id)
      from public.guardians g where g.family_id = p_family_id
    ) all_e
    where e ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' and char_length(e) <= 254
    group by e
    order by min(pos)
    limit 4
  ) picked;

  select r.max_count, r.window_length into v_cap, v_window
  from public._public_rate_limit_rule('email_recipient_day') r;

  -- Locks taken in address order, so two submissions sharing addresses
  -- can't deadlock and the cap count is exact.
  foreach v_email in array (select coalesce(array_agg(x order by x), '{}') from unnest(v_recipients) x) loop
    perform pg_advisory_xact_lock(hashtextextended('admissions_email:' || v_email, 0));
  end loop;

  foreach v_email in array coalesce(v_recipients, '{}') loop
    select count(*) into v_recent
    from public.admissions_email_outbox o
    where o.recipient_email = v_email
      and o.status <> 'suppressed'
      and o.created_at > clock_timestamp() - v_window;
    insert into public.admissions_email_outbox
      (event_key, kind, recipient_email, application_ids, params, status)
    values (
      v_event_key, p_event || '_parent', v_email, v_app_ids,
      jsonb_build_object('references', v_refs),
      case when v_recent >= v_cap then 'suppressed' else 'pending' end
    )
    on conflict on constraint admissions_email_outbox_event_unique do nothing;
  end loop;

  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params)
  values (v_event_key, p_event || '_staff', null, v_app_ids, v_staff_params)
  on conflict on constraint admissions_email_outbox_event_unique do nothing;
end;
$$;

-- ------------------------------------------------------------ worker RPCs

-- Service role only. Claims up to p_limit due rows: pending rows whose
-- time has come, and sending rows whose 5 minute lease has lapsed. A
-- lapsed lease on the last attempt is marked failed instead. The daily
-- ceiling (a function secret, passed in) counts rows sent or being sent in
-- the last 24 hours; rows over it stay pending and the worker row records
-- that the ceiling was reached.
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

-- Service role only. Records one send result, only while the caller still
-- holds the claim. p_outcome: 'sent', 'retry' (backs off, or fails on the
-- last attempt) or 'failed'. Returns whether the result was recorded.
create or replace function public.mark_admissions_email_result(
  p_id uuid,
  p_claim_token uuid,
  p_outcome text,
  p_error_class text,
  p_http_status integer,
  p_provider_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.admissions_email_outbox;
  v_delay interval;
begin
  perform public._require_public_service_caller();
  if p_outcome is null or p_outcome not in ('sent', 'retry', 'failed') then
    raise exception 'Unknown outcome: %', p_outcome;
  end if;
  if p_outcome <> 'sent' and p_error_class is null then
    raise exception 'A failed send needs an error class';
  end if;

  select * into v_row from public.admissions_email_outbox o
  where o.id = p_id and o.status = 'sending' and o.claim_token = p_claim_token
  for update;
  if not found or p_claim_token is null then
    return false;
  end if;

  if p_outcome = 'sent' then
    update public.admissions_email_outbox o
    set status = 'sent', sent_at = clock_timestamp(), claim_token = null, claimed_at = null,
        provider_message_id = left(p_provider_message_id, 200),
        last_error_class = null, last_http_status = p_http_status
    where o.id = p_id;
    update public.admissions_email_worker w set last_success_at = clock_timestamp() where w.id;
    return true;
  end if;

  v_delay := case when p_outcome = 'retry' then public._admissions_email_retry_delay(v_row.attempts) end;
  update public.admissions_email_outbox o
  set status = case when v_delay is null then 'failed' else 'pending' end,
      next_attempt_at = case when v_delay is null then o.next_attempt_at else clock_timestamp() + v_delay end,
      claim_token = null, claimed_at = null,
      last_error_class = p_error_class, last_http_status = p_http_status
  where o.id = p_id;
  return true;
end;
$$;

-- ------------------------------------------------------------ staff RPCs

-- Manager only. Puts failed rows back in the queue with a fresh attempt
-- count. Suppressed rows stay suppressed. Returns how many were requeued.
create or replace function public.requeue_admissions_emails(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can retry emails';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then
    return 0;
  end if;
  if cardinality(p_ids) > 100 then
    raise exception 'At most 100 emails at a time';
  end if;
  update public.admissions_email_outbox o
  set status = 'pending', attempts = 0, next_attempt_at = clock_timestamp(),
      last_error_class = null, last_http_status = null,
      requeued_by = auth.uid(), requeued_at = clock_timestamp()
  where o.id = any (p_ids) and o.status = 'failed';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Manager and Auditor. The outbox with masked recipients, newest first.
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
  if p_status is not null and p_status not in ('pending', 'sending', 'sent', 'failed', 'suppressed') then
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

-- Manager and Auditor. Counts and what the worker last reported.
create or replace function public.get_admissions_email_health()
returns table (
  waiting integer,
  failed integer,
  suppressed integer,
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
    w.last_run_at, w.last_success_at, w.ceiling_reached_at,
    exists (select 1 from public.admissions_email_outbox o
            where o.status in ('pending', 'failed') and o.last_error_class = 'config')
  from public.admissions_email_worker w where w.id;
end;
$$;

-- Anyone who can see the application: the parent confirmation status for
-- it, one row per status, with no address.
create or replace function public.get_application_email_status(p_application_id uuid)
returns table (
  status text,
  emails integer,
  last_sent_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_role(array['Manager', 'Auditor', 'Admissions Officer'])
     or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  return query
  select o.status, count(*)::integer, max(o.sent_at)
  from public.admissions_email_outbox o
  where o.application_ids @> array[p_application_id] and o.kind like '%_parent'
  group by o.status
  order by o.status;
end;
$$;

-- ------------------------------------------------------------ submit RPCs

-- submit_inquiry, re-created from 20261023100000 with one line added: the
-- outbox insert after every write, in the same transaction. Same signature
-- and grants (service_role only; create or replace keeps them).
create or replace function public.submit_inquiry(p_payload jsonb)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open boolean;
  v_referral text;
  v_referral_other text;
  v_comments text;
  v_guardians jsonb;
  v_students jsonb;
  v_g jsonb;
  v_s jsonb;
  v_label text;
  v_path text;
  v_i integer;
  v_phone text;
  v_email text;
  v_emails text[] := '{}';
  v_relationship text;
  v_religion text;
  v_dob_text text;
  v_dob date;
  v_grade_id uuid;
  v_grade_name text;
  v_current_grade_text text;
  v_current_grade_id uuid;
  v_prior text;
  v_school text;
  v_year text;
  v_month text;
  v_campus_id uuid;
  v_family_id uuid;
  v_student_id uuid;
  v_ref text;
  v_refs text[] := '{}';
begin
  perform public._require_public_service_caller();

  -- Public inquiries only: the applications switch plays no part here.
  select public_intake_open into v_open from public.admissions_settings where id = 1 for share;
  if v_open is not true then
    raise exception using errcode = 'TCS03', message = 'Online enquiries are closed';
  end if;

  -- ---------------------------------------------------- shape
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    perform public._public_invalid('The enquiry must be a JSON object', null);
  end if;
  perform public._public_only_keys(
    p_payload, array['referral_source', 'referral_source_other', 'comments', 'guardians', 'students'],
    'The enquiry', null);

  v_referral := public._public_text(p_payload, 'referral_source', 'How you heard about us', 30, true, 'referral_source');
  if v_referral not in ('current_parent', 'former_parent', 'parent_referral', 'staff_referral',
                        'website', 'friend_colleague', 'social_media', 'other') then
    perform public._public_invalid('How you heard about us: choose one of the listed options', 'referral_source');
  end if;
  v_referral_other := public._public_text(
    p_payload, 'referral_source_other', 'How you heard about us (other)', 255, v_referral = 'other',
    'referral_source_other');
  if v_referral <> 'other' then
    v_referral_other := '';
  end if;
  v_comments := public._public_text(p_payload, 'comments', 'Comments', 10000, false, 'comments');

  v_guardians := p_payload -> 'guardians';
  if v_guardians is null or jsonb_typeof(v_guardians) <> 'array'
     or jsonb_array_length(v_guardians) not between 1 and 2 then
    perform public._public_invalid('Give one or two parents or guardians', 'guardians');
  end if;
  v_students := p_payload -> 'students';
  if v_students is null or jsonb_typeof(v_students) <> 'array'
     or jsonb_array_length(v_students) not between 1 and 5 then
    perform public._public_invalid('Give between one and five children', 'students');
  end if;

  -- ---------------------------------------------------- guardians
  for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
    v_g := v_guardians -> v_i;
    v_label := 'Parent or guardian ' || (v_i + 1);
    v_path := 'guardians.' || v_i || '.';
    if jsonb_typeof(v_g) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object', 'guardians.' || v_i);
    end if;
    perform public._public_only_keys(
      v_g, array['surname', 'first_name', 'relationship', 'religion', 'address', 'town_city', 'phone', 'email'],
      v_label, 'guardians.' || v_i);
    perform public._public_text(v_g, 'surname', v_label || ': surname', 255, true, v_path || 'surname');
    perform public._public_text(v_g, 'first_name', v_label || ': first name', 255, true, v_path || 'first_name');
    v_relationship := public._public_text(v_g, 'relationship', v_label || ': relationship', 20, true, v_path || 'relationship');
    if v_relationship not in ('mother', 'father', 'guardian', 'other') then
      perform public._public_invalid(v_label || ': choose a relationship from the list', v_path || 'relationship');
    end if;
    v_religion := public._public_text(v_g, 'religion', v_label || ': religion', 30, true, v_path || 'religion');
    if v_religion not in ('Christian', 'Muslim', 'Traditional', 'Other', 'Prefer not to say') then
      perform public._public_invalid(v_label || ': choose a religion from the list', v_path || 'religion');
    end if;
    perform public._public_text(v_g, 'address', v_label || ': address', 255, true, v_path || 'address');
    perform public._public_text(v_g, 'town_city', v_label || ': town or city', 255, true, v_path || 'town_city');
    -- A plus sign and digits only (D-9d revised 2026-10-14): +233 and
    -- exactly 9 digits, or another country code and 8 to 15 digits in all.
    v_phone := public._public_text(v_g, 'phone', v_label || ': phone', 32, true, v_path || 'phone');
    if not (v_phone ~ '^\+233[1-9][0-9]{8}$'
            or (v_phone ~ '^\+[1-9][0-9]{7,14}$' and v_phone !~ '^\+233')) then
      perform public._public_invalid(
        v_label || ': format +233590000000, country code and number, no spaces',
        v_path || 'phone');
    end if;
    v_email := lower(public._public_text(v_g, 'email', v_label || ': email', 254, true, v_path || 'email'));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      perform public._public_invalid(v_label || ': enter a valid email address', v_path || 'email');
    end if;
    if not v_email = any (v_emails) then
      v_emails := v_emails || v_email;
    end if;
  end loop;

  -- ---------------------------------------------------- students
  for v_i in 0 .. jsonb_array_length(v_students) - 1 loop
    v_s := v_students -> v_i;
    v_label := 'Child ' || (v_i + 1);
    v_path := 'students.' || v_i || '.';
    if jsonb_typeof(v_s) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object', 'students.' || v_i);
    end if;
    perform public._public_only_keys(
      v_s, array['full_name', 'date_of_birth', 'current_school', 'current_grade_id', 'prior_schooling',
                 'grade_id', 'academic_year', 'campus_id', 'month_of_enrollment'],
      v_label, 'students.' || v_i);
    perform public._public_text(v_s, 'full_name', v_label || ': full name', 255, true, v_path || 'full_name');

    v_dob_text := public._public_text(v_s, 'date_of_birth', v_label || ': date of birth', 10, true, v_path || 'date_of_birth');
    if v_dob_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
    end if;
    begin
      v_dob := v_dob_text::date;
    exception when others then
      perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
    end;
    if v_dob > (clock_timestamp() at time zone 'Africa/Accra')::date or v_dob < date '1900-01-01' then
      perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
    end if;

    -- Current grade or class: an active grade id, or not yet in school.
    -- Exactly one.
    v_current_grade_text := public._public_text(
      v_s, 'current_grade_id', v_label || ': current grade or class', 36, false, v_path || 'current_grade_id');
    v_prior := public._public_text(
      v_s, 'prior_schooling', v_label || ': current grade or class', 30, false, v_path || 'current_grade_id');
    if v_current_grade_text <> '' and v_prior <> '' then
      perform public._public_invalid(v_label || ': choose one current grade or class', v_path || 'current_grade_id');
    end if;
    if v_current_grade_text = '' and v_prior = '' then
      perform public._public_invalid(v_label || ': current grade or class is required', v_path || 'current_grade_id');
    end if;
    if v_prior <> '' and v_prior <> 'not_yet_in_school' then
      perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
    end if;
    if v_current_grade_text <> '' then
      begin
        v_current_grade_id := v_current_grade_text::uuid;
      exception when invalid_text_representation then
        perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
      end;
      if not exists (select 1 from public.admissions_grades g where g.id = v_current_grade_id and g.is_active) then
        perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
      end if;
    end if;

    -- Current school: none when not yet in school, required otherwise.
    v_school := public._public_text(
      v_s, 'current_school', v_label || ': current school', 255, v_prior <> 'not_yet_in_school', v_path || 'current_school');
    if v_prior = 'not_yet_in_school' and v_school <> '' then
      perform public._public_invalid(
        v_label || ': leave current school empty for a child not yet in school', v_path || 'current_school');
    end if;

    v_month := public._public_text(v_s, 'month_of_enrollment', v_label || ': month of enrolment', 20, true, v_path || 'month_of_enrollment');
    if v_month not in ('January', 'September') then
      perform public._public_invalid(v_label || ': choose a month of enrolment from the list', v_path || 'month_of_enrollment');
    end if;

    -- Grade applying into: an active grade id, nothing else.
    begin
      v_grade_id := public._public_text(v_s, 'grade_id', v_label || ': grade', 36, true, v_path || 'grade_id')::uuid;
    exception when invalid_text_representation then
      perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
    end;
    v_grade_name := null;
    select g.name into v_grade_name from public.admissions_grades g
    where g.id = v_grade_id and g.is_active;
    if v_grade_name is null then
      perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
    end if;

    -- Academic year: an active label, nothing else.
    v_year := public._public_text(v_s, 'academic_year', v_label || ': academic year', 20, true, v_path || 'academic_year');
    if not exists (select 1 from public.admissions_academic_years y where y.label = v_year and y.is_active) then
      perform public._public_invalid(v_label || ': choose an academic year from the list', v_path || 'academic_year');
    end if;

    -- Campus: optional, a campus id, and it must accept the grade.
    v_campus_id := null;
    if public._public_text(v_s, 'campus_id', v_label || ': campus', 36, false, v_path || 'campus_id') <> '' then
      begin
        v_campus_id := (v_s ->> 'campus_id')::uuid;
      exception when invalid_text_representation then
        perform public._public_invalid(v_label || ': choose a campus from the list', v_path || 'campus_id');
      end;
      if not exists (select 1 from public.branches b where b.id = v_campus_id) then
        perform public._public_invalid(v_label || ': choose a campus from the list', v_path || 'campus_id');
      end if;
      if exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = v_campus_id)
         and not exists (select 1 from public.admissions_campus_grade_rules r
                         where r.branch_id = v_campus_id and r.grade_id = v_grade_id) then
        perform public._public_invalid(
          v_label || ': this campus does not take ' || v_grade_name || '. Please contact the school',
          v_path || 'grade_id');
      end if;
    end if;
  end loop;

  -- ---------------------------------------------------- per-email limit
  foreach v_email in array v_emails loop
    if not public._public_rate_limit_hit(
      'inquiry_email', encode(sha256(convert_to(v_email, 'UTF8')), 'hex')
    ) then
      raise exception using errcode = 'TCS29', message = 'Too many enquiries for this email today';
    end if;
  end loop;

  -- ---------------------------------------------------- writes
  insert into public.families (referral_source, referral_source_other, comments)
  values (v_referral, v_referral_other, v_comments)
  returning id into v_family_id;

  for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
    v_g := v_guardians -> v_i;
    insert into public.guardians
      (family_id, surname, first_name, relationship, religion, address, town_city, phone, email)
    values (
      v_family_id,
      btrim(v_g ->> 'surname'), btrim(v_g ->> 'first_name'), btrim(v_g ->> 'relationship'),
      btrim(v_g ->> 'religion'), btrim(v_g ->> 'address'), btrim(v_g ->> 'town_city'),
      btrim(v_g ->> 'phone'), btrim(v_g ->> 'email')
    );
  end loop;

  for v_i in 0 .. jsonb_array_length(v_students) - 1 loop
    v_s := v_students -> v_i;
    select g.name into v_grade_name from public.admissions_grades g
    where g.id = (v_s ->> 'grade_id')::uuid;
    v_campus_id := nullif(btrim(coalesce(v_s ->> 'campus_id', '')), '')::uuid;

    insert into public.students
      (family_id, full_name, date_of_birth, current_school, current_grade, current_grade_id, prior_schooling)
    values (
      v_family_id, btrim(v_s ->> 'full_name'), (btrim(v_s ->> 'date_of_birth'))::date,
      btrim(coalesce(v_s ->> 'current_school', '')), '',
      nullif(btrim(coalesce(v_s ->> 'current_grade_id', '')), '')::uuid,
      nullif(btrim(coalesce(v_s ->> 'prior_schooling', '')), '')
    )
    returning id into v_student_id;

    insert into public.applications
      (student_id, stage, academic_year, year_group_applied_for, month_of_enrollment, branch_id)
    values (
      v_student_id, 'inquiry', btrim(v_s ->> 'academic_year'), v_grade_name,
      btrim(v_s ->> 'month_of_enrollment'), v_campus_id
    )
    returning inquiry_reference into v_ref;
    v_refs := v_refs || v_ref;
  end loop;

  perform public._enqueue_admissions_emails('inquiry', v_family_id, null, v_emails);

  return v_refs;
end;
$$;

-- submit_application, re-created from 20261025100000 with one line added:
-- the outbox insert after every write. The repeat submit of a used session
-- (D-9o) returns before it, so a double click never queues a second email.
-- Same signature and grants.
create or replace function public.submit_application(
  p_payload jsonb, p_session_token text, p_sniffed jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open boolean;
  v_guardians jsonb;
  v_g jsonb;
  v_s jsonb;
  v_ec jsonb;
  v_h jsonb;
  v_docs jsonb;
  v_d jsonb;
  v_label text;
  v_path text;
  v_i integer;
  v_phone text;
  v_email text;
  v_emails text[] := '{}';
  v_relationship text;
  v_religion text;
  -- student
  v_full_name text;
  v_dob_text text;
  v_dob date;
  v_gender text;
  v_nationality text;
  v_address text;
  v_town text;
  v_postal text;
  v_country text;
  v_school text;
  v_prev_location text;
  v_current_grade_text text;
  v_current_grade_id uuid;
  v_prior text;
  v_grade_id uuid;
  v_grade_name text;
  v_year text;
  v_month text;
  v_campus_id uuid;
  -- application
  v_ec_name text;
  v_ec_relationship text;
  v_ec_phone text;
  v_has_needs boolean;
  v_needs text;
  v_has_medical boolean;
  v_medical text;
  v_has_allergies boolean;
  v_allergies text;
  v_wants_scholarship boolean;
  v_scholarship text;
  v_media boolean;
  v_signature text;
  -- documents
  v_required text[];
  v_types text[] := '{}';
  v_res_ids uuid[] := '{}';
  v_res_id uuid;
  v_res public.application_upload_reservations;
  v_kind text;
  -- session and writes
  v_session public.application_upload_sessions;
  v_family_id uuid;
  v_student_id uuid;
  v_app public.applications;
  v_matched_app_id uuid;
  v_family_matched boolean := false;
  v_student_matched boolean := false;
  v_outcome text := 'new_application';
  v_existing public.guardians;
  v_existing_student public.students;
  v_guardian_diffs jsonb := '[]'::jsonb;
  v_student_diffs jsonb := '{}'::jsonb;
  v_fields jsonb;
  v_differences jsonb;
  v_now timestamptz := clock_timestamp();
  v_doc_message constant text :=
    'A required document is missing or could not be accepted. Please choose your files again and resubmit.';
begin
  perform public._require_public_service_caller();

  -- Public applications only: the enquiries switch plays no part here.
  select public_applications_open into v_open from public.admissions_settings where id = 1 for share;
  if v_open is not true then
    raise exception using errcode = 'TCS03', message = 'Online applications are closed';
  end if;

  -- ---------------------------------------------------- shape
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    perform public._public_invalid('The application must be a JSON object', null);
  end if;
  perform public._public_only_keys(
    p_payload, array['guardians', 'student', 'campus_id', 'emergency_contact', 'health_info', 'documents',
                     'wants_scholarship_info', 'scholarship_interest_details', 'media_consent_agreed',
                     'declaration_signature_name', 'declaration_agreed'],
    'The application', null);

  -- ---------------------------------------------------- guardians
  v_guardians := p_payload -> 'guardians';
  if v_guardians is null or jsonb_typeof(v_guardians) <> 'array'
     or jsonb_array_length(v_guardians) not between 1 and 2 then
    perform public._public_invalid('Give one or two parents or guardians', 'guardians');
  end if;
  for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
    v_g := v_guardians -> v_i;
    v_label := 'Parent or guardian ' || (v_i + 1);
    v_path := 'guardians.' || v_i || '.';
    if jsonb_typeof(v_g) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object', 'guardians.' || v_i);
    end if;
    perform public._public_only_keys(
      v_g, array['surname', 'first_name', 'relationship', 'religion', 'address', 'town_city', 'phone', 'email'],
      v_label, 'guardians.' || v_i);
    perform public._public_text(v_g, 'surname', v_label || ': surname', 255, true, v_path || 'surname');
    perform public._public_text(v_g, 'first_name', v_label || ': first name', 255, true, v_path || 'first_name');
    v_relationship := public._public_text(v_g, 'relationship', v_label || ': relationship', 20, true, v_path || 'relationship');
    if v_relationship not in ('mother', 'father', 'guardian', 'other') then
      perform public._public_invalid(v_label || ': choose a relationship from the list', v_path || 'relationship');
    end if;
    v_religion := public._public_text(v_g, 'religion', v_label || ': religion', 30, true, v_path || 'religion');
    if v_religion not in ('Christian', 'Muslim', 'Traditional', 'Other', 'Prefer not to say') then
      perform public._public_invalid(v_label || ': choose a religion from the list', v_path || 'religion');
    end if;
    perform public._public_text(v_g, 'address', v_label || ': address', 255, true, v_path || 'address');
    perform public._public_text(v_g, 'town_city', v_label || ': town or city', 255, true, v_path || 'town_city');
    v_phone := public._public_text(v_g, 'phone', v_label || ': phone', 32, true, v_path || 'phone');
    if not public._public_phone_ok(v_phone) then
      perform public._public_invalid(
        v_label || ': format +233590000000, country code and number, no spaces', v_path || 'phone');
    end if;
    v_email := lower(public._public_text(v_g, 'email', v_label || ': email', 254, true, v_path || 'email'));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      perform public._public_invalid(v_label || ': enter a valid email address', v_path || 'email');
    end if;
    if not v_email = any (v_emails) then
      v_emails := v_emails || v_email;
    end if;
  end loop;

  -- ---------------------------------------------------- student
  v_s := p_payload -> 'student';
  if v_s is null or jsonb_typeof(v_s) <> 'object' then
    perform public._public_invalid('The child''s details are required', 'student');
  end if;
  v_label := 'Child';
  v_path := 'student.';
  perform public._public_only_keys(
    v_s, array['full_name', 'date_of_birth', 'gender', 'nationality', 'address', 'town_city', 'postal_code',
               'country', 'current_school', 'previous_school_location', 'current_grade_id', 'prior_schooling',
               'grade_id', 'academic_year', 'month_of_enrollment'],
    v_label, 'student');
  v_full_name := public._public_text(v_s, 'full_name', v_label || ': full name', 255, true, v_path || 'full_name');

  v_dob_text := public._public_text(v_s, 'date_of_birth', v_label || ': date of birth', 10, true, v_path || 'date_of_birth');
  if v_dob_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
  end if;
  begin
    v_dob := v_dob_text::date;
  exception when others then
    perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
  end;
  if v_dob > (clock_timestamp() at time zone 'Africa/Accra')::date or v_dob < date '1900-01-01' then
    perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
  end if;

  v_gender := public._public_text(v_s, 'gender', v_label || ': gender', 10, true, v_path || 'gender');
  if v_gender not in ('male', 'female') then
    perform public._public_invalid(v_label || ': choose a gender from the list', v_path || 'gender');
  end if;
  v_nationality := public._public_text(v_s, 'nationality', v_label || ': nationality', 100, true, v_path || 'nationality');
  v_address := public._public_text(v_s, 'address', v_label || ': address', 255, true, v_path || 'address');
  v_town := public._public_text(v_s, 'town_city', v_label || ': town or city', 255, true, v_path || 'town_city');
  v_postal := public._public_text(v_s, 'postal_code', v_label || ': postal code', 20, false, v_path || 'postal_code');
  v_country := public._public_text(v_s, 'country', v_label || ': country', 100, false, v_path || 'country');
  v_prev_location := public._public_text(
    v_s, 'previous_school_location', v_label || ': previous school location', 255, false,
    v_path || 'previous_school_location');

  -- Current grade or class: an active grade id, or not yet in school.
  -- Exactly one (slice 8b).
  v_current_grade_text := public._public_text(
    v_s, 'current_grade_id', v_label || ': current grade or class', 36, false, v_path || 'current_grade_id');
  v_prior := public._public_text(
    v_s, 'prior_schooling', v_label || ': current grade or class', 30, false, v_path || 'current_grade_id');
  if v_current_grade_text <> '' and v_prior <> '' then
    perform public._public_invalid(v_label || ': choose one current grade or class', v_path || 'current_grade_id');
  end if;
  if v_current_grade_text = '' and v_prior = '' then
    perform public._public_invalid(v_label || ': current grade or class is required', v_path || 'current_grade_id');
  end if;
  if v_prior <> '' and v_prior <> 'not_yet_in_school' then
    perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
  end if;
  v_current_grade_id := null;
  if v_current_grade_text <> '' then
    begin
      v_current_grade_id := v_current_grade_text::uuid;
    exception when invalid_text_representation then
      perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
    end;
    if not exists (select 1 from public.admissions_grades g where g.id = v_current_grade_id and g.is_active) then
      perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
    end if;
  end if;

  -- Current school: none when not yet in school, required otherwise.
  v_school := public._public_text(
    v_s, 'current_school', v_label || ': current school', 255, v_prior <> 'not_yet_in_school', v_path || 'current_school');
  if v_prior = 'not_yet_in_school' and v_school <> '' then
    perform public._public_invalid(
      v_label || ': leave current school empty for a child not yet in school', v_path || 'current_school');
  end if;

  v_month := public._public_text(v_s, 'month_of_enrollment', v_label || ': month of enrolment', 20, true, v_path || 'month_of_enrollment');
  if v_month not in ('January', 'September') then
    perform public._public_invalid(v_label || ': choose a month of enrolment from the list', v_path || 'month_of_enrollment');
  end if;

  -- Grade applying into: an active grade id, nothing else.
  begin
    v_grade_id := public._public_text(v_s, 'grade_id', v_label || ': grade', 36, true, v_path || 'grade_id')::uuid;
  exception when invalid_text_representation then
    perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
  end;
  select g.name into v_grade_name from public.admissions_grades g where g.id = v_grade_id and g.is_active;
  if v_grade_name is null then
    perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
  end if;

  -- Academic year: an active label, nothing else.
  v_year := public._public_text(v_s, 'academic_year', v_label || ': academic year', 20, true, v_path || 'academic_year');
  if not exists (select 1 from public.admissions_academic_years y where y.label = v_year and y.is_active) then
    perform public._public_invalid(v_label || ': choose an academic year from the list', v_path || 'academic_year');
  end if;

  -- ---------------------------------------------------- campus
  -- Required for an application, and a campus with grade rules must accept
  -- the grade.
  begin
    v_campus_id := public._public_text(p_payload, 'campus_id', 'Campus', 36, true, 'campus_id')::uuid;
  exception when invalid_text_representation then
    perform public._public_invalid('Choose a campus from the list', 'campus_id');
  end;
  if not exists (select 1 from public.branches b where b.id = v_campus_id) then
    perform public._public_invalid('Choose a campus from the list', 'campus_id');
  end if;
  if exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = v_campus_id)
     and not exists (select 1 from public.admissions_campus_grade_rules r
                     where r.branch_id = v_campus_id and r.grade_id = v_grade_id) then
    perform public._public_invalid(
      'This campus does not take ' || v_grade_name || '. Please choose another campus or contact the school',
      'campus_id');
  end if;

  -- ---------------------------------------------------- emergency contact
  v_ec := p_payload -> 'emergency_contact';
  if v_ec is null or jsonb_typeof(v_ec) <> 'object' then
    perform public._public_invalid('An emergency contact is required', 'emergency_contact');
  end if;
  perform public._public_only_keys(v_ec, array['name', 'relationship', 'phone'], 'Emergency contact', 'emergency_contact');
  v_ec_name := public._public_text(v_ec, 'name', 'Emergency contact: name', 255, true, 'emergency_contact.name');
  v_ec_relationship := public._public_text(
    v_ec, 'relationship', 'Emergency contact: relationship', 100, true, 'emergency_contact.relationship');
  v_ec_phone := public._public_text(v_ec, 'phone', 'Emergency contact: phone', 32, true, 'emergency_contact.phone');
  if not public._public_phone_ok(v_ec_phone) then
    perform public._public_invalid(
      'Emergency contact: format +233590000000, country code and number, no spaces', 'emergency_contact.phone');
  end if;

  -- ---------------------------------------------------- health
  -- Details are kept only when the answer is yes; 2,000 characters each
  -- (D-4e).
  v_h := p_payload -> 'health_info';
  if v_h is null or jsonb_typeof(v_h) <> 'object' then
    perform public._public_invalid('The health questions are required', 'health_info');
  end if;
  perform public._public_only_keys(
    v_h, array['has_learning_or_physical_needs', 'learning_or_physical_needs_details', 'has_medical_conditions',
               'medical_conditions_details', 'has_allergies_or_dietary_requirements', 'allergies_dietary_details'],
    'Health', 'health_info');
  v_has_needs := public._public_bool(
    v_h, 'has_learning_or_physical_needs', 'Learning or physical needs', 'health_info.has_learning_or_physical_needs');
  v_needs := public._public_text(
    v_h, 'learning_or_physical_needs_details', 'Learning or physical needs: details', 2000, v_has_needs,
    'health_info.learning_or_physical_needs_details');
  v_has_medical := public._public_bool(
    v_h, 'has_medical_conditions', 'Medical conditions', 'health_info.has_medical_conditions');
  v_medical := public._public_text(
    v_h, 'medical_conditions_details', 'Medical conditions: details', 2000, v_has_medical,
    'health_info.medical_conditions_details');
  v_has_allergies := public._public_bool(
    v_h, 'has_allergies_or_dietary_requirements', 'Allergies or dietary requirements',
    'health_info.has_allergies_or_dietary_requirements');
  v_allergies := public._public_text(
    v_h, 'allergies_dietary_details', 'Allergies or dietary requirements: details', 2000, v_has_allergies,
    'health_info.allergies_dietary_details');
  if not v_has_needs then v_needs := ''; end if;
  if not v_has_medical then v_medical := ''; end if;
  if not v_has_allergies then v_allergies := ''; end if;

  -- ---------------------------------------------------- the rest
  v_wants_scholarship := public._public_bool(
    p_payload, 'wants_scholarship_info', 'Scholarship information', 'wants_scholarship_info');
  v_scholarship := public._public_text(
    p_payload, 'scholarship_interest_details', 'Scholarship interest', 10000, false, 'scholarship_interest_details');
  if not v_wants_scholarship then v_scholarship := ''; end if;
  v_media := public._public_bool(p_payload, 'media_consent_agreed', 'Media consent', 'media_consent_agreed');
  v_signature := public._public_text(
    p_payload, 'declaration_signature_name', 'Declaration: your full name as signature', 255, true,
    'declaration_signature_name');
  if not public._public_bool(p_payload, 'declaration_agreed', 'Declaration', 'declaration_agreed') then
    perform public._public_invalid('You must agree to the declaration to submit this application', 'declaration_agreed');
  end if;

  -- ---------------------------------------------------- documents (shape)
  v_docs := p_payload -> 'documents';
  if v_docs is null or jsonb_typeof(v_docs) <> 'array' or jsonb_array_length(v_docs) not between 1 and 4 then
    perform public._public_invalid(v_doc_message, 'documents');
  end if;
  for v_i in 0 .. jsonb_array_length(v_docs) - 1 loop
    v_d := v_docs -> v_i;
    if jsonb_typeof(v_d) <> 'object'
       or exists (select 1 from jsonb_object_keys(v_d) k where k not in ('document_type', 'reservation_id', 'path'))
       or jsonb_typeof(v_d -> 'document_type') is distinct from 'string'
       or jsonb_typeof(v_d -> 'reservation_id') is distinct from 'string'
       or jsonb_typeof(v_d -> 'path') is distinct from 'string'
       or (v_d ->> 'reservation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (v_d ->> 'document_type') = any (v_types) then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
    v_types := v_types || (v_d ->> 'document_type');
    v_res_ids := v_res_ids || (v_d ->> 'reservation_id')::uuid;
  end loop;
  v_required := public._application_required_document_types(v_grade_id);
  if v_required is null or not (v_types @> v_required) then
    perform public._public_invalid(v_doc_message, 'documents');
  end if;
  if p_sniffed is null or jsonb_typeof(p_sniffed) <> 'array' then
    perform public._public_invalid(v_doc_message, 'documents');
  end if;

  -- ---------------------------------------------------- session
  if p_session_token is not null and p_session_token ~ '^[0-9a-f]{64}$' then
    select * into v_session from public.application_upload_sessions
    where token_hash = encode(sha256(convert_to(p_session_token, 'UTF8')), 'hex')
    for update;
  end if;
  -- The same session already made an application: a double click or a
  -- retry. Same answer, nothing written, nothing counted.
  if v_session.id is not null and v_session.submitted_application_id is not null then
    return (select a.application_reference from public.applications a
            where a.id = v_session.submitted_application_id);
  end if;
  if v_session.id is null or v_session.closed_at is not null or v_session.expires_at <= v_now then
    raise exception using errcode = 'TCS22', detail = 'documents',
      message = 'Your upload session has expired. Please reload the page and choose your files again.';
  end if;

  -- ---------------------------------------------------- per-email limit
  -- In sorted order, so two submissions naming the same emails take the
  -- counter rows' locks (held to commit) in the same order and can't
  -- deadlock. Those locks also make two submissions sharing an email run
  -- one after the other, so the second one's family match sees the first.
  select array_agg(e order by e) into v_emails from unnest(v_emails) e;
  foreach v_email in array v_emails loop
    if not public._public_rate_limit_hit(
      'application_email', encode(sha256(convert_to(v_email, 'UTF8')), 'hex')
    ) then
      raise exception using errcode = 'TCS29', message = 'Too many applications for this email today';
    end if;
  end loop;

  -- ---------------------------------------------------- documents (binding)
  -- Every reservation of the session, locked in id order.
  perform 1 from public.application_upload_reservations r
  where r.session_id = v_session.id order by r.id for update;
  for v_i in 0 .. jsonb_array_length(v_docs) - 1 loop
    v_d := v_docs -> v_i;
    v_res := null;
    select * into v_res from public.application_upload_reservations r
    where r.id = (v_d ->> 'reservation_id')::uuid and r.session_id = v_session.id;
    if v_res.id is null
       or v_res.consumed_at is not null or v_res.cleaned_at is not null or v_res.expires_at <= v_now
       or v_res.document_type <> (v_d ->> 'document_type')
       or v_res.storage_path <> (v_d ->> 'path') then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
    if not exists (select 1 from storage.objects o
                   where o.bucket_id = 'admissions-documents' and o.name = v_res.storage_path) then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
    -- The kind the Edge Function read from this reservation's own path.
    select e ->> 'kind' into v_kind
    from jsonb_array_elements(p_sniffed) e
    where jsonb_typeof(e) = 'object'
      and e ->> 'reservation_id' = v_res.id::text
      and e ->> 'path' = v_res.storage_path
    limit 1;
    if v_kind is null or v_kind is distinct from public._application_kind_for_extension(v_res.extension) then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
  end loop;

  -- ---------------------------------------------------- family
  select f.id into v_family_id
  from public.families f
  where exists (select 1 from public.guardians g where g.family_id = f.id and g.email = any (v_emails))
  order by exists (select 1 from public.students s
                   where s.family_id = f.id and lower(btrim(s.full_name)) = lower(v_full_name)
                     and s.date_of_birth = v_dob) desc,
           f.created_at, f.id
  limit 1;

  if v_family_id is null then
    insert into public.families default values returning id into v_family_id;
    for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
      v_g := v_guardians -> v_i;
      insert into public.guardians
        (family_id, surname, first_name, relationship, religion, address, town_city, phone, email)
      values (
        v_family_id,
        btrim(v_g ->> 'surname'), btrim(v_g ->> 'first_name'), btrim(v_g ->> 'relationship'),
        btrim(v_g ->> 'religion'), btrim(v_g ->> 'address'), btrim(v_g ->> 'town_city'),
        btrim(v_g ->> 'phone'), btrim(v_g ->> 'email')
      );
    end loop;
  else
    -- Matched: the family's guardians are never added to or changed. What
    -- differs is recorded for staff.
    v_family_matched := true;
    for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
      v_g := v_guardians -> v_i;
      v_email := lower(btrim(v_g ->> 'email'));
      v_existing := null;
      select * into v_existing from public.guardians g
      where g.family_id = v_family_id and g.email = v_email
      order by g.id limit 1;
      if v_existing.id is null then
        v_guardian_diffs := v_guardian_diffs || jsonb_build_array(jsonb_build_object(
          'email', v_email, 'new', true,
          'fields', jsonb_build_object(
            'surname', btrim(v_g ->> 'surname'), 'first_name', btrim(v_g ->> 'first_name'),
            'relationship', btrim(v_g ->> 'relationship'), 'religion', btrim(v_g ->> 'religion'),
            'address', btrim(v_g ->> 'address'), 'town_city', btrim(v_g ->> 'town_city'),
            'phone', btrim(v_g ->> 'phone'))));
      else
        select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_fields
        from (values
          ('surname', btrim(v_g ->> 'surname'), v_existing.surname),
          ('first_name', btrim(v_g ->> 'first_name'), v_existing.first_name),
          ('relationship', btrim(v_g ->> 'relationship'), v_existing.relationship),
          ('religion', btrim(v_g ->> 'religion'), v_existing.religion),
          ('address', btrim(v_g ->> 'address'), v_existing.address),
          ('town_city', btrim(v_g ->> 'town_city'), v_existing.town_city),
          ('phone', btrim(v_g ->> 'phone'), v_existing.phone)
        ) as d (k, v, old)
        where d.v is distinct from d.old;
        if v_fields <> '{}'::jsonb then
          v_guardian_diffs := v_guardian_diffs || jsonb_build_array(jsonb_build_object(
            'email', v_email, 'new', false, 'fields', v_fields));
        end if;
      end if;
    end loop;
  end if;

  -- ---------------------------------------------------- student
  select * into v_existing_student from public.students s
  where s.family_id = v_family_id and lower(btrim(s.full_name)) = lower(v_full_name) and s.date_of_birth = v_dob
  order by s.id limit 1;
  if v_existing_student.id is null then
    insert into public.students
      (family_id, full_name, date_of_birth, gender, nationality, address, town_city, postal_code, country,
       current_school, previous_school_location, current_grade, current_grade_id, prior_schooling)
    values (
      v_family_id, v_full_name, v_dob, v_gender, v_nationality, v_address, v_town, v_postal, v_country,
      v_school, v_prev_location, '', v_current_grade_id, nullif(v_prior, '')
    )
    returning id into v_student_id;
  else
    -- Matched: never updated. What differs is recorded for staff.
    v_student_matched := true;
    v_student_id := v_existing_student.id;
    select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_student_diffs
    from (values
      ('gender', v_gender, v_existing_student.gender),
      ('nationality', v_nationality, v_existing_student.nationality),
      ('address', v_address, v_existing_student.address),
      ('town_city', v_town, v_existing_student.town_city),
      ('postal_code', v_postal, v_existing_student.postal_code),
      ('country', v_country, v_existing_student.country),
      ('current_school', v_school, v_existing_student.current_school),
      ('previous_school_location', v_prev_location, v_existing_student.previous_school_location),
      ('current_grade_id', v_current_grade_id::text, v_existing_student.current_grade_id::text),
      ('prior_schooling', nullif(v_prior, ''), v_existing_student.prior_schooling)
    ) as d (k, v, old)
    where d.v is distinct from d.old;
  end if;

  -- ---------------------------------------------------- application
  v_app := null;
  if v_student_matched then
    -- An inquiry for the same year and grade is advanced, the oldest first,
    -- re-checked under its row lock.
    select * into v_app from public.applications a
    where a.student_id = v_student_id and a.academic_year = v_year
      and a.year_group_applied_for = v_grade_name and a.stage = 'inquiry'
    order by a.created_at, a.id
    limit 1
    for update;
    if v_app.id is null then
      select a.id into v_matched_app_id from public.applications a
      where a.student_id = v_student_id and a.academic_year = v_year
        and a.year_group_applied_for = v_grade_name
      order by a.created_at desc, a.id desc
      limit 1;
    end if;
  end if;

  if v_app.id is not null then
    v_outcome := 'inquiry_advanced';
    update public.applications set
      stage = 'application',
      month_of_enrollment = v_month,
      branch_id = v_campus_id,
      wants_scholarship_info = v_wants_scholarship,
      scholarship_interest_details = v_scholarship,
      declaration_signature_name = v_signature,
      declaration_agreed = true,
      declaration_agreed_at = v_now,
      declaration_ip_address = null,
      media_consent_agreed = v_media
    where id = v_app.id
    returning * into v_app;
  else
    if v_matched_app_id is not null then
      v_outcome := 'possible_duplicate';
    end if;
    insert into public.applications
      (student_id, stage, academic_year, year_group_applied_for, month_of_enrollment, branch_id,
       wants_scholarship_info, scholarship_interest_details, declaration_signature_name,
       declaration_agreed, declaration_agreed_at, declaration_ip_address, media_consent_agreed)
    values (
      v_student_id, 'application', v_year, v_grade_name, v_month, v_campus_id,
      v_wants_scholarship, v_scholarship, v_signature, true, v_now, null, v_media
    )
    returning * into v_app;
  end if;

  insert into public.application_emergency_contacts (application_id, name, relationship, phone)
  values (v_app.id, v_ec_name, v_ec_relationship, v_ec_phone);

  -- Always the application's own fresh row (D-9j).
  insert into public.application_health_info
    (application_id, has_learning_or_physical_needs, learning_or_physical_needs_details,
     has_medical_conditions, medical_conditions_details,
     has_allergies_or_dietary_requirements, allergies_dietary_details)
  values (v_app.id, v_has_needs, v_needs, v_has_medical, v_medical, v_has_allergies, v_allergies);

  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at)
  select v_app.id, r.document_type, r.storage_path, 'pending_review', v_now
  from public.application_upload_reservations r
  where r.id = any (v_res_ids)
  order by array_position(v_res_ids, r.id);

  update public.application_upload_reservations set consumed_at = v_now where id = any (v_res_ids);
  update public.application_upload_sessions
  set closed_at = v_now, submitted_application_id = v_app.id
  where id = v_session.id;

  if v_family_matched then
    v_differences := '{}'::jsonb;
    if jsonb_array_length(v_guardian_diffs) > 0 then
      v_differences := v_differences || jsonb_build_object('guardians', v_guardian_diffs);
    end if;
    if v_student_diffs <> '{}'::jsonb then
      v_differences := v_differences || jsonb_build_object('student', v_student_diffs);
    end if;
    insert into public.application_match_flags
      (application_id, family_matched, student_matched, outcome, matched_application_id, differences)
    values (v_app.id, true, v_student_matched, v_outcome, v_matched_app_id, v_differences);
  end if;

  perform public._enqueue_admissions_emails('application', v_family_id, v_app.id, v_emails);

  return v_app.application_reference;
end;
$$;

-- ------------------------------------------------------------ grants

-- Helpers: nobody.
revoke execute on function public._admissions_email_retry_delay(integer) from public, anon, authenticated, service_role;
revoke execute on function public._admissions_email_params_ok(text, jsonb) from public, anon, authenticated, service_role;
revoke execute on function public._admissions_mask_email(text) from public, anon, authenticated, service_role;
revoke execute on function public._enqueue_admissions_emails(text, uuid, uuid, text[]) from public, anon, authenticated, service_role;
revoke execute on function public.set_admissions_worker_url(text) from public, anon, authenticated, service_role;

-- The worker: service_role only.
revoke execute on function public.admissions_worker_secret() from public, anon, authenticated;
grant execute on function public.admissions_worker_secret() to service_role;
revoke execute on function public.claim_admissions_emails(integer, integer) from public, anon, authenticated;
grant execute on function public.claim_admissions_emails(integer, integer) to service_role;
revoke execute on function public.mark_admissions_email_result(uuid, uuid, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.mark_admissions_email_result(uuid, uuid, text, text, integer, text) to service_role;

-- Staff: signed-in callers; each function checks the role itself.
revoke execute on function public.requeue_admissions_emails(uuid[]) from public, anon;
grant execute on function public.requeue_admissions_emails(uuid[]) to authenticated;
revoke execute on function public.list_admissions_emails(text, integer) from public, anon;
grant execute on function public.list_admissions_emails(text, integer) to authenticated;
revoke execute on function public.get_admissions_email_health() from public, anon;
grant execute on function public.get_admissions_email_health() to authenticated;
revoke execute on function public.get_application_email_status(uuid) from public, anon;
grant execute on function public.get_application_email_status(uuid) to authenticated;
