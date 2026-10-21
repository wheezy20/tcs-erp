-- Admissions slice 13, migration 2 of 2: capturing a lead, its two emails,
-- the staff lead list and lead retention (docs/admissions/PORT-PLAN.md,
-- "Slice 13 plan").
--
--   capture_lead            service role only; the admissions-public
--                           pdf_gate action calls it after Turnstile
--   _enqueue_lead_emails    callable by nobody
--   get_lead_alert          service role only; the worker reads the staff
--                           alert's fields while it holds the claim
--   list_admissions_leads   Manager and Admissions Officer in full, Auditor
--                           masked (D-13h, a new permission approved by
--                           Eyram 2026-10-21)
--
-- Re-created: _enqueue_admissions_emails (the parent cap counts only
-- parent kinds), claim_admissions_emails (lead mail claimed last and at
-- most half the daily ceiling) and purge_admissions_housekeeping (lead
-- retention). Same signatures, so no drops.
--
-- Errors use the slice 8 SQLSTATEs the Edge Function maps:
--   TCS22  invalid input; the message is safe to show, the field in DETAIL
--   TCS03  lead capture is closed
--
-- The anon-executable count stays at 170.

-- ------------------------------------------------------------ emails

-- Called only from capture_lead, in its transaction. The PDF goes to the
-- lead's address unless that address already had 2 in 24 hours; then the
-- row is stored suppressed and nothing tells the sender. The staff alert
-- always queues.
create or replace function public._enqueue_lead_emails(p_lead_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_email text;
  v_cap integer;
  v_window interval;
  v_recent integer;
begin
  select l.email into v_email from public.admissions_leads l where l.id = p_lead_id;
  if v_email is null then
    raise exception 'A lead without an email can''t be sent the PDF';
  end if;
  -- The lock every email to this address takes, so the count is exact.
  perform pg_advisory_xact_lock(hashtextextended('admissions_email:' || v_email, 0));

  select r.max_count, r.window_length into v_cap, v_window
  from public._public_rate_limit_rule('lead_email_day') r;
  select count(*) into v_recent
  from public.admissions_email_outbox o
  where o.kind = 'pdf_gate' and o.recipient_email = v_email
    and o.status <> 'suppressed'
    and o.created_at > clock_timestamp() - v_window;

  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, lead_id)
  values ('lead:' || p_lead_id, 'pdf_gate', v_email, '{}', '{}'::jsonb,
          case when v_recent >= v_cap then 'suppressed' else 'pending' end, p_lead_id);

  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, lead_id)
  values ('lead:' || p_lead_id, 'lead_staff', null, '{}', '{}'::jsonb, p_lead_id);
end;
$$;

-- Re-created from 20261028100000 with one predicate changed: the 4 a day
-- cap counts only confirmation emails (the two parent kinds), so neither a
-- resume email nor a PDF can use up a family's confirmations. Same
-- signature and grants (callable by nobody).
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
      and o.kind in ('inquiry_parent', 'application_parent')
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

-- ------------------------------------------------------------ capture

