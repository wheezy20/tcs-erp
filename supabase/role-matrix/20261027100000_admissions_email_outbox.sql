-- Probes for 20261027100000_admissions_email_outbox and
-- 20261027110000_admissions_scheduled_jobs (admissions slice 12, checkpoint
-- C1; docs/admissions/PORT-PLAN.md, slice 12): the outbox and worker
-- tables have no API privileges; the worker functions are service_role
-- only and refuse every other caller even with a mistaken grant; staff
-- read masked status (Manager and Auditor), an application's confirmation
-- status (anyone who can see it) and retry failed rows (Manager only).
-- Submissions queue one parent email per recipient (typed first, then the
-- family on record, at most 4) and one staff alert, with no names or
-- health data, never twice for one event, and suppressed past 4 per
-- address per day. Claim, mark, back-off, the ceiling, housekeeping and
-- the cron jobs are value-probed.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261027100000_admissions_email_outbox.sql
-- Run the probe files before the Edge Function integration tests (they
-- commit rows).

-- probe: E1 structure: both tables have RLS and no API privilege; helpers granted to nobody; worker functions service_role only; staff functions authenticated only; all definer with a pinned search_path
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text; p text; f text;
begin
  foreach f in array array['public.admissions_email_outbox', 'public.admissions_email_worker'] loop
    if not (select relrowsecurity from pg_class where oid = f::regclass) then raise exception '% RLS off', f; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = split_part(f, '.', 2)) then
      raise exception '% has a policy', f;
    end if;
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(r, f, p) then raise exception '% % % granted', f, r, p; end if;
      end loop;
    end loop;
  end loop;
  foreach f in array array['public._admissions_email_retry_delay(integer)', 'public._admissions_email_params_ok(text, jsonb)',
      'public._admissions_mask_email(text)', 'public._enqueue_admissions_emails(text, uuid, uuid, text[])',
      'public.set_admissions_worker_url(text)', 'public._admissions_worker_kick(text)',
      'public.purge_admissions_housekeeping()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
  foreach f in array array['public.admissions_worker_secret()', 'public.claim_admissions_emails(integer, integer)',
      'public.mark_admissions_email_result(uuid, uuid, text, text, integer, text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% grants wrong', f;
    end if;
  end loop;
  foreach f in array array['public.requeue_admissions_emails(uuid[])', 'public.list_admissions_emails(text, integer)',
      'public.get_admissions_email_health()', 'public.get_application_email_status(uuid)'] loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute') then
      raise exception '% grants wrong', f;
    end if;
  end loop;
  foreach f in array array['public.admissions_worker_secret()', 'public.claim_admissions_emails(integer, integer)',
      'public.mark_admissions_email_result(uuid, uuid, text, text, integer, text)', 'public.requeue_admissions_emails(uuid[])',
      'public.list_admissions_emails(text, integer)', 'public.get_admissions_email_health()',
      'public.get_application_email_status(uuid)', 'public.set_admissions_worker_url(text)',
      'public._admissions_worker_kick(text)', 'public.purge_admissions_housekeeping()'] loop
    if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception '% not definer', f; end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure
                   and exists (select 1 from unnest(proconfig) c where c like 'search_path=%')) then
      raise exception '% has no search_path', f;
    end if;
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f::regprocedure and a.grantee = 0) then
      raise exception '% executable by public', f;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: E2 the anon-executable count stays 170; no overloads; the Vault secret exists as 64 hex
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare n integer;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
  if exists (select proname from pg_proc where proname in ('submit_inquiry', 'submit_application',
      'claim_admissions_emails', 'mark_admissions_email_result', '_enqueue_admissions_emails', '_public_rate_limit_rule')
      group by proname having count(*) > 1) then
    raise exception 'overloads';
  end if;
  if (select decrypted_secret from vault.decrypted_secrets where name = 'admissions_worker_secret') !~ '^[0-9a-f]{64}$' then
    raise exception 'worker secret missing or malformed';
  end if;
  if (select r.max_count || '/' || r.window_length from public._public_rate_limit_rule('email_recipient_day') r)
     is distinct from '4/1 day' then
    raise exception 'recipient cap wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: E3 no JWT role can read the outbox table directly
-- expect: none
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row();
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_email_outbox) then raise exception 'no rows'; end if;
end $$;

-- probe: E4 even with grants added by mistake, every JWT role is refused by the worker functions' guard
-- expect: none
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row();
grant execute on function public.claim_admissions_emails(integer, integer) to anon, authenticated;
grant execute on function public.admissions_worker_secret() to anon, authenticated;
-- as role:
do $$ declare n integer := 0; begin
  begin perform public.admissions_worker_secret(); n := n + 1; exception when others then null; end;
  begin perform public.claim_admissions_emails(10, 100); n := n + 1; exception when others then null; end;
  if n = 0 then raise exception 'all refused'; end if;
end $$;

-- probe: E5 mark_admissions_email_result, set_admissions_worker_url, the kick and the purge: no JWT role can call them
-- expect: none
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row('sending');
-- as role:
do $$ declare n integer := 0; begin
  begin perform public.mark_admissions_email_result(gen_random_uuid(), gen_random_uuid(), 'sent', null, 200, 'x'); n := n + 1;
  exception when others then null; end;
  begin perform public.set_admissions_worker_url('https://example.test/w'); n := n + 1; exception when others then null; end;
  begin perform public._admissions_worker_kick('mail'); n := n + 1; exception when others then null; end;
  begin perform public.purge_admissions_housekeeping(); n := n + 1; exception when others then null; end;
  if n = 0 then raise exception 'all refused'; end if;
