-- Role matrix for 20261005100000_admissions_grades_and_capabilities
-- (admissions slice 2, docs/admissions/PORT-PLAN.md): admissions_grades,
-- staff_admissions_capabilities, set_admissions_capabilities(), the holding
-- and role-change triggers, clear-on-deactivate, and the audit trigger.
-- Predicates are in the sibling *_predicates.sql file.
--
-- Fixtures: invented staff with ids 9e020000-…, created in setup through
-- auth.users (handle_new_staff_signup):
--   …01 inactive Admissions Officer   …02 Accountant   …03 Attendant
--   …04 Auditor   …05 Manager   …06 Admissions Officer
-- They are only ever targets. Probes that need the impersonated account
-- itself look it up with the harness's own query (role, active, lowest id),
-- excluding the fixtures. For Attendant that is a seed.sql account, not
-- Dev Attendant.
--
-- Probes with expect = all six roles assert an invariant in the postgres
-- setup (a failure shows as SETUP FAILED); their role part is a no-op.
-- Refusal probes catch the error and pass only if the message is the
-- expected one, so "expect: Manager" means "a Manager is refused, for the
-- right reason"; every other role is stopped earlier and shows as denied.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261005100000_admissions_grades_and_capabilities.sql

-- ================================================================ admissions_grades

-- probe: A1 grades seed is the 14 TCS OS grades
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select string_agg(concat_ws(':', position, name, classification_code, band,
              is_preschool_vaccination_required, is_active), ' | ' order by position)
      from public.admissions_grades)
     is distinct from
     '1:Pre Nursery:01:preschool:t:t | 2:Nursery 1:01:preschool:t:t | '
     '3:Nursery 2:01:preschool:t:t | 4:Kindergarten 1:02:preschool:t:t | '
     '5:Kindergarten 2:02:preschool:t:t | 6:Grade 1:03:primary:f:t | '
     '7:Grade 2:03:primary:f:t | 8:Grade 3:03:primary:f:t | '
     '9:Grade 4:03:primary:f:t | 10:Grade 5:03:primary:f:t | '
     '11:Grade 6:03:primary:f:t | 12:Grade 7:04:jhs:f:t | '
     '13:Grade 8:04:jhs:f:t | 14:Grade 9:04:jhs:f:t' then
    raise exception 'admissions_grades seed is not the expected 14 rows';
  end if;
end $$;
-- as role:
select 1;

-- probe: A2 read admissions_grades
-- expect: Manager,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from public.admissions_grades) <> 14 then raise exception 'expected 14 grades'; end if;
end $$;

-- probe: A3 insert admissions_grades
-- expect: none
insert into public.admissions_grades (name, position) values ('Probe Grade', 99);

-- probe: A4 update admissions_grades
-- expect: none
update public.admissions_grades set position = position;

-- probe: A5 delete admissions_grades
-- expect: none
delete from public.admissions_grades;

-- probe: A6 truncate admissions_grades
-- expect: none
truncate public.admissions_grades;

-- probe: A7 grade names unique ignoring case
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  begin
    insert into public.admissions_grades (name, position, classification_code) values ('grade 3', 99, '03');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'duplicate key value violates unique constraint%' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: A8 band is generated from classification_code
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  begin
    insert into public.admissions_grades (name, position, band) values ('Probe', 99, 'jhs');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'cannot insert a non-DEFAULT value into column "band"%' then raise; end if;
  end;
  update public.admissions_grades set classification_code = '04' where name = 'Grade 6';
  if (select band from public.admissions_grades where name = 'Grade 6') is distinct from 'jhs' then
    raise exception 'band did not follow classification_code';
  end if;
end $$;
-- as role:
select 1;

