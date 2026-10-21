-- Admissions slice 10, migration 2 of 2: the saved application RPCs
-- (docs/admissions/PORT-PLAN.md, slice 10; plan approved by Eyram
-- 2026-10-21).
--
-- Every function here is service_role only and starts with
-- _require_public_service_caller(). The admissions-public Edge Function
-- calls them after its origin, size and IP limit checks (and Turnstile
-- for create), passing tokens in the POST body, never in a URL. No draft
-- function is callable by anon, so the anon-executable count stays at 170.
--
--   create_application_draft(email, state, step, consent)
--     returns {token, expires_at, version, email_masked}; queues the first
--     resume email in the same transaction.
--   get_application_draft(token)
--     returns {state, step, version, expires_at, email_masked}.
--   save_application_draft(token, state, step, expected_version, send_email)
--     returns {version, expires_at, email_queued, email_masked}.
--   delete_application_draft(token)
--     the parent's own erasure: the row, its links and its queued emails go.
--   issue_application_draft_link(outbox_id, claim_token)
--     the worker, between claim and send: mints a fresh token for a claimed
--     resume email, stores only its hash, returns it once.
--   submit_application_from_draft(payload, session_token, sniffed, draft_token)
--     submit_application, unchanged, plus the draft retired and wiped in the
--     same transaction.
--
-- Refusals (TCS22, the message is safe to show; DETAIL names the case so
-- the Edge Function and the page can act on it):
--   draft_invalid    the token opens nothing
--   draft_expired    the draft has expired
--   draft_submitted  the draft was already submitted
--   draft_version    the draft was saved from another window since
--   draft_state      the form state is not accepted (shape or size)
--   email, consent   the create panel's fields
-- TCS03 while public applications are closed (except delete), TCS29 for a
-- limit (the message says what to do).
--
-- Lock order: a draft row first, then the address lock
-- ('admissions_email:<address>', the same key _enqueue_admissions_emails
-- takes), then whatever submit_application takes. Create takes the global
-- draft lock before the address lock. Nothing takes them the other way.

-- ------------------------------------------------------------ helpers

-- The draft a raw token opens, or null. No lock.
create or replace function public._application_draft_id(p_token text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select l.draft_id from public.application_draft_links l
  where p_token is not null and p_token ~ '^[0-9a-f]{64}$'
    and l.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
$$;

-- Raises the right refusal for a draft that can't be used: unknown,
-- submitted or expired.
create or replace function public._application_draft_usable(p_draft public.application_drafts)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_draft.id is null then
    raise exception using errcode = 'TCS22', detail = 'draft_invalid',
      message = 'This saved application link is not valid. Please check the link or start a new application.';
  end if;
  if p_draft.submitted_at is not null then
    raise exception using errcode = 'TCS22', detail = 'draft_submitted',
      message = 'This application has already been submitted.';
  end if;
  if p_draft.expires_at <= clock_timestamp() then
    raise exception using errcode = 'TCS22', detail = 'draft_expired',
      message = 'This saved application has expired. Please start a new one.';
  end if;
end;
$$;

-- Refuses a form state the draft may not hold.
create or replace function public._application_draft_check_state(p_state jsonb, p_step integer)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if not public._application_draft_state_ok(p_state)
     or octet_length(p_state::text) > (public._application_draft_lifetime()).max_bytes then
    raise exception using errcode = 'TCS22', detail = 'draft_state',
      message = 'This form could not be saved. Please reload the page and try again.';
  end if;
  if p_step is null or p_step not between 0 and 5 then
    raise exception using errcode = 'TCS22', detail = 'draft_state',
      message = 'This form could not be saved. Please reload the page and try again.';
  end if;
end;
$$;

-- Refuses while public applications are closed (no dual intake).
create or replace function public._application_draft_require_open()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false) then
    raise exception using errcode = 'TCS03', message = 'Public applications are closed';
  end if;
end;
$$;

