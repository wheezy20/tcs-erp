-- Admissions slice 10, migration 1 of 2: saved applications ("Save and
-- finish later") for the public Application form, and the outbox changes
-- the resume email needs (docs/admissions/PORT-PLAN.md, slice 10; plan
-- approved by Eyram 2026-10-21 with D-10a to D-10l).
--
-- What a saved application is: the form's own state (the camelCase
-- ApplicationDraft the browser holds), not a submit payload. It is
-- checked only for shape and size here; every business rule is checked by
-- submit_application when the parent submits. It never holds:
--   health answers (neither the Yes/No answers nor the details, D-10d),
--   files or upload references (D-10c),
--   the declaration, the signature or media consent (D-10e).
-- Those keys are refused, at every level, by _application_draft_state_ok,
-- which is also a table check.
--
-- Credentials: every token that opens a draft is a row in
-- application_draft_links holding only the sha256 of the token. The raw
-- token is returned once (to the browser at create, or to the worker at
-- send time) and never stored. Links are equal and never rotate; at most 61
-- per draft (one per send attempt).
--
-- Lifetime (D-10a, D-10b): a draft lives 30 days from its last save,
-- never beyond 60 days from creation. The daily housekeeping job wipes the
-- data and the email of an expired draft, and deletes the row (and its
-- links) 30 days after it expired or was submitted. Resume email rows are
-- deleted after 7 days, whatever their status.
--
-- Staff see nothing: no API role has any privilege on either table, there
-- is no policy, and the staff outbox functions leave resume emails out.
-- The one trace is a count of failed resume emails in the email health
-- summary (decided 2026-10-21).
--
-- The draft RPCs are in migration 2. Everything here and there is
-- service_role only or callable by nobody; the anon-executable count stays
-- at 170.

-- ------------------------------------------------------------ the numbers

alter table public.public_rate_limits drop constraint public_rate_limits_bucket_check;
alter table public.public_rate_limits add constraint public_rate_limits_bucket_check
  check (bucket in ('submit_ip', 'submit_global', 'inquiry_email',
                    'application_email', 'upload_ip', 'upload_global',
                    'draft_ip', 'draft_global', 'draft_use_ip'));

-- Unchanged apart from the draft rows. Counted buckets (stored as hits):
--   draft_ip       10 saved applications started per hour per IP hash
--                  (before Turnstile)
--   draft_global   100 started per hour across everyone (after Turnstile)
--   draft_use_ip   60 saves, opens and deletes per hour per IP hash
-- Caps (never stored as hits; the table check refuses these names):
--   draft_live                   2,000 live drafts across everyone
--   draft_live_per_email         3 live drafts per email address
--   draft_links                  61 links per draft: the browser's link
--                                plus one per send attempt (10 emails, 6
--                                attempts each). A backstop that can never
--                                stop a real email.
--   draft_email_per_draft_total  10 resume emails per draft in its life
--                                (the window is the 60 day ceiling)
--   draft_email_recipient_day    3 resume emails per address in 24 hours,
--                                counted apart from email_recipient_day so
--                                resume emails can't use up a family's
--                                confirmation emails. A draft's
--                                email is fixed and its resume emails go
--                                only there, so this also caps each draft
--                                at 3 a day; a separate per-draft daily
--                                cap could never bind and is not kept.
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
    ('email_recipient_day', 4, interval '1 day'),
    ('draft_ip', 10, interval '1 hour'),
    ('draft_global', 100, interval '1 hour'),
    ('draft_use_ip', 60, interval '1 hour'),
    ('draft_live', 2000, interval '60 days'),
    ('draft_live_per_email', 3, interval '60 days'),
    ('draft_links', 61, interval '60 days'),
    ('draft_email_per_draft_total', 10, interval '60 days'),
    ('draft_email_recipient_day', 3, interval '1 day')
  ) as r (bucket, max_count, window_length)
  where r.bucket = p_bucket;
$$;

