-- Admissions slice 1b-ii: the Admissions Officer role (docs/admissions/PORT-PLAN.md,
-- slice 1b-ii; decisions D-1b-b and D-1b-d, 2026-09-29).
--
-- 1b-i (20260929110000) already made every guard an allowlist, so the new role
-- reaches nothing it isn't named in: it reads branches (is_active_staff()),
-- its own staff row, and list_staff_names(). No policy, grant or other
-- function changes here. Proof: supabase/role-matrix/
-- 20260929130000_admissions_officer_role.sql plus the 1b-i files re-run with
-- a sixth column.

alter table public.staff drop constraint staff_role_check;
alter table public.staff add constraint staff_role_check
  check (role = any (array['Attendant', 'Manager', 'Accountant', 'Auditor', 'Admissions Officer']));

-- An explicit role outside the list used to become Attendant silently, which
-- would hand store access to anyone invited with a role this trigger doesn't
-- know. It now aborts the auth.users insert instead. A missing role still
-- defaults to Attendant: seed.sql and scripts/seed-local-dev-staff.sh create
-- users with a name only and set the role on staff afterwards. Every path
-- that passes a role (invite-staff, bootstrap-production-manager.sh) passes
-- one from the list.
create or replace function public.handle_new_staff_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_branch_id uuid;
  v_role text := coalesce(new.raw_user_meta_data ->> 'role', 'Attendant');
begin
  if v_role not in ('Attendant', 'Manager', 'Accountant', 'Auditor', 'Admissions Officer') then
    raise exception 'Unknown staff role: %', v_role;
  end if;

  select id into v_branch_id from public.branches order by created_at limit 1;

  insert into public.staff (id, branch_id, name, email, role)
  values (
    new.id,
    v_branch_id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)),
    new.email,
    v_role
  );

  return new;
end;
$function$;
