-- Admissions slice 7a: the academic year list
-- (docs/admissions/PORT-PLAN.md, slice 7a; plan approved 2026-10-12).
--
-- applications.academic_year and admissions_capacity.academic_year are free
-- text, so a typo ("2026/2072") silently misses its capacity row (D-6o).
-- Following DESIGN.md's curated-list pattern (positions, departments,
-- payment providers), this adds a small reference list. The columns that
-- use it stay plain text with no foreign key: the list constrains the
-- pickers and, from 7b, create_admissions_capacity(); legacy values keep
-- round-tripping.
--
-- Format YYYY/YYYY with consecutive years. Seeded with 2026/2027 and
-- 2027/2028 (entity-wide reference data goes in the migration, DESIGN.md).
--
-- Select-only for Manager, Auditor and Admissions Officer. No write policy
-- and no write grant for authenticated: the Manager add and deactivate RPCs
-- come in slice 7b. Nothing for anon.

create table public.admissions_academic_years (
  -- case, not and: the casts must only run once the shape is known good.
  label text primary key check (
    case when label ~ '^[0-9]{4}/[0-9]{4}$'
      then split_part(label, '/', 2)::integer = split_part(label, '/', 1)::integer + 1
      else false
    end
  ),
  position integer not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.admissions_academic_years (label, position) values
  ('2026/2027', 1),
  ('2027/2028', 2)
on conflict (label) do nothing;

alter table public.admissions_academic_years enable row level security;

create policy admissions_academic_years_select on public.admissions_academic_years
  for select using (public.has_role(array['Manager', 'Auditor', 'Admissions Officer']));

revoke all on table public.admissions_academic_years from public, anon, authenticated;
grant select on table public.admissions_academic_years to authenticated;
grant select, insert, update, delete on table public.admissions_academic_years to service_role;