-- probe: A9 table grants: authenticated select only, anon none
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if has_table_privilege('anon', 'public.admissions_grades', 'select,insert,update,delete,truncate')
     or has_table_privilege('anon', 'public.staff_admissions_capabilities', 'select,insert,update,delete,truncate')
     or has_table_privilege('authenticated', 'public.admissions_grades', 'insert,update,delete,truncate')
     or has_table_privilege('authenticated', 'public.staff_admissions_capabilities', 'insert,update,delete,truncate')
     or not has_table_privilege('authenticated', 'public.admissions_grades', 'select')
     or not has_table_privilege('authenticated', 'public.staff_admissions_capabilities', 'select') then
    raise exception 'unexpected table grants';
  end if;
end $$;
-- as role:
select 1;

-- ================================================================ capabilities table

-- probe: B1 read own capability row
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not exists (select 1 from public.staff_admissions_capabilities where staff_id = auth.uid()) then
    raise exception 'own row not visible';
  end if;
end $$;

-- probe: B2 read every capability row
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if (select count(*) from public.staff_admissions_capabilities) < 5 then raise exception 'not all rows visible'; end if;
end $$;

-- probe: B3 sees exactly its own row
-- expect: Attendant,Accountant,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if (select count(*) from public.staff_admissions_capabilities) <> 1
     or not exists (select 1 from public.staff_admissions_capabilities where staff_id = auth.uid()) then
    raise exception 'sees % rows', (select count(*) from public.staff_admissions_capabilities);
  end if;
end $$;

-- probe: B4 inactive staff see no capability rows
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
alter table public.staff disable trigger staff_clear_admissions_caps_on_deactivate;
update public.staff set active = false where not protected;
-- as role:
do $$ begin
  if exists (select 1 from public.staff_admissions_capabilities) then raise exception 'rows visible'; end if;
end $$;

-- probe: B5 direct insert capability row
-- expect: none
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values (auth.uid(), true);

-- probe: B6 direct update capability rows
-- expect: none
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
update public.staff_admissions_capabilities set can_view_health = true;

-- probe: B7 direct delete capability rows
-- expect: none
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
delete from public.staff_admissions_capabilities;

-- probe: B8 truncate capability rows
-- expect: none
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
truncate public.staff_admissions_capabilities;

