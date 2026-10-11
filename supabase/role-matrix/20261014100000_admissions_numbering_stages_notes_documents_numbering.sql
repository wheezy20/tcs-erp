-- Role matrix for 20261014100000_admissions_numbering_stages_notes_documents, NUMBERING file (admissions slice 5,
-- docs/admissions/PORT-PLAN.md): INQ and APP assignment, the per-year
-- counters, the Accra year, widening past 9999, hand-entered numbers, the
-- reference and enrolled guards, and updated_at. Each probe empties the
-- counters first and computes the year in SQL. Most work happens as
-- postgres in setup and raises on failure, so they expect every role; N2
-- calls the move RPC as each role. All fixture rows are invented (ids
-- 9e050000-...).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261014100000_admissions_numbering_stages_notes_documents_numbering.sql

-- ================================================================ numbering (counters start empty in each probe; the year is computed, never hard-coded)

-- probe: N1 the first two inquiries get INQ-<year>-0001 and 0002, and no APP
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000066', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001' and (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000066') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0002' and (select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is null) then raise exception 'INQ numbering wrong'; end if;
end $$;
-- as role:
select 1;

-- probe: N2 moving an inquiry to Document Review adds APP-<year>-0001 and keeps the INQ
-- expect: Manager,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health) values
  ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false, false, false);
-- as role:
do $$ begin
  perform public.move_application_to_document_review('9e050000-0000-4000-8000-000400000065');
  if (select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is distinct from 'APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001'
     or (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is distinct from 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001' then
    raise exception 'references wrong after the move';
  end if;
end $$;

-- probe: N3 a row created at application gets APP and no INQ, and moving it on never adds an INQ
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application');
do $$ begin
  if not ((select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001' and (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is null) then raise exception 'APP-only wrong'; end if;
end $$;
update public.applications set stage = 'document_review' where id = '9e050000-0000-4000-8000-000400000065';
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is null) then raise exception 'INQ appeared on update'; end if;
end $$;
-- as role:
select 1;

-- probe: N3c a row with no INQ moved back to inquiry by hand still gets no INQ (INQ is insert-only)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application');
update public.applications set stage = 'inquiry' where id = '9e050000-0000-4000-8000-000400000065';
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is null) then raise exception 'INQ assigned on update'; end if;
end $$;
-- as role:
select 1;

-- probe: N3b inserted at each stage: APP exactly when past inquiry, INQ exactly at inquiry
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000066', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000067', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'document_review');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000068', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000069', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'enrolled');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-00040000006a', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'waitlisted');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-00040000006b', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'rejected');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-00040000006c', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'offer_declined');
do $$ begin
  if not ((select count(*) from public.applications where id::text like '9e050000-%' and ((stage = 'inquiry') <> (application_reference is null) or (stage = 'inquiry') <> (inquiry_reference is not null))) = 0) then raise exception 'stage and references disagree'; end if;
end $$;
-- as role:
select 1;

-- probe: N4 an APP is never reassigned: advance, step back, advance again
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
update public.applications set stage = 'application' where id = '9e050000-0000-4000-8000-000400000065';
update public.applications set stage = 'waitlisted' where id = '9e050000-0000-4000-8000-000400000065';
update public.applications set stage = 'document_review' where id = '9e050000-0000-4000-8000-000400000065';
do $$ begin
  if not ((select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001' and (select next_value from public.admissions_reference_counters where key = 'APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY')) = 2) then raise exception 'APP reassigned'; end if;
end $$;
-- as role:
select 1;

-- probe: N5 a hand-supplied INQ is kept and doesn't use up a counter value
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, inquiry_reference) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0500');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000066', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0500' and (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000066') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001') then raise exception 'hand INQ not kept or counter used'; end if;
end $$;
-- as role:
select 1;

-- probe: N6 a number already held by a hand-entered row is skipped
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, inquiry_reference) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000066', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000066') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0002') then raise exception 'held number not skipped'; end if;
end $$;
-- as role:
select 1;

-- probe: N7 counters are per year
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
do $$
declare r1 text; r2 text; r3 text;
begin
  r1 := public._next_admissions_reference('INQ', 2031);
  r2 := public._next_admissions_reference('INQ', 2031);
  r3 := public._next_admissions_reference('INQ', 2032);
  if (r1, r2, r3) is distinct from ('INQ-2031-0001', 'INQ-2031-0002', 'INQ-2032-0001')
     or (select count(*) from public.admissions_reference_counters where key in ('INQ-2031', 'INQ-2032')) <> 2 then
    raise exception 'per-year counters wrong: % % %', r1, r2, r3;
  end if;
end $$;
-- as role:
select 1;

