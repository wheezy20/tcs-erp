import { useSyncExternalStore } from "react";

import { reloadInvoices } from "@/data/invoice-store";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type CustomerDepositStatus = "Open" | "Fulfilled" | "Cancelled";
export type DepositMethod = "Cash" | "Mobile Money" | "Card" | "Bank Transfer";

export type CustomerDeposit = {
  id: string;
  customerId: string;
  customerName: string;
  description: string;
  amount: number;
  method: DepositMethod;
  bankAccountId: string | null;
  status: CustomerDepositStatus;
  takenAt: string;
  takenBy: string;
  fulfilledSaleId: string | null;
  fulfilledInvoiceId: string | null;
  fulfilledAt: string | null;
  cancelledAt: string | null;
  cancelledBy: string | null;
  cancellationFee: number | null;
  cancellationRefund: number | null;
  cancellationNote: string | null;
};

/** What a caller submits to record a deposit — no id/status/timestamps (all
 * database-decided), no takenBy (the identity trigger sets it). */
export type NewCustomerDeposit = {
  customerId: string;
  description: string;
  amount: number;
  method: DepositMethod;
  bankAccountId: string | null;
};

type DepositRow = Database["public"]["Tables"]["customer_deposits"]["Row"];
type DepositWithStaff = DepositRow & {
  taker: { name: string } | null;
  canceller: { name: string } | null;
};

function mapRow(row: DepositWithStaff): CustomerDeposit {
  return {
    id: row.id,
    customerId: row.customer_id,
    customerName: row.customer_name,
    description: row.description,
    amount: Number(row.amount),
    method: row.method as DepositMethod,
    bankAccountId: row.bank_account_id,
    status: row.status as CustomerDepositStatus,
    takenAt: row.taken_at,
    takenBy: row.taker?.name ?? "Unknown",
    fulfilledSaleId: row.fulfilled_sale_id,
    fulfilledInvoiceId: row.fulfilled_invoice_id,
    fulfilledAt: row.fulfilled_at,
    cancelledAt: row.cancelled_at,
    cancelledBy: row.canceller?.name ?? null,
    cancellationFee: row.cancellation_fee === null ? null : Number(row.cancellation_fee),
    cancellationRefund: row.cancellation_refund === null ? null : Number(row.cancellation_refund),
    cancellationNote: row.cancellation_note,
  };
}

type State = { deposits: CustomerDeposit[]; loading: boolean; error: string | null };
let state: State = { deposits: [], loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;
async function load() {
  // customer_deposits has two FKs into staff (taken_by, cancelled_by) — an
  // unqualified staff(name) embed is the ambiguous PGRST201 that broke
  // pos-store's sales query once. Name both explicitly, same as
  // end-of-day-store.ts.
  const { data, error } = await supabase
    .from("customer_deposits")
    .select(
      "*, taker:staff!customer_deposits_taken_by_fkey(name), canceller:staff!customer_deposits_cancelled_by_fkey(name)",
    )
    .order("taken_at", { ascending: false });
  if (error) throw error;
  setState({
    deposits: (data as unknown as DepositWithStaff[]).map(mapRow),
    loading: false,
    error: null,
  });
}
function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = load().catch((error) => {
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
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

export function useCustomerDeposits() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

/** Records a deposit: real money in, Dr cash/bank/MoMo / Cr 2450 posted
 * immediately by create_customer_deposit(). */
export async function createCustomerDeposit(
  branchId: string,
  input: NewCustomerDeposit,
): Promise<CustomerDeposit> {
  const { data, error } = await supabase.rpc("create_customer_deposit", {
    p_branch_id: branchId,
    p_customer_id: input.customerId,
    p_description: input.description,
    p_amount: input.amount,
    p_method: input.method,
    p_bank_account_id: (input.bankAccountId ?? null) as unknown as string,
  });
  if (error) throw error;
  await reload();
  const row = Array.isArray(data) ? data[0] : data;
  const created = state.deposits.find((d) => d.id === row?.id);
  if (!created) throw new Error("The deposit was recorded but could not be loaded.");
  return created;
}

/** Manager-only. fee is an explicit choice (0..amount); refund = amount −
 * fee. Posts Dr 2450 / Cr <settlement> refund / Cr 4900 fee. */
export async function cancelCustomerDeposit(
  depositId: string,
  fee: number,
  note: string,
): Promise<void> {
  const { error } = await supabase.rpc("cancel_customer_deposit", {
    p_deposit_id: depositId,
    p_fee: fee,
    // "" reaches the RPC as an empty note, which it stores as NULL
    // (nullif(trim(...), '')). The generated arg type is a plain string.
    p_note: note.trim(),
  });
  if (error) throw error;
  await reload();
}

/** Fulfilment happens inside create_sale() / record_invoice_payment(), which
 * also flip the deposit to Fulfilled — call this afterward so the list
 * reflects it without a full page reload. reloadInvoices() covers the
 * invoice path's own store. */
export async function reloadCustomerDeposits() {
  await reload();
  await reloadInvoices().catch(() => {});
}