end $$;

-- probe: E6 list_admissions_emails: Manager and Auditor see masked recipients and references, never the address
-- expect: Manager,Auditor
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row('failed', 'jane.doe@gmail.com');
-- as role:
do $$ declare r record; begin
  select * into r from public.list_admissions_emails('failed', 10) limit 1;
  if r.id is null then raise exception 'nothing listed'; end if;
  if r.recipient_masked is distinct from 'j•••@g•••.com' then raise exception 'mask %', r.recipient_masked; end if;
  if r."references" is distinct from array['INQ-2026-9001'] then raise exception 'refs'; end if;
end $$;

-- probe: E7 get_admissions_email_health: Manager and Auditor
-- expect: Manager,Auditor
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row('failed');
select pg_temp.row('suppressed');
select pg_temp.row('pending');
-- as role:
do $$ declare h record; begin
  select * into h from public.get_admissions_email_health();
  if (h.waiting, h.failed, h.suppressed) is distinct from (1, 1, 1) then raise exception 'counts %', h; end if;
end $$;

-- probe: E8 requeue_admissions_emails: Manager only; a failed row goes back to pending with a fresh count and the Manager recorded; a suppressed row stays
-- expect: Manager
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
create temp table ids (k text, id uuid);
grant select on ids to public;
insert into ids select 'failed', pg_temp.row('failed');
insert into ids select 'suppressed', pg_temp.row('suppressed');
update public.admissions_email_outbox set attempts = 6, last_error_class = 'network' where id = (select id from ids where k = 'failed');
-- as role:
do $$ declare n integer; begin
  n := public.requeue_admissions_emails(array(select id from ids));
  if n <> 1 then raise exception 'requeued %', n; end if;
end $$;
reset role;
do $$ begin
  if not exists (select 1 from public.admissions_email_outbox o join ids on ids.id = o.id and ids.k = 'failed'
                 where o.status = 'pending' and o.attempts = 0 and o.last_error_class is null
                   and o.requeued_by = auth.uid()
                   and o.requeued_at is not null) then
    raise exception 'failed row not requeued';
  end if;
  if not exists (select 1 from public.admissions_email_outbox o join ids on ids.id = o.id and ids.k = 'suppressed'
                 where o.status = 'suppressed') then
    raise exception 'suppressed row changed';
  end if;
end $$;

-- probe: E9 get_application_email_status: Manager, Auditor and an in-scope officer see the status, with no address
-- expect: Manager,Auditor,Admissions Officer
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
insert into public.families (id) values ('12000000-0000-4000-8000-000000000001');
insert into public.students (id, family_id, full_name) values
  ('12000000-0000-4000-8000-000000000002', '12000000-0000-4000-8000-000000000001', 'Status Child');
insert into public.applications (id, student_id, stage, academic_year, year_group_applied_for) values
  ('12000000-0000-4000-8000-000000000003', '12000000-0000-4000-8000-000000000002', 'application', '2026/2027', 'Grade 3');
select pg_temp.row('sent', p_app => '12000000-0000-4000-8000-000000000003');

insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ declare r record; begin
  select * into r from public.get_application_email_status('12000000-0000-4000-8000-000000000003');
  if r.status is distinct from 'sent' or r.emails <> 1 or r.last_sent_at is null then raise exception 'status %', r; end if;
end $$;

-- probe: E10 get_application_email_status: an officer outside the band is refused
-- expect: Manager,Auditor
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
insert into public.families (id) values ('12000000-0000-4000-8000-000000000001');
insert into public.students (id, family_id, full_name) values
  ('12000000-0000-4000-8000-000000000002', '12000000-0000-4000-8000-000000000001', 'Status Child');
insert into public.applications (id, student_id, stage, academic_year, year_group_applied_for) values
  ('12000000-0000-4000-8000-000000000003', '12000000-0000-4000-8000-000000000002', 'application', '2026/2027', 'Grade 3');
select pg_temp.row('sent', p_app => '12000000-0000-4000-8000-000000000003');

insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool}', false, false, true);
-- as role:
select * from public.get_application_email_status('12000000-0000-4000-8000-000000000003');