-- probe: B9 checks refuse bad rows
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
do $$ begin
  begin
    insert into public.staff_admissions_capabilities (staff_id, all_grades, grade_bands) values ('9e020000-0000-0000-0000-000000000006', true, '{primary}');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like '%staff_admissions_capabilities_scope_check%' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000006', '{shs}');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like '%staff_admissions_capabilities_bands_check%' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000006', '{primary,primary}');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like '%staff_admissions_capabilities_bands_check%' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000006', array['primary', null]);
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like '%staff_admissions_capabilities_bands_check%' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id) values ('9e020000-0000-0000-0000-000000000006');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like '%staff_admissions_capabilities_not_empty_check%' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id, can_view_health, grade_bands) values ('9e020000-0000-0000-0000-000000000006', true, null);
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'null value in column "grade_bands"%' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: B10 deleting a staff member cascades; granted_by is set null
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_decide, granted_by) values ('9e020000-0000-0000-0000-000000000006', true, '9e020000-0000-0000-0000-000000000005');
insert into public.staff_admissions_capabilities (staff_id, can_view_health, granted_by) values ('9e020000-0000-0000-0000-000000000003', true, '9e020000-0000-0000-0000-000000000005');
delete from auth.users where id = '9e020000-0000-0000-0000-000000000006';
delete from auth.users where id = '9e020000-0000-0000-0000-000000000005';
do $$ begin
  if exists (select 1 from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') then raise exception 'row not cascaded'; end if;
  if (select granted_by from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000003') is not null then raise exception 'granted_by not set null'; end if;
end $$;
-- as role:
select 1;

-- ================================================================ set_admissions_capabilities

-- probe: C1 grant can_decide to an officer
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, false, '{}', false);
  if not exists (select 1 from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006' and can_decide) then raise exception 'not granted'; end if;
end $$;

-- probe: C2 inactive Manager cannot grant
-- expect: none
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
update public.staff set active = false where id = (select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1);
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, false, '{}', false);
end $$;

-- probe: C3 function grants: no anon or PUBLIC; callable ones for authenticated and service_role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (
    select 1 from pg_proc p
    where p.oid in ('public.admissions_grade_band(text)'::regprocedure,
                    'public.admissions_grade_visible(text)'::regprocedure,
                    'public.has_admissions_capability(text)'::regprocedure,
                    'public.set_admissions_capabilities(uuid,boolean,boolean,text[],boolean)'::regprocedure)
      and (has_function_privilege('anon', p.oid, 'execute')
           or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
           or not has_function_privilege('authenticated', p.oid, 'execute')
           or not has_function_privilege('service_role', p.oid, 'execute'))
  ) or exists (
    select 1 from pg_proc p
    where p.oid in ('public._admissions_capability_holder_problem(text,boolean,text[],boolean)'::regprocedure,
                    'public.set_admissions_capabilities_identity()'::regprocedure,
                    'public.check_admissions_capability_holder()'::regprocedure,
                    'public.guard_staff_role_change_admissions()'::regprocedure,
                    'public.clear_admissions_capabilities_on_deactivate()'::regprocedure,
                    'public.audit_admissions_capabilities()'::regprocedure)
      and (has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('authenticated', p.oid, 'execute'))
  ) then
    raise exception 'unexpected function grants';
  end if;
end $$;
-- as role:
select 1;

-- probe: C4 can_decide refused for Attendant, Accountant, Auditor
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000003', true, false, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'can_decide can only be held by a Manager or Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000002', true, false, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'can_decide can only be held by a Manager or Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000004', true, false, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'can_decide can only be held by a Manager or Admissions Officer' then raise; end if;
  end;
end $$;

-- probe: C5 grade_bands refused for every role but the officer
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000005', false, false, '{primary}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000003', false, false, '{primary}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000002', false, false, '{primary}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000004', false, false, '{primary}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
end $$;

-- probe: C6 all_grades refused for every role but the officer
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000005', false, false, '{}', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000003', false, false, '{}', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000002', false, false, '{}', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000004', false, false, '{}', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
end $$;

-- probe: C7 can_decide allowed for Manager and officer
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000005', true, false, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, false, '{}', false);
  if (select count(*) from public.staff_admissions_capabilities where staff_id in ('9e020000-0000-0000-0000-000000000005', '9e020000-0000-0000-0000-000000000006') and can_decide) <> 2 then raise exception 'not granted'; end if;
end $$;

-- probe: C8 can_view_health allowed for every role
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000002', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000003', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000004', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000005', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
  if (select count(*) from public.staff_admissions_capabilities where can_view_health) <> 5 then raise exception 'not all granted'; end if;
end $$;

-- probe: C9 officer scopes: one band, all three (stored sorted), all grades
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{primary}', false);
  if (select grade_bands from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') is distinct from array['primary'] then raise exception 'one band'; end if;
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{primary,preschool,jhs}', false);
  if (select grade_bands from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') is distinct from array['jhs','preschool','primary'] then raise exception 'not sorted'; end if;
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{}', true);
  if (select (all_grades, grade_bands) from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') is distinct from (true, '{}'::text[]) then raise exception 'all grades'; end if;
end $$;

-- probe: C10 validation refusals
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{shs}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Unknown grade band: shs (allowed: preschool, primary, jhs)' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{primary,primary}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Duplicate grade band: primary' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{primary}', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Choose either all grades or specific grade bands, not both' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', null, false, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'All admissions access values are required' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, null, false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'All admissions access values are required' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities(null, false, true, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Staff member is required' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-00000000dead', false, true, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Staff member not found' then raise; end if;
  end;
  begin
    perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000001', false, true, '{}', false);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Cannot change admissions access for an inactive staff member' then raise; end if;
  end;
end $$;

-- probe: C11 all-empty clears the row; no row is not an error
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{}', false);
  if exists (select 1 from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') then raise exception 'row not cleared'; end if;
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000005', false, false, '{}', false);
end $$;

-- probe: C12 identical call writes nothing
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ('9e020000-0000-0000-0000-000000000006', true);
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
  if (select granted_by from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') is not null then raise exception 'row was rewritten'; end if;
  if exists (select 1 from public.audit_log where entity_id = '9e020000-0000-0000-0000-000000000006'::text) then raise exception 'audit row written'; end if;
end $$;

-- probe: C13 a real change records the granting Manager
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ('9e020000-0000-0000-0000-000000000006', true);
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, true, '{}', false);
  if (select granted_by from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') is distinct from auth.uid() then raise exception 'granted_by not set'; end if;
end $$;

-- probe: C14 Manager self-grant
-- expect: Manager
do $$ begin
  perform public.set_admissions_capabilities(auth.uid(), true, true, '{}', false);
  if not exists (select 1 from public.staff_admissions_capabilities where staff_id = auth.uid() and can_decide and can_view_health) then raise exception 'not granted'; end if;
end $$;

-- probe: C15 Manager revokes own can_decide
-- expect: Manager
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  perform public.set_admissions_capabilities(auth.uid(), false, false, '{}', false);
  if exists (select 1 from public.staff_admissions_capabilities where staff_id = auth.uid()) then raise exception 'not cleared'; end if;
end $$;

-- ================================================================ holding rules and role changes

-- probe: D1 direct writes obey the holding rules
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
do $$ begin
  begin
    insert into public.staff_admissions_capabilities (staff_id, can_decide) values ('9e020000-0000-0000-0000-000000000002', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'can_decide can only be held by a Manager or Admissions Officer' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000003', '{primary}');
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  begin
    insert into public.staff_admissions_capabilities (staff_id, all_grades) values ('9e020000-0000-0000-0000-000000000005', true);
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Grade bands and all grades can only be held by an Admissions Officer' then raise; end if;
  end;
  insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ('9e020000-0000-0000-0000-000000000003', true), ('9e020000-0000-0000-0000-000000000002', true);
end $$;
-- as role:
select 1;

-- probe: D2 officer with bands -> Attendant refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000006', '{primary}');
do $$ begin
  begin
    update public.staff set role = 'Attendant' where id = '9e020000-0000-0000-0000-000000000006';
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'Cannot change P2 Officer to Attendant: %Clear it under Settings → Staff → Admissions access first.' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: D3 officer with all_grades -> Manager refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ('9e020000-0000-0000-0000-000000000006', true);
do $$ begin
  begin
    update public.staff set role = 'Manager' where id = '9e020000-0000-0000-0000-000000000006';
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'Cannot change P2 Officer to Manager: %Clear it under Settings → Staff → Admissions access first.' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: D4 officer with can_decide -> Manager allowed
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ('9e020000-0000-0000-0000-000000000006', true);
do $$ begin
  update public.staff set role = 'Manager' where id = '9e020000-0000-0000-0000-000000000006';
  if (select role from public.staff where id = '9e020000-0000-0000-0000-000000000006') is distinct from 'Manager' then raise exception 'role not changed'; end if;
end $$;
-- as role:
select 1;

-- probe: D5 officer with can_decide -> Accountant refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ('9e020000-0000-0000-0000-000000000006', true);
do $$ begin
  begin
    update public.staff set role = 'Accountant' where id = '9e020000-0000-0000-0000-000000000006';
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'Cannot change P2 Officer to Accountant: %Clear it under Settings → Staff → Admissions access first.' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: D6 Manager with can_decide -> officer allowed
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ('9e020000-0000-0000-0000-000000000005', true);
do $$ begin
  update public.staff set role = 'Admissions Officer' where id = '9e020000-0000-0000-0000-000000000005';
  if (select role from public.staff where id = '9e020000-0000-0000-0000-000000000005') is distinct from 'Admissions Officer' then raise exception 'role not changed'; end if;
end $$;
-- as role:
select 1;

-- probe: D7 Manager with can_decide -> Auditor refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ('9e020000-0000-0000-0000-000000000005', true);
do $$ begin
  begin
    update public.staff set role = 'Auditor' where id = '9e020000-0000-0000-0000-000000000005';
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'Cannot change P2 Manager to Auditor: %Clear it under Settings → Staff → Admissions access first.' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: D8 health only -> any role allowed
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ('9e020000-0000-0000-0000-000000000003', true), ('9e020000-0000-0000-0000-000000000002', true);
do $$ begin
  update public.staff set role = 'Auditor' where id = '9e020000-0000-0000-0000-000000000003';
  if (select role from public.staff where id = '9e020000-0000-0000-0000-000000000003') is distinct from 'Auditor' then raise exception 'role not changed'; end if;
  update public.staff set role = 'Admissions Officer' where id = '9e020000-0000-0000-0000-000000000002';
  if (select role from public.staff where id = '9e020000-0000-0000-0000-000000000002') is distinct from 'Admissions Officer' then raise exception 'role not changed'; end if;
end $$;
-- as role:
select 1;

-- probe: D9 no capability row -> role change unchanged
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
do $$ begin
  update public.staff set role = 'Accountant' where id = '9e020000-0000-0000-0000-000000000004';
  if (select role from public.staff where id = '9e020000-0000-0000-0000-000000000004') is distinct from 'Accountant' then raise exception 'role not changed'; end if;
end $$;
-- as role:
select 1;

-- probe: D10 Settings role change refused while bands held
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000006', '{primary}');
-- as role:
do $$ begin
  begin
    update public.staff set role = 'Attendant' where id = '9e020000-0000-0000-0000-000000000006';
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'Cannot change P2 Officer to Attendant: %Clear it under Settings → Staff → Admissions access first.' then raise; end if;
  end;
end $$;

-- probe: D11 Settings role change with no capabilities still works
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  update public.staff set role = 'Accountant' where id = '9e020000-0000-0000-0000-000000000004';
  if (select role from public.staff where id = '9e020000-0000-0000-0000-000000000004') is distinct from 'Accountant' then raise exception 'role not changed'; end if;
end $$;

-- probe: D12 protected account: protect_staff_row's message wins
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ('9e020000-0000-0000-0000-000000000006', '{primary}');
update public.staff set protected = true where id = '9e020000-0000-0000-0000-000000000006';
do $$ begin
  begin
    update public.staff set role = 'Attendant' where id = '9e020000-0000-0000-0000-000000000006';
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like 'This is a protected staff account%' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: D13 deactivating clears the row; reactivating doesn't restore it
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, grade_bands, can_decide) values ('9e020000-0000-0000-0000-000000000006', '{primary}', true);
-- as role:
do $$ begin
  declare n int; begin
  update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000006';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not deactivated'; end if;
  if exists (select 1 from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') then raise exception 'row not cleared'; end if;
  update public.staff set active = true where id = '9e020000-0000-0000-0000-000000000006';
  if exists (select 1 from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006') then raise exception 'row restored'; end if;
  end;
end $$;

-- probe: D14 an invited officer starts with no capabilities
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('9e020000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'p2-invited@tcs.test', '{"name":"P2 Invited","role":"Admissions Officer"}');
do $$ begin
  if exists (select 1 from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-0000000000a1') then raise exception 'row created'; end if;
end $$;
-- as role:
select 1;

-- ================================================================ audit

-- probe: E1 grant writes one complete audit row
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, false, '{}', false);
  if (select count(*) from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text) <> 1 then raise exception 'expected one audit row'; end if;
  if not exists (
    select 1 from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text
    and actor_id = auth.uid() and entity_table = 'staff_admissions_capabilities' and before is null
      and after = jsonb_build_object('can_decide', true, 'can_view_health', false, 'grade_bands', '[]'::jsonb,
                                     'all_grades', false, 'role', 'Admissions Officer', 'name', 'P2 Officer')
      and branch_id = (select branch_id from public.staff where id = '9e020000-0000-0000-0000-000000000006')
  ) then raise exception 'audit row content wrong'; end if;
end $$;

-- probe: E2 change records before and after
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, false, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', true, true, '{primary}', false);
  if not exists (
    select 1 from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text
    and before->>'can_view_health' = 'false' and after->>'can_view_health' = 'true'
      and after->'grade_bands' = '["primary"]'::jsonb
  ) then raise exception 'update not audited'; end if;
end $$;

-- probe: E3 clear records after = null
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, false, '{}', false);
  if not exists (select 1 from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text and after is null and before->>'can_view_health' = 'true') then
    raise exception 'clear not audited';
  end if;
end $$;

-- probe: E4 identical call adds no audit row
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
-- as role:
do $$ begin
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
  perform public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
  if (select count(*) from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text) <> 1 then raise exception 'no-op audited'; end if;
end $$;

-- probe: E5 self-grant audited with actor = holder
-- expect: Manager
do $$ begin
  perform public.set_admissions_capabilities(auth.uid(), false, true, '{}', false);
  if not exists (select 1 from public.audit_log
                 where action = 'admissions_capabilities_changed' and entity_id = auth.uid()::text and actor_id = auth.uid()) then
    raise exception 'self-grant not audited';
  end if;
end $$;

-- probe: E6 read capability audit rows
-- expect: Manager,Accountant,Auditor
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1))::text, true);
select public.set_admissions_capabilities('9e020000-0000-0000-0000-000000000006', false, true, '{}', false);
-- as role:
do $$ begin
  if not exists (select 1 from public.audit_log where action = 'admissions_capabilities_changed') then raise exception 'no rows visible'; end if;
end $$;

-- probe: E7 audit_log accepts every existing action and the new one, nothing else
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
  select (select id from public.branches order by created_at limit 1), (select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), a, 'probe', 'probe'
  from unnest(array['discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided', 'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected', 'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved', 'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed', 'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected', 'payroll_run_exclusion_added', 'payroll_run_exclusion_removed', 'admissions_capabilities_changed']) a;
  begin
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id) values ((select id from public.branches order by created_at limit 1), (select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), 'not_an_action', 'probe', 'probe');
    raise exception 'accepted';
  exception when others then
    if sqlerrm not like '%audit_log_action_check%' then raise; end if;
  end;
end $$;
-- as role:
select 1;

-- probe: E8 writes with no signed-in actor aren't audited
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ('9e020000-0000-0000-0000-000000000006', true);
update public.staff_admissions_capabilities set can_decide = true where staff_id = '9e020000-0000-0000-0000-000000000006';
delete from public.staff_admissions_capabilities where staff_id = '9e020000-0000-0000-0000-000000000006';
do $$ begin
  if exists (select 1 from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text) then raise exception 'audited without an actor'; end if;
end $$;
-- as role:
select 1;

-- probe: E9 deactivation clear audited, actor = deactivating Manager
-- expect: Manager
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('9e020000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-inactive-officer@tcs.test', '{"name":"P2 Inactive Officer","role":"Admissions Officer"}'),
  ('9e020000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-accountant@tcs.test', '{"name":"P2 Accountant","role":"Accountant"}'),
  ('9e020000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-attendant@tcs.test', '{"name":"P2 Attendant","role":"Attendant"}'),
  ('9e020000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-auditor@tcs.test', '{"name":"P2 Auditor","role":"Auditor"}'),
  ('9e020000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-manager@tcs.test', '{"name":"P2 Manager","role":"Manager"}'),
  ('9e020000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2-officer@tcs.test', '{"name":"P2 Officer","role":"Admissions Officer"}');
update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000001';
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ('9e020000-0000-0000-0000-000000000006', true);
-- as role:
do $$ begin
  update public.staff set active = false where id = '9e020000-0000-0000-0000-000000000006';
  if not exists (select 1 from public.audit_log where action = 'admissions_capabilities_changed' and entity_id = '9e020000-0000-0000-0000-000000000006'::text and actor_id = auth.uid() and after is null) then
    raise exception 'clear not audited';
  end if;
end $$;
