import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Receipt, Search } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { ExportMenu } from "@/components/export-menu";
import { RecordExpenseDialog } from "@/components/expenses/record-expense-dialog";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currencyPrecise } from "@/data/dashboard";
import { EXPENSE_METHODS, expenseTotal, type Expense } from "@/data/expenses";
import { useExpenses } from "@/data/expenses-store";
import { formatDate, useDocumentSettings } from "@/data/settings-store";

export const Route = createFileRoute("/expenses/")({
  head: () => ({
    meta: [
      { title: "Expenses — TCS" },
      {
        name: "description",
        content:
          "Record and review business expenses by category, payment method and date range, with receipts attached.",
      },
      { property: "og:title", content: "Expenses — TCS" },
      {
        property: "og:description",
        content:
          "Record and review business expenses by category, payment method and date range, with receipts attached.",
      },
    ],
  }),
  component: ExpensesPage,
});

function ExpensesPage() {
  const { staff } = useAuth();
  const canWrite = canWriteFinancials(staff?.role);
  const { expenses, categories: knownCategories } = useExpenses();
  const settings = useDocumentSettings();

  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("all");
  const [method, setMethod] = useState("all");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const categories = useMemo(
    () => [...new Set([...knownCategories, ...expenses.map((e) => e.category)])],
    [knownCategories, expenses],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return expenses
      .filter((e) => {
        if (category !== "all" && e.category !== category) return false;
        if (method !== "all" && e.method !== method) return false;
        if (from && e.date < from) return false;
        if (to && e.date > to) return false;
        if (!q) return true;
        return (
          e.description.toLowerCase().includes(q) ||
          e.category.toLowerCase().includes(q) ||
          e.recordedBy.toLowerCase().includes(q) ||
          e.id.toLowerCase().includes(q) ||
          (e.reference ?? "").toLowerCase().includes(q)
        );
      })
      .sort((a, b) => (a.date === b.date ? b.id.localeCompare(a.id) : a.date < b.date ? 1 : -1));
  }, [expenses, query, category, method, from, to]);

  // A voided expense still appears in the list (so a Manager can find one),
  // but counts toward none of the summary figures — it's an erasure, not a
  // real cost.
  const liveFiltered = filtered.filter((e) => !e.voidedAt);
  const total = expenseTotal(liveFiltered);
  const cashTotal = expenseTotal(liveFiltered.filter((e) => e.method === "Cash"));
  const filtersApplied =
    Boolean(query) || category !== "all" || method !== "all" || Boolean(from) || Boolean(to);

  return (
    <>
      <PageHeader
        title="Expenses"
        description="Money going out of the business — cash, mobile money and bank."
        actions={
          <>
            <ExportMenu
              baseName="expenses"
              filters={[
                category !== "all" && category,
                method !== "all" && method,
                query,
                from,
                to,
              ]}
              summary={`${filtered.length} of ${expenses.length} expenses, as filtered`}
              disabled={filtered.length === 0}
              getSheets={() => [
                {
                  name: "Expenses",
                  columns: [
                    { header: "Reference", value: (e: Expense) => e.id },
                    { header: "Date", value: (e: Expense) => e.date },
                    { header: "Category", value: (e: Expense) => e.category },
                    { header: "Description", value: (e: Expense) => e.description },
                    { header: "Amount (GHS)", value: (e: Expense) => e.amount },
                    { header: "Payment method", value: (e: Expense) => e.method },
                    { header: "Payment reference", value: (e: Expense) => e.reference ?? "" },
                    { header: "Recorded by", value: (e: Expense) => e.recordedBy },
                    { header: "Recorded at", value: (e: Expense) => e.recordedAt },
                    {
                      header: "Receipt attached",
                      value: (e: Expense) => (e.receiptUrl ? "Yes" : "No"),
                    },
                  ],
                  rows: filtered,
                },
              ]}
            />
            {canWrite && <RecordExpenseDialog />}
          </>
        }
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard
          label={filtersApplied ? "Total (filtered)" : "Total expenses"}
          value={currencyPrecise(total)}
          hint={`${liveFiltered.length} expense${liveFiltered.length === 1 ? "" : "s"} in view`}
        />
        <SummaryCard
          label="Paid in cash"
          value={currencyPrecise(cashTotal)}
          hint="Deducted from cash on hand"
        />
        <SummaryCard
          label="Average expense"
          value={currencyPrecise(liveFiltered.length ? total / liveFiltered.length : 0)}
          hint="Across the current selection"
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="space-y-4 border-b p-4">
          <div className="relative max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search description, category, reference or staff"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>

          <div className="flex flex-wrap items-end gap-3">
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Category</Label>
              <Select value={category} onValueChange={setCategory}>
                <SelectTrigger className="w-[190px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All categories</SelectItem>
                  {categories.map((c) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Payment method</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger className="w-[170px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All methods</SelectItem>
                  {EXPENSE_METHODS.map((m) => (
                    <SelectItem key={m} value={m}>
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">From</Label>
              <Input
                type="date"
                value={from}
                onChange={(e) => setFrom(e.target.value)}
                className="w-[160px]"
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">To</Label>
              <Input
                type="date"
                value={to}
                onChange={(e) => setTo(e.target.value)}
                className="w-[160px]"
              />
            </div>

            {filtersApplied && (
              <Button
                variant="ghost"
                onClick={() => {
                  setQuery("");
                  setCategory("all");
                  setMethod("all");
                  setFrom("");
                  setTo("");
                }}
              >
                Clear filters
              </Button>
            )}
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <Receipt className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No expenses match these filters</p>
            <p className="text-sm text-muted-foreground">
              Try a wider date range or a different category.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 font-medium">Category</th>
                  <th className="px-5 py-3 font-medium">Description</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                  <th className="px-5 py-3 font-medium">Method</th>
                  <th className="px-5 py-3 font-medium">Recorded by</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((e) => (
                  <tr
                    key={e.id}
                    className={`group hover:bg-muted/40 ${e.voidedAt ? "text-muted-foreground" : ""}`}
                  >
                    <td className="px-5 py-3 tabular-nums text-muted-foreground">
                      {formatDate(e.date, settings.localisation.dateFormat)}
                    </td>
                    <td className="px-5 py-3">
                      <span className="inline-flex rounded-lg bg-muted px-2 py-0.5 text-xs font-medium">
                        {e.category}
                      </span>
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-3">
                        {e.receiptUrl ? (
                          <img
                            src={e.receiptUrl}
                            alt={`Receipt for ${e.description}`}
                            className="size-9 shrink-0 rounded-lg border object-cover"
                          />
                        ) : (
                          <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-muted">
                            <Receipt className="size-4 text-muted-foreground" />
                          </div>
                        )}
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <Link
                              to="/expenses/$expenseId"
                              params={{ expenseId: e.id }}
                              className={`font-medium group-hover:text-primary ${e.voidedAt ? "line-through" : ""}`}
                            >
                              {e.description}
                            </Link>
                            {e.voidedAt ? (
                              <span className="inline-flex items-center rounded-full bg-destructive/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-destructive">
                                Voided
                              </span>
                            ) : null}
                          </div>
                          <p className="text-xs text-muted-foreground">
                            {e.id}
                            {e.reference ? ` · ${e.reference}` : ""}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currencyPrecise(e.amount)}
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{e.method}</td>
                    <td className="px-5 py-3 text-muted-foreground">{e.recordedBy}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t bg-muted/40 text-sm">
                <tr>
                  <td colSpan={3} className="px-5 py-3 font-medium">
                    Total ({liveFiltered.length})
                  </td>
                  <td className="px-5 py-3 text-right font-semibold tabular-nums">
                    {currencyPrecise(total)}
                  </td>
                  <td colSpan={2} />
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function SummaryCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tracking-tight">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
