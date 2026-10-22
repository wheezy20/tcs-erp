-- Admissions slice 11, checkpoint C1, part 2 of 2: the offer functions
-- (docs/admissions/PORT-PLAN.md, "Slice 11 plan"; decided by Eyram
-- 2026-10-22).
--
-- Staff (authenticated; role and capability, then scope, then the locks
-- in the order application, decision, offer, then the re-checks):
--   generate_offer, reset_offer   re-created: no raw token any more (the
--                                 copy link is retired, D-11d); each
--                                 queues one offer email per guardian
--                                 address (D-11b, D-11c)
--   resend_offer_link             new: same offer and expiry, a new
--                                 generation, so every older link dies
--   record_offer_response         re-created: records the source (staff)
--   correct_offer_response        new (D-11j): changes a response given
--                                 through the link, with a reason
--   preview_offer_recipients      new: how many addresses a send would
--                                 email now, for the panel's confirm step
--   get_offer_email_status        new: the current links' emails, masked
--
-- Service role only (each starts with _require_public_service_caller):
--   get_offer_by_link             the page's read; writes nothing
--   respond_to_offer              the parent's answer, once
--   issue_offer_link              the worker's send-time mint
--
-- Also re-created: audit_application_offer (the parent's response and
-- every link send are audited, D-11i) and claim_admissions_emails (offer
-- kinds first and their own maximum age, D-11g, D-11h).
--
-- Stage effects of a correction (D-11j), stated here as Eyram asked:
--   accepted to declined  stage offer to offer_declined
--   declined to accepted  stage offer_declined to offer; the offer must
--                         still be in date
--   both                  refused once the application is enrolled, and
--                         when the decision is no longer accepted; only a
--                         response whose source is the offer link
--
-- Nothing here is granted to anon. The anon-executable count stays 170.

-- ------------------------------------------------------------ helpers

-- The guardian addresses for an offer (D-11b): every guardian of the
-- student's family with a usable email, lowercased, de-duplicated, at most
-- 4, in the order D-12h uses (by guardian id).
create or replace function public._offer_recipients(p_application_id uuid)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(x.e order by x.first_id), '{}')
  from (
    select lower(btrim(g.email)) as e, min(g.id::text) as first_id
    from public.applications a
    join public.students s on s.id = a.student_id
    join public.guardians g on g.family_id = s.family_id
    where a.id = p_application_id
      and lower(btrim(g.email)) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
      and char_length(btrim(g.email)) <= 254
    group by 1
    order by 2
    limit 4
  ) x;
$$;

-- Starts a new link generation and queues the offer emails for it. The
-- caller holds the application, decision and offer locks. In order: the
-- daily cap (only when something will be sent), the older generation's
-- waiting and failed emails expire, every live link is revoked, the
-- generation moves up (the audit trigger reads the send and the recipient
-- count from a transaction-local setting), then one row per address.
-- Returns how many emails were queued.
create or replace function public._offer_queue_send(p_offer_id uuid, p_send text)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_offer public.application_offers;
  v_app public.applications;
  v_recipients text[];
  v_cap integer;
  v_window interval;
  v_sends integer;
  v_email text;
begin
  select * into v_offer from public.application_offers o where o.id = p_offer_id;
  select * into v_app from public.applications a where a.id = v_offer.application_id;
  v_recipients := public._offer_recipients(v_app.id);

  if cardinality(v_recipients) > 0 then
    select r.max_count, r.window_length into v_cap, v_window
    from public._public_rate_limit_rule('offer_links_day') r;
    select count(distinct o.event_key) into v_sends
    from public.admissions_email_outbox o
    where o.offer_id = p_offer_id and o.kind = 'offer' and o.created_at > clock_timestamp() - v_window;
    if v_sends >= v_cap then
      raise exception using detail = 'offer_link_limit',
        message = 'This offer''s link has already been sent ' || v_cap
                  || ' times in the last 24 hours. Try again tomorrow, or contact the family by phone.';
    end if;
  end if;

  update public.admissions_email_outbox o
  set status = 'expired', claim_token = null, claimed_at = null
  where o.offer_id = p_offer_id and o.kind = 'offer' and o.status in ('pending', 'failed');

  update public.application_offer_links l
  set revoked_at = clock_timestamp()
  where l.offer_id = p_offer_id and l.revoked_at is null;

  perform set_config('tcs.offer_link_send',
    jsonb_build_object('send', p_send, 'recipients', cardinality(v_recipients))::text, true);
  update public.application_offers o
  set link_generation = o.link_generation + 1
  where o.id = p_offer_id
  returning * into v_offer;
  perform set_config('tcs.offer_link_send', '', true);

  foreach v_email in array v_recipients loop
    insert into public.admissions_email_outbox
      (event_key, kind, recipient_email, application_ids, params, offer_id)
    values (
      'offer:' || v_offer.id || ':' || v_offer.link_generation, 'offer', v_email, array[v_app.id],
      jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
        'reference', v_app.application_reference,
        'grade', v_app.year_group_applied_for,
        'academic_year', v_app.academic_year))),
      v_offer.id
    );
  end loop;
  return cardinality(v_recipients);
