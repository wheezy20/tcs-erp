-- Probes for 20261019110000_audit_log_revoke_truncate (slice 7c): no API
-- role holds TRUNCATE on audit_log, and a truncate as any role fails.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261019110000_audit_log_revoke_truncate.sql

-- probe: T1 anon, authenticated and service_role hold no TRUNCATE on audit_log
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_table_privilege(r, 'public.audit_log', 'truncate') then
      raise exception '% can truncate audit_log', r;
    end if;
  end loop;
end $$;
-- as role:
select 1;

-- probe: T2 truncate audit_log
-- expect: none
truncate public.audit_log;
