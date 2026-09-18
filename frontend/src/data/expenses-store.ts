import { useSyncExternalStore } from "react";

import { type Expense, type ExpenseMethod } from "@/data/expenses";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

const RECEIPTS_BUCKET = "receipts";

type ExpenseRow = Database["public"]["Tables"]["expenses"]["Row"];
type ExpenseRowWithStaff = ExpenseRow & {
  recorder_staff: { name: string } | null;
  voider_staff: { name: string } | null;
};
type ExpenseCategoryRow = Database["public"]["Tables"]["expense_categories"]["Row"];

type ExpenseState = {
  expenses: Expense[];
  categories: string[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};

let state: ExpenseState = {
  expenses: [],
  categories: [],
  branchId: null,
  loading: true,
  error: null,
};

const listeners = new Set<() => void>();

function setState(next: ExpenseState) {
  state = next;
  listeners.forEach((l) => l());
}

/** Signed URLs expire after this long. The bucket is private
 * (20260918110000) — a receipt is exactly as sensitive as the expense row
 * it belongs to (Manager/Accountant/Auditor only), so it's read through a
 * time-limited signed URL rather than a permanent public one. Re-signed on
 * every load, so this only bounds how long a URL keeps working if it
 * leaks somewhere outside the app (browser history, a screenshare) — a
 * normal viewing session never sees a stale one. */
const RECEIPT_URL_EXPIRY_SECONDS = 60 * 60;

/** One batched `createSignedUrls()` call for every receipt in this load,
 * instead of one request per row — same signed-URL access-check either
 * way (Storage gates signing itself against the `receipts_select` RLS
 * policy using the caller's own session), just fewer round trips. Missing/
 * failed entries resolve to null rather than failing the whole load — a
 * receipt that can't be signed (e.g. the underlying object was somehow
 * removed) shouldn't block the rest of the expense list from loading. */
async function signReceiptUrls(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data, error } = await supabase.storage
    .from(RECEIPTS_BUCKET)
    .createSignedUrls(paths, RECEIPT_URL_EXPIRY_SECONDS);
  if (error) throw error;
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) map.set(item.path, item.signedUrl);
  }
  return map;
}

function mapExpenseRow(row: ExpenseRowWithStaff, signedUrls: Map<string, string>): Expense {
  return {
    id: row.id,
    date: row.date,
    category: row.category,
    description: row.description,
    amount: Number(row.amount),
    method: row.method as ExpenseMethod,
    reference: row.reference ?? undefined,
    bankAccountId: row.bank_account_id,
    recordedBy: row.recorder_staff?.name ?? "Unknown",
    recordedAt: row.recorded_at,
    receiptUrl: row.receipt_path ? (signedUrls.get(row.receipt_path) ?? null) : null,
    voidedAt: row.voided_at,
    voidedBy: row.voider_staff?.name ?? null,
    voidReason: row.void_reason,
  };
}

let loadPromise: Promise<void> | null = null;

async function loadExpenses() {
  const [branchResult, categoriesResult, expensesResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase.from("expense_categories").select("*").order("position"),
    supabase
      .from("expenses")
      // expenses has two FKs into staff (recorded_by, and voided_by as of
      // the void feature) — a bare staff(name) embed is ambiguous
      // (PGRST201), so each is named explicitly.
      .select(
        "*, recorder_staff:staff!expenses_recorded_by_fkey(name), voider_staff:staff!expenses_voided_by_fkey(name)",
      )
      .order("date", { ascending: false })
      .order("recorded_at", { ascending: false }),
  ]);

  if (branchResult.error) throw branchResult.error;
  if (categoriesResult.error) throw categoriesResult.error;
  if (expensesResult.error) throw expensesResult.error;

  const rows = expensesResult.data as ExpenseRowWithStaff[];
  const receiptPaths = rows.map((r) => r.receipt_path).filter((p): p is string => p !== null);
  const signedUrls = await signReceiptUrls(receiptPaths);

  setState({
    expenses: rows.map((row) => mapExpenseRow(row, signedUrls)),
    categories: (categoriesResult.data as ExpenseCategoryRow[]).map((c) => c.name),
    branchId: branchResult.data.id,
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadExpenses().catch((err) => {
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

export function useExpenses() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

async function getBranchId(): Promise<string> {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

/** What a caller submits to record a new expense — no id (the database
 * generates it, see create_expense()) and no recordedBy/recordedAt (server-
 * assigned). `receiptFile` is the raw picked file, if any; createExpense()
 * uploads it to Storage itself and only sends the resulting path to the RPC. */
export type NewExpense = Pick<
  Expense,
  "date" | "category" | "description" | "amount" | "method" | "reference"
> & {
  receiptFile?: File | null;
  /** Which real bank account a "Bank" expense was paid from. Required for
   * that method (server-enforced), null for Cash / Mobile Money. */
  bankAccountId?: string | null;
};

/** Always inserts a brand new expense (see create_expense() in the Session 4
 * migration): the database generates the id from an atomic sequence, never
 * accepted from the client, and the insert is a plain insert (never an
 * upsert) — same discipline as createInvoice(), applied here even though
 * there's no separate updateExpense(): nothing in the UI edits an existing
 * expense once recorded, so create_expense() is the only entry point. */
export async function createExpense(expense: NewExpense): Promise<Expense> {
  const branchId = await getBranchId();

  let receiptPath: string | null = null;
  if (expense.receiptFile) {
    const extension = expense.receiptFile.name.split(".").pop() || "jpg";
    const path = `${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await supabase.storage
      .from(RECEIPTS_BUCKET)
      .upload(path, expense.receiptFile, { contentType: expense.receiptFile.type });
    if (uploadError) throw uploadError;
    receiptPath = path;
  }

  const { data, error } = await supabase.rpc("create_expense", {
    p_branch_id: branchId,
    p_date: expense.date,
    p_category: expense.category,
    p_description: expense.description,
    p_amount: expense.amount,
    p_method: expense.method,
    p_reference: expense.reference ?? "",
    p_receipt_path: receiptPath ?? undefined,
    p_bank_account_id: (expense.bankAccountId ?? null) as unknown as string,
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Expense was recorded but no id was returned.");

  await reload();
  const created = state.expenses.find((e) => e.id === row.id);
  if (!created) throw new Error("Expense was recorded but could not be found after reloading.");
  return created;
}

/** Replaces the whole branch-wide category list in one call (see
 * set_expense_categories() in the migration) — matches the existing
 * ListEditor UX in Settings, which always submits the full desired list
 * rather than one add/remove at a time. */
export async function setExpenseCategories(categories: string[]): Promise<void> {
  const branchId = await getBranchId();
  const { error } = await supabase.rpc("set_expense_categories", {
    p_branch_id: branchId,
    p_categories: categories,
  });
  if (error) throw error;
  await reload();
}

export function findExpense(id: string) {
  return state.expenses.find((e) => e.id === id) ?? null;
}

/** Manager-only. Voids a mistaken expense: reverses its ledger entry and
 * marks it dead. Rejected server-side for a non-Manager, a blank reason, an
 * expense from a closed day, or one older than 7 days. */
export async function voidExpense(expenseId: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("void_expense", {
    p_expense_id: expenseId,
    p_reason: reason,
  });
  if (error) throw error;
  await reload();
}