-- Queues one resume email for a draft the caller holds locked, after the
-- two email caps (per address per day, which also caps the draft, and per
-- draft ever). Refuses (TCS29) rather than suppressing: a parent with
-- no link would otherwise lose their work without knowing (decided
-- 2026-10-21). Takes the address lock, so the per-address count is exact.
create or replace function public._enqueue_application_draft_email(p_draft_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draft public.application_drafts;
  v_cap integer;
  v_window interval;
  v_n integer;
begin
  select * into v_draft from public.application_drafts d where d.id = p_draft_id;
  if v_draft.email is null then
    raise exception 'A draft without an email can''t be emailed';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('admissions_email:' || v_draft.email, 0));

  select r.max_count into v_cap from public._public_rate_limit_rule('draft_email_per_draft_total') r;
  if v_draft.resume_emails >= v_cap then
    raise exception using errcode = 'TCS29',
      message = 'This link can''t be emailed again. Please call the school office and we''ll help you directly.';
  end if;

  select r.max_count, r.window_length into v_cap, v_window
  from public._public_rate_limit_rule('draft_email_recipient_day') r;
  select count(*) into v_n from public.admissions_email_outbox o
  where o.kind = 'draft_resume' and o.recipient_email = v_draft.email
    and o.created_at > clock_timestamp() - v_window;
  if v_n >= v_cap then
    raise exception using errcode = 'TCS29',
      message = 'Too many emails have been sent to this address today. Please try again tomorrow or call the school office.';
  end if;

  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, draft_id)
  values ('draft:' || v_draft.id || ':' || (v_draft.resume_emails + 1), 'draft_resume', v_draft.email,
          '{}', '{}'::jsonb, v_draft.id);
  update public.application_drafts d set resume_emails = d.resume_emails + 1 where d.id = v_draft.id;
end;
$$;

-- A fresh 256-bit token for a draft: the hash is stored, the token returned.
create or replace function public._application_draft_new_link(p_draft_id uuid, p_claim uuid)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_cap integer;
  v_token text;
begin
  select r.max_count into v_cap from public._public_rate_limit_rule('draft_links') r;
  if (select count(*) from public.application_draft_links l where l.draft_id = p_draft_id) >= v_cap then
    return null;
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.application_draft_links (draft_id, token_hash, issued_for_claim)
  values (p_draft_id, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), p_claim);
  return v_token;
end;
$$;

-- ------------------------------------------------------------ the RPCs

