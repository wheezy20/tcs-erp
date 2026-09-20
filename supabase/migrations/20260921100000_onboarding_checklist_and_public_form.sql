-- HR expansion, Phase 3 of 5: onboarding checklist + the tokenized public
-- onboarding form. See docs/CONSTRAINTS.md's "HR expansion beyond
-- payroll" section for the phase plan and docs/DESIGN.md for the design
-- rationale behind every decision below (that file is the one to read
-- for *why*; this migration is deliberately comment-heavy anyway because
-- this is the first anon-writable path in the whole app).
--
-- One deviation from the original plan, based on the real
-- ACCEPTED_STAFF_ONBOARDING tracker (not just the Apps Script source
-- code): the 18 checklist items split into two genuinely different
-- kinds, not one flat list —
--   * MANUAL items: a human does something with no other record in this
--     system (issue a handbook, run a welcome session, verify an
--     uploaded document). Checkbox-toggled via toggle_onboarding_task().
--   * DERIVED items: the fact already lives elsewhere in this schema
--     (an Active pay config, a linked staff login). Never manually
--     toggleable — a trigger recomputes them whenever their source of
--     truth changes. onboarding_checklist_items.is_derived +
--     .derivation_key drive this; deactivating a derived item just
--     removes it from the completion check (the trigger has nothing to
--     compute for an inactive item).
-- Two of the four named derived signals collapsed into one item each:
-- "Bank Details Form" and "Payroll Added" are literally the same
-- predicate (an Active employee_pay_config row exists) under two names —
-- keeping them as two catalog rows would double-count one fact with zero
-- added information. Same reasoning applied to "Staff Email Created" /
-- "Staff ID Issued": both were specified against the same compound
-- condition (a linked staff row exists AND employees.school_email is
-- set) — this schema has no way to distinguish "email created" from "ID
-- issued" as separate signals, so tracking them as two rows that will
-- always flip together is the same redundancy. Collapsed to two derived
-- catalog items total, not four. 14 manual + 2 derived = 16 catalog rows
-- for an original 18 named signals — the count drops because of this
-- collapse, not because anything was dropped.

-- pgcrypto is already enabled in this project (under `extensions`,
-- confirmed against the running instance) — `digest()`/`gen_random_bytes()`
-- need it on the search_path explicitly inside a `set search_path = public`
-- function, since that clause replaces the session's default path.
create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- 1. onboarding_checklist_items: the school-editable catalog.
-- =====================================================================
create table public.onboarding_checklist_items (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  requires_document boolean not null default false,
  is_derived boolean not null default false,
  derivation_key text check (derivation_key in ('pay_config_active', 'staff_account_created')),
  position integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check ((is_derived and derivation_key is not null) or (not is_derived and derivation_key is null)),
  check (not (is_derived and requires_document))
);
create index onboarding_checklist_items_position_idx on public.onboarding_checklist_items (position);

-- Deliberately NOT run through uppercase_ref_list_name() the way
-- positions/departments are — these are read as sentence-like labels in
-- the checklist UI ("Welcome Session"), not short codes matched against
-- anything elsewhere, so there's no "Ama"/"AMA" drift risk to guard against.

alter table public.onboarding_checklist_items enable row level security;

create policy onboarding_checklist_items_select on public.onboarding_checklist_items
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy onboarding_checklist_items_insert on public.onboarding_checklist_items
for insert with check (public.has_role(array['Manager', 'Accountant']));
create policy onboarding_checklist_items_update on public.onboarding_checklist_items
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));
create policy onboarding_checklist_items_delete on public.onboarding_checklist_items
for delete using (public.has_role(array['Manager', 'Accountant']));

grant select, insert, update, delete on public.onboarding_checklist_items to authenticated;
grant select, insert, update, delete on public.onboarding_checklist_items to service_role;

