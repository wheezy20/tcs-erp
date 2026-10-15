-- Admissions slice 9a, checkpoint 1: the upload backend for the public
-- Application form (docs/admissions/PORT-PLAN.md, slice 9; D-9a, D-9e,
-- D-9f, D-9g, D-9h and D-9l decided 2026-10-14).
--
-- A parent's browser never writes to the database or the bucket on its
-- own authority. The flow:
--
--   1. One Turnstile solve opens an upload session (D-9f). The Edge
--      Function calls open_application_upload_session(), which returns a
--      random token once and keeps only its sha256.
--   2. For each file, the Edge Function calls reserve_application_upload()
--      with the session token, the document type and the extension. The
--      database makes the storage path; the Edge Function then mints a
--      signed upload URL for exactly that path, with overwrite off.
--   3. The browser uploads straight to Storage. The bucket (slice 4)
--      enforces 10 MiB and the three MIME types; it still has no write
--      policy (D-9a).
--   4. submit_application (checkpoint 2) will accept only this session's
--      unused, unexpired reservations whose file exists, and mark them used.
--   5. Reservations nobody used are cleaned up by a sweep in the Edge
--      Function (D-9h): claim_expired_application_uploads() hands out a
--      small batch, the function deletes the files through the Storage API
--      (SQL can't delete stored files; storage.objects has a delete guard),
--      and finish_application_upload_cleanup() marks them cleaned.
--
-- Every function here is service_role only and starts with
-- _require_public_service_caller(). The two tables have no API privileges
-- and no policies, like public_rate_limits: only these definer functions
-- touch them.
--
-- The numbers (D-9g, D-9l) are added to _public_rate_limit_rule() so every
-- public limit stays in one place.
--
-- The required document types per grade come from one helper,
-- _application_required_document_types(), used by the public options
-- (below) and by submit_application (checkpoint 2), so the form and the
-- server can't disagree. The application fee proof is required for every
-- grade (D-9e); vaccination proof is added where the grade requires it.
--
-- Errors use the slice 8 SQLSTATEs the Edge Function already maps:
--   TCS22  invalid input; the message is safe to show
--   TCS03  public applications are closed
--   TCS29  a limit is reached (the parent is pointed to the school office)

-- ------------------------------------------------------------ the numbers

alter table public.public_rate_limits drop constraint public_rate_limits_bucket_check;
alter table public.public_rate_limits add constraint public_rate_limits_bucket_check
  check (bucket in ('submit_ip', 'submit_global', 'inquiry_email',
                    'application_email', 'upload_ip', 'upload_global'));

-- Counted buckets (a hit is stored in public_rate_limits):
--   submit_ip          20 per hour per IP hash (enquiries and applications)
--   submit_global      200 per hour across every visitor
--   inquiry_email      5 per day per guardian email
--   application_email  5 per day per guardian email (counted by
--                      submit_application, checkpoint 2)
--   upload_ip          10 upload sessions per hour per IP hash
--   upload_global      100 upload sessions per hour, counted only after
--                      Turnstile passes
-- Caps (never stored as hits; the table check refuses these names):
--   upload_session_files      8 files per session; the window is how long a
--                             session and its reservations live (6 hours)
--   upload_open_reservations  400 reservations across everyone that are
--                             neither used nor cleaned up AND either have a
--                             file at their path, or are unexpired and made
--                             within the window (30 minutes) with no file
--                             yet. An empty reservation stops counting after
--                             30 minutes, so empty reservations can't hold
--                             the cap; stored files always count.
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
    ('upload_open_reservations', 400, interval '30 minutes')
  ) as r (bucket, max_count, window_length)
  where r.bucket = p_bucket;
$$;