-- probe: E11 service_role enquiry: one parent email per typed address in form order, one staff alert, references in form order, no names or other keys stored
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.ipayload(emails) is a valid two-child enquiry with one
-- guardian per email.
create function pg_temp.ipayload(p_emails text[]) returns jsonb language plpgsql as $f$
declare v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_intake_open = true where id = 1;
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('referral_source', 'website', 'guardians', v_g,
    'students', jsonb_build_array(
      jsonb_build_object('full_name', 'NAME-SENTINEL First', 'date_of_birth', '2019-02-03', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
        'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      jsonb_build_object('full_name', 'NAME-SENTINEL Second', 'date_of_birth', '2023-05-14',
        'prior_schooling', 'not_yet_in_school', 'grade_id', (select id from public.admissions_grades where name = 'Nursery 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September')));
end $f$;
select set_config('tcs.p', pg_temp.ipayload(array['First.Parent@Example.test', 'second.parent@example.test'])::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.refs', public.submit_inquiry(current_setting('tcs.p')::jsonb)::text, true);
reset role;
do $$ declare v_refs text[] := current_setting('tcs.refs')::text[]; v_expect jsonb;
begin
  v_expect := jsonb_build_object('references', jsonb_build_array(
    jsonb_build_object('reference', v_refs[1], 'grade', 'Grade 1', 'academic_year', '2026/2027'),
    jsonb_build_object('reference', v_refs[2], 'grade', 'Nursery 1', 'academic_year', '2026/2027')));
  if (select array_agg(coalesce(recipient_email, '(staff)') || '|' || status order by kind, created_at, recipient_email)
      from public.admissions_email_outbox where params -> 'references' -> 0 ->> 'reference' = v_refs[1])
     is distinct from array['first.parent@example.test|pending', 'second.parent@example.test|pending', '(staff)|pending'] then
    raise exception 'rows wrong: %', (select array_agg(kind || ':' || coalesce(recipient_email, '-')) from public.admissions_email_outbox);
  end if;
  if exists (select 1 from public.admissions_email_outbox
             where params -> 'references' -> 0 ->> 'reference' = v_refs[1] and params is distinct from v_expect) then
    raise exception 'params wrong';
  end if;
  if exists (select 1 from public.admissions_email_outbox o where row_to_json(o)::text like '%SENTINEL%') then
    raise exception 'a name was stored';
  end if;
  if (select count(distinct event_key) from public.admissions_email_outbox
      where params -> 'references' -> 0 ->> 'reference' = v_refs[1]) <> 1 then
    raise exception 'event keys differ';
  end if;
end $$;

-- probe: E12 service_role application, new family: one parent email and one staff alert with family_matched false; nothing about health
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.afx(emails, child, dob) builds an open switch, a live
-- upload session with a stored fee proof, and a valid payload with one
-- guardian per email; pg_temp.asub(b) submits it as the caller.
create function pg_temp.afx(p_emails text[], p_child text default 'Outbox Child',
  p_dob date default date '2018-05-01', p_grade text default 'Grade 3')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_id uuid; v_p text;
  v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_sid, 'application_fee_proof', 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
  insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Probe Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('token', v_tok,
    'sniffed', jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf')),
    'payload', jsonb_build_object(
      'guardians', v_g,
      'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
        'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
        'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      'campus_id', (select id from public.branches where name = 'Main')::text,
      'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
      'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
      'documents', jsonb_build_array(jsonb_build_object('document_type', 'application_fee_proof',
        'reservation_id', v_id, 'path', v_p)),
      'declaration_signature_name', 'Guardian One', 'declaration_agreed', true));
end $f$;
create function pg_temp.asub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
create temp table fx (k text, b jsonb);
grant select on fx to public;
insert into fx select 'a', pg_temp.afx(array['new.family@example.test']);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.ref', pg_temp.asub(b), true) from fx where k = 'a';
reset role;
do $$ declare v_ref text := current_setting('tcs.ref'); begin
  if (select array_agg(kind || '|' || coalesce(recipient_email, '-') || '|' || status order by kind)
      from public.admissions_email_outbox where params -> 'references' -> 0 ->> 'reference' = v_ref)
     is distinct from array['application_parent|new.family@example.test|pending', 'application_staff|-|pending'] then
    raise exception 'rows wrong';
  end if;
  if (select params from public.admissions_email_outbox
      where kind = 'application_staff' and params -> 'references' -> 0 ->> 'reference' = v_ref)
     is distinct from jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
       'reference', v_ref, 'grade', 'Grade 3', 'academic_year', '2026/2027')), 'family_matched', false, 'outcome', null) then
    raise exception 'staff params wrong';
  end if;
  if exists (select 1 from public.admissions_email_outbox o where row_to_json(o)::text like '%SENTINEL%'
             or row_to_json(o)::text like '%Outbox Child%') then
    raise exception 'health or name stored';
  end if;
end $$;

-- probe: E13 service_role matched family: typed addresses first, then the guardian on record; a typed stranger gets the same email; the staff alert says matched
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.afx(emails, child, dob) builds an open switch, a live
-- upload session with a stored fee proof, and a valid payload with one
-- guardian per email; pg_temp.asub(b) submits it as the caller.
create function pg_temp.afx(p_emails text[], p_child text default 'Outbox Child',
  p_dob date default date '2018-05-01', p_grade text default 'Grade 3')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_id uuid; v_p text;
  v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_sid, 'application_fee_proof', 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
  insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Probe Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('token', v_tok,
    'sniffed', jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf')),
    'payload', jsonb_build_object(
      'guardians', v_g,
      'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
        'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
        'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      'campus_id', (select id from public.branches where name = 'Main')::text,
      'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
      'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
      'documents', jsonb_build_array(jsonb_build_object('document_type', 'application_fee_proof',
        'reservation_id', v_id, 'path', v_p)),
      'declaration_signature_name', 'Guardian One', 'declaration_agreed', true));
end $f$;
create function pg_temp.asub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
create temp table fx (k text, b jsonb);
grant select on fx to public;
insert into public.families (id) values ('12000000-0000-4000-8000-000000000011');
insert into public.guardians (family_id, surname, first_name, relationship, phone, email) values
  ('12000000-0000-4000-8000-000000000011', 'Record', 'Real', 'mother', '+233590000009', 'real.parent@example.test'),
  ('12000000-0000-4000-8000-000000000011', 'Record', 'Other', 'father', '+233590000008', 'other.parent@example.test');
