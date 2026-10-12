-- Role matrix for 20261015100000_admissions_decisions_capacity, DECISIONS file (admissions slice 6a,
-- docs/admissions/PORT-PLAN.md): record_decision and change_decision as each role.
-- Authorization grid (capability and scope variants), error order, behaviour
-- (stage moves, offer withdrawal, refusals) and the application_decision_changed
-- audit rows. A probe that calls an RPC succeeds only if the call does, so the
-- expect line lists the roles allowed to make it; behaviour probes use a setup
-- where Manager and Admissions Officer are both entitled and assert exact
-- outcomes or exact refusal messages. All fixture rows are invented
-- (ids 9e060000-...). Capabilities are set inside each probe's rolled-back setup.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261015100000_admissions_decisions_capacity_decisions.sql

-- ================================================================ authorization grid: record_decision and change_decision, capability and scope variants

-- probe: V0r record_decision: base: Manager and AO hold can_decide, AO {primary}, Grade 3
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V0c change_decision: base: Manager and AO hold can_decide, AO {primary}, Grade 3
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V1r record_decision: nobody holds can_decide
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V1c change_decision: nobody holds can_decide
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V2r record_decision: AO can_decide with no bands
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V2c change_decision: AO can_decide with no bands
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V3r record_decision: AO {primary} on a Grade 7 application
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V3c change_decision: AO {primary} on a Grade 7 application
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V4r record_decision: AO all three bands on Grade 11 (legacy grade)
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V4c change_decision: AO all three bands on Grade 11 (legacy grade)
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V5r record_decision: AO can_decide + all_grades on Grade 11
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V5c change_decision: AO can_decide + all_grades on Grade 11
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V6r record_decision: AO can_decide + all_grades on year-only grade 2027
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', '2027', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V6c change_decision: AO can_decide + all_grades on year-only grade 2027
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', '2027', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V7r record_decision: AO can_view_health only, Manager keeps can_decide
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V7c change_decision: AO can_view_health only, Manager keeps can_decide
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, false, true);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V8r record_decision: Manager has no can_decide row, AO holds it
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V8c change_decision: Manager has no can_decide row, AO holds it
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V9r record_decision: all staff inactive
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
update public.staff set active = false;
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V9c change_decision: all staff inactive
-- expect: none
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
update public.staff set active = false;
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V10r record_decision: AO {jhs} on Grade 7
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V10c change_decision: AO {jhs} on Grade 7
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- probe: V11r record_decision: AO {primary} with can_decide on Grade 3 stage document_review
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'ok');

-- probe: V11c change_decision: AO {primary} with can_decide on Grade 3 stage document_review
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'ok');

-- ================================================================ error order: capability before scope, and identical not-found text

-- probe: E1r record_decision: AO without can_decide on an out-of-scope application gets the capability message
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'You need the admissions decide permission to do this' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E1c change_decision: AO without can_decide on an out-of-scope application gets the capability message
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'You need the admissions decide permission to do this' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E2r record_decision: missing id gets Application not found (Manager and AO with can_decide)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-0004000000ff', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Application not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E3r record_decision: out-of-scope id gets Application not found for the AO (Manager succeeds, so denied)
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Application not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E4r record_decision: missing and out-of-scope ids give identical text
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$
declare m1 text; m2 text;
begin
  begin perform public.record_decision('9e060000-0000-4000-8000-0004000000ff', 'accepted', ''); exception when others then m1 := sqlerrm; end;
  begin perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', ''); exception when others then m2 := sqlerrm; end;
  if m1 is distinct from m2 or m1 is distinct from 'Application not found' then raise exception 'texts differ: % / %', m1, m2; end if;
end $$;

-- probe: E2c change_decision: missing id gets Application not found (Manager and AO with can_decide)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-0004000000ff', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Application not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E3c change_decision: out-of-scope id gets Application not found for the AO (Manager succeeds, so denied)
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Application not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E4c change_decision: missing and out-of-scope ids give identical text
-- expect: Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$
declare m1 text; m2 text;
begin
  begin perform public.change_decision('9e060000-0000-4000-8000-0004000000ff', 'accepted', ''); exception when others then m1 := sqlerrm; end;
  begin perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', ''); exception when others then m2 := sqlerrm; end;
  if m1 is distinct from m2 or m1 is distinct from 'Application not found' then raise exception 'texts differ: % / %', m1, m2; end if;
