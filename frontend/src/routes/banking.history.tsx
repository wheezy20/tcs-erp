import { createFileRoute } from "@tanstack/react-router";
import { History } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { useBankAccounts } from "@/data/bank-accounts-store";
import { useBankReconciliationData } from "@/data/bank-reconciliation-store";
import { currency } from "@/data/dashboard";

export const Route = createFileRoute("/banking/history")({
  component: BankingHistoryPage,
});

function BankingHistoryPage() {
  const { accounts, loading: accountsLoading } = useBankAccounts();
  const { reconciliations, loading: reconLoading } = useBankReconciliationData();

  if (accountsLoading || reconLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const completed = reconciliations
    .filter((r) => r.completedAt)
    .sort((a, b) => (a.statementDate < b.statementDate ? 1 : -1));

  const accountName = (id: string) => accounts.find((a) => a.id === id)?.name ?? "Unknown account";

  return (
    <div className="mt-4">
      {completed.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <History className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No completed reconciliations yet</p>
          <p className="max-w-sm text-sm text-muted-foreground">
            Every reconciliation that ties out lands here, permanently — once completed, none of its
            figures can change.
          </p>
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Bank account</th>
                  <th className="px-5 py-3 font-medium">Statement date</th>
                  <th className="px-5 py-3 text-right font-medium">Opening</th>
                  <th className="px-5 py-3 text-right font-medium">Statement ending</th>
                  <th className="px-5 py-3 text-right font-medium">Reconciled</th>
                  <th className="px-5 py-3 text-right font-medium">Difference</th>
                  <th className="px-5 py-3 font-medium">Completed by</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {completed.map((r) => (
                  <tr key={r.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3 font-medium">{accountName(r.bankAccountId)}</td>
                    <td className="px-5 py-3">{r.statementDate}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(r.openingBalance)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(r.statementEndingBalance)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(r.reconciledBalance ?? 0)}
                    </td>
                    <td className="px-5 py-3 text-right">
                      <Badge
                        variant="outline"
                        className="border-emerald-500/40 text-emerald-600 dark:text-emerald-400"
                      >
                        {currency(Math.abs(r.difference ?? 0))}
                      </Badge>
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">
                      {r.completedBy} · {r.completedAt?.slice(0, 10)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
