-- Role matrix for 20261015100000_admissions_decisions_capacity, CAPACITY file (admissions slice 6a,
-- docs/admissions/PORT-PLAN.md): create/update/delete_admissions_capacity (Manager
-- only, no capability needed), their validation messages, the capacity warning
-- returned by record_decision and change_decision (strictly greater, what counts,
-- null-safe campus match, Manager figures versus the officer's figure-free text),
-- and the admissions_capacity_changed audit rows. Fixture rows are invented
-- (ids 9e060000-...).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261015100000_admissions_decisions_capacity_capacity.sql

-- ================================================================ authorization: Manager only

-- probe: C1 create_admissions_capacity: Manager only (AO holds every capability)
-- expect: Manager
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
select public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);

-- probe: C2 update_admissions_capacity: Manager only
-- expect: Manager
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 9);

-- probe: C3 delete_admissions_capacity: Manager only
-- expect: Manager
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.delete_admissions_capacity('9e060000-0000-4000-8000-000700000001');

-- probe: C4 create: a Manager with no capability row at all still works
-- expect: Manager
select public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);

-- probe: C4b update: Manager with no capability row
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 9);

-- probe: C4c delete: Manager with no capability row
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.delete_admissions_capacity('9e060000-0000-4000-8000-000700000001');

-- probe: C5 the officer gets the Manager-only message from all three
-- expect: Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Only a Manager can change admissions capacity' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 9);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Only a Manager can change admissions capacity' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.delete_admissions_capacity('9e060000-0000-4000-8000-000700000001');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Only a Manager can change admissions capacity' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: C6 the Auditor gets the read-only message from all three
-- expect: Auditor
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Auditor is read-only and cannot perform this action' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 9);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Auditor is read-only and cannot perform this action' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.delete_admissions_capacity('9e060000-0000-4000-8000-000700000001');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Auditor is read-only and cannot perform this action' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: C7 the Manager's update lands: figure changed, key columns unchanged
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select set_config('t.r', to_jsonb(public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 9))::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select capacity = 9 and academic_year = '2027/2028' and grade_id = (select id from public.admissions_grades where name = 'Grade 3') and branch_id is null from public.admissions_capacity where id = '9e060000-0000-4000-8000-000700000001')), false) then raise exception 'update wrong'; end if;
end $$;

-- ================================================================ validation: exact messages, Manager only

-- probe: V1 blank year refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The academic year must be 1 to 50 characters' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V1b whitespace-only year refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('   ', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The academic year must be 1 to 50 characters' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V1c null year refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity(null, (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The academic year must be 1 to 50 characters' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V2 year of 51 characters refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity(repeat('y', 51), (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The academic year must be 1 to 50 characters' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V3 unknown grade refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('2027/2028', gen_random_uuid(), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Grade not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V3b null grade refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('2027/2028', null, null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Grade not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V4 unknown campus refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), gen_random_uuid(), 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Campus not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V5 negative capacity refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, -1);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity must be a whole number from 0 to 100,000' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V5b capacity 100001 refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 100001);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity must be a whole number from 0 to 100,000' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V5c null capacity refused on create
-- expect: Manager
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, null);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity must be a whole number from 0 to 100,000' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V6 duplicate year, grade and campus (Main)
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 5);
-- as role:
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A capacity for this year, grade and campus already exists' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V6b duplicate with a null campus
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 5);
-- as role:
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A capacity for this year, grade and campus already exists' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V6c duplicate after the year is trimmed
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 5);
-- as role:
do $$ begin
  perform public.create_admissions_capacity('  2027/2028  ', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A capacity for this year, grade and campus already exists' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V6d a different campus, grade or year is not a duplicate
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 5);
-- as role:
select public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000002', 5);
select public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 4'), null, 5);
select public.create_admissions_capacity('2028/2029', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);

-- probe: V7 year stored trimmed; 50 characters, 0 and 100000 accepted
-- expect: Manager
select public.create_admissions_capacity('  2030/2031  ', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
select public.create_admissions_capacity('yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy', (select id from public.admissions_grades where name = 'Grade 3'), null, 100000);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((exists (select 1 from public.admissions_capacity where academic_year = '2030/2031' and capacity = 0) and exists (select 1 from public.admissions_capacity where char_length(academic_year) = 50 and capacity = 100000)), false) then raise exception 'year not trimmed or boundary refused'; end if;
end $$;

-- probe: V7b the created row is returned
-- expect: Manager
select set_config('t.r', to_jsonb(public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 7))::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity' = '7' and r->>'academic_year' = '2027/2028' and r->'branch_id' = 'null'::jsonb and r->>'id' is not null), false) then raise exception 'returned row wrong'; end if;
end $$;

-- probe: V8 update refused when the figure is unchanged
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
do $$ begin
  perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The capacity is already 5' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V8b update refused for an unknown id
-- expect: Manager
do $$ begin
  perform public.update_admissions_capacity(gen_random_uuid(), 3);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V8c update refuses a negative, over-limit or null figure
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
do $$ begin
  perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', -1);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity must be a whole number from 0 to 100,000' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 100001);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity must be a whole number from 0 to 100,000' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', null);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity must be a whole number from 0 to 100,000' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V8d update to 0 and to 100000 works
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 0);
select public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 100000);

