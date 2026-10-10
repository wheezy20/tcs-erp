-- Hosted ERP: add the Annex campus and its admissions grade rules.
--
-- Run by hand in the Supabase SQL editor on the HOSTED ERP project, once,
-- after the admissions slice 3a and 3b migrations are applied. Not for
-- local dev (supabase/seed.sql already does this there), and not part of
-- any migration or seed file.
--
-- What it writes:
--   * public.branches: one row named Annex, only if no branch named Annex
--     exists. Same columns and values as the Annex insert in
--     supabase/seed.production.sql: name 'Annex',
--     default_low_stock_threshold 20, and created_at one second after the
--     newest existing branch (or now, if later), so the existing branch
--     stays the oldest. id comes from its default, gen_random_uuid().
--   * public.admissions_campus_grade_rules: Annex accepts Pre Nursery and
--     Nursery 1 (on conflict do nothing).
-- It does not rename or change the existing branch, and does not touch
-- expense categories, allowance types or anything else.
--
-- The DO block is all or nothing: if any check fails it raises, and
-- nothing from the block is kept. The final select only reads.

do $$
declare
  v_grades int;
  v_annex_id uuid;
  v_rules int;
begin
  -- Both grades must exist before anything is written.
  select count(*) into v_grades
  from public.admissions_grades
  where lower(name) in ('pre nursery', 'nursery 1');
  if v_grades <> 2 then
    raise exception 'Expected Pre Nursery and Nursery 1 in admissions_grades, found % of them', v_grades;
  end if;

  insert into public.branches (name, default_low_stock_threshold, created_at)
  select 'Annex', 20,
         greatest(now(), (select max(created_at) from public.branches)) + interval '1 second'
  where not exists (select 1 from public.branches where name = 'Annex');

  select id into v_annex_id from public.branches where name = 'Annex';

  -- Every school-wide record (payroll, expenses, staff, POS) resolves to the
  -- oldest branch, so Annex must never be it.
  if (select id from public.branches order by created_at limit 1) = v_annex_id then
    raise exception 'Annex would be the oldest branch; stopping';
  end if;

  insert into public.admissions_campus_grade_rules (branch_id, grade_id)
  select v_annex_id, g.id
  from public.admissions_grades g
  where lower(g.name) in ('pre nursery', 'nursery 1')
  on conflict do nothing;

  select count(*) into v_rules
  from public.admissions_campus_grade_rules
  where branch_id = v_annex_id;
  if v_rules <> 2 then
    raise exception 'Expected exactly 2 Annex grade rules, found %', v_rules;
  end if;
end $$;

-- Check the result: every branch, oldest first, with the grades it is
-- limited to (none listed means it accepts every grade).
select b.name as branch,
       b.created_at,
       g.name as accepted_grade
from public.branches b
left join public.admissions_campus_grade_rules r on r.branch_id = b.id
left join public.admissions_grades g on g.id = r.grade_id
order by b.created_at, g.position;
