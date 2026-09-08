import { useMemo } from "react";

import { TODAY } from "@/data/dashboard";
import type { Expense } from "@/data/expenses";
import { useExpenses } from "@/data/expenses-store";
import {
  effectiveThreshold,
  hasCost,
  hasPrice,
  stockStatus,
  useInventory,
} from "@/data/inventory-store";
import type { Category, Product } from "@/data/inventory";
import { invoiceTotals, type Invoice } from "@/data/invoices";
import {
  discountAmount,
  lineGross as posLineGross,
  lineNet as posLineNet,
  lineTaxable,
  posTotals,
  round2,
  type PosSale,
} from "@/data/pos";
import { usePosSales } from "@/data/pos-store";
import { useSales } from "@/data/sales-store";

/* ------------------------------------------------------------------ filters */

export type RangePreset = "today" | "week" | "month" | "quarter" | "year" | "all" | "custom";

export type ReportFilters = {
  preset: RangePreset;
  from: string;
  to: string;
  category: string;
  customerId: string;
  staff: string;
};

const iso = (d: Date) => d.toISOString().slice(0, 10);
const day = (value: string) => new Date(`${value}T00:00:00Z`);
const addDays = (value: string, n: number) => {
  const d = day(value);
  d.setUTCDate(d.getUTCDate() + n);
  return iso(d);
};

export function presetRange(preset: RangePreset): { from: string; to: string } {
  const today = TODAY();
  const d = day(today);
  switch (preset) {
    case "today":
      return { from: today, to: today };
    case "week": {
      const dow = (d.getUTCDay() + 6) % 7; // Monday start
      return { from: addDays(today, -dow), to: today };
    }
    case "month":
      return { from: `${today.slice(0, 7)}-01`, to: today };
    case "quarter": {
      const q = Math.floor(d.getUTCMonth() / 3) * 3 + 1;
      return { from: `${today.slice(0, 4)}-${String(q).padStart(2, "0")}-01`, to: today };
    }
    case "year":
      return { from: `${today.slice(0, 4)}-01-01`, to: today };
    default:
      return { from: "", to: "" };
  }
}

export const PRESET_LABELS: Array<{ id: RangePreset; label: string }> = [
  { id: "today", label: "Today" },
  { id: "week", label: "This week" },
  { id: "month", label: "This month" },
  { id: "quarter", label: "This quarter" },
  { id: "year", label: "This year" },
  { id: "all", label: "All time" },
];

export function defaultFilters(): ReportFilters {
  return {
    preset: "month",
    ...presetRange("month"),
    category: "all",
    customerId: "all",
    staff: "all",
  };
}

/* --------------------------------------------------------- normalised model */

export type TxnKind = "Invoice" | "POS";

export type TxnLine = {
  productId: string | null;
  name: string;
  unit: string;
  category: string;
  quantity: number;
  unitPrice: number;
  gross: number;
  /** discount applied directly on the line */
  lineDiscount: number;
  /** share of the document-level discount allocated to this line */
  allocatedDiscount: number;
  /** revenue excluding VAT, after every discount */
  net: number;
  /** treated as 0 when costIncomplete is true — never trust this alone */
  cost: number;
  /** true when the matched product has no recorded cost price (or no
   * product matched at all) — cost above is an estimate, not a fact */
  costIncomplete: boolean;
  taxable: boolean;
};

export type TxnPayment = { method: string; amount: number; date: string };

export type Txn = {
  kind: TxnKind;
  id: string;
  date: string;
  customerId: string | null;
  customerName: string;
  staff: string;
  lines: TxnLine[];
  payments: TxnPayment[];
  lineDiscounts: number;
  docDiscount: number;
  net: number;
  vat: number;
  total: number;
  paid: number;
  balance: number;
  dueDate?: string;
};

/** Never returns a bare number — a missing product match and a matched
 * product with no recorded cost price both mean "we don't actually know
 * this," and every caller needs to be able to tell that apart from a real,
 * confirmed cost of 0. `cost` is 0 in the incomplete case purely so
 * existing arithmetic can keep summing without a null check at every use
 * site; `complete` is what callers must check before trusting the figure. */
function costOf(
  products: Product[],
  productId: string | null,
  name: string,
): { cost: number; complete: boolean } {
  const byId = productId ? products.find((p) => p.id === productId) : undefined;
  const match = byId ?? products.find((p) => p.name === name);
  if (match && hasCost(match)) return { cost: match.cost, complete: true };
  return { cost: 0, complete: false };
}