-- The Edge Function's entry point, now with the two upload buckets. The IP
-- buckets need the 64-character HMAC hex the function made; the global
-- ones take no key. application_email is counted inside
-- submit_application's transaction, never from here.
create or replace function public.check_public_rate_limit(p_bucket text, p_key_hash text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_public_service_caller();
  if p_bucket in ('submit_ip', 'upload_ip') then
    if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
      raise exception '% needs a 64-character lowercase hex key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, p_key_hash);
  elsif p_bucket in ('submit_global', 'upload_global') then
    if p_key_hash is not null then
      raise exception '% takes no key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, 'global');
  end if;
  raise exception 'Unknown rate limit bucket: %', p_bucket;
end;
$$;

-- ------------------------------------------------------------ required documents

-- The document types a public application for this grade must include, fee
-- proof first. Null for a grade id that doesn't exist. Shared by the public
-- options and submit_application.
create or replace function public._application_required_document_types(p_grade_id uuid)
returns text[]
language sql
stable
set search_path = ''
as $$
  select case when g.is_preschool_vaccination_required
              then array['application_fee_proof', 'proof_of_vaccination']
              else array['application_fee_proof'] end
  from public.admissions_grades g
  where g.id = p_grade_id;
$$;

-- ------------------------------------------------------------ tables

create table public.application_upload_sessions (
  id uuid primary key default gen_random_uuid(),
  -- sha256 hex of the raw token, which is returned once and never stored.
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  -- Set by submit_application (checkpoint 2): a session is used once.
  closed_at timestamptz,
  check (expires_at > created_at)
);

alter table public.application_upload_sessions enable row level security;
revoke all on table public.application_upload_sessions from public, anon, authenticated, service_role;

create table public.application_upload_reservations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.application_upload_sessions (id) on delete restrict,
  -- The four document types the public form collects (TCS OS
  -- serializers.py:22-23); the other four are staff-only.
  document_type text not null check (document_type in (
    'proof_of_vaccination', 'financial_clearance', 'previous_report', 'application_fee_proof'
  )),
  extension text not null check (extension in ('pdf', 'jpg', 'jpeg', 'png')),
  -- Made here, never sent by the client. No token and no original file
  -- name: only the reservation id, so there is nothing to sanitize and the
  -- path satisfies application_documents' storage_path check.
  storage_path text generated always as
    ('uploads/' || id::text || '/' || document_type || '.' || extension) stored unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  cleanup_claimed_at timestamptz,
  cleaned_at timestamptz,
  check (consumed_at is null or cleaned_at is null)
);

create index application_upload_reservations_session_id_idx
  on public.application_upload_reservations (session_id);
create index application_upload_reservations_open_idx
  on public.application_upload_reservations (expires_at)
  where consumed_at is null and cleaned_at is null;

alter table public.application_upload_reservations enable row level security;
revoke all on table public.application_upload_reservations from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ RPCs

-- Raises TCS29 when the open-reservation cap is reached. A reservation that
-- is neither used nor cleaned counts if its file is in the bucket at the
-- reserved path (expired or not: the file still takes space until the
-- sweep), or if it is unexpired, has no file yet and was made within the
-- rule's window (30 minutes), so a parent's upload in progress holds a
-- place. Used reservations belong to applications and never count. Held
-- under one advisory lock to commit, so two callers can't both take the
-- last place. Files land outside the lock, so the count can briefly run
-- over the cap by uploads already granted; it never grants a new one.
create or replace function public._application_upload_capacity_check()
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_cap integer;
  v_window interval;
begin
  select r.max_count, r.window_length into v_cap, v_window
  from public._public_rate_limit_rule('upload_open_reservations') r;
  perform pg_advisory_xact_lock(hashtext('public.application_upload_reservations'));
  if (select count(*) from public.application_upload_reservations res
      where res.consumed_at is null and res.cleaned_at is null
        and (exists (select 1 from storage.objects o
                     where o.bucket_id = 'admissions-documents' and o.name = res.storage_path)
             or (res.expires_at > clock_timestamp() and res.created_at > clock_timestamp() - v_window))) >= v_cap then
    raise exception using errcode = 'TCS29', message = 'The upload limit is reached';
  end if;
