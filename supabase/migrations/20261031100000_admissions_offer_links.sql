-- Admissions slice 11, checkpoint C1, part 1 of 2: the schema for the
-- offer email and the public offer page (docs/admissions/PORT-PLAN.md,
-- "Slice 11 plan"; decided by Eyram 2026-10-22).
--
-- 1. Offer links. The parent's link is minted by the worker at send time
--    (the slice 10 pattern): application_offer_links holds only the
--    sha256 of each token, one link per emailed guardian (D-11b). A link
--    works only while it is unrevoked and of the offer's current
--    generation; every generate, reset and resend starts a new generation,
--    which kills every older link. No API role has a privilege on the
--    table and RLS has no policy.
-- 2. application_offers: token_hash becomes nullable and is cleared on
--    every row, retiring the staff copy link (D-11d). Hosted holds only
--    test offers (reported by Eyram 2026-10-22). New columns
--    link_generation and response_source, each with an explicit column
--    grant; application_offer_status shows both.
-- 3. Outbox kinds offer (to a guardian) and offer_staff (the alert when a
--    parent responds, D-11k), with offer_id cascading with the offer.
-- 4. Rate limit rows: offer_ip and offer_global (counted buckets for the
--    two public actions) and offer_links_day (3 link sends per offer per
--    day, a cap, D-11h).
-- 5. Audit: actions application_offer_link_sent and
--    application_offer_responded (40 to 42), and actor_id may be null for
--    application_offer_responded only (D-11i, the schema change gate,
--    approved by Eyram 2026-10-22).
--
-- Nothing here is granted to anon. The anon-executable count stays 170.

-- ------------------------------------------------------------ offers

alter table public.application_offers alter column token_hash drop not null;
update public.application_offers set token_hash = null where token_hash is not null;

alter table public.application_offers
  -- Starts at 0; each send (generate, reset, resend) moves it up by one.
  add column link_generation integer not null default 0 check (link_generation between 0 and 100000),
  -- Who gave the response: the parent through the link, or staff
  -- (a reply by phone, or a correction). Null while no response is held.
  add column response_source text check (response_source in ('offer_link', 'staff')),
  add constraint application_offers_response_source_response_check
    check (response_source is null or response in ('accepted', 'declined'));

grant select (link_generation, response_source) on table public.application_offers to authenticated;

-- Re-created from 20261016100000 with the two columns added at the end.
create or replace view public.application_offer_status with (security_invoker = true) as
select
  o.id,
  o.application_id,
  o.sent_at,
  o.expires_at,
  o.response,
  o.responded_at,
  case
    when o.response = 'pending' and o.expires_at is not null and clock_timestamp() > o.expires_at
      then 'expired'
    else o.response
  end as effective_response,
  o.response_source,
  o.link_generation
from public.application_offers o;

-- ------------------------------------------------------------ links

create table public.application_offer_links (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.application_offers (id) on delete cascade,
  -- sha256 hex of the raw token, which exists only in the email.
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  generation integer not null check (generation between 1 and 100000),
  -- The outbox row and the claim it was minted for; one link per claim.
  outbox_id uuid not null,
  issued_for_claim uuid not null unique,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz
);

create index application_offer_links_offer_id_idx on public.application_offer_links (offer_id);
create index application_offer_links_outbox_id_idx on public.application_offer_links (outbox_id);

alter table public.application_offer_links enable row level security;
revoke all on table public.application_offer_links from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ outbox

alter table public.admissions_email_outbox
  add column offer_id uuid references public.application_offers (id) on delete cascade;

create index admissions_email_outbox_offer_id_idx on public.admissions_email_outbox (offer_id)
  where offer_id is not null;

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_kind_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_kind_check
  check (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff', 'draft_resume',
                  'pdf_gate', 'lead_staff', 'offer', 'offer_staff'));

-- offer:<offer id>:<generation>
alter table public.admissions_email_outbox drop constraint admissions_email_outbox_event_key_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_event_key_check check (
  (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff')
   and event_key ~ '^(inquiry|application):[0-9a-f-]{36}$')
  or (kind = 'draft_resume' and event_key ~ '^draft:[0-9a-f-]{36}:[0-9]{1,3}$')
  or (kind in ('pdf_gate', 'lead_staff') and event_key ~ '^lead:[0-9a-f-]{36}$')
  or (kind in ('offer', 'offer_staff') and event_key ~ '^offer:[0-9a-f-]{36}:[1-9][0-9]{0,5}$')
);

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_application_ids_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_application_ids_check check (
  (kind in ('inquiry_parent', 'inquiry_staff', 'application_parent', 'application_staff')
   and cardinality(application_ids) between 1 and 20)
  or (kind in ('draft_resume', 'pdf_gate', 'lead_staff') and cardinality(application_ids) = 0)
  or (kind in ('offer', 'offer_staff') and cardinality(application_ids) = 1)
);

