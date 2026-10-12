-- Behaviour probes for 20261018110000_admissions_academic_years_write
-- (admissions slice 7b2, docs/admissions/PORT-PLAN.md): adding, retiring
-- and reactivating academic years, the audit rows, and capacity creation
-- limited to active listed years.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261018110000_admissions_academic_years_write.sql

-- probe: A1 add an academic year
-- expect: Manager
select public.add_admissions_academic_year('2028/2029');
reset role;
do $$ begin
  if not exists (select 1 from public.admissions_academic_years where label = '2028/2029' and is_active and position = 3) then
    raise exception 'not added at position 3';
  end if;
end $$;

-- probe: A2 add: every non-Manager gets the same error whatever the input
-- expect: Attendant,Accountant,Auditor,Admissions Officer
do $$ declare v text;
begin
  foreach v in array array['2028/2029', '2026/2027', 'bad', '', null] loop
    begin
      perform public.add_admissions_academic_year(v);
      raise exception 'NOT REFUSED %', v;
    exception when others then
      if sqlerrm <> 'Only a Manager can change the academic year list' then
        raise exception 'wrong outcome for %: %', v, sqlerrm;
      end if;
    end;
  end loop;
end $$;

-- probe: A3 add refuses a label in the wrong format
-- expect: Manager
do $$ declare v text;
begin
  foreach v in array array['2028/2030', '2028-2029', '2028', '28/29', '2029/2028', '', '   ', 'abcd/efgh', '20282029'] loop
    begin
      perform public.add_admissions_academic_year(v);
      raise exception 'NOT REFUSED %', v;
    exception when others then
      if sqlerrm <> 'The academic year must look like 2028/2029, two consecutive years' then
        raise exception 'wrong outcome for %: %', v, sqlerrm;
      end if;
    end;
  end loop;
  begin
    perform public.add_admissions_academic_year(null);
    raise exception 'NOT REFUSED null';
  exception when others then
    if sqlerrm <> 'The academic year must look like 2028/2029, two consecutive years' then
      raise exception 'wrong outcome for null: %', sqlerrm;
    end if;
  end;
end $$;

-- probe: A4 add refuses a duplicate, active, retired or padded
-- expect: Manager
update public.admissions_academic_years set is_active = false where label = '2026/2027';
-- as role:
do $$ declare v text;
begin
  foreach v in array array['2027/2028', '  2027/2028 ', '2026/2027'] loop
    begin
      perform public.add_admissions_academic_year(v);
      raise exception 'NOT REFUSED %', v;
    exception when others then
      if sqlerrm <> 'That academic year is already on the list' then
        raise exception 'wrong outcome for %: %', v, sqlerrm;
      end if;
    end;
  end loop;
end $$;

-- probe: A5 add trims the label and assigns the next positions
-- expect: Manager
select set_config('t.r', to_jsonb(public.add_admissions_academic_year('  2029/2030  '))::text, true);
select public.add_admissions_academic_year('2028/2029');
reset role;
do $$ declare r jsonb := current_setting('t.r', true)::jsonb;
begin
  if not coalesce((r->>'label' = '2029/2030' and r->>'position' = '3' and r->>'is_active' = 'true'), false) then
    raise exception 'returned row wrong: %', r;
  end if;
  if (select array_agg(label order by position) from public.admissions_academic_years)
     is distinct from array['2026/2027', '2027/2028', '2029/2030', '2028/2029'] then
    raise exception 'positions wrong';
  end if;
end $$;

-- probe: A6 retire an academic year
-- expect: Manager
select public.set_admissions_academic_year_active('2027/2028', false);
reset role;
do $$ begin
  if (select is_active from public.admissions_academic_years where label = '2027/2028') then
    raise exception 'not retired';
  end if;
end $$;

-- probe: A7 reactivate a retired academic year
-- expect: Manager
update public.admissions_academic_years set is_active = false where label = '2027/2028';
-- as role:
select public.set_admissions_academic_year_active(' 2027/2028 ', true);
reset role;
do $$ begin
  if not (select is_active from public.admissions_academic_years where label = '2027/2028') then
    raise exception 'not reactivated';
  end if;
