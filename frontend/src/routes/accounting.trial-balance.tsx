import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Scale } from "lucide-react";

import { AsOfDateFilter } from "@/components/accounting/as-of-date-filter";
import { ExportMenu } from "@/components/export-menu";
import { useAccounts } from "@/data/accounts-store";
import { currency, TODAY } from "@/data/dashboard";
import { trialBalance } from "@/data/financial-reports";
import { useJournalEntries } from "@/data/journal-store";

export const Route = createFileRoute("/accounting/trial-balance")({
  component: TrialBalancePage,
});

function TrialBalancePage() {
  const { accounts, loading: accountsLoading } = useAccounts();
  const { entries, loading: entriesLoading } = useJournalEntries();
  const [asOf, setAsOf] = useState(TODAY());

  const report = useMemo(() => trialBalance(entries, accounts, asOf), [entries, accounts, asOf]);
  const balanced = Math.abs(report.totalDebit - report.totalCredit) < 0.005;

  if (accountsLoading || entriesLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <AsOfDateFilter value={asOf} onChange={setAsOf} />
        <ExportMenu
          baseName="trial-balance"
          filters={[asOf]}
          summary={`Trial Balance as of ${asOf}`}
          getSheets={() => [
            {
              name: "Trial Balance",
              columns: [
                { header: "Code", value: (r: (typeof report.rows)[number]) => r.code },
                { header: "Account", value: (r: (typeof report.rows)[number]) => r.name },
                { header: "Category", value: (r: (typeof report.rows)[number]) => r.category },
                { header: "Debit (GHS)", value: (r: (typeof report.rows)[number]) => r.debit },
                { header: "Credit (GHS)", value: (r: (typeof report.rows)[number]) => r.credit },
              ],
              rows: report.rows,
            },
          ]}
        />
      </div>

      {report.rows.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Scale className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No postings on or before {asOf} yet</p>
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Code</th>
                  <th className="px-5 py-3 font-medium">Account</th>
                  <th className="px-5 py-3 font-medium">Category</th>
                  <th className="px-5 py-3 text-right font-medium">Debit</th>
                  <th className="px-5 py-3 text-right font-medium">Credit</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {report.rows.map((row) => (
                  <tr key={row.accountId} className="hover:bg-muted/40">
                    <td className="px-5 py-3 font-mono tabular-nums">{row.code}</td>
                    <td className="px-5 py-3">{row.name}</td>
                    <td className="px-5 py-3 text-muted-foreground">{row.category}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {row.debit > 0 ? currency(row.debit) : ""}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {row.credit > 0 ? currency(row.credit) : ""}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t-2 border-border font-semibold">
                <tr>
                  <td className="px-5 py-3" colSpan={3}>
                    Total
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    {currency(report.totalDebit)}
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    {currency(report.totalCredit)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
          <div
            className={
              "border-t px-5 py-3 text-sm font-medium " +
              (balanced
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
                : "border-destructive/30 bg-destructive/10 text-destructive")
            }
          >
            {balanced
              ? "Debits equal credits — the ledger balances."
              : "Debits and credits do not match — this indicates a bug in the ledger, not a data issue a report can fix."}
          </div>
        </div>
      )}
    </div>
  );
}