insert into fx select 'a', pg_temp.afx(array['stranger@example.test', 'REAL.parent@example.test']);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.ref', pg_temp.asub(b), true) from fx where k = 'a';
reset role;
do $$ declare v_ref text := current_setting('tcs.ref'); begin
  if (select array_agg(recipient_email order by created_at, id) from public.admissions_email_outbox
      where kind = 'application_parent' and params -> 'references' -> 0 ->> 'reference' = v_ref) is null then
    raise exception 'no parent rows';
  end if;
  if (select array_agg(recipient_email order by recipient_email) from public.admissions_email_outbox
      where kind = 'application_parent' and params -> 'references' -> 0 ->> 'reference' = v_ref)
     is distinct from array['other.parent@example.test', 'real.parent@example.test', 'stranger@example.test'] then
    raise exception 'recipients %', (select array_agg(recipient_email) from public.admissions_email_outbox where kind = 'application_parent');
  end if;
  if (select count(*) from public.guardians where family_id = '12000000-0000-4000-8000-000000000011') <> 2 then
    raise exception 'guardians changed';
  end if;
  if not exists (select 1 from public.admissions_email_outbox where kind = 'application_staff'
                 and params -> 'references' -> 0 ->> 'reference' = v_ref
                 and params -> 'family_matched' = 'true'::jsonb and params ->> 'outcome' = 'new_application') then
    raise exception 'staff alert not marked matched';
  end if;
  if (select count(distinct params) from public.admissions_email_outbox
      where kind = 'application_parent' and params -> 'references' -> 0 ->> 'reference' = v_ref) <> 1 then
    raise exception 'parent emails differ';
  end if;
end $$;

-- probe: E14 service_role: a repeat submit of a used session returns the same reference and queues nothing more
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.afx(emails, child, dob) builds an open switch, a live
-- upload session with a stored fee proof, and a valid payload with one
-- guardian per email; pg_temp.asub(b) submits it as the caller.
create function pg_temp.afx(p_emails text[], p_child text default 'Outbox Child',
  p_dob date default date '2018-05-01', p_grade text default 'Grade 3')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_id uuid; v_p text;
  v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_sid, 'application_fee_proof', 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
  insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Probe Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('token', v_tok,
    'sniffed', jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf')),
    'payload', jsonb_build_object(
      'guardians', v_g,
      'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
        'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
        'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      'campus_id', (select id from public.branches where name = 'Main')::text,
      'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
      'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
      'documents', jsonb_build_array(jsonb_build_object('document_type', 'application_fee_proof',
        'reservation_id', v_id, 'path', v_p)),
      'declaration_signature_name', 'Guardian One', 'declaration_agreed', true));
end $f$;
create function pg_temp.asub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
create temp table fx (k text, b jsonb);
grant select on fx to public;
insert into fx select 'a', pg_temp.afx(array['double.click@example.test']);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare b jsonb; r1 text; r2 text; n1 integer; n2 integer; begin
  select fx.b into b from fx where k = 'a';
  r1 := pg_temp.asub(b);
  reset role;
  select count(*) into n1 from public.admissions_email_outbox;
  set local role service_role;
  r2 := pg_temp.asub(b);
  reset role;
  select count(*) into n2 from public.admissions_email_outbox;
  if r1 is distinct from r2 then raise exception 'references differ'; end if;
  if n1 <> 2 or n2 <> 2 then raise exception 'rows % then %', n1, n2; end if;
end $$;

