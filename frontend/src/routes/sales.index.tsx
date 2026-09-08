import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { FileText, Plus, Search } from "lucide-react";

import { ExportMenu } from "@/components/export-menu";
import { PageHeader } from "@/components/page-header";
import { SortableTh } from "@/components/sortable-th";
import { InvoiceStatusBadge } from "@/components/sales/invoice-status-badge";
import { ImportInvoicesDialog } from "@/components/sales/import-invoices-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useCurrentBranch } from "@/data/branch-store";
import { currency } from "@/data/dashboard";
import { invoiceTotals, type Invoice, type InvoiceTotals } from "@/data/invoices";
import { useSales } from "@/data/sales-store";
import { useSort } from "@/lib/use-sort";

export const Route = createFileRoute("/sales/")({
  head: () => ({
    meta: [
      { title: "Sales & Invoicing — TCS" },
      {
        name: "description",
        content:
          "Create invoices, apply discounts and VAT, record partial payments and track outstanding balances.",
      },
      { property: "og:title", content: "Sales & Invoicing — TCS" },
      {
        property: "og:description",
        content: "Invoice list with paid, partly paid and unpaid status filters.",
      },
    ],
  }),
  component: InvoiceListPage,
});

type Row = { invoice: Invoice; totals: InvoiceTotals };

type InvoiceSortKey = "date" | "customer" | "total";

const invoiceSortAccessors: Record<InvoiceSortKey, (r: Row) => string | number> = {
  date: (r) => r.invoice.date,
  customer: (r) => r.invoice.customerName,
  total: (r) => r.totals.total,
};

