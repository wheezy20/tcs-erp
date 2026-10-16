-- Probes for 20261026100000_hr_staff_numbers (staff ID numbers, HR).
--
-- Role cells: Manager issues (by approving), corrects and sets a position's
-- class; Manager, Accountant and Auditor read staff_numbers; nobody writes
-- staff_numbers, the counters or positions.staff_class directly.
-- Value probes hold the format, the per-year roll across classes, the 999
-- cap, the unmapped and renamed position refusals, no overwrite, the one
-- correction, retired IDs never reissued, suspension keeping the ID, the
-- audit rows and the anon surface. The two-session race needs committed
-- rows, so it isn't a probe here: it was run by hand on 2026-10-16 and is
-- recorded in docs/JOURNAL.md with its method.
--
-- Expected numbers use the current Africa/Accra year, so the file keeps
-- passing after a new year. Fixed ids use the 9e5 prefix.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261026100000_hr_staff_numbers.sql

-- ======================================================== role cells

-- probe: R1 read staff_numbers
-- expect: Manager,Accountant,Auditor
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R1', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
-- as role:
do $$ begin
  if not exists (select 1 from public.staff_numbers where number = 'ST25-01900') then
    raise exception 'no rows visible';
  end if;
end $$;

-- probe: R2 direct insert into staff_numbers
-- expect: none
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R2', 'Active', 'BURSAR');
-- as role:
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);

-- probe: R3 direct update of staff_numbers
-- expect: none
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R3', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
-- as role:
do $$ declare n int; begin
  update public.staff_numbers set retired_at = now(), retire_reason = 'x' where number = 'ST25-01900';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: R4 direct delete from staff_numbers
-- expect: none
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R4', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
-- as role:
do $$ declare n int; begin
  delete from public.staff_numbers where number = 'ST25-01900';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row deleted'; end if;
end $$;

-- probe: R5 approve_employee issues a staff ID
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R5', 'Pending Approval', 'CLASS TEACHER');
-- as role:
select public.approve_employee('9e500000-0000-0000-0000-000000000001');
do $$ begin
  if not exists (select 1 from public.staff_numbers
                 where employee_id = '9e500000-0000-0000-0000-000000000001' and retired_at is null) then
    raise exception 'no staff ID issued';
  end if;
end $$;

-- probe: R6 correct_staff_number
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R6', 'Active', 'BURSAR');
insert into public.staff_number_counters (year, next_roll) values (2025, 901);
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
-- as role:
select public.correct_staff_number('9e500000-0000-0000-0000-000000000001', 'Probe correction');

-- probe: R7 set_position_staff_class
-- expect: Manager
-- as role:
select public.set_position_staff_class(
  (select id from public.positions where name = 'LIBRARIAN'), '01');

-- probe: R8 direct update of positions.staff_class
-- expect: none
-- as role:
do $$ declare n int; begin
  update public.positions set staff_class = '01' where name = 'LIBRARIAN';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: R8b direct insert of a position carrying a staff_class
-- expect: none
-- as role:
insert into public.positions (name, staff_class) values ('PROBE PORTER', '04');

-- probe: R8c direct update of other positions columns still works for Manager and Accountant
-- expect: Manager,Accountant
-- as role:
do $$ declare n int; begin
  update public.positions set is_teaching = not is_teaching where name = 'LIBRARIAN';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: R9 read staff_number_counters
-- expect: none
insert into public.staff_number_counters (year, next_roll) values (2025, 5);
-- as role:
do $$ begin
  if not exists (select 1 from public.staff_number_counters) then raise exception 'no rows visible'; end if;
end $$;

-- probe: R9b write staff_number_counters
-- expect: none
-- as role:
insert into public.staff_number_counters (year, next_roll) values (2031, 1);

-- probe: R10 call _issue_staff_number directly
-- expect: none
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R10', 'Active', 'BURSAR');
-- as role:
select public._issue_staff_number('9e500000-0000-0000-0000-000000000001', 2026);

