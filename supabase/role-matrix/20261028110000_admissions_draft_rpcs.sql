-- Probes for 20261028110000_admissions_draft_rpcs (admissions slice 10,
-- checkpoint C1; docs/admissions/PORT-PLAN.md, slice 10): the six draft
-- RPCs are service_role only and refuse every other caller even with a
-- mistaken grant; the helpers are granted to nobody. Create returns a raw
-- token once and stores only its hash; get and save round-trip the form
-- state with a version check and a sliding expiry under a 60 day ceiling;
-- unknown, expired and submitted drafts are refused with their own DETAIL;
-- the switch closes everything but delete; the resume email caps refuse
-- (and roll back the save); the live caps; the worker's send-time link;
-- the submit wrapper retires the draft atomically, keeps the upload
-- session's replay rule and refuses a second window; delete erases.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261028110000_admissions_draft_rpcs.sql
-- Run the probe files before the Edge Function integration tests (they
-- commit rows).
--
-- Value probes run their checks as postgres in setup (the service-caller
-- guard lets postgres through, as it does service_role) and pass for every
-- role. pg_temp.err(sql) returns 'SQLSTATE|DETAIL' for a statement that
-- must fail, or 'ok'.

-- probe: B1 structure: the six RPCs are definer, pinned, service_role only; the helpers are granted to nobody; the count stays 170
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text; n integer;
begin
  foreach f in array array['public.create_application_draft(text, jsonb, integer, boolean)',
      'public.get_application_draft(text)', 'public.save_application_draft(text, jsonb, integer, integer, boolean)',
      'public.delete_application_draft(text)', 'public.issue_application_draft_link(uuid, uuid)',
      'public.submit_application_from_draft(jsonb, text, jsonb, text)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% grants wrong', f;
    end if;
    if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception '% not definer', f; end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=public']) then
      raise exception '% search_path not pinned', f;
    end if;
  end loop;
  foreach f in array array['public._application_draft_id(text)',
      'public._application_draft_usable(public.application_drafts)', 'public._application_draft_check_state(jsonb, integer)',
      'public._application_draft_require_open()', 'public._enqueue_application_draft_email(uuid)',
      'public._application_draft_new_link(uuid, uuid)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=""']) then
      raise exception '% search_path not pinned', f;
    end if;
  end loop;
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
  if exists (select proname from pg_proc where proname like '%application_draft%' group by proname having count(*) > 1) then
    raise exception 'overloads';
  end if;
end $$;
-- as role:
select 1;

-- probe: B2 even with grants added by mistake, every JWT role is refused by the guard of all six RPCs
-- expect: none
update public.admissions_settings set public_applications_open = true where id = 1;
insert into public.application_drafts (id, email, data, consented_at, expires_at)
values ('12000000-0000-4000-8000-00000000b201', 'g@example.test', '{}', now(), now() + interval '30 days');
insert into public.application_draft_links (draft_id, token_hash)
values ('12000000-0000-4000-8000-00000000b201', encode(sha256(convert_to(repeat('a', 64), 'UTF8')), 'hex'));
grant execute on function public.create_application_draft(text, jsonb, integer, boolean) to anon, authenticated;
grant execute on function public.get_application_draft(text) to anon, authenticated;
grant execute on function public.save_application_draft(text, jsonb, integer, integer, boolean) to anon, authenticated;
grant execute on function public.delete_application_draft(text) to anon, authenticated;
grant execute on function public.issue_application_draft_link(uuid, uuid) to anon, authenticated;
grant execute on function public.submit_application_from_draft(jsonb, text, jsonb, text) to anon, authenticated;
-- as role:
do $$ declare n integer := 0; begin
  begin perform public.create_application_draft('x@example.test', '{}', 0, true); n := n + 1; exception when others then null; end;
  begin perform public.get_application_draft(repeat('a', 64)); n := n + 1; exception when others then null; end;
  begin perform public.save_application_draft(repeat('a', 64), '{}', 0, 1, false); n := n + 1; exception when others then null; end;
  begin perform public.delete_application_draft(repeat('a', 64)); n := n + 1; exception when others then null; end;
  begin perform public.issue_application_draft_link(gen_random_uuid(), gen_random_uuid()); n := n + 1; exception when others then null; end;
  begin perform public.submit_application_from_draft('{}', null, '[]', repeat('a', 64)); n := n + 1; exception when others then null; end;
  if n = 0 then raise exception 'all refused'; end if;
