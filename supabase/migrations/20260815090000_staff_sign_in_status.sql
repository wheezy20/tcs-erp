-- Backs "Resend invite" in Settings > Staff: a Manager needs to see which
-- staff members have never signed in (a real "invite still pending" state,
-- not something public.staff itself can answer — it has no column that
-- tracks this). auth.users.last_sign_in_at is the ground truth, but that
-- table lives in a schema PostgREST never exposes and RLS can't reach
-- either way, so a SECURITY DEFINER function reading it directly (the
-- function owner has access to auth.* even though the calling role never
-- would) is the only way to surface it at all, the same reasoning that
-- already justifies compute_day_totals() reading expenses on Attendant's
-- behalf.
--
-- Gated to Manager only, matching every other control in this feature
-- (Invite staff, role/active edits) — but by returning an empty result for
-- anyone else rather than raising, since this is a passive, automatic load
-- on every Staff tab render, not a deliberate action a non-Manager took;
-- raising here would just be an unwanted error toast on page load for two
-- of the three roles that can see this tab at all.
create or replace function public.staff_sign_in_status()
returns table (staff_id uuid, last_sign_in_at timestamptz)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if not public.has_role(array['Manager']) then
    return;
  end if;

  return query
    select s.id, u.last_sign_in_at
    from public.staff s
    join auth.users u on u.id = s.id;
end;
$$;

grant execute on function public.staff_sign_in_status() to authenticated;