end $$;

-- probe: E5 null application id gets Application not found
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision(null, 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Application not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.change_decision(null, 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Application not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: E6 Manager succeeds on a Grade 11 application; AO out of scope, other roles refused
-- expect: Manager
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');

-- ================================================================ behaviour: stage guards, refusals, trimming, stage moves

-- probe: B1 record_decision refused at inquiry
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision can''t be recorded while the application is at inquiry' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B2 record_decision refused at enrolled
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'enrolled', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision can''t be recorded while the application is at enrolled' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B3 change_decision refused at inquiry
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision can''t be changed while the application is at inquiry' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B4 change_decision refused at enrolled
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'enrolled', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision can''t be changed while the application is at enrolled' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B5 record_decision refused when a decision exists (no upsert)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'first');
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'second');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision has already been recorded for this application; change it instead' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 1 and (select decision_type || notes from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 'waitlistedfirst'), false) then raise exception 'existing decision was overwritten'; end if;
end $$;

-- probe: B6 change_decision refused when there is no decision
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'No decision has been recorded for this application yet' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B7 change_decision refused when type and notes are unchanged
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'same');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'same');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The decision is already waitlisted with these notes' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B7b unchanged check compares trimmed notes
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'same');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', '   same  ');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The decision is already waitlisted with these notes' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B7c null notes equal empty notes for the unchanged check
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', null);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The decision is already waitlisted with these notes' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B8 notes are trimmed on record
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '   padded note  ')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select notes from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 'padded note'), false) then raise exception 'notes not trimmed'; end if;
end $$;

-- probe: B9 null notes are stored as empty
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', null)::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select notes from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = ''), false) then raise exception 'null notes not stored empty'; end if;
end $$;

-- probe: B10 notes over 10000 characters refused on record
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', repeat('x', 10001));
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Decision notes can be at most 10,000 characters' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B10b notes over 10000 characters refused on change
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', repeat('x', 10001));
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'Decision notes can be at most 10,000 characters' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B10c exactly 10000 characters (plus padding that trims away) is accepted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', ' ' || repeat('x', 10000) || ' ')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select char_length(notes) from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 10000), false) then raise exception 'length wrong'; end if;
end $$;

-- probe: B11 record_decision refuses an unknown or null decision type
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'maybe', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision must be accepted, waitlisted or rejected' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', null, '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision must be accepted, waitlisted or rejected' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'Accepted', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision must be accepted, waitlisted or rejected' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B11b change_decision refuses an unknown or null decision type
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'maybe', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision must be accepted, waitlisted or rejected' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', null, '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision must be accepted, waitlisted or rejected' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- probe: B12 waitlisted moves the stage to waitlisted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'stage' = 'waitlisted' and r->>'decision_type' = 'waitlisted'), false) then raise exception 'result wrong'; end if;
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'waitlisted'), false) then raise exception 'stage not moved'; end if;
end $$;

-- probe: B13 rejected moves the stage to rejected
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'rejected' and r->>'stage' = 'rejected'), false) then raise exception 'stage not moved'; end if;
end $$;

-- probe: B14 accepted never moves the stage
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture'),
  ('9e060000-0000-4000-8000-000300000003', '9e060000-0000-4000-8000-000100000001', 'Child 3 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'document_review', null),
  ('9e060000-0000-4000-8000-000400000003', '9e060000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000002', 'accepted', '');
select public.record_decision('9e060000-0000-4000-8000-000400000003', 'accepted', '');
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'application' and (select stage from public.applications where id = '9e060000-0000-4000-8000-000400000002') = 'document_review' and (select stage from public.applications where id = '9e060000-0000-4000-8000-000400000003') = 'waitlisted'), false) then raise exception 'accepted moved a stage'; end if;
end $$;

-- probe: B15 rejected then accepted leaves the stage at rejected
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '');
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'reconsidered')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'rejected' and r->>'stage' = 'rejected'), false) then raise exception 'stage moved by accepted'; end if;
end $$;