end;
$$;

-- Opens a session after the Edge Function's IP limit, Turnstile and global
-- limit. Refuses while public applications are closed (no dual intake) or
-- the open-reservation cap is full. Returns the raw token once.
create or replace function public.open_application_upload_session()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_files integer;
  v_lifetime interval;
  v_token text;
  v_expires timestamptz;
begin
  perform public._require_public_service_caller();
  if not coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false) then
    raise exception using errcode = 'TCS03', message = 'Public applications are closed';
  end if;
  perform public._application_upload_capacity_check();

  select r.max_count, r.window_length into v_files, v_lifetime
  from public._public_rate_limit_rule('upload_session_files') r;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := clock_timestamp() + v_lifetime;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_expires);

  return jsonb_build_object('session_token', v_token, 'expires_at', v_expires, 'max_files', v_files);
end;
$$;

-- Reserves one storage path in a live session. The reservation lives as
-- long as its session. Returns the reservation id and the path the Edge
-- Function signs; the path never reaches the database from the client.
create or replace function public.reserve_application_upload(
  p_session_token text, p_document_type text, p_extension text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.application_upload_sessions;
  v_files integer;
  v_res public.application_upload_reservations;
begin
  perform public._require_public_service_caller();
  if not coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false) then
    raise exception using errcode = 'TCS03', message = 'Public applications are closed';
  end if;

  if p_session_token is not null and p_session_token ~ '^[0-9a-f]{64}$' then
    select * into v_session from public.application_upload_sessions
    where token_hash = encode(sha256(convert_to(p_session_token, 'UTF8')), 'hex')
    for update;
  end if;
  if v_session.id is null or v_session.closed_at is not null or v_session.expires_at <= clock_timestamp() then
    raise exception using errcode = 'TCS22',
      message = 'Your upload session has expired. Please reload the page and choose your files again.';
  end if;

  if p_document_type is null or p_document_type not in (
    'proof_of_vaccination', 'financial_clearance', 'previous_report', 'application_fee_proof'
  ) then
    raise exception using errcode = 'TCS22', message = 'That document type is not accepted';
  end if;
  if p_extension is null or p_extension not in ('pdf', 'jpg', 'jpeg', 'png') then
    raise exception using errcode = 'TCS22', message = 'Only PDF, JPG or PNG files can be uploaded';
  end if;

  select r.max_count into v_files from public._public_rate_limit_rule('upload_session_files') r;
  if (select count(*) from public.application_upload_reservations where session_id = v_session.id) >= v_files then
    raise exception using errcode = 'TCS22',
      message = 'This form has reached its file limit. Please reload the page and choose your files again.';
  end if;
  perform public._application_upload_capacity_check();

  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_session.id, p_document_type, p_extension, v_session.expires_at)
  returning * into v_res;

  return jsonb_build_object(
    'reservation_id', v_res.id, 'storage_path', v_res.storage_path, 'expires_at', v_res.expires_at
  );
end;
$$;

-- Hands the sweep up to p_limit (1 to 50) reservations that were never used,
-- expired more than 30 minutes ago, and were made more than 2 hours 15
-- minutes ago. A claim is held for 10 minutes; a sweep that fails to delete
-- the files leaves it to be claimed again. A reservation can only be used
-- before it expires, so the grace keeps the sweep and a submit from ever
-- touching the same row. The age rule covers Storage's signed upload token,
-- which lives 2 hours from signing (just after the reservation is made)
-- whatever the reservation's expiry: once a row is cleaned, its token is
-- dead, so no file can land after the sweep and be left behind.
create or replace function public.claim_expired_application_uploads(p_limit integer)
returns table (reservation_id uuid, storage_path text)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_public_service_caller();
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'p_limit must be between 1 and 50';
  end if;
  return query
  with c as (
    select r.id from public.application_upload_reservations r
    where r.consumed_at is null and r.cleaned_at is null
      and r.expires_at < clock_timestamp() - interval '30 minutes'
      and r.created_at < clock_timestamp() - interval '2 hours 15 minutes'
      and (r.cleanup_claimed_at is null or r.cleanup_claimed_at < clock_timestamp() - interval '10 minutes')
    order by r.expires_at
    limit p_limit
    for update skip locked
  )
  update public.application_upload_reservations r
  set cleanup_claimed_at = clock_timestamp()
  from c where r.id = c.id
  returning r.id, r.storage_path;
