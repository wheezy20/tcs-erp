-- Admissions slice 3b: decisions, offers, capacity and campus grade rules,
-- with their staff read RLS (docs/admissions/PORT-PLAN.md, slice 3b; reads,
-- design choices (a) to (f) and the docs changes approved 2026-10-11).
--
-- application_decisions, application_offers and admissions_capacity port
-- TCS OS's Decision, Offer and Capacity (models.py:392-541).
-- admissions_campus_grade_rules replaces the Annex-by-name check
-- (serializers.py:17-18, 218-221): a campus with rows accepts only those
-- grades, a campus with none accepts every grade. The Annex rows are
-- branch-scoped, so they live in seed.sql and seed.production.sql, not here.
--
-- Read-only for staff, like 3a: select-only for authenticated, no
-- insert/update/delete grant or policy, no write RPCs (slice 6 adds them).
-- Who reads what (D-3c, D-3g, A4):
--   decisions, offers: Manager and Auditor; an Admissions Officer only when
--     the application is in scope and they hold can_decide.
--   capacity: Manager and Auditor only.
--   campus rules: Manager, Auditor and Admissions Officer.
-- Attendant, Accountant and anon read nothing.
--
-- Not here: stage propagation, offer expiry and the capacity warning
-- (slice 6); the campus rule check (slice 9's submit RPC only, never a
-- trigger on applications); the decision audit trigger (slice 6).
--
-- No anon surface: anon has no grant on any table, and the one new function
-- is revoked from public, anon and authenticated.

-- ------------------------------------------------------------ decisions

create table public.application_decisions (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.applications (id) on delete cascade,
  decision_type text not null check (decision_type in ('accepted', 'waitlisted', 'rejected')),
  decided_by uuid references public.staff (id) on delete set null,
  -- The last change, as TCS OS's auto_now kept it (models.py:409).
  decided_at timestamptz not null default now(),
  notes text not null default '' check (char_length(notes) <= 10000)
);

-- Server-forced decider and time for a signed-in writer, on insert and on
-- every update. With no signed-in user (postgres, service_role) the
-- supplied values stand.
create or replace function public.set_application_decision_identity()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end;
$$;

create trigger application_decisions_set_identity
  before insert or update on public.application_decisions
  for each row execute function public.set_application_decision_identity();

-- ------------------------------------------------------------ offers

create table public.application_offers (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.applications (id) on delete cascade,
  -- sha256 hex of the offer token; the raw token is never stored. It's
  -- minted and shown once by slice 6's RPC, so there's no default.
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  -- Nullable, as in TCS OS (models.py:466-467); no checks between the dates.
  sent_at timestamptz,
  expires_at timestamptz,
  response text not null default 'pending'
    check (response in ('pending', 'accepted', 'declined', 'expired')),
  responded_at timestamptz
);

-- ------------------------------------------------------------ capacity

create table public.admissions_capacity (
  id uuid primary key default gen_random_uuid(),
  -- Matched as exact text, as TCS OS did (admin.py:287-292).
  academic_year text not null
    check (char_length(academic_year) <= 50 and btrim(academic_year) <> ''),
  grade_id uuid not null references public.admissions_grades (id) on delete restrict,
  -- Null means not campus-specific.
  branch_id uuid references public.branches (id) on delete restrict,
  -- 0 means closed.
  capacity integer not null check (capacity >= 0),
  -- A null campus counts as a value, which closes the duplicate gap TCS OS
  -- accepted (models.py:514-523).
  constraint admissions_capacity_year_grade_branch_key
    unique nulls not distinct (academic_year, grade_id, branch_id)
);

-- ------------------------------------------------------------ campus grade rules

-- Restrict, not cascade: deleting a rule silently would open a campus to
-- every grade.
create table public.admissions_campus_grade_rules (
  branch_id uuid not null references public.branches (id) on delete restrict,
  grade_id uuid not null references public.admissions_grades (id) on delete restrict,
  primary key (branch_id, grade_id)
);

-- ------------------------------------------------------------ RLS

alter table public.application_decisions enable row level security;
alter table public.application_offers enable row level security;
alter table public.admissions_capacity enable row level security;
alter table public.admissions_campus_grade_rules enable row level security;

-- Select only. No insert, update or delete policy on any of them. The
-- officer branch names the role explicitly, so a later change to
-- has_admissions_capability() can't widen these reads to another role.
create policy application_decisions_select on public.application_decisions
  for select using (
    public.has_role(array['Manager', 'Auditor'])
    or (public.has_role(array['Admissions Officer'])
        and public.has_admissions_capability('decide')
        and public.admissions_application_visible(application_id))
  );

create policy application_offers_select on public.application_offers
  for select using (
    public.has_role(array['Manager', 'Auditor'])
    or (public.has_role(array['Admissions Officer'])
        and public.has_admissions_capability('decide')
        and public.admissions_application_visible(application_id))
  );

create policy admissions_capacity_select on public.admissions_capacity
  for select using (public.has_role(array['Manager', 'Auditor']));

create policy admissions_campus_grade_rules_select on public.admissions_campus_grade_rules
  for select using (public.has_role(array['Manager', 'Auditor', 'Admissions Officer']));

-- ------------------------------------------------------------ grants

revoke all on table public.application_decisions from anon, authenticated;
revoke all on table public.application_offers from anon, authenticated;
revoke all on table public.admissions_capacity from anon, authenticated;
revoke all on table public.admissions_campus_grade_rules from anon, authenticated;

grant select on table public.application_decisions to authenticated;
grant select on table public.application_offers to authenticated;
grant select on table public.admissions_capacity to authenticated;
grant select on table public.admissions_campus_grade_rules to authenticated;

grant select, insert, update, delete on table public.application_decisions to service_role;
grant select, insert, update, delete on table public.application_offers to service_role;
grant select, insert, update, delete on table public.admissions_capacity to service_role;
grant select, insert, update, delete on table public.admissions_campus_grade_rules to service_role;

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- the new function is revoked explicitly. Trigger functions get no grant.
revoke execute on function public.set_application_decision_identity() from public, anon, authenticated;
