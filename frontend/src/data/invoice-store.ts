import { useSyncExternalStore } from "react";

import { type Invoice, type InvoiceLine, type InvoicePayment } from "@/data/invoices";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

type InvoiceRow = Database["public"]["Tables"]["invoices"]["Row"];
type InvoiceLineRow = Database["public"]["Tables"]["invoice_lines"]["Row"];
type InvoicePaymentRow = Database["public"]["Tables"]["invoice_payments"]["Row"];
type InvoicePaymentWithStaff = InvoicePaymentRow & { staff: { name: string } | null };
type InvoiceWithRelations = InvoiceRow & {
  branches: { name: string } | null;
  issuer_staff: { name: string } | null;
  voider_staff: { name: string } | null;
  invoice_lines: InvoiceLineRow[];
  invoice_payments: InvoicePaymentWithStaff[];
};

export type NewInvoicePayment = {
  amount: number;
  method: InvoicePayment["method"];
  reference: string;
  note?: string;
  /** defaults to now() in the database when omitted */
  date?: string;
  /** Which real bank account a Bank Transfer / Cheque payment settled
   * into. Required for those methods (server-enforced), null otherwise. */
  bankAccountId?: string | null;
  /** The customer_deposits row a `method: "Deposit"` payment draws down —
   * set only by the "Fulfil with an invoice" flow. record_invoice_payment()
   * validates it's an Open deposit for this invoice's customer and flips it
   * to Fulfilled. */
  depositId?: string | null;
};

/** What a caller submits to create a brand new invoice — no id (the
 * database generates it), no payments (always logged separately via
 * addPayment, after the invoice itself exists), no issuedBy (the
 * create_invoice()/update_invoice() trigger sets it from the signed-in
 * user — it can't be supplied by the client), and no whtRate/whtAmount
 * (server-computed from business_settings.wht_rate and the taxable
 * subtotal — whtApplied is the only WHT field a caller actually sets). */
export type NewInvoice = Omit<
  Invoice,
  "id" | "payments" | "issuedBy" | "whtRate" | "whtAmount" | "voidedAt" | "voidedBy" | "voidReason"
>;

type InvoiceState = {
  invoices: Invoice[];
  branchId: string | null;
  /** the business's current VAT rate (business_settings.vat_rate) — the
   * source create_invoice() itself reads server-side; exposed here only so
   * the UI can preview a matching total before submitting. */
  vatRate: number | null;
  loading: boolean;
  error: string | null;
};

let state: InvoiceState = {
  invoices: [],
  branchId: null,
  vatRate: null,
  loading: true,
  error: null,
};

const listeners = new Set<() => void>();

function setState(next: InvoiceState) {
  state = next;
  listeners.forEach((l) => l());
}

function mapLineRow(row: InvoiceLineRow): InvoiceLine {
  return {
    id: row.id,
    productId: row.product_id,
    name: row.name,
    unit: row.unit,
    quantity: Number(row.quantity),
    unitPrice: Number(row.unit_price),
    discount: Number(row.discount),
    vat: row.vat,
  };
}

function mapPaymentRow(row: InvoicePaymentWithStaff): InvoicePayment {
  return {
    id: row.id,
    // paid_at is a timestamptz, but Invoice.date/dueDate elsewhere are plain
    // YYYY-MM-DD strings and every display site assumes that same shape.
    date: row.paid_at.slice(0, 10),
    amount: Number(row.amount),
    method: row.method as InvoicePayment["method"],
    reference: row.reference,
    note: row.note || undefined,
    recordedBy: row.staff?.name ?? "Unknown",
  };
}

function mapInvoiceRow(row: InvoiceWithRelations): Invoice {
  return {
    id: row.id,
    customerId: row.customer_id,
    customerName: row.customer_name,
    date: row.date,
    dueDate: row.due_date,
    branch: row.branches?.name ?? "",
    issuedBy: row.issuer_staff?.name ?? "Unknown",
    notes: row.notes,
    lines: [...row.invoice_lines].sort((a, b) => a.position - b.position).map(mapLineRow),
    invoiceDiscount: Number(row.invoice_discount),
    vatRate: Number(row.vat_rate),
    payments: [...row.invoice_payments]
      .sort((a, b) => b.paid_at.localeCompare(a.paid_at))
      .map(mapPaymentRow),
    whtApplied: row.wht_applied,
    whtRate: row.wht_rate === null ? null : Number(row.wht_rate),
    whtAmount: Number(row.wht_amount),
    voidedAt: row.voided_at,
    voidedBy: row.voider_staff?.name ?? null,
    voidReason: row.void_reason,
  };
}

let loadPromise: Promise<void> | null = null;

