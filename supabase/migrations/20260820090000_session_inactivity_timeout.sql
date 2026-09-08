-- Inactivity timeout: sign a user out completely (a real supabase.auth
-- session end, not a client-side lock screen) after a period with no
-- interaction, requiring their normal password to sign back in via the
-- existing /login flow.
--
-- The duration itself is a Manager-editable setting, not hardcoded — the
-- same shape as vat_rate/wht_rate: a value business_settings holds because
-- it needs to be a single, trustworthy, shared source every signed-in
-- client reads, not because anything server-side enforces it. There's no
-- RPC/trigger reading this column the way create_invoice() reads vat_rate
-- — the enforcement is entirely client-side (frontend/src/hooks/
-- use-inactivity-logout.ts calls supabase.auth.signOut() once the browser
-- itself has seen no mouse/keyboard/touch/scroll activity for this many
-- minutes) — but it still belongs here rather than in localStorage
-- (settings-store.ts) for the same reason the three notification toggles
-- do: every active staff member's browser needs to read the *same* value a
-- Manager set, not whatever was last saved in that one browser's own
-- localStorage.
--
-- business_settings_select (any active staff) and business_settings_update
-- (Manager only, both USING and WITH CHECK) already exist and already cover
-- this column — no new policy needed, matching every other business_settings
-- column added since Session 7.
alter table public.business_settings
  add column session_timeout_minutes integer not null default 15
    check (session_timeout_minutes > 0 and session_timeout_minutes <= 480);