-- probe: B16 change waitlisted to rejected moves the stage; waitlisted at waitlisted is fine
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture'),
  ('9e060000-0000-4000-8000-000300000002', '9e060000-0000-4000-8000-000100000001', 'Child 2 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'waitlisted', null),
  ('9e060000-0000-4000-8000-000400000002', '9e060000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000002', 'rejected', '');
-- as role:
select public.change_decision('9e060000-0000-4000-8000-000400000002', 'waitlisted', 'x');
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'rejected' and (select stage from public.applications where id = '9e060000-0000-4000-8000-000400000002') = 'waitlisted'), false) then raise exception 'stages wrong'; end if;
end $$;

-- probe: B16b record waitlisted at an application already waitlisted leaves the stage
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'waitlisted'), false) then raise exception 'stage wrong'; end if;
end $$;

-- ================================================================ behaviour: offers when leaving accepted

-- probe: B17 accepted to rejected with a pending in-date offer: withdrawn, flagged, stage rejected
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'no place')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is true and r->>'stage' = 'rejected'), false) then raise exception 'result wrong'; end if;
  if not coalesce(((select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'withdrawn'), false) then raise exception 'offer not withdrawn'; end if;
  if not coalesce(((select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'rejected'), false) then raise exception 'stage not rejected'; end if;
  if not coalesce(((select decision_type from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 'rejected'), false) then raise exception 'decision not changed'; end if;
end $$;

-- probe: B17b accepted to waitlisted with a pending in-date offer: withdrawn, stage waitlisted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is true and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'withdrawn' and r->>'stage' = 'waitlisted'), false) then raise exception 'wrong'; end if;
end $$;

-- probe: B17c pending offer with no expiry date is withdrawn too
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', null, 'pending');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is true and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'withdrawn'), false) then raise exception 'wrong'; end if;
end $$;

-- probe: B18 an accepted offer blocks the change and nothing moves
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
do $$ begin
  perform public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The parent has accepted the offer, so the decision can''t be changed' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'accepted' and (select decision_type from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 'accepted' and (select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'offer'), false) then raise exception 'state changed'; end if;
end $$;

-- probe: B19 a declined offer is left untouched when leaving accepted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is false and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'declined'), false) then raise exception 'offer touched'; end if;
end $$;

-- probe: B19 a expired offer is left untouched when leaving accepted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'expired');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is false and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'expired'), false) then raise exception 'offer touched'; end if;
end $$;

-- probe: B19 a withdrawn offer is left untouched when leaving accepted
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is false and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'withdrawn'), false) then raise exception 'offer touched'; end if;
end $$;

-- probe: B20 a pending offer past its expiry is left as pending (not withdrawn, not rewritten)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() - interval '1 hour', 'pending');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is false and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'pending'), false) then raise exception 'offer touched'; end if;
end $$;

-- probe: B21 from stage offer_declined to waitlisted works
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'stage' = 'waitlisted' and (select stage from public.applications where id = '9e060000-0000-4000-8000-000400000001') = 'waitlisted' and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'declined'), false) then raise exception 'wrong'; end if;
end $$;

-- probe: B22 accepted to accepted (notes only) leaves a pending offer alone
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'new note')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is false and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'pending' and (select notes from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = 'new note'), false) then raise exception 'wrong'; end if;
end $$;

-- probe: B23 waitlisted to rejected with a pending offer present leaves the offer alone
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e060000-0000-4000-8000-000400000001', md5('o1') || md5('p1'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((r->>'offer_withdrawn')::boolean is false and (select response from public.application_offers where application_id = '9e060000-0000-4000-8000-000400000001') = 'pending'), false) then raise exception 'offer touched'; end if;
end $$;

-- probe: B24 record_decision result keys
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select array_agg(k order by k) from jsonb_object_keys(r) k) = array['capacity_warning','decision_type','stage']), false) then raise exception 'record keys wrong'; end if;
end $$;

-- probe: B24b change_decision result keys
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select array_agg(k order by k) from jsonb_object_keys(r) k) = array['capacity_warning','decision_type','offer_withdrawn','stage']), false) then raise exception 'change keys wrong'; end if;
end $$;

-- probe: B25 decided_by is forced to the caller on record
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select decided_by from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid), false) then raise exception 'decided_by not the caller'; end if;
end $$;

-- probe: B25b decided_by moves to the caller on change
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', '');
update public.application_decisions set decided_by = (select id from public.staff where role = 'Accountant' and active order by id limit 1);
-- as role:
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select decided_by from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid), false) then raise exception 'decided_by not the caller'; end if;
end $$;

