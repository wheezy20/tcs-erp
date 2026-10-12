-- Role matrix for 20261017100000_admissions_application_list (admissions slice 7a,
-- docs/admissions/PORT-PLAN.md): row scope through the admissions_application_list
-- view, the admissions_grade_name() helper, and the view's shape and grants.
-- Each probe raises unless the stated rows are visible (or, for structure
-- probes, the stated fact holds), so the expect line lists the roles for
-- which the statement holds. Fixture rows are invented (ids 9e070000-...);
-- capability rows go on the account the harness impersonates.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261017100000_admissions_application_list.sql

-- ================================================================ row scope

-- probe: L1 view read, Grade 3, no capability rows
-- expect: Manager,Auditor
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L2 view read, Grade 3, AO {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L3 view read, Grade 3, AO {jhs}
-- expect: Manager,Auditor
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L3b AO {jhs} sees exactly its in-scope row through the view and nothing out of scope
-- expect: Admissions Officer
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{jhs}', false);
-- as role:
do $$ declare v_ids uuid[];
begin
  select array_agg(id order by id) into v_ids from public.admissions_application_list
   where id::text like '9e070000-%';
  if v_ids is distinct from array['9e070000-0000-4000-8000-000400000002'::uuid] then
    raise exception 'visible set is %, expected only the Grade 8 row', v_ids;
  end if;
end $$;

-- probe: L4 view read, Grade 3, AO all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L5 view read, unbanded Grade 11, AO holding all three bands
-- expect: Manager,Auditor
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{preschool,primary,jhs}', false);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L5b view read, unbanded Grade 11, AO all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{}', true);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000003') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L6 live grade move (Grade 3 to Grade 7) hides the row from AO {primary}
-- expect: Manager,Auditor
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false);
update public.applications set year_group_applied_for = 'Grade 7' where id = '9e070000-0000-4000-8000-000400000001';
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list where id = '9e070000-0000-4000-8000-000400000001') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: L7 row for padded mixed-case ' grade  3 ' carries grade_name Grade 3 and band primary
-- expect: Manager,Auditor,Admissions Officer
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active order by id limit 1), '{primary}', false);
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_application_list
                 where id = '9e070000-0000-4000-8000-000400000004' and grade_name = 'Grade 3' and grade_band = 'primary') then
    raise exception 'not visible or wrong grade';
  end if;
  if not exists (select 1 from public.admissions_application_list
                 where id = '9e070000-0000-4000-8000-000400000003' and grade_name is null and grade_band is null)
     and public.has_role(array['Manager', 'Auditor']) then
    raise exception 'unbanded row should carry null grade_name and grade_band';
  end if;
end $$;

-- probe: L7b with no capability rows the view returns zero rows (Attendant, Accountant and a bare officer see nothing; anon is refused outright)
-- expect: Attendant,Accountant,Admissions Officer
insert into public.families (id) values ('9e070000-0000-4000-8000-000100000001');
insert into public.students (id, family_id, full_name) values
  ('9e070000-0000-4000-8000-000300000001', '9e070000-0000-4000-8000-000100000001', 'Probe Child Three'),
  ('9e070000-0000-4000-8000-000300000002', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eight'),
  ('9e070000-0000-4000-8000-000300000003', '9e070000-0000-4000-8000-000100000001', 'Probe Child Eleven'),
  ('9e070000-0000-4000-8000-000300000004', '9e070000-0000-4000-8000-000100000001', 'Probe Child Messy');
insert into public.applications (id, student_id, academic_year, year_group_applied_for) values
  ('9e070000-0000-4000-8000-000400000001', '9e070000-0000-4000-8000-000300000001', '2027/2028', 'Grade 3'),
  ('9e070000-0000-4000-8000-000400000002', '9e070000-0000-4000-8000-000300000002', '2027/2028', 'Grade 8'),
  ('9e070000-0000-4000-8000-000400000003', '9e070000-0000-4000-8000-000300000003', '2027/2028', 'Grade 11'),
  ('9e070000-0000-4000-8000-000400000004', '9e070000-0000-4000-8000-000300000004', '2027/2028', ' grade  3 ');
-- as role:
do $$ begin
  if exists (select 1 from public.admissions_application_list) then
    raise exception 'rows visible';
  end if;
end $$;

-- ================================================================ grants and shape

-- probe: L8 admissions_grade_name agrees with admissions_grade_band on messy inputs
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare v text;
begin
  foreach v in array array['Grade 3', ' grade  3 ', E'GRADE\t9', 'nursery 1', 'Pre  Nursery', 'Kindergarten 2 ', 'Grade 10', 'Grade 11', 'Other', '2027', ''] loop
    if (public.admissions_grade_name(v) is null) <> (public.admissions_grade_band(v) is null) then
      raise exception 'name and band disagree for %', v;
    end if;
  end loop;
  if public.admissions_grade_name(' grade  3 ') is distinct from 'Grade 3' then
    raise exception 'messy Grade 3 did not resolve';
  end if;
  if public.admissions_grade_name('Grade 11') is not null or public.admissions_grade_name('Other') is not null then
    raise exception 'an unbanded grade resolved';
  end if;
end $$;
-- as role:
select 1;

-- probe: L9 view is security_invoker and its columns are exactly the pinned list
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (select 1 from pg_class where oid = 'public.admissions_application_list'::regclass
                 and reloptions @> array['security_invoker=true']) then
    raise exception 'view is not security_invoker';
  end if;
  if (select array_agg(attname::text order by attnum) from pg_attribute
      where attrelid = 'public.admissions_application_list'::regclass and attnum > 0 and not attisdropped)
     is distinct from array['id', 'student_id', 'student_full_name', 'branch_id', 'branch_name',
       'academic_year', 'year_group_applied_for', 'grade_name', 'grade_band', 'month_of_enrollment',
       'stage', 'inquiry_reference', 'application_reference', 'created_at', 'updated_at'] then
    raise exception 'view columns changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: L10 anon cannot read the view
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
select count(*) from public.admissions_application_list;

-- probe: L10b anon cannot execute admissions_grade_name
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
select public.admissions_grade_name('Grade 3');

-- probe: L10c grants: only authenticated and service_role hold privileges on the view, select only
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if has_table_privilege('anon', 'public.admissions_application_list', 'select') then
    raise exception 'anon can select the view';
  end if;
  if exists (select 1 from information_schema.role_table_grants
             where table_schema = 'public' and table_name = 'admissions_application_list'
               and (grantee not in ('authenticated', 'service_role', 'postgres') or
                    (grantee in ('authenticated', 'service_role') and privilege_type <> 'SELECT'))) then
    raise exception 'unexpected grant on the view';
  end if;
end $$;
-- as role:
select 1;

-- probe: L11 admissions_grade_name is security definer with a pinned search_path
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if not exists (select 1 from pg_proc where oid = 'public.admissions_grade_name(text)'::regprocedure
                 and prosecdef and proconfig @> array['search_path=public']) then
    raise exception 'not security definer with search_path=public';
  end if;
  if not has_function_privilege('authenticated', 'public.admissions_grade_name(text)', 'execute') then
    raise exception 'authenticated cannot execute';
  end if;
end $$;
-- as role:
select 1;

-- probe: L12 anon can still execute exactly 169 public functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 169 then
    raise exception 'anon-executable function count changed';
  end if;
end $$;
-- as role:
select 1;
