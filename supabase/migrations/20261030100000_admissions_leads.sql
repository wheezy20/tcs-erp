-- Admissions slice 13, migration 1 of 2: leads from the marketing site's
-- PDF gate, the lead switch, and the outbox changes the two lead emails
-- need (docs/admissions/PORT-PLAN.md, "Slice 13 plan"; approved by Eyram
-- with changes on 2026-10-21, D-13a to D-13p).
--
-- A lead is a person who asked for the Admissions Overview and Fees PDF on
-- tcsch.edu.gh. It is not an admissions submission: it has its own switch
-- (public_leads_open), independent of the inquiries and applications
-- switches, because the marketing site points at the ERP weeks before
-- intake opens. The switch is closed by default.
--
-- Staff see leads only through list_admissions_leads (migration 2):
-- Manager and Admissions Officer in full, Auditor with email and phone
-- masked (D-13h). No API role has any privilege on the table and there is
-- no policy.
--
-- Unsubscribe: only the timestamp is kept (D-13i). Retention (D-13l) is
-- 12 months without marketing consent, 24 months with it, and a lead with
-- bulk_email_unsubscribed_at set is deleted by the next housekeeping run.
--
-- Everything here is service_role only or callable by nobody, apart from
-- the Manager switch setter (authenticated). The anon-executable count
-- stays at 170.

-- ------------------------------------------------------------ the numbers

alter table public.public_rate_limits drop constraint public_rate_limits_bucket_check;
alter table public.public_rate_limits add constraint public_rate_limits_bucket_check
  check (bucket in ('submit_ip', 'submit_global', 'inquiry_email',
                    'application_email', 'upload_ip', 'upload_global',
                    'draft_ip', 'draft_global', 'draft_use_ip',
                    'lead_ip', 'lead_global'));

-- Unchanged apart from the lead rows (D-13j, starting values set by Eyram
-- 2026-10-21). Counted buckets (stored as hits):
--   lead_ip         20 PDF requests per hour per IP hash (before Turnstile)
--   lead_global     40 per day across everyone (after Turnstile)
-- Cap (never stored as hits; the table check refuses the name):
--   lead_email_day  2 PDF emails per address in 24 hours, counted apart
--                   from email_recipient_day, so lead mail can't use up a
--                   family's confirmation emails. Extras are stored as
--                   suppressed and the response doesn't change.
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
    ('draft_email_recipient_day', 3, interval '1 day'),
    ('lead_ip', 20, interval '1 hour'),
    ('lead_global', 40, interval '1 day'),
    ('lead_email_day', 2, interval '1 day')
  ) as r (bucket, max_count, window_length)
  where r.bucket = p_bucket;
$$;

