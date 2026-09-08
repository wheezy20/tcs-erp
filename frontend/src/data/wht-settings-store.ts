import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";

// Same "third narrow exception to Settings staying local" shape
// notification-settings-store.ts already established — business_settings.
// wht_rate needs a real, database-level source of truth because
// create_invoice() reads it server-side when computing wht_amount for a new
// WHT invoice; a localStorage value could never answer that from inside
// Postgres. Every other Tax & VAT field (including the VAT rate input right
// next to this one in Settings) stays local/display-only, a known,
// documented, pre-existing gap this session doesn't touch.
type State = {
  whtRate: number | null;
  loading: boolean;
  error: string | null;
};

let state: State = { whtRate: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

async function load() {
  const { data, error } = await supabase
    .from("business_settings")
    .select("wht_rate")
    .eq("id", 1)
    .single();
  if (error) throw error;
  setState({ whtRate: Number(data.wht_rate), loading: false, error: null });
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

const SERVER_SNAPSHOT: State = { whtRate: null, loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

export function useWhtRate() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

/** RLS's business_settings_update policy is Manager-only and is the real
 * boundary — the Settings UI just disables the input for anyone else. */
export async function updateWhtRate(rate: number) {
  const { error } = await supabase.from("business_settings").update({ wht_rate: rate }).eq("id", 1);
  if (error) throw error;
  await reload();
}
