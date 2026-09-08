import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";

import { DateRangeFilter } from "@/components/accounting/date-range-filter";
import { ExportMenu } from "@/components/export-menu";
import { useAccounts } from "@/data/accounts-store";
import { currency } from "@/data/dashboard";
import { profitAndLoss, type PLRow } from "@/data/financial-reports";
import { useJournalEntries } from "@/data/journal-store";
import { defaultFilters, type RangePreset } from "@/data/reports";

export const Route = createFileRoute("/accounting/profit-loss")({
  component: ProfitLossPage,
});

function ProfitLossPage() {
  const { accounts, loading: accountsLoading } = useAccounts();
  const { entries, loading: entriesLoading } = useJournalEntries();
  const initial = defaultFilters();
  const [range, setRange] = useState<{ preset: RangePreset; from: string; to: string }>({
    preset: initial.preset,
    from: initial.from,
    to: initial.to,
  });

  const report = useMemo(
    () => profitAndLoss(entries, accounts, range.from, range.to),
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
          baseName="profit-and-loss"
          filters={[range.from || "all", range.to || "now"]}
          summary={`Profit & Loss · ${rangeLabel}`}
          getSheets={() => [
            {
              name: "Revenue",
              columns: plColumns,
              rows: report.revenue,
            },
            {
              name: "Cost of Goods Sold",
              columns: plColumns,
              rows: report.cogs,
            },
            {
              name: "Operating Expenses",
              columns: plColumns,
              rows: report.operatingExpenses,
            },
          ]}
        />
      </div>

      <div className="card-surface overflow-hidden">
        <PLSection title="Revenue" rows={report.revenue} total={report.totalRevenue} />
        <PLSection title="Cost of Goods Sold" rows={report.cogs} total={report.totalCogs} />
        <div className="flex items-center justify-between border-y bg-muted/40 px-5 py-3 font-semibold">
          <span>Gross profit</span>
          <span className="tabular-nums">{currency(report.grossProfit)}</span>
        </div>
        <PLSection
          title="Operating Expenses"
          rows={report.operatingExpenses}
          total={report.totalOperatingExpenses}
        />
        <div className="flex items-center justify-between border-t-2 border-border px-5 py-4 text-lg font-bold">
          <span>Net profit</span>
          <span className="tabular-nums">{currency(report.netProfit)}</span>
        </div>
      </div>
      <p className="text-xs text-muted-foreground">
        Net profit here means Revenue minus Cost of Goods Sold minus every recorded expense account
        in the chart — the only figure in this app allowed to use that name. "Gross profit" and
        "operating margin" elsewhere (Reports) are narrower figures computed before Accounting
        existed and keep their own labels.
      </p>
    </div>
  );
}

const plColumns = [
  { header: "Code", value: (r: PLRow) => r.code },
  { header: "Account", value: (r: PLRow) => r.name },
  { header: "Amount (GHS)", value: (r: PLRow) => r.amount },
];

function PLSection({ title, rows, total }: { title: string; rows: PLRow[]; total: number }) {
  return (
    <div>
      <div className="bg-muted/20 px-5 py-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        {title}
      </div>
      {rows.length === 0 ? (
        <p className="px-5 py-4 text-sm text-muted-foreground">Nothing posted in this range</p>
      ) : (
        <table className="w-full text-sm">
          <tbody className="divide-y">
            {rows.map((row) => (
              <tr key={row.accountId} className="hover:bg-muted/40">
                <td className="px-5 py-2.5">
                  <span className="font-mono text-xs text-muted-foreground">{row.code} · </span>
                  {row.name}
                </td>
                <td className="px-5 py-2.5 text-right tabular-nums">{currency(row.amount)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot className="border-t font-medium">
            <tr>
              <td className="px-5 py-2.5">Total {title}</td>
              <td className="px-5 py-2.5 text-right tabular-nums">{currency(total)}</td>
            </tr>
          </tfoot>
        </table>
      )}
    </div>
  );
}
