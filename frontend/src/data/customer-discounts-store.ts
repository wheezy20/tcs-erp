import { useSyncExternalStore } from "react";

import type { DiscountMode } from "@/data/pos";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type CustomerDiscount = {
  id: string;
  customerId: string;
  label: string;
  mode: DiscountMode;
  value: number;
  active: boolean;
  createdBy: string;
  createdAt: string;
};

type CustomerDiscountRow = Database["public"]["Tables"]["customer_discounts"]["Row"];
type CustomerDiscountRowWithStaff = CustomerDiscountRow & { staff: { name: string } | null };

function mapCustomerDiscountRow(row: CustomerDiscountRowWithStaff): CustomerDiscount {
  return {
    id: row.id,
    customerId: row.customer_id,
    label: row.label,
    mode: row.mode as DiscountMode,
    value: Number(row.value),
    active: row.active,
    createdBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
  };
}

type CustomerDiscountState = {
  discounts: CustomerDiscount[];
  loading: boolean;
  error: string | null;
};

let state: CustomerDiscountState = { discounts: [], loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: CustomerDiscountState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadCustomerDiscounts() {
  const { data, error } = await supabase
    .from("customer_discounts")
    .select("*, staff(name)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  setState({
    discounts: (data as CustomerDiscountRowWithStaff[]).map(mapCustomerDiscountRow),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadCustomerDiscounts().catch((err) => {
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

/** Every customer discount, every branch (there's only one branch right
 * now). Loaded broadly like every other small reference table in this app
 * (useStaff(), expense_categories) — consumers filter by customerId
 * themselves, e.g. POS picking the active ones for the sale's customer. */
export function useCustomerDiscounts() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewCustomerDiscount = {
  customerId: string;
  label: string;
  mode: DiscountMode;
  value: number;
};

/** Manager-only, enforced server-side by create_customer_discount() — same
 * create-can't-overwrite discipline as every other table in this build: no
 * client-supplied id, a plain insert (never an upsert). */
export async function createCustomerDiscount(
  input: NewCustomerDiscount,
): Promise<CustomerDiscount> {
  const { data, error } = await supabase.rpc("create_customer_discount", {
    p_customer_id: input.customerId,
    p_label: input.label,
    p_mode: input.mode,
    p_value: input.value,
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Discount was created but no id was returned.");

  await reload();
  const created = state.discounts.find((d) => d.id === row.id);
  if (!created) throw new Error("Discount was created but could not be found after reloading.");
  return created;
}

/** A plain state-replace (active=false), not a creation — goes through
 * ordinary RLS-gated update rather than its own RPC, same reasoning as
 * setStaffActive()/setExpenseCategories(). Manager-only per customer_discounts'
 * RLS update policy. */
export async function setCustomerDiscountActive(id: string, active: boolean): Promise<void> {
  const { error } = await supabase.from("customer_discounts").update({ active }).eq("id", id);
  if (error) throw error;
  await reload();
}

export function activeDiscountsForCustomer(customerId: string | null): CustomerDiscount[] {
  if (!customerId) return [];
  return state.discounts.filter((d) => d.customerId === customerId && d.active);
}
