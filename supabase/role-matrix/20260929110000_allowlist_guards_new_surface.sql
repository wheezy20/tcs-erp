-- Role matrix for admissions slice 1b-i (allowlist guards), NEW SURFACE file.
-- docs/admissions/PORT-PLAN.md, slice 1b; decisions D-1b-a/b.
--
-- Covers what 20260929110000_allowlist_guards.sql adds: can_read_store() and
-- list_staff_names(). These don't exist on the old schema, so they live
-- apart from the before/after regression file
-- (20260929110000_allowlist_guards_regression.sql).
-- The staff own-row branch for a role outside can_read_store() can't be
-- probed until slice 1b-ii adds such a role.
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20260929110000_allowlist_guards_new_surface.sql

-- probe: can_read_store()
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not public.can_read_store() then raise exception 'false'; end if; end $$;

-- probe: can_read_store(), every staff row inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
do $$ begin if not public.can_read_store() then raise exception 'false'; end if; end $$;

-- probe: list_staff_names()
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from public.list_staff_names()) < 2 then
    raise exception 'expected every staff name';
  end if;
end $$;

-- probe: list_staff_names() returns only id and name
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select array_agg(k order by k)
      from jsonb_object_keys(to_jsonb((select r from public.list_staff_names() r limit 1))) k)
     is distinct from array['id', 'name'] then
    raise exception 'unexpected columns';
  end if;
end $$;

-- probe: list_staff_names() includes an inactive member
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('9e000000-0000-0000-0000-00000000001b', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'probe-former@tcs.test',
        '{"name":"Probe Former Staff","role":"Attendant"}');
update public.staff set active = false where id = '9e000000-0000-0000-0000-00000000001b';
-- as role:
do $$ begin
  if not exists (select 1 from public.list_staff_names()
                 where id = '9e000000-0000-0000-0000-00000000001b' and name = 'Probe Former Staff') then
    raise exception 'inactive member missing';
  end if;
end $$;

-- probe: list_staff_names(), every staff row inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
select * from public.list_staff_names();
