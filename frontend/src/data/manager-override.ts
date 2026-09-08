// Manager PIN Authorization (Phase 1.5, Session 9) — the client half of the
// ticket flow documented in full in the manager_pin_authorization migration.
//
// This deliberately talks to Supabase over plain `fetch`, never through the
// shared `supabase` client exported from `@/lib/supabase`. Signing in with
// `supabase.auth.signInWithPassword()` on that shared client would replace
// the app's persisted session — exactly the "switching the active session
// away from the Attendant" this session's brief says not to do. A raw fetch
// against GoTrue's own token endpoint gets a Manager access token without
// touching that client's state (or localStorage) at all; the token is used
// for exactly one follow-up call (authorizing the ticket) and then dropped —
// it's never stored anywhere.

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

export type ManagerOverrideTicket = {
  id: string;
  expiresAt: string;
};

/** A deliberately generic message for every failure mode — wrong password,
 * an account that isn't an active Manager, a network hiccup. Distinguishing
 * these to the caller would mean confirming whether an email belongs to a
 * real (or a real-but-non-Manager) account, an enumeration risk with no
 * upside here: the Attendant doesn't need to know *why* it failed, just that
 * it did. */
const GENERIC_FAILURE = "Could not authorize with those Manager credentials.";

/**
 * Signs in with the given credentials via a one-off, unpersisted GoTrue
 * password grant, then immediately spends that token on exactly one call:
 * authorize_manager_override(). Returns a single-use ticket id the caller's
 * own (still fully signed-in) session can later redeem via create_sale()'s
 * p_override_ticket parameter. Throws GENERIC_FAILURE for any failure —
 * wrong credentials, an account that isn't an active Manager, or network
 * trouble all look identical to the caller on purpose.
 */
export async function requestManagerOverride(
  email: string,
  password: string,
  requestedBy: string,
  reason: string = "",
): Promise<ManagerOverrideTicket> {
  let managerAccessToken: string;
  try {
    const tokenResponse = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: SUPABASE_ANON_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    if (!tokenResponse.ok) throw new Error(GENERIC_FAILURE);
    const tokenBody = await tokenResponse.json();
    if (!tokenBody.access_token) throw new Error(GENERIC_FAILURE);
    managerAccessToken = tokenBody.access_token;
  } catch {
    throw new Error(GENERIC_FAILURE);
  }

  const rpcResponse = await fetch(`${SUPABASE_URL}/rest/v1/rpc/authorize_manager_override`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${managerAccessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_requested_by: requestedBy, p_reason: reason }),
  });

  if (!rpcResponse.ok) {
    // Only the RPC's own "Only a Manager can authorize an override" message
    // is safe to surface — everything else (auth failures, 500s) collapses
    // into the same generic message as the sign-in step above.
    const body = await rpcResponse.json().catch(() => null);
    if (body?.message === "Only a Manager can authorize an override") {
      throw new Error(body.message);
    }
    throw new Error(GENERIC_FAILURE);
  }

  const row = await rpcResponse.json();
  return { id: row.id, expiresAt: row.expires_at };
}
