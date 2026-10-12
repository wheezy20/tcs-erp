-- Role matrix for 20261016100000_admissions_offers_enrolment, ENROLMENT file (admissions slice 6b,
-- docs/admissions/PORT-PLAN.md): mark_enrolled (Manager only),
-- student IDs (YYPPNNNN, Africa/Accra year, the STUDENT-YY-PP counter, an
-- existing ID kept, a second same-year enrolment refused, unbanded grades
-- refused), the enrolment stage audit row, the student ID guard, the
-- service_role expiry sweep, and the offer TTL setting.
-- All fixture rows are invented (ids 9e06b000-...). Capabilities are set
-- inside each probe's rolled-back setup.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261016100000_admissions_offers_enrolment_enrolment.sql

-- probe: M0 mark_enrolled with an accepted offer: Manager only, no capability needed
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
select public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');

-- probe: M0b mark_enrolled: Manager and AO hold can_decide and all_grades; still Manager only
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
select public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');

-- probe: M1 mark_enrolled with a pending offer: nobody
-- expect: none
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'pending');
-- as role:
select public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');

-- probe: M2 mark_enrolled with a pending offer past its expiry: nobody
-- expect: none
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 second', 'pending');
-- as role:
select public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');

-- probe: M3 mark_enrolled: the officer gets the Manager-only message, the Auditor the read-only one
-- expect: Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Only a Manager can mark an application enrolled' then raise; end if;
end $$;

-- probe: M4 mark_enrolled: assigns YY03NNNN from the counter, Accra year; the stage audit row carries it
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
do $$
declare r jsonb; want text := to_char(now() at time zone 'Africa/Accra', 'YY') || '030001';
begin
  r := public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');
  if r <> jsonb_build_object('stage', 'enrolled', 'student_id', want, 'student_id_assigned', true) then
    raise exception 'return wrong: %', r;
  end if;
  perform set_config('probe.want', want, true);
end $$;
reset role;
do $$
declare want text := current_setting('probe.want');
begin
  if (select student_id from public.students where id = '9e06b000-0000-4000-8000-000300000001') <> want then raise exception 'student id not stored'; end if;
  if (select stage from public.applications where id = '9e06b000-0000-4000-8000-000400000001') <> 'enrolled' then raise exception 'not enrolled'; end if;
  if (select next_value from public.admissions_reference_counters where key = 'STUDENT-' || to_char(now() at time zone 'Africa/Accra', 'YY') || '-03') <> 2 then
    raise exception 'counter wrong';
  end if;
  if (select count(*) from public.audit_log where action = 'application_stage_changed' and entity_id = '9e06b000-0000-4000-8000-000400000001'
      and before = '{"stage": "offer"}'::jsonb and after->>'stage' = 'enrolled' and after->>'student_id' = want
      and after->>'application_reference' ~ '^APP-') <> 1 then
    raise exception 'enrolment audit row wrong';
  end if;
end $$;

-- probe: M5 mark_enrolled: the code follows the grade; numbers continue from the counter
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Nursery 1', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.admissions_reference_counters (key, next_value) values ('STUDENT-' || to_char(now() at time zone 'Africa/Accra', 'YY') || '-04', 42);
-- as role:
do $$ begin
  if public.mark_enrolled('9e06b000-0000-4000-8000-000400000001')->>'student_id' <> to_char(now() at time zone 'Africa/Accra', 'YY') || '010001' then raise exception 'nursery id wrong'; end if;
  if public.mark_enrolled('9e06b000-0000-4000-8000-000400000002')->>'student_id' <> to_char(now() at time zone 'Africa/Accra', 'YY') || '040042' then raise exception 'jhs id wrong'; end if;
end $$;

-- probe: M6 mark_enrolled: skips a number a hand-entered student already holds
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
update public.students set student_id = to_char(now() at time zone 'Africa/Accra', 'YY') || '030001' where id = '9e06b000-0000-4000-8000-000300000002';
-- as role:
do $$ begin
  if public.mark_enrolled('9e06b000-0000-4000-8000-000400000001')->>'student_id' <> to_char(now() at time zone 'Africa/Accra', 'YY') || '030002' then raise exception 'held number not skipped'; end if;
end $$;

-- probe: M7 mark_enrolled: a student who has an ID keeps it; the counter isn't touched
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', '25010007');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
do $$ begin
  if public.mark_enrolled('9e06b000-0000-4000-8000-000400000001') <> '{"stage": "enrolled", "student_id": "25010007", "student_id_assigned": false}'::jsonb then
    raise exception 'existing id not kept';
  end if;
end $$;
reset role;
do $$ begin
  if exists (select 1 from public.admissions_reference_counters where key like 'STUDENT-%') then raise exception 'counter touched'; end if;
end $$;

-- probe: M8 mark_enrolled: unbanded and free-text grades are refused, nothing assigned
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', '2027', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Other: Year 13', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The grade applied for has no student ID classification; correct the grade before enrolling' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000002');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The grade applied for has no student ID classification; correct the grade before enrolling' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000003');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The grade applied for has no student ID classification; correct the grade before enrolling' then raise; end if;
end $$;
reset role;
do $$ begin
  if exists (select 1 from public.admissions_reference_counters where key like 'STUDENT-%')
     or exists (select 1 from public.students where student_id is not null and id::text like '9e06b000%') then
    raise exception 'something assigned';
  end if;