-- probe: N8 the year is Accra's, whatever the session time zone
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not (public._admissions_reference_year('2026-12-31 23:59:59+00') = 2026 and public._admissions_reference_year('2027-01-01 00:00:00+00') = 2027 and public._admissions_reference_year('2026-12-31 23:30:00-01') = 2027) then raise exception 'year wrong'; end if;
end $$;
set local timezone = 'Pacific/Auckland';
do $$ begin
  if not (public._admissions_reference_year('2026-12-31 23:59:59+00') = 2026 and public._admissions_reference_year('2027-01-01 00:00:00+00') = 2027) then raise exception 'year follows session time zone'; end if;
end $$;
-- as role:
select 1;

-- probe: N9 past 9999 the numbers widen, never truncate (INQ and APP)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.admissions_reference_counters (key, next_value) values ('INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY'), 9999), ('APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY'), 9999);
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000066', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000067', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000068', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000069', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'application');
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-9999' and (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000066') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-10000' and (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000067') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-10001' and (select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000068') = 'APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-9999' and (select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000069') = 'APP-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-10000') then raise exception 'widening wrong'; end if;
end $$;
-- as role:
select 1;

-- probe: N10 the formatter pads to four digits and never truncates
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not (public._admissions_sequence_text(7) = '0007' and public._admissions_sequence_text(123) = '0123' and public._admissions_sequence_text(9999) = '9999' and public._admissions_sequence_text(10000) = '10000') then raise exception 'formatter wrong'; end if;
end $$;
-- as role:
select 1;

-- probe: N11 service_role and postgres inserts are numbered
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
set local role service_role;
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000066', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
reset role;
do $$ begin
  if not ((select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0001' and (select inquiry_reference from public.applications where id = '9e050000-0000-4000-8000-000400000066') = 'INQ-' || to_char(now() at time zone 'Africa/Accra', 'YYYY') || '-0002') then raise exception 'service_role insert not numbered'; end if;
end $$;
-- as role:
select 1;

-- probe: N12 a service_role stage change gets an APP but writes no audit row (no actor)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
set local role service_role;
update public.applications set stage = 'application' where id = '9e050000-0000-4000-8000-000400000065';
reset role;
do $$ begin
  if not ((select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') is not null and not exists (select 1 from public.audit_log where entity_id = '9e050000-0000-4000-8000-000400000065')) then raise exception 'APP missing or audit row written'; end if;
end $$;
-- as role:
select 1;

-- probe: N13 an unknown counter key is refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  perform public._next_admissions_sequence('FOO-2026');
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  perform public._next_admissions_reference('XYZ', 2026);
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
-- as role:
select 1;

-- probe: N14 a signed-in caller can't change or clear an assigned reference; postgres can
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry');
update public.applications set stage = 'application' where id = '9e050000-0000-4000-8000-000400000065';
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
do $$ begin
  update public.applications set inquiry_reference = 'INQ-1999-0001' where id = '9e050000-0000-4000-8000-000400000065';
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  update public.applications set application_reference = 'APP-1999-0001' where id = '9e050000-0000-4000-8000-000400000065';
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
do $$ begin
  update public.applications set application_reference = null where id = '9e050000-0000-4000-8000-000400000065';
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
select set_config('request.jwt.claims', '', true);
update public.applications set application_reference = 'APP-1999-0001' where id = '9e050000-0000-4000-8000-000400000065';
do $$ begin
  if not ((select application_reference from public.applications where id = '9e050000-0000-4000-8000-000400000065') = 'APP-1999-0001') then raise exception 'postgres correction failed'; end if;
end $$;
-- as role:
select 1;

-- probe: N15 updated_at moves on every update
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage, updated_at) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'inquiry', '2020-01-01');
update public.applications set month_of_enrollment = 'September' where id = '9e050000-0000-4000-8000-000400000065';
do $$ begin
  if not ((select updated_at from public.applications where id = '9e050000-0000-4000-8000-000400000065') > now() - interval '1 minute') then raise exception 'updated_at not bumped'; end if;
end $$;
-- as role:
select 1;

-- probe: N16 nothing leaves enrolled: postgres, service_role and a signed-in caller are all refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
delete from public.admissions_reference_counters;
insert into public.families (id) values ('9e050000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values ('9e050000-0000-4000-8000-000300000001', '9e050000-0000-4000-8000-000100000001', 'Child Fixture');
insert into public.applications (id, student_id, academic_year, year_group_applied_for, stage) values ('9e050000-0000-4000-8000-000400000065', '9e050000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3', 'enrolled');
do $$ begin
  update public.applications set stage = 'application' where id = '9e050000-0000-4000-8000-000400000065';
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
set local role service_role;
do $$ begin
  update public.applications set stage = 'rejected' where id = '9e050000-0000-4000-8000-000400000065';
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
reset role;
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
do $$ begin
  update public.applications set stage = 'waitlisted' where id = '9e050000-0000-4000-8000-000400000065';
  raise exception 'not refused';
exception when others then
  if sqlerrm = 'not refused' then raise; end if;
end $$;
select set_config('request.jwt.claims', '', true);
-- as role:
select 1;
