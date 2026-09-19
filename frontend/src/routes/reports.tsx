import { useMemo, useState, type ReactNode } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  AlertTriangle,
  BadgePercent,
  BarChart3,
  Boxes,
  ChevronDown,
  Coins,
  CreditCard,
  Printer,
  Receipt,
  RotateCcw,
  Scale,
  TrendingUp,
  Users,
  Wallet,
} from "lucide-react";

import { ExportMenu } from "@/components/export-menu";
import { PageHeader } from "@/components/page-header";
import { PrintDocument } from "@/components/print/print-document";
import { CostMissingBadge } from "@/components/inventory/cost-missing-badge";
import { PriceMissingBadge } from "@/components/inventory/price-missing-badge";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { canViewFinancials, useAuth } from "@/data/auth-store";
import { currency, TODAY } from "@/data/dashboard";
import { formatDate, useDocumentSettings } from "@/data/settings-store";
import {
  AGEING_BUCKETS,
  defaultFilters,
  presetRange,
  PRESET_LABELS,
  useReports,
  type AgeingRow,
  type DiscountRow,
  type ExpenseCategoryRow,
  type ExpenseMethodRow,
  type ExpensePeriodRow,
  type LargestExpenseRow,
  type MarginRow,
  type OperatingRow,
  type MethodRow,
  type PeriodRow,
  type ProductRow,
  type RangePreset,
  type ReportFilters,
  type ReportsData,
  type ReturnRow,
  type ValuationRow,
  type VatRow,
} from "@/data/reports";

export const Route = createFileRoute("/reports")({
  head: () => ({
    meta: [
      { title: "Reports — TCS" },
      {
        name: "description",
        content:
          "Expense tracking and financial reporting, plus store analytics once retail modules are in use.",
      },
      { property: "og:title", content: "Reports — TCS" },
      {
        property: "og:description",
        content:
          "Expense tracking and financial reporting, plus store analytics once retail modules are in use.",
      },
    ],
  }),
  component: ReportsPage,
});

// Every report except Expenses Summary reads from Sales/POS/Inventory —
// the same modules the sidebar's "Procurement & Stores · not yet in use"
// section covers (20260919). Debtors & Receivables and VAT Summary are
// conceptually finance-relevant to a school (fees owed, tax) but as built
// today both compute strictly from the Sales/Invoicing domain, so they'd
// render empty for TCS right now — grouped with the rest until a real
// school-fees or tax data model feeds them instead.
const DORMANT_REPORT_IDS = new Set([
  "sales-summary",
  "profit",
  "operating-margin",
  "debtors",
  "products",
  "valuation",
  "discounts",
  "vat",
  "payments",
  "returns",
]);

/* ------------------------------------------------------------------ helpers */

type Col<T> = {
  header: string;
  value: (row: T) => string | number;
  align?: "right";
  cell?: (row: T) => ReactNode;
};

