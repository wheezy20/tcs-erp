import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type Supplier = {
  id: string;
  name: string;
  contactName: string;
  phone: string;
  email: string;
  address: string;
  /** What we owe them (Accounts Payable direction) — the opposite meaning
   * of customers.balance, trigger-maintained from purchase_orders, never
   * conflated with anything on the customers side of the business. */
  balance: number;
  lifetimeTotal: number;
  active: boolean;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
};

type SupplierRow = Database["public"]["Tables"]["suppliers"]["Row"] & {
  staff: { name: string } | null;
};

function mapSupplierRow(row: SupplierRow): Supplier {
  return {
    id: row.id,
    name: row.name,
    contactName: row.contact_name,
    phone: row.phone,
    email: row.email,
    address: row.address,
    balance: Number(row.balance),
    lifetimeTotal: Number(row.lifetime_total),
    active: row.is_active,
    createdBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

type SuppliersState = {
  suppliers: Supplier[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};

let state: SuppliersState = { suppliers: [], branchId: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: SuppliersState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadSuppliers() {
  const [branchResult, suppliersResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase.from("suppliers").select("*, staff(name)").order("name"),
  ]);
  if (branchResult.error) throw branchResult.error;
  if (suppliersResult.error) throw suppliersResult.error;
  setState({
    suppliers: (suppliersResult.data as SupplierRow[]).map(mapSupplierRow),
    branchId: branchResult.data.id,
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadSuppliers().catch((err) => {
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

/** Every supplier. RLS's suppliers_select policy is what actually
 * restricts this to Manager/Accountant-Auditor — Attendant gets an empty
 * list back, same as accounts/bank_accounts. */
export function useSuppliers() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewSupplier = {
  name: string;
  contactName?: string;
  phone?: string;
  email?: string;
  address?: string;
};

/** Manager-only, enforced server-side by create_supplier() — create-can't-
 * overwrite discipline: no client-supplied id, a plain insert. */
export async function createSupplier(input: NewSupplier): Promise<Supplier> {
  if (!state.branchId) await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");

  const { data, error } = await supabase.rpc("create_supplier", {
    p_branch_id: state.branchId,
    p_name: input.name,
    p_contact_name: input.contactName ?? "",
    p_phone: input.phone ?? "",
    p_email: input.email ?? "",
    p_address: input.address ?? "",
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Supplier was created but no id was returned.");

  await reload();
  const created = state.suppliers.find((s) => s.id === row.id);
  if (!created) throw new Error("Supplier was created but could not be found after reloading.");
  return created;
}

export type SupplierEdits = {
  name: string;
  contactName: string;
  phone: string;
  email: string;
  address: string;
  active: boolean;
};

/** A plain RLS-gated update (Manager-only), not its own RPC — same
 * reasoning as updateAccount()/updateBankAccount(): nothing about a
 * contact-detail edit needs server-side computation beyond what the CHECK
 * constraints already protect. */
export async function updateSupplier(id: string, edits: SupplierEdits): Promise<void> {
  const { error } = await supabase
    .from("suppliers")
    .update({
      name: edits.name,
      contact_name: edits.contactName,
      phone: edits.phone,
      email: edits.email,
      address: edits.address,
      is_active: edits.active,
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}