-- probe: R10b call _take_staff_roll directly
-- expect: none
-- as role:
select public._take_staff_roll(2026);

-- probe: R11 direct rename of a position that has a class
-- expect: none
-- as role:
do $$ declare n int; begin
  update public.positions set name = 'DRIVER X' where name = 'DRIVER';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: R11b the rename swap (move DRIVER away, rename CLEANER to DRIVER) is refused at its first step
-- expect: none
-- as role:
do $$ declare n int; begin
  update public.positions set name = 'OLD DRIVER' where name = 'DRIVER';
  update public.positions set name = 'DRIVER' where name = 'CLEANER';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: R11c a same-name save of a classed position (case and spaces only) still works
-- expect: Manager,Accountant
-- as role:
do $$ declare n int; begin
  update public.positions set name = '  driver ', position = position where name = 'DRIVER';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
  if (select staff_class from public.positions where name = 'DRIVER') <> '05' then raise exception 'class lost'; end if;
end $$;

-- probe: R11d a position with no class can still be renamed directly
-- expect: Manager,Accountant
update public.positions set staff_class = null where name = 'DRIVER';
-- as role:
do $$ declare n int; begin
  update public.positions set name = 'TRANSPORT OFFICER' where name = 'DRIVER';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: R12 direct delete of a position that has a class
-- expect: none
-- as role:
do $$ declare n int; begin
  delete from public.positions where name = 'DRIVER';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row deleted'; end if;
end $$;

-- probe: R12b a position with no class can still be deleted directly
-- expect: Manager,Accountant
update public.positions set staff_class = null where name = 'DRIVER';
-- as role:
do $$ declare n int; begin
  delete from public.positions where name = 'DRIVER';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'no row deleted'; end if;
end $$;

-- probe: R13 generate a document from a template using {{staff_id}} with the current ID
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE R13', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
update public.contract_templates set html_body = html_body || ' {{staff_id}}' where category = 'Appointment Letter';
-- as role:
select public.generate_employee_document('9e500000-0000-0000-0000-000000000001', 'Appointment Letter',
  '9e500000-0000-0000-0000-000000000001/probe.pdf', '{"staff_id": "ST25-01900"}');

-- ======================================================== values