create or replace function public.create_application_draft(
  p_email text, p_state jsonb, p_step integer, p_consent boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_cap integer;
  v_now timestamptz := clock_timestamp();
  v_draft public.application_drafts;
  v_token text;
begin
  perform public._require_public_service_caller();
  perform public._application_draft_require_open();

  if p_consent is not true then
    raise exception using errcode = 'TCS22', detail = 'consent',
      message = 'Please tick the box to agree before saving.';
  end if;
  v_email := lower(btrim(coalesce(p_email, '')));
  if char_length(v_email) > 254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception using errcode = 'TCS22', detail = 'email', message = 'Enter a valid email address.';
  end if;
  perform public._application_draft_check_state(p_state, p_step);

  -- Live drafts across everyone, under one lock held to commit, so two
  -- creates can't both take the last place.
  perform pg_advisory_xact_lock(hashtext('public.application_drafts'));
  select r.max_count into v_cap from public._public_rate_limit_rule('draft_live') r;
  if (select count(*) from public.application_drafts d
      where d.submitted_at is null and d.expires_at > v_now) >= v_cap then
    raise exception using errcode = 'TCS29',
      message = 'We could not save your application right now. Please contact the school office.';
  end if;

  -- Same wording as the global cap, so the refusal never reveals that an
  -- address has saved applications (decided 2026-10-21).
  perform pg_advisory_xact_lock(hashtextextended('admissions_email:' || v_email, 0));
  select r.max_count into v_cap from public._public_rate_limit_rule('draft_live_per_email') r;
  if (select count(*) from public.application_drafts d
      where d.email = v_email and d.submitted_at is null and d.expires_at > v_now) >= v_cap then
    raise exception using errcode = 'TCS29',
      message = 'We could not save your application right now. Please contact the school office.';
  end if;

  insert into public.application_drafts (email, data, current_step, consented_at, created_at, updated_at, expires_at)
  values (v_email, p_state, p_step, v_now, v_now, v_now, v_now + (public._application_draft_lifetime()).sliding)
  returning * into v_draft;

  v_token := public._application_draft_new_link(v_draft.id, null);
  perform public._enqueue_application_draft_email(v_draft.id);

  return jsonb_build_object(
    'token', v_token, 'expires_at', v_draft.expires_at, 'version', v_draft.version,
    'email_masked', public._admissions_mask_email(v_draft.email));
end;
$$;

create or replace function public.get_application_draft(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_draft public.application_drafts;
begin
  perform public._require_public_service_caller();
  perform public._application_draft_require_open();
  select * into v_draft from public.application_drafts d where d.id = public._application_draft_id(p_token);
  perform public._application_draft_usable(v_draft);
  return jsonb_build_object(
    'state', v_draft.data, 'step', v_draft.current_step, 'version', v_draft.version,
    'expires_at', v_draft.expires_at, 'email_masked', public._admissions_mask_email(v_draft.email));
end;
$$;

create or replace function public.save_application_draft(
  p_token text, p_state jsonb, p_step integer, p_expected_version integer, p_send_email boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_draft public.application_drafts;
  v_now timestamptz := clock_timestamp();
begin
  perform public._require_public_service_caller();
  perform public._application_draft_require_open();
  select * into v_draft from public.application_drafts d
  where d.id = public._application_draft_id(p_token)
  for update;
  perform public._application_draft_usable(v_draft);
  if p_expected_version is distinct from v_draft.version then
    raise exception using errcode = 'TCS22', detail = 'draft_version',
      message = 'This application was saved from another window. Please reload the page to see the latest version.';
  end if;
  perform public._application_draft_check_state(p_state, p_step);

  update public.application_drafts d
  set data = p_state, current_step = p_step, version = d.version + 1, updated_at = v_now,
      expires_at = least(v_now + (public._application_draft_lifetime()).sliding,
                         d.created_at + (public._application_draft_lifetime()).ceiling)
  where d.id = v_draft.id
  returning * into v_draft;

  if p_send_email is true then
    perform public._enqueue_application_draft_email(v_draft.id);
  end if;

  return jsonb_build_object(
    'version', v_draft.version, 'expires_at', v_draft.expires_at,
    'email_queued', coalesce(p_send_email, false),
    'email_masked', public._admissions_mask_email(v_draft.email));
end;
$$;

-- Works while public applications are closed: erasure is always allowed.
-- A submitted draft holds nothing any more, so deleting it just succeeds.
create or replace function public.delete_application_draft(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public._require_public_service_caller();
  select d.id into v_id from public.application_drafts d
  where d.id = public._application_draft_id(p_token)
  for update;
  if v_id is null then
    raise exception using errcode = 'TCS22', detail = 'draft_invalid',
      message = 'This saved application link is not valid. Please check the link or start a new application.';
  end if;
  delete from public.application_drafts d where d.id = v_id;
  return true;
end;
$$;

-- The worker calls this after claiming a draft_resume row and before
-- sending it. Only while it holds the claim; one link per claim. Null when
-- the email must not go (the draft is gone, expired or submitted, public
-- applications are closed, or the backstop link cap is reached): the worker then
-- fails the row without sending.
create or replace function public.issue_application_draft_link(p_outbox_id uuid, p_claim_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.admissions_email_outbox;
  v_draft public.application_drafts;
  v_token text;
begin
  perform public._require_public_service_caller();
  if p_outbox_id is null or p_claim_token is null then
    return null;
  end if;
  -- The draft is locked before the outbox row, the order a delete takes
  -- (draft, then its outbox rows by cascade), so the two can't deadlock.
  select * into v_draft from public.application_drafts d
  where d.id = (select o.draft_id from public.admissions_email_outbox o where o.id = p_outbox_id)
  for update;
  select * into v_row from public.admissions_email_outbox o
  where o.id = p_outbox_id and o.kind = 'draft_resume' and o.status = 'sending'
    and o.claim_token = p_claim_token
  for update;
  if v_row.id is null then
    return null;
  end if;
  if exists (select 1 from public.application_draft_links l where l.issued_for_claim = p_claim_token) then
    raise exception 'A link was already issued for this claim';
  end if;

  if v_draft.id is null or v_draft.submitted_at is not null or v_draft.expires_at <= clock_timestamp()
     or v_draft.email is distinct from v_row.recipient_email
     or not coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false) then
    return null;
  end if;

  v_token := public._application_draft_new_link(v_draft.id, p_claim_token);
  if v_token is null then
    return null;
  end if;
  return jsonb_build_object('token', v_token, 'expires_at', v_draft.expires_at);
end;
$$;

-- The application action with a draft token. submit_application is called
-- unchanged, so the upload session, byte check, replay and match rules all
-- stand. A token that opens nothing, or an expired draft, never stops a
-- complete form: it is submitted as if there were no draft.
create or replace function public.submit_application_from_draft(
  p_payload jsonb, p_session_token text, p_sniffed jsonb, p_draft_token text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_draft public.application_drafts;
  v_session public.application_upload_sessions;
  v_ref text;
begin
  perform public._require_public_service_caller();

  select * into v_draft from public.application_drafts d
  where d.id = public._application_draft_id(p_draft_token)
  for update;

  if v_draft.id is null or (v_draft.submitted_at is null and v_draft.expires_at <= clock_timestamp()) then
    return public.submit_application(p_payload, p_session_token, p_sniffed);
  end if;

  if p_session_token is not null and p_session_token ~ '^[0-9a-f]{64}$' then
    select * into v_session from public.application_upload_sessions s
    where s.token_hash = encode(sha256(convert_to(p_session_token, 'UTF8')), 'hex');
  end if;

  if v_draft.submitted_at is not null then
    -- The same submit again (a double click or a retry): the same answer,
    -- nothing written. Any other session: a second window, refused.
    if v_session.submitted_application_id is not null
       and v_session.submitted_application_id = v_draft.submitted_application_id then
      return (select a.application_reference from public.applications a
              where a.id = v_draft.submitted_application_id);
    end if;
    raise exception using errcode = 'TCS22', detail = 'draft_submitted',
      message = 'This application has already been submitted.';
  end if;

  v_ref := public.submit_application(p_payload, p_session_token, p_sniffed);

  select * into v_session from public.application_upload_sessions s
  where s.token_hash = encode(sha256(convert_to(p_session_token, 'UTF8')), 'hex');
  update public.application_drafts d
  set submitted_at = clock_timestamp(), submitted_application_id = v_session.submitted_application_id,
      data = '{}'::jsonb, email = null, updated_at = clock_timestamp()
  where d.id = v_draft.id;
  -- Its resume emails are no longer needed, and hold the address. One
  -- being sent right now is left to the worker, whose link call returns
  -- null for a submitted draft.
  delete from public.admissions_email_outbox o where o.draft_id = v_draft.id and o.status <> 'sending';
  return v_ref;
end;
$$;

-- ------------------------------------------------------------ grants

revoke execute on function public._application_draft_id(text) from public, anon, authenticated, service_role;
revoke execute on function public._application_draft_usable(public.application_drafts) from public, anon, authenticated, service_role;
revoke execute on function public._application_draft_check_state(jsonb, integer) from public, anon, authenticated, service_role;
revoke execute on function public._application_draft_require_open() from public, anon, authenticated, service_role;
revoke execute on function public._enqueue_application_draft_email(uuid) from public, anon, authenticated, service_role;
revoke execute on function public._application_draft_new_link(uuid, uuid) from public, anon, authenticated, service_role;

revoke execute on function public.create_application_draft(text, jsonb, integer, boolean) from public, anon, authenticated;
revoke execute on function public.get_application_draft(text) from public, anon, authenticated;
revoke execute on function public.save_application_draft(text, jsonb, integer, integer, boolean) from public, anon, authenticated;
revoke execute on function public.delete_application_draft(text) from public, anon, authenticated;
revoke execute on function public.issue_application_draft_link(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.submit_application_from_draft(jsonb, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.create_application_draft(text, jsonb, integer, boolean) to service_role;
grant execute on function public.get_application_draft(text) to service_role;
grant execute on function public.save_application_draft(text, jsonb, integer, integer, boolean) to service_role;
grant execute on function public.delete_application_draft(text) to service_role;
grant execute on function public.issue_application_draft_link(uuid, uuid) to service_role;
grant execute on function public.submit_application_from_draft(jsonb, text, jsonb, text) to service_role;