end;
$$;

-- Marks claimed reservations cleaned once their files are deleted. Only a
-- claimed, unused, expired reservation can be marked, so a wrong id can't
-- hide a live upload. Returns how many were marked.
create or replace function public.finish_application_upload_cleanup(p_reservation_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  perform public._require_public_service_caller();
  if p_reservation_ids is null or cardinality(p_reservation_ids) = 0 then
    return 0;
  end if;
  if cardinality(p_reservation_ids) > 50 then
    raise exception 'At most 50 reservations at a time';
  end if;
  update public.application_upload_reservations
  set cleaned_at = clock_timestamp()
  where id = any (p_reservation_ids)
    and consumed_at is null and cleaned_at is null and cleanup_claimed_at is not null
    and expires_at < clock_timestamp() - interval '30 minutes'
    and created_at < clock_timestamp() - interval '2 hours 15 minutes';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ------------------------------------------------------------ options

-- Unchanged apart from required_document_types on each grade (the anon
-- surface gate, approved 2026-10-14). The signature is unchanged, so the
-- anon-executable count stays at 170.
create or replace function public.get_public_admissions_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with active_grades as (
    select g.id, g.name, g.position from public.admissions_grades g where g.is_active
  )
  select jsonb_build_object(
    'intake_open', coalesce((select s.public_intake_open from public.admissions_settings s where s.id = 1), false),
    'applications_open', coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', g.id, 'name', g.name, 'position', g.position,
        'required_document_types', to_jsonb(public._application_required_document_types(g.id))
      ) order by g.position, g.name)
      from active_grades g
    ), '[]'::jsonb),
    'campuses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'name', coalesce(b.public_label, b.name),
        'accepted_grade_ids', coalesce((
          select jsonb_agg(g.id order by g.position, g.name)
          from active_grades g
          where not exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = b.id)
             or exists (select 1 from public.admissions_campus_grade_rules r
                        where r.branch_id = b.id and r.grade_id = g.id)
        ), '[]'::jsonb)
      ) order by coalesce(b.public_label, b.name))
      from public.branches b
    ), '[]'::jsonb),
    'academic_years', coalesce((
      select jsonb_agg(y.label order by y.position, y.label)
      from public.admissions_academic_years y where y.is_active
    ), '[]'::jsonb)
  );
$$;

-- ------------------------------------------------------------ grants

-- create or replace keeps check_public_rate_limit's grants (service_role
-- only) and the options function's (anon, authenticated, service_role).
revoke execute on function public._application_required_document_types(uuid) from public, anon, authenticated, service_role;
revoke execute on function public._application_upload_capacity_check() from public, anon, authenticated, service_role;

revoke execute on function public.open_application_upload_session() from public, anon, authenticated;
revoke execute on function public.reserve_application_upload(text, text, text) from public, anon, authenticated;
revoke execute on function public.claim_expired_application_uploads(integer) from public, anon, authenticated;
revoke execute on function public.finish_application_upload_cleanup(uuid[]) from public, anon, authenticated;
grant execute on function public.open_application_upload_session() to service_role;
grant execute on function public.reserve_application_upload(text, text, text) to service_role;
grant execute on function public.claim_expired_application_uploads(integer) to service_role;
grant execute on function public.finish_application_upload_cleanup(uuid[]) to service_role;
