import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import type { Staff, StaffRole } from "@/data/auth-store";

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

type StaffState = {
  staff: Staff[];
  /** staff.id for anyone whose auth.users.last_sign_in_at is still null —
   * an invite genuinely still pending, not yet accepted. Only ever
   * populated for a Manager viewer; staff_sign_in_status() returns nothing
   * for anyone else, so this is just an empty set for them, not an error. */
  pendingIds: Set<string>;
  loading: boolean;
  error: string | null;
};

let state: StaffState = { staff: [], pendingIds: new Set(), loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: StaffState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadStaff() {
  const [staffResult, statusResult] = await Promise.all([
    supabase.from("staff").select("*").order("name"),
    supabase.rpc("staff_sign_in_status"),
  ]);
  if (staffResult.error) throw staffResult.error;
  if (statusResult.error) throw statusResult.error;

  const pendingIds = new Set(
    (statusResult.data ?? [])
      .filter((row) => row.last_sign_in_at === null)
      .map((row) => row.staff_id),
  );

  setState({
    staff: staffResult.data.map(mapStaffRow),
    pendingIds,
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadStaff().catch((err) => {
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    });
  }
  return loadPromise;
}

async function reload() {
  loadPromise = null;
  await ensureLoaded();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

/** The full roster, every role. RLS's staff_select policy already scopes
 * this to "any active staff member can see it" — there's no separate
 * Manager-only read restriction, since the app needs to show names for
 * "Recorded by"/"Issued by"/etc. everywhere, not just in Settings. */
export function useStaff() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

/** Only a Manager can actually do this — RLS's staff_update policy is what
 * actually enforces it (has_role(['Manager'])), this just calls it; the
 * Settings UI hides the controls from anyone else so the request is never
 * even attempted. */
export async function setStaffRole(id: string, role: StaffRole): Promise<void> {
  const { error } = await supabase.from("staff").update({ role }).eq("id", id);
  if (error) throw error;
  await reload();
}

export async function setStaffActive(id: string, active: boolean): Promise<void> {
  const { error } = await supabase.from("staff").update({ active }).eq("id", id);
  if (error) throw error;
  await reload();
}

/** Contact / org-placement fields edited on the Staff Overview profile
 * screen. Manager-only, enforced by the same `staff_update` RLS policy
 * (`has_role(['Manager'])`) that gates role/active — this just calls the
 * update; the profile screen hides the form for anyone else. Empty strings
 * are normalised to null so "cleared" reads back as "not set". Bank details
 * are deliberately NOT here — they live on staff_pay_config (Pay Config
 * screen), tied to pay history. */
export async function updateStaffProfile(
  id: string,
  patch: { phone?: string; position?: string; department?: string },
): Promise<void> {
  const clean = (v: string | undefined) => (v === undefined ? undefined : v.trim() || null);
  const { error } = await supabase
    .from("staff")
    .update({
      ...(patch.phone !== undefined ? { phone: clean(patch.phone) } : {}),
      ...(patch.position !== undefined ? { position: clean(patch.position) } : {}),
      ...(patch.department !== undefined ? { department: clean(patch.department) } : {}),
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}

function inviteRedirectTo() {
  return typeof window !== "undefined" ? `${window.location.origin}/accept-invite` : undefined;
}

// supabase-js's own FunctionsHttpError.message is a generic "Edge Function
// returned a non-2xx status code" — the real message (e.g. "Only a Manager
// can invite staff") is in the raw response body, which the SDK leaves for
// the caller to parse itself. Shared by inviteStaff()/resendInvite() since
// both call the same invite-staff function and hit the same gap.
async function throwInviteFunctionError(error: unknown): Promise<never> {
  if (
    error &&
    typeof error === "object" &&
    "context" in error &&
    error.context instanceof Response
  ) {
    const body = await error.context
      .clone()
      .json()
      .catch(() => null);
    throw new Error(body?.error || (error instanceof Error ? error.message : String(error)));
  }
  throw error;
}

/** Invites a new staff member (see supabase/functions/invite-staff/) — a
 * real invite email through Supabase Auth, plus the linked staff row
 * created immediately (by handle_new_staff_signup(), reading the role
 * passed here out of the invite's own metadata), ahead of the invited
 * person ever completing signup. The Edge Function independently re-checks
 * the caller is an active Manager server-side; this call being reachable
 * at all doesn't mean it will succeed. */
export async function inviteStaff(email: string, name: string, role: StaffRole): Promise<void> {
  const { error } = await supabase.functions.invoke("invite-staff", {
    body: { action: "invite", email, name, role, redirectTo: inviteRedirectTo() },
  });
  if (error) await throwInviteFunctionError(error);
  await reload();
}

/** Resends an invite to someone who's never signed in yet — same Edge
 * Function, "resend" action. Deliberately does NOT call
 * admin.inviteUserByEmail() again (fails with "already registered" for
 * anyone previously invited, confirmed directly); the function instead
 * generates a fresh recovery link and emails it itself. Nothing about the
 * staff roster changes as a result (their pending status is unaffected
 * until they actually sign in), so this doesn't reload() — there's nothing
 * cached here for it to refresh. */
export async function resendInvite(staffId: string): Promise<void> {
  const { error } = await supabase.functions.invoke("invite-staff", {
    body: { action: "resend", staffId, redirectTo: inviteRedirectTo() },
  });
  if (error) await throwInviteFunctionError(error);
}
