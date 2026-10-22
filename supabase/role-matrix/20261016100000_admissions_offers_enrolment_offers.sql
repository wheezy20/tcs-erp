-- Role matrix for 20261016100000_admissions_offers_enrolment, OFFERS file (admissions slice 6b,
-- docs/admissions/PORT-PLAN.md): generate_offer, reset_offer and
-- record_offer_response as each role: the authorization grid (capability
-- and scope variants), error order, token hashing (only the SHA-256 is
-- stored, a reset changes it and the old hash is gone), expiry, refusals,
-- application_offer_changed audit rows, and who reads application_offer_status.
-- All fixture rows are invented (ids 9e06b000-...). Capabilities are set
-- inside each probe's rolled-back setup.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261016100000_admissions_offers_enrolment_offers.sql

-- probe: V0 generate_offer: base: Manager and AO hold can_decide, AO {primary}, Grade 3
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V0 reset_offer: base: Manager and AO hold can_decide, AO {primary}, Grade 3
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V0 record_offer_response: base: Manager and AO hold can_decide, AO {primary}, Grade 3
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V1 generate_offer: nobody holds can_decide
-- expect: none
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V1 reset_offer: nobody holds can_decide
-- expect: none
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V1 record_offer_response: nobody holds can_decide
-- expect: none
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V2 generate_offer: only the AO holds can_decide
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V2 reset_offer: only the AO holds can_decide
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V2 record_offer_response: only the AO holds can_decide
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V3 generate_offer: AO can_decide with no bands
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V3 reset_offer: AO can_decide with no bands
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V3 record_offer_response: AO can_decide with no bands
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V4 generate_offer: AO {primary} on a Grade 7 application
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V4 reset_offer: AO {primary} on a Grade 7 application
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V4 record_offer_response: AO {primary} on a Grade 7 application
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V5 generate_offer: AO {primary,jhs,preschool} on Grade 11 (unbanded)
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary,jhs,preschool}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V5 reset_offer: AO {primary,jhs,preschool} on Grade 11 (unbanded)
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary,jhs,preschool}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V5 record_offer_response: AO {primary,jhs,preschool} on Grade 11 (unbanded)
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary,jhs,preschool}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V6 generate_offer: AO all_grades on Grade 11
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V6 reset_offer: AO all_grades on Grade 11
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V6 record_offer_response: AO all_grades on Grade 11
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: V7 generate_offer: AO all_grades on a free-text 2027 grade
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', '2027', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V7 reset_offer: AO all_grades on a free-text 2027 grade
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', '2027', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
select public.reset_offer('9e06b000-0000-4000-8000-000400000001');

-- probe: V7 record_offer_response: AO all_grades on a free-text 2027 grade
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', '2027', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');

-- probe: E1 generate_offer: without can_decide, out of scope still gives the capability message (capability before scope)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'document_review', null);

insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'You need the admissions decide permission to do this' then raise; end if;
end $$;

-- probe: E2 generate_offer: the Auditor gets the read-only message while others hold can_decide (role before capability)
-- expect: Auditor
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Auditor is read-only and cannot perform this action' then raise; end if;
end $$;

-- probe: E3 generate_offer: out of scope and not found give the same message
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'document_review', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000499999999');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;

-- probe: E1 reset_offer: without can_decide, out of scope still gives the capability message (capability before scope)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer_declined', null);

insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'You need the admissions decide permission to do this' then raise; end if;
end $$;

-- probe: E2 reset_offer: the Auditor gets the read-only message while others hold can_decide (role before capability)
-- expect: Auditor
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Auditor is read-only and cannot perform this action' then raise; end if;
end $$;

-- probe: E3 reset_offer: out of scope and not found give the same message
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
-- as role:
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000499999999');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;

-- probe: E1 record_offer_response: without can_decide, out of scope still gives the capability message (capability before scope)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer', null);

insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'You need the admissions decide permission to do this' then raise; end if;
end $$;

-- probe: E2 record_offer_response: the Auditor gets the read-only message while others hold can_decide (role before capability)
-- expect: Auditor
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Auditor is read-only and cannot perform this action' then raise; end if;
end $$;

-- probe: E3 record_offer_response: out of scope and not found give the same message
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000499999999', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;