end $$;

-- probe: B3 create: a 64 hex token returned once and stored only as its hash, consent and email checked, one resume email queued with no params, refused while closed
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare r jsonb; t text; d public.application_drafts; begin
  if pg_temp.err($q$select public.create_application_draft('a@example.test', '{}', 0, true)$q$) <> 'TCS03|' then
    raise exception 'open while closed';
  end if;
  update public.admissions_settings set public_applications_open = true where id = 1;
  if pg_temp.err($q$select public.create_application_draft('a@example.test', '{}', 0, false)$q$) <> 'TCS22|consent'
     or pg_temp.err($q$select public.create_application_draft('a@example.test', '{}', 0, null)$q$) <> 'TCS22|consent'
     or pg_temp.err($q$select public.create_application_draft('not an email', '{}', 0, true)$q$) <> 'TCS22|email'
     or pg_temp.err($q$select public.create_application_draft('a@example.test', '{"health": {}}', 0, true)$q$) <> 'TCS22|draft_state'
     or pg_temp.err($q$select public.create_application_draft('a@example.test', '{}', 6, true)$q$) <> 'TCS22|draft_state' then
    raise exception 'a bad create was not refused';
  end if;
  r := public.create_application_draft('  Ama.Mensah@Example.TEST ', '{"campusId": "c1"}', 2, true);
  t := r ->> 'token';
  if t !~ '^[0-9a-f]{64}$' then raise exception 'token %', t; end if;
  if r ->> 'email_masked' <> 'a•••@e•••.test' or (r ->> 'version')::int <> 1 then raise exception 'result %', r; end if;
  select * into d from public.application_drafts;
  if d.email <> 'ama.mensah@example.test' or d.consented_at is null or d.current_step <> 2
     or d.expires_at not between now() + interval '30 days' - interval '1 minute' and now() + interval '30 days' + interval '1 minute' then
    raise exception 'row %', d;
  end if;
  if (select token_hash from public.application_draft_links) <> encode(sha256(convert_to(t, 'UTF8')), 'hex') then
    raise exception 'hash wrong';
  end if;
  if exists (select 1 from public.application_drafts x where row_to_json(x)::text like '%' || t || '%')
     or exists (select 1 from public.application_draft_links x where row_to_json(x)::text like '%' || t || '%')
     or exists (select 1 from public.admissions_email_outbox x where row_to_json(x)::text like '%' || t || '%') then
    raise exception 'raw token stored';
  end if;
  if (select array_agg(kind || '|' || recipient_email || '|' || params::text || '|' || status || '|' || cardinality(application_ids))
      from public.admissions_email_outbox where draft_id = d.id)
     is distinct from array['draft_resume|ama.mensah@example.test|{}|pending|0'] then
    raise exception 'resume email wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: B4 get and save: the state round-trips; the version must match and goes up; a save slides the expiry but never past 60 days from creation; a refused save changes nothing
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare r jsonb; t text; g jsonb; d public.application_drafts; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  t := public.create_application_draft('s@example.test', '{"campusId": "c1"}', 1, true) ->> 'token';
  g := public.get_application_draft(t);
  if g -> 'state' <> '{"campusId": "c1"}' or (g ->> 'step')::int <> 1 or (g ->> 'version')::int <> 1 then
    raise exception 'get %', g;
  end if;
  r := public.save_application_draft(t, '{"campusId": "c2", "child": {"fullName": "Kojo"}}', 3, 1, false);
  if (r ->> 'version')::int <> 2 or (r ->> 'email_queued')::boolean then raise exception 'save %', r; end if;
  if pg_temp.err(format('select public.save_application_draft(%L, %L, 3, 1, false)', t, '{"campusId": "old"}')) <> 'TCS22|draft_version'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 3, null, false)', t, '{"campusId": "old"}')) <> 'TCS22|draft_version'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 3, 2, false)', t, '{"documents": []}')) <> 'TCS22|draft_state'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 3, 2, false)', t, '{"child": {"medical": "x"}}')) <> 'TCS22|draft_state'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, -1, 2, false)', t, '{}')) <> 'TCS22|draft_state'
     or pg_temp.err(format('select public.save_application_draft(%L, jsonb_build_object(''scholarshipDetails'', repeat(''x'', 49200)), 3, 2, false)', t)) <> 'TCS22|draft_state' then
    raise exception 'a bad save was not refused';
  end if;
  g := public.get_application_draft(t);
  if g -> 'state' <> '{"campusId": "c2", "child": {"fullName": "Kojo"}}' or (g ->> 'step')::int <> 3 or (g ->> 'version')::int <> 2 then
    raise exception 'after save %', g;
  end if;
  -- Sliding: a draft made 20 days ago with 10 days left gets 30 again.
  update public.application_drafts set created_at = now() - interval '20 days', expires_at = now() + interval '10 days';
  r := public.save_application_draft(t, '{}', 0, 2, false);
  if (r ->> 'expires_at')::timestamptz < now() + interval '29 days' then raise exception 'not slid %', r; end if;
  -- Ceiling: made 50 days ago, a save gives at most 10 more days.
  update public.application_drafts set created_at = now() - interval '50 days', expires_at = now() + interval '1 day';
  r := public.save_application_draft(t, '{}', 0, 3, false);
  select * into d from public.application_drafts;
  if d.expires_at <> d.created_at + interval '60 days' then raise exception 'ceiling %', d.expires_at; end if;
