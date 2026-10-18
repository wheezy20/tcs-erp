-- Admissions slice 12, migration 2 of 2: the scheduled jobs.
--
-- pg_cron runs four jobs, all as postgres:
--   admissions-mail           every minute: calls the admissions-worker
--                             Edge Function (job "mail") through pg_net,
--                             only when an email is due, so an idle queue
--                             makes no calls.
--   admissions-upload-sweep   every 15 minutes: calls the worker (job
--                             "sweep"), which removes the files of expired
--                             upload reservations through the Storage API
--                             (files are never deleted in SQL, D-4d). This
--                             is the scheduled sweep D-9h left to slice 12;
--                             the per-request sweep in admissions-public
--                             stays.
--   admissions-settle-offers  hourly: settle_expired_offers() (D-6l).
--   admissions-housekeeping   daily at 03:00 (Accra time is UTC): purges
--                             old upload sessions and their used or
--                             cleaned reservations, old outbox rows, and
--                             old pg_cron run history.
--
-- The worker calls need the worker URL (set by hand with
-- set_admissions_worker_url) and the Vault secret made in migration 1.
-- Until the URL is set, the two worker jobs do nothing.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- ------------------------------------------------------------ worker call

-- Queues one HTTP call to the worker. pg_net sends it after this
-- transaction commits. Returns whether a call was queued. Nobody but
-- postgres (the cron jobs) can run it.
create or replace function public._admissions_worker_kick(p_job text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if p_job is null or p_job not in ('mail', 'sweep') then
    raise exception 'Unknown worker job: %', p_job;
  end if;
  select w.worker_url into v_url from public.admissions_email_worker w where w.id;
  select nullif(s.decrypted_secret, '') into v_secret
  from vault.decrypted_secrets s where s.name = 'admissions_worker_secret';
  if v_url is null or v_secret is null then
    return false;
  end if;
  if p_job = 'mail' and not exists (
    select 1 from public.admissions_email_outbox o
    where (o.status = 'pending' and o.next_attempt_at <= clock_timestamp())
       or (o.status = 'sending' and o.claimed_at < clock_timestamp() - interval '5 minutes')
  ) then
    return false;
  end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('job', p_job),
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-admissions-worker-secret', v_secret
    ),
    timeout_milliseconds := 55000
  );
  return true;
end;
$$;

-- ------------------------------------------------------------ housekeeping

-- Deletes, and returns the counts:
--   upload reservations whose session expired more than 30 days ago and
--     that were used or cleaned (an unused, uncleaned one may still have a
--     file, so it waits for the sweep);
--   upload sessions expired more than 30 days ago with no reservation left;
--   sent outbox rows older than 90 days, failed and suppressed ones older
--     than 180 days (decided 2026-10-16);
--   pg_cron run history older than 7 days.
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
     or (o.status in ('failed', 'suppressed') and o.created_at < clock_timestamp() - interval '180 days');
  get diagnostics v_emails = row_count;

  delete from cron.job_run_details d where d.end_time < clock_timestamp() - interval '7 days';
  get diagnostics v_runs = row_count;

  return jsonb_build_object(
    'reservations', v_reservations, 'sessions', v_sessions,
    'emails', v_emails, 'cron_runs', v_runs
  );
end;
$$;

revoke execute on function public._admissions_worker_kick(text) from public, anon, authenticated, service_role;
revoke execute on function public.purge_admissions_housekeeping() from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ the jobs

-- cron.schedule with a name replaces a job of the same name, so this is
-- safe to re-run.
select cron.schedule('admissions-mail', '* * * * *',
  $job$select public._admissions_worker_kick('mail')$job$);
select cron.schedule('admissions-upload-sweep', '*/15 * * * *',
  $job$select public._admissions_worker_kick('sweep')$job$);
select cron.schedule('admissions-settle-offers', '7 * * * *',
  $job$select public.settle_expired_offers()$job$);
select cron.schedule('admissions-housekeeping', '0 3 * * *',
  $job$select public.purge_admissions_housekeeping()$job$);
