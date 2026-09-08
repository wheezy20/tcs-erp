import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { ChevronDown, ChevronUp, Receipt, Search } from "lucide-react";

import { ExportMenu } from "@/components/export-menu";
import { VoidTransactionDialog } from "@/components/void-transaction-dialog";
import { useAuth } from "@/data/auth-store";
import { useBankAccounts } from "@/data/bank-accounts-store";
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
import { currency } from "@/data/dashboard";
import {
  discountAmount,
  lineGross,
  lineNet,
  lineTaxable,
  posTotals,
  POS_METHODS,
  type PosSale,
} from "@/data/pos";
import { usePosSales, voidSale } from "@/data/pos-store";

export const Route = createFileRoute("/pos/history")({
  head: () => ({
    meta: [{ title: "Sales history — TCS POS" }],
  }),
  // Optional deep-link seed for the search box — e.g. the Dashboard's
  // Recent Transactions list links a POS sale straight to its own receipt
  // number here, since there's no separate per-sale detail route to land
  // on instead (unlike invoices' /sales/$invoiceId).
  validateSearch: (search: Record<string, unknown>): { q?: string } => ({
    q: typeof search.q === "string" ? search.q : undefined,
  }),
  component: PosHistoryPage,
});

type Row = { sale: PosSale; totals: ReturnType<typeof posTotals> };

/** "Cash GHS200 + Mobile Money GHS94" — one column instead of a variable
 * number of payment columns, the same flattening `itemsSummary()` does for
 * a customer's order lines in customers.$customerId.tsx. */
function paymentsSummary(sale: PosSale) {
  return sale.payments.map((p) => `${p.method} ${currency(p.amount)}`).join(" + ");
}