-- probe: B26 one decision per application after record then refused second record
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'a');
do $$ begin
  perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'b');
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'A decision has already been recorded for this application; change it instead' then raise exception 'wrong outcome: %', sqlerrm; end if;
end $$;

-- ================================================================ audit: application_decision_changed

-- probe: U1 record writes one row: before null, after {decision_type, application_reference}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
update public.applications set application_reference = 'APP-2027-0001' where id = '9e060000-0000-4000-8000-000400000001';
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'SECRETNOTE')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'application_decision_changed') = 1), false) then raise exception 'row count'; end if;
  if not coalesce(((select before is null and after = jsonb_build_object('decision_type', 'accepted', 'application_reference', 'APP-2027-0001') and entity_table = 'application_decisions' and entity_id = (select id::text from public.application_decisions where application_id = '9e060000-0000-4000-8000-000400000001') and actor_id = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid from public.audit_log where action = 'application_decision_changed')), false) then raise exception 'row wrong'; end if;
end $$;

-- probe: U1b audit branch is the staff member's branch when the application has none
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select branch_id from public.audit_log where action = 'application_decision_changed') = (select branch_id from public.staff where id = (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid)), false) then raise exception 'branch wrong'; end if;
end $$;

-- probe: U1c audit branch is the application's branch when it has one
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', '00000000-0000-0000-0000-000000000002');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select set_config('t.r', public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', '')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select branch_id from public.audit_log where action = 'application_decision_changed') = '00000000-0000-0000-0000-000000000002'), false) then raise exception 'branch wrong'; end if;
end $$;

-- probe: U2 a type change writes a row with before {decision_type}
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'n');
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'accepted', 'n')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'application_decision_changed') = 2), false) then raise exception 'row count'; end if;
  if not coalesce((exists (select 1 from public.audit_log where action = 'application_decision_changed' and before = jsonb_build_object('decision_type', 'waitlisted') and after->>'decision_type' = 'accepted')), false) then raise exception 'change row wrong'; end if;
end $$;

-- probe: U3 a notes-only change writes no decision row
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'n');
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'different notes')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'application_decision_changed') = 1), false) then raise exception 'notes-only change wrote a row'; end if;
end $$;

-- probe: U4 payload keys are exactly the planned ones; no notes, no names
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
select public.record_decision('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'SECRETNOTE alpha');
select set_config('t.r', public.change_decision('9e060000-0000-4000-8000-000400000001', 'rejected', 'SECRETNOTE beta')::text, true);
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((not exists (select 1 from public.audit_log where action = 'application_decision_changed' and (coalesce(before::text, '') || after::text) ~* '(secretnote|child|fixture)')), false) then raise exception 'notes or names leaked'; end if;
  if not coalesce((not exists (select 1 from public.audit_log where action = 'application_decision_changed' and ((select array_agg(k order by k) from jsonb_object_keys(after) k) is distinct from array['application_reference', 'decision_type'] or (before is not null and (select array_agg(k) from jsonb_object_keys(before) k) is distinct from array['decision_type'])))), false) then raise exception 'payload keys wrong'; end if;
end $$;

-- probe: U5 no audit row when postgres or service_role (no auth.uid) writes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
reset role;
set local request.jwt.claims = '{}';
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'waitlisted', 'by postgres');
update public.application_decisions set decision_type = 'accepted';
delete from public.application_decisions;
set local request.jwt.claims = '{"role":"service_role"}';
insert into public.application_decisions (application_id, decision_type, notes) values ('9e060000-0000-4000-8000-000400000001', 'rejected', 'by service');
update public.application_decisions set decision_type = 'waitlisted';
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'application_decision_changed') = 0), false) then raise exception 'audit row written without an actor'; end if;
end $$;

-- probe: U6 a refused call writes no audit row
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e060000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e060000-0000-4000-8000-000300000001', '9e060000-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values
  ('9e060000-0000-4000-8000-000400000001', '9e060000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin perform public.record_decision('9e060000-0000-4000-8000-000400000001', 'accepted', ''); exception when others then null; end $$;
reset role;
do $$
declare
  r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce(((select count(*) from public.audit_log where action = 'application_decision_changed') = 0), false) then raise exception 'row written for a refused call'; end if;
end $$;
