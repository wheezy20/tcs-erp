import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Landmark } from "lucide-react";

import { AsOfDateFilter } from "@/components/accounting/as-of-date-filter";
import { ExportMenu } from "@/components/export-menu";
import { useAccounts } from "@/data/accounts-store";
import { currency, TODAY } from "@/data/dashboard";
import { balanceSheet, type BalanceSheetSection } from "@/data/financial-reports";
import { useJournalEntries } from "@/data/journal-store";

export const Route = createFileRoute("/accounting/balance-sheet")({
  component: BalanceSheetPage,
});

function BalanceSheetPage() {
  const { accounts, loading: accountsLoading } = useAccounts();
  const { entries, loading: entriesLoading } = useJournalEntries();
  const [asOf, setAsOf] = useState(TODAY());

  const report = useMemo(() => balanceSheet(entries, accounts, asOf), [entries, accounts, asOf]);
  const balanced = Math.abs(report.totalAssets - report.totalLiabilitiesAndEquity) < 0.005;

  if (accountsLoading || entriesLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <AsOfDateFilter value={asOf} onChange={setAsOf} />
        <ExportMenu
          baseName="balance-sheet"
          filters={[asOf]}
          summary={`Balance Sheet as of ${asOf}`}
          getSheets={() => [
            {
              name: "Assets",
              columns: [
                { header: "Code", value: (r: { code: string }) => r.code },
                { header: "Account", value: (r: { name: string }) => r.name },
                { header: "Amount (GHS)", value: (r: { amount: number }) => r.amount },
              ],
              rows: report.assets.rows,
            },
            {
              name: "Liabilities",
              columns: [
                { header: "Code", value: (r: { code: string }) => r.code },
                { header: "Account", value: (r: { name: string }) => r.name },
                { header: "Amount (GHS)", value: (r: { amount: number }) => r.amount },
              ],
              rows: report.liabilities.rows,
            },
            {
              name: "Equity",
              columns: [
                { header: "Code", value: (r: { code: string }) => r.code },
                { header: "Account", value: (r: { name: string }) => r.name },
                { header: "Amount (GHS)", value: (r: { amount: number }) => r.amount },
              ],
              rows: report.equity.rows,
            },
          ]}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <SheetSection title="Assets" section={report.assets} />
        <div className="space-y-4">
          <SheetSection title="Liabilities" section={report.liabilities} />
          <SheetSection title="Equity" section={report.equity} />
        </div>
      </div>

      <div className="card-surface flex flex-wrap items-center justify-between gap-4 p-5">
        <div>
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Total Assets</p>
          <p className="text-lg font-semibold tabular-nums">{currency(report.totalAssets)}</p>
        </div>
        <Landmark className="size-5 text-muted-foreground" />
        <div className="text-right">
          <p className="text-xs uppercase tracking-wide text-muted-foreground">
            Total Liabilities + Equity
          </p>
          <p className="text-lg font-semibold tabular-nums">
            {currency(report.totalLiabilitiesAndEquity)}
          </p>
        </div>
      </div>

      <div
        className={
          "rounded-xl border px-5 py-3 text-sm font-medium " +
          (balanced
            ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
            : "border-destructive/30 bg-destructive/10 text-destructive")
        }
      >
        {balanced
          ? "Assets equal Liabilities plus Equity."
          : "Assets do not equal Liabilities plus Equity — this indicates a bug in the report, not a data issue."}
      </div>
    </div>
  );
}

function SheetSection({ title, section }: { title: string; section: BalanceSheetSection }) {
  return (
    <div className="card-surface overflow-hidden">
      <div className="border-b border-border px-5 py-3">
        <h3 className="text-sm font-semibold">{title}</h3>
      </div>
      {section.rows.length === 0 ? (
        <p className="px-5 py-6 text-center text-sm text-muted-foreground">No balance yet</p>
      ) : (
        <table className="w-full text-sm">
          <tbody className="divide-y">
            {section.rows.map((row) => (
              <tr key={row.accountId} className="hover:bg-muted/40">
                <td className="px-5 py-2.5">
                  <span className="font-mono text-xs text-muted-foreground">
                    {row.code ? `${row.code} · ` : ""}
                  </span>
                  {row.name}
                </td>
                <td className="px-5 py-2.5 text-right tabular-nums">{currency(row.amount)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot className="border-t-2 border-border font-semibold">
            <tr>
              <td className="px-5 py-3">Total {title}</td>
              <td className="px-5 py-3 text-right tabular-nums">{currency(section.total)}</td>
            </tr>
          </tfoot>
        </table>
      )}
    </div>
  );
}