function categoryOf(products: Product[], productId: string | null, fallback = "Uncategorised") {
  const match = productId ? products.find((p) => p.id === productId) : undefined;
  return match?.category ?? fallback;
}

function fromInvoice(invoice: Invoice, products: Product[]): Txn {
  const totals = invoiceTotals(invoice);
  const subtotal = totals.subtotal;
  const share = subtotal > 0 ? totals.invoiceDiscount / subtotal : 0;

  const lines: TxnLine[] = invoice.lines.map((l) => {
    const gross = round2(l.quantity * l.unitPrice);
    const lineDiscount = round2(Math.min(l.discount, gross));
    const afterLine = round2(gross - lineDiscount);
    const allocated = round2(afterLine * share);
    const costInfo = costOf(products, l.productId, l.name);
    return {
      productId: l.productId,
      name: l.name,
      unit: l.unit,
      category: categoryOf(products, l.productId),
      quantity: l.quantity,
      unitPrice: l.unitPrice,
      gross,
      lineDiscount,
      allocatedDiscount: allocated,
      net: round2(afterLine - allocated),
      cost: round2(costInfo.cost * l.quantity),
      costIncomplete: !costInfo.complete,
      taxable: l.vat,
    };
  });

  return {
    kind: "Invoice",
    id: invoice.id,
    date: invoice.date,
    dueDate: invoice.dueDate,
    customerId: invoice.customerId,
    customerName: invoice.customerName,
    staff: invoice.issuedBy,
    lines,
    payments: invoice.payments.map((p) => ({ method: p.method, amount: p.amount, date: p.date })),
    lineDiscounts: totals.lineDiscounts,
    docDiscount: totals.invoiceDiscount,
    net: totals.netAfterDiscount,
    vat: totals.vat,
    total: totals.total,
    paid: totals.paid,
    balance: totals.balance,
  };
}

function fromPosSale(sale: PosSale, products: Product[]): Txn {
  const totals = posTotals(sale);
  const share = totals.subtotal > 0 ? totals.saleDiscount / totals.subtotal : 0;

  const lines: TxnLine[] = sale.lines.map((l) => {
    const gross = posLineGross(l);
    const afterLine = posLineNet(l);
    const allocated = round2(afterLine * share);
    const costInfo = costOf(products, l.productId, l.name);
    return {
      productId: l.productId,
      name: l.name,
      unit: String(l.unit),
      category: l.category as Category,
      quantity: l.quantity,
      unitPrice: l.unitPrice,
      gross,
      lineDiscount: round2(discountAmount(l.discount, gross, l.quantity)),
      allocatedDiscount: allocated,
      net: round2(afterLine - allocated),
      cost: round2(costInfo.cost * l.quantity),
      costIncomplete: !costInfo.complete,
      taxable: lineTaxable(l, sale.vatMode),
    };
  });

  return {
    kind: "POS",
    id: sale.id,
    date: sale.date,
    customerId: sale.customerId,
    customerName: sale.customerName,
    staff: sale.cashier,
    lines,
    payments: sale.payments.map((p) => ({ method: p.method, amount: p.amount, date: sale.date })),
    lineDiscounts: totals.lineDiscounts,
    docDiscount: totals.saleDiscount,
    net: totals.net,
    vat: totals.vat,
    total: totals.total,
    paid: totals.paid,
    balance: totals.balance,
  };
}

/* --------------------------------------------------------------- row shapes */

