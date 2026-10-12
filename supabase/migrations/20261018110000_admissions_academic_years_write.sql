-- Admissions slice 7b2: academic year writes and the tightened capacity year
-- (docs/admissions/PORT-PLAN.md, slice 7b2; plan approved 2026-10-12).
--
-- * add_admissions_academic_year(p_label): Manager only. The label must be
--   YYYY/YYYY with consecutive years (the table's CHECK); the database
--   assigns the next position. A duplicate is refused with a plain error.
-- * set_admissions_academic_year_active(p_label, p_active): Manager only,
--   retire or reactivate. There is no rename and no delete.
-- * audit_admissions_academic_year(): admissions_academic_year_changed for
--   every add and every change of the active flag, only for a signed-in
--   actor. The action is already in the audit CHECK (7b1,
--   20261018100000); this slice does not touch the CHECK.
-- * create_admissions_capacity(): same signature (create or replace, no
--   drop), now refuses a year that isn't active on the list. Existing
--   capacity rows for an unlisted year are left alone; update and delete
--   still work on them.
--
-- Order of checks everywhere: role, then scope (none here: the list is
-- entity wide), then validation, then writes. Every non-Manager gets the
-- same error whatever the input, because the role check runs first.

-- ------------------------------------------------------------ helper

-- The signed-in Manager, or one plain error for everyone else. No argument
-- is read before this runs.
create or replace function public._require_admissions_year_manager()
returns public.staff
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
begin
  if auth.uid() is null then
    raise exception 'Only a Manager can change the academic year list';
  end if;
  select * into v_staff from public.staff where id = auth.uid() and active;
  if not found or v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change the academic year list';
  end if;
  return v_staff;
end;
$$;

-- ------------------------------------------------------------ academic year RPCs

-- Manager only. The label is trimmed, then must match the table's format.
-- The position is one past the current highest. The table lock makes two
-- adds at once take positions one after the other.
create or replace function public.add_admissions_academic_year(p_label text)
returns public.admissions_academic_years
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_label text;
  v_valid boolean;
  v_row public.admissions_academic_years;
begin
  v_staff := public._require_admissions_year_manager();
  v_label := btrim(coalesce(p_label, ''));
  -- case, not and: the casts must only run once the shape is known good.
  v_valid := case when v_label ~ '^[0-9]{4}/[0-9]{4}$'
    then split_part(v_label, '/', 2)::integer = split_part(v_label, '/', 1)::integer + 1
    else false
  end;
  if not v_valid then
    raise exception 'The academic year must look like 2028/2029, two consecutive years';
  end if;
  lock table public.admissions_academic_years in share row exclusive mode;
  if exists (select 1 from public.admissions_academic_years where label = v_label) then
    raise exception 'That academic year is already on the list';
  end if;
  insert into public.admissions_academic_years (label, position)
  values (v_label, coalesce((select max(position) from public.admissions_academic_years), 0) + 1)
  returning * into v_row;
  return v_row;
end;
$$;

-- Manager only. Retire (false) or reactivate (true). A retired year stays
-- on the list, so applications and capacity rows that use it still match.
create or replace function public.set_admissions_academic_year_active(p_label text, p_active boolean)
returns public.admissions_academic_years
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_row public.admissions_academic_years;
begin
  v_staff := public._require_admissions_year_manager();
  if p_active is null then
    raise exception 'Choose whether the academic year is active';
  end if;
  select * into v_row from public.admissions_academic_years
  where label = btrim(coalesce(p_label, '')) for update;
  if not found then
    raise exception 'Academic year not found';
  end if;
  if v_row.is_active = p_active then
    raise exception 'The academic year % is already %', v_row.label,
      case when p_active then 'active' else 'retired' end;
  end if;
  update public.admissions_academic_years set is_active = p_active where label = v_row.label
  returning * into v_row;
  return v_row;
end;
$$;

-- ------------------------------------------------------------ capacity

-- As 20261015100000, plus the year must be active on the academic year
-- list. The year row is share-locked so it can't be retired between the
-- check and the insert. The length check stays first, so its message is
-- unchanged.
create or replace function public.create_admissions_capacity(
  p_academic_year text, p_grade_id uuid, p_branch_id uuid, p_capacity integer
)
returns public.admissions_capacity
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_year text := btrim(coalesce(p_academic_year, ''));
  v_row public.admissions_capacity;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can change admissions capacity';
  end if;
  if v_year = '' or char_length(v_year) > 50 then
    raise exception 'The academic year must be 1 to 50 characters';
  end if;
  perform 1 from public.admissions_academic_years
  where label = v_year and is_active for share;
  if not found then
    raise exception 'The academic year must be an active year on the academic year list';
  end if;
  if p_grade_id is null or not exists (select 1 from public.admissions_grades where id = p_grade_id) then
    raise exception 'Grade not found';
  end if;
  if p_branch_id is not null and not exists (select 1 from public.branches where id = p_branch_id) then
    raise exception 'Campus not found';
  end if;
  if p_capacity is null or p_capacity < 0 or p_capacity > 100000 then
    raise exception 'Capacity must be a whole number from 0 to 100,000';
  end if;
  begin
    insert into public.admissions_capacity (academic_year, grade_id, branch_id, capacity)
    values (v_year, p_grade_id, p_branch_id, p_capacity)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'A capacity for this year, grade and campus already exists';
  end;
  return v_row;
end;
$$;

-- ------------------------------------------------------------ audit trigger

-- admissions_academic_year_changed, only for a signed-in actor: every add,
-- and every change of the active flag. The list is entity wide, so the row
-- goes to the actor's campus, as admissions_settings_changed does.
create or replace function public.audit_admissions_academic_year()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
begin
  if v_actor is null then return null; end if;
  if tg_op = 'UPDATE' and old.is_active is not distinct from new.is_active then
    return null;
  end if;
  v_branch := (select branch_id from public.staff where id = v_actor);
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'admissions_academic_year_changed', 'admissions_academic_years', new.label,
    case when tg_op = 'UPDATE' then jsonb_build_object('is_active', old.is_active) end,
    jsonb_build_object('label', new.label, 'is_active', new.is_active, 'position', new.position)
  );
  return null;
end;
$$;

create trigger admissions_academic_years_audit
  after insert or update of is_active on public.admissions_academic_years
  for each row execute function public.audit_admissions_academic_year();

-- ------------------------------------------------------------ grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. The helper and the trigger
-- function get no grant; the two RPCs are for signed-in staff.
-- create_admissions_capacity keeps its 6a grants (create or replace keeps
-- them); they are restated here so this file shows them.
revoke execute on function public._require_admissions_year_manager() from public, anon, authenticated;
revoke execute on function public.audit_admissions_academic_year() from public, anon, authenticated;

revoke execute on function public.add_admissions_academic_year(text) from public, anon;
revoke execute on function public.set_admissions_academic_year_active(text, boolean) from public, anon;
revoke execute on function public.create_admissions_capacity(text, uuid, uuid, integer) from public, anon;
grant execute on function public.add_admissions_academic_year(text) to authenticated, service_role;
grant execute on function public.set_admissions_academic_year_active(text, boolean) to authenticated, service_role;
grant execute on function public.create_admissions_capacity(text, uuid, uuid, integer) to authenticated, service_role;