function InvoiceListPage() {
  const { invoices, customers } = useSales();
  const { name: branchName } = useCurrentBranch();
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("all");
  const [customer, setCustomer] = useState("all");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const rows = useMemo(
    () => invoices.map((invoice) => ({ invoice, totals: invoiceTotals(invoice) })),
    [invoices],
  );

  const filtered = rows.filter(({ invoice, totals }) => {
    const q = query.trim().toLowerCase();
    const matchesQuery =
      !q || invoice.id.toLowerCase().includes(q) || invoice.customerName.toLowerCase().includes(q);
    const matchesStatus = status === "all" || totals.status === status;
    const matchesCustomer = customer === "all" || invoice.customerId === customer;
    const matchesFrom = !from || invoice.date >= from;
    const matchesTo = !to || invoice.date <= to;
    return matchesQuery && matchesStatus && matchesCustomer && matchesFrom && matchesTo;
  });

  // Defaults to most-recent-first, matching this list's pre-existing default
  // order (before per-column sorting existed) rather than an arbitrary one.
  const { sortKey, sortDirection, toggleSort, sorted } = useSort<Row, InvoiceSortKey>(
    filtered,
    invoiceSortAccessors,
    { key: "date", direction: "desc" },
  );

  // Voided invoices still show in the list (so a Manager can find one) but
  // count toward none of the summary figures.
  const liveRows = rows.filter((r) => !r.invoice.voidedAt);
  const invoiced = liveRows.reduce((s, r) => s + r.totals.total, 0);
  const outstanding = liveRows.reduce((s, r) => s + r.totals.balance, 0);
  const unpaidCount = liveRows.filter((r) => r.totals.status !== "Paid").length;

  const resetFilters = () => {
    setQuery("");
    setStatus("all");
    setCustomer("all");
    setFrom("");
    setTo("");
  };

  return (
    <>
      <PageHeader
        title="Sales & Invoicing"
        description={`Invoices, discounts, VAT and payments for the ${branchName ?? "…"}.`}
        actions={
          <>
            <ExportMenu
              baseName="invoices"
              filters={[
                status !== "all" ? status : null,
                customer !== "all" ? customers.find((c) => c.id === customer)?.name : null,
                from && `from-${from}`,
                to && `to-${to}`,
                query,
              ]}
              summary={`${filtered.length} of ${rows.length} invoices, as filtered`}
              disabled={filtered.length === 0}
              getSheets={() => [
                {
                  name: "Invoices",
                  columns: [
                    { header: "Invoice", value: (r: Row) => r.invoice.id },
                    { header: "Customer", value: (r: Row) => r.invoice.customerName },
                    { header: "Date", value: (r: Row) => r.invoice.date },
                    { header: "Due date", value: (r: Row) => r.invoice.dueDate },
                    { header: "Branch", value: (r: Row) => r.invoice.branch },
                    { header: "Issued by", value: (r: Row) => r.invoice.issuedBy },
                    { header: "Subtotal (GHS)", value: (r: Row) => r.totals.subtotal },
                    {
                      header: "Discount (GHS)",
                      value: (r: Row) => r.totals.lineDiscounts + r.totals.invoiceDiscount,
                    },
                    { header: "VAT (GHS)", value: (r: Row) => r.totals.vat },
                    { header: "Total (GHS)", value: (r: Row) => r.totals.total },
                    { header: "Paid (GHS)", value: (r: Row) => r.totals.paid },
                    { header: "Balance (GHS)", value: (r: Row) => r.totals.balance },
                    { header: "Status", value: (r: Row) => r.totals.status },
                  ],
                  rows: filtered,
                },
              ]}
            />
            <ImportInvoicesDialog />
            <Button asChild className="gap-2">
              <Link to="/sales/new">
                <Plus className="size-4" /> New invoice
              </Link>
            </Button>
          </>
        }
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard
          label="Total invoiced"
          value={currency(invoiced)}
          hint={`${liveRows.length} invoices`}
        />
        <SummaryCard
          label="Outstanding balance"
          value={currency(outstanding)}
          hint={`${unpaidCount} invoices awaiting payment`}
          tone={outstanding > 0 ? "warning" : "default"}
        />
        <SummaryCard
          label="Collected"
          value={currency(invoiced - outstanding)}
          hint="Payments received to date"
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-56 flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search invoice number or customer"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
          <Select value={status} onValueChange={setStatus}>
            <SelectTrigger className="h-10 w-40 rounded-xl">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All statuses</SelectItem>
              <SelectItem value="Paid">Paid</SelectItem>
              <SelectItem value="Partly paid">Partly paid</SelectItem>
              <SelectItem value="Unpaid">Unpaid</SelectItem>
            </SelectContent>
          </Select>
          <Select value={customer} onValueChange={setCustomer}>
            <SelectTrigger className="h-10 w-52 rounded-xl">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All customers</SelectItem>
              {customers.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Input
            type="date"
            value={from}
            onChange={(e) => setFrom(e.target.value)}
            className="h-10 w-40 rounded-xl"
            aria-label="From date"
          />
          <Input
            type="date"
            value={to}
            onChange={(e) => setTo(e.target.value)}
            className="h-10 w-40 rounded-xl"
            aria-label="To date"
          />
          <Button variant="ghost" className="h-10" onClick={resetFilters}>
            Reset
          </Button>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <FileText className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No invoices match your filters</p>
            <p className="text-sm text-muted-foreground">
              Try another status, customer or date range.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Invoice</th>
                  <SortableTh<InvoiceSortKey>
                    label="Customer"
                    sortKeyValue="customer"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                  />
                  <SortableTh<InvoiceSortKey>
                    label="Date"
                    sortKeyValue="date"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                  />
                  <SortableTh<InvoiceSortKey>
                    label="Total"
                    sortKeyValue="total"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                    align="right"
                  />
                  <th className="px-5 py-3 text-right font-medium">Paid</th>
                  <th className="px-5 py-3 text-right font-medium">Balance</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {sorted.map(({ invoice, totals }) => (
                  <tr key={invoice.id} className="group hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/sales/$invoiceId"
                        params={{ invoiceId: invoice.id }}
                        className="font-medium group-hover:text-primary"
                      >
                        {invoice.id}
                      </Link>
                      <p className="text-xs text-muted-foreground">
                        {invoice.lines.length} line items
                      </p>
                    </td>
                    <td className="px-5 py-3">
                      <Link
                        to="/customers/$customerId"
                        params={{ customerId: invoice.customerId }}
                        className="hover:text-primary"
                      >
                        {invoice.customerName}
                      </Link>
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{invoice.date}</td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(totals.total)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums text-muted-foreground">
                      {currency(totals.paid)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums font-medium">
                      {invoice.voidedAt || totals.balance <= 0 ? "—" : currency(totals.balance)}
                    </td>
                    <td className="px-5 py-3">
                      {invoice.voidedAt ? (
                        <span className="inline-flex items-center rounded-full bg-destructive/10 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-destructive">
                          Voided
                        </span>
                      ) : (
                        <InvoiceStatusBadge status={totals.status} />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function SummaryCard({
  label,
  value,
  hint,
  tone = "default",
}: {
  label: string;
  value: string;
  hint: string;
  tone?: "default" | "warning";
}) {
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p
        className={
          tone === "warning"
            ? "mt-2 text-2xl font-semibold tabular-nums text-amber-600 dark:text-amber-400"
            : "mt-2 text-2xl font-semibold tabular-nums"
        }
      >
        {value}
      </p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
