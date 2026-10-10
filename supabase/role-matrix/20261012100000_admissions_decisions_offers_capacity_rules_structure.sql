-- Role matrix for 20261012100000_admissions_decisions_offers_capacity_rules, STRUCTURE file (admissions slice 3b,
-- docs/admissions/PORT-PLAN.md): direct writes denied for every role, the
-- grants and RLS shape, the checks (legacy values accepted, bad values
-- refused), unique and delete behaviour, the decision identity trigger, the
-- import shape, and the Annex seed rows. Structural probes do their work as
-- postgres in setup and raise there on failure, so they expect every role;
-- the write probes expect none. All fixture rows are invented (ids
-- 9e03b000-...).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261012100000_admissions_decisions_offers_capacity_rules_structure.sql

-- ================================================================ direct writes are denied for every role, including Manager

-- probe: W insert into application_decisions
-- expect: none
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
insert into public.application_decisions (application_id, decision_type) values ('9e03b000-0000-4000-8000-000400000005', 'accepted');

-- probe: W update application_decisions
-- expect: none
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
update public.application_decisions set notes = 'x';

-- probe: W delete from application_decisions
-- expect: none
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
delete from public.application_decisions;

-- probe: W insert into application_offers
-- expect: none
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
insert into public.application_offers (application_id, token_hash) values ('9e03b000-0000-4000-8000-000400000005', encode(sha256(convert_to('fixture-offer-5', 'UTF8')), 'hex'));

-- probe: W update application_offers
-- expect: none
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
update public.application_offers set response = 'accepted';

-- probe: W delete from application_offers
-- expect: none
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
delete from public.application_offers;

-- probe: W insert into admissions_capacity
-- expect: none
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
insert into public.admissions_capacity (academic_year, grade_id, capacity) values ('2028/2029', (select id from public.admissions_grades where name = 'Grade 2'), 10);

-- probe: W update admissions_capacity
-- expect: none
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
update public.admissions_capacity set capacity = 1;

-- probe: W delete from admissions_capacity
-- expect: none
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
delete from public.admissions_capacity;

-- probe: W insert into admissions_campus_grade_rules
-- expect: none
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
insert into public.admissions_campus_grade_rules (branch_id, grade_id) values ((select id from public.branches where name = 'Main'), (select id from public.admissions_grades where name = 'Grade 2'));

-- probe: W update admissions_campus_grade_rules
-- expect: none
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
update public.admissions_campus_grade_rules set grade_id = (select id from public.admissions_grades where name = 'Grade 2');

-- probe: W delete from admissions_campus_grade_rules
-- expect: none
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
delete from public.admissions_campus_grade_rules;

-- probe: W insert a decision as an AO holding all_grades and can_decide
-- expect: none
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
insert into public.application_decisions (application_id, decision_type) values ('9e03b000-0000-4000-8000-000400000005', 'accepted');

-- probe: W insert an offer as an AO holding all_grades and can_decide
-- expect: none
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
insert into public.application_offers (application_id, token_hash) values ('9e03b000-0000-4000-8000-000400000005', encode(sha256(convert_to('fixture-offer-5', 'UTF8')), 'hex'));

-- ================================================================ grants

