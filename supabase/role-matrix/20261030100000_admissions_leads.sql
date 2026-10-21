-- Probes for 20261030100000_admissions_leads (admissions slice 13,
-- checkpoint C1; docs/admissions/PORT-PLAN.md, "Slice 13 plan"): the
-- leads table has RLS and no API privilege; the helpers are granted to
-- nobody; the anon-executable count stays 170; the lead numbers; the lead
-- switch is Manager only, audited with only its own field, readable by
-- Manager and Auditor, and independent of the two intake switches; the
-- outbox takes the two lead kinds only with a lead, no application and no
-- params; a row shaped like the TCS OS import is accepted.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261030100000_admissions_leads.sql

-- probe: L1 structure: table RLS on, no policy, no privilege; helpers granted to nobody; setter for authenticated only; bucket private; the numbers; the count stays 170
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text; p text; f text; n integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.admissions_leads'::regclass) then
    raise exception 'RLS off';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'admissions_leads') then
    raise exception 'admissions_leads has a policy';
  end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      if has_table_privilege(r, 'public.admissions_leads', p) then raise exception '% % granted', r, p; end if;
    end loop;
  end loop;
  foreach f in array array['public._admissions_lead_retention()', 'public._admissions_mask_phone(text)',
      'public._public_rate_limit_rule(text)', 'public._admissions_email_params_ok(text, jsonb)',
      'public.audit_admissions_settings()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.set_admissions_public_leads(boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.set_admissions_public_leads(boolean)', 'execute') then
    raise exception 'setter grants wrong';
  end if;
  if not exists (select 1 from storage.buckets where id = 'admissions-attachments' and not public
                 and file_size_limit = 10485760 and allowed_mime_types = array['application/pdf']) then
    raise exception 'bucket wrong';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and qual like '%admissions-attachments%') then
    raise exception 'bucket has a policy';
  end if;
  if (select string_agg(b || '=' || r2.max_count || '/' || r2.window_length, ',' order by b)
      from unnest(array['lead_ip', 'lead_global', 'lead_email_day']) b, public._public_rate_limit_rule(b) r2)
     is distinct from 'lead_email_day=2/1 day,lead_global=40/1 day,lead_ip=20/01:00:00' then
    raise exception 'lead numbers wrong';
  end if;
  if (select without_consent || '/' || with_consent from public._admissions_lead_retention())
     is distinct from '1 year/2 years' then
    raise exception 'retention wrong';
  end if;
  if (select public_leads_open from public.admissions_settings where id = 1) then
    raise exception 'lead switch open by default';
  end if;
  select count(*) into n from pg_proc p2 join pg_namespace s on s.oid = p2.pronamespace
  where s.nspname = 'public' and has_function_privilege('anon', p2.oid, 'execute');
  if n <> 170 then raise exception 'anon-executable count is %, expected 170', n; end if;
end $$;
-- as role:
select 1;

-- probe: L2 only a Manager can open lead capture
-- expect: Manager
-- as role:
select public.set_admissions_public_leads(true);

-- probe: L3 a flip writes exactly one admissions_settings_changed row holding only public_leads_open; a no-change call raises; a service role change writes no row
-- expect: Manager
do $$ declare n integer;
begin
  n := (select count(*) from public.audit_log where action = 'admissions_settings_changed');
  update public.admissions_settings set public_leads_open = true where id = 1;
  update public.admissions_settings set public_leads_open = false where id = 1;
  if (select count(*) from public.audit_log where action = 'admissions_settings_changed') <> n then
    raise exception 'a change without a staff caller wrote an audit row';
  end if;
end $$;
-- as role:
do $$ declare n integer; a public.audit_log;
begin
  n := (select count(*) from public.audit_log where action = 'admissions_settings_changed');
  perform public.set_admissions_public_leads(true);
  if (select count(*) from public.audit_log where action = 'admissions_settings_changed') <> n + 1 then
    raise exception 'not exactly one audit row';
  end if;
  select * into a from public.audit_log where action = 'admissions_settings_changed' order by occurred_at desc, id desc limit 1;
  if a.before is distinct from '{"public_leads_open": false}'::jsonb
     or a.after is distinct from '{"public_leads_open": true}'::jsonb then
    raise exception 'audit row wrong: % %', a.before, a.after;
  end if;
  begin
    perform public.set_admissions_public_leads(true);
    raise exception 'no-change call accepted';
  exception when raise_exception then
    if sqlerrm = 'no-change call accepted' then raise; end if;
  end;
end $$;

