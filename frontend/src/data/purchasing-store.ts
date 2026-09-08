import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type PurchaseOrderStatus =
  "draft" | "ordered" | "partially_received" | "received" | "cancelled";

export type PurchaseOrderLine = {
  id: string;
  productId: string;
  name: string;
  unit: string;
  quantityOrdered: number;
  quantityReceived: number;
  unitCost: number;
};

export type PurchaseOrderReceiptLine = {
  id: string;
  purchaseOrderLineId: string;
  productId: string;
  quantity: number;
  unitCost: number;
};

export type PurchaseOrderReceipt = {
  id: string;
  receivedDate: string;
  notes: string;
  totalValue: number;
  receivedBy: string;
  createdAt: string;
  lines: PurchaseOrderReceiptLine[];
};

export type SupplierPayment = {
  id: string;
  amount: number;
  method: "Cash" | "Mobile Money" | "Bank Transfer" | "Cheque";
  reference: string;
  note: string;
  paidAt: string;
  recordedBy: string;
  /** Which real bank account a Bank Transfer / Cheque payment settled
   * from. Required for those methods (server-enforced), null otherwise. */
  bankAccountId: string | null;
};

export type PurchaseOrder = {
  id: string;
  supplierId: string;
  supplierName: string;
  status: PurchaseOrderStatus;
  orderDate: string;
  expectedDate: string | null;
  notes: string;
  total: number;
  receivedValue: number;
  amountPaid: number;
  balance: number;
  createdBy: string;
  createdAt: string;
  lines: PurchaseOrderLine[];
  receipts: PurchaseOrderReceipt[];
  payments: SupplierPayment[];
};

type POLineRow = Database["public"]["Tables"]["purchase_order_lines"]["Row"];
type ReceiptLineRow = Database["public"]["Tables"]["purchase_order_receipt_lines"]["Row"];
type ReceiptRow = Database["public"]["Tables"]["purchase_order_receipts"]["Row"] & {
  staff: { name: string } | null;
  purchase_order_receipt_lines: ReceiptLineRow[];
};
type PaymentRow = Database["public"]["Tables"]["supplier_payments"]["Row"] & {
  staff: { name: string } | null;
};
type PORow = Database["public"]["Tables"]["purchase_orders"]["Row"] & {
  purchase_order_lines: POLineRow[];
  purchase_order_receipts: ReceiptRow[];
  supplier_payments: PaymentRow[];
};

function mapLine(row: POLineRow): PurchaseOrderLine {
  return {
    id: row.id,
    productId: row.product_id,
    name: row.name,
    unit: row.unit,
    quantityOrdered: row.quantity_ordered,
    quantityReceived: row.quantity_received,
    unitCost: Number(row.unit_cost),
  };
}

function mapReceiptLine(row: ReceiptLineRow): PurchaseOrderReceiptLine {
  return {
    id: row.id,
    purchaseOrderLineId: row.purchase_order_line_id,
    productId: row.product_id,
    quantity: row.quantity,
    unitCost: Number(row.unit_cost),
  };
}

function mapReceipt(row: ReceiptRow): PurchaseOrderReceipt {
  return {
    id: row.id,
    receivedDate: row.received_date,
    notes: row.notes,
    totalValue: Number(row.total_value),
    receivedBy: row.staff?.name ?? "Unknown",
    createdAt: row.created_at,
    lines: [...row.purchase_order_receipt_lines].map(mapReceiptLine),
  };
}

function mapPayment(row: PaymentRow): SupplierPayment {
  return {
    id: row.id,
    amount: Number(row.amount),
    method: row.method as SupplierPayment["method"],
    reference: row.reference,
    note: row.note,
    paidAt: row.paid_at,
    recordedBy: row.staff?.name ?? "Unknown",
    bankAccountId: row.bank_account_id,
  };
}

function mapPO(row: PORow): PurchaseOrder {
  return {
    id: row.id,
    supplierId: row.supplier_id,
    supplierName: row.supplier_name,
    status: row.status as PurchaseOrderStatus,
    orderDate: row.order_date,
    expectedDate: row.expected_date,
    notes: row.notes,
    total: Number(row.total),
    receivedValue: Number(row.received_value),
    amountPaid: Number(row.amount_paid),
    balance: Number(row.balance),
    createdBy: row.created_by,
    createdAt: row.created_at,
    lines: [...row.purchase_order_lines].sort((a, b) => a.id.localeCompare(b.id)).map(mapLine),
    receipts: [...row.purchase_order_receipts]
      .sort((a, b) => b.received_date.localeCompare(a.received_date))
      .map(mapReceipt),
    payments: [...row.supplier_payments]
      .sort((a, b) => b.paid_at.localeCompare(a.paid_at))
      .map(mapPayment),
  };
}