end $$;
-- as role:
select 1;

-- probe: B5 unknown, malformed, expired and submitted drafts are refused by get and save with their own DETAIL; the expired message holds after the wipe
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare te text; ts text; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  te := public.create_application_draft('e@example.test', '{"campusId": "c"}', 0, true) ->> 'token';
  ts := public.create_application_draft('f@example.test', '{"campusId": "c"}', 0, true) ->> 'token';
  update public.application_drafts set created_at = now() - interval '2 days', expires_at = now() - interval '1 second' where email = 'e@example.test';
  update public.application_drafts set submitted_at = now(), data = '{}', email = null where email = 'f@example.test';
  if pg_temp.err(format('select public.get_application_draft(%L)', repeat('0', 64))) <> 'TCS22|draft_invalid'
     or pg_temp.err($q$select public.get_application_draft('not-hex')$q$) <> 'TCS22|draft_invalid'
     or pg_temp.err('select public.get_application_draft(null)') <> 'TCS22|draft_invalid'
     or pg_temp.err(format('select public.get_application_draft(%L)', upper(te))) <> 'TCS22|draft_invalid'
     or pg_temp.err(format('select public.get_application_draft(%L)', te)) <> 'TCS22|draft_expired'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 0, 1, false)', te, '{}')) <> 'TCS22|draft_expired'
     or pg_temp.err(format('select public.get_application_draft(%L)', ts)) <> 'TCS22|draft_submitted'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 0, 1, false)', ts, '{}')) <> 'TCS22|draft_submitted'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 0, 1, false)', repeat('0', 64), '{}')) <> 'TCS22|draft_invalid' then
    raise exception 'a refusal is wrong';
  end if;
  perform public.purge_admissions_housekeeping();
  if pg_temp.err(format('select public.get_application_draft(%L)', te)) <> 'TCS22|draft_expired' then
    raise exception 'expired message lost after the wipe';
  end if;
end $$;
-- as role:
select 1;