alter table public.admissions_email_outbox drop constraint admissions_email_outbox_recipient_check;
alter table public.admissions_email_outbox add constraint admissions_email_outbox_recipient_check check (
  (kind in ('inquiry_parent', 'application_parent', 'draft_resume', 'pdf_gate', 'offer') and recipient_email is not null)
  or (kind in ('inquiry_staff', 'application_staff', 'lead_staff', 'offer_staff') and recipient_email is null)
);

alter table public.admissions_email_outbox add constraint admissions_email_outbox_offer_check
  check ((kind in ('offer', 'offer_staff')) = (offer_id is not null));

-- Re-created from 20261030100000 with the two offer kinds:
--   offer        references: exactly one APP reference with its grade and
--                academic year (as application_parent)
--   offer_staff  the same, plus application_id (for the ERP link) and the
--                response, accepted or declined
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
  if p_kind in ('inquiry_parent', 'application_parent', 'inquiry_staff', 'offer') then
    v_allowed := array['references'];
  elsif p_kind = 'application_staff' then
    v_allowed := array['references', 'family_matched', 'outcome'];
  elsif p_kind = 'offer_staff' then
    v_allowed := array['references', 'application_id', 'response'];
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
  if p_kind = 'offer_staff' then
    if jsonb_typeof(p_params -> 'application_id') is distinct from 'string'
       or (p_params ->> 'application_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or jsonb_typeof(p_params -> 'response') is distinct from 'string'
       or (p_params ->> 'response') not in ('accepted', 'declined') then
      return false;
    end if;
  end if;
  return true;
end;
$$;

-- The maximum age of a queued offer email (D-11g): 7 days, and never past
-- the offer's own expiry (applied by the claim and by issue_offer_link).
create or replace function public._admissions_offer_email_max_age()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '7 days';
$$;

revoke execute on function public._admissions_offer_email_max_age() from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ rate limits

alter table public.public_rate_limits drop constraint public_rate_limits_bucket_check;
alter table public.public_rate_limits add constraint public_rate_limits_bucket_check
  check (bucket in ('submit_ip', 'submit_global', 'inquiry_email',
                    'application_email', 'upload_ip', 'upload_global',
                    'draft_ip', 'draft_global', 'draft_use_ip',
                    'lead_ip', 'lead_global', 'offer_ip', 'offer_global'));

-- Unchanged apart from the offer rows (D-11h, Eyram 2026-10-22). Counted:
--   offer_ip         30 offer page requests (read or answer) per hour per
--                    IP hash, checked before any token lookup
--   offer_global     300 per hour across everyone
-- Cap (never stored as hits; the table check refuses the name):
--   offer_links_day  3 link sends (generate, reset, resend) per offer in
--                    24 hours
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
    ('lead_email_day', 2, interval '1 day'),
    ('offer_ip', 30, interval '1 hour'),
    ('offer_global', 300, interval '1 hour'),
    ('offer_links_day', 3, interval '1 day')
  ) as r (bucket, max_count, window_length)
  where r.bucket = p_bucket;
$$;

-- The Edge Function's entry point, now with the two offer buckets.
create or replace function public.check_public_rate_limit(p_bucket text, p_key_hash text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_public_service_caller();
  if p_bucket in ('submit_ip', 'upload_ip', 'draft_ip', 'draft_use_ip', 'lead_ip', 'offer_ip') then
    if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
      raise exception '% needs a 64-character lowercase hex key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, p_key_hash);
  elsif p_bucket in ('submit_global', 'upload_global', 'draft_global', 'lead_global', 'offer_global') then
    if p_key_hash is not null then
      raise exception '% takes no key', p_bucket;
    end if;
    return public._public_rate_limit_hit(p_bucket, 'global');
  end if;
  raise exception 'Unknown rate limit bucket: %', p_bucket;
end;
$$;

-- ------------------------------------------------------------ audit

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action = any (array[
  'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
  'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
  'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
  'admissions_capabilities_changed',
  'staff_advance_proposed', 'staff_advance_approved', 'staff_advance_rejected',
  'staff_advance_change_proposed', 'staff_advance_change_approved',
  'staff_advance_change_rejected',
  'employees_imported',
  'application_stage_changed', 'application_document_status_changed',
  'application_decision_changed', 'admissions_capacity_changed',
  'application_offer_changed', 'admissions_settings_changed',
  'application_grade_corrected', 'admissions_academic_year_changed',
  'staff_number_issued', 'staff_number_retired', 'position_staff_class_changed',
  'application_offer_link_sent', 'application_offer_responded'
]));

-- A parent answering through the offer link has no staff identity. That
-- one action, and no other, may be written without an actor (D-11i).
alter table public.audit_log alter column actor_id drop not null;
alter table public.audit_log add constraint audit_log_actor_check
  check (actor_id is not null or action = 'application_offer_responded');
