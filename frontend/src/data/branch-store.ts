import { useSyncExternalStore } from "react";

import type { Database } from "@/lib/database.types";
import { supabase } from "@/lib/supabase";

// branches = campuses. TCS has two, Main and Annex (docs/CONSTRAINTS.md,
// Architecture). The oldest row is Main, and every school-wide record
// (payroll, expenses, accounting, POS, inventory) lives on it (D-1b in
// docs/admissions/PORT-PLAN.md). Pick it only through getSchoolBranchId() /
// getSchoolBranchRow() below: an unordered `.limit(1)` returns an arbitrary
// row once a second branch exists. Same rule the database's own pickers use
// (`order by created_at limit 1` in handle_new_staff_signup /
// post_journal_entry).
//
// The hook below exists so display-only spots (page headers, the topbar,
// dialog copy) can show the branch name without each running its own query.

type BranchRow = Database["public"]["Tables"]["branches"]["Row"];

export async function getSchoolBranchRow(): Promise<BranchRow> {
  const { data, error } = await supabase
    .from("branches")
    .select("*")
    .order("created_at", { ascending: true })
    .limit(1)
    .single();
  if (error) throw error;
  return data;
}

export async function getSchoolBranchId(): Promise<string> {
  const { data, error } = await supabase
    .from("branches")
    .select("id")
    .order("created_at", { ascending: true })
    .limit(1)
    .single();
  if (error) throw error;
  return data.id;
}

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
  const branch = await getSchoolBranchRow();
  setState({ id: branch.id, name: branch.name, loading: false, error: null });
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