end $$;

-- probe: A8 retire and reactivate: every non-Manager gets the same error whatever the input
-- expect: Attendant,Accountant,Auditor,Admissions Officer
update public.admissions_academic_years set is_active = false where label = '2026/2027';
-- as role:
do $$ declare v text; a boolean;
begin
  foreach v in array array['2027/2028', '2026/2027', '1999/2000', 'bad', null] loop
    foreach a in array array[true, false, null] loop
      begin
        perform public.set_admissions_academic_year_active(v, a);
        raise exception 'NOT REFUSED % %', v, a;
      exception when others then
        if sqlerrm <> 'Only a Manager can change the academic year list' then
          raise exception 'wrong outcome for % %: %', v, a, sqlerrm;
        end if;
      end;
    end loop;
  end loop;
end $$;

-- probe: A9 retire and reactivate refuse an unknown year, a null flag and no change
-- expect: Manager
update public.admissions_academic_years set is_active = false where label = '2026/2027';
-- as role:
do $$ begin
  begin
    perform public.set_admissions_academic_year_active('1999/2000', false);
    raise exception 'NOT REFUSED unknown';
  exception when others then
    if sqlerrm <> 'Academic year not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
  end;
  begin
    perform public.set_admissions_academic_year_active(null, false);
    raise exception 'NOT REFUSED null label';
  exception when others then
    if sqlerrm <> 'Academic year not found' then raise exception 'wrong outcome: %', sqlerrm; end if;
  end;
  begin
    perform public.set_admissions_academic_year_active('2027/2028', null);
    raise exception 'NOT REFUSED null flag';
  exception when others then
    if sqlerrm <> 'Choose whether the academic year is active' then raise exception 'wrong outcome: %', sqlerrm; end if;
  end;
  begin
    perform public.set_admissions_academic_year_active('2027/2028', true);
    raise exception 'NOT REFUSED already active';
  exception when others then
    if sqlerrm <> 'The academic year 2027/2028 is already active' then raise exception 'wrong outcome: %', sqlerrm; end if;
  end;
  begin
    perform public.set_admissions_academic_year_active('2026/2027', false);
    raise exception 'NOT REFUSED already retired';
  exception when others then
    if sqlerrm <> 'The academic year 2026/2027 is already retired' then raise exception 'wrong outcome: %', sqlerrm; end if;
  end;
end $$;

-- probe: A10 an add writes one audit row with the actor and the year
-- expect: Manager
select public.add_admissions_academic_year('2028/2029');
reset role;
do $$ begin
  if (select count(*) from public.audit_log
      where action = 'admissions_academic_year_changed'
        and entity_table = 'admissions_academic_years'
        and entity_id = '2028/2029'
        and before is null
        and after = '{"label": "2028/2029", "is_active": true, "position": 3}'::jsonb
        and actor_id = (select id from public.staff where role = 'Manager' and active order by id limit 1)
        and branch_id = (select branch_id from public.staff where role = 'Manager' and active order by id limit 1)) <> 1 then
    raise exception 'audit row missing or wrong';
  end if;
end $$;

-- probe: A11 retire and reactivate each write one audit row with before and after
-- expect: Manager
select public.set_admissions_academic_year_active('2027/2028', false);
select public.set_admissions_academic_year_active('2027/2028', true);
reset role;
do $$ begin
  if (select count(*) from public.audit_log
      where action = 'admissions_academic_year_changed' and entity_id = '2027/2028'
        and before = '{"is_active": true}'::jsonb and after->>'is_active' = 'false') <> 1 then
    raise exception 'retire audit row missing or wrong';
  end if;
  if (select count(*) from public.audit_log
      where action = 'admissions_academic_year_changed' and entity_id = '2027/2028'
        and before = '{"is_active": false}'::jsonb and after->>'is_active' = 'true') <> 1 then
    raise exception 'reactivate audit row missing or wrong';
  end if;