-- The Edge Function's entry point, now with the two lead buckets.
create or replace function public.check_public_rate_limit(p_bucket text, p_key_hash text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_public_service_caller();
  if p_bucket in ('submit_ip', 'upload_ip', 'draft_ip', 'draft_use_ip', 'lead_ip') then
    if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
      raise exception '% needs a 64-character lowercase hex key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, p_key_hash);
  elsif p_bucket in ('submit_global', 'upload_global', 'draft_global', 'lead_global') then
    if p_key_hash is not null then
      raise exception '% takes no key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, 'global');
  end if;
  raise exception 'Unknown rate limit bucket: %', p_bucket;
end;
$$;

-- How long a lead is kept (D-13l, decided by Eyram 2026-10-21). One place,
-- so a change is a one-function migration. The privacy policy states the
-- same numbers. An unsubscribed lead is deleted by the next run, whatever
-- its age.
create or replace function public._admissions_lead_retention(
  out without_consent interval,
  out with_consent interval
)
language sql
immutable
set search_path = ''
as $$
  select interval '12 months', interval '24 months';
$$;

-- A phone number for an Auditor: the first four and last two characters.
create or replace function public._admissions_mask_phone(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_phone is null then null
    when char_length(p_phone) < 8 then '•••'
    else left(p_phone, 4) || '•••' || right(p_phone, 2)
  end;
$$;

-- ------------------------------------------------------------ the table

create table public.admissions_leads (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 255 and name !~ '[[:cntrl:]]'),
  email text check (
    email is null
    or (char_length(email) <= 254 and email = lower(email)
        and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
  ),
  phone text check (phone is null or (char_length(phone) between 1 and 32 and phone !~ '[[:cntrl:]]')),
  grade_interest text check (
    grade_interest is null or (char_length(grade_interest) between 1 and 50 and grade_interest !~ '[[:cntrl:]]')),
  -- Set by the server, never by the sender (D-13d: the PDF gate only).
  source text not null check (source in ('pdf_gate_admissions_overview')),
  -- Only an explicit true from the sender is honoured.
  consent_to_marketing boolean not null default false,
  utm_source text check (char_length(utm_source) <= 200),
  utm_medium text check (char_length(utm_medium) <= 200),
  utm_campaign text check (char_length(utm_campaign) <= 200),
  bulk_email_unsubscribed_at timestamptz,
  -- The capture time. The TCS OS import (a reviewed statement after
  -- cutover) sets the original date, which retention counts from.
  created_at timestamptz not null default now(),
  constraint admissions_leads_contact_check check (email is not null or phone is not null),
  constraint admissions_leads_pdf_gate_email_check check (
    source <> 'pdf_gate_admissions_overview' or email is not null)
);

create index admissions_leads_created_idx on public.admissions_leads (created_at);

alter table public.admissions_leads enable row level security;
revoke all on table public.admissions_leads from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ the switch

alter table public.admissions_settings
  add column public_leads_open boolean not null default false;

comment on column public.admissions_settings.public_leads_open is
  'Lead capture switch (slice 13). capture_lead refuses while false. Independent of the two intake switches.';

create or replace function public.set_admissions_public_leads(p_open boolean)
returns public.admissions_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_row public.admissions_settings;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can open or close lead capture';
  end if;
  if p_open is null then
    raise exception 'Choose whether lead capture is open or closed';
  end if;
  select * into v_row from public.admissions_settings where id = 1 for update;
  if v_row.public_leads_open = p_open then
    raise exception 'Lead capture is already %', case when p_open then 'open' else 'closed' end;
  end if;
  update public.admissions_settings set public_leads_open = p_open where id = 1
  returning * into v_row;
  return v_row;
end;
$$;

-- Re-created from 20261021100000 with a third field branch. The action is
-- still admissions_settings_changed, so the audit action list is unchanged.
create or replace function public.audit_admissions_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
begin
  if v_actor is null then
    return null;
  end if;
  if old.offer_ttl_days is distinct from new.offer_ttl_days then
    v_before := v_before || jsonb_build_object('offer_ttl_days', old.offer_ttl_days);
    v_after := v_after || jsonb_build_object('offer_ttl_days', new.offer_ttl_days);
  end if;
  if old.public_intake_open is distinct from new.public_intake_open then
    v_before := v_before || jsonb_build_object('public_intake_open', old.public_intake_open);
    v_after := v_after || jsonb_build_object('public_intake_open', new.public_intake_open);
  end if;
  if old.public_applications_open is distinct from new.public_applications_open then
    v_before := v_before || jsonb_build_object('public_applications_open', old.public_applications_open);
    v_after := v_after || jsonb_build_object('public_applications_open', new.public_applications_open);
  end if;
  if old.public_leads_open is distinct from new.public_leads_open then
    v_before := v_before || jsonb_build_object('public_leads_open', old.public_leads_open);
    v_after := v_after || jsonb_build_object('public_leads_open', new.public_leads_open);
  end if;
  if v_after = '{}'::jsonb then
    return null;
  end if;
  v_branch := (select branch_id from public.staff where id = v_actor);
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'admissions_settings_changed', 'admissions_settings', new.id::text,
    v_before, v_after
  );
  return null;
end;
$$;

-- ------------------------------------------------------------ outbox

-- Two lead kinds: pdf_gate (the PDF to the lead's address) and lead_staff
-- (the staff alert). Both name the lead, no application, and carry params
-- exactly {}: the worker reads what the alert shows at send time through
-- get_lead_alert (migration 2), so no outbox row holds lead details.
alter table public.admissions_email_outbox
  add column lead_id uuid references public.admissions_leads (id) on delete cascade;

create index admissions_email_outbox_lead_id_idx on public.admissions_email_outbox (lead_id)
  where lead_id is not null;

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_kind_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_kind_check
  check (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff', 'draft_resume',
                  'pdf_gate', 'lead_staff'));

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_event_key_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_event_key_check check (
  (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff')
   and event_key ~ '^(inquiry|application):[0-9a-f-]{36}$')
  or (kind = 'draft_resume' and event_key ~ '^draft:[0-9a-f-]{36}:[0-9]{1,3}$')
  or (kind in ('pdf_gate', 'lead_staff') and event_key ~ '^lead:[0-9a-f-]{36}$')
);

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_application_ids_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_application_ids_check check (
  (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff')
   and cardinality(application_ids) between 1 and 20)
  or (kind in ('draft_resume', 'pdf_gate', 'lead_staff') and cardinality(application_ids) = 0)
);

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_recipient_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_recipient_check check (
  (kind in ('inquiry_parent', 'application_parent', 'draft_resume', 'pdf_gate') and recipient_email is not null)
  or (kind in ('inquiry_staff', 'application_staff', 'lead_staff') and recipient_email is null)
);

alter table public.admissions_email_outbox add constraint admissions_email_outbox_lead_check
  check ((kind in ('pdf_gate', 'lead_staff')) = (lead_id is not null));

-- Unchanged apart from the first branch: the lead kinds carry no params.
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
  if p_kind in ('draft_resume', 'pdf_gate', 'lead_staff') then
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

-- ------------------------------------------------------------ the PDF

-- The Admissions Overview and Fees PDF, uploaded once by Eyram (never in
-- any repo) at pdf-gate/admissions-overview-and-fees.pdf. Private, PDF
-- only, 10 MB. No policy for any role: only the worker reads it, with the
-- service role key, from a path it holds as a constant.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('admissions-attachments', 'admissions-attachments', false, 10485760, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- ------------------------------------------------------------ grants

-- create or replace keeps the grants of check_public_rate_limit (service
-- role only), the rule and the params check (nobody) and the audit trigger
-- function (nobody).
revoke execute on function public._admissions_lead_retention() from public, anon, authenticated, service_role;
revoke execute on function public._admissions_mask_phone(text) from public, anon, authenticated, service_role;
revoke execute on function public.set_admissions_public_leads(boolean) from public, anon;
grant execute on function public.set_admissions_public_leads(boolean) to authenticated;
