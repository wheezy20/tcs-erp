-- Admissions slice 3a: the applicant core tables and their staff read RLS
-- (docs/admissions/PORT-PLAN.md, slice 3, split 3a/3b; gates A1-A5, B1-B4
-- and D-3c approved 2026-10-10).
--
-- families, guardians, students, applications, application_emergency_contacts
-- and application_notes, ported from TCS OS's Family, Guardian, Student,
-- Application, EmergencyContact and Note (models.py:118-300, 581-594,
-- 656-666). TCS OS's Campus table is replaced by branches.
--
-- Read-only for staff: every table is select-only for authenticated, with
-- no insert/update/delete grant or policy. The first writers are the slice 5
-- RPCs; until then rows come only from postgres (probe setup, and the
-- slice 15 hand import).
--
-- Scope resolves live from applications.year_group_applied_for through
-- slice 2's admissions_grade_visible() (D-2c): never stored per row. Child
-- tables inherit their application's visibility; a student is visible when
-- one of its applications is, and a family or guardian when one of its
-- students is (D-3d: siblings in other bands stay hidden). Manager and
-- Auditor see every row, including orphans; Attendant, Accountant and anon
-- see nothing. Campus doesn't scope reads.
--
-- Import-friendly on purpose (slice 15). References and student_id are
-- nullable (pre-numbering rows have none) and accept more than 4 sequence
-- digits; grades, academic years and months stay free text; there's no
-- unique on guardian email or on a family, because TCS OS's inquiry path
-- never de-duplicated. A few checks are stricter than TCS OS's columns:
-- non-blank grade and academic year, the student_id and reference formats,
-- and the length caps. The slice 15 import dry run reports any legacy row
-- they would refuse. Identity
-- triggers act only when there's a signed-in user, so the import keeps the
-- original authors and timestamps. No legacy id column (B3).
--
-- No anon surface: anon has no grant on any table, and every new function
-- is revoked from public and anon.

-- ------------------------------------------------------------ families

