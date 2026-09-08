import type { Category, Unit } from "@/data/inventory";

export type PosMethod =
  "Cash" | "Mobile Money" | "Card" | "Bank Transfer" | "Store Credit" | "Deposit";

export const POS_METHODS: PosMethod[] = ["Cash", "Mobile Money", "Card", "Bank Transfer"];

/** POS payment methods that settle into a real bank account and therefore
 * need a bank account chosen per transaction (the rest map to a fixed
 * ledger account). */
export const POS_BANK_METHODS: PosMethod[] = ["Card", "Bank Transfer"];

// "amount" is a flat GHS figure off the whole line, regardless of quantity
// (its original, permanent meaning — every historical sale_lines row is this).
// "amount_per_unit" multiplies the typed figure by the line quantity, so it
// scales as quantity changes. "percent" is unchanged. Only line-item
// discounts ever use "amount_per_unit"; the sale-level discount selector
// still offers "amount"/"percent" only, and create_sale() rejects anything
// else for the whole-sale mode.
export type DiscountMode = "percent" | "amount" | "amount_per_unit";

export type Discount = {
  mode: DiscountMode;
  value: number;
};

export const noDiscount = (): Discount => ({ mode: "amount", value: 0 });

export type VatMode = "per-item" | "all" | "none";

export type PosLine = {
  id: string;
  productId: string;
  name: string;
  unit: Unit | string;
  category: Category;
  quantity: number;
  unitPrice: number;
  discount: Discount;
  /** used when the sale-level VAT mode is "per-item" */
  vat: boolean;
};

export type PosPayment = {
  id: string;
  method: PosMethod;
  amount: number;
  reference?: string;
  /** Which real bank account a Card / Bank Transfer leg settled into.
   * Required for those methods (server-enforced), null for the rest. */
  bankAccountId?: string | null;
  /** The customer_deposits row a `method: "Deposit"` leg draws down. Only
   * ever set on the one deposit leg injected by the "Fulfil with a POS
   * sale" flow — create_sale() validates it's an Open deposit for this
   * customer and flips it to Fulfilled. Null/absent on every other leg. */
  depositId?: string | null;
};

export type PosReturnLine = {
  productId: string;
  name: string;
  unit: string;
  quantity: number;
  unitPrice: number;
};

export type PosReturn = {
  id: string;
  date: string;
  /** The sale_lines.id this return was processed against — the same key
   * create_sale_return() sums prior returns by to enforce "can't return
   * more than was sold." Lets any consumer compute per-line remaining
   * quantity locally instead of trusting a line's own `quantity` (the
   * amount originally sold, not what's still returnable). */
  returnedSaleLineId: string;
  returned: PosReturnLine;
  replacement: PosReturnLine | null;
  difference: number;
  resolution: "Top-up collected" | "Cash refund" | "Store credit" | "Even exchange";
  approvalState: "Not required" | "Pending manager approval";
  reason: string;
  processedBy: string;
  /** How a "Top-up collected" difference was paid — Cash/Mobile Money/Card/
   * Bank Transfer only (never Store Credit — a top-up is real money coming
   * in, not spending an existing balance). Null for every other resolution. */
  paymentMethod: Exclude<PosMethod, "Store Credit"> | null;
  /** Which real bank account a Card / Bank Transfer top-up settled into.
   * Required for those top-up methods (server-enforced), null otherwise. */
  bankAccountId?: string | null;
  /** The customer a "Store credit" return attaches when the original sale
   * had none (a Walk-in sale) — selected or created inline on the return
   * screen. Null whenever the sale already had a customer (credit goes
   * straight to it) or the resolution isn't Store credit at all. */
  customerId: string | null;
  /** Ties this row to the other line-returns submitted in the same customer
   * transaction (create_sale_return_batch). Null for a standalone return
   * — every return processed before batching existed, and any single-line
   * one that predates it. */
  returnGroupId: string | null;
};

