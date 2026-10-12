-- Admissions slice 7a: the staff applications list source
-- (docs/admissions/PORT-PLAN.md, slice 7a; plan approved 2026-10-12).
--
-- The list screen needs to search the student's name and both references
-- with one filter, and to show each application's canonical grade and band.
-- PostgREST can't OR across an embedded students row, and the grade rules
-- belong in the database, so this adds one view and one helper:
--
--   admissions_grade_name(text): the canonical admissions_grades name for a
--     grade as stored, or null when it matches no grade (unbanded, legacy,
--     free-text "Other"). Same normalisation as admissions_grade_band().
--
--   admissions_application_list: one row per application with its student's
--     name, campus name, canonical grade and band. security_invoker, so the
--     applications and students select policies decide every row exactly as
--     they do for a direct read: Manager and Auditor see all, an Admissions
--     Officer sees in-scope grades only, every other role sees nothing.
--     No health, decision, offer, declaration or token column.
--
-- Grants: the view is readable by authenticated and service_role only; the
-- helper is executable by authenticated and service_role only. Nothing is
-- granted to anon, so the anon-executable function count stays at 169.

-- ------------------------------------------------------------ grade name

create or replace function public.admissions_grade_name(p_grade text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select g.name
  from public.admissions_grades g
  where lower(g.name) = regexp_replace(regexp_replace(lower(p_grade), '^\s+|\s+$', '', 'g'), '\s+', ' ', 'g');
$$;

-- ------------------------------------------------------------ list view

create view public.admissions_application_list with (security_invoker = true) as
select
  a.id,
  a.student_id,
  s.full_name as student_full_name,
  a.branch_id,
  b.name as branch_name,
  a.academic_year,
  a.year_group_applied_for,
  public.admissions_grade_name(a.year_group_applied_for) as grade_name,
  public.admissions_grade_band(a.year_group_applied_for) as grade_band,
  a.month_of_enrollment,
  a.stage,
  a.inquiry_reference,
  a.application_reference,
  a.created_at,
  a.updated_at
from public.applications a
join public.students s on s.id = a.student_id
left join public.branches b on b.id = a.branch_id;

-- ------------------------------------------------------------ grants

revoke execute on function public.admissions_grade_name(text) from public, anon;
grant execute on function public.admissions_grade_name(text) to authenticated, service_role;

revoke all on table public.admissions_application_list from public, anon, authenticated, service_role;
grant select on table public.admissions_application_list to authenticated, service_role;