create table public.families (
  id uuid primary key default gen_random_uuid(),
  referral_source text not null default '' check (referral_source in (
    '', 'current_parent', 'former_parent', 'parent_referral', 'staff_referral',
    'website', 'friend_colleague', 'social_media', 'other'
  )),
  referral_source_other text not null default '' check (char_length(referral_source_other) <= 255),
  -- TCS OS's TextFields are unbounded; 10,000 is a guard for when anon
  -- writes arrive (slice 8), not a TCS OS rule.
  comments text not null default '' check (char_length(comments) <= 10000),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------ guardians

create table public.guardians (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  first_name text not null default '' check (char_length(first_name) <= 255),
  surname text not null default '' check (char_length(surname) <= 255),
  email text not null check (char_length(email) <= 254),
  phone text not null check (char_length(phone) <= 32),
  relationship text not null check (relationship in ('mother', 'father', 'guardian', 'other')),
  religion text not null default '' check (char_length(religion) <= 255),
  address text not null default '' check (char_length(address) <= 255),
  town_city text not null default '' check (char_length(town_city) <= 255),
  -- sha256 hex of the bulk-email unsubscribe token; the raw token is never
  -- stored. Nullable until slice 14 gives new guardians one.
  bulk_email_unsubscribe_token_hash text unique
    check (bulk_email_unsubscribe_token_hash ~ '^[0-9a-f]{64}$'),
  bulk_email_unsubscribed_at timestamptz
);

create index guardians_family_id_idx on public.guardians (family_id);
create index guardians_email_idx on public.guardians (email);

-- Email is stored lowercased and trimmed, so matching (slice 9) needs no
-- normalisation. Phone is left as entered (DESIGN.md's phone exception).
create or replace function public.normalise_guardian_email()
returns trigger
language plpgsql
as $$
begin
  new.email := lower(btrim(new.email));
  return new;
end;
$$;

create trigger guardians_normalise_email
  before insert or update of email on public.guardians
  for each row execute function public.normalise_guardian_email();

-- ------------------------------------------------------------ students

create table public.students (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  full_name text not null check (char_length(full_name) <= 255),
  date_of_birth date,
  gender text not null default '' check (gender in ('', 'male', 'female')),
  nationality text not null default '' check (char_length(nationality) <= 100),
  address text not null default '' check (char_length(address) <= 255),
  town_city text not null default '' check (char_length(town_city) <= 255),
  postal_code text not null default '' check (char_length(postal_code) <= 20),
  country text not null default '' check (char_length(country) <= 100),
  current_school text not null default '' check (char_length(current_school) <= 255),
  previous_school_location text not null default '' check (char_length(previous_school_location) <= 255),
  current_grade text not null default '' check (char_length(current_grade) <= 50),
  -- YYPPNNNN (models.py:113): year, classification 01-09, then a sequence
  -- TCS OS pads to 4 digits but doesn't cap. Assigned at enrolment (slice 6).
  student_id text unique
    check (char_length(student_id) <= 20 and student_id ~ '^[0-9]{2}0[1-9][0-9]{4,}$')
);

create index students_family_id_idx on public.students (family_id);

-- ------------------------------------------------------------ applications

create table public.applications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  -- TCS OS's eight stages (models.py:230-239). Only the slice 5 and 6 RPCs
  -- will change it.
  stage text not null default 'inquiry' check (stage in (
    'inquiry', 'application', 'document_review', 'offer', 'enrolled',
    'waitlisted', 'rejected', 'offer_declined'
  )),
  academic_year text not null
    check (char_length(academic_year) <= 50 and btrim(academic_year) <> ''),
  -- Free text, so "Other" and legacy grades round-trip; a grade with no
  -- band is visible only to Manager, Auditor and all_grades officers.
  year_group_applied_for text not null
    check (char_length(year_group_applied_for) <= 50 and btrim(year_group_applied_for) <> ''),
  month_of_enrollment text not null default '' check (char_length(month_of_enrollment) <= 50),
  -- INQ-YYYY-NNNN and APP-YYYY-NNNN (models.py:65-74), assigned in slice 5.
  inquiry_reference text unique
    check (char_length(inquiry_reference) <= 20 and inquiry_reference ~ '^INQ-[0-9]{4}-[0-9]{4,}$'),
  application_reference text unique
    check (char_length(application_reference) <= 20 and application_reference ~ '^APP-[0-9]{4}-[0-9]{4,}$'),
  -- Null for an inquiry: it carries no campus.
  branch_id uuid references public.branches (id) on delete restrict,
  wants_scholarship_info boolean not null default false,
  scholarship_interest_details text not null default ''
    check (char_length(scholarship_interest_details) <= 10000),
  declaration_signature_name text not null default '' check (char_length(declaration_signature_name) <= 255),
  declaration_agreed boolean not null default false,
  declaration_agreed_at timestamptz,
  declaration_ip_address inet,
  media_consent_agreed boolean not null default false,
  created_at timestamptz not null default now(),
  -- Maintained by the first writer (slice 5).
  updated_at timestamptz not null default now()
);

create index applications_student_id_idx on public.applications (student_id);
create index applications_stage_idx on public.applications (stage);
create index applications_branch_id_idx on public.applications (branch_id);
create index applications_academic_year_idx on public.applications (academic_year);

-- ------------------------------------------------------------ emergency contacts

create table public.application_emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  name text not null check (char_length(name) <= 255),
  relationship text not null check (char_length(relationship) <= 100),
  phone text not null check (char_length(phone) <= 32)
);

create index application_emergency_contacts_application_id_idx
  on public.application_emergency_contacts (application_id);

-- ------------------------------------------------------------ notes

create table public.application_notes (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  author_id uuid references public.staff (id) on delete set null,
  content text not null check (char_length(content) <= 10000),
  created_at timestamptz not null default now()
);

create index application_notes_application_id_idx on public.application_notes (application_id);

-- Server-forced author and time for a signed-in writer. With no signed-in
-- user (postgres, service_role, the slice 15 import) the supplied values
-- stand, so legacy notes keep their dates.
create or replace function public.set_application_note_identity()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null then
    new.author_id := auth.uid();
    new.created_at := now();
  end if;
  return new;