export type PeriodRow = {
  period: string;
  transactions: number;
  gross: number;
  discounts: number;
  net: number;
  vat: number;
  total: number;
  average: number;
};
export type MarginRow = {
  name: string;
  category: string;
  quantity: number;
  revenue: number;
  cost: number;
  profit: number;
  margin: number;
  /** true if any line rolled into this row had no recorded cost price —
   * cost/profit/margin above are underestimated, not wrong-but-precise */
  costIncomplete: boolean;
};
export type AgeingRow = {
  invoice: string;
  customerId: string;
  customer: string;
  date: string;
  dueDate: string;
  total: number;
  paid: number;
  balance: number;
  daysOverdue: number;
  bucket: AgeingBucket;
};
export type AgeingBucket = "Current" | "1–30 days" | "31–60 days" | "61–90 days" | "90+ days";
export const AGEING_BUCKETS: AgeingBucket[] = [
  "Current",
  "1–30 days",
  "31–60 days",
  "61–90 days",
  "90+ days",
];
export type ProductRow = {
  name: string;
  sku: string;
  category: string;
  unit: string;
  quantity: number;
  revenue: number;
  profit: number;
  margin: number;
  transactions: number;
  stock: number;
  costIncomplete: boolean;
};
export type ValuationRow = {
  name: string;
  sku: string;
  category: string;
  unit: string;
  stock: number;
  /** null means cost price was never recorded — value below is null too,
   * not a silent 0, so this product's stock at cost is genuinely excluded
   * from stockValue rather than misreported as worthless. */
  cost: number | null;
  value: number | null;
  /** null means selling price was never recorded — same "excluded, not
   * silently zero" treatment as value/cost above. */
  retail: number | null;
  status: string;
};
export type DiscountRow = {
  document: string;
  kind: TxnKind;
  date: string;
  customer: string;
  staff: string;
  item: string;
  discount: number;
  gross: number;
  rate: number;
  level: "Line" | "Whole document";
};
export type VatRow = {
  period: string;
  taxable: number;
  exempt: number;
  vat: number;
  total: number;
};
export type MethodRow = {
  method: string;
  count: number;
  amount: number;
  share: number;
  invoices: number;
  pos: number;
};
export type ReturnRow = {
  id: string;
  date: string;
  sale: string;
  customer: string;
  staff: string;
  item: string;
  quantity: number;
  value: number;
  replacement: string;
  difference: number;
  resolution: string;
  approval: string;
  reason: string;
};
export type ExpenseCategoryRow = {
  category: string;
  count: number;
  amount: number;
  share: number;
  previous: number;
  change: number;
};
export type ExpenseMethodRow = {
  method: string;
  count: number;
  amount: number;
  share: number;
};
export type ExpensePeriodRow = {
  period: string;
  count: number;
  amount: number;
};
export type LargestExpenseRow = {
  id: string;
  date: string;
  category: string;
  description: string;
  method: string;
  recordedBy: string;
  amount: number;
  share: number;
};
export type OperatingRow = {
  line: string;
  amount: number;
  ofRevenue: number;
  note: string;
};

/* ------------------------------------------------------------------ bucket */

function monthKey(date: string) {
  return date.slice(0, 7);
}

function periodLabel(key: string, grain: "day" | "week" | "month") {
  if (grain === "month") {
    return day(`${key}-01`).toLocaleString("en-GB", {
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    });
  }
  if (grain === "week") {
    return `Week of ${day(key).toLocaleString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" })}`;
  }
  return day(key).toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  });
}

function bucketKey(date: string, grain: "day" | "week" | "month") {
  if (grain === "month") return monthKey(date);
  if (grain === "week") {
    const d = day(date);
    const dow = (d.getUTCDay() + 6) % 7;
    return addDays(date, -dow);
  }
  return date;
}

/* -------------------------------------------------------------------- hook */