end $$;

-- probe: M9 mark_enrolled: a second enrolment for one student in one academic year is refused; another year keeps the ID
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000001', '2028/2029', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
do $$
declare first text;
begin
  first := public.mark_enrolled('9e06b000-0000-4000-8000-000400000001')->>'student_id';
  begin
    perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000002');
    raise exception 'not refused';
  exception when others then
    if sqlerrm <> 'This student is already enrolled for 2027/2028' then raise; end if;
  end;
  if public.mark_enrolled('9e06b000-0000-4000-8000-000400000003') <> jsonb_build_object('stage', 'enrolled', 'student_id', first, 'student_id_assigned', false) then
    raise exception 'second year did not keep the id';
  end if;
end $$;

-- probe: M10 mark_enrolled: refused off offer, without an accepted decision, or with a declined, withdrawn or pending offer
-- expect: Manager
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'waitlisted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'declined');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000004');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000004', '9e06b000-0000-4000-8000-000100000004', 'Child 4 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000004', '9e06b000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000004', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000004', encode(extensions.digest('seed4', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'withdrawn');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000005');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000005', '9e06b000-0000-4000-8000-000100000005', 'Child 5 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000005', '9e06b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000005', 'accepted', 'seeded');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000006');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000006', '9e06b000-0000-4000-8000-000100000006', 'Child 6 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000006', '9e06b000-0000-4000-8000-000300000006', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000006', encode(extensions.digest('seed6', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000007');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000007', '9e06b000-0000-4000-8000-000100000007', 'Child 7 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000007', '9e06b000-0000-4000-8000-000300000007', '2027/2028', 'Grade 3', 'enrolled', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000007', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000007', encode(extensions.digest('seed7', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '10 days', 'accepted');
-- as role:
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000001');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Only an application at offer can be enrolled; this one is at offer_declined' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000002');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Enrolment needs an accepted decision' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000003');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Enrolment needs an offer the parent has accepted' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000004');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Enrolment needs an offer the parent has accepted' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000005');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Enrolment needs an offer the parent has accepted' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000006');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Enrolment needs an accepted decision' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled('9e06b000-0000-4000-8000-000400000007');
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Only an application at offer can be enrolled; this one is at enrolled' then raise; end if;
end $$;
do $$ begin
  perform public.mark_enrolled(null);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Application not found' then raise; end if;
end $$;

-- probe: M11 students_guard_student_id: a signed-in caller can't change or clear an assigned ID; can fill an empty one; no actor can
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', '25010007');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application', null);
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'application', null);
-- as role:
reset role;
set local request.jwt.claims = '{"sub":"9e06b000-0000-4000-8000-000999999999","role":"authenticated"}';
do $$ begin
  update public.students set student_id = '25010008' where id = '9e06b000-0000-4000-8000-000300000001';
  raise exception 'change not refused';
exception when others then if sqlerrm <> 'A student ID can''t be changed once assigned' then raise; end if;
end $$;
do $$ begin
  update public.students set student_id = null where id = '9e06b000-0000-4000-8000-000300000001';
  raise exception 'clear not refused';
exception when others then if sqlerrm <> 'A student ID can''t be changed once assigned' then raise; end if;
end $$;
update public.students set full_name = 'Renamed Fixture' where id = '9e06b000-0000-4000-8000-000300000001';
update public.students set student_id = '25010009' where id = '9e06b000-0000-4000-8000-000300000002';
set local request.jwt.claims = '{}';
update public.students set student_id = '25010010' where id = '9e06b000-0000-4000-8000-000300000001';

-- probe: M12 settle_expired_offers: no staff role can call it
-- expect: none
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 second', 'pending');
-- as role:
select public.settle_expired_offers();

