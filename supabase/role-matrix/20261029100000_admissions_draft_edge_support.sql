-- Probes for 20261029100000_admissions_draft_edge_support (admissions
-- slice 10, checkpoint C2; docs/admissions/PORT-PLAN.md, slice 10): the
-- limit refusals carry DETAIL draft_limit (the live-draft caps, with the
-- generic wording that never mentions saved applications) or
-- draft_email_limit (the resume email caps); a resume email that is no
-- longer needed is marked expired by the link function and so never counts
-- as a failed resume email; grants and the anon count are unchanged.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261029100000_admissions_draft_edge_support.sql

-- probe: L1 the three re-created functions keep their grants; the count stays 170
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text; n integer; begin
  foreach f in array array['public.create_application_draft(text, jsonb, integer, boolean)',
      'public.issue_application_draft_link(uuid, uuid)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% grants wrong', f;
    end if;
  end loop;
  f := 'public._enqueue_application_draft_email(uuid)';
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception '% is executable by an API role', f;
  end if;
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
end $$;
-- as role:
select 1;

-- probe: L2 the refusal DETAILs: draft_limit for both live-draft caps with the generic wording, draft_email_limit for the resume email caps
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.refusal(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text; v_msg text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail, v_msg = message_text;
  return v_state || '|' || coalesce(v_detail, '') || '|' || v_msg;
end $f$;
do $$ declare t text; r text; generic constant text := 'We could not save your application right now. Please contact the school office.';
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  -- Per address: 3 live drafts.
  insert into public.application_drafts (email, data, consented_at, expires_at)
  select 'full@example.test', '{}', now(), now() + interval '1 day' from generate_series(1, 3);
  r := pg_temp.refusal($q$select public.create_application_draft('full@example.test', '{}', 0, true)$q$);
  if r <> 'TCS29|draft_limit|' || generic or r ~* 'saved|draft application|already' then
    raise exception 'per address: %', r;
  end if;
  -- Across everyone: 2,000 live drafts.
  insert into public.application_drafts (email, data, consented_at, expires_at)
  select 'many' || n || '@example.test', '{}', now(), now() + interval '1 day' from generate_series(1, 1997) n;
  if pg_temp.refusal($q$select public.create_application_draft('new@example.test', '{}', 0, true)$q$)
     <> 'TCS29|draft_limit|' || generic then
    raise exception 'global cap';
  end if;
  delete from public.application_drafts where email like 'many%' or email = 'full@example.test';

  -- A resume email cap: 3 per address per day.
  t := public.create_application_draft('mail@example.test', '{}', 0, true) ->> 'token';
  perform public.save_application_draft(t, '{}', 0, 1, true);
  perform public.save_application_draft(t, '{}', 0, 2, true);
  if pg_temp.refusal(format('select public.save_application_draft(%L, %L, 0, 3, true)', t, '{}'))
     not like 'TCS29|draft_email_limit|Too many emails%' then
    raise exception 'address cap detail';
  end if;
  -- The lifetime cap.
  update public.admissions_email_outbox set created_at = now() - interval '2 days' where recipient_email = 'mail@example.test';
  update public.application_drafts set resume_emails = 10 where email = 'mail@example.test';
  if pg_temp.refusal(format('select public.save_application_draft(%L, %L, 0, 3, true)', t, '{}'))
     not like 'TCS29|draft_email_limit|This link can''t be emailed again%' then
    raise exception 'lifetime cap detail';
  end if;
  -- The same save without the email goes through.
  perform public.save_application_draft(t, '{"campusId": "kept"}', 0, 3, false);
  if (select data from public.application_drafts where email = 'mail@example.test') <> '{"campusId": "kept"}' then
    raise exception 'save without the email failed';
  end if;
end $$;
-- as role:
select 1;

-- probe: L3 while public applications are closed, a claimed resume email is marked expired by the link function; the health summary counts it in neither failed nor draft_failed
-- expect: Manager,Auditor
do $$ declare c record; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  perform public.create_application_draft('closed@example.test', '{}', 0, true);
  update public.admissions_settings set public_applications_open = false where id = 1;
  select * into c from public.claim_admissions_emails(10, 100) where kind = 'draft_resume';
  if public.issue_application_draft_link(c.id, c.claim_token) is distinct from '{"status": "expired"}' then
    raise exception 'not expired';
  end if;
  if (select status from public.admissions_email_outbox where id = c.id) <> 'expired' then raise exception 'row not expired'; end if;
end $$;
-- as role:
do $$ declare h record; begin
  select * into h from public.get_admissions_email_health();
  if (h.failed, h.expired, h.draft_failed) is distinct from (0, 0, 0) then raise exception 'counts %', h; end if;
end $$;