type PurchasingState = {
  purchaseOrders: PurchaseOrder[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};

let state: PurchasingState = { purchaseOrders: [], branchId: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: PurchasingState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadPurchaseOrders() {
  const [branchResult, poResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase
      .from("purchase_orders")
      .select(
        "*, purchase_order_lines(*), purchase_order_receipts(*, staff(name), purchase_order_receipt_lines(*)), supplier_payments(*, staff(name))",
      )
      .order("created_at", { ascending: false }),
  ]);
  if (branchResult.error) throw branchResult.error;
  if (poResult.error) throw poResult.error;
  setState({
    purchaseOrders: (poResult.data as unknown as PORow[]).map(mapPO),
    branchId: branchResult.data.id,
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadPurchaseOrders().catch((err) => {
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

/** Every purchase order, with its lines, receipts and payments nested.
 * RLS restricts this to Manager/Accountant-Auditor — Attendant gets an
 * empty list back, same as accounts/bank_accounts/suppliers. */
export function usePurchaseOrders() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export type NewPurchaseOrderLine = {
  productId: string;
  name: string;
  unit: string;
  quantity: number;
  unitCost: number;
};

export type NewPurchaseOrder = {
  supplierId: string;
  supplierName: string;
  orderDate: string;
  expectedDate: string | null;
  notes?: string;
  lines: NewPurchaseOrderLine[];
};

async function getBranchId() {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

/** Insert-only, no client-supplied id or total — create-can't-overwrite,
 * the same discipline every other create_x() RPC in this build follows.
 * No journal entry yet: a purchase order is a request, not an economic
 * event until something is actually received. */
export async function createPurchaseOrder(input: NewPurchaseOrder): Promise<PurchaseOrder> {
  const branchId = await getBranchId();
  const { data, error } = await supabase.rpc("create_purchase_order", {
    p_branch_id: branchId,
    p_supplier_id: input.supplierId,
    p_supplier_name: input.supplierName,
    p_order_date: input.orderDate,
    p_expected_date: input.expectedDate as unknown as string,
    p_notes: input.notes ?? "",
    p_lines: input.lines.map((l) => ({
      product_id: l.productId,
      name: l.name,
      unit: l.unit,
      quantity: l.quantity,
      unit_cost: l.unitCost,
    })),
  });
  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null | undefined;
  if (!row?.id) throw new Error("Purchase order was created but no id was returned.");

  await reload();
  const created = state.purchaseOrders.find((po) => po.id === row.id);
  if (!created)
    throw new Error("Purchase order was created but could not be found after reloading.");
  return created;
}

export async function placePurchaseOrder(id: string): Promise<void> {
  const { error } = await supabase.rpc("place_purchase_order", { p_purchase_order_id: id });
  if (error) throw error;
  await reload();
}

export async function cancelPurchaseOrder(id: string): Promise<void> {
  const { error } = await supabase.rpc("cancel_purchase_order", { p_purchase_order_id: id });
  if (error) throw error;
  await reload();
}

export type NewReceiptLine = { purchaseOrderLineId: string; quantity: number };

/** The one place inventory stock changes for this module — reuses
 * adjust_product_stock()'s own locked-read-then-write discipline
 * server-side rather than a new stock-mutation path, matching Session 1's
 * pattern. Posts Dr Inventory / Cr Accounts Payable atomically. */
export async function receivePurchaseOrder(
  purchaseOrderId: string,
  input: { receivedDate: string; notes?: string; lines: NewReceiptLine[] },
): Promise<void> {
  const { error } = await supabase.rpc("receive_purchase_order", {
    p_purchase_order_id: purchaseOrderId,
    p_received_date: input.receivedDate,
    p_notes: input.notes ?? "",
    p_lines: input.lines.map((l) => ({
      purchase_order_line_id: l.purchaseOrderLineId,
      quantity: l.quantity,
    })),
  });
  if (error) throw error;
  await reload();
}

export type NewSupplierPayment = {
  amount: number;
  method: SupplierPayment["method"];
  reference?: string;
  note?: string;
  paidAt?: string;
  /** Required for Bank Transfer / Cheque (server-enforced), null otherwise. */
  bankAccountId?: string | null;
};

/** Dr Accounts Payable / Cr Cash-or-Bank-by-method — the exact mirror of
 * record_invoice_payment()/post_invoice_payment_journal_entry(), opposite
 * direction. Capped server-side at received_value - amount_paid, never
 * the full ordered total — you can't pay for what hasn't arrived yet. */
export async function recordSupplierPayment(
  purchaseOrderId: string,
  input: NewSupplierPayment,
): Promise<void> {
  const { error } = await supabase.rpc("record_supplier_payment", {
    p_purchase_order_id: purchaseOrderId,
    p_amount: input.amount,
    p_method: input.method,
    p_reference: input.reference ?? "",
    p_note: input.note ?? "",
    ...(input.paidAt ? { p_paid_at: input.paidAt } : {}),
    p_bank_account_id: (input.bankAccountId ?? null) as unknown as string,
  });
  if (error) throw error;
  await reload();
}