end $$;

-- probe: A12 no audit row without a signed-in actor, and none for a position-only change
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.admissions_academic_years (label, position) values ('2028/2029', 3);
update public.admissions_academic_years set is_active = false where label = '2028/2029';
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
update public.admissions_academic_years set position = 9 where label = '2028/2029';
select set_config('request.jwt.claims', '', true);
do $$ begin
  if exists (select 1 from public.audit_log where action = 'admissions_academic_year_changed') then
    raise exception 'audit row written without an actor or for a position change';
  end if;
end $$;
-- as role:
select 1;

-- probe: A13 the table still has no direct write path for a Manager
-- expect: none
-- as role:
insert into public.admissions_academic_years (label, position) values ('2028/2029', 3);

-- probe: C1 capacity creation refuses a year that is not on the list
-- expect: Manager
do $$ declare v text;
begin
  foreach v in array array['2031/2032', '2026-2027', 'yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy'] loop
    begin
      perform public.create_admissions_capacity(v, (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
      raise exception 'NOT REFUSED %', v;
    exception when others then
      if sqlerrm <> 'The academic year must be an active year on the academic year list' then
        raise exception 'wrong outcome for %: %', v, sqlerrm;
      end if;
    end;
  end loop;
end $$;

-- probe: C2 capacity creation refuses a retired year
-- expect: Manager
update public.admissions_academic_years set is_active = false where label = '2027/2028';
-- as role:
do $$ begin
  perform public.create_admissions_capacity('2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
  raise exception 'NOT REFUSED';
exception when others then
  if sqlerrm <> 'The academic year must be an active year on the academic year list' then
    raise exception 'wrong outcome: %', sqlerrm;
  end if;
end $$;

-- probe: C3 capacity creation accepts an active listed year, and one just added
-- expect: Manager
select public.create_admissions_capacity(' 2027/2028 ', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
select public.add_admissions_academic_year('2028/2029');
select public.create_admissions_capacity('2028/2029', (select id from public.admissions_grades where name = 'Grade 3'), null, 6);
reset role;
do $$ begin
  if (select count(*) from public.admissions_capacity where academic_year in ('2027/2028', '2028/2029')) <> 2 then
    raise exception 'capacity rows not created';
  end if;
end $$;

-- probe: C4 a capacity row for an unlisted or retired year can still be changed and deleted
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e07b200-0000-4000-8000-000700000001', '2019/2020', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e07b200-0000-4000-8000-000700000002', '2027/2028', (select id from public.admissions_grades where name = 'Grade 4'), null, 5);
update public.admissions_academic_years set is_active = false where label = '2027/2028';
-- as role:
select public.update_admissions_capacity('9e07b200-0000-4000-8000-000700000001', 8);
select public.update_admissions_capacity('9e07b200-0000-4000-8000-000700000002', 9);
select public.delete_admissions_capacity('9e07b200-0000-4000-8000-000700000001');
reset role;
do $$ begin
  if exists (select 1 from public.admissions_capacity where id = '9e07b200-0000-4000-8000-000700000001') then
    raise exception 'unlisted row not deleted';
  end if;
  if (select capacity from public.admissions_capacity where id = '9e07b200-0000-4000-8000-000700000002') <> 9 then
    raise exception 'retired-year row not changed';
  end if;
end $$;

-- probe: C5 retiring a year leaves its capacity rows untouched
-- expect: Manager
insert into public.admissions_capacity (id, academic_year, grade_id, branch_id, capacity) values ('9e07b200-0000-4000-8000-000700000003', '2027/2028', (select id from public.admissions_grades where name = 'Grade 3'), null, 5);
-- as role:
select public.set_admissions_academic_year_active('2027/2028', false);
reset role;
do $$ begin
  if not exists (select 1 from public.admissions_capacity where id = '9e07b200-0000-4000-8000-000700000003' and academic_year = '2027/2028' and capacity = 5) then
    raise exception 'capacity row changed';
  end if;
end $$;
