import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type DepositSource = "Cash" | "Mobile Money";

export type DayClose = {
  id: string;
  businessDate: string;
  openingFloat: number;
  openingConfirmedBy: string;
  openingConfirmedAt: string;
  cashSales: number | null;
  posCashSales: number | null;
  invoiceCashSales: number | null;
  mobileMoneySales: number | null;
  cardSales: number | null;
  bankTransferSales: number | null;
  invoiceChequeSales: number | null;
  vatCollected: number | null;
  discountsGiven: number | null;
  cashRefunds: number | null;
  cashExpenses: number | null;
  /** Drawer cash physically banked during the day (source = 'Cash' bank
   * deposits) — subtracted from expected cash so a mid-day deposit doesn't
   * show as a phantom shortage at close. */
  cashDeposits: number | null;
  expectedCash: number | null;
  countedCash: number | null;
  cashVariance: number | null;
  systemSalesTotal: number | null;
  systemTransactionCount: number | null;
  manualSalesTotal: number | null;
  manualTransactionCount: number | null;
  tallySalesVariance: number | null;
  tallyCountVariance: number | null;
  notes: string;
  closedBy: string | null;
  closedAt: string | null;
};

export type DayTotals = {
  cashSales: number;
  posCashSales: number;
  invoiceCashSales: number;
  mobileMoneySales: number;
  cardSales: number;
  bankTransferSales: number;
  invoiceChequeSales: number;
  vatCollected: number;
  discountsGiven: number;
  cashRefunds: number;
  cashExpenses: number;
  cashDeposits: number;
  systemSalesTotal: number;
  systemTransactionCount: number;
};

export type BankDeposit = {
  id: string;
  amount: number;
  date: string;
  source: DepositSource;
  depositedBy: string;
  reference: string;
  note: string;
  createdAt: string;
  /** Which real bank account (Session 16) received this deposit — was
   * hardcoded to post against 1010 regardless of which account actually
   * received it until Session 16 gave bank_deposits a real reference. */
  bankAccountId: string;
};

type DayCloseRow = Database["public"]["Tables"]["day_closes"]["Row"] & {
  opener: { name: string } | null;
  closer: { name: string } | null;
};
type BankDepositRow = Database["public"]["Tables"]["bank_deposits"]["Row"] & {
  staff: { name: string } | null;
};

function mapDayClose(row: DayCloseRow): DayClose {
  return {
    id: row.id,
    businessDate: row.business_date,
    openingFloat: Number(row.opening_float),
    openingConfirmedBy: row.opener?.name ?? "Unknown",
    openingConfirmedAt: row.opening_confirmed_at,
    cashSales: row.cash_sales === null ? null : Number(row.cash_sales),
    posCashSales: row.pos_cash_sales === null ? null : Number(row.pos_cash_sales),
    invoiceCashSales: row.invoice_cash_sales === null ? null : Number(row.invoice_cash_sales),
    mobileMoneySales: row.mobile_money_sales === null ? null : Number(row.mobile_money_sales),
    cardSales: row.card_sales === null ? null : Number(row.card_sales),
    bankTransferSales: row.bank_transfer_sales === null ? null : Number(row.bank_transfer_sales),
    invoiceChequeSales: row.invoice_cheque_sales === null ? null : Number(row.invoice_cheque_sales),
    vatCollected: row.vat_collected === null ? null : Number(row.vat_collected),
    discountsGiven: row.discounts_given === null ? null : Number(row.discounts_given),
    cashRefunds: row.cash_refunds === null ? null : Number(row.cash_refunds),
    cashExpenses: row.cash_expenses === null ? null : Number(row.cash_expenses),
    cashDeposits: row.cash_deposits === null ? null : Number(row.cash_deposits),
    expectedCash: row.expected_cash === null ? null : Number(row.expected_cash),
    countedCash: row.counted_cash === null ? null : Number(row.counted_cash),
    cashVariance: row.cash_variance === null ? null : Number(row.cash_variance),
    systemSalesTotal: row.system_sales_total === null ? null : Number(row.system_sales_total),
    systemTransactionCount: row.system_transaction_count,
    manualSalesTotal: row.manual_sales_total === null ? null : Number(row.manual_sales_total),
    manualTransactionCount: row.manual_transaction_count,
    tallySalesVariance: row.tally_sales_variance === null ? null : Number(row.tally_sales_variance),
    tallyCountVariance: row.tally_count_variance,
    notes: row.notes,
    closedBy: row.closer?.name ?? (row.closed_by ? "Unknown" : null),
    closedAt: row.closed_at,
  };
}

function mapDeposit(row: BankDepositRow): BankDeposit {
  return {
    id: row.id,
    amount: Number(row.amount),
    date: row.date,
    source: row.source as DepositSource,
    depositedBy: row.staff?.name ?? "Unknown",
    reference: row.reference,
    note: row.note,
    createdAt: row.created_at,
    bankAccountId: row.bank_account_id,
  };
}

