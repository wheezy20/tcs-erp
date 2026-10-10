-- Role matrix for 20261012100000_admissions_decisions_offers_capacity_rules, VISIBILITY file (admissions slice 3b,
-- docs/admissions/PORT-PLAN.md): reads on application_decisions,
-- application_offers, admissions_capacity and admissions_campus_grade_rules.
-- Each probe raises unless the stated rows are visible (or the count holds),
-- so the expect line lists the roles for which the statement holds. All
-- fixture rows are invented (ids 9e03b000-...); capability rows go on the
-- accounts the harness impersonates (role, active, lowest id). The rule
-- probes read the Annex rows that seed.sql inserts.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261012100000_admissions_decisions_offers_capacity_rules_visibility.sql

-- ================================================================ application_decisions (D-3g: role, or officer in scope with can_decide)

-- probe: DEC1 Grade 3, no capability rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC2 Grade 3, AO with {primary} but no can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC3 Grade 3, AO with {primary} and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC4 Grade 3, AO with {jhs} and can_decide (out of scope)
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC5 Grade 3, AO with all_grades and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC6 Grade 3, AO with all_grades but no can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC7 Grade 3, AO with can_decide only, no scope
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC8 Grade 11 (unbanded), AO with all three bands and can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC9 Grade 11, AO with all_grades and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC10 legacy label '2027', AO with all three bands and can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC11 legacy label '2027', AO with all_grades and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC12 Grade 3 moved to Grade 7, AO with {primary} and can_decide loses it
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e03b000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC13 Grade 3 moved to Grade 7, AO with {jhs} and can_decide gains it
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e03b000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC14 inactive AO with {primary} and can_decide sees nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
update public.staff set active = false where id = (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC15 Attendant and Accountant holding can_view_health still see nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC15b Attendant and Accountant holding can_decide and all_grades still see nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
alter table public.staff_admissions_capabilities disable trigger staff_admissions_capabilities_check_holder;
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', true, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', true, true, false);
alter table public.staff_admissions_capabilities enable trigger staff_admissions_capabilities_check_holder;
-- as role:
do $$ begin
  if not exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: DEC16 Manager and Auditor see all 4 rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_decisions where id in ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000700000004');
  if c <> 4 then raise exception 'count %', c; end if;
end $$;

-- probe: DEC17 AO with {primary} and can_decide sees exactly 1 row
-- expect: Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_decisions where id in ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000700000004');
  if c <> 1 then raise exception 'count %', c; end if;
end $$;

-- ================================================================ application_offers (same rule)

-- probe: OFF1 Grade 3, no capability rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF2 Grade 3, AO with {primary} but no can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF3 Grade 3, AO with {primary} and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF4 Grade 3, AO with {jhs} and can_decide (out of scope)
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF5 Grade 3, AO with all_grades and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF6 Grade 3, AO with all_grades but no can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, false, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF7 Grade 3, AO with can_decide only, no scope
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF10 legacy label '2027', AO with all three bands and can_decide
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF11 legacy label '2027', AO with all_grades and can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000004') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF12 Grade 3 moved to Grade 7, AO with {primary} and can_decide loses it
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e03b000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF13 Grade 3 moved to Grade 7, AO with {jhs} and can_decide gains it
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e03b000-0000-4000-8000-000400000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF14 inactive AO with {primary} and can_decide sees nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
update public.staff set active = false where id = (select id from public.staff where role = 'Admissions Officer' and active order by id limit 1);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF15 Attendant and Accountant holding can_view_health still see nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF15b Attendant and Accountant holding can_decide and all_grades still see nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
alter table public.staff_admissions_capabilities disable trigger staff_admissions_capabilities_check_holder;
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', true, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', true, true, false);
alter table public.staff_admissions_capabilities enable trigger staff_admissions_capabilities_check_holder;
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: OFF16 Manager and Auditor see all 3 rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_offers where id in ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000800000004');
  if c <> 3 then raise exception 'count %', c; end if;
end $$;

-- probe: OFF17 AO with {primary} and can_decide sees exactly 1 row
-- expect: Admissions Officer
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.application_offers where id in ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000800000004');
  if c <> 1 then raise exception 'count %', c; end if;
