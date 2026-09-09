import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// `payment_providers` — a school-editable reference list that drives the
// bank / mobile-money picker when proposing an employee or a pay-config
// change (20260909140000 as `banks`, renamed + `kind` added in
// 20260909150000). Same pattern as allowance_types: select for M/Acc/Aud,
// plain RLS-gated writes for M/Acc, not approval-gated.
// `employee_pay_config.bank` stores the provider *name* as text (the bank
// or the network); `employee_pay_config.account_no` the account or wallet
// number. This list only constrains the dropdown.

export type PaymentKind = "Bank" | "Mobile Money";

export type PaymentProvider = {
  id: string;
  name: string;
  kind: PaymentKind;
  position: number;
  isActive: boolean;
};

type ProviderRow = Database["public"]["Tables"]["payment_providers"]["Row"];

function mapProvider(row: ProviderRow): PaymentProvider {
  return {
    id: row.id,
    name: row.name,
    kind: row.kind as PaymentKind,
    position: row.position,
    isActive: row.is_active,
  };
}

type State = { providers: PaymentProvider[]; loading: boolean; error: string | null };

let state: State = { providers: [], loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function load() {
  const { data, error } = await supabase
    .from("payment_providers")
    .select("*")
    .order("position")
    .order("name");
  if (error) throw error;
  setState({ providers: (data as ProviderRow[]).map(mapProvider), loading: false, error: null });
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

export function usePaymentProviders() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

/** Active providers in display order, optionally filtered to one kind —
 * what a picker should offer. */
export function activeProviders(
  providers: PaymentProvider[],
  kind?: PaymentKind,
): PaymentProvider[] {
  return providers.filter((p) => p.isActive && (kind === undefined || p.kind === kind));
}

export async function createProvider(name: string, kind: PaymentKind): Promise<void> {
  const position = state.providers.length + (kind === "Mobile Money" ? 100 : 0);
  const { error } = await supabase
    .from("payment_providers")
    .insert({ name: name.trim(), kind, position });
  if (error) throw error;
  await reload();
}

export async function updateProvider(
  id: string,
  patch: { name?: string; isActive?: boolean },
): Promise<void> {
  const { error } = await supabase
    .from("payment_providers")
    .update({
      ...(patch.name !== undefined ? { name: patch.name.trim() } : {}),
      ...(patch.isActive !== undefined ? { is_active: patch.isActive } : {}),
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}

export async function deleteProvider(id: string): Promise<void> {
  const { error } = await supabase.from("payment_providers").delete().eq("id", id);
  if (error) throw error;
  await reload();
}
