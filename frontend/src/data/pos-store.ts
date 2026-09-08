import { useSyncExternalStore } from "react";

import {
  noDiscount,
  type DiscountMode,
  type PosMethod,
  type PosReturn,
  type PosSale,
} from "@/data/pos";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

type SaleRow = Database["public"]["Tables"]["sales"]["Row"];
type SaleLineRow = Database["public"]["Tables"]["sale_lines"]["Row"];
type SalePaymentRow = Database["public"]["Tables"]["sale_payments"]["Row"];
type SaleReturnRow = Database["public"]["Tables"]["sale_returns"]["Row"];
type SaleReturnRowWithStaff = SaleReturnRow & { staff: { name: string } | null };
type SaleWithRelations = SaleRow & {
  branches: { name: string } | null;
  cashier_staff: { name: string } | null;
  voider_staff: { name: string } | null;
  sale_lines: SaleLineRow[];
  sale_payments: SalePaymentRow[];
  sale_returns: SaleReturnRowWithStaff[];
};

export type NewPosSale = Omit<
  PosSale,
  | "id"
  | "date"
  | "time"
  | "branch"
  | "vatRate"
  | "returns"
  | "cashier"
  | "voidedAt"
  | "voidedBy"
  | "voidReason"
> & {
  /** A single-use manager_overrides ticket id (Session 9) — set only when an
   * Attendant got Manager authorization for this sale's discount/VAT.
   * Redeemed server-side inside create_sale(); omitted entirely for a
   * Manager's own sale or an Attendant sale with no override in it. */
  overrideTicket?: string | null;
};
/** One line's worth of a return batch — which sold line, how many units,
 * and (optionally) what to swap it for. The resolution, difference, and
 * journal posting are all derived server-side per line inside
 * create_sale_return_batch(). */
export type NewReturnLine = {
  returnedSaleLineId: string;
  returnedQuantity: number;
  replacement: { productId: string; quantity: number } | null;
};

/** The decisions shared by every line in one return transaction — a single
 * reason, one refund choice, and (only if some line collects a top-up or
 * credits a Walk-in customer) the shared method / bank / customer. */
export type NewReturnBatch = {
  lines: NewReturnLine[];
  reason: string;
  refundChoice: "Cash refund" | "Store credit";
  paymentMethod: Exclude<PosMethod, "Store Credit"> | null;
  customerId: string | null;
  bankAccountId: string | null;
};

type PosState = {
  sales: PosSale[];
  branchId: string | null;
  loading: boolean;
  error: string | null;
};
let state: PosState = { sales: [], branchId: null, loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: PosState) {
  state = next;
  listeners.forEach((listener) => listener());
}

function mapReturnRow(row: SaleReturnRowWithStaff): PosReturn {
  return {
    id: row.id,
    date: row.returned_at.slice(0, 10),
    returnedSaleLineId: row.returned_sale_line_id,
    returned: {
      productId: row.returned_product_id,
      name: row.returned_name,
      unit: row.returned_unit,
      quantity: row.returned_quantity,
      unitPrice: Number(row.returned_unit_price),
    },
    replacement: row.replacement_product_id
      ? {
          productId: row.replacement_product_id,
          name: row.replacement_name ?? "",
          unit: row.replacement_unit ?? "",
          quantity: row.replacement_quantity ?? 0,
          unitPrice: Number(row.replacement_unit_price ?? 0),
        }
      : null,
    difference: Number(row.difference),
    resolution: row.resolution as PosReturn["resolution"],
    approvalState: row.approval_state as PosReturn["approvalState"],
    reason: row.reason,
    processedBy: row.staff?.name ?? "Unknown",
    paymentMethod: (row.payment_method as PosReturn["paymentMethod"]) ?? null,
    bankAccountId: row.bank_account_id,
    customerId: row.customer_id,
    returnGroupId: row.return_group_id,
  };
}

function mapSaleRow(row: SaleWithRelations): PosSale {
  const soldAt = new Date(row.sold_at);
  return {
    id: row.id,
    date: row.sold_at.slice(0, 10),
    time: soldAt.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }),
    customerId: row.customer_id,
    customerName: row.customer_name,
    cashier: row.cashier_staff?.name ?? "Unknown",
    branch: row.branches?.name ?? "",
    lines: [...row.sale_lines]
      .sort((a, b) => a.position - b.position)
      .map((line) => ({
        id: line.id,
        productId: line.product_id,
        name: line.name,
        unit: line.unit,
        category: line.category as PosSale["lines"][number]["category"],
        quantity: line.quantity,
        unitPrice: Number(line.unit_price),
        discount: {
          mode: line.discount_mode as DiscountMode,
          value: Number(line.discount_value),
        },
        vat: line.vat,
      })),
    saleDiscount: {
      mode: row.sale_discount_mode as "amount" | "percent",
      value: Number(row.sale_discount_value),
    },
    vatMode: row.vat_mode as PosSale["vatMode"],
    vatRate: Number(row.vat_rate),
    payments: row.sale_payments.map((payment) => ({
      id: payment.id,
      method: payment.method as PosSale["payments"][number]["method"],
      amount: Number(payment.amount),
      reference: payment.reference || undefined,
      bankAccountId: payment.bank_account_id,
    })),
    returns: [...row.sale_returns]
      .sort((a, b) => b.returned_at.localeCompare(a.returned_at))
      .map(mapReturnRow),
    notes: row.notes,
    voidedAt: row.voided_at,
    voidedBy: row.voider_staff?.name ?? null,
    voidReason: row.void_reason,
  };
}