-- probe: V9 delete refused for an unknown id
-- expect: Manager
do $$ begin
  perform public.delete_admissions_capacity(gen_random_uuid());
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: V9b delete removes exactly that row
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 4'), null, 5);
-- as role:
select public.delete_admissions_capacity('9e060000-0000-4000-8000-000700000001');
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((not exists (select 1 from public.admissions_capacity where id = '9e060000-0000-4000-8000-000700000001') and exists (select 1 from public.admissions_capacity where id = '9e060000-0000-4000-8000-000700000002')), false) then raise exception 'wrong row deleted'; end if;
end $$;

-- probe: V9c delete with null id refused
-- expect: Manager
do $$ begin
  perform public.delete_admissions_capacity(null);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Capacity not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- ================================================================ capacity warning on record_decision and change_decision

-- probe: W1 capacity 1, this is the first accepted: silent
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W2 capacity 1, one already accepted: warns (2 against 1)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W2b capacity 2, one already accepted: equal, silent
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 2);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W2c capacity 2, two already accepted: warns (3 against 2)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e060000-0000-4000-8000-000300000003', '9e060000-0000-4000-8000-000100000001', 'Child 3 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000003', '9e060000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000003', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 2);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 3, 2) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W3 capacity 0: the first acceptance warns
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 1, 0) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W4 no capacity row: silent however many are accepted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e060000-0000-4000-8000-000300000003', '9e060000-0000-4000-8000-000100000001', 'Child 3 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000003', '9e060000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000003', 'accepted', '');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W5a null-campus application, capacity row for Main only: silent
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W5b Main-campus application, null-campus capacity row only: silent
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', '00000000-0000-0000-0000-000000000001');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
update public.applications set branch_id = '00000000-0000-0000-0000-000000000001' where id = '9e060000-0000-4000-8000-000400000001';
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W5c both null campus: warns, label without a campus
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W5d both Main: warns, label carries the campus
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', '00000000-0000-0000-0000-000000000001');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 1);
update public.applications set branch_id = '00000000-0000-0000-0000-000000000001' where id = '9e060000-0000-4000-8000-000400000001';
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028, Main)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028, Main) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W5e Annex and null-campus acceptances don't count for Main
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e060000-0000-4000-8000-000300000003', '9e060000-0000-4000-8000-000100000001', 'Child 3 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', '00000000-0000-0000-0000-000000000002'),
  ('9e060000-0000-4000-8000-000400000003', '9e060000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000003', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 1);
update public.applications set branch_id = '00000000-0000-0000-0000-000000000001' where id = '9e060000-0000-4000-8000-000400000001';
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W5f a Main acceptance doesn't count for a null-campus row
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', '00000000-0000-0000-0000-000000000001');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W6 a grade written with case and extra whitespace is counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', ' grade   3 ', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W7 an application at offer_declined is not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W8 an offer declined is not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W8 an offer withdrawn is not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W8 an offer expired is not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', now() + interval '10 days', 'expired');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W8b a pending offer past its expiry is not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', now() - interval '1 minute', 'pending');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W9 a pending in-date offer is counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W9b a pending offer with no expiry is counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', null, 'pending');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W9c an accepted offer is counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000002', md5('o2') || md5('p2'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W9d an enrolled student with an accepted decision is counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'enrolled', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W10 a different academic_year text is not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2028/2029', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W11 another grade's acceptances are not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 4', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W11b a capacity row for another grade is not used
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 4'), null, 0);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W11c a capacity row for another year is not used
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2028/2029', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W12 waitlisted and rejected decisions are not counted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e060000-0000-4000-8000-000300000003', '9e060000-0000-4000-8000-000100000001', 'Child 3 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'waitlisted', null),
  ('9e060000-0000-4000-8000-000400000003', '9e060000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'rejected', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'waitlisted', '');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000003', 'rejected', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
end $$;

-- probe: W13 change_decision to accepted warns too
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W13b change_decision accepted to accepted (notes only) still returns the warning
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', 'old');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'new')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((case when public.has_role(array['Manager']) then r->>'capacity_warning' = format('Capacity warning: %s now has %s accepted decisions against a capacity of %s.', 'Grade 3 (2027/2028)', 2, 1) else r->>'capacity_warning' = 'Capacity warning: Grade 3 (2027/2028) is now over its planned capacity. Ask a Manager.' and regexp_replace(r->>'capacity_warning', 'Grade 3 \([^)]*\)', '') !~ '[0-9]' end), false) then raise exception 'warning text wrong'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'accepted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W14 waitlisted over capacity returns no warning
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'waitlisted')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W14b rejected over capacity returns no warning
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'rejected')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W14c change to rejected over capacity returns no warning
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
  if not coalesce((exists (select 1 from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001' and decision_type = 'rejected')), false) then raise exception 'decision not recorded'; end if;
end $$;

-- probe: W15 an application whose grade is not an admissions grade never warns
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'accepted', '');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 0);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'capacity_warning' is null), false) then raise exception 'expected no warning'; end if;
end $$;