-- probe: M13 settle_expired_offers as service_role: settles only pending offers past expiry, offer to offer_declined, no audit row
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- The sweep is global: set aside non-fixture offers (seed.sql demo rows from 7b1) so the counts are the fixtures'.
delete from public.application_offers where application_id::text not like '9e06b000%';
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000001', '9e06b000-0000-4000-8000-000100000001', 'Child 1 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000001', '9e06b000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000001', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000001', encode(extensions.digest('seed1', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 second', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000002');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000002', '9e06b000-0000-4000-8000-000100000002', 'Child 2 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000002', '9e06b000-0000-4000-8000-000300000002', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000002', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000002', encode(extensions.digest('seed2', 'sha256'), 'hex'), now() - interval '1 day', now() + interval '1 hour', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000003');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000003', '9e06b000-0000-4000-8000-000100000003', 'Child 3 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000003', '9e06b000-0000-4000-8000-000300000003', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000003', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000003', encode(extensions.digest('seed3', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 day', 'accepted');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000004');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000004', '9e06b000-0000-4000-8000-000100000004', 'Child 4 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000004', '9e06b000-0000-4000-8000-000300000004', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000004', 'waitlisted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000004', encode(extensions.digest('seed4', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 day', 'withdrawn');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000005');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000005', '9e06b000-0000-4000-8000-000100000005', 'Child 5 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000005', '9e06b000-0000-4000-8000-000300000005', '2027/2028', 'Grade 3', 'waitlisted', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000005', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000005', encode(extensions.digest('seed5', 'sha256'), 'hex'), now() - interval '1 day', now() - interval '1 day', 'pending');
insert into public.families (id) values ('9e06b000-0000-4000-8000-000100000006');
insert into public.students (id, family_id, full_name, student_id) values ('9e06b000-0000-4000-8000-000300000006', '9e06b000-0000-4000-8000-000100000006', 'Child 6 Fixture', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e06b000-0000-4000-8000-000400000006', '9e06b000-0000-4000-8000-000300000006', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e06b000-0000-4000-8000-000400000006', 'accepted', 'seeded');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e06b000-0000-4000-8000-000400000006', encode(extensions.digest('seed6', 'sha256'), 'hex'), now() - interval '1 day', null, 'pending');
-- as role:
reset role;
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
do $$ begin
  if public.settle_expired_offers() <> 2 then raise exception 'settled count wrong'; end if;
  if public.settle_expired_offers() <> 0 then raise exception 'second sweep settled again'; end if;
end $$;
reset role;
do $$ begin
  if (select array_agg(o.response || '/' || a.stage order by a.id) from public.applications a
      join public.application_offers o on o.application_id = a.id where a.id::text like '9e06b000%')
     is distinct from array['expired/offer_declined', 'pending/offer', 'accepted/offer', 'withdrawn/waitlisted', 'expired/waitlisted', 'pending/offer'] then
    raise exception 'sweep result wrong';
  end if;
  if exists (select 1 from public.audit_log where action in ('application_offer_changed', 'application_stage_changed')) then
    raise exception 'sweep wrote an audit row';
  end if;
end $$;

-- probe: M14 settle_expired_offers refuses a signed-in caller even as a superuser
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
set local request.jwt.claims = '{"sub":"9e06b000-0000-4000-8000-000999999999","role":"authenticated"}';
do $$ begin
  perform public.settle_expired_offers();
  raise exception 'not refused';
exception when others then if sqlerrm <> 'This action is not available to your role' then raise; end if;
end $$;

-- probe: T0 set_admissions_offer_ttl_days: Manager only
-- expect: Manager
select public.set_admissions_offer_ttl_days(21);

-- probe: T1 set_admissions_offer_ttl_days: 0, 91, null and the current value refused; 1 and 90 accepted; audited
-- expect: Manager
do $$ begin
  perform public.set_admissions_offer_ttl_days(0);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer expiry must be a whole number of days from 1 to 90' then raise; end if;
end $$;
do $$ begin
  perform public.set_admissions_offer_ttl_days(91);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer expiry must be a whole number of days from 1 to 90' then raise; end if;
end $$;
do $$ begin
  perform public.set_admissions_offer_ttl_days(null);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer expiry must be a whole number of days from 1 to 90' then raise; end if;
end $$;
do $$ begin
  perform public.set_admissions_offer_ttl_days(-5);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer expiry must be a whole number of days from 1 to 90' then raise; end if;
end $$;
do $$ begin
  perform public.set_admissions_offer_ttl_days(14);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'The offer expiry is already 14 days' then raise; end if;
end $$;
select public.set_admissions_offer_ttl_days(1);
select public.set_admissions_offer_ttl_days(90);
reset role;
do $$ begin
  if (select offer_ttl_days from public.admissions_settings) <> 90 then raise exception 'not stored'; end if;
  if (select array_agg((before->>'offer_ttl_days') || '>' || (after->>'offer_ttl_days') order by occurred_at, after->>'offer_ttl_days')
      from public.audit_log where action = 'admissions_settings_changed') is distinct from array['14>1', '1>90'] then
    raise exception 'audit rows wrong';
  end if;
end $$;

-- probe: T2 set_admissions_offer_ttl_days: the officer gets the Manager-only message, the Auditor the read-only one
-- expect: Admissions Officer
do $$ begin
  perform public.set_admissions_offer_ttl_days(21);
  raise exception 'not refused';
exception when others then
  if sqlerrm <> 'Only a Manager can change the offer expiry' then raise; end if;
end $$;

-- probe: T3 read admissions_settings: Manager and Auditor
-- expect: Manager,Auditor
do $$ begin
  if not exists (select 1 from public.admissions_settings) then raise exception 'no rows visible'; end if;
end $$;

-- probe: T4 direct update of admissions_settings is denied
-- expect: none
update public.admissions_settings set offer_ttl_days = 30;

-- probe: T5 direct delete of admissions_settings is denied
-- expect: none
delete from public.admissions_settings;

-- probe: T6 no settings audit row with no signed-in actor
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
set local request.jwt.claims = '{}';
update public.admissions_settings set offer_ttl_days = 30;
do $$ begin
  if exists (select 1 from public.audit_log where action = 'admissions_settings_changed') then raise exception 'audited without an actor'; end if;
end $$;
