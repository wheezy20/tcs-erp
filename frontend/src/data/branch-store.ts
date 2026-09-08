import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";

// Every other store fetches its own branch_id for writes (see getBranchId()
// in inventory-store.ts, invoice-store.ts, etc.) — this one exists purely so
// display-only spots (page headers, the topbar, dialog copy) can show the
// real branch name instead of a hardcoded string, without each needing its
// own Supabase query. Still single-branch, still no switcher: the only thing
// this changes is that the name traces back to the `branches` row instead of
// going stale if that row is ever renamed.

type BranchState = {
  id: string | null;
  name: string | null;
  loading: boolean;
  error: string | null;
};

let state: BranchState = { id: null, name: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: BranchState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadBranch() {
  const { data, error } = await supabase.from("branches").select("id, name").limit(1).single();
  if (error) throw error;
  setState({ id: data.id, name: data.name, loading: false, error: null });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadBranch().catch((err) => {
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

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

// A fixed placeholder, not the live `state` — the fetch never runs
// server-side (subscribe() only fires on the client), so this just has to be
// a stable value that matches what the client's own first paint (before
// hydration's effects run) also sees, or React logs a hydration mismatch.
const SERVER_SNAPSHOT: BranchState = { id: null, name: null, loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

/** The single seeded branch's live id/name from Supabase. `name` is null
 * only while the initial fetch is in flight — every consumer should fall
 * back to something sensible (an empty string, "…") for that brief window. */
export function useCurrentBranch() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