export function useReports(filters: ReportFilters) {
  const { invoices, customers } = useSales();
  const { sales } = usePosSales();
  const { products, defaultThreshold } = useInventory();
  const { expenses } = useExpenses();

  return useMemo(() => {
    const today = TODAY();
    // Voided sales / invoices are erased transactions — their ledger is
    // reversed and they must not count toward any report figure.
    const all: Txn[] = [
      ...invoices.filter((i) => !i.voidedAt).map((i) => fromInvoice(i, products)),
      ...sales.filter((s) => !s.voidedAt).map((s) => fromPosSale(s, products)),
    ];

    const inRange = (date: string) =>
      (!filters.from || date >= filters.from) && (!filters.to || date <= filters.to);

    const scoped = all
      .filter((t) => inRange(t.date))
      .filter((t) => filters.customerId === "all" || t.customerId === filters.customerId)
      .filter((t) => filters.staff === "all" || t.staff === filters.staff);

    const matchesCategory = (line: TxnLine) =>
      filters.category === "all" || line.category === filters.category;

    /* period grain */
    const dates = scoped.map((t) => t.date).sort();
    const first = filters.from || dates[0] || today;
    const last = filters.to || dates[dates.length - 1] || today;
    const spanDays = Math.round((day(last).getTime() - day(first).getTime()) / 86400000);
    const grain: "day" | "week" | "month" =
      spanDays <= 31 ? "day" : spanDays <= 120 ? "week" : "month";

    /* ---------------------------------------------------- sales summary */
    const periodMap = new Map<string, PeriodRow & { key: string }>();
    for (const t of scoped) {
      const key = bucketKey(t.date, grain);
      const row = periodMap.get(key) ?? {
        key,
        period: periodLabel(key, grain),
        transactions: 0,
        gross: 0,
        discounts: 0,
        net: 0,
        vat: 0,
        total: 0,
        average: 0,
      };
      row.transactions += 1;
      row.gross += t.lines.reduce((s, l) => s + l.gross, 0);
      row.discounts += t.lineDiscounts + t.docDiscount;
      row.net += t.net;
      row.vat += t.vat;
      row.total += t.total;
      periodMap.set(key, row);
    }
    const salesByPeriod: PeriodRow[] = [...periodMap.values()]
      .sort((a, b) => (a.key < b.key ? -1 : 1))
      .map(({ key: _key, ...r }) => ({
        ...r,
        average: r.transactions ? round2(r.total / r.transactions) : 0,
      }));

    const revenue = round2(scoped.reduce((s, t) => s + t.total, 0));
    const netRevenue = round2(scoped.reduce((s, t) => s + t.net, 0));
    const txCount = scoped.length;
    const invoiceCount = scoped.filter((t) => t.kind === "Invoice").length;
    const posCount = scoped.filter((t) => t.kind === "POS").length;
    const averageSale = txCount ? round2(revenue / txCount) : 0;

    /* --------------------------------------------------- profit & margin */
    const marginMap = new Map<string, MarginRow>();
    let totalRevenue = 0;
    let totalCost = 0;
    let costDataIncomplete = false;
    for (const t of scoped) {
      for (const l of t.lines) {
        if (!matchesCategory(l)) continue;
        totalRevenue += l.net;
        totalCost += l.cost;
        if (l.costIncomplete) costDataIncomplete = true;
        const row = marginMap.get(l.name) ?? {
          name: l.name,
          category: l.category,
          quantity: 0,
          revenue: 0,
          cost: 0,
          profit: 0,
          margin: 0,
          costIncomplete: false,
        };
        row.quantity += l.quantity;
        row.revenue += l.net;
        row.cost += l.cost;
        if (l.costIncomplete) row.costIncomplete = true;
        marginMap.set(l.name, row);
      }
    }
    const marginRows: MarginRow[] = [...marginMap.values()]
      .map((r) => ({
        ...r,
        revenue: round2(r.revenue),
        cost: round2(r.cost),
        profit: round2(r.revenue - r.cost),
        margin: r.revenue > 0 ? round2(((r.revenue - r.cost) / r.revenue) * 100) : 0,
      }))
      .sort((a, b) => b.profit - a.profit);

    const incompleteCostProductCount = marginRows.filter((r) => r.costIncomplete).length;

    const categoryMap = new Map<string, MarginRow>();
    for (const r of marginRows) {
      const row = categoryMap.get(r.category) ?? {
        name: r.category,
        category: r.category,
        quantity: 0,
        revenue: 0,
        cost: 0,
        profit: 0,
        margin: 0,
        costIncomplete: false,
      };
      row.quantity += r.quantity;
      row.revenue += r.revenue;
      row.cost += r.cost;
      if (r.costIncomplete) row.costIncomplete = true;
      categoryMap.set(r.category, row);
    }
    const marginByCategory: MarginRow[] = [...categoryMap.values()]
      .map((r) => ({
        ...r,
        revenue: round2(r.revenue),
        cost: round2(r.cost),
        profit: round2(r.revenue - r.cost),
        margin: r.revenue > 0 ? round2(((r.revenue - r.cost) / r.revenue) * 100) : 0,
      }))
      .sort((a, b) => b.profit - a.profit);

    // grossProfit/grossMargin still sum every line, treating an incomplete
    // cost as 0 for the estimate (so the figures stay usable rather than
    // going blank) — costDataIncomplete is what makes that estimate honest
    // instead of silently passing as a confirmed number. See reports.tsx
    // for how this is surfaced.
    const grossProfit = round2(totalRevenue - totalCost);
    const grossMargin = totalRevenue > 0 ? round2((grossProfit / totalRevenue) * 100) : 0;

    /* --------------------------------------------------------- debtors */
    const ageing: AgeingRow[] = scoped
      .filter((t) => t.kind === "Invoice" && t.balance > 0.009)
      .map((t) => {
        const due = t.dueDate ?? t.date;
        const daysOverdue = Math.max(
          0,
          Math.round((day(today).getTime() - day(due).getTime()) / 86400000),
        );
        const bucket: AgeingBucket =
          daysOverdue <= 0
            ? "Current"
            : daysOverdue <= 30
              ? "1–30 days"
              : daysOverdue <= 60
                ? "31–60 days"
                : daysOverdue <= 90
                  ? "61–90 days"
                  : "90+ days";
        return {
          invoice: t.id,
          customerId: t.customerId ?? "",
          customer: t.customerName,
          date: t.date,
          dueDate: due,
          total: t.total,
          paid: t.paid,
          balance: t.balance,
          daysOverdue,
          bucket,
        };
      })
      .sort((a, b) => b.daysOverdue - a.daysOverdue || b.balance - a.balance);

    const ageingSummary = AGEING_BUCKETS.map((bucket) => {
      const rows = ageing.filter((r) => r.bucket === bucket);
      return {
        bucket,
        invoices: rows.length,
        amount: round2(rows.reduce((s, r) => s + r.balance, 0)),
      };
    });
    const receivables = round2(ageing.reduce((s, r) => s + r.balance, 0));
    const overdue = round2(
      ageing.filter((r) => r.bucket !== "Current").reduce((s, r) => s + r.balance, 0),
    );

    /* ---------------------------------------------- product performance */
    const perfMap = new Map<string, ProductRow & { docs: Set<string> }>();
    for (const t of scoped) {
      for (const l of t.lines) {
        if (!matchesCategory(l)) continue;
        const product =
          products.find((p) => p.id === l.productId) ?? products.find((p) => p.name === l.name);
        const key = product?.id ?? l.name;
        const row = perfMap.get(key) ?? {
          name: l.name,
          sku: product?.sku ?? "—",
          category: l.category,
          unit: l.unit,
          quantity: 0,
          revenue: 0,
          profit: 0,
          margin: 0,
          transactions: 0,
          stock: product?.stock ?? 0,
          costIncomplete: false,
          docs: new Set<string>(),
        };
        row.quantity += l.quantity;
        row.revenue += l.net;
        row.profit += l.net - l.cost;
        if (l.costIncomplete) row.costIncomplete = true;
        row.docs.add(t.id);
        perfMap.set(key, row);
      }
    }
    // Products with no sales in range still matter — they are the slow movers.
    for (const p of products) {
      if (filters.category !== "all" && p.category !== filters.category) continue;
      if (perfMap.has(p.id)) continue;
      perfMap.set(p.id, {
        name: p.name,
        sku: p.sku,
        category: p.category,
        unit: p.unit,
        quantity: 0,
        revenue: 0,
        profit: 0,
        margin: 0,
        transactions: 0,
        stock: p.stock,
        costIncomplete: !hasCost(p),
        docs: new Set<string>(),
      });
    }
    const productRows: ProductRow[] = [...perfMap.values()]
      .map(({ docs, ...r }) => ({
        ...r,
        revenue: round2(r.revenue),
        profit: round2(r.profit),
        margin: r.revenue > 0 ? round2((r.profit / r.revenue) * 100) : 0,
        transactions: docs.size,
      }))
      .sort((a, b) => b.revenue - a.revenue);

    /* -------------------------------------------------------- valuation */
    const valuation: ValuationRow[] = products
      .filter((p) => filters.category === "all" || p.category === filters.category)
      .map((p) => ({
        name: p.name,
        sku: p.sku,
        category: p.category,
        unit: p.unit,
        stock: p.stock,
        cost: p.cost,
        value: hasCost(p) ? round2(p.stock * p.cost) : null,
        retail: hasPrice(p) ? round2(p.stock * p.price) : null,
        status: stockStatus(p, defaultThreshold),
      }))
      .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));
    // Stock at cost only sums products with a recorded cost price — a
    // missing cost is excluded, never silently treated as 0, which would
    // understate the real figure without any sign it's incomplete. Stock
    // at retail gets the identical treatment for a missing selling price.
    const stockValue = round2(valuation.reduce((s, r) => s + (r.value ?? 0), 0));
    const retailValue = round2(valuation.reduce((s, r) => s + (r.retail ?? 0), 0));
    const valuationIncompleteCount = valuation.filter((r) => r.value === null).length;
    const retailIncompleteCount = valuation.filter((r) => r.retail === null).length;
    // "Potential gross profit" pairs retail against cost for the same set
    // of products — comparing it against the full retailValue above (which
    // includes products missing either figure) would overstate potential
    // profit by counting a partial value against zero on the other side.
    // Scoped to only products where BOTH cost and price are known.
    const fullyPricedRows = valuation.filter((r) => r.value !== null && r.retail !== null);
    const retailValueOfCostedItems = round2(
      fullyPricedRows.reduce((s, r) => s + (r.retail ?? 0), 0),
    );
    const costOfFullyPricedItems = round2(fullyPricedRows.reduce((s, r) => s + (r.value ?? 0), 0));
    const potentialGrossProfit = round2(retailValueOfCostedItems - costOfFullyPricedItems);
    const lowStock = products.filter(
      (p) => p.stock <= effectiveThreshold(p, defaultThreshold),
    ).length;

    /* -------------------------------------------------------- discounts */
    const discountRows: DiscountRow[] = [];
    for (const t of scoped) {
      for (const l of t.lines) {
        if (!matchesCategory(l)) continue;
        if (l.lineDiscount <= 0.009) continue;
        discountRows.push({
          document: t.id,
          kind: t.kind,
          date: t.date,
          customer: t.customerName,
          staff: t.staff,
          item: l.name,
          discount: l.lineDiscount,
          gross: l.gross,
          rate: l.gross > 0 ? round2((l.lineDiscount / l.gross) * 100) : 0,
          level: "Line",
        });
      }
      if (t.docDiscount > 0.009 && (filters.category === "all" || t.lines.some(matchesCategory))) {
        const gross = round2(t.lines.reduce((s, l) => s + l.gross, 0));
        discountRows.push({
          document: t.id,
          kind: t.kind,
          date: t.date,
          customer: t.customerName,
          staff: t.staff,
          item: `Whole ${t.kind === "Invoice" ? "invoice" : "sale"} (${t.lines.length} items)`,
          discount: t.docDiscount,
          gross,
          rate: gross > 0 ? round2((t.docDiscount / gross) * 100) : 0,
          level: "Whole document",
        });
      }
    }
    discountRows.sort((a, b) => b.discount - a.discount);
    const discountTotal = round2(discountRows.reduce((s, r) => s + r.discount, 0));
    const discountedDocs = new Set(discountRows.map((r) => r.document)).size;

    const discountByStaff = [...new Set(discountRows.map((r) => r.staff))]
      .map((staff) => {
        const rows = discountRows.filter((r) => r.staff === staff);
        return {
          staff,
          count: rows.length,
          amount: round2(rows.reduce((s, r) => s + r.discount, 0)),
          largest: round2(Math.max(...rows.map((r) => r.discount))),
        };
      })
      .sort((a, b) => b.amount - a.amount);

    /* --------------------------------------------------------------- VAT */
    const vatMap = new Map<string, VatRow & { key: string }>();
    for (const t of scoped) {
      const key = bucketKey(t.date, grain);
      const row = vatMap.get(key) ?? {
        key,
        period: periodLabel(key, grain),
        taxable: 0,
        exempt: 0,
        vat: 0,
        total: 0,
      };
      for (const l of t.lines) {
        const netAfter = l.net;
        if (l.taxable) row.taxable += netAfter;
        else row.exempt += netAfter;
      }
      row.vat += t.vat;
      row.total += t.total;
      vatMap.set(key, row);
    }
    const vatRows: VatRow[] = [...vatMap.values()]
      .sort((a, b) => (a.key < b.key ? -1 : 1))
      .map(({ key: _key, ...r }) => ({
        period: r.period,
        taxable: round2(r.taxable),
        exempt: round2(r.exempt),
        vat: round2(r.vat),
        total: round2(r.total),
      }));
    const vatCollected = round2(vatRows.reduce((s, r) => s + r.vat, 0));
    const taxableSales = round2(vatRows.reduce((s, r) => s + r.taxable, 0));
    const exemptSales = round2(vatRows.reduce((s, r) => s + r.exempt, 0));

    /* --------------------------------------------------------- payments */
    const methodMap = new Map<string, MethodRow>();
    for (const t of scoped) {
      for (const p of t.payments) {
        const row = methodMap.get(p.method) ?? {
          method: p.method,
          count: 0,
          amount: 0,
          share: 0,
          invoices: 0,
          pos: 0,
        };
        row.count += 1;
        row.amount += p.amount;
        if (t.kind === "Invoice") row.invoices += p.amount;
        else row.pos += p.amount;
        methodMap.set(p.method, row);
      }
    }
    const collected = round2([...methodMap.values()].reduce((s, r) => s + r.amount, 0));
    const methodRows: MethodRow[] = [...methodMap.values()]
      .map((r) => ({
        ...r,
        amount: round2(r.amount),
        invoices: round2(r.invoices),
        pos: round2(r.pos),
        share: collected > 0 ? round2((r.amount / collected) * 100) : 0,
      }))
      .sort((a, b) => b.amount - a.amount);
    const splitPayments = scoped.filter((t) => t.payments.length > 1).length;

    /* ---------------------------------------------------------- returns */
    const returnRows: ReturnRow[] = sales
      .flatMap((sale) => sale.returns.map((r) => ({ sale, r })))
      .filter(({ sale, r }) => {
        if (!inRange(r.date)) return false;
        if (filters.customerId !== "all" && sale.customerId !== filters.customerId) return false;
        if (filters.staff !== "all" && sale.cashier !== filters.staff) return false;
        if (filters.category !== "all") {
          const line = sale.lines.find((l) => l.productId === r.returned.productId);
          const category =
            line?.category ?? categoryOf(products, r.returned.productId, "Uncategorised");
          if (category !== filters.category) return false;
        }
        return true;
      })
      .map(({ sale, r }) => ({
        id: r.id,
        date: r.date,
        sale: sale.id,
        customer: sale.customerName,
        staff: sale.cashier,
        item: `${r.returned.name} (${r.returned.quantity} ${r.returned.unit})`,
        quantity: r.returned.quantity,
        value: round2(r.returned.quantity * r.returned.unitPrice),
        replacement: r.replacement
          ? `${r.replacement.name} (${r.replacement.quantity} ${r.replacement.unit})`
          : "—",
        difference: r.difference,
        resolution: r.resolution,
        approval: r.approvalState,
        reason: r.reason,
      }))
      .sort((a, b) => (a.date < b.date ? 1 : -1));

    const returnedValue = round2(returnRows.reduce((s, r) => s + r.value, 0));
    const pendingApprovals = returnRows.filter((r) => r.approval !== "Not required").length;
    const returnRate = revenue > 0 ? round2((returnedValue / revenue) * 100) : 0;

    /* --------------------------------------------------------- expenses */
    const matchesStaff = (e: Expense) => filters.staff === "all" || e.recordedBy === filters.staff;

    // A voided expense is an erasure — it never happened, so it's excluded
    // from every figure this report derives, not just filtered out visually.
    const expensesInRange = expenses
      .filter((e) => !e.voidedAt && inRange(e.date) && matchesStaff(e))
      .sort((a, b) => (a.date < b.date ? 1 : -1));

    // Equivalent window immediately before the selected one.
    const spanLength = spanDays + 1;
    const prevTo = filters.from ? addDays(filters.from, -1) : "";
    const prevFrom = prevTo ? addDays(prevTo, -(spanLength - 1)) : "";
    const previousExpenses = prevFrom
      ? expenses.filter(
          (e) => !e.voidedAt && e.date >= prevFrom && e.date <= prevTo && matchesStaff(e),
        )
      : [];

    const expenseTotal = round2(expensesInRange.reduce((s, e) => s + e.amount, 0));
    const previousExpenseTotal = round2(previousExpenses.reduce((s, e) => s + e.amount, 0));
    const expenseChange =
      previousExpenseTotal > 0
        ? round2(((expenseTotal - previousExpenseTotal) / previousExpenseTotal) * 100)
        : 0;

    const expenseCategories: ExpenseCategoryRow[] = [
      ...new Set(expensesInRange.map((e) => e.category)),
    ]
      .map((category) => {
        const rows = expensesInRange.filter((e) => e.category === category);
        const amount = round2(rows.reduce((s, e) => s + e.amount, 0));
        const previous = round2(
          previousExpenses.filter((e) => e.category === category).reduce((s, e) => s + e.amount, 0),
        );
        return {
          category,
          count: rows.length,
          amount,
          share: expenseTotal > 0 ? round2((amount / expenseTotal) * 100) : 0,
          previous,
          change: previous > 0 ? round2(((amount - previous) / previous) * 100) : 0,
        };
      })
      .sort((a, b) => b.amount - a.amount);

    const expenseMethods: ExpenseMethodRow[] = [...new Set(expensesInRange.map((e) => e.method))]
      .map((method) => {
        const rows = expensesInRange.filter((e) => e.method === method);
        const amount = round2(rows.reduce((s, e) => s + e.amount, 0));
        return {
          method: String(method),
          count: rows.length,
          amount,
          share: expenseTotal > 0 ? round2((amount / expenseTotal) * 100) : 0,
        };
      })
      .sort((a, b) => b.amount - a.amount);

    const expensePeriodMap = new Map<string, ExpensePeriodRow & { key: string }>();
    for (const e of expensesInRange) {
      const key = bucketKey(e.date, grain);
      const row = expensePeriodMap.get(key) ?? {
        key,
        period: periodLabel(key, grain),
        count: 0,
        amount: 0,
      };
      row.count += 1;
      row.amount += e.amount;
      expensePeriodMap.set(key, row);
    }
    const expenseByPeriod: ExpensePeriodRow[] = [...expensePeriodMap.values()]
      .sort((a, b) => (a.key < b.key ? -1 : 1))
      .map(({ key: _key, ...r }) => ({ ...r, amount: round2(r.amount) }));

    const largestExpenses: LargestExpenseRow[] = expensesInRange
      .slice()
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 15)
      .map((e) => ({
        id: e.id,
        date: e.date,
        category: e.category,
        description: e.description,
        method: String(e.method),
        recordedBy: e.recordedBy,
        amount: e.amount,
        share: expenseTotal > 0 ? round2((e.amount / expenseTotal) * 100) : 0,
      }));

    const largestExpense = largestExpenses[0] ?? null;
    const averageExpense = expensesInRange.length
      ? round2(expenseTotal / expensesInRange.length)
      : 0;

    /* -------------------------------------------------- operating margin */
    const marginRevenue = round2(totalRevenue);
    const operatingProfit = round2(grossProfit - expenseTotal);
    const operatingMargin = marginRevenue > 0 ? round2((operatingProfit / marginRevenue) * 100) : 0;
    const expenseRatio = marginRevenue > 0 ? round2((expenseTotal / marginRevenue) * 100) : 0;

    const operatingRows: OperatingRow[] = [
      {
        line: "Revenue (ex VAT, after discounts)",
        amount: marginRevenue,
        ofRevenue: marginRevenue > 0 ? 100 : 0,
        note: `${txCount} transactions in the period`,
      },
      {
        line: "Cost of goods sold",
        amount: round2(-totalCost),
        ofRevenue: marginRevenue > 0 ? round2((-totalCost / marginRevenue) * 100) : 0,
        note: costDataIncomplete
          ? "At current product cost price — underestimated, some items have no recorded cost"
          : "At current product cost price",
      },
      {
        line: "Gross profit",
        amount: grossProfit,
        ofRevenue: grossMargin,
        note: "From the Profit & Margin report",
      },
      {
        line: "Recorded expenses",
        amount: round2(-expenseTotal),
        ofRevenue: marginRevenue > 0 ? round2((-expenseTotal / marginRevenue) * 100) : 0,
        note: `${expensesInRange.length} expenses logged in Expenses`,
      },
      {
        line: "Operating margin (recorded expenses)",
        amount: operatingProfit,
        ofRevenue: operatingMargin,
        note: "Not net profit — payroll and untracked costs are excluded",
      },
    ];

    const previousFrom = prevFrom;
    const previousTo = prevTo;

    /* ------------------------------------------------------- facet lists */
    const staffList = [...new Set([...all.map((t) => t.staff)].filter(Boolean))].sort();
    const customerList = customers
      .map((c) => ({ id: c.id, name: c.name }))
      .sort((a, b) => a.name.localeCompare(b.name));

    return {
      grain,
      salesByPeriod,
      revenue,
      netRevenue,
      txCount,
      invoiceCount,
      posCount,
      averageSale,
      marginRows,
      marginByCategory,
      grossProfit,
      grossMargin,
      costDataIncomplete,
      incompleteCostProductCount,
      totalCost: round2(totalCost),
      ageing,
      ageingSummary,
      receivables,
      overdue,
      productRows,
      valuation,
      stockValue,
      retailValue,
      retailValueOfCostedItems,
      potentialGrossProfit,
      valuationIncompleteCount,
      retailIncompleteCount,
      lowStock,
      discountRows,
      discountTotal,
      discountedDocs,
      discountByStaff,
      vatRows,
      vatCollected,
      taxableSales,
      exemptSales,
      methodRows,
      collected,
      splitPayments,
      returnRows,
      returnedValue,
      pendingApprovals,
      returnRate,
      staffList,
      customerList,
      expenseRows: expensesInRange,
      expenseTotal,
      previousExpenseTotal,
      previousFrom,
      previousTo,
      expenseChange,
      expenseCategories,
      expenseMethods,
      expenseByPeriod,
      largestExpenses,
      largestExpense,
      averageExpense,
      expenseCount: expensesInRange.length,
      marginRevenue,
      operatingProfit,
      operatingMargin,
      expenseRatio,
      operatingRows,
    };
  }, [invoices, sales, customers, products, defaultThreshold, expenses, filters]);
}

export type ReportsData = ReturnType<typeof useReports>;