insert into public.onboarding_checklist_items (name, requires_document, is_derived, derivation_key, position) values
  ('ID Copy', true, false, null, 0),
  ('SSNIT Card', true, false, null, 1),
  ('TIN Copy', true, false, null, 2),
  ('Academic Certs', true, false, null, 3),
  ('Passport Photos', true, false, null, 4),
  ('Guarantor Form', true, false, null, 5),
  ('Medical Clearance', true, false, null, 6),
  ('Background Check', true, false, null, 7),
  ('Welcome Session', false, false, null, 8),
  ('Campus Tour', false, false, null, 9),
  ('Introduced to Team', false, false, null, 10),
  ('Handbook Issued', false, false, null, 11),
  ('Policy Form Signed', false, false, null, 12),
  ('Biometric Enrolled', false, false, null, 13),
  ('Bank Details & Payroll Setup', false, true, 'pay_config_active', 14),
  ('Staff Email & ID Issued', false, true, 'staff_account_created', 15)
on conflict (name) do nothing;

-- =====================================================================
-- 2. employee_onboarding_tasks: per-employee state, RPC-written only
--    (same "no direct RLS write policy" pattern as employees /
--    employee_pay_config — manual toggles and derived recomputes both
--    go through functions below, never a raw client UPDATE).
-- =====================================================================
create table public.employee_onboarding_tasks (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete restrict,
  checklist_item_id uuid not null references public.onboarding_checklist_items (id) on delete restrict,
  completed boolean not null default false,
  completed_at timestamptz,
  completed_by uuid references public.staff (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (employee_id, checklist_item_id)
);
create index employee_onboarding_tasks_employee_id_idx on public.employee_onboarding_tasks (employee_id);

alter table public.employee_onboarding_tasks enable row level security;

create policy employee_onboarding_tasks_select on public.employee_onboarding_tasks
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

grant select on public.employee_onboarding_tasks to authenticated;
grant select, insert, update, delete on public.employee_onboarding_tasks to service_role;
-- No insert/update/delete grant to authenticated at all — every write
-- happens inside a SECURITY DEFINER function below.

-- =====================================================================
-- 3. employees.onboarding_completed_at — computed-never-stored's cousin:
--    computed-and-then-frozen. Set once, by trigger, when every active
--    checklist item (manual or derived) is done. Never cleared back to
--    null — a catalog item added or reactivated later, or a manual item
--    left unchecked on an old record, doesn't retroactively "unfinish"
--    someone who already onboarded.
-- =====================================================================
alter table public.employees add column onboarding_completed_at timestamptz;

-- =====================================================================
-- 4. Widen employee_documents.document_type (20260920) to the real
--    document-backed checklist item names, now that the actual 18-item
--    tracker (not just the Apps Script source) shows what's really asked
--    for. The 4 generic placeholder values ('National ID' etc.) were a
--    reasonable guess before this data existed; the 8 real names below
--    are more precise AND double as the document_type value written by
--    approve_onboarding_submission() below — the checklist item's own
--    name, no separate mapping table needed. 'Other' stays as an escape
--    hatch for ad-hoc HR uploads that don't fit an onboarding category.
-- =====================================================================
alter table public.employee_documents drop constraint employee_documents_document_type_check;
alter table public.employee_documents add constraint employee_documents_document_type_check
  check (document_type in (
    'ID Copy', 'SSNIT Card', 'TIN Copy', 'Academic Certs', 'Passport Photos',
    'Guarantor Form', 'Medical Clearance', 'Background Check', 'Other'
  ));

-- =====================================================================
-- 5. employee_onboarding_tokens — the sensitive one. Read the full
--    security note above submit_onboarding_form() below for how
--    generation / expiry / single-use fit together end to end.
-- =====================================================================
create table public.employee_onboarding_tokens (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete restrict,
  -- The raw token is NEVER stored — only its SHA-256 hash. A DB read (a
  -- Manager browsing this table, a backup, a compromised replica) can't
  -- be turned into a usable onboarding link from this column alone.
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now()
);
create index employee_onboarding_tokens_employee_id_idx on public.employee_onboarding_tokens (employee_id);

alter table public.employee_onboarding_tokens enable row level security;

create policy employee_onboarding_tokens_select on public.employee_onboarding_tokens
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

grant select on public.employee_onboarding_tokens to authenticated;
grant select, insert, update, delete on public.employee_onboarding_tokens to service_role;
-- No grant to anon at all, and no insert/update grant to authenticated —
-- generation and single-use consumption both happen inside SECURITY
-- DEFINER functions. Deliberately no anon SELECT policy either: the
-- storage upload policy below needs to check token validity, but it does
-- so through is_valid_onboarding_token() (SECURITY DEFINER, returns only
-- a boolean) rather than by granting anon any direct read on this table —
-- a raw SELECT policy for anon would work for that one purpose but would
-- also hand back employee_id / created_by / created_at for every
-- unexpired token to anyone who could enumerate them, which the boolean
-- function never does.

-- =====================================================================
-- 6. employee_onboarding_submissions — the review buffer. The public
--    form writes here (via submit_onboarding_form()), never directly to
--    employees / employee_pay_config / employee_documents. HR reviews
--    and approve_onboarding_submission() copies the safe fields across.
-- =====================================================================
create table public.employee_onboarding_submissions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete restrict,
  token_id uuid not null references public.employee_onboarding_tokens (id) on delete restrict,
  date_of_birth date,
  gender text,
  national_id text,
  personal_email text,
  emergency_contact_name text,
  emergency_contact_phone text,
  residential_address text,
  qualifications text,
  -- Banking fields are captured here for HR's reference only — approving
  -- a submission does NOT write these into employee_pay_config. That
  -- table's bank/account changes stay behind the existing Accountant-
  -- proposes / Manager-approves gate (20260909130000); auto-applying a
  -- candidate-submitted bank detail on a single Manager-or-Accountant
  -- approval would quietly weaken that two-person control for the one
  -- field it exists to protect. HR reads these off the reviewed
  -- submission and proposes the pay config the normal way.
  bank_name text,
  account_no text,
  payment_method text check (payment_method is null or payment_method in ('Bank', 'Mobile Money')),
  contract_accepted boolean not null default false,
  signature_name text,
  -- [{ "document_type": "...", "storage_path": "..." }, ...] — one entry
  -- per file the candidate uploaded straight to the private bucket
  -- before this row was created (see submit_onboarding_form()).
  uploaded_documents jsonb not null default '[]'::jsonb,
  submitted_at timestamptz not null default now(),
  review_status text not null default 'Pending Review'
    check (review_status in ('Pending Review', 'Approved', 'Rejected')),
  reviewed_by uuid references public.staff (id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text
);
create index employee_onboarding_submissions_employee_id_idx
  on public.employee_onboarding_submissions (employee_id);

alter table public.employee_onboarding_submissions enable row level security;

create policy employee_onboarding_submissions_select on public.employee_onboarding_submissions
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

grant select on public.employee_onboarding_submissions to authenticated;
grant select, insert, update, delete on public.employee_onboarding_submissions to service_role;
-- No anon grant, no authenticated write grant — submit_onboarding_form()
-- (insert) and approve/reject_onboarding_submission() (update) are the
-- only ways a row in this table is ever created or changed.

-- =====================================================================
-- 7. Derived-task recompute + completion-freeze machinery.
-- =====================================================================
create or replace function public.recompute_derived_onboarding_task(
  p_employee_id uuid, p_derivation_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_done boolean;
  v_item record;
begin
  if p_derivation_key = 'pay_config_active' then
    select exists (
      select 1 from public.employee_pay_config
      where employee_id = p_employee_id and approval_status = 'Active' and effective_to is null
    ) into v_done;
  elsif p_derivation_key = 'staff_account_created' then
    select exists (
      select 1 from public.staff s
      join public.employees e on e.id = p_employee_id
      where s.employee_id = p_employee_id and e.school_email is not null
    ) into v_done;
  else
    raise exception 'Unknown onboarding derivation key: %', p_derivation_key;
  end if;

  for v_item in
    select id from public.onboarding_checklist_items
    where is_derived and is_active and derivation_key = p_derivation_key
  loop
    insert into public.employee_onboarding_tasks (employee_id, checklist_item_id, completed, completed_at)
    values (p_employee_id, v_item.id, v_done, case when v_done then now() else null end)
    on conflict (employee_id, checklist_item_id) do update
      set completed = excluded.completed,
          completed_at = case when excluded.completed then now() else null end
      where public.employee_onboarding_tasks.completed is distinct from excluded.completed;
  end loop;
end;
$$;

-- One row per newly-Active employee, snapshotting the catalog as it
-- stands right now. A catalog item added or reactivated later does not
-- retroactively appear on an employee whose tasks were already
-- initialized — see docs/DESIGN.md for why that's an accepted scope
-- limit, not an oversight.
create or replace function public.initialize_onboarding_tasks(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.employee_onboarding_tasks (employee_id, checklist_item_id)
  select p_employee_id, i.id
  from public.onboarding_checklist_items i
  where i.is_active
  on conflict (employee_id, checklist_item_id) do nothing;

  perform public.recompute_derived_onboarding_task(p_employee_id, 'pay_config_active');
  perform public.recompute_derived_onboarding_task(p_employee_id, 'staff_account_created');
end;
$$;

create or replace function public.recompute_onboarding_completion(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.employees
  set onboarding_completed_at = now()
  where id = p_employee_id
    and onboarding_completed_at is null
    and exists (select 1 from public.employee_onboarding_tasks where employee_id = p_employee_id)
    and not exists (
      select 1 from public.employee_onboarding_tasks t
      join public.onboarding_checklist_items i on i.id = t.checklist_item_id
      where t.employee_id = p_employee_id and i.is_active and not t.completed
    );
end;
$$;

create or replace function public.trg_onboarding_task_completion_changed()
returns trigger language plpgsql as $$
begin
  perform public.recompute_onboarding_completion(new.employee_id);
  return new;
end;
$$;

create trigger employee_onboarding_tasks_completion_changed
after insert or update of completed on public.employee_onboarding_tasks
for each row execute function public.trg_onboarding_task_completion_changed();

-- Employee reaches Active -> checklist starts existing for them. Covers
-- both the normal approve_employee() transition (UPDATE) and a row
-- inserted already Active (seed data, a future importer) — the latter
-- never fires an "UPDATE OF employment_status" trigger at all, since
-- there's no prior row to transition from.
create or replace function public.trg_employee_became_active()
returns trigger language plpgsql as $$
begin
  if new.employment_status = 'Active'
     and (tg_op = 'INSERT' or old.employment_status is distinct from 'Active') then
    perform public.initialize_onboarding_tasks(new.id);
  end if;
  return new;
end;
$$;

create trigger employees_onboarding_init
after insert or update of employment_status on public.employees
for each row execute function public.trg_employee_became_active();

-- employee_pay_config changes -> "Bank Details & Payroll Setup" recompute.
create or replace function public.trg_pay_config_onboarding_recompute()
returns trigger language plpgsql as $$
begin
  perform public.recompute_derived_onboarding_task(new.employee_id, 'pay_config_active');
  return new;
end;
$$;

create trigger employee_pay_config_onboarding_recompute
after insert or update on public.employee_pay_config
for each row execute function public.trg_pay_config_onboarding_recompute();

-- staff.employee_id gets linked -> "Staff Email & ID Issued" recompute.
create or replace function public.trg_staff_onboarding_recompute()
returns trigger language plpgsql as $$
begin
  if new.employee_id is not null then
    perform public.recompute_derived_onboarding_task(new.employee_id, 'staff_account_created');
  end if;
  return new;
end;
$$;

create trigger staff_onboarding_recompute
after insert or update of employee_id on public.staff
for each row execute function public.trg_staff_onboarding_recompute();

-- employees.school_email gets set -> same recompute, the other half of
-- the compound signal.
create or replace function public.trg_employee_school_email_onboarding_recompute()
returns trigger language plpgsql as $$
begin
  perform public.recompute_derived_onboarding_task(new.id, 'staff_account_created');
  return new;
end;
$$;

create trigger employees_onboarding_email_recompute
after update of school_email on public.employees
for each row execute function public.trg_employee_school_email_onboarding_recompute();

-- Deactivating a catalog item can newly satisfy "every active item done"
-- for employees who were stuck only on that item.
create or replace function public.trg_checklist_item_deactivated()
returns trigger language plpgsql as $$
declare
  v_employee_id uuid;
begin
  if new.is_active = false and old.is_active = true then
    for v_employee_id in
      select distinct employee_id from public.employee_onboarding_tasks where checklist_item_id = new.id
    loop
      perform public.recompute_onboarding_completion(v_employee_id);
    end loop;
  end if;
  return new;
end;
$$;

create trigger onboarding_checklist_items_deactivated
after update of is_active on public.onboarding_checklist_items
for each row execute function public.trg_checklist_item_deactivated();

-- Backfill: employees already Active before this migration ran get their
-- checklist initialized now, same as if they'd just transitioned to
-- Active. This is the path that matters on a real deploy, where Active
-- employees already exist in the table when this migration runs. Under
-- local `supabase db reset`, migrations run before `seed.sql`, so this
-- loop sees zero rows here — the trigger above (now firing on INSERT
-- too) is what initializes the seeded demo employees instead, once
-- seed.sql actually inserts them.
do $$
declare v_emp record;
begin
  for v_emp in select id from public.employees where employment_status = 'Active' loop
    perform public.initialize_onboarding_tasks(v_emp.id);
  end loop;
end $$;

-- =====================================================================
-- 8. Manual-item toggle + catalog-backfill RPCs (Manager/Accountant).
-- =====================================================================
create or replace function public.toggle_onboarding_task(p_task_id uuid, p_completed boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_derived boolean;
  v_employee_id uuid;
begin
  perform public.require_finance_writer();

  select i.is_derived, t.employee_id into v_is_derived, v_employee_id
  from public.employee_onboarding_tasks t
  join public.onboarding_checklist_items i on i.id = t.checklist_item_id
  where t.id = p_task_id;

  if v_employee_id is null then
    raise exception 'Onboarding task not found.';
  end if;
  if v_is_derived then
    raise exception 'This item is tracked automatically and can''t be toggled by hand.';
  end if;

  update public.employee_onboarding_tasks
  set completed = p_completed,
      completed_at = case when p_completed then now() else null end,
      completed_by = case when p_completed then auth.uid() else null end
  where id = p_task_id;
end;
$$;

-- For employees who reached Active before this feature existed and have
-- no task rows yet (or a Manager wants to pick up a newly-added catalog
-- item on an already-onboarding employee) — a manual re-run of the same
-- snapshot initialize_onboarding_tasks() does on the Active transition.
create or replace function public.initialize_onboarding_checklist(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_finance_writer();
  perform public.initialize_onboarding_tasks(p_employee_id);
end;
$$;

-- =====================================================================
-- 9. Token generation, validation, and the public submission RPC.
--
-- SECURITY NOTE (read this before this ships) — how the first
-- anon-writable path in this app is locked down:
--
-- GENERATION: generate_onboarding_token() requires Manager/Accountant
-- (require_finance_writer()) and only for an Active employee. It mints
-- 32 bytes from gen_random_bytes() (pgcrypto's CSPRNG, not
-- pseudo-random) and returns the 64-hex-char result to the caller
-- EXACTLY ONCE. Only its SHA-256 hash is ever written to the database
-- (employee_onboarding_tokens.token_hash, unique). There is no way to
-- recover the raw token from the database afterwards, including for a
-- Manager browsing the table — the frontend must show/copy it at
-- generation time or it's gone, same as an API-key reveal-once UI.
--
-- EXPIRY: expires_at is set at generation (default 14 days, caller can
-- pass a shorter/longer p_ttl_days). Both is_valid_onboarding_token() and
-- submit_onboarding_form() check expires_at > now() on every use. An
-- expired token simply stops working; there's no separate revoke step
-- needed for staleness (though there's also no revoke RPC for an
-- unexpired token HR wants to kill early — see docs/DESIGN.md).
--
-- SINGLE-USE: enforced with a row lock, not just a used_at is null check.
-- submit_onboarding_form() does `select ... for update` on the matching
-- token row before doing anything else, then re-checks used_at is null
-- inside the same transaction before setting it. A second, concurrent
-- submission attempt for the same token blocks on the row lock until the
-- first transaction commits, then finds used_at already set and is
-- rejected — there's no window where two submissions can both pass the
-- "is this token usable" check for the same token.
--
-- STORAGE UPLOADS: candidate document uploads happen BEFORE
-- submit_onboarding_form() is called (the frontend uploads each file
-- first, collects the resulting storage paths, then submits) — so the
-- token is still unused at upload time. The storage RLS policy
-- (`onboarding_documents_anon_insert`, below) checks token validity via
-- is_valid_onboarding_token(), a SECURITY DEFINER function that returns
-- only a boolean — anon is never granted any direct read access to
-- employee_onboarding_tokens itself, so there's no way to enumerate or
-- inspect other employees' tokens through this path.
--
-- WHAT ANON CAN NEVER DO: read employee_onboarding_tokens or
-- employee_onboarding_submissions (no grant, no RLS policy for anon on
-- either); write to employees / employee_pay_config / employee_documents
-- directly (no grant); or resubmit through a used or expired token
-- (rejected inside the same transaction as the check). The only two
-- anon-reachable surfaces in the whole schema are:
--   1. `storage.objects` insert into `onboarding-documents`, gated by a
--      valid token in the object path.
--   2. Three SECURITY DEFINER functions (is_valid_onboarding_token,
--      get_onboarding_context, submit_onboarding_form), each doing its
--      own token check internally rather than relying on RLS at all.
-- =====================================================================
create or replace function public.generate_onboarding_token(
  p_employee_id uuid, p_ttl_days integer default 14
)
returns table(token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token text;
  v_expires timestamptz := now() + make_interval(days => greatest(p_ttl_days, 1));
  v_status text;
begin
  perform public.require_finance_writer();

  select employment_status into v_status from public.employees where id = p_employee_id;
  if v_status is null then
    raise exception 'Employee not found.';
  end if;
  if v_status <> 'Active' then
    raise exception 'Can only generate an onboarding link for an Active employee.';
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into public.employee_onboarding_tokens (employee_id, token_hash, expires_at)
  values (p_employee_id, encode(digest(v_token, 'sha256'), 'hex'), v_expires);

  return query select v_token, v_expires;
end;
$$;

create or replace function public.is_valid_onboarding_token(p_token text)
returns boolean
language sql
security definer
set search_path = public, extensions
stable
as $$
  select exists (
    select 1 from public.employee_onboarding_tokens
    where token_hash = encode(digest(p_token, 'sha256'), 'hex')
      and used_at is null
      and expires_at > now()
  );
$$;

create or replace function public.get_onboarding_context(p_token text)
returns table(employee_name text, employee_position text, department text, valid boolean)
language plpgsql
security definer
set search_path = public, extensions
stable
as $$
declare
  v_hash text := encode(digest(p_token, 'sha256'), 'hex');
begin
  return query
    select e.name, e.position, e.department, true
    from public.employee_onboarding_tokens t
    join public.employees e on e.id = t.employee_id
    where t.token_hash = v_hash and t.used_at is null and t.expires_at > now();

  if not found then
    return query select null::text, null::text, null::text, false;
  end if;
end;
$$;

create or replace function public.submit_onboarding_form(
  p_token text,
  p_date_of_birth date default null,
  p_gender text default null,
  p_national_id text default null,
  p_personal_email text default null,
  p_emergency_contact_name text default null,
  p_emergency_contact_phone text default null,
  p_residential_address text default null,
  p_qualifications text default null,
  p_bank_name text default null,
  p_account_no text default null,
  p_payment_method text default null,
  p_contract_accepted boolean default false,
  p_signature_name text default null,
  p_uploaded_documents jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token_hash text := encode(digest(p_token, 'sha256'), 'hex');
  v_token_id uuid;
  v_employee_id uuid;
  v_submission_id uuid;
begin
  -- Row lock first, then re-check under the lock — closes the
  -- double-submit race (see the security note above this section).
  select id, employee_id into v_token_id, v_employee_id
  from public.employee_onboarding_tokens
  where token_hash = v_token_hash and expires_at > now() and used_at is null
  for update;

  if v_token_id is null then
    raise exception 'This onboarding link is invalid, expired, or already used.';
  end if;

  if not p_contract_accepted or coalesce(trim(p_signature_name), '') = '' then
    raise exception 'Contract acceptance and a typed signature are required.';
  end if;

  update public.employee_onboarding_tokens
  set used_at = now()
  where id = v_token_id and used_at is null;

  insert into public.employee_onboarding_submissions (
    employee_id, token_id, date_of_birth, gender, national_id, personal_email,
    emergency_contact_name, emergency_contact_phone, residential_address, qualifications,
    bank_name, account_no, payment_method, contract_accepted, signature_name, uploaded_documents
  ) values (
    v_employee_id, v_token_id, p_date_of_birth, nullif(trim(p_gender), ''),
    nullif(trim(p_national_id), ''), nullif(trim(p_personal_email), ''),
    nullif(trim(p_emergency_contact_name), ''), nullif(trim(p_emergency_contact_phone), ''),
    nullif(trim(p_residential_address), ''), nullif(trim(p_qualifications), ''),
    nullif(trim(p_bank_name), ''), nullif(trim(p_account_no), ''), nullif(p_payment_method, ''),
    p_contract_accepted, trim(p_signature_name), coalesce(p_uploaded_documents, '[]'::jsonb)
  ) returning id into v_submission_id;

  return v_submission_id;
end;
$$;

-- =====================================================================
-- 10. Review: approve copies the safe fields + documents across;
--     reject just records why. Neither touches employee_pay_config.
-- =====================================================================
create or replace function public.approve_onboarding_submission(p_submission_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub public.employee_onboarding_submissions;
  v_doc jsonb;
begin
  perform public.require_finance_writer();

  select * into v_sub from public.employee_onboarding_submissions where id = p_submission_id;
  if v_sub.id is null then
    raise exception 'Submission not found.';
  end if;
  if v_sub.review_status <> 'Pending Review' then
    raise exception 'This submission has already been reviewed.';
  end if;

  update public.employees
  set date_of_birth = coalesce(v_sub.date_of_birth, date_of_birth),
      gender = coalesce(v_sub.gender, gender),
      national_id = coalesce(v_sub.national_id, national_id),
      personal_email = coalesce(v_sub.personal_email, personal_email),
      emergency_contact_name = coalesce(v_sub.emergency_contact_name, emergency_contact_name),
      emergency_contact_phone = coalesce(v_sub.emergency_contact_phone, emergency_contact_phone),
      residential_address = coalesce(v_sub.residential_address, residential_address),
      qualifications = coalesce(v_sub.qualifications, qualifications)
  where id = v_sub.employee_id;

  for v_doc in select * from jsonb_array_elements(v_sub.uploaded_documents)
  loop
    insert into public.employee_documents (employee_id, document_type, storage_path, notes)
    values (v_sub.employee_id, v_doc ->> 'document_type', v_doc ->> 'storage_path',
            'Uploaded via onboarding form');
  end loop;

  update public.employee_onboarding_submissions
  set review_status = 'Approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_submission_id;
end;
$$;

create or replace function public.reject_onboarding_submission(
  p_submission_id uuid, p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_finance_writer();

  update public.employee_onboarding_submissions
  set review_status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = nullif(trim(coalesce(p_reason, '')), '')
  where id = p_submission_id and review_status = 'Pending Review';

  if not found then
    raise exception 'Submission not found or already reviewed.';
  end if;
end;
$$;

grant execute on function public.toggle_onboarding_task(uuid, boolean) to authenticated, service_role;
grant execute on function public.initialize_onboarding_checklist(uuid) to authenticated, service_role;
grant execute on function public.generate_onboarding_token(uuid, integer) to authenticated, service_role;
grant execute on function public.approve_onboarding_submission(uuid) to authenticated, service_role;
grant execute on function public.reject_onboarding_submission(uuid, text) to authenticated, service_role;

grant execute on function public.is_valid_onboarding_token(text) to anon, authenticated, service_role;
grant execute on function public.get_onboarding_context(text) to anon, authenticated, service_role;
grant execute on function public.submit_onboarding_form(
  text, date, text, text, text, text, text, text, text, text, text, text, boolean, text, jsonb
) to anon, authenticated, service_role;

-- =====================================================================
-- 11. The Phase-2 anon storage policy, held back until this table
--     existed. Built together with employee_onboarding_tokens in this
--     one migration, as planned.
-- =====================================================================
create policy "onboarding_documents_anon_insert" on storage.objects
for insert
to anon
with check (
  bucket_id = 'onboarding-documents'
  and array_length(storage.foldername(name), 1) >= 2
  and (storage.foldername(name))[1] = 'onboarding'
  and public.is_valid_onboarding_token((storage.foldername(name))[2])
);