-- ================================================================ audit: admissions_capacity_changed

-- probe: K1 create writes one row: before null, after {academic_year, grade, campus null, capacity}
-- expect: Manager
select set_config('t.r', to_jsonb(public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 7))::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'admissions_capacity_changed') = 1), false) then raise exception 'row count'; end if;
  if not coalesce(((select before is null and after = jsonb_build_object('academic_year', '2027/2028', 'grade', 'Grade 3', 'campus', null, 'capacity', 7) and entity_table = 'admissions_capacity' and entity_id = r->>'id' and actor_id = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid and branch_id = (select branch_id from public.staff where id = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid) from public.audit_log where action = 'admissions_capacity_changed')), false) then raise exception 'row wrong'; end if;
end $$;

-- probe: K1b create with a campus: campus by name, audit branch is that campus
-- expect: Manager
select set_config('t.r', to_jsonb(public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 4'), '00000000-0000-0000-0000-000000000002', 7))::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select after->>'campus' = 'Annex' and after->>'grade' = 'Grade 4' and branch_id = '00000000-0000-0000-0000-000000000002' from public.audit_log where action = 'admissions_capacity_changed')), false) then raise exception 'campus row wrong'; end if;
end $$;

-- probe: K2 update writes before and after with the figure
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), '00000000-0000-0000-0000-000000000001', 5);
-- as role:
select public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 9);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'admissions_capacity_changed') = 1), false) then raise exception 'row count'; end if;
  if not coalesce(((select before = jsonb_build_object('academic_year', '2027/2028', 'grade', 'Grade 3', 'campus', 'Main', 'capacity', 5) and after = jsonb_build_object('academic_year', '2027/2028', 'grade', 'Grade 3', 'campus', 'Main', 'capacity', 9) and entity_id = '9e060000-0000-4000-8000-000700000001' and actor_id = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid from public.audit_log where action = 'admissions_capacity_changed')), false) then raise exception 'update row wrong'; end if;
end $$;

-- probe: K3 delete writes before with the figure, after null
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.delete_admissions_capacity('9e060000-0000-4000-8000-000700000001');
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select before = jsonb_build_object('academic_year', '2027/2028', 'grade', 'Grade 3', 'campus', null, 'capacity', 5) and after is null and entity_id = '9e060000-0000-4000-8000-000700000001' and actor_id = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid from public.audit_log where action = 'admissions_capacity_changed')), false) then raise exception 'delete row wrong'; end if;
end $$;

-- probe: K4 payload keys are exactly the four, across insert, update and delete
-- expect: Manager
select set_config('t.id', (select id::text from public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 7)), true);
select public.update_admissions_capacity(current_setting('t.id')::uuid, 8);
select public.delete_admissions_capacity(current_setting('t.id')::uuid);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'admissions_capacity_changed') = 3), false) then raise exception 'expected three rows'; end if;
  if not coalesce((not exists (select 1 from public.audit_log where action = 'admissions_capacity_changed' and ((after is not null and (select array_agg(k order by k) from jsonb_object_keys(after) k) is distinct from array['academic_year','campus','capacity','grade']) or (before is not null and (select array_agg(k order by k) from jsonb_object_keys(before) k) is distinct from array['academic_year','campus','capacity','grade'])))), false) then raise exception 'payload keys wrong'; end if;
end $$;

-- probe: K5 no audit row when postgres or service_role (no auth.uid) writes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
set local request.jwt.claims = '{}';
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
update public.admissions_capacity set capacity = 6;
delete from public.admissions_capacity;
set local request.jwt.claims = '{"role":"service_role"}';
insert into public.admissions_capacity (id, academic_year, grade_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), 5);
update public.admissions_capacity set capacity = 6;
delete from public.admissions_capacity;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'admissions_capacity_changed') = 0), false) then raise exception 'audit row written without an actor'; end if;
end $$;

-- probe: K6 a refused call writes no audit row
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e060000-0000-4000-8000-000700000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
do $$ begin perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5); exception when others then null; end $$;
do $$ begin perform public.update_admissions_capacity('9e060000-0000-4000-8000-000700000001', 5); exception when others then null; end $$;
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'admissions_capacity_changed') = 0), false) then raise exception 'row written for a refused call'; end if;
end $$;