-- probe: V1 format, and one roll per year across classes (bursar, teacher, cook)
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position, created_at) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V1 A', 'Pending Approval', 'BURSAR', now()),
  ('9e500000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'PROBE V1 B', 'Pending Approval', 'CLASS TEACHER', now()),
  ('9e500000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'PROBE V1 C', 'Pending Approval', 'KITCHEN STAFF', now());
-- as role:
select public.approve_employee('9e500000-0000-0000-0000-000000000001');
select public.approve_employee('9e500000-0000-0000-0000-000000000002');
select public.approve_employee('9e500000-0000-0000-0000-000000000003');
do $$ declare
  y text := to_char(now() at time zone 'Africa/Accra', 'YY');
  got text[];
begin
  select array_agg(number order by roll) into got from public.staff_numbers
  where employee_id in ('9e500000-0000-0000-0000-000000000001',
                        '9e500000-0000-0000-0000-000000000002',
                        '9e500000-0000-0000-0000-000000000003');
  if got is distinct from array['ST'||y||'-01001', 'ST'||y||'-02002', 'ST'||y||'-03003'] then
    raise exception 'got %', got;
  end if;
  if exists (select 1 from public.staff_numbers where number !~ '^ST[0-9]{2}-0[1-5][0-9]{3}$') then
    raise exception 'format';
  end if;
end $$;

-- probe: V2 the next year starts at roll 001 while this year's count runs on
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V2 A', 'Active', 'DRIVER'),
  ('9e500000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'PROBE V2 B', 'Active', 'CLEANER');
insert into public.staff_number_counters (year, next_roll) values (2026, 57);
-- as role:
reset role;
do $$ declare a text; b text; begin
  a := public._issue_staff_number('9e500000-0000-0000-0000-000000000001', 2026);
  b := public._issue_staff_number('9e500000-0000-0000-0000-000000000002', 2027);
  if a <> 'ST26-05057' or b <> 'ST27-04001' then raise exception 'got % and %', a, b; end if;
end $$;

-- probe: V3 roll 999 issues, the 1000th approval in a year is refused
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V3 A', 'Pending Approval', 'BURSAR'),
  ('9e500000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'PROBE V3 B', 'Pending Approval', 'BURSAR');
insert into public.staff_number_counters (year, next_roll)
values (extract(year from now() at time zone 'Africa/Accra')::int, 999);
-- as role:
select public.approve_employee('9e500000-0000-0000-0000-000000000001');
do $$ begin
  if not exists (select 1 from public.staff_numbers where roll = 999
                 and employee_id = '9e500000-0000-0000-0000-000000000001') then
    raise exception 'roll 999 not issued';
  end if;
  begin
    perform public.approve_employee('9e500000-0000-0000-0000-000000000002');
  exception when others then
    if sqlerrm like 'All 999 staff IDs for % are used.%' then return; end if;
    raise;
  end;
  raise exception '1000th approval accepted';
end $$;

-- probe: V4 an unmapped position refuses the approval with the clear message, and nothing changes
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V4', 'Pending Approval', 'PORTER');
-- as role:
do $$ begin
  begin
    perform public.approve_employee('9e500000-0000-0000-0000-000000000001');
  exception when others then
    if sqlerrm <> 'Set a classification for position PORTER first.' then raise; end if;
    if (select employment_status from public.employees where id = '9e500000-0000-0000-0000-000000000001') <> 'Pending Approval' then
      raise exception 'status changed';
    end if;
    return;
  end;
  raise exception 'approval accepted';
end $$;

-- probe: V4b a position renamed in Settings stops matching until its class is set again
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V4B', 'Pending Approval', 'CLASS TEACHER');
update public.positions set name = 'FORM TEACHER', staff_class = null where name = 'CLASS TEACHER';
update public.employees set position = 'FORM TEACHER' where id = '9e500000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  begin
    perform public.approve_employee('9e500000-0000-0000-0000-000000000001');
    raise exception 'approval accepted';
  exception when others then
    if sqlerrm <> 'Set a classification for position FORM TEACHER first.' then raise; end if;
  end;
  perform public.set_position_staff_class((select id from public.positions where name = 'FORM TEACHER'), '02');
  perform public.approve_employee('9e500000-0000-0000-0000-000000000001');
  if (select class_code from public.staff_numbers where employee_id = '9e500000-0000-0000-0000-000000000001') <> '02' then
    raise exception 'class';
  end if;
end $$;

-- probe: V5 no overwrite: a second issue for the same person is refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V5', 'Active', 'BURSAR');
-- as role:
reset role;
do $$ begin
  perform public._issue_staff_number('9e500000-0000-0000-0000-000000000001', 2026);
  begin
    perform public._issue_staff_number('9e500000-0000-0000-0000-000000000001', 2026);
  exception when others then
    if sqlerrm = 'This employee already has a staff ID' then return; end if;
    raise;
  end;
  raise exception 'second issue accepted';
end $$;

-- probe: V6 a correction retires the old ID, stays in the original year with the next roll and the current class; a second is refused
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V6', 'Suspended', 'CLASS TEACHER');
insert into public.staff_number_counters (year, next_roll) values (2025, 6);
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01005', '9e500000-0000-0000-0000-000000000001', 2025, '01', 5);
-- as role:
do $$ declare v text; r public.staff_numbers; begin
  v := public.correct_staff_number('9e500000-0000-0000-0000-000000000001', '  Wrong class at approval  ');
  if v <> 'ST25-02006' then raise exception 'new ID %', v; end if;
  select * into r from public.staff_numbers where number = 'ST25-01005';
  if r.retired_at is null or r.replaced_by <> 'ST25-02006' or r.retire_reason <> 'Wrong class at approval'
     or r.retired_by is null then
    raise exception 'old row not retired properly';
  end if;
  set constraints all immediate;
  begin
    perform public.correct_staff_number('9e500000-0000-0000-0000-000000000001', 'again');
  exception when others then
    if sqlerrm = 'This employee''s staff ID has already been corrected once' then return; end if;
    raise;
  end;
  raise exception 'second correction accepted';
end $$;

-- probe: V6b correction is refused without a reason, for a Pending or Rejected record, and without a current ID
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V6B A', 'Active', 'BURSAR'),
  ('9e500000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'PROBE V6B B', 'Pending Approval', 'BURSAR'),
  ('9e500000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'PROBE V6B C', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
-- as role:
do $$
declare
  c record;
begin
  for c in select * from (values
    ('9e500000-0000-0000-0000-000000000001'::uuid, '   ', 'A reason is required to correct a staff ID'),
    ('9e500000-0000-0000-0000-000000000002'::uuid, 'x', 'A staff ID can be corrected only for an Active or Suspended employee'),
    ('9e500000-0000-0000-0000-000000000003'::uuid, 'x', 'This employee has no staff ID to correct')) t(id, reason, msg)
  loop
    begin
      perform public.correct_staff_number(c.id, c.reason);
      raise exception 'accepted for %', c.id;
    exception when others then
      if sqlerrm <> c.msg then raise; end if;
    end;
  end loop;
end $$;

-- probe: V7 a retired ID is never issued again, even if a counter were reset
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V7 A', 'Active', 'BURSAR'),
  ('9e500000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'PROBE V7 B', 'Pending Approval', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll, retired_at, retire_reason)
values ('ST' || to_char(now() at time zone 'Africa/Accra', 'YY') || '-01001', '9e500000-0000-0000-0000-000000000001',
        extract(year from now() at time zone 'Africa/Accra')::int, '01', 1, now(), 'probe');
-- as role:
do $$ begin
  perform public.approve_employee('9e500000-0000-0000-0000-000000000002');
  raise exception 'retired ID reissued';
exception when unique_violation then null;
end $$;

-- probe: V8 suspension and reactivation keep the ID
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V8', 'Pending Approval', 'DRIVER');
-- as role:
do $$ declare before_id text; after_id text; begin
  perform public.approve_employee('9e500000-0000-0000-0000-000000000001');
  select number into before_id from public.staff_numbers where employee_id = '9e500000-0000-0000-0000-000000000001';
  perform public.set_employee_status('9e500000-0000-0000-0000-000000000001', 'Suspended');
  perform public.set_employee_status('9e500000-0000-0000-0000-000000000001', 'Active');
  select string_agg(number, ',') into after_id from public.staff_numbers where employee_id = '9e500000-0000-0000-0000-000000000001';
  if after_id is distinct from before_id or before_id is null then
    raise exception 'ID changed: % -> %', before_id, after_id;
  end if;
end $$;

-- probe: V9 audit rows: issued on approval, retired and issued on correction, class change
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V9', 'Pending Approval', 'BURSAR');
-- as role:
do $$ declare n1 text; n2 text; begin
  perform public.approve_employee('9e500000-0000-0000-0000-000000000001');
  select number into n1 from public.staff_numbers where employee_id = '9e500000-0000-0000-0000-000000000001';
  perform public.set_position_staff_class((select id from public.positions where name = 'BURSAR'), '02');
  n2 := public.correct_staff_number('9e500000-0000-0000-0000-000000000001', 'Bursar reclassified');
  if not exists (select 1 from public.audit_log where action = 'staff_number_issued'
                 and entity_id = '9e500000-0000-0000-0000-000000000001' and after->>'number' = n1
                 and actor_id = auth.uid()) then
    raise exception 'issued row missing';
  end if;
  if not exists (select 1 from public.audit_log where action = 'staff_number_retired'
                 and before->>'number' = n1 and after->>'replaced_by' = n2
                 and after->>'reason' = 'Bursar reclassified' and actor_id = auth.uid()) then
    raise exception 'retired row missing';
  end if;
  if not exists (select 1 from public.audit_log where action = 'staff_number_issued' and after->>'number' = n2) then
    raise exception 'reissue row missing';
  end if;
  if not exists (select 1 from public.audit_log where action = 'position_staff_class_changed'
                 and before->>'staff_class' = '01' and after->>'staff_class' = '02'
                 and actor_id = auth.uid()) then
    raise exception 'class change row missing';
  end if;
  if n2 not like 'ST__-02%' then raise exception 'correction did not take the current class: %', n2; end if;
end $$;

-- probe: V10 an issued row changes only by retiring, and is never deleted (even as owner)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V10', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000001', 2025, '01', 900);
-- as role:
reset role;
do $$ begin
  begin
    update public.staff_numbers set class_code = '02', number = 'ST25-02900' where number = 'ST25-01900';
    raise exception 'class change accepted';
  exception when others then
    if sqlerrm <> 'Staff ID ST25-01900 can only be retired' then raise; end if;
  end;
  begin
    delete from public.staff_numbers where number = 'ST25-01900';
    raise exception 'delete accepted';
  exception when others then
    if sqlerrm <> 'A staff ID is never deleted' then raise; end if;
  end;
end $$;

-- probe: V11 a Manager renames a classed position by clearing, renaming and setting again; approval then works
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V11', 'Pending Approval', 'TRANSPORT OFFICER');
-- as role:
do $$ declare v_id uuid := (select id from public.positions where name = 'DRIVER'); begin
  perform public.set_position_staff_class(v_id, null);
  update public.positions set name = 'TRANSPORT OFFICER' where id = v_id;
  perform public.set_position_staff_class(v_id, '05');
  perform public.approve_employee('9e500000-0000-0000-0000-000000000001');
  if (select class_code from public.staff_numbers where employee_id = '9e500000-0000-0000-0000-000000000001') <> '05' then
    raise exception 'class';
  end if;
end $$;

-- probe: V12 {{staff_id}}: refused with no current ID, refused with a stale ID, unaffected when the template doesn't use it
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status, position) values
  ('9e500000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PROBE V12 A', 'Pending Approval', 'BURSAR'),
  ('9e500000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'PROBE V12 B', 'Active', 'BURSAR');
insert into public.staff_numbers (number, employee_id, year, class_code, roll, retired_at, retire_reason, replaced_by)
values ('ST25-01900', '9e500000-0000-0000-0000-000000000002', 2025, '01', 900, now(), 'probe', 'ST25-01901');
insert into public.staff_numbers (number, employee_id, year, class_code, roll)
values ('ST25-01901', '9e500000-0000-0000-0000-000000000002', 2025, '01', 901);
update public.contract_templates set html_body = html_body || ' {{staff_id}}' where category = 'Appointment Letter';
-- as role:
do $$
declare
  c record;
begin
  for c in select * from (values
    ('9e500000-0000-0000-0000-000000000001'::uuid, '{}'::jsonb, 'Approve this employee first so a staff ID exists'),
    ('9e500000-0000-0000-0000-000000000002'::uuid, '{"staff_id": "ST25-01900"}'::jsonb,
     'The staff ID in this document is out of date. Reload the page and generate it again.'),
    ('9e500000-0000-0000-0000-000000000002'::uuid, '{}'::jsonb,
     'The staff ID in this document is out of date. Reload the page and generate it again.')) t(id, md, msg)
  loop
    begin
      perform public.generate_employee_document(c.id, 'Appointment Letter', c.id || '/probe.pdf', c.md);
      raise exception 'accepted for %', c.id;
    exception when others then
      if sqlerrm <> c.msg then raise; end if;
    end;
  end loop;
  -- The Probation Letter template doesn't use the field: a Pending employee still generates it.
  perform public.generate_employee_document('9e500000-0000-0000-0000-000000000001', 'Probation Letter',
    '9e500000-0000-0000-0000-000000000001/probe.pdf', '{}');
end $$;

-- ======================================================== structure

-- probe: S1 anon can still execute exactly 170 public functions, and none of the new ones
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare f text; begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable count changed';
  end if;
  foreach f in array array[
    'public.set_position_staff_class(uuid, text)', 'public.correct_staff_number(uuid, text)',
    'public._issue_staff_number(uuid, integer)', 'public._take_staff_roll(integer)',
    'public._staff_class_for_employee(uuid)', 'public.guard_position_staff_class()',
    'public.audit_position_staff_class()', 'public.guard_staff_number_row()',
    'public.audit_staff_number()'] loop
    if has_function_privilege('anon', f::regprocedure, 'execute') then
      raise exception 'anon can execute %', f;
    end if;
  end loop;
  foreach f in array array[
    'public._issue_staff_number(uuid, integer)', 'public._take_staff_roll(integer)',
    'public._staff_class_for_employee(uuid)'] loop
    if has_function_privilege('authenticated', f::regprocedure, 'execute')
       or has_function_privilege('service_role', f::regprocedure, 'execute') then
      raise exception 'an API role can execute %', f;
    end if;
  end loop;
end $$;

-- probe: S2 the class guard reads current_user, so it must stay SECURITY INVOKER; the setters stay definer
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select prosecdef from pg_proc where oid = 'public.guard_position_staff_class()'::regprocedure) then
    raise exception 'guard is security definer';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.set_position_staff_class(uuid, text)'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.correct_staff_number(uuid, text)'::regprocedure) then
    raise exception 'setter is not security definer';
  end if;
end $$;

-- probe: S3 table grants: staff_numbers select-only for authenticated and service_role, counters nothing, no anon
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text; p text; begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['insert', 'update', 'delete', 'truncate'] loop
      if has_table_privilege(r, 'public.staff_numbers', p) or has_table_privilege(r, 'public.staff_number_counters', p) then
        raise exception '% holds % on a staff number table', r, p;
      end if;
    end loop;
    if has_table_privilege(r, 'public.staff_number_counters', 'select') then
      raise exception '% can select counters', r;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.staff_numbers', 'select') then raise exception 'anon select'; end if;
  if (select array_agg(polname::text || ':' || polcmd::text) from pg_policy
      where polrelid = 'public.staff_numbers'::regclass) is distinct from array['staff_numbers_select:r'] then
    raise exception 'staff_numbers policies changed';
  end if;
  if exists (select 1 from pg_policy where polrelid = 'public.staff_number_counters'::regclass) then
    raise exception 'counters have a policy';
  end if;
end $$;

-- probe: S4 the anon onboarding functions don't read staff IDs
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (select 1 from pg_proc where proname in ('get_onboarding_context', 'submit_onboarding_form')
             and pronamespace = 'public'::regnamespace and prosrc ~* 'staff_number') then
    raise exception 'an onboarding function reads staff IDs';
  end if;
end $$;

-- probe: S5 the 16 seeded positions carry their classes
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
reset role;
do $$ begin
  if (select string_agg(name || '=' || staff_class, ',' order by name) from public.positions where staff_class is not null)
     is distinct from 'ACCOUNTANT=01,ADMINISTRATOR=01,ASSISTANT HEAD TEACHER=02,BURSAR=01,CARETAKER=04,CLASS TEACHER=02,CLEANER=04,DRIVER=05,HEAD TEACHER=02,ICT COORDINATOR=02,KITCHEN STAFF=03,LIBRARIAN=02,SECRETARY=01,SECURITY=04,SUBJECT TEACHER=02,TEACHING ASSISTANT=02' then
    raise exception 'seeded classes wrong';
  end if;
  if (select is_teaching from public.positions where name = 'ICT COORDINATOR')
     or (select is_teaching from public.positions where name = 'LIBRARIAN') then
    raise exception 'is_teaching changed';
  end if;
end $$;