end;
$$;

-- The offer a token opens, or null. A token opens an offer only through an
-- unrevoked link of the offer's current generation.
create or replace function public._offer_id_by_link(p_token text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select l.offer_id
  from public.application_offer_links l
  join public.application_offers o on o.id = l.offer_id
  where p_token ~ '^[0-9a-f]{64}$'
    and l.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and l.revoked_at is null
    and l.generation = o.link_generation;
$$;

-- ------------------------------------------------------------ staff RPCs

-- Re-created from 20261016100000. The checks are unchanged. No token is
-- minted or returned (D-11d); the offer emails are queued instead.
create or replace function public.generate_offer(p_application_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_decision public.application_decisions;
  v_ttl integer;
  v_sent timestamptz;
  v_offer public.application_offers;
  v_queued integer;
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
  v_sent := clock_timestamp();
  insert into public.application_offers (application_id, sent_at, expires_at, response)
  values (p_application_id, v_sent, v_sent + make_interval(days => v_ttl), 'pending')
  returning * into v_offer;

  update public.applications set stage = 'offer' where id = p_application_id
  returning * into v_app;

  v_queued := public._offer_queue_send(v_offer.id, 'generate');

  return jsonb_build_object(
    'sent_at', v_offer.sent_at,
    'expires_at', v_offer.expires_at,
    'stage', v_app.stage,
    'emails_queued', v_queued
  );
end;
$$;

-- Re-created from 20261016100000. The checks are unchanged. A new
-- generation replaces the links (so every old link finds nothing, D-6b),
-- the offer starts again pending with a fresh expiry, and the offer emails
-- are queued. With no guardian address nothing is sent, but the old links
-- still die.
create or replace function public.reset_offer(p_application_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
  v_ttl integer;
  v_sent timestamptz;
  v_queued integer;
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
  v_sent := clock_timestamp();
  update public.application_offers
  set token_hash = null,
      sent_at = v_sent,
      expires_at = v_sent + make_interval(days => v_ttl),
      response = 'pending',
      responded_at = null,
      response_source = null
  where id = v_offer.id
  returning * into v_offer;

  if v_app.stage <> 'offer' then
    update public.applications set stage = 'offer' where id = p_application_id
    returning * into v_app;
  end if;

  v_queued := public._offer_queue_send(v_offer.id, 'reset');

  return jsonb_build_object(
    'sent_at', v_offer.sent_at,
    'expires_at', v_offer.expires_at,
    'stage', v_app.stage,
    'emails_queued', v_queued
  );
end;
$$;

-- Sends the link again for an open offer: the same offer and expiry, a new
-- generation, so every earlier link stops working. Refused unless the
-- offer is pending and in date at stage offer with the decision accepted,
-- and when no guardian has an email address.
create or replace function public.resend_offer_link(p_application_id uuid)
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
  v_queued integer;
begin
  perform public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage <> 'offer' then
    raise exception 'The offer link can''t be sent while the application is at %', v_app.stage;
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
  if cardinality(public._offer_recipients(p_application_id)) = 0 then
    raise exception 'No guardian on this application has an email address';
  end if;

  v_queued := public._offer_queue_send(v_offer.id, 'resend');
  select * into v_offer from public.application_offers where id = v_offer.id;

  return jsonb_build_object(
    'expires_at', v_offer.expires_at,
    'emails_queued', v_queued
  );
end;
$$;

-- How many addresses a send would email right now (D-11c confirm step).
-- The same checks as the send RPCs up to scope; no lock, writes nothing.
create or replace function public.preview_offer_recipients(p_application_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_grade text;
begin
  perform public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select year_group_applied_for into v_grade from public.applications where id = p_application_id;
  if not found or not public.admissions_grade_visible(v_grade) then
    raise exception 'Application not found';
  end if;
  return cardinality(public._offer_recipients(p_application_id));
end;
$$;

-- Re-created from 20261016100000 with one change: the response source is
-- recorded as staff.
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

  update public.application_offers
  set response = p_response, responded_at = clock_timestamp(), response_source = 'staff'
  where id = v_offer.id;

  if p_response = 'declined' then
    update public.applications set stage = 'offer_declined' where id = p_application_id
    returning * into v_app;
  end if;

  return jsonb_build_object('response', p_response, 'stage', v_app.stage);
end;
$$;

-- Corrects a response the parent gave through the offer link (D-11j). The
-- reason (1 to 300 characters, no control characters) goes into the audit
-- row with both sources. Stage effects are in the header of this file.
create or replace function public.correct_offer_response(
  p_application_id uuid,
  p_response text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  perform public._require_admissions_decider();
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  if p_response is null or p_response not in ('accepted', 'declined') then
    raise exception 'An offer response must be accepted or declined';
  end if;
  if char_length(v_reason) not between 1 and 300 or v_reason ~ '[[:cntrl:]]' then
    raise exception 'Give a short reason for the correction (at most 300 characters, on one line)';
  end if;
  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage = 'enrolled' then
    raise exception 'An offer response can''t be corrected once the application is enrolled';
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
  if v_offer.response not in ('accepted', 'declined') or v_offer.response_source is distinct from 'offer_link' then
    raise exception 'Only a response the parent gave through the offer link can be corrected';
  end if;
  if v_offer.response = p_response then
    raise exception 'The offer is already %', p_response;
  end if;
  if p_response = 'declined' and v_app.stage <> 'offer' then
    raise exception 'The response can''t be corrected while the application is at %', v_app.stage;
  end if;
  if p_response = 'accepted' then
    if v_app.stage <> 'offer_declined' then
      raise exception 'The response can''t be corrected while the application is at %', v_app.stage;
    end if;
    if v_offer.expires_at is not null and v_offer.expires_at <= clock_timestamp() then
      raise exception 'The offer''s respond-by date has passed; reset the offer instead';
    end if;
  end if;

  perform set_config('tcs.offer_correction',
    jsonb_build_object('reason', v_reason, 'source_before', v_offer.response_source)::text, true);
  update public.application_offers
  set response = p_response, responded_at = clock_timestamp(), response_source = 'staff'
  where id = v_offer.id;
  perform set_config('tcs.offer_correction', '', true);

  update public.applications
  set stage = case when p_response = 'declined' then 'offer_declined' else 'offer' end
  where id = p_application_id
  returning * into v_app;

  return jsonb_build_object('response', p_response, 'stage', v_app.stage);
end;
$$;

-- The current generation's offer emails for one application, addresses
-- masked. Readable by whoever the offers select policy lets see the offer:
-- Manager, Auditor, and an Admissions Officer with the decide capability
-- and the application in scope.
create or replace function public.get_offer_email_status(p_application_id uuid)
returns table (
  recipient_masked text,
  status text,
  attempts integer,
  created_at timestamptz,
  sent_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_application_id is null
     or not (public.has_role(array['Manager', 'Auditor'])
             or (public.has_role(array['Admissions Officer']) and public.has_admissions_capability('decide')))
     or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  return query
  select public._admissions_mask_email(e.recipient_email), e.status, e.attempts, e.created_at, e.sent_at
  from public.application_offers o
  join public.admissions_email_outbox e
    on e.offer_id = o.id and e.kind = 'offer'
   and e.event_key = 'offer:' || o.id || ':' || o.link_generation
  where o.application_id = p_application_id
  order by e.created_at, e.id;
end;
$$;

-- ------------------------------------------------------------ service RPCs

-- The page's read (D-11a, D-11f). Writes nothing, takes no lock.
--   {"state": "open", "first_name", "grade", "academic_year", "campus",
--    "respond_by"}   pending, in date, at stage offer, decision accepted
--   {"state": "answered", "response"}   accepted or declined
--   null             anything else: unknown, malformed, revoked or older
--                    link, expired, withdrawn
-- The first name is the first word of the full name as typed (students
-- hold only full_name).
create or replace function public.get_offer_by_link(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_offer public.application_offers;
  v_app public.applications;
  v_decision text;
  v_first text;
  v_campus text;
begin
  perform public._require_public_service_caller();
  select * into v_offer from public.application_offers where id = public._offer_id_by_link(p_token);
  if not found then
    return null;
  end if;
  if v_offer.response in ('accepted', 'declined') then
    return jsonb_build_object('state', 'answered', 'response', v_offer.response);
  end if;
  select * into v_app from public.applications where id = v_offer.application_id;
  select decision_type into v_decision from public.application_decisions where application_id = v_app.id;
  if public._offer_effective_response(v_offer.response, v_offer.expires_at) <> 'pending'
     or v_app.stage <> 'offer' or v_decision is distinct from 'accepted' then
    return null;
  end if;
  select split_part(regexp_replace(btrim(s.full_name), '\s+', ' ', 'g'), ' ', 1) into v_first
  from public.students s where s.id = v_app.student_id;
  select coalesce(b.public_label, b.name) into v_campus from public.branches b where b.id = v_app.branch_id;
  return jsonb_build_object(
    'state', 'open',
    'first_name', v_first,
    'grade', v_app.year_group_applied_for,
    'academic_year', v_app.academic_year,
    'campus', v_campus,
    'respond_by', v_offer.expires_at
  );
end;
$$;

-- The parent's answer through the link, given once. Locks in the order
-- every staff offer path uses (application, decision, offer), then re-reads
-- the link and re-checks everything under the locks, so a phone reply
-- recorded by staff, a resend, a withdrawal or the expiry sweep running at
-- the same moment can't be overridden.
--   {"status": "recorded", "response"}   written now
--   {"status": "answered", "response"}   the offer already has a response
--                                        (from either source); nothing
--                                        written
--   null                                 the link opens nothing
-- A decline moves the stage to offer_declined. The staff alert is queued
-- in the same transaction (D-11k).
create or replace function public.respond_to_offer(p_token text, p_response text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer_id uuid;
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
begin
  perform public._require_public_service_caller();
  if p_response is null or p_response not in ('accepted', 'declined') then
    raise exception 'An offer response must be accepted or declined';
  end if;
  v_offer_id := public._offer_id_by_link(p_token);
  if v_offer_id is null then
    return null;
  end if;

  select a.* into v_app from public.applications a
  where a.id = (select o.application_id from public.application_offers o where o.id = v_offer_id)
  for update;
  select * into v_decision from public.application_decisions where application_id = v_app.id for update;
  select * into v_offer from public.application_offers where id = v_offer_id for update;
  if public._offer_id_by_link(p_token) is distinct from v_offer_id then
    return null;
  end if;
  if v_offer.response in ('accepted', 'declined') then
    return jsonb_build_object('status', 'answered', 'response', v_offer.response);
  end if;
  if public._offer_effective_response(v_offer.response, v_offer.expires_at) <> 'pending'
     or v_app.stage <> 'offer' or v_decision.decision_type is distinct from 'accepted' then
    return null;
  end if;

  perform set_config('tcs.offer_link_response', 'on', true);
  update public.application_offers
  set response = p_response, responded_at = clock_timestamp(), response_source = 'offer_link'
  where id = v_offer.id
  returning * into v_offer;
  perform set_config('tcs.offer_link_response', '', true);

  if p_response = 'declined' then
    update public.applications set stage = 'offer_declined' where id = v_app.id
    returning * into v_app;
  end if;

  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, offer_id)
  values (
    'offer:' || v_offer.id || ':' || v_offer.link_generation, 'offer_staff', null, array[v_app.id],
    jsonb_build_object(
      'references', jsonb_build_array(jsonb_build_object(
        'reference', v_app.application_reference,
        'grade', v_app.year_group_applied_for,
        'academic_year', v_app.academic_year)),
      'application_id', v_app.id::text,
      'response', p_response),
    v_offer.id
  )
  on conflict on constraint admissions_email_outbox_event_unique do nothing;

  return jsonb_build_object('status', 'recorded', 'response', p_response);
end;
$$;

-- The worker's send-time link for an offer email it has claimed. Locks the
-- application, decision and offer (the staff order), then the outbox row.
--   {"status": "issued", "token", "expires_at"}  send it
--   {"status": "expired"}  no longer needed: a newer generation exists,
--                          the offer is no longer pending and in date, the
--                          stage or decision changed, or the email is past
--                          its maximum age (D-11g). The row is already
--                          marked expired.
--   null                   the caller doesn't hold this claim
-- A second request for the same claim raises (the worker counts a failed
-- attempt). A retry of the same row gets its own link; earlier links for
-- the same address stay valid within the generation.
create or replace function public.issue_offer_link(p_outbox_id uuid, p_claim_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_offer_id uuid;
  v_app public.applications;
  v_decision public.application_decisions;
  v_offer public.application_offers;
  v_row public.admissions_email_outbox;
  v_token text;
begin
  perform public._require_public_service_caller();
  if p_outbox_id is null or p_claim_token is null then
    return null;
  end if;
  select o.offer_id into v_offer_id from public.admissions_email_outbox o
  where o.id = p_outbox_id and o.kind = 'offer';
  if v_offer_id is null then
    return null;
  end if;
  select a.* into v_app from public.applications a
  where a.id = (select f.application_id from public.application_offers f where f.id = v_offer_id)
  for update;
  select * into v_decision from public.application_decisions where application_id = v_app.id for update;
  select * into v_offer from public.application_offers where id = v_offer_id for update;
  select * into v_row from public.admissions_email_outbox o
  where o.id = p_outbox_id and o.kind = 'offer' and o.status = 'sending' and o.claim_token = p_claim_token
  for update;
  if v_row.id is null then
    return null;
  end if;
  if exists (select 1 from public.application_offer_links l where l.issued_for_claim = p_claim_token) then
    raise exception 'A link was already issued for this claim';
  end if;

  if split_part(v_row.event_key, ':', 3)::integer <> v_offer.link_generation
     or public._offer_effective_response(v_offer.response, v_offer.expires_at) <> 'pending'
     or v_app.stage <> 'offer' or v_decision.decision_type is distinct from 'accepted'
     or coalesce(v_row.requeued_at, v_row.created_at) + public._admissions_offer_email_max_age() <= clock_timestamp() then
    update public.admissions_email_outbox o
    set status = 'expired', claim_token = null, claimed_at = null
    where o.id = v_row.id;
    return jsonb_build_object('status', 'expired');
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.application_offer_links (offer_id, token_hash, generation, outbox_id, issued_for_claim)
  values (v_offer.id, encode(digest(v_token, 'sha256'), 'hex'), v_offer.link_generation, v_row.id, p_claim_token);
  return jsonb_build_object('status', 'issued', 'token', v_token, 'expires_at', v_offer.expires_at);
end;
$$;

-- ------------------------------------------------------------ audit

-- Re-created from 20261016100000.
--   application_offer_changed  as before, for a signed-in actor, when the
--                              response, the expiry or the link generation
--                              changes; token_replaced now means a reset
--                              replaced the links. A correction
--                              (D-11j) adds corrected, reason,
--                              source_before and source_after.
--   application_offer_link_sent  a signed-in actor's generate, reset or
--                              resend that queued at least one email: the
--                              send, the recipient count, the generation
--                              and the reference. Never an address.
--   application_offer_responded  the parent's answer through the link,
--                              with no actor (D-11i). Written only when
--                              respond_to_offer has set its flag, so the
--                              expiry sweep still writes nothing.
-- No token or hash in any row.
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
  v_send jsonb;
  v_correction jsonb;
  v_after jsonb;
  v_generation_changed boolean :=
    tg_op = 'UPDATE' and old.link_generation is distinct from new.link_generation;
begin
  select a.application_reference, a.branch_id into v_reference, v_branch
  from public.applications a where a.id = new.application_id;

  if v_actor is null then
    if tg_op = 'UPDATE' and old.response is distinct from new.response
       and coalesce(current_setting('tcs.offer_link_response', true), '') = 'on' then
      v_branch := coalesce(v_branch, (select b.id from public.branches b order by b.created_at limit 1));
      if v_branch is null then return null; end if;
      insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
      values (
        v_branch, null, 'application_offer_responded', 'application_offers', new.id::text,
        jsonb_build_object('response', old.response),
        jsonb_build_object(
          'response', new.response,
          'source', 'offer_link',
          'generation', new.link_generation,
          'application_reference', v_reference)
      );
    end if;
    return null;
  end if;

  v_branch := coalesce(v_branch, (select branch_id from public.staff where id = v_actor));
  if v_branch is null then return null; end if;

  if tg_op = 'INSERT' or old.response is distinct from new.response
     or old.token_hash is distinct from new.token_hash
     or old.expires_at is distinct from new.expires_at then
    v_after := jsonb_build_object(
      'response', new.response,
      'expires_at', new.expires_at,
      -- A reset (the only update that sets a new sent_at) replaces the links.
      'token_replaced', tg_op = 'UPDATE' and (old.sent_at is distinct from new.sent_at
                                              or old.token_hash is distinct from new.token_hash),
      'application_reference', v_reference);
    v_correction := nullif(current_setting('tcs.offer_correction', true), '')::jsonb;
    if v_correction is not null and tg_op = 'UPDATE' and old.response is distinct from new.response then
      v_after := v_after || jsonb_build_object(
        'corrected', true,
        'reason', v_correction ->> 'reason',
        'source_before', v_correction ->> 'source_before',
        'source_after', new.response_source);
    end if;
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch, v_actor, 'application_offer_changed', 'application_offers', new.id::text,
      case when tg_op = 'UPDATE' then jsonb_build_object('response', old.response, 'expires_at', old.expires_at) end,
      v_after
    );
  end if;

  if v_generation_changed then
    v_send := nullif(current_setting('tcs.offer_link_send', true), '')::jsonb;
    if v_send is not null and coalesce((v_send ->> 'recipients')::integer, 0) > 0 then
      insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
      values (
        v_branch, v_actor, 'application_offer_link_sent', 'application_offers', new.id::text,
        null,
        jsonb_build_object(
          'send', v_send ->> 'send',
          'recipients', (v_send ->> 'recipients')::integer,
          'generation', new.link_generation,
          'expires_at', new.expires_at,
          'application_reference', v_reference)
      );
    end if;
  end if;
  return null;
end;
$$;

-- ------------------------------------------------------------ the claim

-- Re-created from 20261030110000 with two changes (D-11g, D-11h):
--   1. an offer email's maximum age is the earlier of 7 days from queueing
--      (or a Manager's retry) and its offer's expiry, instead of 48 hours;
--      offer_staff keeps 48 hours;
--   2. offer kinds are claimed first, ahead of the other non-lead kinds.
-- Lead mail is still claimed last within its half of the ceiling.
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

  -- Too old to send: a row waiting longer than its maximum age (counted
  -- from a Manager's retry when there is one) is expired, never sent. A
  -- lapsed lease counts as waiting.
  update public.admissions_email_outbox o
  set status = 'expired', claim_token = null, claimed_at = null
  where (o.status = 'pending'
         or (o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes'))
    and (
      (o.kind <> 'offer'
       and coalesce(o.requeued_at, o.created_at) < clock_timestamp() - public._admissions_email_max_age())
      or (o.kind = 'offer'
          and (coalesce(o.requeued_at, o.created_at) < clock_timestamp() - public._admissions_offer_email_max_age()
               or exists (select 1 from public.application_offers f
                          where f.id = o.offer_id and f.expires_at <= clock_timestamp())))
    );

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
    order by (o.kind in ('offer', 'offer_staff')) desc, o.next_attempt_at, o.created_at
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

-- ------------------------------------------------------------ grants

-- Helpers: no API role. Staff RPCs: authenticated and service_role, never
-- anon. Service RPCs: service_role only. Re-created functions keep their
-- grants (create or replace).
revoke execute on function public._offer_recipients(uuid) from public, anon, authenticated, service_role;
revoke execute on function public._offer_queue_send(uuid, text) from public, anon, authenticated, service_role;
revoke execute on function public._offer_id_by_link(text) from public, anon, authenticated, service_role;

revoke execute on function public.resend_offer_link(uuid) from public, anon;
revoke execute on function public.preview_offer_recipients(uuid) from public, anon;
revoke execute on function public.correct_offer_response(uuid, text, text) from public, anon;
revoke execute on function public.get_offer_email_status(uuid) from public, anon;
grant execute on function public.resend_offer_link(uuid) to authenticated, service_role;
grant execute on function public.preview_offer_recipients(uuid) to authenticated, service_role;
grant execute on function public.correct_offer_response(uuid, text, text) to authenticated, service_role;
grant execute on function public.get_offer_email_status(uuid) to authenticated, service_role;

revoke execute on function public.get_offer_by_link(text) from public, anon, authenticated;
revoke execute on function public.respond_to_offer(text, text) from public, anon, authenticated;
revoke execute on function public.issue_offer_link(uuid, uuid) from public, anon, authenticated;
grant execute on function public.get_offer_by_link(text) to service_role;
grant execute on function public.respond_to_offer(text, text) to service_role;
grant execute on function public.issue_offer_link(uuid, uuid) to service_role;
