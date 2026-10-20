-- Probes for 20261027120000_admissions_email_expiry (admissions slice 12,
-- decided 2026-10-20): a queued email older than 48 hours when the worker
-- claims is expired and never sent; age counts from a Manager's retry when
-- there is one; expired rows are never claimed again, can't be retried,
-- show in the staff list and the health summary, and are purged after 180
-- days. The new helper is granted to nobody.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261027120000_admissions_email_expiry.sql

-- probe: X1 structure: expired is a status; the age helper is 48 hours and granted to nobody; health is Manager and Auditor only
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text := 'public._admissions_email_max_age()';
begin
  if not exists (select 1 from pg_constraint where conname = 'admissions_email_outbox_status_check'
                 and pg_get_constraintdef(oid) like '%expired%') then
    raise exception 'expired is not a status';
  end if;
  if public._admissions_email_max_age() <> interval '48 hours' then raise exception 'max age changed'; end if;
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception 'age helper executable by an API role';
  end if;
  f := 'public.get_admissions_email_health()';
  if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception 'health grants wrong';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f::regprocedure and a.grantee = 0) then
    raise exception 'health executable by public';
  end if;
  if not exists (select 1 from pg_proc where oid = f::regprocedure and prosecdef
                 and exists (select 1 from unnest(proconfig) c where c like 'search_path=%')) then
    raise exception 'health not definer with a search_path';
  end if;
end $$;
-- as role:
select 1;

-- probe: X2 service_role claim: pending rows older than 48 hours and lapsed leases on old rows expire unsent; a 47 hour row and an old row retried an hour ago are claimed; expired rows are never claimed again
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.row(p_to text, p_created timestamptz, p_status text default 'pending')
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), 'inquiry_parent', p_to, array[gen_random_uuid()],
    '{"references":[{"reference":"INQ-2026-9001","grade":"Grade 1","academic_year":"2026/2027"}]}',
    p_status, p_created,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() - interval '6 minutes' end,
    now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
create temp table ids (k text, id uuid);
grant select on ids to public;
insert into ids select 'old', pg_temp.row('old@example.test', now() - interval '49 hours');
insert into ids select 'young', pg_temp.row('young@example.test', now() - interval '47 hours');
insert into ids select 'oldlease', pg_temp.row('lease@example.test', now() - interval '50 hours', 'sending');
insert into ids select 'retried', pg_temp.row('retried@example.test', now() - interval '72 hours');
update public.admissions_email_outbox set requeued_at = now() - interval '1 hour', attempts = 0
  where id = (select id from ids where k = 'retried');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare got text[]; begin
  select array_agg(i.k order by i.k) into got
  from public.claim_admissions_emails(50, 1000) c join ids i on i.id = c.id;
  if got is distinct from array['retried', 'young'] then raise exception 'claimed %', got; end if;
  if exists (select 1 from public.claim_admissions_emails(50, 1000)) then raise exception 'claimed again'; end if;
end $$;
reset role;
do $$ begin
  if (select array_agg(i.k || ':' || o.status order by i.k) from public.admissions_email_outbox o join ids i on i.id = o.id)
     is distinct from array['old:expired', 'oldlease:expired', 'retried:sending', 'young:sending'] then
    raise exception 'statuses %', (select array_agg(i.k || ':' || o.status) from public.admissions_email_outbox o join ids i on i.id = o.id);
  end if;
  if exists (select 1 from public.admissions_email_outbox o join ids i on i.id = o.id
             where o.status = 'expired' and (o.claim_token is not null or o.sent_at is not null)) then
    raise exception 'an expired row holds a claim or a send time';
  end if;
end $$;

-- probe: X3 Manager and Auditor see expired rows in the list and the health count; Retry leaves an expired row expired
-- expect: Manager,Auditor
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, status)
values ('inquiry:12000000-0000-4000-8000-000000000201', 'inquiry_parent', 'gone@example.test',
  array[gen_random_uuid()],
  '{"references":[{"reference":"INQ-2026-9001","grade":"Grade 1","academic_year":"2026/2027"}]}', 'expired');
create temp table gone as select id from public.admissions_email_outbox
  where event_key = 'inquiry:12000000-0000-4000-8000-000000000201';
grant select on gone to public;
-- as role:
do $$ declare n integer; begin
  if not exists (select 1 from public.list_admissions_emails('expired', 10) where status = 'expired') then
    raise exception 'expired not listed';
  end if;
  if (select expired from public.get_admissions_email_health()) <> 1 then raise exception 'health count'; end if;
  if public.has_role(array['Manager']) then
    n := public.requeue_admissions_emails(array(select id from gone));
    if n <> 0 then raise exception 'an expired row was retried'; end if;
  end if;
end $$;

-- probe: X4 housekeeping purges expired rows after 180 days and keeps younger ones
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, status, created_at)
select 'inquiry:' || gen_random_uuid(), 'inquiry_parent', 'aged@example.test', array[gen_random_uuid()],
  '{"references":[{"reference":"INQ-2026-9001","grade":"Grade 1","academic_year":"2026/2027"}]}', 'expired', c
from (values (now() - interval '181 days'), (now() - interval '179 days')) v (c);
-- as role:
reset role;
select set_config('request.jwt.claims', '', true);
do $$ declare r jsonb; begin
  r := public.purge_admissions_housekeeping();
  if (r ->> 'emails')::int <> 1 then raise exception 'purged %', r; end if;
  if (select count(*) from public.admissions_email_outbox where recipient_email = 'aged@example.test') <> 1 then
    raise exception 'wrong expired rows kept';
  end if;
end $$;
