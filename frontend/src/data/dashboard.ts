import { useMemo } from "react";

import { useAccounts } from "@/data/accounts-store";
import { canViewFinancials, useAuth } from "@/data/auth-store";
import { useExpenses } from "@/data/expenses-store";
import { useInventory, effectiveThreshold, hasCost } from "@/data/inventory-store";
import { invoiceTotals, type Invoice } from "@/data/invoices";
import { ledgerForAccount, useJournalEntries } from "@/data/journal-store";
import { posTotals, type PosSale } from "@/data/pos";
import { usePosSales } from "@/data/pos-store";
import { useSales } from "@/data/sales-store";
import { getSettings, useDocumentSettings } from "@/data/settings-store";

const formatMoney = (value: number, decimals: number) => {
  const { currencySymbol } = getSettings().localisation;
  const amount = new Intl.NumberFormat("en-GH", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
  return `${currencySymbol}${amount}`;
};

export const currency = (value: number) => formatMoney(value, 0);

export const currencyPrecise = (value: number) =>
  formatMoney(value, getSettings().localisation.decimals);

/** The real current date (UTC, YYYY-MM-DD), computed fresh on every call —
 * never a frozen value. This used to be a fixed literal ("2026-07-28")
 * anchored to the local dummy/seed dataset; production has since
 * accumulated its own real, dated activity, so a frozen date silently
 * broke every "today"/date-range figure that read it. A plain top-level
 * `const` computed once from `new Date()` would only be as fresh as
 * whichever moment the module was first evaluated (once per browser page
 * load, or once per SSR server-process lifetime) — a function, called
 * fresh wherever "today" is actually needed, is what every other "today"
 * reference in this app already does (see e.g. `pos.index.tsx`'s own
 * `today()`), and is the only way this stays correct on day two without a
 * server restart. */
export const TODAY = () => new Date().toISOString().slice(0, 10);

const monthKey = (date: string) => date.slice(0, 7);

function shiftMonth(key: string, delta: number) {
  const [y, m] = key.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

function previousDay(date: string) {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

const monthLabel = (key: string) =>
  new Date(`${key}-01T00:00:00Z`).toLocaleString("en-GB", { month: "short", timeZone: "UTC" });

export type DashboardTransaction = {
  ref: string;
  party: string;
  type: "Invoice" | "Sale";
  date: string;
  amount: number;
  status: "Paid" | "Partly paid" | "Unpaid";
  href: string | null;
};

function saleStatus(paid: number, total: number): DashboardTransaction["status"] {
  if (paid <= 0) return "Unpaid";
  return total - paid <= 0.009 ? "Paid" : "Partly paid";
}

export function useDashboard() {
  const { invoices } = useSales();
  const { sales } = usePosSales();
  const { products, defaultThreshold } = useInventory();
  const { expenses } = useExpenses();
  const { staff } = useAuth();
  const { accounts } = useAccounts();
  const { entries: journalEntries } = useJournalEntries();
  // Subscribe to settings so currency/format changes re-render the numbers.
  useDocumentSettings();

  return useMemo(() => {
    // Voided sales / invoices are erased — their ledger is reversed and they
    // must not count toward any dashboard figure.
    const invoiceRows = invoices
      .filter((invoice: Invoice) => !invoice.voidedAt)
      .map((invoice: Invoice) => ({
        invoice,
        totals: invoiceTotals(invoice),
      }));
    const saleRows = sales
      .filter((sale: PosSale) => !sale.voidedAt)
      .map((sale: PosSale) => ({ sale, totals: posTotals(sale) }));

    const today = TODAY();
    const thisMonth = monthKey(today);
    const lastMonth = shiftMonth(thisMonth, -1);
    const yesterday = previousDay(today);

    const sumOn = (predicate: (date: string) => boolean) =>
      invoiceRows
        .filter((r) => predicate(r.invoice.date))
        .reduce((sum, r) => sum + r.totals.total, 0) +
      saleRows.filter((r) => predicate(r.sale.date)).reduce((sum, r) => sum + r.totals.total, 0);

    const todaySales = sumOn((d) => d === today);
    const yesterdaySales = sumOn((d) => d === yesterday);
    const monthSales = sumOn((d) => monthKey(d) === thisMonth);
    const lastMonthSales = sumOn((d) => monthKey(d) === lastMonth);

    const todayCount =
      invoiceRows.filter((r) => r.invoice.date === today).length +
      saleRows.filter((r) => r.sale.date === today).length;

    // Products with no recorded cost price are excluded, not treated as
    // costing 0 — silently including them would understate this KPI with
    // no indication it's incomplete. See inventory-store.ts's hasCost().
    const inventoryValue = products.reduce(
      (sum, p) => (hasCost(p) ? sum + p.stock * p.cost : sum),
      0,
    );
    const missingCostCount = products.filter((p) => !hasCost(p)).length;
    const skuCount = products.length;
    const unitsInStock = products.reduce((sum, p) => sum + p.stock, 0);

    // The real ledger balance of 1000 Cash on Hand — not a hand-sum of
    // sale_payments/invoice_payments/expenses, which had no way to know
    // about a later cash refund (sale_returns) or any other cash-affecting
    // event this file's own author didn't happen to enumerate. The ledger
    // is provably complete (every cash-touching RPC posts to it, Session
    // 14's auto-posting), so reading its own running balance is the one
    // calculation that can never silently miss a new event type again —
    // the same reasoning financial-reports.ts's cashFlow() already
    // documented when it moved off this exact pattern.
    //
    // Only readable by roles RLS actually grants journal_entries/accounts
    // select to (Manager, Accountant, Auditor) — Attendant gets empty
    // arrays back, not an error, so canReadLedger is checked explicitly
    // rather than inferred from "the ledger came back empty" (which would
    // be indistinguishable from a real, freshly-provisioned branch with
    // zero transactions ever posted).
    const canReadLedger = canViewFinancials(staff?.role);
    const cashAccount = accounts.find((a) => a.code === "1000");
    const cashOnHand =
      canReadLedger && cashAccount
        ? (ledgerForAccount(journalEntries, cashAccount).at(-1)?.balance ?? 0)
        : 0;

    // A voided expense is an erasure — it never happened, so it must not
    // count toward either month's total.
    const monthExpenseRows = expenses.filter((e) => !e.voidedAt && monthKey(e.date) === thisMonth);
    const monthExpenses = monthExpenseRows.reduce((sum, e) => sum + e.amount, 0);
    const lastMonthExpenses = expenses
      .filter((e) => !e.voidedAt && monthKey(e.date) === lastMonth)
      .reduce((sum, e) => sum + e.amount, 0);

    const delta = (current: number, previous: number) =>
      previous > 0 ? Math.round(((current - previous) / previous) * 1000) / 10 : 0;

    const kpis = [
      {
        label: "Today's Sales",
        value: todaySales,
        delta: delta(todaySales, yesterdaySales),
        hint: `${todayCount} transaction${todayCount === 1 ? "" : "s"} today`,
        invertDelta: false,
        unavailable: false,
      },
      {
        label: "This Month's Sales",
        value: monthSales,
        delta: delta(monthSales, lastMonthSales),
        hint: `vs. ${currency(lastMonthSales)} last month`,
        invertDelta: false,
        unavailable: false,
      },
      {
        label: "Inventory Value",
        value: inventoryValue,
        delta: 0,
        hint:
          missingCostCount > 0
            ? `Excludes ${missingCostCount} product${missingCostCount === 1 ? "" : "s"} with no cost price recorded`
            : `${skuCount} SKUs · ${unitsInStock.toLocaleString("en-GH")} units in stock`,
        invertDelta: false,
        unavailable: false,
      },
      {
        label: "Cash on Hand",
        value: cashOnHand,
        delta: 0,
        hint: canReadLedger
          ? "Live balance of the ledger's Cash on Hand account"
          : "Visible to Manager, Accountant and Auditor",
        invertDelta: false,
        // Only this KPI can ever be role-gated — Attendant genuinely can't
        // read the ledger this figure now comes from, and showing a
        // silent 0 (indistinguishable from "no cash at all") would be
        // exactly the kind of quietly-wrong number this rewrite exists to
        // stop producing.
        unavailable: !canReadLedger,
      },
      {
        label: "Expenses this Month",
        value: monthExpenses,
        delta: delta(monthExpenses, lastMonthExpenses),
        hint: `${monthExpenseRows.length} expense${monthExpenseRows.length === 1 ? "" : "s"} recorded`,
        invertDelta: true,
        unavailable: false,
      },
    ];

    // Last 12 months of revenue, from the same dated records.
    const revenueSeries = Array.from({ length: 12 }, (_, i) => {
      const key = shiftMonth(thisMonth, i - 11);
      return {
        month: monthLabel(key),
        key,
        revenue: Math.round(sumOn((d) => monthKey(d) === key)),
      };
    });

    const lowStock = products
      .filter((p) => p.stock <= effectiveThreshold(p, defaultThreshold))
      .map((p) => ({
        id: p.id,
        name: p.name,
        stock: p.stock,
        reorder: effectiveThreshold(p, defaultThreshold),
        unit: p.unit.toLowerCase(),
      }))
      .sort((a, b) => a.stock / Math.max(a.reorder, 1) - b.stock / Math.max(b.reorder, 1))
      .slice(0, 6);

    const recentTransactions: DashboardTransaction[] = [
      ...invoiceRows.map((r) => ({
        ref: r.invoice.id,
        party: r.invoice.customerName,
        type: "Invoice" as const,
        date: r.invoice.date,
        amount: r.totals.total,
        status: r.totals.status,
        href: `/sales/${r.invoice.id}`,
      })),
      ...saleRows.map((r) => ({
        ref: r.sale.id,
        party: r.sale.customerName,
        type: "Sale" as const,
        date: r.sale.date,
        amount: r.totals.total,
        status: saleStatus(r.totals.paid, r.totals.total),
        // There's no per-sale detail route for POS the way invoices have
        // /sales/$invoiceId — this deep-links into Sales history with the
        // receipt number pre-filled into its own search box instead of
        // landing on an unfiltered list the receipt might be several pages
        // into.
        href: `/pos/history?q=${r.sale.id}`,
      })),
    ]
      .sort((a, b) => (a.date === b.date ? b.ref.localeCompare(a.ref) : a.date < b.date ? 1 : -1))
      .slice(0, 8);

    const monthDelta = delta(monthSales, lastMonthSales);

    return { kpis, revenueSeries, lowStock, recentTransactions, monthDelta };
  }, [invoices, sales, products, defaultThreshold, expenses, staff, accounts, journalEntries]);
}
