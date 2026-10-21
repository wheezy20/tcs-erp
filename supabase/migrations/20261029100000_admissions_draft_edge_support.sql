-- Admissions slice 10, checkpoint C2: what the Edge Functions need from
-- the draft RPCs (docs/admissions/PORT-PLAN.md, slice 10; decided by Eyram
-- 2026-10-21).
--
-- 1. Limit refusals carry a DETAIL, so admissions-public maps them by code,
--    never by matching message text:
--      draft_limit        the live-draft caps (per address and across
--                         everyone). The page shows one generic message
--                         that never says drafts exist.
--      draft_email_limit  a resume email cap. The save is undone; the page
--                         keeps what the parent typed and offers to save
--                         again without the email.
--    create_application_draft and _enqueue_application_draft_email are
--    re-created with only the DETAIL added (same signatures and grants).
--
-- 2. issue_application_draft_link tells the worker what to do, in one
--    object, instead of a bare null:
--      {"status": "issued", "token", "expires_at"}  send it
--      {"status": "expired"}  the email is no longer needed (public
--                             applications are closed, or the draft has
--                             expired or been submitted). The row is
--                             already marked expired here, so it never
--                             counts as a failed resume email.
--      {"status": "failed"}   it can't be sent (the address differs from
--                             the draft's, or the backstop link cap is
--                             reached); the worker marks it failed.
--      null                   the caller doesn't hold this claim; the
--                             worker records nothing.
--    A second request for the same claim still raises, and the worker
--    counts that as a failed attempt. Same signature, so no drop; the
--    grants are unchanged (service_role only).
--
-- Nothing here widens a grant. The anon-executable count stays at 170.

-- ------------------------------------------------------------ DETAIL codes

-- Re-created from 20261028110000 with DETAIL 'draft_email_limit' added to
-- both refusals.
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
    raise exception using errcode = 'TCS29', detail = 'draft_email_limit',
      message = 'This link can''t be emailed again. Please call the school office and we''ll help you directly.';
  end if;

  select r.max_count, r.window_length into v_cap, v_window
  from public._public_rate_limit_rule('draft_email_recipient_day') r;
  select count(*) into v_n from public.admissions_email_outbox o
  where o.kind = 'draft_resume' and o.recipient_email = v_draft.email
    and o.created_at > clock_timestamp() - v_window;
  if v_n >= v_cap then
    raise exception using errcode = 'TCS29', detail = 'draft_email_limit',
      message = 'Too many emails have been sent to this address today. Please try again tomorrow or call the school office.';
  end if;

  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, draft_id)
  values ('draft:' || v_draft.id || ':' || (v_draft.resume_emails + 1), 'draft_resume', v_draft.email,
          '{}', '{}'::jsonb, v_draft.id);
  update public.application_drafts d set resume_emails = d.resume_emails + 1 where d.id = v_draft.id;
end;
$$;

-- Re-created from 20261028110000 with DETAIL 'draft_limit' added to both
-- live-draft refusals.
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
    raise exception using errcode = 'TCS29', detail = 'draft_limit',
      message = 'We could not save your application right now. Please contact the school office.';
  end if;

  -- Same wording as the global cap, so the refusal never reveals that an
  -- address has saved applications (decided 2026-10-21).
  perform pg_advisory_xact_lock(hashtextextended('admissions_email:' || v_email, 0));
  select r.max_count into v_cap from public._public_rate_limit_rule('draft_live_per_email') r;
  if (select count(*) from public.application_drafts d
      where d.email = v_email and d.submitted_at is null and d.expires_at > v_now) >= v_cap then
    raise exception using errcode = 'TCS29', detail = 'draft_limit',
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

-- ------------------------------------------------------------ the link

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

  -- No longer needed: final, and not a failure.
  if v_draft.id is null or v_draft.submitted_at is not null or v_draft.expires_at <= clock_timestamp()
     or not coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false) then
    update public.admissions_email_outbox o
    set status = 'expired', claim_token = null, claimed_at = null
    where o.id = v_row.id;
    return jsonb_build_object('status', 'expired');
  end if;

  if v_draft.email is distinct from v_row.recipient_email then
    return jsonb_build_object('status', 'failed');
  end if;
  v_token := public._application_draft_new_link(v_draft.id, p_claim_token);
  if v_token is null then
    return jsonb_build_object('status', 'failed');
  end if;
  return jsonb_build_object('status', 'issued', 'token', v_token, 'expires_at', v_draft.expires_at);
end;
$$;
