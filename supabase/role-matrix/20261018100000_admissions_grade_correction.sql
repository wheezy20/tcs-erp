-- Role matrix for 20261018100000_admissions_grade_correction (admissions
-- slice 7b1, docs/admissions/PORT-PLAN.md): correct_application_grade's
-- role, scope, state and campus rules, its audit row, and the offers column
-- grant that keeps token_hash out of reach of every signed-in role.
-- All fixture rows are invented (ids 9e07b100-...). Grade ids are passed in
-- through probe.* settings written during setup.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261018100000_admissions_grade_correction.sql

-- probe: G1 correct "Grade 11" to Grade 3 at offer with an accepted offer (Manager holds no capability)
-- expect: Manager
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', null);
insert into public.application_decisions (application_id, decision_type, notes) values ('9e07b100-0000-4000-8000-000400000001', 'accepted', '');
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e07b100-0000-4000-8000-000400000001', encode(extensions.digest('fx1', 'sha256'), 'hex'), now(), now() + interval '5 days', 'accepted');
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
do $$
declare r jsonb;
begin
  r := public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.g3')::uuid);
  if r->>'year_group_applied_for' <> 'Grade 3' or r->>'grade_band' <> 'primary' or r->>'stage' <> 'offer'
     or (select count(*) from jsonb_object_keys(r)) <> 3 then
    raise exception 'result wrong: %', r;
  end if;
  if (select year_group_applied_for from public.applications where id = '9e07b100-0000-4000-8000-000400000001') <> 'Grade 3' then
    raise exception 'grade not stored';
  end if;
end $$;

-- probe: G1b Manager only, even with the Manager holding decide and the officer holding decide and all grades
-- expect: Manager
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'application', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
select public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.g3')::uuid);

-- probe: G2 refused: nonexistent application, null application
-- expect: Manager
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
do $$ begin
  begin
    perform public.correct_application_grade('9e07b100-0000-4000-8000-0004000000ff', current_setting('probe.g3')::uuid);
    raise exception 'not refused';
  exception when others then if sqlerrm <> 'Application not found' then raise; end if;
  end;
  begin
    perform public.correct_application_grade(null, current_setting('probe.g3')::uuid);
    raise exception 'not refused';
  exception when others then if sqlerrm <> 'Application not found' then raise; end if;
  end;
end $$;

-- probe: G3 refused: the grade is already recognised (narrow rule), in any spelling
-- expect: Manager
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 4', 'offer', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000002', '9e07b100-0000-4000-8000-000300000001', '2026/2027', '  grade   4 ', 'offer', null);
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
do $$
declare a uuid;
begin
  foreach a in array array['9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000400000002']::uuid[] loop
    begin
      perform public.correct_application_grade(a, current_setting('probe.g3')::uuid);
      raise exception 'not refused';
    exception when others then
      if sqlerrm <> 'This is already a recognised grade; only an unrecognised grade can be corrected' then raise; end if;
    end;
  end loop;
end $$;

-- probe: G4 refused at enrolled; allowed at inquiry, rejected and offer_declined
-- expect: Manager
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'enrolled', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000002', '9e07b100-0000-4000-8000-000300000001', '2026/2027', '2027', 'inquiry', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000003', '9e07b100-0000-4000-8000-000300000001', '2025/2026', 'Other', 'rejected', null);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000004', '9e07b100-0000-4000-8000-000300000001', '2024/2025', 'Grade 12', 'offer_declined', null);
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
do $$ begin
  begin
    perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.g3')::uuid);
    raise exception 'not refused';
  exception when others then if sqlerrm <> 'An enrolled application''s grade can''t be corrected' then raise; end if;
  end;
  perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000002', current_setting('probe.g3')::uuid);
  perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000003', current_setting('probe.g3')::uuid);
  perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000004', current_setting('probe.g3')::uuid);
end $$;

-- probe: G5 refused: an inactive, unknown or null grade
-- expect: Manager
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', null);
update public.admissions_grades set is_active = false where name = 'Grade 5';
select set_config('probe.g5', (select id::text from public.admissions_grades where name = 'Grade 5'), true);
-- as role:
do $$
declare g uuid;
begin
  foreach g in array array[current_setting('probe.g5')::uuid, '9e07b100-0000-4000-8000-0009000000ff'::uuid, null] loop
    begin
      perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', g);
      raise exception 'not refused';
    exception when others then if sqlerrm <> 'Grade not found' then raise; end if;
    end;
  end loop;
end $$;

-- probe: G6 refused: the campus has grade rules and the new grade isn't one of them
-- expect: Manager
insert into public.branches (id, name) values ('9e07b100-0000-4000-8000-000b00000001', 'Fixture Campus');
insert into public.admissions_campus_grade_rules (branch_id, grade_id) select '9e07b100-0000-4000-8000-000b00000001', id from public.admissions_grades where name in ('Pre Nursery', 'Nursery 1');
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', '9e07b100-0000-4000-8000-000b00000001');
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
do $$ begin
  perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.g3')::uuid);
  raise exception 'not refused';
exception when others then if sqlerrm <> 'This campus doesn''t accept Grade 3' then raise; end if;
end $$;

