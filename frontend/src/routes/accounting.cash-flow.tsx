import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { ArrowDownRight, ArrowUpRight, Wallet } from "lucide-react";

import { DateRangeFilter } from "@/components/accounting/date-range-filter";
import { ExportMenu } from "@/components/export-menu";
import { useAccounts } from "@/data/accounts-store";
import { currency } from "@/data/dashboard";
import { cashFlow, type CashFlowSourceRow } from "@/data/financial-reports";
import { useJournalEntries } from "@/data/journal-store";
import { defaultFilters, type RangePreset } from "@/data/reports";

export const Route = createFileRoute("/accounting/cash-flow")({
  component: CashFlowPage,
});

function CashFlowPage() {
  const { accounts, loading: accountsLoading } = useAccounts();
  const { entries, loading: entriesLoading } = useJournalEntries();
  const initial = defaultFilters();
  const [range, setRange] = useState<{ preset: RangePreset; from: string; to: string }>({
    preset: initial.preset,
    from: initial.from,
    to: initial.to,
  });

  const report = useMemo(
    () => cashFlow(entries, accounts, range.from, range.to),
    [entries, accounts, range.from, range.to],
  );

  if (accountsLoading || entriesLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const rangeLabel =
    range.from || range.to ? `${range.from || "start"} → ${range.to || "now"}` : "All time";

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <DateRangeFilter
          preset={range.preset}
          from={range.from}
          to={range.to}
          onChange={setRange}
        />
        <ExportMenu
          baseName="cash-flow"
          filters={[range.from || "all", range.to || "now"]}
          summary={`Cash Flow · ${rangeLabel}`}
          getSheets={() => [
            {
              name: "Cash Flow by source",
              columns: [
                { header: "Source", value: (r: CashFlowSourceRow) => r.source },
                { header: "Cash in (GHS)", value: (r: CashFlowSourceRow) => r.in },
                { header: "Cash out (GHS)", value: (r: CashFlowSourceRow) => r.out },
                { header: "Net (GHS)", value: (r: CashFlowSourceRow) => r.net },
              ],
              rows: report.bySource,
            },
          ]}
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <StatCard
          icon={ArrowUpRight}
          label="Cash in"
          value={currency(report.totalIn)}
          tone="text-emerald-600 dark:text-emerald-400"
        />
        <StatCard
          icon={ArrowDownRight}
          label="Cash out"
          value={currency(report.totalOut)}
          tone="text-destructive"
        />
        <StatCard icon={Wallet} label="Net cash flow" value={currency(report.net)} />
      </div>

      <div className="card-surface overflow-hidden">
        <div className="border-b border-border px-5 py-3">
          <h3 className="text-sm font-semibold">By source</h3>
          <p className="text-xs text-muted-foreground">
            Every posted journal entry that touched Cash on Hand, Cash in Bank or Mobile Money
            Float, grouped by the same transaction type shown in Journal Entries. A transfer between
            two of those accounts (e.g. a bank deposit) nets to zero here — it moves cash between
            accounts, it isn't new cash in or out.
          </p>
        </div>
        {report.bySource.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-muted-foreground">
            No cash activity in this range
          </p>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-5 py-3 font-medium">Source</th>
                <th className="px-5 py-3 text-right font-medium">Cash in</th>
                <th className="px-5 py-3 text-right font-medium">Cash out</th>
                <th className="px-5 py-3 text-right font-medium">Net</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {report.bySource.map((row) => (
                <tr key={row.source} className="hover:bg-muted/40">
                  <td className="px-5 py-3">{row.source}</td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    {row.in > 0 ? currency(row.in) : ""}
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    {row.out > 0 ? currency(row.out) : ""}
                  </td>
                  <td className="px-5 py-3 text-right font-medium tabular-nums">
                    {currency(row.net)}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t-2 border-border font-semibold">
              <tr>
                <td className="px-5 py-3">Total</td>
                <td className="px-5 py-3 text-right tabular-nums">{currency(report.totalIn)}</td>
                <td className="px-5 py-3 text-right tabular-nums">{currency(report.totalOut)}</td>
                <td className="px-5 py-3 text-right tabular-nums">{currency(report.net)}</td>
              </tr>
            </tfoot>
          </table>
        )}
      </div>
    </div>
  );
}

function StatCard({
  icon: Icon,
  label,
  value,
  tone,
}: {
  icon: typeof Wallet;
  label: string;
  value: string;
  tone?: string;
}) {
  return (
    <div className="card-surface flex items-center gap-3 p-4">
      <div className="rounded-xl bg-muted p-2.5">
        <Icon className={`size-5 ${tone ?? "text-muted-foreground"}`} />
      </div>
      <div>
        <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
        <p className={`text-lg font-semibold tabular-nums ${tone ?? ""}`}>{value}</p>
      </div>
    </div>
  );
}
