import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";

// Same "narrow exception to Settings staying local" shape vat_rate/wht_rate/
// the notification toggles already established — business_settings.
// session_timeout_minutes needs a real, shared, database-level source
// because every active staff member's own browser has to read the *same*
// value a Manager set (frontend/src/hooks/use-inactivity-logout.ts), not
// whatever was last saved in that one browser's own localStorage.
type State = {
  sessionTimeoutMinutes: number | null;
  loading: boolean;
  error: string | null;
};

let state: State = { sessionTimeoutMinutes: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

async function load() {
  const { data, error } = await supabase
    .from("business_settings")
    .select("session_timeout_minutes")
    .eq("id", 1)
    .single();
  if (error) throw error;
  setState({
    sessionTimeoutMinutes: Number(data.session_timeout_minutes),
    loading: false,
    error: null,
  });
}

let loadPromise: Promise<void> | null = null;

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = load().catch((err) => {
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

const SERVER_SNAPSHOT: State = { sessionTimeoutMinutes: null, loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

export function useSessionTimeoutMinutes() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

/** RLS's business_settings_update policy is Manager-only and is the real
 * boundary — the Settings UI just disables the input for anyone else. */
export async function updateSessionTimeoutMinutes(minutes: number) {
  const { error } = await supabase
    .from("business_settings")
    .update({ session_timeout_minutes: minutes })
    .eq("id", 1);
  if (error) throw error;
  await reload();
}