-- probe: A1 anon has no privilege; authenticated select only; service_role full; RLS on; one select policy each
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare t text;
begin
  foreach t in array array['public.application_decisions', 'public.application_offers', 'public.admissions_capacity', 'public.admissions_campus_grade_rules'] loop
    if has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'anon holds a privilege on %', t;
    end if;
    if not has_table_privilege('authenticated', t, 'SELECT')
       or has_table_privilege('authenticated', t, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'authenticated privileges wrong on %', t;
    end if;
    if not (has_table_privilege('service_role', t, 'SELECT') and has_table_privilege('service_role', t, 'INSERT')
            and has_table_privilege('service_role', t, 'UPDATE') and has_table_privilege('service_role', t, 'DELETE')) then
      raise exception 'service_role privileges wrong on %', t;
    end if;
    if not (select relrowsecurity from pg_class where oid = t::regclass) then
      raise exception 'RLS off on %', t;
    end if;
    if (select count(*) from pg_policies where schemaname || '.' || tablename = t) <> 1
       or exists (select 1 from pg_policies where schemaname || '.' || tablename = t and cmd <> 'SELECT') then
      raise exception 'policies wrong on %', t;
    end if;
  end loop;
end $$;

-- probe: A2 the trigger function is executable by nobody signed in or anon
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if has_function_privilege('anon', 'public.set_application_decision_identity()', 'execute')
     or has_function_privilege('authenticated', 'public.set_application_decision_identity()', 'execute') then
    raise exception 'unexpected execute privilege';
  end if;
end $$;

-- probe: A3 the predicates the policies call are security definer with search_path pinned
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (
    select 1 from pg_proc
    where oid in ('public.admissions_application_visible(uuid)'::regprocedure,
                  'public.admissions_grade_visible(text)'::regprocedure,
                  'public.has_admissions_capability(text)'::regprocedure,
                  'public.has_role(text[])'::regprocedure)
      and (not prosecdef or not coalesce('search_path=public' = any (proconfig), false))
  ) then
    raise exception 'a predicate lost security definer or its search_path';
  end if;
end $$;

-- ================================================================ checks accept legacy values and refuse bad ones (run as postgres in setup)

-- probe: C1 legacy-shaped values are accepted
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
update public.application_offers set response = 'accepted', responded_at = '2026-10-02 10:00+00' where id = '9e03b000-0000-4000-8000-000800000001';
insert into public.application_offers (application_id, token_hash)
  values ('9e03b000-0000-4000-8000-000400000005', encode(sha256(convert_to('AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE', 'UTF8')), 'hex'));
update public.application_decisions set decided_by = null where id = '9e03b000-0000-4000-8000-000700000001';
update public.admissions_capacity set capacity = 0 where id = '9e03b000-0000-4000-8000-000900000001';
insert into public.admissions_capacity (academic_year, grade_id, branch_id, capacity)
  values ('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Annex'), 5);
-- as role:
select 1;

-- probe: C2 refused: decision_type pending
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.application_decisions set decision_type = 'pending' where id = '9e03b000-0000-4000-8000-000700000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: oversized decision notes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.application_decisions set notes = repeat('x', 10001) where id = '9e03b000-0000-4000-8000-000700000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: offer response maybe
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.application_offers set response = 'maybe' where id = '9e03b000-0000-4000-8000-000800000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: raw 43-character token stored as the hash
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.application_offers set token_hash = repeat('A', 43) where id = '9e03b000-0000-4000-8000-000800000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: uppercase hex hash
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.application_offers set token_hash = upper(encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex')) where id = '9e03b000-0000-4000-8000-000800000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: null token_hash
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.application_offers set token_hash = null where id = '9e03b000-0000-4000-8000-000800000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: blank academic year
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.admissions_capacity set academic_year = '  ' where id = '9e03b000-0000-4000-8000-000900000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: academic year over 50 characters
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.admissions_capacity set academic_year = repeat('9', 51) where id = '9e03b000-0000-4000-8000-000900000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: negative capacity
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.admissions_capacity set capacity = -1 where id = '9e03b000-0000-4000-8000-000900000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: null capacity
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.admissions_capacity set capacity = null where id = '9e03b000-0000-4000-8000-000900000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: capacity with an unknown grade
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.admissions_capacity set grade_id = gen_random_uuid() where id = '9e03b000-0000-4000-8000-000900000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: capacity with an unknown branch
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  update public.admissions_capacity set branch_id = gen_random_uuid() where id = '9e03b000-0000-4000-8000-000900000001';
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: rule with an unknown grade
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.admissions_campus_grade_rules (branch_id, grade_id) values ((select id from public.branches where name = 'Main'), gen_random_uuid());
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C2 refused: rule with an unknown branch
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.admissions_campus_grade_rules (branch_id, grade_id) values (gen_random_uuid(), (select id from public.admissions_grades where name = 'Grade 2'));
  raise exception 'accepted a bad value';
exception when check_violation or foreign_key_violation or not_null_violation then null;
end $$;
-- as role:
select 1;

-- probe: C3 refused: a second decision for one application
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.application_decisions (application_id, decision_type) values ('9e03b000-0000-4000-8000-000400000001', 'rejected');
  raise exception 'accepted a duplicate';
exception when unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C3 refused: a second offer for one application
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.application_offers (application_id, token_hash) values ('9e03b000-0000-4000-8000-000400000001', encode(sha256(convert_to('fixture-offer-9', 'UTF8')), 'hex'));
  raise exception 'accepted a duplicate';
exception when unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C3 refused: a duplicate token_hash
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.application_offers (application_id, token_hash) values ('9e03b000-0000-4000-8000-000400000005', encode(sha256(convert_to('fixture-offer-1', 'UTF8')), 'hex'));
  raise exception 'accepted a duplicate';
exception when unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C3 refused: duplicate capacity for one campus
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.admissions_capacity (academic_year, grade_id, branch_id, capacity) values ('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Main'), 1);
  raise exception 'accepted a duplicate';