-- Changed in slice 11 (20261031110000, D-11d): no raw token is returned or
-- stored any more; links are minted at send time (see the slice 11 probes).
-- probe: B1 generate_offer: no token returned or stored; pending, 14 days, stage offer
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
do $$
declare r jsonb; o public.application_offers; a public.applications;
begin
  r := public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  if r ? 'token' then raise exception 'token returned'; end if;
  if r->>'stage' <> 'offer' then raise exception 'stage not returned'; end if;
end $$;
reset role;
do $$
declare o public.application_offers;
begin
  select * into o from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001';
  if o.token_hash is not null then raise exception 'a hash was stored'; end if;
  if o.response <> 'pending' or o.responded_at is not null then raise exception 'not pending'; end if;
  if o.expires_at - o.sent_at <> interval '14 days' then raise exception 'ttl wrong: %', o.expires_at - o.sent_at; end if;
  if o.sent_at < now() then raise exception 'sent_at before the transaction'; end if;
  if (select stage from public.applications where id = '9e06b000-0000-4000-8000-000400000001') <> 'offer' then raise exception 'stage not offer'; end if;
  if exists (select 1 from public.audit_log l where l.before::text ~ '[0-9a-f]{64}' or l.after::text ~ '[0-9a-f]{64}') then
    raise exception 'token or hash in the audit log';
  end if;
end $$;

-- probe: B2 generate_offer: uses admissions_settings.offer_ttl_days
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
update public.admissions_settings set offer_ttl_days = 30;
-- as role:
select public.generate_offer('9e06b000-0000-4000-8000-000400000001');
reset role;
do $$ begin
  if (select expires_at - sent_at from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001') <> interval '30 days' then
    raise exception 'ttl not read from settings';
  end if;
end $$;

-- Changed in slice 11 (20261031110000, D-11d): no raw token is returned or
-- stored any more; links are minted at send time (see the slice 11 probes).
-- probe: B3 generate_offer: two calls on two applications, neither returns a token
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
-- as role:
do $$ begin
  if (public.generate_offer('9e06b000-0000-4000-8000-000400000001') ? 'token')
     or (public.generate_offer('9e06b000-0000-4000-8000-000400000002') ? 'token') then
    raise exception 'token returned';
  end if;
end $$;

-- probe: B4 generate_offer: refused with no decision, a waitlisted decision, or an existing offer
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'waitlisted', 'seeded');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
-- as role:
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer needs an accepted decision' then raise; end if;
end $$;
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000002');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer needs an accepted decision' then raise; end if;
end $$;
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000003');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer already exists for this application; reset it instead' then raise; end if;
end $$;

-- probe: B5 generate_offer: allowed from waitlisted and rejected when the decision is accepted (the gate is the decision)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'rejected', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
-- as role:
do $$ begin
  if public.generate_offer('9e06b000-0000-4000-8000-000400000001')->>'stage' <> 'offer' then raise exception 'waitlisted not moved'; end if;
  if public.generate_offer('9e06b000-0000-4000-8000-000400000002')->>'stage' <> 'offer' then raise exception 'rejected not moved'; end if;
end $$;

-- probe: B6 generate_offer: refused at inquiry, offer, offer_declined and enrolled
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000004');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000004', '9e06b000-0000-4000-8000-000100000004', 'Child 4 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000004', '9e06b000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3', 'enrolled', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000004', 'accepted', 'seeded');
-- as role:
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer can''t be generated while the application is at inquiry' then raise; end if;
end $$;
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000002');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer can''t be generated while the application is at offer' then raise; end if;
end $$;
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000003');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer can''t be generated while the application is at offer_declined' then raise; end if;
end $$;
do $$ begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000004');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer can''t be generated while the application is at enrolled' then raise; end if;
end $$;