let loadPromise: Promise<void> | null = null;
async function loadSales() {
  const [branchResult, salesResult] = await Promise.all([
    supabase.from("branches").select("id").limit(1).single(),
    supabase
      .from("sales")
      .select(
        // sales has three FKs into staff (cashier, override_authorized_by
        // as of Session 9, voided_by as of the void feature) — staff(name)
        // alone is an ambiguous embed PostgREST rejects with PGRST201, so
        // each embed we want must name its FK explicitly. sale_returns still
        // has only one FK into staff (processed_by), so that embed stays
        // unqualified.
        "*, branches(name), cashier_staff:staff!sales_cashier_fkey(name), voider_staff:staff!sales_voided_by_fkey(name), sale_lines(*), sale_payments(*), sale_returns(*, staff(name))",
      )
      .order("sold_at", { ascending: false }),
  ]);
  if (branchResult.error) throw branchResult.error;
  if (salesResult.error) throw salesResult.error;
  setState({
    sales: (salesResult.data as unknown as SaleWithRelations[]).map(mapSaleRow),
    branchId: branchResult.data.id,
    loading: false,
    error: null,
  });
}
function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadSales().catch((error) => {
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
export function usePosSales() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
async function getBranchId() {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

/** Insert-only receipt creation. The RPC has no id or total parameter: receipt
 * numbers, VAT rate and total remain database-owned, and stock is deducted
 * atomically before the receipt can commit. */
export async function createPosSale(sale: NewPosSale): Promise<PosSale> {
  const branchId = await getBranchId();
  const { data, error } = await supabase.rpc("create_sale", {
    p_branch_id: branchId,
    // supabase's generated RPC input type loses nullable PostgreSQL arguments;
    // the function intentionally receives JSON null for walk-in customers.
    p_customer_id: sale.customerId as unknown as string,
    p_customer_name: sale.customerName,
    p_sale_discount_mode: sale.saleDiscount.mode,
    p_sale_discount_value: sale.saleDiscount.value,
    p_vat_mode: sale.vatMode,
    p_lines: sale.lines.map((line) => ({
      product_id: line.productId,
      name: line.name,
      unit: line.unit,
      category: line.category,
      quantity: line.quantity,
      unit_price: line.unitPrice,
      discount_mode: line.discount.mode,
      discount_value: line.discount.value,
      vat: line.vat,
    })),
    p_payments: sale.payments.map((payment) => ({
      method: payment.method,
      amount: payment.amount,
      reference: payment.reference ?? "",
      bank_account_id: payment.bankAccountId ?? null,
      deposit_id: payment.depositId ?? null,
    })),
    p_override_ticket: (sale.overrideTicket ?? null) as unknown as string,
    p_notes: sale.notes,
  });
  if (error) throw error;
  const createdId = (Array.isArray(data) ? data[0] : data)?.id;
  if (!createdId) throw new Error("Sale was created but no receipt number was returned.");
  await reload();
  const created = state.sales.find((item) => item.id === createdId);
  if (!created) throw new Error("Sale was created but could not be loaded.");
  return created;
}

/** A return/exchange is a database transaction: for each line it restores the
 * returned item and, if a replacement was chosen, check-then-deducts it under
 * row locks, then posts that line's own journal entry. Every line in one call
 * shares a return_group_id so the history reads as a single customer event.
 * Handles one line or many identically — a single-line return is just a batch
 * of one. */
export async function createPosReturnBatch(saleId: string, batch: NewReturnBatch) {
  const { error } = await supabase.rpc("create_sale_return_batch", {
    p_sale_id: saleId,
    p_lines: batch.lines.map((l) => ({
      returned_sale_line_id: l.returnedSaleLineId,
      returned_quantity: l.returnedQuantity,
      replacement_product_id: l.replacement?.productId ?? null,
      replacement_quantity: l.replacement?.quantity ?? null,
    })),
    p_reason: batch.reason,
    p_refund_choice: batch.refundChoice,
    p_payment_method: (batch.paymentMethod ?? null) as unknown as string,
    p_customer_id: (batch.customerId ?? null) as unknown as string,
    p_bank_account_id: (batch.bankAccountId ?? null) as unknown as string,
  });
  if (error) throw error;
  await reload();
}

/** Manager-only. Voids a mistaken sale: reverses its ledger entry, restores
 * its stock (a 'Void' movement), and marks it dead. Rejected server-side for
 * a non-Manager, a blank reason, a sale from a closed day, a sale with
 * returns against it, or one older than 7 days. */
export async function voidSale(saleId: string, reason: string) {
  const { error } = await supabase.rpc("void_sale", {
    p_sale_id: saleId,
    p_reason: reason,
  });
  if (error) throw error;
  await reload();
}

export { noDiscount };
