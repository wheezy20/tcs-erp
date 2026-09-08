import { useSyncExternalStore } from "react";

import { reloadInvoices } from "@/data/invoice-store";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import type { InvoiceLine } from "@/data/invoices";

export type ProFormaStatus = "open" | "converted";

export type ProFormaInvoice = {
  id: string;
  customerId: string;
  customerName: string;
  date: string;
  /** "Valid until", not a payment due date — see the Session 19 migration. */
  validUntil: string;
  notes: string;
  lines: InvoiceLine[];
  invoiceDiscount: number;
  vatRate: number;
  total: number;
  status: ProFormaStatus;
  convertedInvoiceId: string | null;
  createdBy: string;
  createdAt: string;
};

/** What a caller submits to create a new pro-forma — no id, status, or
 * convertedInvoiceId (all database-decided), no createdBy (the identity
 * trigger sets it). */
export type NewProFormaInvoice = Omit<
  ProFormaInvoice,
  "id" | "status" | "convertedInvoiceId" | "createdBy" | "createdAt"
>;

type ProFormaRow = Database["public"]["Tables"]["pro_forma_invoices"]["Row"];
type ProFormaLineRow = Database["public"]["Tables"]["pro_forma_invoice_lines"]["Row"];
type ProFormaWithRelations = ProFormaRow & {
  staff: { name: string } | null;
  pro_forma_invoice_lines: ProFormaLineRow[];
};

function mapLineRow(row: ProFormaLineRow): InvoiceLine {
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

function mapRow(row: ProFormaWithRelations): ProFormaInvoice {
  return {
    id: row.id,
    customerId: row.customer_id,
    customerName: row.customer_name,
    date: row.date,
    validUntil: row.due_date,
    notes: row.notes,
    lines: [...row.pro_forma_invoice_lines].sort((a, b) => a.position - b.position).map(mapLineRow),
    invoiceDiscount: Number(row.invoice_discount),
    vatRate: Number(row.vat_rate),
    total: Number(row.total),
    status: row.status as ProFormaStatus,
    convertedInvoiceId: row.converted_invoice_id,
    createdBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
  };
}

type State = {
  proFormaInvoices: ProFormaInvoice[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};

let state: State = { proFormaInvoices: [], branchId: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

async function load() {
  const [branchResult, rowsResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase
      .from("pro_forma_invoices")
      .select("*, staff(name), pro_forma_invoice_lines(*)")
      .order("created_at", { ascending: false }),
  ]);
  if (branchResult.error) throw branchResult.error;
  if (rowsResult.error) throw rowsResult.error;

  setState({
    proFormaInvoices: (rowsResult.data as ProFormaWithRelations[]).map(mapRow),
    branchId: branchResult.data.id,
    loading: false,
    error: null,
  });
}

let loadPromise: Promise<void> | null = null;

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

export function useProFormaInvoices() {
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

/** Creates a new pro-forma (see create_pro_forma_invoice() in the
 * migration): no ledger entry, no stock reservation, no AR impact — a
 * non-binding quote only. */
export async function createProFormaInvoice(pf: NewProFormaInvoice): Promise<ProFormaInvoice> {
  const branchId = await getBranchId();

  const { data, error } = await supabase.rpc("create_pro_forma_invoice", {
    p_branch_id: branchId,
    p_customer_id: pf.customerId,
    p_customer_name: pf.customerName,
    p_date: pf.date,
    p_due_date: pf.validUntil,
    p_notes: pf.notes,
    p_invoice_discount: pf.invoiceDiscount,
    p_lines: toLinePayload(pf.lines),
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Pro-forma invoice was created but no id was returned.");

  await reload();
  const created = state.proFormaInvoices.find((p) => p.id === row.id);
  if (!created)
    throw new Error("Pro-forma invoice was created but could not be found after reloading.");
  return created;
}

/** The one sanctioned way a pro-forma becomes a real invoice (see
 * convert_pro_forma_to_invoice() in the migration) — issued today, with a
 * fresh due date and an explicit WHT decision, both chosen at conversion
 * time rather than carried over from the quote. Returns the new invoice's
 * id; the caller navigates there. */
export async function convertProFormaToInvoice(
  proFormaId: string,
  dueDate: string,
  whtApplied: boolean,
): Promise<string> {
  const { data, error } = await supabase.rpc("convert_pro_forma_to_invoice", {
    p_pro_forma_invoice_id: proFormaId,
    p_due_date: dueDate,
    p_wht_applied: whtApplied,
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Converted, but no new invoice id was returned.");

  // The invoices store's own cache doesn't know a new row exists yet — this
  // RPC created it directly, bypassing invoice-store.ts's createInvoice()
  // (the only path that normally triggers a reload there).
  await Promise.all([reload(), reloadInvoices()]);
  return row.id;
}