-- probe: E15 service_role: an address with 4 parent emails in 24 hours gets the next one suppressed; older or suppressed rows don't count; the other address still sends
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.ipayload(emails) is a valid two-child enquiry with one
-- guardian per email.
create function pg_temp.ipayload(p_emails text[]) returns jsonb language plpgsql as $f$
declare v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_intake_open = true where id = 1;
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('referral_source', 'website', 'guardians', v_g,
    'students', jsonb_build_array(
      jsonb_build_object('full_name', 'NAME-SENTINEL First', 'date_of_birth', '2019-02-03', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
        'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      jsonb_build_object('full_name', 'NAME-SENTINEL Second', 'date_of_birth', '2023-05-14',
        'prior_schooling', 'not_yet_in_school', 'grade_id', (select id from public.admissions_grades where name = 'Nursery 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September')));
end $f$;-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row('sent', 'busy@example.test', now() - interval '1 hour') from generate_series(1, 2);
select pg_temp.row('suppressed', 'busy@example.test', now() - interval '1 hour') from generate_series(1, 5);
select pg_temp.row('sent', 'busy@example.test', now() - interval '25 hours') from generate_series(1, 5);
select pg_temp.row('failed', 'busy@example.test', now() - interval '2 hours');
select set_config('tcs.p', pg_temp.ipayload(array['busy@example.test', 'calm@example.test'])::text, true);
select set_config('tcs.p2', pg_temp.ipayload(array['busy@example.test'])::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.r1', public.submit_inquiry(current_setting('tcs.p')::jsonb)::text, true);
select set_config('tcs.r2', public.submit_inquiry(current_setting('tcs.p2')::jsonb)::text, true);
reset role;
do $$ declare r1 text := (current_setting('tcs.r1')::text[])[1]; r2 text := (current_setting('tcs.r2')::text[])[1]; begin
  if (select array_agg(recipient_email || '|' || status order by recipient_email) from public.admissions_email_outbox
      where kind = 'inquiry_parent' and params -> 'references' -> 0 ->> 'reference' = r1)
     is distinct from array['busy@example.test|pending', 'calm@example.test|pending'] then
    raise exception 'fourth email not sent';
  end if;
  if (select array_agg(recipient_email || '|' || status) from public.admissions_email_outbox
      where kind = 'inquiry_parent' and params -> 'references' -> 0 ->> 'reference' = r2)
     is distinct from array['busy@example.test|suppressed'] then
    raise exception 'fifth email not suppressed';
  end if;
  if not exists (select 1 from public.admissions_email_outbox where kind = 'inquiry_staff'
                 and params -> 'references' -> 0 ->> 'reference' = r2 and status = 'pending') then
    raise exception 'staff alert missing';
  end if;
end $$;

-- probe: E16 the params and row checks refuse a name, a health key, a bad reference, a staff row with an address and a parent row without one
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
reset role;
select set_config('request.jwt.claims', '', true);
do $$ declare i integer; ok boolean; bad jsonb[] := array[
    '{"references":[{"reference":"INQ-2026-0001","grade":"Grade 1","academic_year":"2026/2027"}],"child_name":"X"}',
    '{"references":[{"reference":"INQ-2026-0001","grade":"Grade 1","academic_year":"2026/2027","health":"x"}]}',
    '{"references":[{"reference":"INQ-26-1","grade":"Grade 1","academic_year":"2026/2027"}]}',
    '{"references":[{"reference":"APP-2026-0001","grade":"Grade 1","academic_year":"2026/2027"}]}',
    '{"references":[]}',
    '{"references":[{"reference":"INQ-2026-0001","grade":"Grade 1","academic_year":"2026/2027"}],"family_matched":true}'];
begin
  for i in 1 .. array_length(bad, 1) loop
    ok := true;
    begin
      insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params)
      values ('inquiry:' || gen_random_uuid(), 'inquiry_parent', 'p@example.test', array[gen_random_uuid()], bad[i]);
    exception when check_violation then ok := false; end;
    if ok then raise exception 'bad params % accepted', i; end if;
  end loop;
  begin
    insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params)
    values ('inquiry:' || gen_random_uuid(), 'inquiry_staff', 'staff@example.test', array[gen_random_uuid()],
      '{"references":[{"reference":"INQ-2026-0001","grade":"Grade 1","academic_year":"2026/2027"}]}');
    raise exception 'staff row with an address accepted';
  exception when check_violation then null; end;
  begin
    insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params)
    values ('inquiry:' || gen_random_uuid(), 'inquiry_parent', null, array[gen_random_uuid()],
      '{"references":[{"reference":"INQ-2026-0001","grade":"Grade 1","academic_year":"2026/2027"}]}');
    raise exception 'parent row without an address accepted';
  exception when check_violation then null; end;
end $$;

-- probe: E17 service_role claim and mark: only due rows are claimed, once; a wrong claim token records nothing; sent, retry back-off, the sixth failure, an immediate failure and a lapsed lease
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
create temp table ids (k text, id uuid);
grant select on ids to public;
insert into ids select 'due1', pg_temp.row('pending', 'a@example.test');
insert into ids select 'due2', pg_temp.row('pending', 'b@example.test');
insert into ids select 'due3', pg_temp.row('pending', 'c@example.test');
insert into ids select 'later', pg_temp.row('pending', 'd@example.test');
update public.admissions_email_outbox set next_attempt_at = now() + interval '1 hour' where id = (select id from ids where k = 'later');
insert into ids select 'sent', pg_temp.row('sent', 'e@example.test');
insert into ids select 'failed', pg_temp.row('failed', 'f@example.test');
insert into ids select 'supp', pg_temp.row('suppressed', 'g@example.test');
insert into ids select 'stale', pg_temp.row('sending', 'h@example.test');
insert into ids select 'stale6', pg_temp.row('sending', 'i@example.test');
update public.admissions_email_outbox set claimed_at = now() - interval '6 minutes', attempts = 2
  where id = (select id from ids where k = 'stale');
update public.admissions_email_outbox set claimed_at = now() - interval '6 minutes', attempts = 6
  where id = (select id from ids where k = 'stale6');
create temp table claimed (id uuid, kind text, recipient_email text, params jsonb, claim_token uuid, attempts integer);
grant select, insert on claimed to public;
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
insert into claimed select * from public.claim_admissions_emails(50, 1000);
do $$ declare cr record; begin
  if (select array_agg(i.k order by i.k) from claimed c join ids i on i.id = c.id)
     is distinct from array['due1', 'due2', 'due3', 'stale'] then
    raise exception 'claimed %', (select array_agg(i.k) from claimed c join ids i on i.id = c.id);
  end if;
  if exists (select 1 from public.claim_admissions_emails(50, 1000)) then raise exception 'claimed twice'; end if;
  if (select attempts from claimed c join ids i on i.id = c.id and i.k = 'stale') <> 3 then raise exception 'lease attempt'; end if;
  select c.* into cr from claimed c join ids i on i.id = c.id and i.k = 'due1';
  if public.mark_admissions_email_result(cr.id, gen_random_uuid(), 'sent', null, 200, 'msg') then raise exception 'wrong token recorded'; end if;
  if not public.mark_admissions_email_result(cr.id, cr.claim_token, 'sent', null, 200, 'msg-1') then raise exception 'sent not recorded'; end if;
  if public.mark_admissions_email_result(cr.id, cr.claim_token, 'sent', null, 200, 'msg-1') then raise exception 'recorded twice'; end if;
  select c.* into cr from claimed c join ids i on i.id = c.id and i.k = 'due2';
  perform public.mark_admissions_email_result(cr.id, cr.claim_token, 'retry', 'network', null, null);
  select c.* into cr from claimed c join ids i on i.id = c.id and i.k = 'due3';
  perform public.mark_admissions_email_result(cr.id, cr.claim_token, 'failed', 'invalid_recipient', 422, null);
