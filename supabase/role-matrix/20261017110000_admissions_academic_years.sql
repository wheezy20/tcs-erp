-- Role matrix for 20261017110000_admissions_academic_years (admissions slice 7a,
-- docs/admissions/PORT-PLAN.md): read scope, no write path for any role, and
-- the table's shape, seed and grants.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261017110000_admissions_academic_years.sql

-- probe: Y1 read the academic year list
-- expect: Manager,Auditor,Admissions Officer
-- as role:
do $$ begin
  if not exists (select 1 from public.admissions_academic_years where label = '2026/2027') then
    raise exception 'not visible';
  end if;
end $$;

-- probe: Y2 insert an academic year
-- expect: none
-- as role:
insert into public.admissions_academic_years (label, position) values ('2028/2029', 3);

-- probe: Y3 update an academic year
-- expect: none
-- as role:
do $$ declare v_n integer;
begin
  update public.admissions_academic_years set is_active = false where label = '2026/2027';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'no row updated'; end if;
end $$;

-- probe: Y4 delete an academic year
-- expect: none
-- as role:
do $$ declare v_n integer;
begin
  delete from public.admissions_academic_years where label = '2026/2027';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'no row deleted'; end if;
end $$;

-- probe: Y5 RLS on, no anon privilege, seed is exactly the agreed labels, bad labels refused
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare v text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.admissions_academic_years'::regclass) then
    raise exception 'RLS off';
  end if;
  if has_table_privilege('anon', 'public.admissions_academic_years', 'select,insert,update,delete') then
    raise exception 'anon holds a privilege';
  end if;
  if has_table_privilege('authenticated', 'public.admissions_academic_years', 'insert,update,delete') then
    raise exception 'authenticated holds a write privilege';
  end if;
  if (select array_agg(label order by position) from public.admissions_academic_years)
     is distinct from array['2026/2027', '2027/2028'] then
    raise exception 'seeded labels changed';
  end if;
  foreach v in array array['2026/2028', '2026-2027', '2026', '26/27', ' 2026/2027'] loop
    begin
      insert into public.admissions_academic_years (label, position) values (v, 99);
      raise exception 'accepted bad label %', v;
    exception when check_violation then null;
    end;
  end loop;
end $$;
-- as role:
select 1;
