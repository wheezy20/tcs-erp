-- Admissions slice 8: the public intake switch
-- (docs/admissions/PORT-PLAN.md, slice 8; decisions recorded 2026-10-13).
--
-- admissions_settings.public_intake_open is the technical enforcement of no
-- dual intake: every public submit RPC (submit_inquiry here, slice 9's
-- submit_application later) refuses while it is false. It starts false, so
-- nothing public is accepted until a Manager opens intake on purpose.
--
-- set_admissions_public_intake(boolean) is Manager only, like the offer
-- expiry RPC. The change is audited as admissions_settings_changed (already
-- in the audit CHECK since 6b), so the audit action list is unchanged.
-- Manager and Auditor read the flag through the existing select policy.

alter table public.admissions_settings
  add column public_intake_open boolean not null default false;

-- ------------------------------------------------------------ RPC

create or replace function public.set_admissions_public_intake(p_open boolean)
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
    raise exception 'Only a Manager can open or close public intake';
  end if;
  if p_open is null then
    raise exception 'Choose whether public intake is open or closed';
  end if;
  select * into v_row from public.admissions_settings where id = 1 for update;
  if v_row.public_intake_open = p_open then
    raise exception 'Public intake is already %', case when p_open then 'open' else 'closed' end;
  end if;
  update public.admissions_settings set public_intake_open = p_open where id = 1
  returning * into v_row;
  return v_row;
end;
$$;

-- ------------------------------------------------------------ audit

-- admissions_settings_changed, only for a signed-in actor. before and after
-- carry only the fields that changed, so an offer expiry change writes the
-- same row as it did in 6b.
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

revoke execute on function public.set_admissions_public_intake(boolean) from public, anon;
grant execute on function public.set_admissions_public_intake(boolean) to authenticated;
revoke execute on function public.audit_admissions_settings() from public, anon, authenticated;
