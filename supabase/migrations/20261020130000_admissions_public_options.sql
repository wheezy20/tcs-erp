-- Admissions slice 8: get_public_admissions_options(), the public Inquiry
-- form's picker data (docs/admissions/PORT-PLAN.md, slice 8; anon surface
-- decided 2026-10-13).
--
-- The one new anon-executable function in slice 8: the anon-executable
-- count in public goes from 169 to 170. SECURITY DEFINER, no arguments,
-- read only. It returns exactly:
--   intake_open     admissions_settings.public_intake_open
--   grades          active grades: id, name, position
--   campuses        every campus: id, name, and the ids of the active
--                   grades it accepts (all active grades when it has no
--                   rules)
--   academic_years  active year labels, in list order
-- Nothing else: no capacity, no counts, no settings beyond the flag, no
-- applicant data. The lists are the same ones submit_inquiry checks, so a
-- value the form offers is a value the RPC accepts.

create or replace function public.get_public_admissions_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with active_grades as (
    select g.id, g.name, g.position from public.admissions_grades g where g.is_active
  )
  select jsonb_build_object(
    'intake_open', coalesce((select s.public_intake_open from public.admissions_settings s where s.id = 1), false),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'position', g.position)
                       order by g.position, g.name)
      from active_grades g
    ), '[]'::jsonb),
    'campuses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'name', b.name,
        'accepted_grade_ids', coalesce((
          select jsonb_agg(g.id order by g.position, g.name)
          from active_grades g
          where not exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = b.id)
             or exists (select 1 from public.admissions_campus_grade_rules r
                        where r.branch_id = b.id and r.grade_id = g.id)
        ), '[]'::jsonb)
      ) order by b.name)
      from public.branches b
    ), '[]'::jsonb),
    'academic_years', coalesce((
      select jsonb_agg(y.label order by y.position, y.label)
      from public.admissions_academic_years y where y.is_active
    ), '[]'::jsonb)
  );
$$;

revoke execute on function public.get_public_admissions_options() from public;
grant execute on function public.get_public_admissions_options() to anon, authenticated, service_role;