type Section<T> = {
  name: string;
  hint?: string;
  columns: Col<T>[];
  rows: T[];
  footer?: (rows: T[]) => Array<string | number>;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnySection = Section<any>;

type ReportDef = {
  id: string;
  label: string;
  icon: typeof BarChart3;
  description: string;
  /** Optional cross-report callout shown under the description. */
  note?: ReactNode;
  facets: Array<"category" | "customer" | "staff">;
  stats: Array<{ label: string; value: string; hint: string; tone?: "warning" | "good" }>;
  chart?: { title?: string; seriesLabel?: string; data: Array<{ label: string; value: number }> };
  sections: AnySection[];
};

const pct = (value: number) => `${value.toFixed(1)}%`;

function ReportsPage() {
  const { staff: currentStaff } = useAuth();
  const canViewReports = canViewFinancials(currentStaff?.role);

  const [filters, setFilters] = useState<ReportFilters>(defaultFilters);
  const [active, setActive] = useState("expenses");
  const [storesOpen, setStoresOpen] = useState(false);
  const data = useReports(filters);
  const settings = useDocumentSettings();

  const patch = (next: Partial<ReportFilters>) => setFilters((f) => ({ ...f, ...next }));
  const applyPreset = (preset: RangePreset) =>
    setFilters((f) => ({ ...f, preset, ...presetRange(preset) }));

  const reports = useReportDefs(data, setActive);
  const report = reports.find((r) => r.id === active) ?? reports[0];

  const rangeLabel =
    filters.from || filters.to
      ? `${filters.from ? formatDate(filters.from) : "start"} → ${formatDate(filters.to || TODAY())}`
      : "All time";

  const facetLabel = (facet: "category" | "customer" | "staff") => {
    if (facet === "category") return filters.category === "all" ? null : filters.category;
    if (facet === "staff") return filters.staff === "all" ? null : filters.staff;
    return filters.customerId === "all"
      ? null
      : (data.customerList.find((c) => c.id === filters.customerId)?.name ?? null);
  };

  const activeFacets = report.facets.map(facetLabel).filter(Boolean) as string[];
  const filterSummary = [rangeLabel, ...activeFacets].join(" · ");

  // Reports stays off-limits to an Attendant entirely, not just restricted
  // on some fields — several reports here (Profit & Margin, Valuation) show
  // cost price and margin, and Expenses-derived figures rely on data an
  // Attendant has no RLS read access to at all. There's no separate
  // "Reports query" the database could distinguish from an ordinary
  // Sales/POS read (this page is a client-side useMemo over the same
  // useInventory()/useSales()/usePosSales()/useExpenses() hooks those pages
  // call), so this route guard is what actually makes the page show
  // nothing for that role — see the role-permissions-rewrite migration for
  // the backend half (Attendant has zero access to expenses/expense_categories).
  if (!canViewReports) {
    return (
      <>
        <PageHeader
          title="Reports"
          description="Expense tracking, financial reporting, and store analytics once retail modules are in use."
        />
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <BarChart3 className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Reports isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            Reports is restricted to Managers, Accountants and Auditors — it isn't part of Sales,
            POS, Returns or Invoices, and some of its figures (cost price, margin) aren't meant for
            an Attendant to see. Ask a Manager or Accountant if you need something from here.
          </p>
        </div>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Reports"
        description="Every figure is calculated from the same records that drive Expenses, Accounting and (once in use) Inventory, Customers, Sales and POS."
        actions={
          <>
            <Button variant="outline" className="gap-2" onClick={() => window.print()}>
              <Printer className="size-4" />
              Print view
            </Button>
            <ExportMenu
              baseName={`report-${report.id}`}
              filters={[filters.from || "all", filters.to || TODAY(), ...activeFacets]}
              summary={`${report.label} · ${filterSummary}`}
              getSheets={() =>
                report.sections.map((s) => ({
                  name: s.name.slice(0, 31),
                  columns: s.columns.map((c) => ({ header: c.header, value: c.value })),
                  rows: s.rows,
                }))
              }
            />
          </>
        }
      />

      {/* ------------------------------------------------------ filter bar */}
      <div className="card-surface mb-6 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-wrap gap-1.5">
            {PRESET_LABELS.map((p) => (
              <Button
                key={p.id}
                size="sm"
                variant={filters.preset === p.id ? "default" : "ghost"}
                className="h-9 rounded-xl"
                onClick={() => applyPreset(p.id)}
              >
                {p.label}
              </Button>
            ))}
          </div>

          <div className="ml-auto flex flex-wrap items-end gap-3">
            <Field label="From" htmlFor="report-from">
              <Input
                id="report-from"
                type="date"
                value={filters.from}
                onChange={(e) => patch({ from: e.target.value, preset: "custom" })}
                className="h-9 w-40 rounded-xl"
              />
            </Field>
            <Field label="To" htmlFor="report-to">
              <Input
                id="report-to"
                type="date"
                value={filters.to}
                onChange={(e) => patch({ to: e.target.value, preset: "custom" })}
                className="h-9 w-40 rounded-xl"
              />
            </Field>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-end gap-3 border-t pt-3">
          <FacetSelect
            label="Category"
            disabled={!report.facets.includes("category")}
            value={filters.category}
            onChange={(v) => patch({ category: v })}
            options={[
              { value: "all", label: "All categories" },
              ...settings.inventory.categories.map((c) => ({ value: c, label: c })),
            ]}
          />
          <FacetSelect
            label="Customer"
            disabled={!report.facets.includes("customer")}
            value={filters.customerId}
            onChange={(v) => patch({ customerId: v })}
            options={[
              { value: "all", label: "All customers" },
              ...data.customerList.map((c) => ({ value: c.id, label: c.name })),
            ]}
          />
          <FacetSelect
            label="Staff member"
            disabled={!report.facets.includes("staff")}
            value={filters.staff}
            onChange={(v) => patch({ staff: v })}
            options={[
              { value: "all", label: "All staff" },
              ...data.staffList.map((s) => ({ value: s, label: s })),
            ]}
          />
          <div className="ml-auto flex items-center gap-2">
            <p className="text-xs text-muted-foreground">{filterSummary}</p>
            <Button
              variant="ghost"
              size="sm"
              className="h-9"
              onClick={() => setFilters(defaultFilters())}
            >
              Reset
            </Button>
          </div>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)]">
        {/* -------------------------------------------------- report picker */}
        <nav className="card-surface h-fit p-2 lg:sticky lg:top-24">
          <ReportPickerList
            reports={reports.filter((r) => !DORMANT_REPORT_IDS.has(r.id))}
            activeId={report.id}
            onSelect={setActive}
          />

          {/* Same "collapsed by default, forced open if it holds the active
              report" treatment as the sidebar's dormant section — everything
              here reads from Sales/POS/Inventory, none of it populated for
              TCS yet (see DORMANT_REPORT_IDS above). */}
          {(() => {
            const storeReports = reports.filter((r) => DORMANT_REPORT_IDS.has(r.id));
            if (storeReports.length === 0) return null;
            const hasActive = storeReports.some((r) => r.id === report.id);
            const open = storesOpen || hasActive;
            return (
              <div className="mt-2 border-t pt-2">
                <button
                  type="button"
                  onClick={() => setStoresOpen((o) => !o)}
                  className="flex w-full items-center justify-between rounded-lg px-3 py-1.5 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/70 hover:text-muted-foreground"
                >
                  <span className="truncate">Store & Sales · not yet in use</span>
                  <ChevronDown
                    className={`size-3.5 shrink-0 transition-transform ${open ? "rotate-180" : ""}`}
                  />
                </button>
                {open && (
                  <div className="mt-1 opacity-80">
                    <ReportPickerList
                      reports={storeReports}
                      activeId={report.id}
                      onSelect={setActive}
                    />
                  </div>
                )}
              </div>
            );
          })()}
        </nav>

        {/* --------------------------------------------------- active report */}
        <div className="min-w-0">
          <div className="mb-4">
            <h2 className="text-xl font-semibold tracking-tight">{report.label}</h2>
            <p className="text-sm text-muted-foreground">{report.description}</p>
            {report.note && (
              <div className="mt-3 rounded-xl border border-dashed bg-muted/40 p-3 text-sm text-muted-foreground">
                {report.note}
              </div>
            )}
          </div>

          {report.stats.length > 0 && (
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              {report.stats.map((s) => (
                <Stat key={s.label} {...s} />
              ))}
            </div>
          )}

          {report.chart && report.chart.data.length > 0 && (
            <div className="card-surface mt-6 p-5">
              <h3 className="text-sm font-medium text-muted-foreground">
                {report.chart.title ?? "Revenue trend"}
              </h3>
              <div className="mt-4 h-64">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={report.chart.data} margin={{ left: 4, right: 8, top: 8 }}>
                    <defs>
                      <linearGradient id="reportRevenue" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="var(--color-chart-1)" stopOpacity={0.35} />
                        <stop offset="100%" stopColor="var(--color-chart-1)" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" vertical={false} opacity={0.25} />
                    <XAxis dataKey="label" tickLine={false} axisLine={false} fontSize={11} />
                    <YAxis
                      tickLine={false}
                      axisLine={false}
                      fontSize={11}
                      width={64}
                      tickFormatter={(v: number) => currency(v)}
                    />
                    <Tooltip
                      formatter={(v: number) => [
                        currency(v),
                        report.chart?.seriesLabel ?? "Revenue",
                      ]}
                      contentStyle={{ borderRadius: 12, fontSize: 12 }}
                    />
                    <Area
                      type="monotone"
                      dataKey="value"
                      stroke="var(--color-chart-1)"
                      strokeWidth={2}
                      fill="url(#reportRevenue)"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}

          <div className="mt-6 grid gap-6">
            {report.sections.map((section) => (
              <DataTable key={section.name} section={section} />
            ))}
          </div>
        </div>
      </div>

      <PrintDocument pageSize="A4 landscape" margin="12mm">
        <PrintableReport
          title={report.label}
          description={report.description}
          company={settings.company.name}
          summary={filterSummary}
          sections={report.sections}
          stats={report.stats}
        />
      </PrintDocument>
    </>
  );
}

/* ------------------------------------------------------------ report specs */

function useReportDefs(d: ReportsData, goTo: (id: string) => void): ReportDef[] {
  return useMemo(() => {
    const sum = <T,>(rows: T[], pick: (r: T) => number) => rows.reduce((s, r) => s + pick(r), 0);

    return [
      {
        id: "sales-summary",
        label: "Sales Summary",
        icon: BarChart3,
        description: "Invoiced and till revenue for the selected period, net of discounts.",
        facets: ["customer", "staff"],
        stats: [
          { label: "Revenue", value: currency(d.revenue), hint: `${d.txCount} transactions` },
          { label: "Net of VAT", value: currency(d.netRevenue), hint: "Excludes VAT charged" },
          {
            label: "Average sale",
            value: currency(d.averageSale),
            hint: `${d.invoiceCount} invoices · ${d.posCount} till sales`,
          },
          { label: "Payments received", value: currency(d.collected), hint: "All methods" },
        ],
        chart: { data: d.salesByPeriod.map((r) => ({ label: r.period, value: r.total })) },
        sections: [
          {
            name: "Sales summary",
            hint: `Grouped by ${d.grain}`,
            columns: [
              { header: "Period", value: (r: PeriodRow) => r.period },
              { header: "Transactions", value: (r: PeriodRow) => r.transactions, align: "right" },
              { header: "Gross (GHS)", value: (r: PeriodRow) => r.gross, align: "right" },
              { header: "Discounts (GHS)", value: (r: PeriodRow) => r.discounts, align: "right" },
              { header: "Net (GHS)", value: (r: PeriodRow) => r.net, align: "right" },
              { header: "VAT (GHS)", value: (r: PeriodRow) => r.vat, align: "right" },
              { header: "Total (GHS)", value: (r: PeriodRow) => r.total, align: "right" },
              { header: "Average sale (GHS)", value: (r: PeriodRow) => r.average, align: "right" },
            ],
            rows: d.salesByPeriod,
            footer: (rows: PeriodRow[]) => [
              "Total",
              sum(rows, (r) => r.transactions),
              currency(sum(rows, (r) => r.gross)),
              currency(sum(rows, (r) => r.discounts)),
              currency(sum(rows, (r) => r.net)),
              currency(sum(rows, (r) => r.vat)),
              currency(sum(rows, (r) => r.total)),
              currency(d.averageSale),
            ],
          },
        ],
      },
      {
        id: "profit",
        label: "Profit & Margin",
        icon: TrendingUp,
        description: "Gross profit against cost price, by product and by category.",
        note: (
          <>
            {d.costDataIncomplete && (
              <>
                <strong className="text-amber-700 dark:text-amber-400">
                  {d.incompleteCostProductCount} product
                  {d.incompleteCostProductCount === 1 ? "" : "s"} sold in this period
                  {d.incompleteCostProductCount === 1 ? " has" : " have"} no recorded cost price
                </strong>{" "}
                — cost of goods, gross profit and margin below are underestimated for those items,
                treated as GHS 0 cost rather than a confirmed figure.{" "}
              </>
            )}
            Gross profit is <strong>not</strong> the final figure — it stops at cost of goods and
            ignores running costs. Recorded expenses for this period come to{" "}
            <strong>{currency(d.expenseTotal)}</strong>, leaving an operating margin of{" "}
            <strong>{currency(d.operatingProfit)}</strong> ({pct(d.operatingMargin)}).{" "}
            <button
              type="button"
              onClick={() => goTo("operating-margin")}
              className="font-medium text-primary underline-offset-2 hover:underline"
            >
              Open Operating Margin
            </button>{" "}
            ·{" "}
            <button
              type="button"
              onClick={() => goTo("expenses")}
              className="font-medium text-primary underline-offset-2 hover:underline"
            >
              Open Expenses Summary
            </button>
          </>
        ),
        facets: ["category", "customer", "staff"],
        stats: [
          {
            label: "Revenue (ex VAT)",
            value: currency(d.revenue - d.vatCollected),
            hint: "After discounts",
          },
          {
            label: "Cost of goods",
            value: currency(d.totalCost),
            hint: d.costDataIncomplete
              ? "Underestimated — cost price missing for some items"
              : "At current cost price",
            tone: d.costDataIncomplete ? "warning" : undefined,
          },
          {
            label: "Gross profit",
            value: currency(d.grossProfit),
            hint: d.costDataIncomplete
              ? "Overestimated — cost price missing for some items"
              : "Revenue less cost",
            tone: d.costDataIncomplete ? "warning" : "good",
          },
          {
            label: "Gross margin",
            value: pct(d.grossMargin),
            hint: d.costDataIncomplete
              ? "Overestimated — cost price missing for some items"
              : "Gross profit as a share of revenue",
            tone: d.costDataIncomplete ? "warning" : d.grossMargin < 15 ? "warning" : "good",
          },
        ],
        sections: [
          {
            name: "Margin by category",
            columns: [
              { header: "Category", value: (r: MarginRow) => r.category },
              { header: "Quantity", value: (r: MarginRow) => r.quantity, align: "right" },
              { header: "Revenue (GHS)", value: (r: MarginRow) => r.revenue, align: "right" },
              {
                header: "Cost (GHS)",
                value: (r: MarginRow) => r.cost,
                align: "right",
                cell: (r: MarginRow) => (
                  <span className="inline-flex items-center gap-1.5">
                    {r.costIncomplete && (
                      <AlertTriangle
                        className="size-3.5 shrink-0 text-amber-500"
                        aria-label="Cost price missing for one or more items"
                      />
                    )}
                    {currency(r.cost)}
                  </span>
                ),
              },
              { header: "Gross profit (GHS)", value: (r: MarginRow) => r.profit, align: "right" },
              { header: "Margin %", value: (r: MarginRow) => r.margin, align: "right" },
            ],
            rows: d.marginByCategory,
            footer: (rows: MarginRow[]) => [
              "Total",
              sum(rows, (r) => r.quantity),
              currency(sum(rows, (r) => r.revenue)),
              currency(sum(rows, (r) => r.cost)),
              currency(sum(rows, (r) => r.profit)),
              pct(d.grossMargin),
            ],
          },
          {
            name: "Margin by product",
            hint: "Sorted by gross profit contribution",
            columns: [
              { header: "Product", value: (r: MarginRow) => r.name },
              { header: "Category", value: (r: MarginRow) => r.category },
              { header: "Quantity", value: (r: MarginRow) => r.quantity, align: "right" },
              { header: "Revenue (GHS)", value: (r: MarginRow) => r.revenue, align: "right" },
              {
                header: "Cost (GHS)",
                value: (r: MarginRow) => r.cost,
                align: "right",
                cell: (r: MarginRow) => (
                  <span className="inline-flex items-center gap-1.5">
                    {r.costIncomplete && (
                      <AlertTriangle
                        className="size-3.5 shrink-0 text-amber-500"
                        aria-label="Cost price missing for one or more items"
                      />
                    )}
                    {currency(r.cost)}
                  </span>
                ),
              },
              { header: "Gross profit (GHS)", value: (r: MarginRow) => r.profit, align: "right" },
              { header: "Margin %", value: (r: MarginRow) => r.margin, align: "right" },
            ],
            rows: d.marginRows,
          },
        ],
      },
      {
        id: "expenses",
        label: "Expenses Summary",
        icon: Wallet,
        description:
          "Everything recorded in Expenses for the period, by category and payment method.",
        note: (
          <>
            Compared against the previous equivalent period (
            {d.previousFrom
              ? `${formatDate(d.previousFrom)} → ${formatDate(d.previousTo)}`
              : "no earlier window"}
            ), which totalled <strong>{currency(d.previousExpenseTotal)}</strong>.{" "}
            <button
              type="button"
              onClick={() => goTo("operating-margin")}
              className="font-medium text-primary underline-offset-2 hover:underline"
            >
              See what this leaves as operating margin
            </button>
          </>
        ),
        facets: ["staff"],
        stats: [
          {
            label: "Total expenses",
            value: currency(d.expenseTotal),
            hint: `${d.expenseCount} expenses recorded`,
          },
          {
            label: "vs. previous period",
            value: d.previousExpenseTotal > 0 ? pct(d.expenseChange) : "—",
            hint:
              d.previousExpenseTotal > 0
                ? `${currency(d.previousExpenseTotal)} previously`
                : "No comparable earlier window",
            tone: d.expenseChange > 0 ? "warning" : d.previousExpenseTotal > 0 ? "good" : undefined,
          },
          {
            label: "Largest category",
            value: d.expenseCategories[0]?.category ?? "—",
            hint: d.expenseCategories[0]
              ? `${currency(d.expenseCategories[0].amount)} · ${pct(d.expenseCategories[0].share)}`
              : "Nothing recorded in range",
          },
          {
            label: "Average expense",
            value: currency(d.averageExpense),
            hint: d.largestExpense
              ? `Largest ${currency(d.largestExpense.amount)} · ${d.largestExpense.category}`
              : "No expenses in range",
          },
        ],
        chart: {
          title: "Expense trend",
          seriesLabel: "Expenses",
          data: d.expenseByPeriod.map((r) => ({ label: r.period, value: r.amount })),
        },
        sections: [
          {
            name: "By category",
            hint: "Against the previous equivalent period",
            columns: [
              { header: "Category", value: (r: ExpenseCategoryRow) => r.category },
              { header: "Expenses", value: (r: ExpenseCategoryRow) => r.count, align: "right" },
              {
                header: "Amount (GHS)",
                value: (r: ExpenseCategoryRow) => r.amount,
                align: "right",
              },
              { header: "Share %", value: (r: ExpenseCategoryRow) => r.share, align: "right" },
              {
                header: "Previous period (GHS)",
                value: (r: ExpenseCategoryRow) => r.previous,
                align: "right",
              },
              { header: "Change %", value: (r: ExpenseCategoryRow) => r.change, align: "right" },
            ],
            rows: d.expenseCategories,
            footer: (rows: ExpenseCategoryRow[]) => [
              "Total",
              sum(rows, (r) => r.count),
              currency(sum(rows, (r) => r.amount)),
              "100.0%",
              currency(d.previousExpenseTotal),
              d.previousExpenseTotal > 0 ? pct(d.expenseChange) : "—",
            ],
          },
          {
            name: "By payment method",
            columns: [
              { header: "Method", value: (r: ExpenseMethodRow) => r.method },
              { header: "Expenses", value: (r: ExpenseMethodRow) => r.count, align: "right" },
              { header: "Amount (GHS)", value: (r: ExpenseMethodRow) => r.amount, align: "right" },
              { header: "Share %", value: (r: ExpenseMethodRow) => r.share, align: "right" },
            ],
            rows: d.expenseMethods,
            footer: (rows: ExpenseMethodRow[]) => [
              "Total",
              sum(rows, (r) => r.count),
              currency(sum(rows, (r) => r.amount)),
              "100.0%",
            ],
          },
          {
            name: "Expense trend",
            hint: `Grouped by ${d.grain}`,
            columns: [
              { header: "Period", value: (r: ExpensePeriodRow) => r.period },
              { header: "Expenses", value: (r: ExpensePeriodRow) => r.count, align: "right" },
              { header: "Amount (GHS)", value: (r: ExpensePeriodRow) => r.amount, align: "right" },
            ],
            rows: d.expenseByPeriod,
            footer: (rows: ExpensePeriodRow[]) => [
              "Total",
              sum(rows, (r) => r.count),
              currency(sum(rows, (r) => r.amount)),
            ],
          },
          {
            name: "Largest expenses",
            hint: "Biggest individual entries in the period",
            columns: [
              {
                header: "Reference",
                value: (r: LargestExpenseRow) => r.id,
                cell: (r: LargestExpenseRow) => (
                  <Link
                    to="/expenses/$expenseId"
                    params={{ expenseId: r.id }}
                    className="font-medium text-primary hover:underline"
                  >
                    {r.id}
                  </Link>
                ),
              },
              { header: "Date", value: (r: LargestExpenseRow) => formatDate(r.date) },
              { header: "Category", value: (r: LargestExpenseRow) => r.category },
              { header: "Description", value: (r: LargestExpenseRow) => r.description },
              { header: "Method", value: (r: LargestExpenseRow) => r.method },
              { header: "Recorded by", value: (r: LargestExpenseRow) => r.recordedBy },
              { header: "Amount (GHS)", value: (r: LargestExpenseRow) => r.amount, align: "right" },
              { header: "Share %", value: (r: LargestExpenseRow) => r.share, align: "right" },
            ],
            rows: d.largestExpenses,
          },
        ],
      },
      {
        id: "operating-margin",
        label: "Operating Margin",
        icon: Scale,
        description:
          "Gross profit less the expenses recorded in the system, as an amount and a share of revenue.",
        note: (
          <>
            This is the <strong>operating margin based on recorded expenses</strong>, not net
            profit. Payroll is not built yet and any cost never entered into Expenses is missing, so
            treat this as a floor rather than a final result.{" "}
            <button
              type="button"
              onClick={() => goTo("profit")}
              className="font-medium text-primary underline-offset-2 hover:underline"
            >
              Back to Profit & Margin
            </button>{" "}
            ·{" "}
            <button
              type="button"
              onClick={() => goTo("expenses")}
              className="font-medium text-primary underline-offset-2 hover:underline"
            >
              Expenses Summary
            </button>
          </>
        ),
        facets: ["category", "customer", "staff"],
        stats: [
          {
            label: "Gross profit",
            value: currency(d.grossProfit),
            hint: `${pct(d.grossMargin)} of revenue`,
            tone: "good",
          },
          {
            label: "Recorded expenses",
            value: currency(d.expenseTotal),
            hint: `${pct(d.expenseRatio)} of revenue`,
            tone: d.expenseTotal > 0 ? "warning" : undefined,
          },
          {
            label: "Operating margin",
            value: currency(d.operatingProfit),
            hint: "Gross profit less recorded expenses",
            tone: d.operatingProfit >= 0 ? "good" : "warning",
          },
          {
            label: "Operating margin %",
            value: pct(d.operatingMargin),
            hint: "Share of revenue, ex VAT",
            tone: d.operatingMargin < 5 ? "warning" : "good",
          },
        ],
        sections: [
          {
            name: "Operating margin build-up",
            hint: "Operating margin based on recorded expenses — not net profit",
            columns: [
              { header: "Line", value: (r: OperatingRow) => r.line },
              { header: "Amount (GHS)", value: (r: OperatingRow) => r.amount, align: "right" },
              { header: "Share %", value: (r: OperatingRow) => r.ofRevenue, align: "right" },
              { header: "Basis", value: (r: OperatingRow) => r.note },
            ],
            rows: d.operatingRows,
          },
          {
            name: "Expenses deducted, by category",
            columns: [
              { header: "Category", value: (r: ExpenseCategoryRow) => r.category },
              { header: "Expenses", value: (r: ExpenseCategoryRow) => r.count, align: "right" },
              {
                header: "Amount (GHS)",
                value: (r: ExpenseCategoryRow) => r.amount,
                align: "right",
              },
              {
                header: "Share of revenue %",
                value: (r: ExpenseCategoryRow) =>
                  d.marginRevenue > 0 ? Math.round((r.amount / d.marginRevenue) * 1000) / 10 : 0,
                align: "right",
              },
            ],
            rows: d.expenseCategories,
            footer: (rows: ExpenseCategoryRow[]) => [
              "Total",
              sum(rows, (r) => r.count),
              currency(sum(rows, (r) => r.amount)),
              pct(d.expenseRatio),
            ],
          },
        ],
      },
      {
        id: "debtors",
        label: "Debtors & Receivables",
        icon: Users,
        description: "Unpaid invoice balances, aged against their due date.",
        facets: ["customer", "staff"],
        stats: [
          {
            label: "Total receivable",
            value: currency(d.receivables),
            hint: `${d.ageing.length} open invoices`,
          },
          {
            label: "Overdue",
            value: currency(d.overdue),
            hint: "Past the due date",
            tone: d.overdue > 0 ? "warning" : undefined,
          },
          {
            label: "Not yet due",
            value: currency(d.receivables - d.overdue),
            hint: "Still within terms",
          },
          {
            label: "Oldest debt",
            value: d.ageing.length ? `${d.ageing[0].daysOverdue} days` : "—",
            hint: d.ageing.length ? d.ageing[0].customer : "Nothing outstanding",
          },
        ],
        sections: [
          {
            name: "Ageing breakdown",
            columns: [
              { header: "Age bucket", value: (r: { bucket: string }) => r.bucket },
              {
                header: "Invoices",
                value: (r: { invoices: number }) => r.invoices,
                align: "right",
              },
              {
                header: "Balance (GHS)",
                value: (r: { amount: number }) => r.amount,
                align: "right",
              },
              {
                header: "Share",
                value: (r: { amount: number }) =>
                  d.receivables > 0 ? Math.round((r.amount / d.receivables) * 1000) / 10 : 0,
                align: "right",
              },
            ],
            rows: d.ageingSummary,
            footer: (rows: Array<{ invoices: number; amount: number }>) => [
              "Total",
              sum(rows, (r) => r.invoices),
              currency(sum(rows, (r) => r.amount)),
              "100.0%",
            ],
          },
          {
            name: "Open invoices",
            hint: "Oldest debt first",
            columns: [
              {
                header: "Invoice",
                value: (r: AgeingRow) => r.invoice,
                cell: (r: AgeingRow) => (
                  <Link
                    to="/sales/$invoiceId"
                    params={{ invoiceId: r.invoice }}
                    className="font-medium text-primary hover:underline"
                  >
                    {r.invoice}
                  </Link>
                ),
              },
              {
                header: "Customer",
                value: (r: AgeingRow) => r.customer,
                cell: (r: AgeingRow) =>
                  r.customerId ? (
                    <Link
                      to="/customers/$customerId"
                      params={{ customerId: r.customerId }}
                      className="hover:underline"
                    >
                      {r.customer}
                    </Link>
                  ) : (
                    r.customer
                  ),
              },
              { header: "Issued", value: (r: AgeingRow) => formatDate(r.date) },
              { header: "Due", value: (r: AgeingRow) => formatDate(r.dueDate) },
              { header: "Days overdue", value: (r: AgeingRow) => r.daysOverdue, align: "right" },
              {
                header: "Bucket",
                value: (r: AgeingRow) => r.bucket,
                cell: (r: AgeingRow) => (
                  <Badge variant={r.bucket === "Current" ? "secondary" : "destructive"}>
                    {r.bucket}
                  </Badge>
                ),
              },
              { header: "Invoiced (GHS)", value: (r: AgeingRow) => r.total, align: "right" },
              { header: "Paid (GHS)", value: (r: AgeingRow) => r.paid, align: "right" },
              { header: "Balance (GHS)", value: (r: AgeingRow) => r.balance, align: "right" },
            ],
            rows: d.ageing,
          },
        ],
      },
      {
        id: "products",
        label: "Product Performance",
        icon: Boxes,
        description: "Best sellers and slow movers, with the stock still on the shelf.",
        facets: ["category", "customer", "staff"],
        stats: [
          {
            label: "Products sold",
            value: String(d.productRows.filter((r) => r.quantity > 0).length),
            hint: `${d.productRows.length} products in scope`,
          },
          {
            label: "Units moved",
            value: d.productRows.reduce((s, r) => s + r.quantity, 0).toLocaleString("en-GB"),
            hint: "Across invoices and till",
          },
          {
            label: "Top seller",
            value: d.productRows[0]?.name.split(" — ")[0] ?? "—",
            hint: d.productRows[0] ? currency(d.productRows[0].revenue) : "No sales in range",
          },
          {
            label: "No sales in range",
            value: String(d.productRows.filter((r) => r.quantity === 0).length),
            hint: "Consider a promotion",
            tone: d.productRows.some((r) => r.quantity === 0) ? "warning" : undefined,
          },
        ],
        sections: [
          {
            name: "Product performance",
            hint: "Sorted by revenue, slow movers at the bottom",
            columns: [
              { header: "Product", value: (r: ProductRow) => r.name },
              { header: "SKU", value: (r: ProductRow) => r.sku },
              { header: "Category", value: (r: ProductRow) => r.category },
              { header: "Unit", value: (r: ProductRow) => r.unit },
              { header: "Quantity sold", value: (r: ProductRow) => r.quantity, align: "right" },
              { header: "Transactions", value: (r: ProductRow) => r.transactions, align: "right" },
              { header: "Revenue (GHS)", value: (r: ProductRow) => r.revenue, align: "right" },
              { header: "Gross profit (GHS)", value: (r: ProductRow) => r.profit, align: "right" },
              { header: "Margin %", value: (r: ProductRow) => r.margin, align: "right" },
              { header: "In stock", value: (r: ProductRow) => r.stock, align: "right" },
            ],
            rows: d.productRows,
            footer: (rows: ProductRow[]) => [
              "Total",
              "",
              "",
              "",
              sum(rows, (r) => r.quantity),
              "",
              currency(sum(rows, (r) => r.revenue)),
              currency(sum(rows, (r) => r.profit)),
              "",
              sum(rows, (r) => r.stock),
            ],
          },
        ],
      },
      {
        id: "valuation",
        label: "Inventory Valuation",
        icon: Coins,
        description: "What the stock on hand is worth at cost, and at retail.",
        facets: ["category"],
        stats: [
          {
            label: "Stock at cost",
            value: currency(d.stockValue),
            hint:
              d.valuationIncompleteCount > 0
                ? `Excludes ${d.valuationIncompleteCount} product${d.valuationIncompleteCount === 1 ? "" : "s"} with no cost price recorded`
                : `${d.valuation.length} products`,
            tone: d.valuationIncompleteCount > 0 ? "warning" : undefined,
          },
          {
            label: "Stock at retail",
            value: currency(d.retailValue),
            hint:
              d.retailIncompleteCount > 0
                ? `Excludes ${d.retailIncompleteCount} product${d.retailIncompleteCount === 1 ? "" : "s"} with no selling price recorded`
                : "If sold at list price",
            tone: d.retailIncompleteCount > 0 ? "warning" : undefined,
          },
          {
            label: "Potential gross profit",
            value: currency(d.potentialGrossProfit),
            hint:
              d.valuationIncompleteCount > 0 || d.retailIncompleteCount > 0
                ? "Retail less cost, for products with both recorded only"
                : "Retail less cost",
            tone: "good",
          },
          {
            label: "Need restocking",
            value: String(d.lowStock),
            hint: "At or below threshold",
            tone: d.lowStock > 0 ? "warning" : undefined,
          },
        ],
        sections: [
          {
            name: "Inventory valuation",
            hint: "Highest value first",
            columns: [
              { header: "Product", value: (r: ValuationRow) => r.name },
              { header: "SKU", value: (r: ValuationRow) => r.sku },
              { header: "Category", value: (r: ValuationRow) => r.category },
              { header: "Unit", value: (r: ValuationRow) => r.unit },
              { header: "In stock", value: (r: ValuationRow) => r.stock, align: "right" },
              {
                header: "Cost price (GHS)",
                value: (r: ValuationRow) => r.cost ?? "Not recorded",
                align: "right",
                cell: (r: ValuationRow) =>
                  r.cost === null ? <CostMissingBadge className="ml-auto" /> : currency(r.cost),
              },
              {
                header: "Stock value (GHS)",
                value: (r: ValuationRow) => r.value ?? "Not recorded",
                align: "right",
                cell: (r: ValuationRow) =>
                  r.value === null ? (
                    <span className="text-muted-foreground">—</span>
                  ) : (
                    currency(r.value)
                  ),
              },
              {
                header: "Retail value (GHS)",
                value: (r: ValuationRow) => r.retail ?? "Not recorded",
                align: "right",
                cell: (r: ValuationRow) =>
                  r.retail === null ? (
                    <PriceMissingBadge className="ml-auto" />
                  ) : (
                    currency(r.retail)
                  ),
              },
              {
                header: "Status",
                value: (r: ValuationRow) => r.status,
                cell: (r: ValuationRow) => (
                  <Badge
                    variant={
                      r.status === "In stock"
                        ? "secondary"
                        : r.status === "Low stock"
                          ? "outline"
                          : "destructive"
                    }
                  >
                    {r.status}
                  </Badge>
                ),
              },
            ],
            rows: d.valuation,
            footer: (rows: ValuationRow[]) => [
              "Total",
              "",
              "",
              "",
              sum(rows, (r) => r.stock),
              "",
              currency(d.stockValue),
              currency(d.retailValue),
              "",
            ],
          },
        ],
      },
      {
        id: "discounts",
        label: "Discounts Given",
        icon: BadgePercent,
        description: "Every discount applied on a line or a whole document, and who approved it.",
        facets: ["category", "customer", "staff"],
        stats: [
          {
            label: "Discounts given",
            value: currency(d.discountTotal),
            hint: `${d.discountRows.length} discounts`,
          },
          {
            label: "Documents affected",
            value: String(d.discountedDocs),
            hint: "Invoices and till sales",
          },
          {
            label: "Share of revenue",
            value: pct(d.revenue > 0 ? (d.discountTotal / d.revenue) * 100 : 0),
            hint: "Discount against revenue",
            tone: d.revenue > 0 && d.discountTotal / d.revenue > 0.05 ? "warning" : undefined,
          },
          {
            label: "Largest single discount",
            value: currency(d.discountRows[0]?.discount ?? 0),
            hint: d.discountRows[0]?.staff ?? "None in range",
          },
        ],
        sections: [
          {
            name: "By staff member",
            columns: [
              { header: "Staff member", value: (r: { staff: string }) => r.staff },
              { header: "Discounts", value: (r: { count: number }) => r.count, align: "right" },
              {
                header: "Total given (GHS)",
                value: (r: { amount: number }) => r.amount,
                align: "right",
              },
              {
                header: "Largest (GHS)",
                value: (r: { largest: number }) => r.largest,
                align: "right",
              },
            ],
            rows: d.discountByStaff,
            footer: (rows: Array<{ count: number; amount: number }>) => [
              "Total",
              sum(rows, (r) => r.count),
              currency(sum(rows, (r) => r.amount)),
              "",
            ],
          },
          {
            name: "Discount detail",
            hint: "Largest first",
            columns: [
              { header: "Document", value: (r: DiscountRow) => r.document },
              { header: "Type", value: (r: DiscountRow) => r.kind },
              { header: "Date", value: (r: DiscountRow) => formatDate(r.date) },
              { header: "Customer", value: (r: DiscountRow) => r.customer },
              { header: "Staff member", value: (r: DiscountRow) => r.staff },
              { header: "Applied to", value: (r: DiscountRow) => r.item },
              { header: "Level", value: (r: DiscountRow) => r.level },
              { header: "Value before (GHS)", value: (r: DiscountRow) => r.gross, align: "right" },
              { header: "Discount (GHS)", value: (r: DiscountRow) => r.discount, align: "right" },
              { header: "Rate %", value: (r: DiscountRow) => r.rate, align: "right" },
            ],
            rows: d.discountRows,
          },
        ],
      },
      {
        id: "vat",
        label: "VAT Summary",
        icon: Receipt,
        description: "Taxable and exempt sales with the VAT charged on top.",
        facets: ["customer", "staff"],
        stats: [
          {
            label: "VAT charged",
            value: currency(d.vatCollected),
            hint: "Output tax for the period",
          },
          {
            label: "Taxable sales",
            value: currency(d.taxableSales),
            hint: "Net of discounts, ex VAT",
          },
          { label: "Exempt sales", value: currency(d.exemptSales), hint: "No VAT applied" },
          {
            label: "Effective rate",
            value: pct(d.taxableSales > 0 ? (d.vatCollected / d.taxableSales) * 100 : 0),
            hint: "VAT over taxable base",
          },
        ],
        sections: [
          {
            name: "VAT summary",
            hint: `Grouped by ${d.grain}`,
            columns: [
              { header: "Period", value: (r: VatRow) => r.period },
              { header: "Taxable sales (GHS)", value: (r: VatRow) => r.taxable, align: "right" },
              { header: "Exempt sales (GHS)", value: (r: VatRow) => r.exempt, align: "right" },
              { header: "VAT charged (GHS)", value: (r: VatRow) => r.vat, align: "right" },
              { header: "Gross total (GHS)", value: (r: VatRow) => r.total, align: "right" },
            ],
            rows: d.vatRows,
            footer: (rows: VatRow[]) => [
              "Total",
              currency(sum(rows, (r) => r.taxable)),
              currency(sum(rows, (r) => r.exempt)),
              currency(sum(rows, (r) => r.vat)),
              currency(sum(rows, (r) => r.total)),
            ],
          },
        ],
      },
      {
        id: "payments",
        label: "Payment Methods",
        icon: CreditCard,
        description: "Where the money came in, with split payments attributed per method.",
        facets: ["customer", "staff"],
        stats: [
          { label: "Total collected", value: currency(d.collected), hint: "Invoices and till" },
          {
            label: "Leading method",
            value: d.methodRows[0]?.method ?? "—",
            hint: d.methodRows[0]
              ? `${pct(d.methodRows[0].share)} of takings`
              : "No payments in range",
          },
          {
            label: "Split payments",
            value: String(d.splitPayments),
            hint: "Sales settled with 2+ methods",
          },
          {
            label: "Still unpaid",
            value: currency(d.receivables),
            hint: "Outstanding invoice balances",
            tone: d.receivables > 0 ? "warning" : undefined,
          },
        ],
        sections: [
          {
            name: "Payment methods",
            hint: "Each part of a split payment counted against its own method",
            columns: [
              { header: "Method", value: (r: MethodRow) => r.method },
              { header: "Payments", value: (r: MethodRow) => r.count, align: "right" },
              {
                header: "From invoices (GHS)",
                value: (r: MethodRow) => r.invoices,
                align: "right",
              },
              { header: "From till (GHS)", value: (r: MethodRow) => r.pos, align: "right" },
              { header: "Total (GHS)", value: (r: MethodRow) => r.amount, align: "right" },
              { header: "Share %", value: (r: MethodRow) => r.share, align: "right" },
            ],
            rows: d.methodRows,
            footer: (rows: MethodRow[]) => [
              "Total",
              sum(rows, (r) => r.count),
              currency(sum(rows, (r) => r.invoices)),
              currency(sum(rows, (r) => r.pos)),
              currency(sum(rows, (r) => r.amount)),
              "100.0%",
            ],
          },
        ],
      },
      {
        id: "returns",
        label: "Returns & Exchanges",
        icon: RotateCcw,
        description: "Goods brought back, how each case was resolved and what needs approval.",
        facets: ["category", "customer", "staff"],
        stats: [
          { label: "Returns", value: String(d.returnRows.length), hint: "Cases in the period" },
          { label: "Value returned", value: currency(d.returnedValue), hint: "At the price sold" },
          {
            label: "Return rate",
            value: pct(d.returnRate),
            hint: "Returned value over revenue",
            tone: d.returnRate > 3 ? "warning" : undefined,
          },
          {
            label: "Awaiting approval",
            value: String(d.pendingApprovals),
            hint: "Refunds and store credit",
            tone: d.pendingApprovals > 0 ? "warning" : undefined,
          },
        ],
        sections: [
          {
            name: "Returns and exchanges",
            hint: "Most recent first",
            columns: [
              { header: "Return", value: (r: ReturnRow) => r.id },
              { header: "Date", value: (r: ReturnRow) => formatDate(r.date) },
              { header: "Original sale", value: (r: ReturnRow) => r.sale },
              { header: "Customer", value: (r: ReturnRow) => r.customer },
              { header: "Handled by", value: (r: ReturnRow) => r.staff },
              { header: "Item returned", value: (r: ReturnRow) => r.item },
              { header: "Value (GHS)", value: (r: ReturnRow) => r.value, align: "right" },
              { header: "Replacement", value: (r: ReturnRow) => r.replacement },
              { header: "Difference (GHS)", value: (r: ReturnRow) => r.difference, align: "right" },
              { header: "Resolution", value: (r: ReturnRow) => r.resolution },
              {
                header: "Approval",
                value: (r: ReturnRow) => r.approval,
                cell: (r: ReturnRow) => (
                  <Badge variant={r.approval === "Not required" ? "secondary" : "destructive"}>
                    {r.approval}
                  </Badge>
                ),
              },
              { header: "Reason", value: (r: ReturnRow) => r.reason },
            ],
            rows: d.returnRows,
          },
        ],
      },
    ];
  }, [d, goTo]);
}

/* -------------------------------------------------------------- primitives */

function ReportPickerList({
  reports,
  activeId,
  onSelect,
}: {
  reports: ReportDef[];
  activeId: string;
  onSelect: (id: string) => void;
}) {
  return (
    <ul className="grid gap-1 sm:grid-cols-2 lg:grid-cols-1">
      {reports.map((r) => {
        const Icon = r.icon;
        const isActive = r.id === activeId;
        return (
          <li key={r.id}>
            <button
              type="button"
              onClick={() => onSelect(r.id)}
              className={`flex w-full items-center gap-2 rounded-xl px-3 py-2 text-left text-sm transition-colors ${
                isActive
                  ? "bg-primary/10 font-medium text-primary"
                  : "text-muted-foreground hover:bg-muted"
              }`}
            >
              <Icon className="size-4 shrink-0" />
              <span className="truncate">{r.label}</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function Field({
  label,
  htmlFor,
  children,
}: {
  label: string;
  htmlFor?: string;
  children: ReactNode;
}) {
  return (
    <div>
      <label className="text-xs font-medium text-muted-foreground" htmlFor={htmlFor}>
        {label}
      </label>
      <div className="mt-1">{children}</div>
    </div>
  );
}

function FacetSelect({
  label,
  value,
  onChange,
  options,
  disabled,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: Array<{ value: string; label: string }>;
  disabled?: boolean;
}) {
  return (
    <div className={disabled ? "opacity-45" : undefined}>
      <label className="text-xs font-medium text-muted-foreground">
        {label}
        {disabled && <span className="ml-1 text-[10px]">(n/a)</span>}
      </label>
      <Select value={value} onValueChange={onChange} disabled={disabled}>
        <SelectTrigger className="mt-1 h-9 w-52 rounded-xl">
          <SelectValue />
        </SelectTrigger>
        <SelectContent className="max-h-72">
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

function Stat({
  label,
  value,
  hint,
  tone,
}: {
  label: string;
  value: string;
  hint: string;
  tone?: "warning" | "good";
}) {
  const toneClass =
    tone === "warning"
      ? "text-amber-600 dark:text-amber-400"
      : tone === "good"
        ? "text-primary"
        : "";
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p
        className={`mt-2 truncate text-xl font-semibold tabular-nums xl:text-2xl ${toneClass}`}
        title={value}
      >
        {value}
      </p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}

const isMoney = (header: string) => /GHS/.test(header);
const isPercent = (header: string) => /%|Share/.test(header);

function formatCell(header: string, value: string | number) {
  if (typeof value !== "number") return value;
  if (isMoney(header)) return currency(value);
  if (isPercent(header)) return `${value.toFixed(1)}%`;
  return value.toLocaleString("en-GB");
}

function DataTable({ section }: { section: AnySection }) {
  const footer = section.rows.length > 0 ? section.footer?.(section.rows) : undefined;

  return (
    <section className="card-surface overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b p-4">
        <div>
          <h3 className="text-base font-semibold">{section.name}</h3>
          {section.hint && <p className="text-xs text-muted-foreground">{section.hint}</p>}
        </div>
        <p className="text-xs text-muted-foreground">{section.rows.length} rows</p>
      </div>
      {section.rows.length === 0 ? (
        <p className="p-10 text-center text-sm text-muted-foreground">
          Nothing matches the current filters.
        </p>
      ) : (
        <div className="max-h-[30rem] overflow-auto">
          <table className="w-full text-sm">
            <thead className="sticky top-0 z-10 bg-muted/70 text-left text-xs uppercase tracking-wide text-muted-foreground backdrop-blur">
              <tr>
                {section.columns.map((c) => (
                  <th
                    key={c.header}
                    className={`whitespace-nowrap px-4 py-3 font-medium ${
                      c.align === "right" ? "text-right" : ""
                    }`}
                  >
                    {c.header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y">
              {section.rows.map((row, i) => (
                <tr key={i} className="transition-colors hover:bg-muted/40">
                  {section.columns.map((c) => (
                    <td
                      key={c.header}
                      className={`whitespace-nowrap px-4 py-3 ${
                        c.align === "right" ? "text-right tabular-nums" : ""
                      }`}
                    >
                      {c.cell ? c.cell(row) : formatCell(c.header, c.value(row))}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
            {footer && (
              <tfoot className="sticky bottom-0 bg-muted/70 font-medium backdrop-blur">
                <tr>
                  {footer.map((cell, i) => (
                    <td
                      key={i}
                      className={`whitespace-nowrap px-4 py-3 ${
                        section.columns[i]?.align === "right" ? "text-right tabular-nums" : ""
                      }`}
                    >
                      {cell}
                    </td>
                  ))}
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      )}
    </section>
  );
}

/* ------------------------------------------------------------- print sheet */

function PrintableReport({
  title,
  description,
  company,
  summary,
  sections,
  stats,
}: {
  title: string;
  description: string;
  company: string;
  summary: string;
  sections: AnySection[];
  stats: ReportDef["stats"];
}) {
  return (
    <div
      style={{
        color: "#111",
        background: "#fff",
        fontFamily: "Inter, system-ui, sans-serif",
        fontSize: "9px",
        lineHeight: 1.4,
      }}
    >
      <div style={{ borderBottom: "1px solid #111", paddingBottom: "6px", marginBottom: "10px" }}>
        <p style={{ fontSize: "13px", fontWeight: 700 }}>{company}</p>
        <p style={{ fontSize: "11px", fontWeight: 600 }}>{title}</p>
        <p style={{ color: "#555" }}>{description}</p>
        <p style={{ color: "#555" }}>{summary}</p>
      </div>

      <div style={{ display: "flex", gap: "12px", marginBottom: "12px", flexWrap: "wrap" }}>
        {stats.map((s) => (
          <div
            key={s.label}
            style={{ border: "1px solid #ddd", padding: "6px 10px", minWidth: "110px" }}
          >
            <div style={{ color: "#666" }}>{s.label}</div>
            <div style={{ fontSize: "12px", fontWeight: 700 }}>{s.value}</div>
            <div style={{ color: "#888" }}>{s.hint}</div>
          </div>
        ))}
      </div>

      {sections.map((section) => (
        <div key={section.name} style={{ marginBottom: "14px", breakInside: "avoid" }}>
          <p style={{ fontWeight: 700, marginBottom: "4px" }}>{section.name}</p>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>
                {section.columns.map((c) => (
                  <th
                    key={c.header}
                    style={{
                      borderBottom: "1px solid #111",
                      padding: "3px 4px",
                      textAlign: c.align === "right" ? "right" : "left",
                      fontSize: "8px",
                      textTransform: "uppercase",
                      color: "#555",
                    }}
                  >
                    {c.header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {section.rows.map((row, i) => (
                <tr key={i}>
                  {section.columns.map((c) => (
                    <td
                      key={c.header}
                      style={{
                        borderBottom: "1px solid #eee",
                        padding: "3px 4px",
                        textAlign: c.align === "right" ? "right" : "left",
                      }}
                    >
                      {formatCell(c.header, c.value(row))}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
          {section.rows.length === 0 && (
            <p style={{ color: "#888", padding: "6px 0" }}>No data for this selection.</p>
          )}
        </div>
      ))}

      <p style={{ marginTop: "10px", color: "#888" }}>Generated by TCS on {formatDate(TODAY())}.</p>
    </div>
  );
}
