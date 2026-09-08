export type InvoiceStatus = "Paid" | "Partly paid" | "Unpaid";

export type PaymentMethod = "Cash" | "Mobile Money" | "Bank Transfer" | "Cheque" | "Store Credit";

export const PAYMENT_METHODS: PaymentMethod[] = ["Cash", "Mobile Money", "Bank Transfer", "Cheque"];

/** Invoice payment methods that settle into a real bank account and need a
 * bank account chosen per payment. */
export const INVOICE_BANK_METHODS: PaymentMethod[] = ["Bank Transfer", "Cheque"];

export const DEFAULT_VAT_RATE = 20;
export const DEFAULT_WHT_RATE = 3;

export type InvoiceLine = {
  id: string;
  productId: string | null;
  name: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  /** discount on this line, in GHS */
  discount: number;
  /** whether VAT applies to this line */
  vat: boolean;
};

export type InvoicePayment = {
  id: string;
  date: string;
  amount: number;
  // "WHT Credit" / "Deposit" are never offered as a choice in a
  // payment-method dropdown (PAYMENT_METHODS/PaymentMethod stay the
  // user-choosable set). "WHT Credit" is a row create_invoice() inserts
  // automatically for a WHT invoice; "Deposit" is inserted by the "Fulfil
  // with an invoice" flow, drawing down a customer_deposits row. Both are
  // widened in here only so a real one displays correctly.
  method: PaymentMethod | "WHT Credit" | "Deposit";
  reference: string;
  note?: string;
  recordedBy: string;
};

export type Invoice = {
  id: string;
  customerId: string;
  customerName: string;
  date: string;
  dueDate: string;
  branch: string;
  issuedBy: string;
  notes: string;
  lines: InvoiceLine[];
  /** discount applied to the whole invoice, in GHS */
  invoiceDiscount: number;
  vatRate: number;
  payments: InvoicePayment[];
  /** Fixed at creation, like vatRate — see create_invoice() in the Session
   * 19 migration. Never re-toggled or recomputed by an edit. */
  whtApplied: boolean;
  whtRate: number | null;
  whtAmount: number;
  /** Set when a Manager has voided this invoice (void_invoice()): the whole
   * transaction was a mistake — its ledger entries (creation + every
   * payment) are reversed, its balance zeroed, and it no longer counts.
   * null on a normal invoice. */
  voidedAt: string | null;
  voidedBy: string | null;
  voidReason: string | null;
};

export type InvoiceTotals = {
  gross: number;
  lineDiscounts: number;
  subtotal: number;
  invoiceDiscount: number;
  netAfterDiscount: number;
  vat: number;
  total: number;
  paid: number;
  balance: number;
  status: InvoiceStatus;
};

export function lineGross(line: InvoiceLine) {
  return line.quantity * line.unitPrice;
}

export function lineNet(line: InvoiceLine) {
  return Math.max(0, lineGross(line) - line.discount);
}

export function invoiceTotals(invoice: Invoice): InvoiceTotals {
  const gross = invoice.lines.reduce((sum, l) => sum + lineGross(l), 0);
  const lineDiscounts = invoice.lines.reduce(
    (sum, l) => sum + Math.min(l.discount, lineGross(l)),
    0,
  );
  const subtotal = invoice.lines.reduce((sum, l) => sum + lineNet(l), 0);
  const invoiceDiscount = Math.min(Math.max(invoice.invoiceDiscount, 0), subtotal);
  const netAfterDiscount = subtotal - invoiceDiscount;
  const ratio = subtotal > 0 ? netAfterDiscount / subtotal : 0;
  const vatBase =
    invoice.lines.filter((l) => l.vat).reduce((sum, l) => sum + lineNet(l), 0) * ratio;
  const vat = round2(vatBase * (invoice.vatRate / 100));
  const total = round2(netAfterDiscount + vat);
  const paid = round2(invoice.payments.reduce((sum, p) => sum + p.amount, 0));
  const balance = round2(Math.max(0, total - paid));

  const status: InvoiceStatus = paid <= 0 ? "Unpaid" : balance <= 0.009 ? "Paid" : "Partly paid";

  return {
    gross: round2(gross),
    lineDiscounts: round2(lineDiscounts),
    subtotal: round2(subtotal),
    invoiceDiscount: round2(invoiceDiscount),
    netAfterDiscount: round2(netAfterDiscount),
    vat,
    total,
    paid,
    balance,
    status,
  };
}

function round2(n: number) {
  return Math.round(n * 100) / 100;
}