end $$;
reset role;
do $$ begin
  if not exists (select 1 from public.admissions_email_outbox o join ids i on i.id = o.id and i.k = 'due1'
                 where o.status = 'sent' and o.provider_message_id = 'msg-1' and o.sent_at is not null and o.claim_token is null) then
    raise exception 'sent row wrong';
  end if;
  if (select last_success_at from public.admissions_email_worker) is null then raise exception 'no last success'; end if;
  if not exists (select 1 from public.admissions_email_outbox o join ids i on i.id = o.id and i.k = 'due2'
                 where o.status = 'pending' and o.attempts = 1 and o.last_error_class = 'network'
                   and o.next_attempt_at between now() + interval '50 seconds' and now() + interval '70 seconds') then
    raise exception 'retry back-off wrong';
  end if;
  if not exists (select 1 from public.admissions_email_outbox o join ids i on i.id = o.id and i.k = 'due3'
                 where o.status = 'failed' and o.last_http_status = 422) then
    raise exception 'immediate failure wrong';
  end if;
  if not exists (select 1 from public.admissions_email_outbox o join ids i on i.id = o.id and i.k = 'stale6'
                 where o.status = 'failed' and o.last_error_class = 'timeout' and o.claim_token is null) then
    raise exception 'lapsed last lease not failed';
  end if;
  if exists (select 1 from public.admissions_email_outbox o join ids i on i.id = o.id
             where i.k in ('later', 'sent', 'failed', 'supp') and o.status = 'sending') then
    raise exception 'claimed a row that was not due';
  end if;
end $$;

-- probe: E18 service_role: retries back off 1, 5, 15, 60, 240 minutes and the sixth failure marks the row failed
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select set_config('tcs.id', pg_temp.row('pending', 'retry@example.test')::text, true);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare c record; i integer; v_wait interval; waits interval[] := '{}'; begin
  for i in 1 .. 6 loop
    reset role;
    update public.admissions_email_outbox set next_attempt_at = now() - interval '1 second' where id = current_setting('tcs.id')::uuid;
    set local role service_role;
    select * into c from public.claim_admissions_emails(1, 1000);
    if c.id is null then raise exception 'not claimed on attempt %', i; end if;
    perform public.mark_admissions_email_result(c.id, c.claim_token, 'retry', 'provider_error', 503, null);
    reset role;
    select next_attempt_at - now() into v_wait from public.admissions_email_outbox where id = c.id and status = 'pending';
    set local role service_role;
    waits := waits || date_trunc('minute', v_wait + interval '30 seconds');
  end loop;
  reset role;
  if waits[1:5] is distinct from array[interval '1 minute', interval '5 minutes', interval '15 minutes',
                                       interval '60 minutes', interval '240 minutes'] then
    raise exception 'waits %', waits;
  end if;
  if (select status || '/' || attempts from public.admissions_email_outbox where id = current_setting('tcs.id')::uuid)
     <> 'failed/6' then
    raise exception 'sixth failure did not fail the row';
  end if;
end $$;

-- probe: E19 service_role: the daily ceiling counts the last 24 hours; at the ceiling nothing is claimed and the worker row says so
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
select pg_temp.row('sent', 'x@example.test', now() - interval '1 hour') from generate_series(1, 2);
select pg_temp.row('sent', 'x@example.test', now() - interval '30 hours') from generate_series(1, 5);
select pg_temp.row('pending', 'y@example.test') from generate_series(1, 3);
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ declare n integer; begin
  select count(*) into n from public.claim_admissions_emails(50, 2);
  if n <> 0 then raise exception 'claimed % at the ceiling', n; end if;
  reset role;
  if (select ceiling_reached_at from public.admissions_email_worker) is null then raise exception 'ceiling not recorded'; end if;
  set local role service_role;
  select count(*) into n from public.claim_admissions_emails(50, 3);
  if n <> 1 then raise exception 'claimed % with room for 1', n; end if;
  reset role;
  if (select last_run_at from public.admissions_email_worker) is null then raise exception 'no last run'; end if;
end $$;

-- probe: E20 service_role reads the worker secret, the same value as Vault
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.s', public.admissions_worker_secret(), true);
reset role;
do $$ begin
  if current_setting('tcs.s') is distinct from
     (select decrypted_secret from vault.decrypted_secrets where name = 'admissions_worker_secret') then
    raise exception 'secret differs';
  end if;
end $$;

