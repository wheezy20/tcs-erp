import { useSyncExternalStore } from "react";

import type { Customer } from "@/data/customers";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

type CustomerRow = Database["public"]["Tables"]["customers"]["Row"];

export type NewCustomer = {
  name: string;
  phone: string;
  email: string;
  address: string;
};

type CustomerState = {
  customers: Customer[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};

let state: CustomerState = {
  customers: [],
  branchId: null,
  loading: true,
  error: null,
};

const listeners = new Set<() => void>();

function setState(next: CustomerState) {
  state = next;
  listeners.forEach((l) => l());
}

function sinceLabel(dateStr: string) {
  return new Date(dateStr).toLocaleDateString("en-GB", { month: "short", year: "numeric" });
}

function mapCustomerRow(row: CustomerRow): Customer {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    email: row.email,
    address: row.address,
    type: row.customer_type as Customer["type"],
    since: sinceLabel(row.customer_since),
    balance: Number(row.balance),
    lifetime: Number(row.lifetime_total),
    storeCreditBalance: Number(row.store_credit_balance),
  };
}

let loadPromise: Promise<void> | null = null;

async function loadCustomers() {
  const [branchResult, customersResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase.from("customers").select("*").order("name"),
  ]);

  if (branchResult.error) throw branchResult.error;
  if (customersResult.error) throw customersResult.error;

  setState({
    customers: customersResult.data.map(mapCustomerRow),
    branchId: branchResult.data.id,
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadCustomers().catch((err) => {
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

export function useCustomers() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

async function getBranchId(): Promise<string> {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

export async function addCustomer(input: NewCustomer): Promise<Customer> {
  const branchId = await getBranchId();
  const { data: inserted, error } = await supabase
    .from("customers")
    .insert({
      branch_id: branchId,
      name: input.name,
      phone: input.phone,
      email: input.email,
      address: input.address,
    })
    .select()
    .single();
  if (error) throw error;

  await reload();
  return mapCustomerRow(inserted);
}

/** Bulk variant for the spreadsheet import flow — one reload instead of one per row. */
export async function addCustomers(inputs: NewCustomer[]): Promise<void> {
  if (inputs.length === 0) return;
  const branchId = await getBranchId();

  const { error } = await supabase.from("customers").insert(
    inputs.map((input) => ({
      branch_id: branchId,
      name: input.name,
      phone: input.phone,
      email: input.email,
      address: input.address,
    })),
  );
  if (error) throw error;

  await reload();
}
