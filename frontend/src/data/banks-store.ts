import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// `banks` — a school-editable reference list that drives the bank picker
// when proposing an employee or a bank/account change (20260909140000).
// Same pattern as allowance_types: select for M/Acc/Aud, plain RLS-gated
// writes for M/Acc, not approval-gated. `employee_pay_config.bank` stores
// the bank *name* as text; this list only constrains the dropdown.

export type Bank = {
  id: string;
  name: string;
  position: number;
  isActive: boolean;
};

type BankRow = Database["public"]["Tables"]["banks"]["Row"];

function mapBank(row: BankRow): Bank {
  return { id: row.id, name: row.name, position: row.position, isActive: row.is_active };
}

type State = { banks: Bank[]; loading: boolean; error: string | null };

let state: State = { banks: [], loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function load() {
  const { data, error } = await supabase.from("banks").select("*").order("position").order("name");
  if (error) throw error;
  setState({ banks: (data as BankRow[]).map(mapBank), loading: false, error: null });
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

function getSnapshot() {
  return state;
}

export function useBanks() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

/** Active banks in display order — what a picker should offer. */
export function activeBanks(banks: Bank[]): Bank[] {
  return banks.filter((b) => b.isActive);
}

export async function createBank(name: string): Promise<void> {
  const position = state.banks.length;
  const { error } = await supabase.from("banks").insert({ name: name.trim(), position });
  if (error) throw error;
  await reload();
}

export async function updateBank(
  id: string,
  patch: { name?: string; isActive?: boolean },
): Promise<void> {
  const { error } = await supabase
    .from("banks")
    .update({
      ...(patch.name !== undefined ? { name: patch.name.trim() } : {}),
      ...(patch.isActive !== undefined ? { is_active: patch.isActive } : {}),
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}

export async function deleteBank(id: string): Promise<void> {
  const { error } = await supabase.from("banks").delete().eq("id", id);
  if (error) throw error;
  await reload();
}