-- probe: B6 with public applications closed, get and save refuse and delete still works
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare t text; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  t := public.create_application_draft('c@example.test', '{}', 0, true) ->> 'token';
  update public.admissions_settings set public_applications_open = false where id = 1;
  if pg_temp.err(format('select public.get_application_draft(%L)', t)) <> 'TCS03|'
     or pg_temp.err(format('select public.save_application_draft(%L, %L, 0, 1, false)', t, '{}')) <> 'TCS03|' then
    raise exception 'not closed';
  end if;
  if not public.delete_application_draft(t) then raise exception 'delete'; end if;
  if exists (select 1 from public.application_drafts) or exists (select 1 from public.application_draft_links)
     or exists (select 1 from public.admissions_email_outbox where kind = 'draft_resume') then
    raise exception 'delete left rows';
  end if;
  if pg_temp.err(format('select public.delete_application_draft(%L)', t)) <> 'TCS22|draft_invalid' then
    raise exception 'a second delete';
  end if;
end $$;
-- as role:
select 1;

-- probe: B7 resume email caps: 3 per address per day (so 3 per draft, create counts), 10 per draft ever, across drafts too; a refusal is TCS29 and rolls back the save; the email always goes to the stored address
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare t text; t2 text; v integer; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  t := public.create_application_draft('m@example.test', '{}', 0, true) ->> 'token';
  perform public.save_application_draft(t, '{}', 0, 1, true);
  perform public.save_application_draft(t, '{}', 0, 2, true);
  if pg_temp.err(format('select public.save_application_draft(%L, %L, 0, 3, true)', t, '{"campusId": "new"}')) <> 'TCS29|' then
    raise exception 'fourth email for the draft allowed';
  end if;
  select version into v from public.application_drafts where email = 'm@example.test';
  if v <> 3 or (select data from public.application_drafts where email = 'm@example.test') <> '{}' then
    raise exception 'refused save was kept';
  end if;
  -- A save without an email still works.
  perform public.save_application_draft(t, '{}', 0, 3, false);
  -- A second draft for the same address: the address has had 3 today.
  update public.admissions_email_outbox set created_at = now() - interval '25 hours' where recipient_email = 'm@example.test';
  -- After a day the draft may email again, up to its lifetime 10.
  perform public.save_application_draft(t, '{}', 0, 4, true);
  update public.application_drafts set resume_emails = 10 where email = 'm@example.test';
  if pg_temp.err(format('select public.save_application_draft(%L, %L, 0, 5, true)', t, '{}')) <> 'TCS29|' then
    raise exception 'eleventh email allowed';
  end if;
  update public.application_drafts set resume_emails = 4 where email = 'm@example.test';
  perform public.save_application_draft(t, '{}', 0, 5, true);
  perform public.save_application_draft(t, '{}', 0, 6, true);
  -- The address now has 3 resume emails in 24 hours: a new draft for it is refused.
  if pg_temp.err($q$select public.create_application_draft('M@example.test', '{}', 0, true)$q$) <> 'TCS29|' then
    raise exception 'fourth email to the address allowed';
  end if;
  if (select count(*) from public.application_drafts) <> 1 then raise exception 'refused create kept a row'; end if;
  if exists (select 1 from public.admissions_email_outbox where kind = 'draft_resume' and recipient_email <> 'm@example.test') then
    raise exception 'an email went elsewhere';
  end if;
end $$;
-- as role:
select 1;