-- The PDF gate. Order: the caller, the source, the lead switch, the
-- fields, the insert, the emails. Only the known keys are read, so a
-- sender's own "source" (or anything else) is ignored, as in TCS OS.
-- Returns true and nothing else: no id, no echo.
create or replace function public.capture_lead(p_source text, p_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_email text;
  v_phone text;
  v_grade text;
  v_consent boolean;
  v_utm text[] := array[null, null, null]::text[];
  v_key text;
  v_i integer := 0;
  v_id uuid;
begin
  perform public._require_public_service_caller();
  if p_source is distinct from 'pdf_gate_admissions_overview' then
    raise exception 'Unknown lead source';
  end if;
  if not coalesce((select s.public_leads_open from public.admissions_settings s where s.id = 1), false) then
    raise exception using errcode = 'TCS03',
      message = 'The Admissions Overview download is not available right now. Please contact the school office.';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    perform public._public_invalid('The form could not be read', '');
  end if;

  v_name := public._public_text(p_payload, 'name', 'Name', 255, true, 'name');
  if v_name ~ '[[:cntrl:]]' then
    perform public._public_invalid('Name has characters the form does not accept', 'name');
  end if;

  v_email := lower(public._public_text(p_payload, 'email', 'Email', 254, true, 'email'));
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    perform public._public_invalid('Enter a valid email address', 'email');
  end if;

  v_phone := regexp_replace(public._public_text(p_payload, 'phone', 'Phone', 32, false, 'phone'),
                            '[[:space:]]', '', 'g');
  if v_phone <> '' and not public._public_phone_ok(v_phone) then
    perform public._public_invalid('Enter the phone number with its country code, for example +233 24 123 4567', 'phone');
  end if;

  v_grade := public._public_text(p_payload, 'grade_interest', 'Grade of interest', 50, false, 'grade_interest');
  if v_grade ~ '[[:cntrl:]]' then
    perform public._public_invalid('Grade of interest has characters the form does not accept', 'grade_interest');
  end if;

  -- Consent: only the JSON boolean true. "true", "on", 1 and null are false.
  v_consent := coalesce(jsonb_typeof(p_payload -> 'consent_to_marketing') = 'boolean'
                        and (p_payload -> 'consent_to_marketing') = 'true'::jsonb, false);

  -- UTM: a string is trimmed, stripped of control characters and cut to
  -- 200; anything else is dropped. Never refused (TCS OS parity).
  foreach v_key in array array['utm_source', 'utm_medium', 'utm_campaign'] loop
    v_i := v_i + 1;
    if jsonb_typeof(p_payload -> v_key) = 'string' then
      v_utm[v_i] := nullif(left(btrim(regexp_replace(p_payload ->> v_key, '[[:cntrl:]]', '', 'g')), 200), '');
    end if;
  end loop;

  insert into public.admissions_leads
    (name, email, phone, grade_interest, source, consent_to_marketing, utm_source, utm_medium, utm_campaign)
  values (v_name, v_email, nullif(v_phone, ''), nullif(v_grade, ''), p_source, v_consent,
          v_utm[1], v_utm[2], v_utm[3])
  returning id into v_id;

  perform public._enqueue_lead_emails(v_id);
  return true;
end;
$$;

-- ------------------------------------------------------------ worker

-- Re-created from 20261027120000. Unchanged up to the claim; the claim now
-- takes every other kind first, then lead mail, and lead mail only while
-- lead emails sent or being sent in 24 hours stay under half the daily
-- ceiling. A burst of PDF requests can't starve application mail. Same
-- signature and grants (service role only).
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
  v_lead_used integer;
  v_lead_room integer;
  v_claimed integer;
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

  select count(*), count(*) filter (where o.kind in ('pdf_gate', 'lead_staff'))
    into v_used, v_lead_used
  from public.admissions_email_outbox o
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
    where ((o.status = 'pending' and o.next_attempt_at <= clock_timestamp())
           or (o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes'))
      and o.kind not in ('pdf_gate', 'lead_staff')
    order by o.next_attempt_at, o.created_at
    limit v_room
    for update skip locked
  )
  update public.admissions_email_outbox o
  set status = 'sending', claim_token = gen_random_uuid(), claimed_at = clock_timestamp(),
      attempts = o.attempts + 1
  from c where o.id = c.id
  returning o.id, o.kind, o.recipient_email, o.params, o.claim_token, o.attempts;
  get diagnostics v_claimed = row_count;

  v_lead_room := least(v_room - v_claimed, p_daily_ceiling / 2 - v_lead_used);
  if v_lead_room <= 0 then
    -- Lead mail held back by its half of the ceiling shows on the staff
    -- health strip like the full ceiling does, instead of waiting silently
    -- until it expires.
    if p_daily_ceiling / 2 - v_lead_used <= 0 and exists (
         select 1 from public.admissions_email_outbox o
         where o.status = 'pending' and o.next_attempt_at <= clock_timestamp()
           and o.kind in ('pdf_gate', 'lead_staff')) then
      update public.admissions_email_worker w set ceiling_reached_at = clock_timestamp() where w.id;
    end if;
    return;
  end if;

  return query
  with c as (
    select o.id from public.admissions_email_outbox o
    where ((o.status = 'pending' and o.next_attempt_at <= clock_timestamp())
           or (o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes'))
      and o.kind in ('pdf_gate', 'lead_staff')
    order by o.next_attempt_at, o.created_at
    limit v_lead_room
    for update skip locked
  )
  update public.admissions_email_outbox o
  set status = 'sending', claim_token = gen_random_uuid(), claimed_at = clock_timestamp(),
      attempts = o.attempts + 1
  from c where o.id = c.id
  returning o.id, o.kind, o.recipient_email, o.params, o.claim_token, o.attempts;
end;
$$;

-- What the staff alert shows (D-13g): the grade of interest, the consent
-- answer, the source and the lead's id for the ERP link. No name, email or
-- phone. Only for a lead_staff row the caller still holds a claim on;
-- null otherwise.
create or replace function public.get_lead_alert(p_outbox_id uuid, p_claim_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  perform public._require_public_service_caller();
  if p_outbox_id is null or p_claim_token is null then
    return null;
  end if;
  select jsonb_build_object(
           'lead_id', l.id,
           'grade_interest', l.grade_interest,
           'consent_to_marketing', l.consent_to_marketing,
           'source', l.source)
    into v_result
  from public.admissions_email_outbox o
  join public.admissions_leads l on l.id = o.lead_id
  where o.id = p_outbox_id and o.kind = 'lead_staff' and o.status = 'sending'
    and o.claim_token = p_claim_token;
  return v_result;
end;
$$;

-- ------------------------------------------------------------ staff list

-- Newest first, at most 500 a page. p_lead_id shows one lead (the staff
-- alert's link). Manager and Admissions Officer see every field (D-13h, no
-- grade band scope: the grade of interest is mostly blank free text);
-- Auditor sees email and phone masked. Every other role is refused.
create or replace function public.list_admissions_leads(
  p_limit integer default 200,
  p_offset integer default 0,
  p_lead_id uuid default null
)
returns table (
  id uuid,
  created_at timestamptz,
  name text,
  email text,
  phone text,
  grade_interest text,
  source text,
  consent_to_marketing boolean,
  bulk_email_unsubscribed_at timestamptz,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_full boolean;
begin
  if not public.has_role(array['Manager', 'Admissions Officer', 'Auditor']) then
    raise exception 'Only a Manager, Admissions Officer or Auditor can see leads';
  end if;
  v_full := public.has_role(array['Manager', 'Admissions Officer']);
  return query
  select l.id, l.created_at, l.name,
         case when v_full then l.email else public._admissions_mask_email(l.email) end,
         case when v_full then l.phone else public._admissions_mask_phone(l.phone) end,
         l.grade_interest, l.source, l.consent_to_marketing, l.bulk_email_unsubscribed_at,
         l.utm_source, l.utm_medium, l.utm_campaign,
         count(*) over ()
  from public.admissions_leads l
  where p_lead_id is null or l.id = p_lead_id
  order by l.created_at desc, l.id
  limit greatest(1, least(coalesce(p_limit, 200), 500))
  offset greatest(0, coalesce(p_offset, 0));
end;
$$;

-- ------------------------------------------------------------ housekeeping

-- Re-created from 20261028100000. Every existing step and key is
-- unchanged. Added last, leads_deleted (D-13l): leads without consent 12
-- months after capture, with consent 24 months after capture, and any
-- unsubscribed lead, except one with an email being sent (next run).
-- Their outbox rows go with them (cascade).
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
  v_draft_emails integer;
  v_wiped integer;
  v_drafts integer;
  v_leads integer;
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
  where o.kind = 'draft_resume' and o.created_at < clock_timestamp() - interval '7 days';
  get diagnostics v_draft_emails = row_count;

  delete from public.admissions_email_outbox o
  where (o.status = 'sent' and o.created_at < clock_timestamp() - interval '90 days')
     or (o.status in ('failed', 'suppressed', 'expired') and o.created_at < clock_timestamp() - interval '180 days');
  get diagnostics v_emails = row_count;

  delete from cron.job_run_details d where d.end_time < clock_timestamp() - interval '7 days';
  get diagnostics v_runs = row_count;

  delete from public.admissions_email_outbox o
  using public.application_drafts d
  where o.draft_id = d.id and o.status <> 'sending'
    and d.submitted_at is null and d.expires_at <= clock_timestamp() and d.email is not null;
  get diagnostics v_wiped = row_count;
  v_draft_emails := v_draft_emails + v_wiped;

  update public.application_drafts d
  set data = '{}'::jsonb, email = null
  where d.submitted_at is null and d.expires_at <= clock_timestamp()
    and (d.email is not null or d.data <> '{}'::jsonb);
  get diagnostics v_wiped = row_count;

  delete from public.application_drafts d
  where coalesce(d.submitted_at, d.expires_at) < clock_timestamp() - interval '30 days';
  get diagnostics v_drafts = row_count;

  -- A lead whose email is being sent right now waits for the next run, so
  -- the worker never loses the row it holds a claim on.
  delete from public.admissions_leads l
  using public._admissions_lead_retention() k
  where (l.bulk_email_unsubscribed_at is not null
         or (not l.consent_to_marketing and l.created_at < clock_timestamp() - k.without_consent)
         or (l.consent_to_marketing and l.created_at < clock_timestamp() - k.with_consent))
    and not exists (select 1 from public.admissions_email_outbox o
                    where o.lead_id = l.id and o.status = 'sending');
  get diagnostics v_leads = row_count;

  return jsonb_build_object(
    'reservations', v_reservations, 'sessions', v_sessions,
    'emails', v_emails, 'cron_runs', v_runs,
    'draft_emails', v_draft_emails, 'drafts_wiped', v_wiped, 'drafts_deleted', v_drafts,
    'leads_deleted', v_leads
  );
end;
$$;

-- ------------------------------------------------------------ grants

-- create or replace keeps the grants of _enqueue_admissions_emails
-- (nobody), claim_admissions_emails (service role only) and the purge
-- (nobody).
revoke execute on function public._enqueue_lead_emails(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.capture_lead(text, jsonb) from public, anon, authenticated;
grant execute on function public.capture_lead(text, jsonb) to service_role;
revoke execute on function public.get_lead_alert(uuid, uuid) from public, anon, authenticated;
grant execute on function public.get_lead_alert(uuid, uuid) to service_role;
revoke execute on function public.list_admissions_leads(integer, integer, uuid) from public, anon;
grant execute on function public.list_admissions_leads(integer, integer, uuid) to authenticated;
