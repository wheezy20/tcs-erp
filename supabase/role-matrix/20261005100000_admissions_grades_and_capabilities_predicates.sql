-- Role matrix for 20261005100000_admissions_grades_and_capabilities,
-- PREDICATES file: admissions_grade_band(), admissions_grade_visible(),
-- has_admissions_capability() (admissions slice 2, docs/admissions/PORT-PLAN.md).
-- Each probe raises unless the predicate gives the stated value, so the
-- expect line lists the roles for which the statement holds. anon has no
-- execute on any predicate, so it is never listed. Grade strings are
-- invented; capability rows go on the accounts the harness impersonates
-- (role, active, lowest id; the Attendant is a seed.sql account).
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261005100000_admissions_grades_and_capabilities_predicates.sql

-- ================================================================ admissions_grade_band

-- probe: F1 band truth table
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (public.admissions_grade_band('Grade 3'), public.admissions_grade_band('Nursery 2'),
      public.admissions_grade_band('Kindergarten 2'), public.admissions_grade_band('Pre Nursery'),
      public.admissions_grade_band('Grade 9'))
     is distinct from ('primary', 'preschool', 'preschool', 'preschool', 'jhs') then
    raise exception 'banded grades wrong';
  end if;
  if coalesce(public.admissions_grade_band('Grade 10'), public.admissions_grade_band('Grade 11'),
              public.admissions_grade_band('Other: Year 13'), public.admissions_grade_band('KG 1'),
              public.admissions_grade_band(''), public.admissions_grade_band(null)) is not null then
    raise exception 'unbanded grades resolved to a band';
  end if;
end $$;

-- probe: F2 case and whitespace are ignored
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (public.admissions_grade_band('grade 3'), public.admissions_grade_band(' GRADE  3 '),
      public.admissions_grade_band('kindergarten 2'), public.admissions_grade_band(E'\tGrade\t3\n'))
     is distinct from ('primary', 'primary', 'preschool', 'primary') then
    raise exception 'variants not resolved';
  end if;
end $$;

-- probe: F3 an inactive grade row still resolves
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.admissions_grades set is_active = false where name = 'Grade 3';
-- as role:
do $$ begin
  if public.admissions_grade_band('Grade 3') is distinct from 'primary' then raise exception 'inactive row not resolved'; end if;
end $$;

-- probe: F4 re-coding a grade moves it between bands live
-- expect: Manager,Auditor,Admissions Officer
update public.admissions_grades set classification_code = '04' where name = 'Grade 6';
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{jhs}');
-- as role:
do $$ begin
  if public.admissions_grade_band('Grade 6') is distinct from 'jhs' then raise exception 'band not moved'; end if;
  if not public.admissions_grade_visible('Grade 6') then raise exception 'not visible'; end if;
end $$;

-- ================================================================ has_admissions_capability

-- probe: G1 'decide' is false with no row
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if  public.has_admissions_capability('decide') then raise exception 'capability(%) is wrong', 'decide'; end if;
end $$;

-- probe: G2 'decide' is true with a can_decide row
-- expect: Manager,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true), ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not public.has_admissions_capability('decide') then raise exception 'capability(%) is wrong', 'decide'; end if;
end $$;

-- probe: G3 'decide' is false with health only
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if  public.has_admissions_capability('decide') then raise exception 'capability(%) is wrong', 'decide'; end if;
end $$;

-- probe: G4 'decide' is false for a role that can't hold it, even if the row exists
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
alter table public.staff_admissions_capabilities disable trigger staff_admissions_capabilities_check_holder;
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_decide) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if  public.has_admissions_capability('decide') then raise exception 'capability(%) is wrong', 'decide'; end if;
end $$;

-- probe: G5 'health' is true with a can_view_health row
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Manager' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Auditor' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not public.has_admissions_capability('health') then raise exception 'capability(%) is wrong', 'health'; end if;
end $$;

-- probe: G6 'health' is false with no row
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if  public.has_admissions_capability('health') then raise exception 'capability(%) is wrong', 'health'; end if;
end $$;

-- probe: G7 an inactive holder has no capability
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
  if  public.has_admissions_capability('health') then raise exception 'capability(%) is wrong', 'health'; end if;
end $$;

