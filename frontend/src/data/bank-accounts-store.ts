import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type BankAccount = {
  id: string;
  name: string;
  accountNumber: string;
  glAccountId: string;
  glAccountCode: string;
  glAccountName: string;
  openingBalance: number;
  openingBalanceDate: string;
  currency: string;
  active: boolean;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
};

type BankAccountRow = Database["public"]["Tables"]["bank_accounts"]["Row"] & {
  staff: { name: string } | null;
  accounts: { code: string; name: string } | null;
};

function mapBankAccountRow(row: BankAccountRow): BankAccount {
  return {
    id: row.id,
    name: row.name,
    accountNumber: row.account_number,
    glAccountId: row.gl_account_id,
    glAccountCode: row.accounts?.code ?? "?",
    glAccountName: row.accounts?.name ?? "Unknown account",
    openingBalance: Number(row.opening_balance),
    openingBalanceDate: row.opening_balance_date,
    currency: row.currency,
    active: row.is_active,
    createdBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

type BankAccountsState = {
  accounts: BankAccount[];
  loading: boolean;
  error: string | null;
};

let state: BankAccountsState = { accounts: [], loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: BankAccountsState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadBankAccounts() {
  const { data, error } = await supabase
    .from("bank_accounts")
    .select("*, staff(name), accounts(code, name)")
    .order("name");
  if (error) throw error;
  setState({
    accounts: (data as BankAccountRow[]).map(mapBankAccountRow),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadBankAccounts().catch((err) => {
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

/** Every real bank account. RLS's bank_accounts_select policy is what
 * actually restricts this to Manager/Accountant-Auditor — Attendant gets
 * an empty list back, same as accounts/journal entries. */
export function useBankAccounts() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewBankAccount = {
  name: string;
  accountNumber: string;
  /** Optional. Omitted -> create_bank_account() provisions a dedicated,
   * postable "Cash in Bank — <name>" sub-account (1011, 1012, ...) in the
   * same step, so a bank account and its ledger account are never out of
   * sync. Supplied -> that existing postable Assets account is attached. */
  glAccountId?: string;
  openingBalance: number;
  openingBalanceDate: string;
  currency?: string;
};

/** Manager-only, enforced server-side by create_bank_account() —
 * create-can't-overwrite discipline: no client-supplied id, a plain
 * insert, a friendly "already linked" error instead of a raw
 * unique_violation on gl_account_id. */
export async function createBankAccount(input: NewBankAccount): Promise<BankAccount> {
  const { data, error } = await supabase.rpc("create_bank_account", {
    p_name: input.name,
    p_account_number: input.accountNumber,
    p_opening_balance: input.openingBalance,
    p_opening_balance_date: input.openingBalanceDate,
    p_currency: input.currency ?? "GHS",
    ...(input.glAccountId ? { p_gl_account_id: input.glAccountId } : {}),
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Bank account was created but no id was returned.");

  await reload();
  const created = state.accounts.find((a) => a.id === row.id);
  if (!created) throw new Error("Bank account was created but could not be found after reloading.");
  return created;
}

export type BankAccountEdits = {
  name: string;
  accountNumber: string;
  currency: string;
  active: boolean;
};

/** A plain RLS-gated update (Manager-only), not its own RPC — the same
 * reasoning as updateAccount(): glAccountId/openingBalance/
 * openingBalanceDate are enforced immutable by a database trigger, so
 * there's no invariant left for an update RPC to protect beyond what
 * plain RLS + that trigger already do. */
export async function updateBankAccount(id: string, edits: BankAccountEdits): Promise<void> {
  const { error } = await supabase
    .from("bank_accounts")
    .update({
      name: edits.name,
      account_number: edits.accountNumber,
      currency: edits.currency,
      is_active: edits.active,
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}
