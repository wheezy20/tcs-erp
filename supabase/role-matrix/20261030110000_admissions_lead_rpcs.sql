-- Probes for 20261030110000_admissions_lead_rpcs (admissions slice 13,
-- checkpoint C1; docs/admissions/PORT-PLAN.md, "Slice 13 plan"):
-- capture_lead and get_lead_alert are definer, pinned, service role only
-- and refuse every JWT role even with a grant added by mistake; the
-- capture rules ported from TCS OS (source server-forced, email required,
-- consent only for true, UTM cut not refused, no echo); the 2 a day PDF
-- cap per address, kept apart from the confirmation cap; the staff alert
-- carries no contact details; the lead list (Manager and Admissions
-- Officer full, Auditor masked); lead mail claimed last and at most half
-- the ceiling; retention; a failed PDF email can be retried by a Manager.
--
-- Value probes run as postgres in the setup block (the service caller
-- guard lets postgres through, as it does service_role) and pass for
-- every role.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261030110000_admissions_lead_rpcs.sql

-- probe: R1 structure: capture_lead, get_lead_alert definer, pinned, service role only; the enqueue granted to nobody; the list for authenticated only; no overloads
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text;
begin
  foreach f in array array['public.capture_lead(text, jsonb)', 'public.get_lead_alert(uuid, uuid)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% grants wrong', f;
    end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and prosecdef
                   and proconfig @> array['search_path=public']) then
      raise exception '% not definer or not pinned', f;
    end if;
  end loop;
  foreach f in array array['public._enqueue_lead_emails(uuid)', 'public._enqueue_admissions_emails(text, uuid, uuid, text[])',
      'public.purge_admissions_housekeeping()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      raise exception '% is executable by an API role', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.claim_admissions_emails(integer, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.claim_admissions_emails(integer, integer)', 'execute')
     or not has_function_privilege('service_role', 'public.claim_admissions_emails(integer, integer)', 'execute') then
    raise exception 'claim grants wrong';
  end if;
  if has_function_privilege('anon', 'public.list_admissions_leads(integer, integer, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.list_admissions_leads(integer, integer, uuid)', 'execute') then
    raise exception 'list grants wrong';
  end if;
  if exists (select proname from pg_proc where proname in ('capture_lead', 'get_lead_alert', 'list_admissions_leads',
      '_enqueue_lead_emails', 'claim_admissions_emails', 'purge_admissions_housekeeping', 'set_admissions_public_leads')
      group by proname having count(*) > 1) then
    raise exception 'overloads';
  end if;
end $$;
-- as role:
select 1;

-- probe: R2 even with grants added by mistake, every JWT role is refused by capture_lead
-- expect: none
update public.admissions_settings set public_leads_open = true where id = 1;
grant execute on function public.capture_lead(text, jsonb) to anon, authenticated;
-- as role:
select public.capture_lead('pdf_gate_admissions_overview', '{"name": "Role Lead", "email": "role@example.test"}');