exception when unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C3 refused: duplicate capacity with no campus
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.admissions_capacity (academic_year, grade_id, branch_id, capacity) values ('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 1);
  raise exception 'accepted a duplicate';
exception when unique_violation then null;
end $$;
-- as role:
select 1;

-- probe: C3 refused: a duplicate campus rule
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  insert into public.admissions_campus_grade_rules (branch_id, grade_id) values ((select id from public.branches where name = 'Annex'), (select id from public.admissions_grades where name = 'Pre Nursery'));
  raise exception 'accepted a duplicate';
exception when unique_violation then null;
end $$;
-- as role:
select 1;

-- ================================================================ delete behaviour

-- probe: C4 deleting an application removes its decision and offer
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
delete from public.applications where id = '9e03b000-0000-4000-8000-000400000001';
do $$ begin
  if exists (select 1 from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001')
     or exists (select 1 from public.application_offers where id = '9e03b000-0000-4000-8000-000800000001') then
    raise exception 'cascade incomplete';
  end if;
end $$;
-- as role:
select 1;

-- probe: C5 a grade used by capacity or a rule can't be deleted
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  delete from public.admissions_grades where name = 'Grade 3';
  raise exception 'grade used by capacity was deleted';
exception when foreign_key_violation then null; end $$;
do $$ begin
  delete from public.admissions_grades where name = 'Nursery 1';
  raise exception 'grade used by a campus rule was deleted';
exception when foreign_key_violation then null; end $$;
-- as role:
select 1;

-- probe: C6 a branch used by capacity or a rule can't be deleted
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
do $$ begin
  delete from public.admissions_campus_grade_rules where branch_id = (select id from public.branches where name = 'Annex');
  delete from public.admissions_capacity where branch_id is not null;
  insert into public.admissions_capacity (academic_year, grade_id, branch_id, capacity)
    values ('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), (select id from public.branches where name = 'Annex'), 1);
  delete from public.branches where name = 'Annex';
  raise exception 'branch used by capacity was deleted';
exception when foreign_key_violation then null; end $$;
do $$ begin
  delete from public.branches where name = 'Annex';
  raise exception 'branch used by a campus rule was deleted';
exception when foreign_key_violation then null; end $$;
-- as role:
select 1;

-- probe: C7 the decided_by foreign key is declared on delete set null
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select confdeltype from pg_constraint where conrelid = 'public.application_decisions'::regclass
        and contype = 'f' and conkey = array[(select attnum from pg_attribute
          where attrelid = 'public.application_decisions'::regclass and attname = 'decided_by')]) <> 'n' then
    raise exception 'decided_by is not on delete set null';
  end if;
end $$;
-- as role:
select 1;

-- ================================================================ decision identity trigger

-- probe: R1a signed-in insert: decided_by and decided_at are forced
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.application_decisions (id, application_id, decision_type, decided_by, decided_at)
  values ('9e03b000-0000-4000-8000-000700000005', '9e03b000-0000-4000-8000-000400000005', 'accepted', (select id from public.staff where role = 'Accountant' and active order by id limit 1), '2020-01-01');
select set_config('request.jwt.claims', '', true);
do $$ begin
  if (select decided_by from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000005') is distinct from (select id from public.staff where role = 'Manager' and active order by id limit 1)
     or (select decided_at from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000005') < now() - interval '1 minute' then
    raise exception 'identity not forced on insert';
  end if;
end $$;
-- as role:
select 1;

-- probe: R1b signed-in update: decided_by and decided_at are re-stamped
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
update public.application_decisions set decided_at = '2020-01-01' where id = '9e03b000-0000-4000-8000-000700000001';
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Auditor' and active order by id limit 1))::text, true);
update public.application_decisions set notes = 'changed' where id = '9e03b000-0000-4000-8000-000700000001';
select set_config('request.jwt.claims', '', true);
do $$ begin
  if (select decided_by from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') is distinct from (select id from public.staff where role = 'Auditor' and active order by id limit 1)
     or (select decided_at from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001') < now() - interval '1 minute' then
    raise exception 'identity not re-stamped on update';
  end if;
end $$;
-- as role:
select 1;

-- probe: R1c no signed-in user, insert: supplied values stand
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
insert into public.application_decisions (id, application_id, decision_type, decided_by, decided_at)
  values ('9e03b000-0000-4000-8000-000700000005', '9e03b000-0000-4000-8000-000400000005', 'waitlisted', null, '2026-09-04 09:00+00');
do $$ begin
  if (select (decided_by, decided_at) from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000005')
     is distinct from (null::uuid, '2026-09-04 09:00+00'::timestamptz) then
    raise exception 'supplied values not kept on insert';
  end if;
end $$;
-- as role:
select 1;

-- probe: R1d no signed-in user, update: values untouched
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
update public.application_decisions set decided_by = (select id from public.staff where role = 'Manager' and active order by id limit 1), decided_at = '2026-09-04 09:00+00' where id = '9e03b000-0000-4000-8000-000700000001';
update public.application_decisions set notes = 'changed' where id = '9e03b000-0000-4000-8000-000700000001';
do $$ begin
  if (select (decided_by, decided_at) from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000001')
     is distinct from ((select id from public.staff where role = 'Manager' and active order by id limit 1), '2026-09-04 09:00+00'::timestamptz) then
    raise exception 'values changed on update';
  end if;
end $$;
-- as role:
select 1;

-- ================================================================ import shape

-- probe: I1 a legacy-shaped decision, offer and capacity keep ids and timestamps
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
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
insert into public.application_decisions (id, application_id, decision_type, decided_at, notes)
  values ('9e03b000-0000-4000-8000-000700000009', '9e03b000-0000-4000-8000-000400000005', 'accepted', '2026-09-03 10:00+00', 'Legacy note');
insert into public.application_offers (id, application_id, token_hash, sent_at, expires_at, response, responded_at)
  values ('9e03b000-0000-4000-8000-000800000009', '9e03b000-0000-4000-8000-000400000005', encode(sha256(convert_to('legacy-offer', 'UTF8')), 'hex'), '2026-09-03 11:00+00', '2026-09-17 11:00+00', 'declined', '2026-09-05 08:00+00');
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity)
  values ('9e03b000-0000-4000-8000-000900000009', '2026/2027', (select id from public.admissions_grades where name = 'Grade 2'), null, 30);
do $$ begin
  if (select decided_at from public.application_decisions where id = '9e03b000-0000-4000-8000-000700000009') <> '2026-09-03 10:00+00'
     or (select (sent_at, expires_at, response, responded_at) from public.application_offers where id = '9e03b000-0000-4000-8000-000800000009')
        is distinct from ('2026-09-03 11:00+00'::timestamptz, '2026-09-17 11:00+00'::timestamptz, 'declined'::text, '2026-09-05 08:00+00'::timestamptz)
     or (select capacity from public.admissions_capacity where id = '9e03b000-0000-4000-8000-000900000009') <> 30 then
    raise exception 'legacy values not preserved';
  end if;
end $$;
-- as role:
select 1;

-- ================================================================ seed

-- probe: S1 after reset, Annex has exactly Pre Nursery and Nursery 1, and no other campus has a rule
-- expect: Manager,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(g.name order by g.name) from public.admissions_campus_grade_rules r
        join public.admissions_grades g on g.id = r.grade_id
        join public.branches b on b.id = r.branch_id where b.name = 'Annex')
     is distinct from array['Nursery 1', 'Pre Nursery'] then
    raise exception 'Annex rules wrong';
  end if;
  if exists (select 1 from public.admissions_campus_grade_rules r
             join public.branches b on b.id = r.branch_id where b.name <> 'Annex') then
    raise exception 'another campus has a rule';
  end if;
end $$;