end $$;

-- ================================================================ admissions_capacity (D-3c: Manager and Auditor only)

-- probe: CAP1 capacity row visible
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_capacity where id = '9e03b000-0000-4000-8000-000900000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: CAP2 AO with all_grades, can_decide and can_view_health still can't read capacity
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_capacity where id = '9e03b000-0000-4000-8000-000900000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: CAP3 Manager and Auditor see both capacity rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e03b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e03b000-0000-4000-8000-000300000001', '9e03b000-0000-4000-8000-000100000001', 'Child One Fixture'), ('9e03b000-0000-4000-8000-000300000002', '9e03b000-0000-4000-8000-000100000001', 'Child Two Fixture'),
  ('9e03b000-0000-4000-8000-000300000003', '9e03b000-0000-4000-8000-000100000001', 'Child Three Fixture'), ('9e03b000-0000-4000-8000-000300000004', '9e03b000-0000-4000-8000-000100000001', 'Child Four Fixture'),
  ('9e03b000-0000-4000-8000-000300000005', '9e03b000-0000-4000-8000-000100000001', 'Child Five Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e03b000-0000-4000-8000-000400000001', '9e03b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'), ('9e03b000-0000-4000-8000-000400000002', '9e03b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e03b000-0000-4000-8000-000400000003', '9e03b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'), ('9e03b000-0000-4000-8000-000400000004', '9e03b000-0000-4000-8000-000300000004', '2027/2028', '2027'),
  ('9e03b000-0000-4000-8000-000400000005', '9e03b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 2');
insert into public.application_decisions (id, application_id, decision_type) values
  ('9e03b000-0000-4000-8000-000700000001', '9e03b000-0000-4000-8000-000400000001', 'accepted'), ('9e03b000-0000-4000-8000-000700000002', '9e03b000-0000-4000-8000-000400000002', 'waitlisted'),
  ('9e03b000-0000-4000-8000-000700000003', '9e03b000-0000-4000-8000-000400000003', 'rejected'), ('9e03b000-0000-4000-8000-000700000004', '9e03b000-0000-4000-8000-000400000004', 'accepted');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at) values
  ('9e03b000-0000-4000-8000-000800000001', '9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00'),
  ('9e03b000-0000-4000-8000-000800000002', '9e03b000-0000-4000-8000-000400000002', encode(sha256(convert_to('fixture-offer-2', 'UTF8')), 'hex'), null, null),
  ('9e03b000-0000-4000-8000-000800000004', '9e03b000-0000-4000-8000-000400000004', encode(sha256(convert_to('fixture-offer-4', 'UTF8')), 'hex'), '2026-10-01 09:00+00', '2026-10-15 09:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values
  ('9e03b000-0000-4000-8000-000900000001', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 25),
  ('9e03b000-0000-4000-8000-000900000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 40);
-- as role:
do $$
declare c int;
begin
  select count(*) into c from public.admissions_capacity where id in ('9e03b000-0000-4000-8000-000900000001', '9e03b000-0000-4000-8000-000900000002');
  if c <> 2 then raise exception 'count %', c; end if;
end $$;

-- ================================================================ admissions_campus_grade_rules (A4: Manager, Auditor, Admissions Officer)

-- probe: RUL1 an Annex rule is visible, AO with no capability row
-- expect: Manager,Auditor,Admissions Officer
do $$ begin
  if not exists (select 1 from public.admissions_campus_grade_rules r
                 join public.branches b on b.id = r.branch_id where b.name = 'Annex') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: RUL2 an Annex rule is visible, AO with can_decide only
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_campus_grade_rules r
                 join public.branches b on b.id = r.branch_id where b.name = 'Annex') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: RUL3 Attendant and Accountant holding can_view_health still see no rule
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Attendant' and active order by id limit 1), '{}', false, false, true);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Accountant' and active order by id limit 1), '{}', false, false, true);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_campus_grade_rules r
                 join public.branches b on b.id = r.branch_id where b.name = 'Annex') then
    raise exception 'not visible';
  end if;
end $$;