-- probe: R3 a capture makes one lead with the server's source, one pending PDF email to the lowercased address and one staff alert, both with params {} and no application; it returns only true
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare l public.admissions_leads; r jsonb;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  if public.capture_lead('pdf_gate_admissions_overview',
       '{"name": "  Ama Lead ", "email": " Ama.Lead@Example.TEST ", "phone": "+233 24 123 4567", "grade_interest": "Nursery 1"}')
     is distinct from true then
    raise exception 'capture did not return true';
  end if;
  select * into l from public.admissions_leads;
  if l.name <> 'Ama Lead' or l.email <> 'ama.lead@example.test' or l.phone <> '+233241234567'
     or l.grade_interest <> 'Nursery 1' or l.source <> 'pdf_gate_admissions_overview' then
    raise exception 'lead wrong: %', row_to_json(l);
  end if;
  if (select array_agg(kind || '|' || coalesce(recipient_email, '-') || '|' || params::text || '|' || status
                       || '|' || cardinality(application_ids) || '|' || event_key order by kind)
      from public.admissions_email_outbox where lead_id = l.id)
     is distinct from array['lead_staff|-|{}|pending|0|lead:' || l.id,
                            'pdf_gate|ama.lead@example.test|{}|pending|0|lead:' || l.id] then
    raise exception 'outbox wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: R4 the sender's source is ignored; only the PDF gate source is accepted from the caller
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  perform public.capture_lead('pdf_gate_admissions_overview',
    '{"name": "Src Lead", "email": "src@example.test", "source": "quick_interest_widget"}');
  if (select source from public.admissions_leads where email = 'src@example.test') <> 'pdf_gate_admissions_overview' then
    raise exception 'sender source used';
  end if;
  begin
    perform public.capture_lead('quick_interest_widget', '{"name": "Q", "email": "q@example.test"}');
    raise exception 'quick interest accepted';
  exception when raise_exception then
    if sqlerrm <> 'Unknown lead source' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: R5 the fields: name and email required; a malformed email, a bad phone, an overlong grade and a control character are refused with TCS22 naming the field; nothing is written
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare bad jsonb; want text; got text;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  for bad, want in values
    ('{"email": "a@example.test"}'::jsonb, 'name'),
    ('{"name": "A"}'::jsonb, 'email'),
    ('{"name": "A", "email": ""}'::jsonb, 'email'),
    ('{"name": "A", "email": "not-an-email"}'::jsonb, 'email'),
    ('{"name": "A", "email": 5}'::jsonb, 'email'),
    ('{"name": "A", "email": "a@example.test", "phone": "024 123 4567"}'::jsonb, 'phone'),
    ('{"name": "A", "email": "a@example.test", "grade_interest": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}'::jsonb, 'grade_interest'),
    (jsonb_build_object('name', E'A\u0007B', 'email', 'a@example.test'), 'name')
  loop
    got := null;
    begin
      perform public.capture_lead('pdf_gate_admissions_overview', bad);
    exception when sqlstate 'TCS22' then
      get stacked diagnostics got = pg_exception_detail;
    end;
    if got is distinct from want then raise exception '% gave %, expected %', bad, got, want; end if;
  end loop;
  if exists (select 1 from public.admissions_leads) then raise exception 'a refused capture wrote a lead'; end if;
end $$;
-- as role:
select 1;

-- probe: R6 consent is true only for the JSON boolean true
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare v jsonb; i integer := 0;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  foreach v in array array['true', 'false', '"true"', '"on"', '1', 'null', '{"x": true}']::jsonb[] loop
    i := i + 1;
    perform public.capture_lead('pdf_gate_admissions_overview',
      jsonb_build_object('name', 'C', 'email', 'c' || i || '@example.test', 'consent_to_marketing', v));
  end loop;
  perform public.capture_lead('pdf_gate_admissions_overview', '{"name": "C", "email": "c0@example.test"}');
  if (select array_agg(email order by email) from public.admissions_leads where consent_to_marketing)
     is distinct from array['c1@example.test'] then
    raise exception 'consent wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: R7 UTM: a long value is cut to 200, never refused; null, a number and absent are accepted as empty; nothing echoes it
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r boolean;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  r := public.capture_lead('pdf_gate_admissions_overview', jsonb_build_object('name', 'U', 'email', 'u@example.test',
    'utm_source', repeat('s', 300), 'utm_medium', null, 'utm_campaign', 42));
  if r is distinct from true then raise exception 'returned %', r; end if;
  if (select char_length(utm_source) || '|' || coalesce(utm_medium, '-') || '|' || coalesce(utm_campaign, '-')
      from public.admissions_leads where email = 'u@example.test') <> '200|-|-' then
    raise exception 'utm wrong';
  end if;
end $$;
-- as role:
select 1;

-- probe: R8 lead capture closed: TCS03, no lead, no email, no rate count
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  update public.admissions_settings set public_leads_open = false where id = 1;
  begin
    perform public.capture_lead('pdf_gate_admissions_overview', '{"name": "Closed", "email": "closed@example.test"}');
    raise exception 'accepted while closed';
  exception when sqlstate 'TCS03' then null;
  end;
  if exists (select 1 from public.admissions_leads) or exists (select 1 from public.admissions_email_outbox)
     or exists (select 1 from public.public_rate_limits where bucket like 'lead%') then
    raise exception 'closed capture wrote something';
  end if;
end $$;
-- as role:
select 1;

