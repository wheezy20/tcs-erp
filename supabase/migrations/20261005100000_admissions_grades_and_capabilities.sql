-- Admissions slice 2: grade reference data and the capabilities layer
-- (docs/admissions/PORT-PLAN.md, slice 2; decisions D-2a, D-2b-revised,
-- D-2c to D-2g, and O-1 to O-9 recorded 2026-10-05).
--
-- admissions_grades replaces TCS OS's hand-kept STUDENT_ID_CLASSIFICATION
-- and the GRADE_BANDS derived from it (models.py:24-52): band is generated
-- from classification_code, so the two can't drift apart.
--
-- staff_admissions_capabilities narrows access inside admissions. No row
-- means nothing granted. Writes go only through set_admissions_capabilities()
-- (active Manager only); every change is audited by trigger. Who may hold
-- what is enforced on both sides: on the capabilities table, and on a staff
-- role change. Deactivating a member clears their row (O-1).
--
-- The predicates admissions_grade_band(), admissions_grade_visible() and
-- has_admissions_capability() are for the slice 3-6 policies and RPCs.
-- No admissions data table exists yet. No anon surface: every new function
-- is revoked from public and anon, and neither table has an anon grant.

-- ------------------------------------------------------------ admissions_grades

create table public.admissions_grades (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  position integer not null,
  classification_code text check (classification_code in ('01', '02', '03', '04')),
  band text generated always as (
    case
      when classification_code in ('01', '02') then 'preschool'
      when classification_code = '03' then 'primary'
      when classification_code = '04' then 'jhs'
    end
  ) stored,
  is_preschool_vaccination_required boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index admissions_grades_name_key on public.admissions_grades (lower(name));

-- The 14 TCS OS grades (models.py:24-39; vaccination per serializers.py:14).
-- No SHS rows: they have no classification code yet (TODO(SHS), O-3).
insert into public.admissions_grades
  (name, position, classification_code, is_preschool_vaccination_required)
values
  ('Pre Nursery', 1, '01', true),
  ('Nursery 1', 2, '01', true),
  ('Nursery 2', 3, '01', true),
  ('Kindergarten 1', 4, '02', true),
  ('Kindergarten 2', 5, '02', true),
  ('Grade 1', 6, '03', false),
  ('Grade 2', 7, '03', false),
  ('Grade 3', 8, '03', false),
  ('Grade 4', 9, '03', false),
  ('Grade 5', 10, '03', false),
  ('Grade 6', 11, '03', false),
  ('Grade 7', 12, '04', false),
  ('Grade 8', 13, '04', false),
  ('Grade 9', 14, '04', false)
on conflict ((lower(name))) do nothing;

alter table public.admissions_grades enable row level security;

create policy admissions_grades_select on public.admissions_grades
  for select using (public.has_role(array['Manager', 'Auditor', 'Admissions Officer']));

revoke all on table public.admissions_grades from anon, authenticated;
grant select on table public.admissions_grades to authenticated;
grant select, insert, update, delete on table public.admissions_grades to service_role;

-- ------------------------------------------------------------ capabilities

create table public.staff_admissions_capabilities (
  staff_id uuid primary key references public.staff (id) on delete cascade,
  can_decide boolean not null default false,
  can_view_health boolean not null default false,
  grade_bands text[] not null default '{}',
  all_grades boolean not null default false,
  granted_by uuid references public.staff (id) on delete set null,
  updated_at timestamptz not null default now(),
  -- Only the three band names, each at most once (<@ alone allows repeats
  -- and the count also rejects a NULL element).
  constraint staff_admissions_capabilities_bands_check check (
    grade_bands <@ array['preschool', 'primary', 'jhs']
    and cardinality(grade_bands) =
      ('preschool' = any (grade_bands))::int
      + ('primary' = any (grade_bands))::int
      + ('jhs' = any (grade_bands))::int
  ),
  -- D-2g: all grades, or specific bands, never both.
  constraint staff_admissions_capabilities_scope_check check (
    not (all_grades and cardinality(grade_bands) > 0)
  ),
  -- No row means nothing granted, so an all-empty row isn't allowed (O-7).
  constraint staff_admissions_capabilities_not_empty_check check (
    can_decide or can_view_health or all_grades or cardinality(grade_bands) > 0
  )
);

alter table public.staff_admissions_capabilities enable row level security;

-- Own row for every active staff member; all rows for Manager and Auditor.
create policy staff_admissions_capabilities_select on public.staff_admissions_capabilities
  for select using (
    public.has_role(array['Manager', 'Auditor'])
    or (staff_id = auth.uid() and public.is_active_staff())
  );

revoke all on table public.staff_admissions_capabilities from anon, authenticated;
grant select on table public.staff_admissions_capabilities to authenticated;
grant select, insert, update, delete on table public.staff_admissions_capabilities to service_role;

-- Server-forced: who last changed the row, and when.
create or replace function public.set_admissions_capabilities_identity()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then new.granted_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger staff_admissions_capabilities_set_identity
  before insert or update on public.staff_admissions_capabilities
  for each row execute function public.set_admissions_capabilities_identity();

-- ------------------------------------------------------------ who may hold what

-- One definition of the holding rules (D-2b-revised), used by both triggers
-- and the RPC. Returns the problem, or null when the role may hold them.
create or replace function public._admissions_capability_holder_problem(
  p_role text, p_can_decide boolean, p_grade_bands text[], p_all_grades boolean
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_can_decide and p_role not in ('Manager', 'Admissions Officer')
      then 'can_decide can only be held by a Manager or Admissions Officer'
    when (p_all_grades or cardinality(p_grade_bands) > 0) and p_role <> 'Admissions Officer'
      then 'Grade bands and all grades can only be held by an Admissions Officer'
  end;
$$;

create or replace function public.check_admissions_capability_holder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_problem text;
begin
  -- for share: a concurrent role change on this member waits for us.
  select role into v_role from public.staff where id = new.staff_id for share;
  if not found then
    raise exception 'Staff member not found';
  end if;
  v_problem := public._admissions_capability_holder_problem(
    v_role, new.can_decide, new.grade_bands, new.all_grades);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;
  return new;
end;
$$;

create trigger staff_admissions_capabilities_check_holder
  before insert or update on public.staff_admissions_capabilities
  for each row execute function public.check_admissions_capability_holder();

-- A role change that would leave a capability the new role can't hold is
-- refused until a Manager clears it. Applies to every caller.
create or replace function public.guard_staff_role_change_admissions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caps public.staff_admissions_capabilities;
  v_problem text;
begin
  select * into v_caps from public.staff_admissions_capabilities where staff_id = new.id;
  if not found then
    return new;
  end if;
  v_problem := public._admissions_capability_holder_problem(
    new.role, v_caps.can_decide, v_caps.grade_bands, v_caps.all_grades);
  if v_problem is not null then
    raise exception 'Cannot change % to %: % (%). Clear it under Settings → Staff → Admissions access first.',
      new.name, new.role, 'they hold admissions access that role cannot hold', v_problem;
  end if;
  return new;
end;
$$;

create trigger staff_role_capability_guard
  before update of role on public.staff
  for each row when (old.role is distinct from new.role)
  execute function public.guard_staff_role_change_admissions();

-- O-1: deactivating a member clears their admissions access, so a
-- reactivated member doesn't silently regain it. Audited as a change by the
-- deactivating Manager.
create or replace function public.clear_admissions_capabilities_on_deactivate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.staff_admissions_capabilities where staff_id = new.id;
  return null;
end;
$$;

create trigger staff_clear_admissions_caps_on_deactivate
  after update of active on public.staff
  for each row when (old.active and not new.active)
  execute function public.clear_admissions_capabilities_on_deactivate();

-- ------------------------------------------------------------ predicates

-- The band a grade belongs to, or null (unbanded: SHS, free-text "Other",
-- unknown). Case and extra whitespace (spaces, tabs, newlines) are ignored
-- (O-2).
create or replace function public.admissions_grade_band(p_grade text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select g.band
  from public.admissions_grades g
  where lower(g.name) = regexp_replace(regexp_replace(lower(p_grade), '^\s+|\s+$', '', 'g'), '\s+', ' ', 'g');
$$;

-- Whether the caller may see an application for this grade (D-2c: the grade
-- applied for, resolved live). Manager and Auditor see every grade; an
-- Admissions Officer sees all_grades, or grades in their bands; with neither
-- they see nothing. Every other role: false.
create or replace function public.admissions_grade_visible(p_grade text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.has_role(array['Manager', 'Auditor']) then true
    when public.has_role(array['Admissions Officer']) then coalesce((
      select c.all_grades
        or coalesce(public.admissions_grade_band(p_grade) = any (c.grade_bands), false)
      from public.staff_admissions_capabilities c
      where c.staff_id = auth.uid()
    ), false)
    else false
  end;
$$;

-- 'decide': an active Manager or Admissions Officer holding can_decide (the
-- role is re-checked here too). 'health': any active member holding
-- can_view_health; slice 4 intersects it with admissions_grade_visible().
-- An unknown name raises (O-5), so a typo in a policy shows at once.
create or replace function public.has_admissions_capability(p_capability text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_capability is null then
    return false;
  elsif p_capability = 'decide' then
    return public.has_role(array['Manager', 'Admissions Officer'])
      and exists (select 1 from public.staff_admissions_capabilities
                  where staff_id = auth.uid() and can_decide);
  elsif p_capability = 'health' then
    return public.is_active_staff()
      and exists (select 1 from public.staff_admissions_capabilities
                  where staff_id = auth.uid() and can_view_health);
  end if;
  raise exception 'Unknown admissions capability: %', p_capability;
end;
$$;

-- ------------------------------------------------------------ the write RPC

-- Sets a member's full admissions access. Active Manager only; self-grant is
-- allowed and audited (D-2e). All-empty clears the row (O-7). A call that
-- changes nothing writes nothing. Not a create function: p_staff_id names an
-- existing staff row, it isn't a client-chosen new key.
create or replace function public.set_admissions_capabilities(
  p_staff_id uuid,
  p_can_decide boolean,
  p_can_view_health boolean,
  p_grade_bands text[],
  p_all_grades boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_active boolean;
  v_band text;
  v_bands text[];
  v_existing public.staff_admissions_capabilities;
  v_problem text;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can change admissions access';
  end if;

  if p_staff_id is null then
    raise exception 'Staff member is required';
  end if;
  if p_can_decide is null or p_can_view_health is null
     or p_grade_bands is null or p_all_grades is null then
    raise exception 'All admissions access values are required';
  end if;

  select role, active into v_role, v_active from public.staff where id = p_staff_id for share;
  if not found then
    raise exception 'Staff member not found';
  end if;

  foreach v_band in array p_grade_bands loop
    if v_band is null or v_band not in ('preschool', 'primary', 'jhs') then
      raise exception 'Unknown grade band: % (allowed: preschool, primary, jhs)',
        coalesce(v_band, 'NULL');
    end if;
  end loop;
  if cardinality(p_grade_bands) <> (select count(distinct b) from unnest(p_grade_bands) b) then
    raise exception 'Duplicate grade band: %',
      (select b from unnest(p_grade_bands) b group by b having count(*) > 1 limit 1);
  end if;
  if p_all_grades and cardinality(p_grade_bands) > 0 then
    raise exception 'Choose either all grades or specific grade bands, not both';
  end if;

  v_bands := array(select b from unnest(p_grade_bands) b order by b);
  select * into v_existing from public.staff_admissions_capabilities where staff_id = p_staff_id;

  if not (p_can_decide or p_can_view_health or p_all_grades or cardinality(v_bands) > 0) then
    delete from public.staff_admissions_capabilities where staff_id = p_staff_id;
    return;
  end if;

  if not v_active then
    raise exception 'Cannot change admissions access for an inactive staff member';
  end if;
  v_problem := public._admissions_capability_holder_problem(
    v_role, p_can_decide, v_bands, p_all_grades);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;

  if v_existing.staff_id is null then
    insert into public.staff_admissions_capabilities
      (staff_id, can_decide, can_view_health, grade_bands, all_grades)
    values (p_staff_id, p_can_decide, p_can_view_health, v_bands, p_all_grades);
  elsif (v_existing.can_decide, v_existing.can_view_health, v_existing.grade_bands, v_existing.all_grades)
        is distinct from (p_can_decide, p_can_view_health, v_bands, p_all_grades) then
    update public.staff_admissions_capabilities
    set can_decide = p_can_decide,
        can_view_health = p_can_view_health,
        grade_bands = v_bands,
        all_grades = p_all_grades
    where staff_id = p_staff_id;
  end if;
end;
$$;

-- ------------------------------------------------------------ audit

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action = any (array[
  'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
  'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
  'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
  'admissions_capabilities_changed'
]));

-- Every grant, change and clear, with the holder's role and name at the
-- time. Writes with no signed-in actor (postgres, service_role, a cascade
-- from auth.users) aren't audited, as for the other audit triggers.
create or replace function public.audit_admissions_capabilities()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_staff_id uuid := case when tg_op = 'DELETE' then old.staff_id else new.staff_id end;
  v_branch uuid;
  v_role text;
  v_name text;
begin
  if v_actor is null then return null; end if;
  if tg_op = 'UPDATE'
     and (old.can_decide, old.can_view_health, old.grade_bands, old.all_grades)
         is not distinct from (new.can_decide, new.can_view_health, new.grade_bands, new.all_grades) then
    return null;
  end if;
  select branch_id, role, name into v_branch, v_role, v_name from public.staff where id = v_staff_id;
  -- Gone when the row is removed by the staff row's own deletion (FK
  -- cascade): that deletion is the event, so the cascade isn't audited.
  if v_branch is null then return null; end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'admissions_capabilities_changed',
    'staff_admissions_capabilities', v_staff_id::text,
    case when tg_op <> 'INSERT' then jsonb_build_object(
      'can_decide', old.can_decide, 'can_view_health', old.can_view_health,
      'grade_bands', to_jsonb(old.grade_bands), 'all_grades', old.all_grades,
      'role', v_role, 'name', v_name) end,
    case when tg_op <> 'DELETE' then jsonb_build_object(
      'can_decide', new.can_decide, 'can_view_health', new.can_view_health,
      'grade_bands', to_jsonb(new.grade_bands), 'all_grades', new.all_grades,
      'role', v_role, 'name', v_name) end
  );
  return null;
end;
$$;

create trigger staff_admissions_capabilities_audit
  after insert or update or delete on public.staff_admissions_capabilities
  for each row execute function public.audit_admissions_capabilities();

-- ------------------------------------------------------------ grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. Trigger functions and the
-- helper get no grant at all.
revoke execute on function public.set_admissions_capabilities_identity() from public, anon, authenticated;
revoke execute on function public._admissions_capability_holder_problem(text, boolean, text[], boolean) from public, anon, authenticated;
revoke execute on function public.check_admissions_capability_holder() from public, anon, authenticated;
revoke execute on function public.guard_staff_role_change_admissions() from public, anon, authenticated;
revoke execute on function public.clear_admissions_capabilities_on_deactivate() from public, anon, authenticated;
revoke execute on function public.audit_admissions_capabilities() from public, anon, authenticated;

revoke execute on function public.admissions_grade_band(text) from public, anon;
revoke execute on function public.admissions_grade_visible(text) from public, anon;
revoke execute on function public.has_admissions_capability(text) from public, anon;
revoke execute on function public.set_admissions_capabilities(uuid, boolean, boolean, text[], boolean) from public, anon;
grant execute on function public.admissions_grade_band(text) to authenticated, service_role;
grant execute on function public.admissions_grade_visible(text) to authenticated, service_role;
grant execute on function public.has_admissions_capability(text) to authenticated, service_role;
grant execute on function public.set_admissions_capabilities(uuid, boolean, boolean, text[], boolean) to authenticated, service_role;