-- Changed in slice 11 (20261031110000, D-11d): no raw token is returned or
-- stored any more; links are minted at send time (see the slice 11 probes).
-- probe: B7 reset_offer: no token, old hash gone, a new link generation, fresh pending offer, stage back to offer
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('oldtoken', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
update public.application_offers set responded_at = now() - interval '1 hour';
-- as role:
do $$
declare r jsonb;
begin
  r := public.reset_offer('9e06b000-0000-4000-8000-000400000001');
  if r ? 'token' then raise exception 'token returned'; end if;
  if r->>'stage' <> 'offer' then raise exception 'stage not offer'; end if;
end $$;
reset role;
do $$
declare o public.application_offers;
begin
  select * into o from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001';
  if o.token_hash is not null then raise exception 'hash kept after reset'; end if;
  if o.link_generation <> 1 then raise exception 'no new link generation'; end if;
  if exists (select 1 from public.application_offers where token_hash = encode(extensions.digest('oldtoken', 'sha256'), 'hex')) then
    raise exception 'old link still finds an offer';
  end if;
  if o.response <> 'pending' or o.responded_at is not null then raise exception 'not a fresh pending offer'; end if;
  if o.expires_at - o.sent_at <> interval '14 days' or o.sent_at < now() then raise exception 'dates not fresh'; end if;
  if (select stage from public.applications where id = '9e06b000-0000-4000-8000-000400000001') <> 'offer' then raise exception 'stage not offer'; end if;
end $$;

-- Changed in slice 11 (20261031110000, D-11d): no raw token is returned or
-- stored any more; links are minted at send time (see the slice 11 probes).
-- probe: B8 reset_offer: twice in a row gives two new link generations (pending offer, lost link)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$
begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000001');
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000001');
end $$;
reset role;
do $$
declare o public.application_offers;
begin
  select * into o from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001';
  if o.link_generation <> 2 or o.token_hash is not null then
    raise exception 'reset did not replace the links twice';
  end if;
end $$;

-- probe: B9 reset_offer: allowed on expired and withdrawn offers; refused on accepted, with no offer, and without an accepted decision
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 hour', 'pending');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000004');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000004', '9e06b000-0000-4000-8000-000100000004', 'Child 4 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000004', '9e06b000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3', 'application', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000004', 'accepted', 'seeded');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000005');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000005', '9e06b000-0000-4000-8000-000100000005', 'Child 5 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000005', '9e06b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000005', encode(extensions.digest('seed5', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000005', 'waitlisted', 'seeded');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000006');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000006', '9e06b000-0000-4000-8000-000100000006', 'Child 6 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000006', '9e06b000-0000-4000-8000-000300000006', '2027/2028', 'Grade 3', 'enrolled', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000006', encode(extensions.digest('seed6', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000006', 'accepted', 'seeded');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if public.reset_offer('9e06b000-0000-4000-8000-000400000001')->>'stage' <> 'offer' then raise exception 'expired not reset'; end if;
  if public.reset_offer('9e06b000-0000-4000-8000-000400000002')->>'stage' <> 'offer' then raise exception 'withdrawn not reset'; end if;
end $$;
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000003');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The parent has accepted the offer, so it can''t be reset' then raise; end if;
end $$;
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000004');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'No offer exists for this application; generate one instead' then raise; end if;
end $$;
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000005');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer needs an accepted decision' then raise; end if;
end $$;
do $$ begin
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000006');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer can''t be reset while the application is at enrolled' then raise; end if;
end $$;

-- probe: B10 record_offer_response accepted: response, responded_at, stage stays offer
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  if public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted') <> '{"response": "accepted", "stage": "offer"}'::jsonb then
    raise exception 'return wrong';
  end if;
end $$;
reset role;
do $$ begin
  if (select response from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001') <> 'accepted'
     or (select responded_at from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001') is null then
    raise exception 'offer not accepted';
  end if;
end $$;

-- probe: B11 record_offer_response declined: stage offer_declined
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  if public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'declined') <> '{"response": "declined", "stage": "offer_declined"}'::jsonb then
    raise exception 'return wrong';
  end if;
end $$;

-- probe: B12 record_offer_response: an expired offer is refused and still reads expired, stored pending
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 second', 'pending');
-- as role:
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer has expired; reset it to send a new one' then raise; end if;
end $$;
do $$ begin
  if (select effective_response from public.application_offer_status where application_id = '9e06b000-0000-4000-8000-000400000001') <> 'expired' then
    raise exception 'view does not read expired';
  end if;
end $$;
reset role;
do $$ begin
  if (select response from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001') <> 'pending'
     or (select stage from public.applications where id = '9e06b000-0000-4000-8000-000400000001') <> 'offer' then
    raise exception 'a refused call wrote something';
  end if;
end $$;

-- probe: B13 record_offer_response: refused when the decision is no longer accepted, the offer is settled, or the stage isn't offer
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'waitlisted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000004');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000004', '9e06b000-0000-4000-8000-000100000004', 'Child 4 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000004', '9e06b000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000004', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000004', encode(extensions.digest('seed4', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000005');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000005', '9e06b000-0000-4000-8000-000100000005', 'Child 5 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000005', '9e06b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000005', 'accepted', 'seeded');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The decision is no longer accepted' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000002', 'declined');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer has already been accepted' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000003', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer has already been withdrawn' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000004', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer response can''t be recorded while the application is at offer_declined' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000005', 'accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'No offer exists for this application' then raise; end if;
end $$;

-- probe: B14 record_offer_response: only accepted or declined
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'expired');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer response must be accepted or declined' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'withdrawn');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer response must be accepted or declined' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'pending');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer response must be accepted or declined' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', null);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer response must be accepted or declined' then raise; end if;
end $$;
do $$ begin
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'Accepted');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'An offer response must be accepted or declined' then raise; end if;
end $$;