-- probe: B8 live caps: at most 3 live drafts per address (expired and submitted ones don't count) and 2,000 across everyone; both refusals use the same generic wording, which never mentions saved applications
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare v_msg text; v_global text; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_drafts (email, data, consented_at, expires_at)
  select 'l@example.test', '{}', now(), now() + interval '1 day' from generate_series(1, 3);
  insert into public.application_drafts (email, data, consented_at, created_at, expires_at)
  values ('k@example.test', '{}', now(), now() - interval '2 days', now() - interval '1 day');
  insert into public.application_drafts (email, data, consented_at, expires_at)
  select 'k@example.test', '{}', now(), now() + interval '1 day' from generate_series(1, 2);
  if pg_temp.err($q$select public.create_application_draft('l@example.test', '{}', 0, true)$q$) <> 'TCS29|' then
    raise exception 'fourth live draft allowed';
  end if;
  begin
    perform public.create_application_draft('l@example.test', '{}', 0, true);
  exception when others then
    get stacked diagnostics v_msg = message_text;
  end;
  if v_msg is distinct from 'We could not save your application right now. Please contact the school office.'
     or v_msg ~* 'saved|draft|already' then
    raise exception 'per-address refusal reveals drafts: %', v_msg;
  end if;
  perform public.create_application_draft('k@example.test', '{}', 0, true);
  insert into public.application_drafts (email, data, consented_at, expires_at)
  select 'bulk' || n || '@example.test', '{}', now(), now() + interval '1 day' from generate_series(1, 2000 - 6) n;
  if pg_temp.err($q$select public.create_application_draft('z@example.test', '{}', 0, true)$q$) <> 'TCS29|' then
    raise exception 'draft 2,001 allowed';
  end if;
  begin
    perform public.create_application_draft('z@example.test', '{}', 0, true);
  exception when others then
    get stacked diagnostics v_global = message_text;
  end;
  if v_global is distinct from v_msg then raise exception 'the two refusals differ'; end if;
  update public.application_drafts set submitted_at = now(), data = '{}', email = null where email = 'bulk1@example.test';
  perform public.create_application_draft('z@example.test', '{}', 0, true);
end $$;
-- as role:
select 1;

-- probe: B9 the send-time link: only for a claimed resume email with its claim token, one per claim, never for an expired or submitted draft, another address or while closed; the hash only; the link opens the draft; at most 61 links
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
do $$ declare t text; c record; r jsonb; tok text; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  t := public.create_application_draft('w@example.test', '{"campusId": "w"}', 0, true) ->> 'token';
  -- Not claimed yet: nothing.
  if public.issue_application_draft_link((select id from public.admissions_email_outbox where kind = 'draft_resume'),
                                         gen_random_uuid()) is not null then
    raise exception 'issued unclaimed';
  end if;
  select * into c from public.claim_admissions_emails(10, 100) where kind = 'draft_resume';
  if c.params <> '{}' or c.recipient_email <> 'w@example.test' then raise exception 'claim %', c; end if;
  if public.issue_application_draft_link(c.id, gen_random_uuid()) is not null
     or public.issue_application_draft_link(c.id, null) is not null
     or public.issue_application_draft_link(null, c.claim_token) is not null then
    raise exception 'issued with a wrong claim';
  end if;
  r := public.issue_application_draft_link(c.id, c.claim_token);
  tok := r ->> 'token';
  if tok !~ '^[0-9a-f]{64}$' or tok = t then raise exception 'token %', r; end if;
  if not exists (select 1 from public.application_draft_links
                 where token_hash = encode(sha256(convert_to(tok, 'UTF8')), 'hex') and issued_for_claim = c.claim_token) then
    raise exception 'hash not stored';
  end if;
  if exists (select 1 from public.application_draft_links x where row_to_json(x)::text like '%' || tok || '%')
     or exists (select 1 from public.admissions_email_outbox x where row_to_json(x)::text like '%' || tok || '%') then
    raise exception 'raw token stored';
  end if;
  if pg_temp.err(format('select public.issue_application_draft_link(%L, %L)', c.id, c.claim_token)) = 'ok' then
    raise exception 'a second link for one claim';
  end if;
  if public.get_application_draft(tok) -> 'state' <> '{"campusId": "w"}' then raise exception 'link does not open'; end if;
  -- A confirmation email's claim can't mint a link.
  insert into public.admissions_email_outbox (id, event_key, kind, recipient_email, application_ids, params, status, claim_token, claimed_at)
  values ('12000000-0000-4000-8000-00000000b901', 'inquiry:' || gen_random_uuid(), 'inquiry_parent', 'w@example.test',
          array[gen_random_uuid()],
          '{"references": [{"reference": "INQ-2026-0001", "grade": "Grade 1", "academic_year": "2026/2027"}]}',
          'sending', '12000000-0000-4000-8000-00000000b9c1', now());
  if public.issue_application_draft_link('12000000-0000-4000-8000-00000000b901', '12000000-0000-4000-8000-00000000b9c1') is not null then
    raise exception 'issued for another kind';
  end if;
  -- Closed, expired, submitted, link cap: nothing.
  update public.admissions_email_outbox set status = 'sending', claim_token = gen_random_uuid(), claimed_at = now()
  where id = c.id;
  select claim_token into c.claim_token from public.admissions_email_outbox where id = c.id;
  update public.admissions_settings set public_applications_open = false where id = 1;
  if public.issue_application_draft_link(c.id, c.claim_token) is not null then raise exception 'issued while closed'; end if;
  update public.admissions_settings set public_applications_open = true where id = 1;
  update public.application_drafts set created_at = now() - interval '2 days', expires_at = now() - interval '1 second';
  if public.issue_application_draft_link(c.id, c.claim_token) is not null then raise exception 'issued for expired'; end if;
  update public.application_drafts set expires_at = now() + interval '1 day';
  insert into public.application_draft_links (draft_id, token_hash)
  select (select id from public.application_drafts), encode(sha256(convert_to(n::text, 'UTF8')), 'hex') from generate_series(1, 59) n;
  if public.issue_application_draft_link(c.id, c.claim_token) is not null then raise exception 'issued a 62nd link'; end if;
  delete from public.application_draft_links where token_hash in
    (select encode(sha256(convert_to(n::text, 'UTF8')), 'hex') from generate_series(1, 59) n);
  -- The row's recipient must be the draft's own address.
  update public.admissions_email_outbox set recipient_email = 'other@example.test' where id = c.id;
  if public.issue_application_draft_link(c.id, c.claim_token) is not null then raise exception 'issued to another address'; end if;
  update public.admissions_email_outbox set recipient_email = 'w@example.test' where id = c.id;
  update public.application_drafts set submitted_at = now(), data = '{}', email = null;
  if public.issue_application_draft_link(c.id, c.claim_token) is not null then raise exception 'issued for submitted'; end if;
end $$;
-- as role:
select 1;

-- probe: B10 the submit wrapper: success returns the APP reference, retires and wipes the draft and drops its resume emails; the same session again returns the same reference and writes nothing; another session is refused; a failed submit leaves the draft; an unknown or expired draft token still submits
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
declare v_state text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || '|' || coalesce(v_detail, '');
end $f$;
-- Fixture: pg_temp.afx(email, child) builds an open switch, a live upload
-- session with a stored fee proof, and a valid payload.
create function pg_temp.afx(p_email text, p_child text)
returns jsonb language plpgsql as $f$
declare v_tok text := encode(extensions.gen_random_bytes(32), 'hex'); v_sid uuid; v_id uuid; v_p text;
begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  insert into public.application_upload_sessions (token_hash, expires_at)
  values (encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), now() + interval '6 hours') returning id into v_sid;
  insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
  values (v_sid, 'application_fee_proof', 'pdf', now() + interval '6 hours') returning id, storage_path into v_id, v_p;
  insert into storage.objects (bucket_id, name) values ('admissions-documents', v_p);
  return jsonb_build_object('token', v_tok,
    'sniffed', jsonb_build_array(jsonb_build_object('reservation_id', v_id, 'path', v_p, 'kind', 'pdf')),
    'payload', jsonb_build_object(
      'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama',
        'relationship', 'mother', 'religion', 'Christian', 'address', '1 Probe Road', 'town_city', 'Accra',
        'phone', '+233590000001', 'email', p_email)),
      'student', jsonb_build_object('full_name', p_child, 'date_of_birth', '2018-05-01', 'gender', 'female',
        'nationality', 'Ghanaian', 'address', '1 Probe Road', 'town_city', 'Accra', 'current_school', 'Little Stars',
        'current_grade_id', (select id from public.admissions_grades where name = 'Grade 2')::text,
        'grade_id', (select id from public.admissions_grades where name = 'Grade 3')::text,
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'),
      'campus_id', (select id from public.branches where name = 'Main')::text,
      'emergency_contact', jsonb_build_object('name', 'Kofi Mensah', 'relationship', 'Uncle', 'phone', '+233240000000'),
      'health_info', jsonb_build_object('has_medical_conditions', false),
      'documents', jsonb_build_array(jsonb_build_object('document_type', 'application_fee_proof',
        'reservation_id', v_id, 'path', v_p)),
      'declaration_signature_name', 'Ama Mensah', 'declaration_agreed', true));