-- probe: E21 housekeeping: purges old used or cleaned uploads, keeps a reservation that may hold a file and anything recent, and keeps outbox rows inside retention
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
insert into public.application_upload_sessions (id, token_hash, created_at, expires_at, closed_at) values
  ('12000000-0000-4000-8000-000000000101', repeat('a', 64), now() - interval '32 days', now() - interval '31 days', now() - interval '31 days'),
  ('12000000-0000-4000-8000-000000000102', repeat('b', 64), now() - interval '32 days', now() - interval '31 days', null),
  ('12000000-0000-4000-8000-000000000103', repeat('c', 64), now() - interval '30 days', now() - interval '29 days', null);
insert into public.application_upload_reservations (session_id, document_type, extension, expires_at, created_at, consumed_at, cleaned_at, cleanup_claimed_at) values
  ('12000000-0000-4000-8000-000000000101', 'application_fee_proof', 'pdf', now() - interval '31 days', now() - interval '31 days', now() - interval '31 days', null, null),
  ('12000000-0000-4000-8000-000000000101', 'previous_report', 'pdf', now() - interval '31 days', now() - interval '31 days', null, now() - interval '30 days', now() - interval '30 days'),
  ('12000000-0000-4000-8000-000000000102', 'application_fee_proof', 'pdf', now() - interval '31 days', now() - interval '31 days', null, null, null),
  ('12000000-0000-4000-8000-000000000103', 'application_fee_proof', 'pdf', now() - interval '29 days', now() - interval '29 days', now() - interval '29 days', null, null);
create temp table ids (k text, id uuid);
insert into ids select 'sent91', pg_temp.row('sent', 'o@example.test', now() - interval '91 days');
insert into ids select 'sent89', pg_temp.row('sent', 'o@example.test', now() - interval '89 days');
insert into ids select 'failed181', pg_temp.row('failed', 'o@example.test', now() - interval '181 days');
insert into ids select 'failed179', pg_temp.row('failed', 'o@example.test', now() - interval '179 days');
insert into ids select 'supp181', pg_temp.row('suppressed', 'o@example.test', now() - interval '181 days');
insert into ids select 'pending200', pg_temp.row('pending', 'o@example.test', now() - interval '200 days');
-- as role:
reset role;
select set_config('request.jwt.claims', '', true);
do $$ declare r jsonb; begin
  r := public.purge_admissions_housekeeping();
  if (r ->> 'reservations')::int <> 2 or (r ->> 'sessions')::int <> 1 or (r ->> 'emails')::int <> 3 then
    raise exception 'counts %', r;
  end if;
  if (select array_agg(id::text order by id) from public.application_upload_sessions
      where id::text like '12000000-0000-4000-8000-0000000001%')
     is distinct from array['12000000-0000-4000-8000-000000000102', '12000000-0000-4000-8000-000000000103'] then
    raise exception 'wrong sessions kept';
  end if;
  if (select count(*) from public.application_upload_reservations
      where session_id in ('12000000-0000-4000-8000-000000000102', '12000000-0000-4000-8000-000000000103')) <> 2 then
    raise exception 'a reservation that may hold a file was purged';
  end if;
  if (select array_agg(k order by k) from ids where exists (select 1 from public.admissions_email_outbox o where o.id = ids.id))
     is distinct from array['failed179', 'pending200', 'sent89'] then
    raise exception 'wrong outbox rows kept';
  end if;
end $$;

-- probe: E22 the four cron jobs are scheduled; the kick does nothing without a URL, nothing when no email is due, and queues one call with the secret header when one is
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.row(status, recipient, created, kind) inserts one valid
-- outbox row and returns its id.
create function pg_temp.row(p_status text default 'pending', p_recipient text default 'row@example.test',
  p_created timestamptz default now(), p_kind text default 'inquiry_parent', p_app uuid default null)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.admissions_email_outbox
    (event_key, kind, recipient_email, application_ids, params, status, created_at, sent_at,
     claim_token, claimed_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), p_kind,
    case when p_kind like '%_parent' then p_recipient end,
    array[coalesce(p_app, gen_random_uuid())],
    jsonb_build_object('references', jsonb_build_array(jsonb_build_object(
      'reference', 'INQ-2026-9001', 'grade', 'Grade 1', 'academic_year', '2026/2027'))),
    p_status, p_created, case when p_status = 'sent' then p_created end,
    case when p_status = 'sending' then gen_random_uuid() end,
    case when p_status = 'sending' then now() end, now() - interval '1 second')
  returning id into v_id;
  return v_id;
end $f$;
-- as role:
reset role;
select set_config('request.jwt.claims', '', true);
do $$ declare n0 bigint; begin
  if (select array_agg(jobname || '|' || schedule || '|' || command order by jobname) from cron.job where jobname like 'admissions-%')
     is distinct from array[
       'admissions-housekeeping|0 3 * * *|select public.purge_admissions_housekeeping()',
       'admissions-mail|* * * * *|select public._admissions_worker_kick(''mail'')',
       'admissions-settle-offers|7 * * * *|select public.settle_expired_offers()',
       'admissions-upload-sweep|*/15 * * * *|select public._admissions_worker_kick(''sweep'')'] then
    raise exception 'jobs %', (select array_agg(jobname || ' ' || schedule) from cron.job);
  end if;
  select count(*) into n0 from net.http_request_queue;
  if public._admissions_worker_kick('mail') or public._admissions_worker_kick('sweep') then raise exception 'kicked without a URL'; end if;
  begin
    perform public.set_admissions_worker_url('http://worker.example.test/functions/v1/admissions-worker');
    raise exception 'plain http to a public host accepted';
  exception when check_violation then null; end;
  perform public.set_admissions_worker_url('http://kong:8000/functions/v1/admissions-worker');
  if public._admissions_worker_kick('mail') then raise exception 'kicked with nothing due'; end if;
  perform pg_temp.row('pending', 'due@example.test');
  if not public._admissions_worker_kick('mail') then raise exception 'not kicked with an email due'; end if;
  if not public._admissions_worker_kick('sweep') then raise exception 'sweep not kicked'; end if;
  if (select count(*) from net.http_request_queue) <> n0 + 2 then raise exception 'calls not queued'; end if;
  if not exists (select 1 from net.http_request_queue q
                 where q.url = 'http://kong:8000/functions/v1/admissions-worker'
                   and q.headers ->> 'x-admissions-worker-secret' =
                       (select decrypted_secret from vault.decrypted_secrets where name = 'admissions_worker_secret')) then
    raise exception 'call has no secret header';
  end if;
