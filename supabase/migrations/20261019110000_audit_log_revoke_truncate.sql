-- Slice 7c, second migration: no API role can truncate audit_log.
--
-- anon, authenticated and service_role held TRUNCATE on audit_log through
-- Supabase's default privileges. RLS doesn't cover TRUNCATE, so any of
-- those roles on a direct SQL connection could empty the log. PostgREST has
-- no truncate verb, so the API never reached it.
--
-- Checked before revoking: no seed, probe, script, golden case or Edge
-- Function truncates audit_log. db reset runs as postgres, the owner,
-- which this doesn't touch.
--
-- Other public tables still hold the same default TRUNCATE; they are left
-- for a separate decision (docs/JOURNAL.md, 7c entry).

revoke truncate on public.audit_log from anon, authenticated, service_role;