type EodState = {
  closes: DayClose[];
  deposits: BankDeposit[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};
let state: EodState = { closes: [], deposits: [], branchId: null, loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: EodState) {
  state = next;
  listeners.forEach((listener) => listener());
}

let loadPromise: Promise<void> | null = null;
async function load() {
  const [branchResult, closesResult, depositsResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase
      .from("day_closes")
      // day_closes has two FKs into staff (opening_confirmed_by, closed_by)
      // — a bare staff(name) embed is ambiguous and PostgREST rejects it
      // with PGRST201 (see pos-store.ts's loadSales() for the same trap
      // hit and fixed on the sales table earlier).
      .select(
        "*, opener:staff!day_closes_opening_confirmed_by_fkey(name), closer:staff!day_closes_closed_by_fkey(name)",
      )
      .order("business_date", { ascending: false }),
    supabase
      .from("bank_deposits")
      .select("*, staff(name)")
      .order("date", { ascending: false })
      .order("created_at", { ascending: false }),
  ]);
  if (branchResult.error) throw branchResult.error;
  // Attendant has no read access to bank_deposits at all (same sensitivity
  // class as expenses) — treat that specific denial as "no deposits to
  // show" rather than a load failure, the same way an Attendant's RLS-
  // filtered empty expenses list isn't an error either.
  if (closesResult.error) throw closesResult.error;
  const deposits =
    depositsResult.error && depositsResult.error.code === "42501"
      ? []
      : (() => {
          if (depositsResult.error) throw depositsResult.error;
          return (depositsResult.data as unknown as BankDepositRow[]).map(mapDeposit);
        })();

  setState({
    closes: (closesResult.data as unknown as DayCloseRow[]).map(mapDayClose),
    deposits,
    branchId: branchResult.data.id,
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
export function useEndOfDay() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

async function getBranchId(): Promise<string> {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

/** The live figures for one branch/day — never cached in the shared store,
 * always a fresh RPC call, since "live" means computed on demand, not
 * computed once and reused. Callers decide their own refresh cadence. */
export async function fetchDayTotals(branchId: string, businessDate: string): Promise<DayTotals> {
  const { data, error } = await supabase.rpc("compute_day_totals", {
    p_branch_id: branchId,
    p_business_date: businessDate,
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) throw new Error("Could not compute today's figures.");
  return {
    cashSales: Number(row.cash_sales),
    posCashSales: Number(row.pos_cash_sales),
    invoiceCashSales: Number(row.invoice_cash_sales),
    mobileMoneySales: Number(row.mobile_money_sales),
    cardSales: Number(row.card_sales),
    bankTransferSales: Number(row.bank_transfer_sales),
    invoiceChequeSales: Number(row.invoice_cheque_sales),
    vatCollected: Number(row.vat_collected),
    discountsGiven: Number(row.discounts_given),
    cashRefunds: Number(row.cash_refunds),
    cashExpenses: Number(row.cash_expenses),
    cashDeposits: Number(row.cash_deposits),
    systemSalesTotal: Number(row.system_sales_total),
    systemTransactionCount: row.system_transaction_count,
  };
}

export async function openDay(openingFloat: number): Promise<DayClose> {
  const branchId = await getBranchId();
  const { data, error } = await supabase.rpc("open_day", {
    p_branch_id: branchId,
    p_opening_float: openingFloat,
  });
  if (error) throw error;
  await reload();
  const created = state.closes.find((c) => c.id === data.id);
  if (!created) throw new Error("Opening float was confirmed but could not be loaded.");
  return created;
}

export async function closeDay(input: {
  countedCash: number;
  manualSalesTotal: number;
  manualTransactionCount: number;
  notes?: string;
}): Promise<DayClose> {
  const branchId = await getBranchId();
  const { data, error } = await supabase.rpc("close_day", {
    p_branch_id: branchId,
    p_counted_cash: input.countedCash,
    p_manual_sales_total: input.manualSalesTotal,
    p_manual_transaction_count: input.manualTransactionCount,
    p_notes: input.notes ?? "",
  });
  if (error) throw error;
  await reload();
  const closed = state.closes.find((c) => c.id === data.id);
  if (!closed) throw new Error("The day was closed but could not be loaded.");
  return closed;
}

export async function recordDeposit(input: {
  bankAccountId: string;
  amount: number;
  date: string;
  source: DepositSource;
  reference?: string;
  note?: string;
}): Promise<BankDeposit> {
  const branchId = await getBranchId();
  const { data, error } = await supabase.rpc("record_bank_deposit", {
    p_branch_id: branchId,
    p_bank_account_id: input.bankAccountId,
    p_amount: input.amount,
    p_date: input.date,
    p_source: input.source,
    p_reference: input.reference ?? "",
    p_note: input.note ?? "",
  });
  if (error) throw error;
  await reload();
  const created = state.deposits.find((d) => d.id === data.id);
  if (!created) throw new Error("The deposit was recorded but could not be loaded.");
  return created;
}