end $$;

-- probe: E23 service_role application that advances an enquiry: one parent email with the APP reference, the staff alert says inquiry_advanced, no name stored
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- Fixture: pg_temp.ipayload(emails) is a valid two-child enquiry with one
-- guardian per email.
create function pg_temp.ipayload(p_emails text[]) returns jsonb language plpgsql as $f$
declare v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_intake_open = true where id = 1;
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('referral_source', 'website', 'guardians', v_g,
    'students', jsonb_build_array(
      jsonb_build_object('full_name', 'NAME-SENTINEL First', 'date_of_birth', '2019-02-03', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
        'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      jsonb_build_object('full_name', 'NAME-SENTINEL Second', 'date_of_birth', '2023-05-14',
        'prior_schooling', 'not_yet_in_school', 'grade_id', (select id from public.admissions_grades where name = 'Nursery 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September')));
end $f$;-- Fixture: pg_temp.afx(emails, child, dob) builds an open switch, a live
-- upload session with a stored fee proof, and a valid payload with one
-- guardian per email; pg_temp.asub(b) submits it as the caller.
create function pg_temp.afx(p_emails text[], p_child text default 'Outbox Child',
  p_dob date default date '2018-05-01', p_grade text default 'Grade 3')
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_id uuid; v_p text;
  v_g jsonb := '[]'; e text; i integer := 0;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_sid, 'application_fee_proof', 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
  insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
  foreach e in array p_emails loop
    i := i + 1;
    v_g := v_g || jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Guardian' || i,
      'relationship', case when i = 1 then 'mother' else 'father' end, 'religion', 'Christian',
      'address', '1 Probe Road', 'town_city', 'Accra', 'phone', '+23359000000' || i, 'email', e));
  end loop;
  return jsonb_build_object('token', v_tok,
    'sniffed', jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf')),
    'payload', jsonb_build_object(
      'guardians', v_g,
      'student', jsonb_build_object('full_name', p_child, 'date_of_birth', p_dob::text, 'gender', 'female',
        'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
        'grade_id', (select id from public.admissions_grades where name = p_grade)::text,
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      'campus_id', (select id from public.branches where name = 'Main')::text,
      'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
      'health_info', jsonb_build_object('has_medical_conditions', true, 'medical_conditions_details', 'HEALTH-SENTINEL asthma'),
      'documents', jsonb_build_array(jsonb_build_object('document_type', 'application_fee_proof',
        'reservation_id', v_id, 'path', v_p)),
      'declaration_signature_name', 'Guardian One', 'declaration_agreed', true));
end $f$;
create function pg_temp.asub(b jsonb) returns text language sql as
  $f$ select public.submit_application(b -> 'payload', b ->> 'token', b -> 'sniffed') $f$;
create temp table fx (k text, b jsonb);
grant select on fx to public;
select set_config('tcs.p', pg_temp.ipayload(array['advance@example.test'])::text, true);
select set_config('tcs.inq', (public.submit_inquiry(current_setting('tcs.p')::jsonb))[1], true);
insert into fx select 'a', pg_temp.afx(array['advance@example.test'], 'NAME-SENTINEL First', date '2019-02-03', 'Grade 1');
-- as role:
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select set_config('tcs.ref', pg_temp.asub(b), true) from fx where k = 'a';
reset role;
do $$ declare v_ref text := current_setting('tcs.ref'); begin
  if not exists (select 1 from public.applications where inquiry_reference = current_setting('tcs.inq')
                 and application_reference = v_ref) then
    raise exception 'the enquiry did not advance';
  end if;
  if (select array_agg(kind || '|' || coalesce(recipient_email, '-') order by kind) from public.admissions_email_outbox
      where params -> 'references' -> 0 ->> 'reference' = v_ref)
     is distinct from array['application_parent|advance@example.test', 'application_staff|-'] then
    raise exception 'rows wrong';
  end if;
  if not exists (select 1 from public.admissions_email_outbox where kind = 'application_staff'
                 and params -> 'references' -> 0 ->> 'reference' = v_ref
                 and params -> 'family_matched' = 'true'::jsonb and params ->> 'outcome' = 'inquiry_advanced') then
    raise exception 'staff alert outcome wrong';
  end if;
  if exists (select 1 from public.admissions_email_outbox o where row_to_json(o)::text like '%SENTINEL%') then
    raise exception 'a name was stored';
  end if;
end $$;
