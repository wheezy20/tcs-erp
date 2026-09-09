import { useSyncExternalStore } from "react";
import type { Session } from "@supabase/supabase-js";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type StaffRole = "Attendant" | "Manager" | "Accountant" | "Auditor";

/** Roles that can *view* the finance-adjacent sections (Payroll, Accounting,
 * Expenses, Reports, Banking, Purchasing, the ledger-derived dashboard KPIs)
 * — everywhere the old combined "Accountant/Auditor" role had read access.
 * The DB mirror is each table's `_select` RLS policy. */
export function canViewFinancials(role: StaffRole | undefined | null): boolean {
  return role === "Manager" || role === "Accountant" || role === "Auditor";
}

/** Roles that can *write* the finance modules (Payroll, Accounting, Expenses)
 * — the same set the DB's require_finance_writer() enforces. Auditor cannot;
 * Accountant has Manager-equivalent write access on those specific tables. */
export function canWriteFinancials(role: StaffRole | undefined | null): boolean {
  return role === "Manager" || role === "Accountant";
}

export type Staff = {
  id: string;
  name: string;
  email: string;
  role: StaffRole;
  active: boolean;
  /** Set once, only ever by scripts/bootstrap-production-manager.sh. Once
   * true, staff_protect_row() (Session 20) makes role/active/protected
   * itself unconditionally unchangeable and the row undeletable — no RPC or
   * UI path can lift this, by design. */
  protected: boolean;
  /** Contact / org-placement fields — editable on Staff Overview by a
   * Manager (20260909100000). `position` / `department` used to live on
   * `staff_pay_config`; they moved here as current-state identity, not pay
   * history (see docs/DESIGN.md). Bank details stay on `staff_pay_config`. */
  phone: string | null;
  position: string | null;
  department: string | null;
};

type StaffRow = Database["public"]["Tables"]["staff"]["Row"];

function mapStaffRow(row: StaffRow): Staff {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    role: row.role as StaffRole,
    active: row.active,
    protected: row.protected,
    phone: row.phone,
    position: row.position,
    department: row.department,
  };
}

type AuthState = {
  session: Session | null;
  staff: Staff | null;
  /** True until the very first session check resolves. */
  loading: boolean;
  error: string | null;
};

let state: AuthState = { session: null, staff: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: AuthState) {
  state = next;
  listeners.forEach((l) => l());
}

/** Looks up the staff row for a session's user and updates state. A session
 * with no matching (or inactive) staff row is treated as signed-out from the
 * app's point of view — RLS would reject every request anyway (is_active_staff()
 * requires both), so there's nothing useful this session could do. */
async function resolveSession(session: Session | null) {
  if (!session) {
    setState({ session: null, staff: null, loading: false, error: null });
    return;
  }

  const { data, error } = await supabase
    .from("staff")
    .select("*")
    .eq("id", session.user.id)
    .maybeSingle();

  if (error) {
    setState({ session, staff: null, loading: false, error: error.message });
    return;
  }

  setState({
    session,
    staff: data && data.active ? mapStaffRow(data) : null,
    loading: false,
    error: null,
  });
}

let initialized = false;

function ensureInitialized() {
  if (initialized) return;
  initialized = true;

  supabase.auth.getSession().then(({ data }) => resolveSession(data.session));
  supabase.auth.onAuthStateChange((_event, session) => {
    resolveSession(session);
  });
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureInitialized();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

// A fixed placeholder, not the live `state` — supabase.auth.getSession()
// never resolves during SSR (it reads from browser localStorage), so this
// just has to be a stable value matching what the client's own first paint
// (before hydration's effects run) also sees. Same pattern as
// useCurrentBranch() in branch-store.ts, for the same reason.
const SERVER_SNAPSHOT: AuthState = { session: null, staff: null, loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

export function useAuth() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

export async function signIn(email: string, password: string): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
}

/** Used once, by routes/accept-invite.tsx — an invited user already has a
 * valid session (established from the invite link's own URL fragment) but
 * no password yet, since nothing has ever set one for them. */
export async function setPassword(password: string): Promise<void> {
  const { error } = await supabase.auth.updateUser({ password });
  if (error) throw error;
}

/** Public, unauthenticated action from /login's "Forgot password?" link.
 * resetPasswordForEmail() always resolves successfully regardless of
 * whether the email is actually registered — GoTrue's own design, so the
 * caller can't use a thrown/not-thrown error to enumerate accounts; any
 * error that does surface here is a real operational one (rate limit,
 * network failure), not an "this account doesn't exist" leak.
 *
 * redirectTo reuses the exact same /accept-invite flow the invite/resend
 * paths already use — a recovery-type link, same mechanism
 * resendInvite()'s own generateLink({ type: "recovery" }) relies on, just
 * self-triggered instead of sent by a Manager. window.location.origin
 * (not a hardcoded domain) is what actually reaches the browser's real
 * origin in every environment this runs in — local dev, a preview
 * deployment, production — and GoTrue only ever honors a redirect_to that
 * matches its own site_url/additional_redirect_urls allow-list regardless
 * of what's passed, the same reasoning invite-staff's own redirectTo
 * already relies on. */
export async function requestPasswordReset(email: string): Promise<void> {
  const redirectTo =
    typeof window !== "undefined" ? `${window.location.origin}/accept-invite` : undefined;
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  if (error) throw error;
}

export async function signOut(): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}