-- probe: L4 the lead switch is readable by Manager and Auditor only, like the other admissions settings
-- expect: Manager,Auditor
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_settings where public_leads_open is not null) then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L5 independence: leads open with both intake switches closed captures; leads closed with both intake switches open refuses with TCS03 and writes nothing
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare n integer;
begin
  update public.admissions_settings
  set public_leads_open = true, public_intake_open = false, public_applications_open = false where id = 1;
  if not public.capture_lead('pdf_gate_admissions_overview', '{"name": "Lead One", "email": "l5@example.test"}') then
    raise exception 'capture refused while open';
  end if;
  update public.admissions_settings
  set public_leads_open = false, public_intake_open = true, public_applications_open = true where id = 1;
  n := (select count(*) from public.admissions_leads);
  begin
    perform public.capture_lead('pdf_gate_admissions_overview', '{"name": "Lead Two", "email": "l5b@example.test"}');
    raise exception 'capture accepted while closed';
  exception when sqlstate 'TCS03' then null;
  end;
  if (select count(*) from public.admissions_leads) <> n then raise exception 'closed capture wrote a lead'; end if;
end $$;
-- as role:
select 1;

-- probe: L6 no JWT role can read a lead directly
-- expect: none
insert into public.admissions_leads (name, email, source)
values ('Seen Lead', 'seen@example.test', 'pdf_gate_admissions_overview');
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_leads) then raise exception 'no rows'; end if;
end $$;

-- probe: L7 outbox constraints: lead kinds need a lead, no application, params {} and the right recipient; other kinds can't carry a lead; deleting a lead removes its outbox rows
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare l uuid := '13000000-0000-4000-8000-000000000a07'; bad text; refused integer := 0;
begin
  insert into public.admissions_leads (id, name, email, source)
  values (l, 'Lead Seven', 'l7@example.test', 'pdf_gate_admissions_overview');
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, lead_id)
  values ('lead:' || l, 'pdf_gate', 'l7@example.test', '{}', '{}', l),
         ('lead:' || l, 'lead_staff', null, '{}', '{}', l);
  foreach bad in array array[
    format($q$('lead:%s', 'pdf_gate', 'l7@example.test', '{}', '{}', null)$q$, l),
    format($q$('lead:%s', 'pdf_gate', null, '{}', '{}', '%s')$q$, l, l),
    format($q$('lead:%s', 'lead_staff', 'l7@example.test', '{}', '{}', '%s')$q$, l, l),
    format($q$('lead:%s', 'pdf_gate', 'x@example.test', '{%s}', '{}', '%s')$q$, l, l, l),
    format($q$('lead:%s', 'pdf_gate', 'y@example.test', '{}', '{"references": []}', '%s')$q$, l, l),
    format($q$('inquiry:%s', 'pdf_gate', 'z@example.test', '{}', '{}', '%s')$q$, l, l),
    format($q$('inquiry:%s', 'inquiry_staff', null, '{%s}', '{"references": [{"reference": "INQ-2026-0001", "grade": "Nursery 1", "academic_year": "2027/2028"}]}', '%s')$q$, l, l, l)
  ] loop
    begin
      execute 'insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, lead_id) values ' || bad;
      raise exception 'outbox took %', bad;
    exception when check_violation then refused := refused + 1;
    end;
  end loop;
  if refused <> 7 then raise exception 'refused %', refused; end if;
  delete from public.admissions_leads where id = l;
  if exists (select 1 from public.admissions_email_outbox where lead_id = l) then
    raise exception 'outbox rows outlived the lead';
  end if;
end $$;
-- as role:
select 1;

-- probe: L8 the TCS OS import shape: a direct insert with an original created_at and consent true is accepted and makes no outbox row; the source must be the PDF gate; a PDF gate lead needs an email; control characters are refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare refused integer := 0; bad text;
begin
  insert into public.admissions_leads (name, email, phone, source, consent_to_marketing, created_at)
  values ('Imported Lead', 'imported@example.test', null, 'pdf_gate_admissions_overview', true, '2026-08-14 10:00+00');
  if (select created_at from public.admissions_leads where email = 'imported@example.test') <> '2026-08-14 10:00+00'
     or not (select consent_to_marketing from public.admissions_leads where email = 'imported@example.test') then
    raise exception 'import shape not kept';
  end if;
  if exists (select 1 from public.admissions_email_outbox where kind in ('pdf_gate', 'lead_staff')) then
    raise exception 'a direct insert queued email';
  end if;
  foreach bad in array array[
    $q$('A', 'a@example.test', null, 'quick_interest_widget')$q$,
    $q$('A', null, '+233241234567', 'pdf_gate_admissions_overview')$q$,
    $q$(E'A\nB', 'a@example.test', null, 'pdf_gate_admissions_overview')$q$,
    $q$('A', 'A@Example.test', null, 'pdf_gate_admissions_overview')$q$,
    $q$('', 'a@example.test', null, 'pdf_gate_admissions_overview')$q$
  ] loop
    begin
      execute 'insert into public.admissions_leads (name, email, phone, source) values ' || bad;
      raise exception 'table took %', bad;
    exception when check_violation then refused := refused + 1;
    end;
  end loop;
  if refused <> 5 then raise exception 'refused %', refused; end if;
end $$;
-- as role:
select 1;