-- probe: G7 the same campus accepts a grade in its rules; a campus with no rules accepts any grade
-- expect: Manager
insert into public.branches (id, name) values ('9e07b100-0000-4000-8000-000b00000001', 'Fixture Campus');
insert into public.branches (id, name) values ('9e07b100-0000-4000-8000-000b00000002', 'Fixture Open Campus');
insert into public.admissions_campus_grade_rules (branch_id, grade_id) select '9e07b100-0000-4000-8000-000b00000001', id from public.admissions_grades where name in ('Pre Nursery', 'Nursery 1');
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Nursery One', 'offer', '9e07b100-0000-4000-8000-000b00000001');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000002', '9e07b100-0000-4000-8000-000300000001', '2026/2027', 'Grade 11', 'offer', '9e07b100-0000-4000-8000-000b00000002');
select set_config('probe.n1', (select id::text from public.admissions_grades where name = 'Nursery 1'), true);
select set_config('probe.g9', (select id::text from public.admissions_grades where name = 'Grade 9'), true);
-- as role:
do $$ begin
  perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.n1')::uuid);
  perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000002', current_setting('probe.g9')::uuid);
  if (select array_agg(year_group_applied_for order by id) from public.applications where id::text like '9e07b100%')
     is distinct from array['Nursery 1', 'Grade 9'] then
    raise exception 'grades not stored';
  end if;
end $$;

-- probe: G8 a non-Manager gets the same error for an existing and a nonexistent application
-- expect: anon,Attendant,Accountant,Auditor,Admissions Officer
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', null);
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
do $$
declare e1 text := '(none)'; e2 text := '(none)';
begin
  begin
    perform public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.g3')::uuid);
  exception when others then e1 := sqlerrm;
  end;
  begin
    perform public.correct_application_grade('9e07b100-0000-4000-8000-0004000000ff', current_setting('probe.g3')::uuid);
  exception when others then e2 := sqlerrm;
  end;
  if e1 = '(none)' or e1 <> e2 then raise exception 'errors differ: [%] [%]', e1, e2; end if;
end $$;

-- probe: G9 one application_grade_corrected row: reference, old and new grade, nothing else
-- expect: Manager
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child Fixture Uniquename');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Year 13 (typed)', 'offer', null);
select set_config('probe.g3', (select id::text from public.admissions_grades where name = 'Grade 3'), true);
-- as role:
select public.correct_application_grade('9e07b100-0000-4000-8000-000400000001', current_setting('probe.g3')::uuid);
reset role;
do $$
declare l public.audit_log; n int;
begin
  select count(*) into n from public.audit_log where action = 'application_grade_corrected';
  if n <> 1 then raise exception 'expected 1 audit row, got %', n; end if;
  select * into l from public.audit_log where action = 'application_grade_corrected';
  if l.entity_table <> 'applications' or l.entity_id <> '9e07b100-0000-4000-8000-000400000001'
     or l.actor_id is distinct from (select id from public.staff where role = 'Manager' and active order by id limit 1) then
    raise exception 'entity or actor wrong';
  end if;
  if l.before is distinct from jsonb_build_object('year_group_applied_for', 'Year 13 (typed)') then
    raise exception 'before wrong: %', l.before;
  end if;
  if l.after is distinct from jsonb_build_object('year_group_applied_for', 'Grade 3', 'application_reference',
       (select application_reference from public.applications where id = '9e07b100-0000-4000-8000-000400000001'))
     or l.after->>'application_reference' is null then
    raise exception 'after wrong: %', l.after;
  end if;
  if (l.before::text || l.after::text) ~ 'Uniquename' then raise exception 'name in audit'; end if;
  if exists (select 1 from public.audit_log where action = 'application_stage_changed' and entity_id = l.entity_id) then
    raise exception 'stage audit written by a grade change';
  end if;
end $$;

-- probe: G10 a change with no signed-in actor writes no audit row
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- The fixture has a campus, so the trigger's no-branch exit can't hide a missing actor check.
insert into public.branches (id, name) values ('9e07b100-0000-4000-8000-000b00000001', 'Fixture Campus');
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 11', 'offer', '9e07b100-0000-4000-8000-000b00000001');
update public.applications set year_group_applied_for = 'Grade 3' where id = '9e07b100-0000-4000-8000-000400000001';
do $$ begin
  if exists (select 1 from public.audit_log where action = 'application_grade_corrected') then
    raise exception 'audit written without an actor';
  end if;
end $$;
-- as role:
select 1;

-- ================================================================ offers column grant

-- probe: T1 refused for every role: selecting token_hash from application_offers
-- expect: none
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e07b100-0000-4000-8000-000400000001', encode(extensions.digest('fx1', 'sha256'), 'hex'), now(), now() + interval '5 days', 'pending');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
select token_hash from public.application_offers;

-- probe: T1b refused for every role: select * from application_offers
-- expect: none
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e07b100-0000-4000-8000-000400000001', encode(extensions.digest('fx1', 'sha256'), 'hex'), now(), now() + interval '5 days', 'pending');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true, true, false);
-- as role:
select * from public.application_offers;

-- probe: T2 the granted columns and the status view still read for Manager, Auditor and an officer with decide
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e07b100-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e07b100-0000-4000-8000-000300000001', '9e07b100-0000-4000-8000-000100000001', 'Child 1 Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, branch_id) values ('9e07b100-0000-4000-8000-000400000001', '9e07b100-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer', null);
insert into public.application_offers (application_id, token_hash, sent_at, expires_at, response) values ('9e07b100-0000-4000-8000-000400000001', encode(extensions.digest('fx1', 'sha256'), 'hex'), now(), now() + interval '5 days', 'pending');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, true, false);
-- as role:
do $$ begin
  if not exists (select id, application_id, sent_at, expires_at, response, responded_at from public.application_offers
                 where application_id = '9e07b100-0000-4000-8000-000400000001') then
    raise exception 'offer columns not readable';
  end if;
  if (select effective_response from public.application_offer_status
      where application_id = '9e07b100-0000-4000-8000-000400000001') is distinct from 'pending' then
    raise exception 'status view not readable';
  end if;
end $$;