function PosHistoryPage() {
  const { sales } = usePosSales();
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";
  const { accounts: bankAccounts } = useBankAccounts();
  const { q } = Route.useSearch();
  const [query, setQuery] = useState(q ?? "");
  const [method, setMethod] = useState("all");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  // One expanded row at a time — the same lightweight pattern
  // accounting.journal-entries.tsx uses for its own line-item drill-down.
  const [expanded, setExpanded] = useState<string | null>(null);

  const bankName = (id: string | null | undefined) =>
    id ? (bankAccounts.find((a) => a.id === id)?.name ?? "Unknown bank") : null;

  const rows = useMemo<Row[]>(
    () =>
      sales
        .map((sale) => ({ sale, totals: posTotals(sale) }))
        .sort((a, b) => (a.sale.date === b.sale.date ? 1 : a.sale.date < b.sale.date ? 1 : -1)),
    [sales],
  );

  const filtered = rows.filter(({ sale }) => {
    const q = query.trim().toLowerCase();
    const matchesQuery =
      !q ||
      sale.id.toLowerCase().includes(q) ||
      sale.customerName.toLowerCase().includes(q) ||
      sale.cashier.toLowerCase().includes(q);
    const matchesMethod = method === "all" || sale.payments.some((p) => p.method === method);
    const matchesFrom = !from || sale.date >= from;
    const matchesTo = !to || sale.date <= to;
    return matchesQuery && matchesMethod && matchesFrom && matchesTo;
  });

  // Voided receipts still appear in the list (so a Manager can find one),
  // but count toward none of the summary figures.
  const liveRows = rows.filter((r) => !r.sale.voidedAt);
  const totalSales = liveRows.reduce((s, r) => s + r.totals.total, 0);
  const totalChange = liveRows.reduce((s, r) => s + r.totals.change, 0);
  const returnsCount = liveRows.filter((r) => r.sale.returns.length > 0).length;

  const resetFilters = () => {
    setQuery("");
    setMethod("all");
    setFrom("");
    setTo("");
  };

  return (
    <>
      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard
          label="Total sales"
          value={currency(totalSales)}
          hint={`${liveRows.length} receipt${liveRows.length === 1 ? "" : "s"}`}
        />
        <SummaryCard
          label="Change given"
          value={currency(totalChange)}
          hint="Over cash payments, across all receipts"
        />
        <SummaryCard
          label="Receipts with a return"
          value={String(returnsCount)}
          hint="At least one line returned or exchanged"
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-56 flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search receipt, customer or cashier"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
          <Select value={method} onValueChange={setMethod}>
            <SelectTrigger className="h-10 w-44 rounded-xl">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All payment methods</SelectItem>
              {POS_METHODS.map((m) => (
                <SelectItem key={m} value={m}>
                  {m}
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
          <ExportMenu
            baseName="pos-sales"
            filters={[
              method !== "all" ? method : null,
              from && `from-${from}`,
              to && `to-${to}`,
              query,
            ]}
            summary={`${filtered.length} of ${rows.length} receipts, as filtered`}
            disabled={filtered.length === 0}
            size="sm"
            getSheets={() => [
              {
                name: "POS sales",
                columns: [
                  { header: "Receipt", value: (r: Row) => r.sale.id },
                  { header: "Date", value: (r: Row) => r.sale.date },
                  { header: "Time", value: (r: Row) => r.sale.time },
                  { header: "Customer", value: (r: Row) => r.sale.customerName },
                  { header: "Cashier", value: (r: Row) => r.sale.cashier },
                  { header: "Branch", value: (r: Row) => r.sale.branch },
                  { header: "Subtotal (GHS)", value: (r: Row) => r.totals.subtotal },
                  {
                    header: "Discount (GHS)",
                    value: (r: Row) => r.totals.lineDiscounts + r.totals.saleDiscount,
                  },
                  { header: "VAT (GHS)", value: (r: Row) => r.totals.vat },
                  { header: "Total (GHS)", value: (r: Row) => r.totals.total },
                  { header: "Paid (GHS)", value: (r: Row) => r.totals.paid },
                  { header: "Change (GHS)", value: (r: Row) => r.totals.change },
                  { header: "Payments", value: (r: Row) => paymentsSummary(r.sale) },
                  { header: "Returns", value: (r: Row) => r.sale.returns.length },
                ],
                rows: filtered,
              },
            ]}
          />
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <Receipt className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No sales match your filters</p>
            <p className="text-sm text-muted-foreground">
              Try another payment method, customer or date range.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="w-8 px-3 py-3" />
                  <th className="px-5 py-3 font-medium">Receipt</th>
                  <th className="px-5 py-3 font-medium">Customer</th>
                  <th className="px-5 py-3 font-medium">Cashier</th>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 font-medium">Payment</th>
                  <th className="px-5 py-3 font-medium">Returns</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map(({ sale, totals }) => {
                  const isOpen = expanded === sale.id;
                  return (
                    <SaleRows
                      key={sale.id}
                      sale={sale}
                      totals={totals}
                      open={isOpen}
                      onToggle={() => setExpanded(isOpen ? null : sale.id)}
                      bankName={bankName}
                      isManager={isManager}
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

/** One sale: the compact list row (unchanged columns), plus a drill-down
 * row — the actual line items, the payment breakdown, the checkout note
 * and any returns — that only renders when the row is expanded, so the
 * list itself stays uncluttered. */
function SaleRows({
  sale,
  totals,
  open,
  onToggle,
  bankName,
  isManager,
}: {
  sale: PosSale;
  totals: ReturnType<typeof posTotals>;
  open: boolean;
  onToggle: () => void;
  bankName: (id: string | null | undefined) => string | null;
  isManager: boolean;
}) {
  return (
    <>
      <tr
        className={`cursor-pointer hover:bg-muted/40 ${sale.voidedAt ? "text-muted-foreground" : ""}`}
        onClick={onToggle}
      >
        <td className="px-3 py-3 text-muted-foreground">
          {open ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}
        </td>
        <td className="px-5 py-3">
          <p className="flex items-center gap-2 font-medium">
            <span className={sale.voidedAt ? "line-through" : ""}>{sale.id}</span>
            {sale.voidedAt ? (
              <span className="inline-flex items-center rounded-full bg-destructive/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-destructive">
                Voided
              </span>
            ) : null}
          </p>
          <p className="text-xs text-muted-foreground">
            {sale.lines.length} line item{sale.lines.length === 1 ? "" : "s"}
            {sale.notes.trim() ? " · note" : ""}
          </p>
        </td>
        <td className="px-5 py-3">{sale.customerName}</td>
        <td className="px-5 py-3 text-muted-foreground">{sale.cashier}</td>
        <td className="px-5 py-3 text-muted-foreground">
          {sale.date} · {sale.time}
        </td>
        <td className="px-5 py-3 text-right font-medium tabular-nums">{currency(totals.total)}</td>
        <td className="px-5 py-3 text-muted-foreground">{paymentsSummary(sale)}</td>
        <td className="px-5 py-3">
          {sale.returns.length > 0 ? (
            <Badge variant="secondary">{sale.returns.length}</Badge>
          ) : (
            <span className="text-muted-foreground">—</span>
          )}
        </td>
      </tr>
      {open && (
        <tr>
          <td colSpan={8} className="bg-muted/20 px-5 py-4">
            <div className="space-y-4">
              <div>
                <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Items
                </p>
                <table className="w-full text-xs">
                  <thead className="text-left uppercase tracking-wide text-muted-foreground">
                    <tr>
                      <th className="py-1.5 pr-4 font-medium">Item</th>
                      <th className="py-1.5 pr-4 text-right font-medium">Qty × price</th>
                      <th className="py-1.5 pr-4 text-right font-medium">Discount</th>
                      <th className="py-1.5 pr-4 font-medium">VAT</th>
                      <th className="py-1.5 text-right font-medium">Line total</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border/60">
                    {sale.lines.map((line) => {
                      const disc = discountAmount(line.discount, lineGross(line));
                      return (
                        <tr key={line.id}>
                          <td className="py-1.5 pr-4">{line.name}</td>
                          <td className="py-1.5 pr-4 text-right tabular-nums">
                            {line.quantity} {String(line.unit).toLowerCase()} ×{" "}
                            {currency(line.unitPrice)}
                          </td>
                          <td className="py-1.5 pr-4 text-right tabular-nums">
                            {disc > 0 ? `-${currency(disc)}` : "—"}
                          </td>
                          <td className="py-1.5 pr-4 text-muted-foreground">
                            {lineTaxable(line, sale.vatMode) ? "Yes" : "No"}
                          </td>
                          <td className="py-1.5 text-right tabular-nums">
                            {currency(lineNet(line))}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Payment
                  </p>
                  <ul className="space-y-1 text-xs">
                    {sale.payments.map((p) => (
                      <li key={p.id} className="flex justify-between gap-4">
                        <span>
                          {p.method}
                          {bankName(p.bankAccountId) ? ` · ${bankName(p.bankAccountId)}` : ""}
                          {p.reference ? ` · ${p.reference}` : ""}
                        </span>
                        <span className="tabular-nums">{currency(p.amount)}</span>
                      </li>
                    ))}
                    <li className="flex justify-between gap-4 border-t border-border/60 pt-1 font-medium">
                      <span>Subtotal / VAT / total</span>
                      <span className="tabular-nums">
                        {currency(totals.subtotal)} / {currency(totals.vat)} /{" "}
                        {currency(totals.total)}
                      </span>
                    </li>
                    {totals.change > 0 && (
                      <li className="flex justify-between gap-4 text-muted-foreground">
                        <span>Change given</span>
                        <span className="tabular-nums">{currency(totals.change)}</span>
                      </li>
                    )}
                  </ul>
                </div>

                <div className="space-y-3">
                  {sale.notes.trim() && (
                    <div>
                      <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                        Note
                      </p>
                      <p className="whitespace-pre-wrap text-xs">{sale.notes.trim()}</p>
                    </div>
                  )}
                  {sale.returns.length > 0 && (
                    <div>
                      <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                        Returns / exchanges ({sale.returns.length})
                      </p>
                      <ul className="space-y-1 text-xs">
                        {sale.returns.map((r) => (
                          <li key={r.id}>
                            {r.returned.quantity} × {r.returned.name} — {r.resolution}
                            {r.replacement ? ` (for ${r.replacement.name})` : ""} · {r.date}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              </div>

              {sale.voidedAt ? (
                <div className="rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs">
                  <span className="font-semibold text-destructive">Voided</span>
                  {sale.voidedBy ? ` by ${sale.voidedBy}` : ""} on{" "}
                  {new Date(sale.voidedAt).toLocaleDateString()} — ledger reversed, stock restored.
                  {sale.voidReason ? (
                    <span className="mt-0.5 block text-muted-foreground">
                      Reason: {sale.voidReason}
                    </span>
                  ) : null}
                </div>
              ) : isManager ? (
                <div className="flex justify-end border-t pt-3">
                  <VoidTransactionDialog
                    kind="sale"
                    id={sale.id}
                    onVoid={(reason) => voidSale(sale.id, reason)}
                  />
                </div>
              ) : null}
            </div>
          </td>
        </tr>
      )}
    </>
  );
}

function SummaryCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tabular-nums">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
