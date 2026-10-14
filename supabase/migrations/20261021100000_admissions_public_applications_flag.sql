-- Admissions slice 8b: two independent public intake switches
-- (docs/admissions/PORT-PLAN.md, slice 8b; approved 2026-10-14).
--
-- Naming: slice 8's admissions_settings.public_intake_open and
-- set_admissions_public_intake(boolean) are applied on hosted and keep their
-- names and behaviour. They now mean "public inquiries" only. Renaming them
-- would need a coordinated column rename, function drop and frontend deploy
-- for no change in behaviour, so this migration only adds:
--
--   public_applications_open boolean default false: the switch slice 9's
--     public application submit will check. No form reads it yet.
--   set_admissions_public_applications(boolean): Manager only, the same
--     shape as set_admissions_public_intake.
--
-- The two switches are independent: submit_inquiry checks only
-- public_intake_open, and the future application submit checks only
-- public_applications_open. Each change writes admissions_settings_changed
-- holding only the field that changed. Manager and Auditor read both
-- through the existing select policy; no other role sees them.

alter table public.admissions_settings
  add column public_applications_open boolean not null default false;

comment on column public.admissions_settings.public_intake_open is
  'Public inquiries switch (slice 8). submit_inquiry refuses while false.';
comment on column public.admissions_settings.public_applications_open is
  'Public applications switch (slice 8b). The slice 9 application submit refuses while false.';

-- ------------------------------------------------------------ RPC

create or replace function public.set_admissions_public_applications(p_open boolean)
returns public.admissions_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_row public.admissions_settings;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can open or close public applications';
  end if;
  if p_open is null then
    raise exception 'Choose whether public applications are open or closed';
  end if;
  select * into v_row from public.admissions_settings where id = 1 for update;
  if v_row.public_applications_open = p_open then
    raise exception 'Public applications are already %', case when p_open then 'open' else 'closed' end;
  end if;
  update public.admissions_settings set public_applications_open = p_open where id = 1
  returning * into v_row;
  return v_row;
end;
$$;

-- ------------------------------------------------------------ audit

-- As in slice 8, before and after carry only the fields that changed.
create or replace function public.audit_admissions_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
begin
  if v_actor is null then
    return null;
  end if;
  if old.offer_ttl_days is distinct from new.offer_ttl_days then
    v_before := v_before || jsonb_build_object('offer_ttl_days', old.offer_ttl_days);
    v_after := v_after || jsonb_build_object('offer_ttl_days', new.offer_ttl_days);
  end if;
  if old.public_intake_open is distinct from new.public_intake_open then
    v_before := v_before || jsonb_build_object('public_intake_open', old.public_intake_open);
    v_after := v_after || jsonb_build_object('public_intake_open', new.public_intake_open);
  end if;
  if old.public_applications_open is distinct from new.public_applications_open then
    v_before := v_before || jsonb_build_object('public_applications_open', old.public_applications_open);
    v_after := v_after || jsonb_build_object('public_applications_open', new.public_applications_open);
  end if;
  if v_after = '{}'::jsonb then
    return null;
  end if;
  v_branch := (select branch_id from public.staff where id = v_actor);
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'admissions_settings_changed', 'admissions_settings', new.id::text,
    v_before, v_after
  );
  return null;
end;
$$;

-- ------------------------------------------------------------ grants

revoke execute on function public.set_admissions_public_applications(boolean) from public, anon;
grant execute on function public.set_admissions_public_applications(boolean) to authenticated;
revoke execute on function public.audit_admissions_settings() from public, anon, authenticated;
