-- Slice 1c: every staff role can read the inactivity timeout
-- (docs/admissions/PORT-PLAN.md, open item from slice 1b-ii).
--
-- The idle timer read business_settings.session_timeout_minutes directly.
-- The Admissions Officer can't read business_settings (can_read_store(),
-- 20260929110000), so its timer never armed and it was never signed out for
-- inactivity. This returns that one value, and nothing else from
-- business_settings, to any active staff member, current or future role.
-- The Settings screen's write path is unchanged (business_settings_update,
-- Manager only).

create or replace function public.get_session_timeout_minutes()
returns integer
language plpgsql
stable security definer
set search_path = public
as $$
begin
  perform public.require_staff();
  return (select session_timeout_minutes from public.business_settings where id = 1);
end;
$$;

revoke execute on function public.get_session_timeout_minutes() from public, anon;
grant execute on function public.get_session_timeout_minutes() to authenticated, service_role;
