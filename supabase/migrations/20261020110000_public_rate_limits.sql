-- Admissions slice 8: rate limits for the public request path
-- (docs/admissions/PORT-PLAN.md, slice 8, D-8d decided 2026-10-13).
--
-- public_rate_limits holds fixed-window counters. key_hash is never a raw
-- value: a per-IP key is an HMAC made in the Edge Function with a secret
-- the database never sees, a per-email key is the sha256 of the normalised
-- email, and the global bucket uses the literal key 'global'. The CHECK
-- refuses anything else, so a raw IP can't be stored even by mistake.
--
-- The numbers live in one place, _public_rate_limit_rule(), so they can be
-- tuned after the first real month with a one-function migration:
--   submit_ip      20 per hour per IP hash (shared with slice 9's submit)
--   submit_global  200 per hour across every visitor
--   inquiry_email  5 per day per guardian email (UTC day, which is
--                  Africa/Accra's day)
-- The draft (120) and lead (60) buckets are not decided and not built.
--
-- No API role has any privilege on the table, service_role included, and
-- there is no policy: only the definer functions below touch it. revoke all
-- also removes TRUNCATE (the audit_log lesson from 7c).
--
-- check_public_rate_limit() is service_role only. It takes the two buckets
-- the Edge Function owns (submit_ip with an HMAC hex key, submit_global
-- with no key); the email bucket is counted inside submit_inquiry, in the
-- same transaction as the rows it creates.

create table public.public_rate_limits (
  bucket text not null check (bucket in ('submit_ip', 'submit_global', 'inquiry_email')),
  key_hash text not null check (key_hash ~ '^[0-9a-f]{64}$' or key_hash = 'global'),
  window_start timestamptz not null,
  count integer not null default 0 check (count >= 0),
  primary key (bucket, key_hash, window_start)
);

create index public_rate_limits_window_start_idx on public.public_rate_limits (window_start);

alter table public.public_rate_limits enable row level security;
revoke all on table public.public_rate_limits from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ the numbers

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
    ('inquiry_email', 5, interval '1 day')
  ) as r (bucket, max_count, window_length)
  where r.bucket = p_bucket;
$$;

-- ------------------------------------------------------------ counter

-- Counts one hit and says whether it is within the limit. A refused hit
-- still counts, so hammering doesn't reset anything. The upsert's row lock
-- is held to commit, so concurrent callers queue on the same counter.
-- Rows two days past their window are cleared as it goes.
create or replace function public._public_rate_limit_hit(p_bucket text, p_key_hash text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max integer;
  v_window interval;
  v_start timestamptz;
  v_count integer;
begin
  select r.max_count, r.window_length into v_max, v_window
  from public._public_rate_limit_rule(p_bucket) r;
  if v_max is null then
    raise exception 'Unknown rate limit bucket: %', p_bucket;
  end if;
  if p_key_hash is null or not (p_key_hash ~ '^[0-9a-f]{64}$' or p_key_hash = 'global') then
    raise exception 'A rate limit key must be a lowercase hex hash';
  end if;
  v_start := date_bin(v_window, clock_timestamp(), timestamptz '2000-01-01 00:00:00+00');

  delete from public.public_rate_limits where window_start < clock_timestamp() - interval '2 days';

  insert into public.public_rate_limits as l (bucket, key_hash, window_start, count)
  values (p_bucket, p_key_hash, v_start, 1)
  on conflict (bucket, key_hash, window_start) do update set count = l.count + 1
  returning l.count into v_count;
  return v_count <= v_max;
end;
$$;

-- Refuses every caller except service_role and postgres, even if a grant is
-- ever added by mistake: a signed-in user (a uid) and the anon or
-- authenticated role (the SET ROLE value, which SECURITY DEFINER doesn't
-- change) are all refused. Shared with submit_inquiry.
create or replace function public._require_public_service_caller()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is not null
     or coalesce(current_setting('role', true), '') in ('anon', 'authenticated') then
    raise exception 'This action is not available to your role';
  end if;
end;
$$;

-- The Edge Function's entry point. submit_ip needs the 64-character HMAC
-- hex the function made; submit_global takes no key.
create or replace function public.check_public_rate_limit(p_bucket text, p_key_hash text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_public_service_caller();
  if p_bucket = 'submit_ip' then
    if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
      raise exception 'submit_ip needs a 64-character lowercase hex key';
    end if;
    return public._public_rate_limit_hit('submit_ip', p_key_hash);
  elsif p_bucket = 'submit_global' then
    if p_key_hash is not null then
      raise exception 'submit_global takes no key';
    end if;
    return public._public_rate_limit_hit('submit_global', 'global');
  end if;
  raise exception 'Unknown rate limit bucket: %', p_bucket;
end;
$$;

-- ------------------------------------------------------------ grants

revoke execute on function public._require_public_service_caller() from public, anon, authenticated, service_role;
revoke execute on function public._public_rate_limit_rule(text) from public, anon, authenticated, service_role;
revoke execute on function public._public_rate_limit_hit(text, text) from public, anon, authenticated, service_role;
revoke execute on function public.check_public_rate_limit(text, text) from public, anon, authenticated;
grant execute on function public.check_public_rate_limit(text, text) to service_role;