-- probe: R9 the third PDF to one address in a day (any case or spacing) is stored suppressed while the lead and its staff alert still queue; PDFs don't count toward the confirmation cap and confirmations don't count toward the PDF cap
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare e text;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  foreach e in array array['cap@example.test', ' CAP@example.test', 'Cap@Example.Test '] loop
    perform public.capture_lead('pdf_gate_admissions_overview', jsonb_build_object('name', 'Cap', 'email', e));
  end loop;
  if (select array_agg(status order by status) from public.admissions_email_outbox where kind = 'pdf_gate')
     is distinct from array['pending', 'pending', 'suppressed'] then
    raise exception 'PDF cap wrong';
  end if;
  if (select count(*) from public.admissions_leads) <> 3
     or (select count(*) from public.admissions_email_outbox where kind = 'lead_staff' and status = 'pending') <> 3 then
    raise exception 'leads or alerts missing';
  end if;
  -- Four confirmations to the same address are all pending despite the
  -- PDFs; and a new address with four confirmations still gets its PDF.
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params)
  select 'inquiry:' || gen_random_uuid(), 'inquiry_parent', a, array[gen_random_uuid()],
         '{"references": [{"reference": "INQ-2026-0001", "grade": "Nursery 1", "academic_year": "2027/2028"}]}'
  from unnest(array['cap@example.test', 'cap@example.test', 'cap@example.test',
                    'other@example.test', 'other@example.test', 'other@example.test', 'other@example.test']) a;
  if (select count(*) from public.admissions_email_outbox o
      where o.recipient_email = 'cap@example.test' and o.status <> 'suppressed'
        and o.kind in ('inquiry_parent', 'application_parent')) <> 3 then
    raise exception 'setup';
  end if;
  perform public.capture_lead('pdf_gate_admissions_overview', '{"name": "Other", "email": "other@example.test"}');
  if (select status from public.admissions_email_outbox where kind = 'pdf_gate' and recipient_email = 'other@example.test')
     <> 'pending' then
    raise exception 'confirmations counted toward the PDF cap';
  end if;
end $$;
-- as role:
select 1;

-- probe: R9b the confirmation cap counts only confirmations: two PDFs and a resume email to an address leave all 4 confirmations for a family
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare i integer;
begin
  update public.admissions_settings set public_leads_open = true, public_intake_open = true where id = 1;
  perform public.capture_lead('pdf_gate_admissions_overview', '{"name": "Fam", "email": "fam@example.test"}');
  perform public.capture_lead('pdf_gate_admissions_overview', '{"name": "Fam", "email": "fam@example.test"}');
  for i in 1..4 loop
    perform public.submit_inquiry(jsonb_build_object(
      'referral_source', 'website',
      'guardians', jsonb_build_array(jsonb_build_object('surname', 'Mensah', 'first_name', 'Ama', 'relationship', 'mother',
        'religion', 'Christian', 'address', '1 Ring Road', 'town_city', 'Accra', 'phone', '+233590000000',
        'email', 'fam@example.test')),
      'students', jsonb_build_array(jsonb_build_object('full_name', 'Kofi Mensah ' || i, 'date_of_birth', '2019-02-03',
        'current_school', 'Little Stars', 'current_grade_id', (select id from public.admissions_grades where name = 'Kindergarten 2'),
        'grade_id', (select id from public.admissions_grades where name = 'Grade 1'),
        'academic_year', '2026/2027', 'month_of_enrollment', 'September'))));
  end loop;
  if (select count(*) from public.admissions_email_outbox
      where kind = 'inquiry_parent' and recipient_email = 'fam@example.test' and status = 'pending') <> 4 then
    raise exception 'PDFs used up confirmations';
  end if;
end $$;
-- as role:
select 1;

-- probe: R10 get_lead_alert: the claim holder gets grade, consent, source and the lead id, and no name, email or phone; a wrong token, a PDF row, an unclaimed row give null
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare c record; a jsonb; v_pdf uuid; v_staff uuid; v_tok uuid;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  perform public.capture_lead('pdf_gate_admissions_overview',
    '{"name": "Alert Lead", "email": "alert@example.test", "phone": "+233241234567", "grade_interest": "KG 1", "consent_to_marketing": true}');
  select id into v_staff from public.admissions_email_outbox where kind = 'lead_staff';
  if public.get_lead_alert(v_staff, gen_random_uuid()) is not null then raise exception 'unclaimed row read'; end if;
  for c in select * from public.claim_admissions_emails(10, 60) loop
    if c.kind = 'lead_staff' then v_tok := c.claim_token; else v_pdf := c.id; end if;
  end loop;
  a := public.get_lead_alert(v_staff, v_tok);
  if a is null or (a - 'lead_id') <> '{"grade_interest": "KG 1", "consent_to_marketing": true, "source": "pdf_gate_admissions_overview"}'::jsonb
     or (a ->> 'lead_id')::uuid <> (select id from public.admissions_leads) then
    raise exception 'alert wrong: %', a;
  end if;
  if a::text ~* 'alert@|Alert Lead|241234567' then raise exception 'alert carries contact details'; end if;
  if public.get_lead_alert(v_staff, gen_random_uuid()) is not null
     or public.get_lead_alert(v_pdf, (select claim_token from public.admissions_email_outbox where id = v_pdf)) is not null then
    raise exception 'alert read without its claim';
  end if;