async function loadInvoices() {
  const [branchResult, settingsResult, invoicesResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase.from("business_settings").select("vat_rate").eq("id", 1).single(),
    supabase
      .from("invoices")
      .select(
        // invoices has two FKs into staff (issued_by, and voided_by as of
        // the void feature) — a bare staff(name) embed is ambiguous
        // (PGRST201), so each is named explicitly. invoice_payments still
        // has only recorded_by, so that embed stays unqualified.
        "*, branches(name), issuer_staff:staff!invoices_issued_by_fkey(name), voider_staff:staff!invoices_voided_by_fkey(name), invoice_lines(*), invoice_payments(*, staff(name))",
      )
      .order("date", { ascending: false }),
  ]);

  if (branchResult.error) throw branchResult.error;
  if (settingsResult.error) throw settingsResult.error;
  if (invoicesResult.error) throw invoicesResult.error;

  setState({
    invoices: (invoicesResult.data as InvoiceWithRelations[]).map(mapInvoiceRow),
    branchId: branchResult.data.id,
    vatRate: Number(settingsResult.data.vat_rate),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadInvoices().catch((err) => {
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

/** Forces a refetch from outside this module — needed anywhere an invoice
 * is created through a path that isn't createInvoice() itself, so this
 * store's cache doesn't go stale. convert_pro_forma_to_invoice() is exactly
 * that case: it inserts a real invoices row via a direct RPC call, and
 * without this, navigating straight to that new invoice would show "this
 * invoice no longer exists" until something else happened to reload the
 * page — a real bug caught live, not a hypothetical one. */
export async function reloadInvoices() {
  await reload();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

export function useInvoices() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

async function getBranchId(): Promise<string> {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

function toLinePayload(lines: InvoiceLine[]) {
  return lines.map((l) => ({
    product_id: l.productId,
    name: l.name,
    unit: l.unit,
    quantity: l.quantity,
    unit_price: l.unitPrice,
    discount: l.discount,
    vat: l.vat,
  }));
}

/** Creates a brand new invoice (see create_invoice() in the migration): the
 * database generates the invoice number and computes `total` itself from
 * the submitted lines — neither is accepted from the client, structurally
 * (create_invoice() has no p_id/p_total parameters at all), so a client can
 * never invent a number or a total. */
export async function createInvoice(invoice: NewInvoice): Promise<Invoice> {
  const branchId = await getBranchId();

  const { data, error } = await supabase.rpc("create_invoice", {
    p_branch_id: branchId,
    p_customer_id: invoice.customerId,
    p_customer_name: invoice.customerName,
    p_date: invoice.date,
    p_due_date: invoice.dueDate,
    p_notes: invoice.notes,
    p_invoice_discount: invoice.invoiceDiscount,
    p_lines: toLinePayload(invoice.lines),
    p_wht_applied: invoice.whtApplied,
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Invoice was created but no id was returned.");

  await reload();
  const created = state.invoices.find((i) => i.id === row.id);
  if (!created) throw new Error("Invoice was created but could not be found after reloading.");
  return created;
}

/** Updates an existing invoice's header + line items (see update_invoice()
 * in the migration): fails loudly if the id doesn't already exist, and — as
 * with createInvoice() — recomputes `total` server-side rather than
 * trusting whatever the client last had on screen. */
export async function updateInvoice(invoice: Invoice): Promise<void> {
  const branchId = await getBranchId();

  const { error } = await supabase.rpc("update_invoice", {
    p_id: invoice.id,
    p_branch_id: branchId,
    p_customer_id: invoice.customerId,
    p_customer_name: invoice.customerName,
    p_date: invoice.date,
    p_due_date: invoice.dueDate,
    p_notes: invoice.notes,
    p_invoice_discount: invoice.invoiceDiscount,
    p_lines: toLinePayload(invoice.lines),
  });
  if (error) throw error;

  await reload();
}

/** Logs a payment against an invoice and updates its amount_paid/balance in
 * the same transaction (see record_invoice_payment() in the migration) —
 * same discipline as inventory-store.ts's adjustStock(). */
export async function addPayment(invoiceId: string, payment: NewInvoicePayment): Promise<void> {
  const { error } = await supabase.rpc("record_invoice_payment", {
    p_invoice_id: invoiceId,
    p_amount: payment.amount,
    p_method: payment.method,
    p_reference: payment.reference,
    p_note: payment.note ?? "",
    ...(payment.date ? { p_paid_at: `${payment.date}T00:00:00Z` } : {}),
    p_bank_account_id: (payment.bankAccountId ?? null) as unknown as string,
    p_deposit_id: (payment.depositId ?? null) as unknown as string,
  });
  if (error) throw error;

  await reload();
}

/** Manager-only. Voids a mistaken invoice: reverses its ledger entries (the
 * creation entry plus one per payment), zeroes its balance, and marks it
 * dead — sync_customer_totals() then drops it from the customer's balance
 * and lifetime total. Rejected server-side for a non-Manager, a blank
 * reason, an invoice touching a closed day, or one older than 7 days. */
export async function voidInvoice(invoiceId: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("void_invoice", {
    p_invoice_id: invoiceId,
    p_reason: reason,
  });
  if (error) throw error;

  await reload();
}