-- probe: B15 audit: generate, reset and respond each write one application_offer_changed row without token or hash
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
-- as role:
do $$
declare t1 text; t2 text;
begin
  perform public.generate_offer('9e06b000-0000-4000-8000-000400000001');
  perform public.reset_offer('9e06b000-0000-4000-8000-000400000001');
  perform public.record_offer_response('9e06b000-0000-4000-8000-000400000001', 'accepted');
end $$;
reset role;
do $$
declare rows jsonb; o public.application_offers;
begin
  select * into o from public.application_offers where application_id = '9e06b000-0000-4000-8000-000400000001';
  select jsonb_agg(jsonb_build_object('b', l.before, 'a', l.after, 'actor', l.actor_id, 'id', l.entity_id) order by l.occurred_at, l.after->>'response' desc, l.after->>'token_replaced')
    into rows from public.audit_log l where l.action = 'application_offer_changed';
  if jsonb_array_length(rows) <> 3 then raise exception 'expected 3 offer audit rows, got %', jsonb_array_length(rows); end if;
  -- Slice 11: no token exists any more, so the check is that no 64 hex
  -- string and no hash field reaches the audit rows.
  if rows::text ~ '[0-9a-f]{64}' or rows::text ~ 'token_hash' then
    raise exception 'token or hash in audit';
  end if;
  if exists (select 1 from jsonb_array_elements(rows) e where (e->>'actor')::uuid <> auth.uid() or e->>'id' <> o.id::text) then
    raise exception 'actor or entity wrong';
  end if;
  if (select count(*) from jsonb_array_elements(rows) e where e->'a'->>'token_replaced' = 'true') <> 1 then
    raise exception 'reset not marked';
  end if;
  if (select count(*) from jsonb_array_elements(rows) e where e->'b' is null or e->'b' = 'null'::jsonb) <> 1 then
    raise exception 'insert row should have no before';
  end if;
  if (select count(*) from jsonb_array_elements(rows) e where e->'a'->>'response' = 'accepted' and e->'b'->>'response' = 'pending') <> 1 then
    raise exception 'response row wrong';
  end if;
  if exists (select 1 from jsonb_array_elements(rows) e where e->'a'->>'application_reference' !~ '^APP-') then
    raise exception 'reference missing';
  end if;
end $$;

-- probe: B16 audit: change_decision withdrawing a pending offer writes an offer row (6a path)
-- expect: Manager,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.change_decision('9e06b000-0000-4000-8000-000400000001', 'waitlisted', 'x');
reset role;
do $$ begin
  if (select count(*) from public.audit_log where action = 'application_offer_changed'
      and after->>'response' = 'withdrawn' and before->>'response' = 'pending') <> 1 then
    raise exception 'withdrawal not audited';
  end if;
end $$;

-- probe: B17 audit: no offer row for a write with no signed-in actor
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
reset role;
set local request.jwt.claims = '{}';
update public.application_offers set response = 'declined';
do $$ begin
  if exists (select 1 from public.audit_log where action = 'application_offer_changed') then
    raise exception 'audited without an actor';
  end if;
end $$;

-- probe: R1 read application_offer_status: Manager, Auditor, in-scope AO with can_decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offer_status where application_id = '9e06b000-0000-4000-8000-000400000001') then raise exception 'no rows visible'; end if;
end $$;

-- probe: R2 read application_offer_status: AO in scope without can_decide sees nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offer_status where application_id = '9e06b000-0000-4000-8000-000400000001') then raise exception 'no rows visible'; end if;
end $$;

-- probe: R3 read application_offer_status: AO with can_decide, out of band, sees nothing
-- expect: Manager,Auditor
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 7', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
do $$ begin
  if not exists (select 1 from public.application_offer_status where application_id = '9e06b000-0000-4000-8000-000400000001') then raise exception 'no rows visible'; end if;
end $$;