end $$;
-- as role:
select 1;

-- probe: R10b even with grants added by mistake, every JWT role is refused by get_lead_alert
-- expect: none
grant execute on function public.get_lead_alert(uuid, uuid) to anon, authenticated;
-- as role:
select public.get_lead_alert(gen_random_uuid(), gen_random_uuid());

-- probe: R11 the lead list: Manager and Admissions Officer see email and phone in full, Auditor masked; p_lead_id shows one lead; newest first with a total; the limit is capped
-- expect: Manager,Auditor,Admissions Officer
insert into public.admissions_leads (id, name, email, phone, source, consent_to_marketing, created_at) values
  ('13000000-0000-4000-8000-000000000b11', 'List Lead', 'listed@example.test', '+233241234567', 'pdf_gate_admissions_overview', true, now()),
  ('13000000-0000-4000-8000-000000000b12', 'Older Lead', 'older@example.test', null, 'pdf_gate_admissions_overview', false, now() - interval '1 day');
-- as role:
do $$ declare r record; full_view boolean := public.has_role(array['Manager', 'Admissions Officer']);
begin
  select * into r from public.list_admissions_leads(1, 0, null);
  if r.id <> '13000000-0000-4000-8000-000000000b11' or r.total_count <> 2 or r.name <> 'List Lead' then
    raise exception 'order or total wrong';
  end if;
  if full_view and (r.email <> 'listed@example.test' or r.phone <> '+233241234567') then
    raise exception 'full view masked';
  end if;
  if not full_view and (r.email <> 'l•••@e•••.test' or r.phone <> '+233•••67') then
    raise exception 'Auditor not masked: % %', r.email, r.phone;
  end if;
  if (select count(*) from public.list_admissions_leads(200, 0, '13000000-0000-4000-8000-000000000b12')) <> 1
     or (select count(*) from public.list_admissions_leads(100000, -5, null)) <> 2 then
    raise exception 'filter or bounds wrong';
  end if;
end $$;

-- probe: R12 claim: other kinds go first; lead mail never exceeds half the daily ceiling, counting lead mail already sent; held back lead mail sets the ceiling marker
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare k text[]; i integer;
begin
  update public.admissions_settings set public_leads_open = true where id = 1;
  for i in 1..3 loop
    perform public.capture_lead('pdf_gate_admissions_overview', jsonb_build_object('name', 'Claim', 'email', 'claim' || i || '@example.test'));
  end loop;
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, created_at, next_attempt_at)
  values ('inquiry:' || gen_random_uuid(), 'inquiry_staff', null, array[gen_random_uuid()],
          '{"references": [{"reference": "INQ-2026-0001", "grade": "Nursery 1", "academic_year": "2027/2028"}]}',
          now() + interval '1 second', now() + interval '1 second');
  update public.admissions_email_outbox set next_attempt_at = now() - interval '1 minute' where kind = 'inquiry_staff';
  -- Ceiling 9: room 9, lead share 4. The inquiry alert comes first, then 4 of the 6 lead rows.
  select array_agg(c.kind) into k from public.claim_admissions_emails(50, 9) c;
  if k[1] <> 'inquiry_staff' or cardinality(k) <> 5 then raise exception 'first claim %', k; end if;
  -- The 4 claimed lead rows count while sending: nothing more for leads.
  update public.admissions_email_worker set ceiling_reached_at = null where id;
  if exists (select 1 from public.claim_admissions_emails(50, 9)) then raise exception 'lead share exceeded'; end if;
  if (select ceiling_reached_at from public.admissions_email_worker where id) is null then
    raise exception 'held back lead mail not flagged';
  end if;
  -- With a higher ceiling, the rest come.
  if (select count(*) from public.claim_admissions_emails(50, 20)) <> 2 then raise exception 'rest not claimed'; end if;