end;
$$;

create trigger application_notes_set_identity
  before insert on public.application_notes
  for each row execute function public.set_application_note_identity();

-- ------------------------------------------------------------ visibility helpers

-- Used by the select policies. SECURITY DEFINER so they read the underlying
-- rows directly instead of stacking each table's RLS inside another's.

-- Whether the caller may see this application (its grade, live).
create or replace function public.admissions_application_visible(p_application_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.applications a
    where a.id = p_application_id
      and public.admissions_grade_visible(a.year_group_applied_for)
  );
$$;

-- A student is visible when one of its applications is. Manager and
-- Auditor get true for any id, so they also see a student with no
-- application.
create or replace function public.admissions_student_visible(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role(array['Manager', 'Auditor'])
    or exists (
      select 1 from public.applications a
      where a.student_id = p_student_id
        and public.admissions_grade_visible(a.year_group_applied_for)
    );
$$;

-- A family (and its guardians) is visible when one of its students has a
-- visible application: one row however many bands its children span.
-- Manager and Auditor get true for any id, so they also see a family with
-- no student.
create or replace function public.admissions_family_visible(p_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role(array['Manager', 'Auditor'])
    or exists (
      select 1 from public.students s
      join public.applications a on a.student_id = s.id
      where s.family_id = p_family_id
        and public.admissions_grade_visible(a.year_group_applied_for)
    );
$$;

-- ------------------------------------------------------------ RLS

alter table public.families enable row level security;
alter table public.guardians enable row level security;
alter table public.students enable row level security;
alter table public.applications enable row level security;
alter table public.application_emergency_contacts enable row level security;
alter table public.application_notes enable row level security;

-- Select only. No insert, update or delete policy on any of them.
create policy families_select on public.families
  for select using (public.admissions_family_visible(id));

create policy guardians_select on public.guardians
  for select using (public.admissions_family_visible(family_id));

create policy students_select on public.students
  for select using (public.admissions_student_visible(id));

create policy applications_select on public.applications
  for select using (public.admissions_grade_visible(year_group_applied_for));

create policy application_emergency_contacts_select on public.application_emergency_contacts
  for select using (public.admissions_application_visible(application_id));

create policy application_notes_select on public.application_notes
  for select using (public.admissions_application_visible(application_id));

-- ------------------------------------------------------------ grants

revoke all on table public.families from anon, authenticated;
revoke all on table public.guardians from anon, authenticated;
revoke all on table public.students from anon, authenticated;
revoke all on table public.applications from anon, authenticated;
revoke all on table public.application_emergency_contacts from anon, authenticated;
revoke all on table public.application_notes from anon, authenticated;

grant select on table public.families to authenticated;
grant select on table public.guardians to authenticated;
grant select on table public.students to authenticated;
grant select on table public.applications to authenticated;
grant select on table public.application_emergency_contacts to authenticated;
grant select on table public.application_notes to authenticated;

grant select, insert, update, delete on table public.families to service_role;
grant select, insert, update, delete on table public.guardians to service_role;
grant select, insert, update, delete on table public.students to service_role;
grant select, insert, update, delete on table public.applications to service_role;
grant select, insert, update, delete on table public.application_emergency_contacts to service_role;
grant select, insert, update, delete on table public.application_notes to service_role;

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. Trigger functions get no grant.
revoke execute on function public.normalise_guardian_email() from public, anon, authenticated;
revoke execute on function public.set_application_note_identity() from public, anon, authenticated;

revoke execute on function public.admissions_application_visible(uuid) from public, anon;
revoke execute on function public.admissions_student_visible(uuid) from public, anon;
revoke execute on function public.admissions_family_visible(uuid) from public, anon;
grant execute on function public.admissions_application_visible(uuid) to authenticated, service_role;
grant execute on function public.admissions_student_visible(uuid) to authenticated, service_role;
grant execute on function public.admissions_family_visible(uuid) to authenticated, service_role;