-- How long a draft lives (D-10a) and how big its state may be. One place,
-- so a change is a one-function migration. The frontend copy reads the
-- same numbers from a shared constant, checked by its test.
create or replace function public._application_draft_lifetime(
  out sliding interval,
  out ceiling interval,
  out max_bytes integer
)
language sql
immutable
set search_path = ''
as $$
  select interval '30 days', interval '60 days', 49152;
$$;

-- The Edge Function's entry point, now with the three draft buckets. The
-- IP buckets need the 64-character HMAC hex the function made; the global
-- ones take no key.
create or replace function public.check_public_rate_limit(p_bucket text, p_key_hash text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_public_service_caller();
  if p_bucket in ('submit_ip', 'upload_ip', 'draft_ip', 'draft_use_ip') then
    if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
      raise exception '% needs a 64-character lowercase hex key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, p_key_hash);
  elsif p_bucket in ('submit_global', 'upload_global', 'draft_global') then
    if p_key_hash is not null then
      raise exception '% takes no key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, 'global');
  end if;
  raise exception 'Unknown rate limit bucket: %', p_bucket;
end;
$$;

-- ------------------------------------------------------------ state check

-- True only for the form state a draft may hold: an object with the
-- listed keys, each nested object with its own listed keys, and every leaf
-- a string, a boolean or null. No health, documents, signature, agreement
-- or media consent key at any level. '{}' (a wiped draft) passes. Size is
-- checked by the RPCs and the table.
create or replace function public._application_draft_state_ok(p_state jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_g jsonb;
  v_leaf jsonb;
  v_t text;
begin
  if p_state is null or jsonb_typeof(p_state) <> 'object' then
    return false;
  end if;
  if (p_state - array['guardians', 'secondSameAddress', 'child', 'campusId', 'emergency',
                      'wantsScholarship', 'scholarshipDetails']) <> '{}'::jsonb then
    return false;
  end if;

  -- Top-level leaves.
  foreach v_t in array array['secondSameAddress', 'wantsScholarship'] loop
    if coalesce(jsonb_typeof(p_state -> v_t), 'null') not in ('boolean', 'null') then
      return false;
    end if;
  end loop;
  foreach v_t in array array['campusId', 'scholarshipDetails'] loop
    if coalesce(jsonb_typeof(p_state -> v_t), 'null') not in ('string', 'null') then
      return false;
    end if;
  end loop;

  -- Guardians: at most two, each with the guardian keys only.
  if p_state ? 'guardians' then
    if jsonb_typeof(p_state -> 'guardians') <> 'array' or jsonb_array_length(p_state -> 'guardians') > 2 then
      return false;
    end if;
    for v_g in select value from jsonb_array_elements(p_state -> 'guardians') loop
      if jsonb_typeof(v_g) <> 'object'
         or (v_g - array['surname', 'firstName', 'relationship', 'religion', 'address', 'townCity',
                         'phone', 'email']) <> '{}'::jsonb then
        return false;
      end if;
      for v_leaf in select value from jsonb_each(v_g) loop
        if jsonb_typeof(v_leaf) not in ('string', 'null') then
          return false;
        end if;
      end loop;
    end loop;
  end if;

  -- The child: the form's child keys only.
  if p_state ? 'child' then
    if jsonb_typeof(p_state -> 'child') <> 'object'
       or ((p_state -> 'child') - array['fullName', 'dateOfBirth', 'gender', 'nationality', 'sameAddress',
                                        'address', 'townCity', 'postalCode', 'country', 'currentGrade',
                                        'currentSchool', 'previousSchoolLocation', 'gradeId',
                                        'academicYear', 'month']) <> '{}'::jsonb then
      return false;
    end if;
    for v_leaf in select value from jsonb_each(p_state -> 'child') loop
      if jsonb_typeof(v_leaf) not in ('string', 'boolean', 'null') then
        return false;
      end if;
    end loop;
  end if;

  -- The emergency contact.
  if p_state ? 'emergency' then
    if jsonb_typeof(p_state -> 'emergency') <> 'object'
       or ((p_state -> 'emergency') - array['name', 'relationship', 'phone']) <> '{}'::jsonb then
      return false;
    end if;
    for v_leaf in select value from jsonb_each(p_state -> 'emergency') loop
      if jsonb_typeof(v_leaf) not in ('string', 'null') then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

-- ------------------------------------------------------------ tables

create table public.application_drafts (
  id uuid primary key default gen_random_uuid(),
  -- Where resume emails go. Fixed at create; null once wiped.
  email text check (
    email is null
    or (char_length(email) <= 254 and email = lower(email)
        and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
  ),
  data jsonb not null default '{}'::jsonb,
  current_step smallint not null default 0 check (current_step between 0 and 5),
  -- Raised by every save; a save naming an older version is refused, so
  -- two windows can't silently overwrite each other.
  version integer not null default 1 check (version >= 1),
  -- How many resume emails were queued for this draft, ever. Outbox rows
  -- are purged after 7 days, so the lifetime cap can't be counted from them.
  resume_emails integer not null default 0 check (resume_emails >= 0),
  consented_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  -- The state flag. Not the foreign key: deleting a test application sets
  -- that to null, and must not turn a submitted draft back into a live one.
  submitted_at timestamptz,
  submitted_application_id uuid references public.applications (id) on delete set null,
  constraint application_drafts_state_check check (public._application_draft_state_ok(data)),
  constraint application_drafts_size_check check (
    octet_length(data::text) <= (public._application_draft_lifetime()).max_bytes),
  constraint application_drafts_expiry_check check (expires_at > created_at),
  constraint application_drafts_submitted_check check (
    (submitted_application_id is null or submitted_at is not null)
    and (submitted_at is null or (data = '{}'::jsonb and email is null))
  ),
  constraint application_drafts_live_email_check check (
    email is not null or data = '{}'::jsonb
  )
);

create index application_drafts_email_idx on public.application_drafts (email) where email is not null;
create index application_drafts_expires_idx on public.application_drafts (expires_at);

alter table public.application_drafts enable row level security;
revoke all on table public.application_drafts from public, anon, authenticated, service_role;

create table public.application_draft_links (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.application_drafts (id) on delete cascade,
  -- sha256 hex of the raw token, which is returned once and never stored.
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  -- The outbox claim a link was minted for (null for the browser's own
  -- link). Unique, so one claim can mint at most one link.
  issued_for_claim uuid unique,
  created_at timestamptz not null default now()
);

create index application_draft_links_draft_id_idx on public.application_draft_links (draft_id);

alter table public.application_draft_links enable row level security;
revoke all on table public.application_draft_links from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ outbox

-- A resume email: kind draft_resume, one recipient (the draft's email), no
-- application, params exactly {}, and the draft it belongs to. The link is
-- minted by issue_application_draft_link (migration 2) when the worker
-- sends, so no row ever holds a token.
alter table public.admissions_email_outbox
  add column draft_id uuid references public.application_drafts (id) on delete cascade;

create index admissions_email_outbox_draft_id_idx on public.admissions_email_outbox (draft_id)
  where draft_id is not null;

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_kind_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_kind_check
  check (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff', 'draft_resume'));

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_event_key_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_event_key_check check (
  (kind <> 'draft_resume' and event_key ~ '^(inquiry|application):[0-9a-f-]{36}$')
  or (kind = 'draft_resume' and event_key ~ '^draft:[0-9a-f-]{36}:[0-9]{1,3}$')
);

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_application_ids_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_application_ids_check check (
  (kind <> 'draft_resume' and cardinality(application_ids) between 1 and 20)
  or (kind = 'draft_resume' and cardinality(application_ids) = 0)
);

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_recipient_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_recipient_check check (
  (kind like '%_parent' and recipient_email is not null)
  or (kind like '%_staff' and recipient_email is null)
  or (kind = 'draft_resume' and recipient_email is not null)
);

alter table public.admissions_email_outbox add constraint admissions_email_outbox_draft_check
  check ((kind = 'draft_resume') = (draft_id is not null));

-- Unchanged apart from the first branch: a resume email carries no params.
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
  if p_kind = 'draft_resume' then
    return p_params = '{}'::jsonb;
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

-- Re-created from 20261027100000 with one line added: resume emails don't
-- count toward the 4 confirmation emails per address per day. Same
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
      and o.kind <> 'draft_resume'
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

-- ------------------------------------------------------------ staff RPCs

-- Re-created from 20261027100000 with one predicate added: a resume email
-- can't be retried by staff. Same signature and grants.
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
  where o.id = any (p_ids) and o.status = 'failed' and o.kind <> 'draft_resume';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Re-created from 20261027120000 with one predicate added: resume emails
-- are left out, so staff never see who saved an application. Same
-- signature and grants.
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
  where (p_status is null or o.status = p_status) and o.kind <> 'draft_resume'
  order by o.created_at desc, o.id
  limit greatest(1, least(coalesce(p_limit, 200), 500));
end;
$$;

-- Re-created from 20261027120000: the four counts leave resume emails out,
-- and one count is added, draft_failed, the resume emails that failed
-- (decided 2026-10-21). A count only: no address, no draft. The config
-- flag still covers every row, so a missing resume link setting shows.
-- The return type changes, so it is dropped first; the grants are
-- restated below.
drop function public.get_admissions_email_health();

create or replace function public.get_admissions_email_health()
returns table (
  waiting integer,
  failed integer,
  suppressed integer,
  expired integer,
  draft_failed integer,
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
    (select count(*)::integer from public.admissions_email_outbox o
     where o.status in ('pending', 'sending') and o.kind <> 'draft_resume'),
    (select count(*)::integer from public.admissions_email_outbox o
     where o.status = 'failed' and o.kind <> 'draft_resume'),
    (select count(*)::integer from public.admissions_email_outbox o
     where o.status = 'suppressed' and o.kind <> 'draft_resume'),
    (select count(*)::integer from public.admissions_email_outbox o
     where o.status = 'expired' and o.kind <> 'draft_resume'),
    (select count(*)::integer from public.admissions_email_outbox o
     where o.status = 'failed' and o.kind = 'draft_resume'),
    w.last_run_at, w.last_success_at, w.ceiling_reached_at,
    exists (select 1 from public.admissions_email_outbox o
            where o.status in ('pending', 'failed') and o.last_error_class = 'config')
  from public.admissions_email_worker w where w.id;
end;
$$;

-- get_application_email_status needs no change: it reads only rows whose
-- kind ends in _parent and that name the application, and a resume email
-- has neither.

-- ------------------------------------------------------------ housekeeping

-- Re-created from 20261027120000. The four existing steps and their keys
-- are unchanged. Added, in this order:
--   draft_emails   resume email rows older than 7 days, whatever their
--                  status (they hold the address), and the resume rows of
--                  drafts being wiped (except one being sent);
--   drafts_wiped   live drafts past their expiry have their data and
--                  email wiped (a submitted draft is wiped at submit);
--   drafts_deleted drafts 30 days after they expired or were submitted,
--                  with their links.
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

  return jsonb_build_object(
    'reservations', v_reservations, 'sessions', v_sessions,
    'emails', v_emails, 'cron_runs', v_runs,
    'draft_emails', v_draft_emails, 'drafts_wiped', v_wiped, 'drafts_deleted', v_drafts
  );
end;
$$;

-- ------------------------------------------------------------ grants

-- create or replace keeps the grants of check_public_rate_limit (service
-- role only), the params check and the enqueue (nobody), requeue and list
-- (authenticated) and the purge (nobody).
revoke execute on function public._application_draft_lifetime() from public, anon, authenticated, service_role;
revoke execute on function public._application_draft_state_ok(jsonb) from public, anon, authenticated, service_role;
revoke execute on function public.get_admissions_email_health() from public, anon;
grant execute on function public.get_admissions_email_health() to authenticated;
