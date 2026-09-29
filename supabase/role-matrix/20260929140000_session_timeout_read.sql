-- Role matrix for 20260929140000_session_timeout_read (slice 1c).
-- get_session_timeout_minutes() returns business_settings.session_timeout_minutes
-- to every active staff role, including the Admissions Officer, and nothing
-- else: the officer still can't read business_settings directly.
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20260929140000_session_timeout_read.sql

-- probe: get_session_timeout_minutes() returns the configured value
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.business_settings set session_timeout_minutes = 37 where id = 1;
-- as role:
do $$ begin
  if public.get_session_timeout_minutes() is distinct from 37 then
    raise exception 'got %', public.get_session_timeout_minutes();
  end if;
end $$;

-- probe: get_session_timeout_minutes(), every staff row inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
select public.get_session_timeout_minutes();

-- probe: direct business_settings read (unchanged)
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin
  if not exists (select 1 from public.business_settings) then raise exception 'no rows visible'; end if;
end $$;

-- probe: direct business_settings update (unchanged)
-- expect: Manager
do $$ declare n int; begin
  update public.business_settings set session_timeout_minutes = session_timeout_minutes where id = 1;
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;
