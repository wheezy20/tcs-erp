import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";

// `positions` and `departments` — school-editable reference lists that
// drive the position / department dropdowns on the employee flow
// (20260909160000). Same shape and RLS as `payment_providers`: select for
// M/Acc/Aud, plain RLS-gated writes for M/Acc, not approval-gated. Values
// are stored UPPERCASE by a DB trigger; `employees.position` /
// `.department` stay plain text (the list constrains the picker, no FK).
//
// `qualifications` (20260923) is the same shape, minus the uppercase
// trigger (these read as proper names/certifications, not short codes) —
// `employees.qualifications` / `employee_onboarding_submissions.qualifications`
// are `text[]`, since unlike position/department this is a multi-select.
// Also readable by `anon` (the public onboarding form needs the active
// list to offer) — the only one of these three with an anon grant, since
// it's the only one anon's own picker needs.

export type RefListItem = {
  id: string;
  name: string;
  position: number;
  isActive: boolean;
};

type Row = { id: string; name: string; position: number; is_active: boolean };

function mapRow(row: Row): RefListItem {
  return { id: row.id, name: row.name, position: row.position, isActive: row.is_active };
}

type State = { items: RefListItem[]; loading: boolean; error: string | null };

/** Build a tiny external store for one reference table. */
function makeRefListStore(table: "positions" | "departments" | "qualifications") {
  let state: State = { items: [], loading: true, error: null };
  const listeners = new Set<() => void>();

  function setState(next: State) {
    state = next;
    listeners.forEach((l) => l());
  }

  let loadPromise: Promise<void> | null = null;

  async function load() {
    const { data, error } = await supabase.from(table).select("*").order("position").order("name");
    if (error) throw error;
    setState({ items: (data as Row[]).map(mapRow), loading: false, error: null });
  }

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

  function useList() {
    return useSyncExternalStore(
      subscribe,
      () => state,
      () => state,
    );
  }

  async function create(name: string): Promise<void> {
    const position = state.items.length;
    const { error } = await supabase.from(table).insert({ name: name.trim(), position });
    if (error) throw error;
    await reload();
  }

  async function update(id: string, patch: { name?: string; isActive?: boolean }): Promise<void> {
    const { error } = await supabase
      .from(table)
      .update({
        ...(patch.name !== undefined ? { name: patch.name.trim() } : {}),
        ...(patch.isActive !== undefined ? { is_active: patch.isActive } : {}),
      })
      .eq("id", id);
    if (error) throw error;
    await reload();
  }

  async function remove(id: string): Promise<void> {
    const { error } = await supabase.from(table).delete().eq("id", id);
    if (error) throw error;
    await reload();
  }

  return { useList, create, update, remove };
}

const positionsStore = makeRefListStore("positions");
const departmentsStore = makeRefListStore("departments");
const qualificationsStore = makeRefListStore("qualifications");

export const usePositions = positionsStore.useList;
export const createPosition = positionsStore.create;
export const updatePosition = positionsStore.update;
export const deletePosition = positionsStore.remove;

export const useDepartments = departmentsStore.useList;
export const createDepartment = departmentsStore.create;
export const updateDepartment = departmentsStore.update;
export const deleteDepartment = departmentsStore.remove;

export const useQualifications = qualificationsStore.useList;
export const createQualification = qualificationsStore.create;
export const updateQualification = qualificationsStore.update;
export const deleteQualification = qualificationsStore.remove;

/** Active names in display order — what a picker should offer. */
export function activeNames(items: RefListItem[]): string[] {
  return items.filter((i) => i.isActive).map((i) => i.name);
}