-- probe: G8 an unknown capability name raises
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  begin
    perform public.has_admissions_capability('approve');
    raise exception 'accepted';
  exception when others then
    if sqlerrm is distinct from 'Unknown admissions capability: approve' then raise; end if;
  end;
end $$;

-- probe: G9 a null capability name is false
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if  public.has_admissions_capability(null) then raise exception 'capability(%) is wrong', null; end if;
end $$;

-- ================================================================ admissions_grade_visible

-- probe: H1 Grade 3, no capability rows
-- expect: Manager,Auditor
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H2 Grade 3, officer {primary}
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{primary}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H3 Grade 3, officer {preschool}
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{preschool}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H4 Grade 3, officer {jhs}
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{jhs}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H5 Grade 3, officer all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H6 Grade 11 (unbanded), officer with all three bands
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{preschool,primary,jhs}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 11'), false) then raise exception 'visible(%) is wrong', 'Grade 11'; end if;
end $$;

-- probe: H7 Grade 11 (unbanded), officer all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 11'), false) then raise exception 'visible(%) is wrong', 'Grade 11'; end if;
end $$;

-- probe: H8 Nursery 1, officer {preschool}
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{preschool}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Nursery 1'), false) then raise exception 'visible(%) is wrong', 'Nursery 1'; end if;
end $$;

-- probe: H9 Nursery 1, officer {primary}
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{primary}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Nursery 1'), false) then raise exception 'visible(%) is wrong', 'Nursery 1'; end if;
end $$;

-- probe: H10 Grade 7, officer {jhs}
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{jhs}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 7'), false) then raise exception 'visible(%) is wrong', 'Grade 7'; end if;
end $$;

-- probe: H11 Grade 7, officer {primary}
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{primary}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Grade 7'), false) then raise exception 'visible(%) is wrong', 'Grade 7'; end if;
end $$;

-- probe: H12 'Other: Year 13', officer with all three bands
-- expect: Manager,Auditor
insert into public.staff_admissions_capabilities (staff_id, grade_bands) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), '{preschool,primary,jhs}');
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Other: Year 13'), false) then raise exception 'visible(%) is wrong', 'Other: Year 13'; end if;
end $$;

-- probe: H13 'Other: Year 13', officer all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible('Other: Year 13'), false) then raise exception 'visible(%) is wrong', 'Other: Year 13'; end if;
end $$;

-- probe: H14 null and empty grade, officer all_grades
-- expect: Manager,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if not coalesce(public.admissions_grade_visible(null), false) then raise exception 'visible(%) is wrong', null; end if;
end $$;
do $$ begin
  if not coalesce(public.admissions_grade_visible(''), false) then raise exception 'visible(%) is wrong', ''; end if;
end $$;

-- probe: H15 Attendant and Accountant with capability rows still see nothing
-- expect: Attendant,Accountant
insert into public.staff_admissions_capabilities (staff_id, can_view_health) values ((select id from public.staff where role = 'Attendant' and active and id::text not like '9e020000-%' order by id limit 1), true), ((select id from public.staff where role = 'Accountant' and active and id::text not like '9e020000-%' order by id limit 1), true);
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
-- as role:
do $$ begin
  if  coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H16 inactive staff see no grade, all_grades or not
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.staff_admissions_capabilities (staff_id, all_grades) values ((select id from public.staff where role = 'Admissions Officer' and active and id::text not like '9e020000-%' order by id limit 1), true);
alter table public.staff disable trigger staff_clear_admissions_caps_on_deactivate;
update public.staff set active = false where not protected;
-- as role:
do $$ begin
  if  coalesce(public.admissions_grade_visible('Grade 3'), false) then raise exception 'visible(%) is wrong', 'Grade 3'; end if;
end $$;

-- probe: H17 predicates are SECURITY DEFINER, stable, search_path pinned
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if exists (
    select 1 from pg_proc p
    where p.oid in ('public.admissions_grade_band(text)'::regprocedure,
                    'public.admissions_grade_visible(text)'::regprocedure,
                    'public.has_admissions_capability(text)'::regprocedure)
      and not (p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=public'])
  ) then
    raise exception 'predicate attributes wrong';
  end if;
end $$;
-- as role:
select 1;