export type PosSale = {
  id: string;
  date: string;
  time: string;
  customerId: string | null;
  customerName: string;
  cashier: string;
  branch: string;
  lines: PosLine[];
  saleDiscount: Discount;
  vatMode: VatMode;
  vatRate: number;
  payments: PosPayment[];
  returns: PosReturn[];
  /** Optional free-text note captured at checkout — printed on the receipt
   * when non-empty, omitted entirely when blank. Same shape as
   * Invoice.notes: always a string, "" when there is no note. */
  notes: string;
  /** Set when a Manager has voided this sale (void_sale()): the whole
   * transaction was rung up by mistake — its ledger entry is reversed, its
   * stock is restored, and it no longer counts anywhere. null on a normal
   * sale. */
  voidedAt: string | null;
  voidedBy: string | null;
  voidReason: string | null;
};

/** A parked/held sale — a draft snapshot of what the active cart looked
 * like, not a real sale in any economic sense (no stock deduction, no
 * payment recorded, no journal entry). `lines`/`payments` mirror
 * PosLine[]/PosPayment[] exactly, so resuming one is a straight
 * `setLines(sale.lines)`/etc. with no further mapping. */
export type HeldSale = {
  id: string;
  customerId: string | null;
  customerName: string;
  lines: PosLine[];
  saleDiscount: Discount;
  vatMode: VatMode;
  payments: PosPayment[];
  heldBy: string;
  /** ISO timestamp — when it was held, not resumed. */
  heldAt: string;
};

export type PosTotals = {
  gross: number;
  lineDiscounts: number;
  subtotal: number;
  saleDiscount: number;
  net: number;
  vat: number;
  total: number;
  paid: number;
  balance: number;
  change: number;
};

export function round2(n: number) {
  return Math.round(n * 100) / 100;
}

export function discountAmount(discount: Discount, base: number, quantity = 1) {
  const raw =
    discount.mode === "percent"
      ? (base * discount.value) / 100
      : discount.mode === "amount_per_unit"
        ? discount.value * quantity
        : discount.value;
  // Clamp unchanged: a discount (any mode) can never exceed the line's gross,
  // and can never go negative.
  return round2(Math.min(Math.max(raw, 0), base));
}

export function lineGross(line: PosLine) {
  return round2(line.quantity * line.unitPrice);
}

export function lineNet(line: PosLine) {
  const gross = lineGross(line);
  return round2(gross - discountAmount(line.discount, gross, line.quantity));
}

export function lineTaxable(line: PosLine, vatMode: VatMode) {
  if (vatMode === "all") return true;
  if (vatMode === "none") return false;
  return line.vat;
}

export function posTotals(sale: {
  lines: PosLine[];
  saleDiscount: Discount;
  vatMode: VatMode;
  vatRate: number;
  payments: PosPayment[];
}): PosTotals {
  const gross = round2(sale.lines.reduce((sum, l) => sum + lineGross(l), 0));
  const subtotal = round2(sale.lines.reduce((sum, l) => sum + lineNet(l), 0));
  const lineDiscounts = round2(gross - subtotal);
  const saleDiscount = discountAmount(sale.saleDiscount, subtotal);
  const net = round2(subtotal - saleDiscount);
  const ratio = subtotal > 0 ? net / subtotal : 0;
  const vatBase =
    sale.lines.filter((l) => lineTaxable(l, sale.vatMode)).reduce((sum, l) => sum + lineNet(l), 0) *
    ratio;
  const vat = round2(vatBase * (sale.vatRate / 100));
  const total = round2(net + vat);
  const paid = round2(sale.payments.reduce((sum, p) => sum + p.amount, 0));
  const balance = round2(Math.max(0, total - paid));
  const change = round2(Math.max(0, paid - total));

  return { gross, lineDiscounts, subtotal, saleDiscount, net, vat, total, paid, balance, change };
}