end $f$;
create function pg_temp.wsub(b jsonb, p_draft text) returns text language sql as
  $f$ select public.submit_application_from_draft(b -> 'payload', b ->> 'token', b -> 'sniffed', p_draft) $f$;
do $$ declare t text; a jsonb; b jsonb; x jsonb; r1 text; r2 text; n integer; d public.application_drafts; begin
  update public.admissions_settings set public_applications_open = true where id = 1;
  t := public.create_application_draft('sub@example.test', '{"campusId": "s"}', 5, true) ->> 'token';
  a := pg_temp.afx('sub@example.test', 'Wrapper Child A');
  -- A failed submit (no declaration) leaves the draft as it was.
  x := jsonb_set(a, '{payload,declaration_agreed}', 'false');
  if pg_temp.err(format('select pg_temp.wsub(%L, %L)', x, t)) not like 'TCS22|%' then raise exception 'bad payload taken'; end if;
  select * into d from public.application_drafts;
  if d.submitted_at is not null or d.data <> '{"campusId": "s"}' or d.email is null then raise exception 'draft touched %', d; end if;

  if not exists (select 1 from public.admissions_email_outbox where kind = 'draft_resume' and status = 'pending') then
    raise exception 'no pending resume email to retire';
  end if;
  r1 := pg_temp.wsub(a, t);
  if r1 !~ '^APP-' then raise exception 'ref %', r1; end if;
  if exists (select 1 from public.admissions_email_outbox where kind = 'draft_resume') then
    raise exception 'resume email kept after submit';
  end if;
  select * into d from public.application_drafts;
  if d.submitted_at is null or d.data <> '{}' or d.email is not null
     or d.submitted_application_id is distinct from (select id from public.applications where application_reference = r1) then
    raise exception 'not retired %', d;
  end if;
  select count(*) into n from public.applications;
  r2 := pg_temp.wsub(a, t);
  if r2 is distinct from r1 or (select count(*) from public.applications) <> n then raise exception 'replay % %', r1, r2; end if;
  b := pg_temp.afx('sub@example.test', 'Wrapper Child B');
  if pg_temp.err(format('select pg_temp.wsub(%L, %L)', b, t)) <> 'TCS22|draft_submitted' then
    raise exception 'a second window was taken';
  end if;
  if (select count(*) from public.applications) <> n then raise exception 'second window wrote'; end if;
  if pg_temp.err(format('select public.get_application_draft(%L)', t)) <> 'TCS22|draft_submitted' then
    raise exception 'get after submit';
  end if;

  -- An unknown token, or none, submits as if there were no draft.
  if pg_temp.wsub(b, repeat('0', 64)) !~ '^APP-' then raise exception 'unknown token blocked a submit'; end if;
  if pg_temp.wsub(pg_temp.afx('sub2@example.test', 'Wrapper Child C'), null) !~ '^APP-' then
    raise exception 'no token blocked a submit';
  end if;
  -- An expired draft: the submit goes through and the draft is left to expire.
  t := public.create_application_draft('exp@example.test', '{"campusId": "e"}', 5, true) ->> 'token';
  update public.application_drafts set created_at = now() - interval '2 days', expires_at = now() - interval '1 second' where email = 'exp@example.test';
  if pg_temp.wsub(pg_temp.afx('exp@example.test', 'Wrapper Child D'), t) !~ '^APP-' then raise exception 'expired draft blocked'; end if;
  if (select submitted_at from public.application_drafts where email = 'exp@example.test') is not null then
    raise exception 'expired draft retired';
  end if;
end $$;
-- as role:
select 1;
