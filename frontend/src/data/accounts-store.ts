import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type AccountCategory = "Assets" | "Liabilities" | "Equity" | "Revenue" | "Expenses";
export type NormalBalance = "debit" | "credit";

export const ACCOUNT_CATEGORIES: AccountCategory[] = [
  "Assets",
  "Liabilities",
  "Equity",
  "Revenue",
  "Expenses",
];

export type Account = {
  id: string;
  code: string;
  name: string;
  category: AccountCategory;
  subtype: string;
  normalBalance: NormalBalance;
  description: string;
  active: boolean;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
};

type AccountRow = Database["public"]["Tables"]["accounts"]["Row"];
type AccountRowWithStaff = AccountRow & { staff: { name: string } | null };

function mapAccountRow(row: AccountRowWithStaff): Account {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    category: row.category as AccountCategory,
    subtype: row.subtype,
    normalBalance: (row.normal_balance ?? "debit") as NormalBalance,
    description: row.description,
    active: row.is_active,
    createdBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

type AccountsState = {
  accounts: Account[];
  loading: boolean;
  error: string | null;
};

let state: AccountsState = { accounts: [], loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: AccountsState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadAccounts() {
  const { data, error } = await supabase.from("accounts").select("*, staff(name)").order("code");
  if (error) throw error;
  setState({
    accounts: (data as AccountRowWithStaff[]).map(mapAccountRow),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadAccounts().catch((err) => {
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

/** The full chart of accounts. RLS's accounts_select policy is what
 * actually restricts this to Manager/Accountant-Auditor — Attendant gets
 * an empty list back, not a load error, same as bank_deposits. */
export function useAccounts() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewAccount = {
  code: string;
  name: string;
  category: AccountCategory;
  subtype: string;
  description?: string;
};

/** Manager-only, enforced server-side by create_account() — create-can't-
 * overwrite discipline: no client-supplied id, a plain insert, a friendly
 * "code already in use" error instead of a raw unique_violation. */
export async function createAccount(input: NewAccount): Promise<Account> {
  const { data, error } = await supabase.rpc("create_account", {
    p_code: input.code,
    p_name: input.name,
    p_category: input.category,
    p_subtype: input.subtype,
    p_description: input.description ?? "",
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Account was created but no id was returned.");

  await reload();
  const created = state.accounts.find((a) => a.id === row.id);
  if (!created) throw new Error("Account was created but could not be found after reloading.");
  return created;
}

export type AccountEdits = {
  name: string;
  category: AccountCategory;
  subtype: string;
  description: string;
  active: boolean;
};

/** A plain RLS-gated update (Manager-only per accounts_update), not its own
 * RPC — same reasoning as customer_discounts.active/setStaffActive(): the
 * unique constraint on code and the category check constraint already
 * protect the only real invariants, so a dedicated update_account() would
 * just be ceremony. */
export async function updateAccount(id: string, edits: AccountEdits): Promise<void> {
  const { error } = await supabase
    .from("accounts")
    .update({
      name: edits.name,
      category: edits.category,
      subtype: edits.subtype,
      description: edits.description,
      is_active: edits.active,
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}