end $$;
-- as role:
select 1;

-- probe: R13 retention: without consent kept 12 months, with consent 24 months, an unsubscribed lead goes at once; a lead whose email is being sent waits; the lead's outbox rows go with it; the key is reported
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r jsonb;
begin
  insert into public.admissions_leads (name, email, source, consent_to_marketing, created_at, bulk_email_unsubscribed_at) values
    ('Keep 1', 'k1@example.test', 'pdf_gate_admissions_overview', false, now() - interval '11 months', null),
    ('Gone 1', 'g1@example.test', 'pdf_gate_admissions_overview', false, now() - interval '13 months', null),
    ('Keep 2', 'k2@example.test', 'pdf_gate_admissions_overview', true, now() - interval '23 months', null),
    ('Gone 2', 'g2@example.test', 'pdf_gate_admissions_overview', true, now() - interval '25 months', null),
    ('Gone 3', 'g3@example.test', 'pdf_gate_admissions_overview', true, now() - interval '1 day', now()),
    ('Busy', 'busy@example.test', 'pdf_gate_admissions_overview', false, now() - interval '13 months', null);
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, lead_id)
  select 'lead:' || id, 'pdf_gate', email, '{}', '{}', id from public.admissions_leads where name <> 'Busy';
  insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, lead_id,
                                              status, claim_token, claimed_at, attempts)
  select 'lead:' || id, 'pdf_gate', email, '{}', '{}', id, 'sending', gen_random_uuid(), now(), 1
  from public.admissions_leads where name = 'Busy';
  r := public.purge_admissions_housekeeping();
  if (r ->> 'leads_deleted')::integer <> 3 then raise exception 'deleted %', r; end if;
  if (select array_agg(name order by name) from public.admissions_leads) is distinct from array['Busy', 'Keep 1', 'Keep 2'] then
    raise exception 'wrong leads kept';
  end if;
  if (select count(*) from public.admissions_email_outbox where kind = 'pdf_gate') <> 3 then
    raise exception 'outbox rows of deleted leads kept';
  end if;
  if not (r ?& array['reservations', 'sessions', 'emails', 'cron_runs', 'draft_emails', 'drafts_wiped', 'drafts_deleted']) then
    raise exception 'existing keys lost';
  end if;
end $$;
-- as role:
select 1;

-- probe: R14 a Manager can retry a failed PDF email
-- expect: Manager
insert into public.admissions_leads (id, name, email, source)
values ('13000000-0000-4000-8000-000000000b14', 'Retry Lead', 'retry@example.test', 'pdf_gate_admissions_overview');
insert into public.admissions_email_outbox (id, event_key, kind, recipient_email, application_ids, params, lead_id, status, attempts, last_error_class)
values ('13000000-0000-4000-8000-000000000e14', 'lead:13000000-0000-4000-8000-000000000b14', 'pdf_gate', 'retry@example.test',
        '{}', '{}', '13000000-0000-4000-8000-000000000b14', 'failed', 6, 'config');
-- as role:
do $$ begin
  if public.requeue_admissions_emails(array['13000000-0000-4000-8000-000000000e14'::uuid]) <> 1 then
    raise exception 'not requeued';
  end if;
end $$;

-- probe: R15 the staff email log and health show lead emails, masked, with no lead details
-- expect: Manager,Auditor
insert into public.admissions_leads (id, name, email, source)
values ('13000000-0000-4000-8000-000000000b15', 'Log Lead', 'logged@example.test', 'pdf_gate_admissions_overview');
insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params, lead_id, status, attempts)
values ('lead:13000000-0000-4000-8000-000000000b15', 'pdf_gate', 'logged@example.test', '{}', '{}',
        '13000000-0000-4000-8000-000000000b15', 'failed', 6),
       ('lead:13000000-0000-4000-8000-000000000b15', 'lead_staff', null, '{}', '{}',
        '13000000-0000-4000-8000-000000000b15', 'pending', 0);
-- as role:
do $$ begin
  if (select array_agg(kind || '|' || coalesce(recipient_masked, '-') order by kind) from public.list_admissions_emails())
     is distinct from array['lead_staff|-', 'pdf_gate|l•••@e•••.test'] then
    raise exception 'log wrong';
  end if;
  if (select failed || '/' || waiting from public.get_admissions_email_health()) <> '1/1' then
    raise exception 'health wrong';
  end if;
end $$;
