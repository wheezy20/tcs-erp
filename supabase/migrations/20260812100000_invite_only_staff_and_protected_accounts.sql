-- Invite-Only Staff Onboarding & Protected Admin Account (Session 20).
--
-- business-app-spec.md's Phase 1.5 Manager PIN session already established
-- staff logins; this session closes the last open door: public self-signup.
-- Three things, in dependency order — (1) a `protected` flag + a trigger
-- that makes a protected staff row structurally untouchable, (2) flipping
-- `handle_new_staff_signup()`'s trust model now that signup is invite-only,
-- (3) nothing else schema-side — the Edge Function and the bootstrap script
-- are both plain callers of the Admin API, not new database objects.
--
-- ================================================================ part 1:
-- protected accounts — a trigger, not just an RLS/RPC check
--
-- Why a trigger and not just tightening staff_update/staff_delete's RLS
-- (e.g. `using (has_role(['Manager']) and not protected)`): RLS is scoped
-- to roles that go through PostgREST as `authenticated`, but `service_role`
-- bypasses RLS entirely by role attribute — and, checked directly rather
-- than assumed, `service_role` already holds a real, unconditional
-- `delete`/`update` grant on `staff` from the broad
-- `service_role_grants` migration (`grant ... on all tables in schema
-- public to service_role`). RLS alone could never stop a service_role-
-- authenticated call (a bootstrapping script gone wrong, a future admin
-- tool) from demoting or deleting a protected row; only a trigger fires
-- unconditionally for every role, matching the "regardless of who's making
-- the request" requirement literally. This is the same reasoning audit_log
-- (Session 8) already established for its own protection, just landing on
-- a trigger instead of a withheld grant, because staff's protection has to
-- coexist with staff still being ordinarily writable for every non-
-- protected row — a table that must stay writable most of the time can't
-- use "withhold the grant" the way an append-only log can.
--
-- Checked directly, not assumed: `authenticated` currently has no `insert`
-- or `delete` grant on `staff` at all (only `select, update`, from the
-- original auth_roles_schema migration) — so a real signed-in Manager's own
-- delete attempt already fails at the grant layer today, before RLS's
-- staff_delete policy (added later, in role_permissions_rewrite.sql) is
-- even reached. That's a real, pre-existing gap between the RLS policy and
-- the grant it depends on, left exactly as found — not this session's job
-- to fix — but it does mean this trigger's practical bite today is mostly
-- against `service_role`, which is precisely the caller RLS could never
-- have covered anyway.
alter table public.staff add column protected boolean not null default false;

-- Sticky in both directions checked here: role/active can't change on a
-- protected row, and `protected` itself can't be cleared once true — without
-- that second check, a two-statement bypass (unset protected, then change
-- role in a second call) would defeat the whole guarantee. Flipping
-- protected FALSE -> TRUE is deliberately still allowed (an INSERT can set
-- it directly, and this trigger only fires on UPDATE/DELETE) — the
-- bootstrap script below relies on exactly that to mark its own account
-- protected in a follow-up statement after the invite-driven insert lands.
create or replace function public.protect_staff_row()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    if old.protected then
      raise exception 'This is a protected staff account and cannot be deleted';
    end if;
    return old;
  end if;

  if old.protected and (
    new.role is distinct from old.role
    or new.active is distinct from old.active
    or new.protected is distinct from old.protected
  ) then
    raise exception 'This is a protected staff account: role, active status, and protected status cannot be changed';
  end if;
  return new;
end;
$$;

create trigger staff_protect_row
before update or delete on public.staff
for each row execute function public.protect_staff_row();

-- ================================================================ part 2:
-- handle_new_staff_signup() — the trust model flips now that signup is
-- invite-only
--
-- The original comment on this function (auth_roles_schema.sql) explains
-- exactly why it never trusted client-supplied metadata: "raw_user_meta_data
-- is caller-controlled input (anyone signing up could put anything in it),
-- so trusting a self-reported 'role': 'Manager' would be a privilege-
-- escalation hole." That threat model assumed a public /signup form any
-- anonymous visitor could post to — which this session removes (see
-- config.toml's enable_signup = false and the removed /login signup tab).
-- Once self-signup is gone, the ONLY way an auth.users row (and therefore
-- this trigger) ever fires at all is:
--   1. supabase.auth.admin.inviteUserByEmail(), called from
--      supabase/functions/invite-staff/ — itself gated on the caller
--      already being an active Manager, checked inside the function before
--      it ever touches the Admin API;
--   2. the same Admin API call, made directly by scripts/
--      bootstrap-production-manager.sh, run by hand with real project
--      credentials the operator alone controls.
-- Both are already-trusted, already-authorized origins for a role decision
-- by the time raw_user_meta_data reaches this trigger — so reading role
-- from it is no longer the hole it used to be, it's the whole point: the
-- Manager (or the bootstrap operator) decides the role at invite time, and
-- this trigger is what actually carries that decision onto the new staff
-- row. Falls back to Attendant for anything missing or invalid, same
-- fail-safe direction as before (never fail open into Manager).
--
-- The old "first signup ever becomes Manager" bootstrapping special case is
-- removed along with this: it existed only to solve "how does the very
-- first Manager get created when nobody exists yet to promote them," which
-- scripts/bootstrap-production-manager.sh now owns explicitly and
-- deliberately (role: 'Manager' in its own invite call), not implicitly via
-- "you happened to be first."
create or replace function public.handle_new_staff_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_role text := coalesce(new.raw_user_meta_data ->> 'role', 'Attendant');
begin
  if v_role not in ('Attendant', 'Manager', 'Accountant/Auditor') then
    v_role := 'Attendant';
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
$$;
