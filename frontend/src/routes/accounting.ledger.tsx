import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Scale } from "lucide-react";

import { AccountPicker } from "@/components/accounting/account-picker";
import { useAccounts } from "@/data/accounts-store";
import { currency } from "@/data/dashboard";
import { ledgerForAccount, useJournalEntries } from "@/data/journal-store";

export const Route = createFileRoute("/accounting/ledger")({
  component: GeneralLedgerPage,
});

function GeneralLedgerPage() {
  const { accounts, loading: accountsLoading } = useAccounts();
  const { entries, loading: entriesLoading } = useJournalEntries();
  const [accountId, setAccountId] = useState("");

  const account = accounts.find((a) => a.id === accountId) ?? null;
  const rows = useMemo(
    () => (account ? ledgerForAccount(entries, account) : []),
    [entries, account],
  );

  if (accountsLoading || entriesLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const endingBalance = rows.length > 0 ? rows[rows.length - 1].balance : 0;

  return (
    <div className="mt-4 space-y-4">
      <div className="max-w-sm">
        <AccountPicker
          accounts={accounts}
          value={accountId}
          onChange={setAccountId}
          includeInactive
          placeholder="Choose an account to view its ledger…"
        />
      </div>

      {!account ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Scale className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">Choose an account above to view its ledger</p>
          <p className="max-w-sm text-sm text-muted-foreground">
            Every line ever posted against that account, oldest first, with a running balance in the
            account's own normal terms — never stored separately, always derived from the journal
            lines themselves.
          </p>
        </div>
      ) : (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card px-4 py-3">
            <div>
              <p className="font-medium">
                {account.code} — {account.name}
              </p>
              <p className="text-xs text-muted-foreground">
                {account.subtype} · Normal balance: {account.normalBalance}
              </p>
            </div>
            <div className="text-right">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">
                Ending balance
              </p>
              <p className="text-lg font-semibold tabular-nums">{currency(endingBalance)}</p>
            </div>
          </div>

          {rows.length === 0 ? (
            <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
              <Scale className="size-8 text-muted-foreground" />
              <p className="text-sm font-medium">No activity posted against this account yet</p>
            </div>
          ) : (
            <div className="card-surface overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                    <tr>
                      <th className="px-5 py-3 font-medium">Date</th>
                      <th className="px-5 py-3 font-medium">Entry</th>
                      <th className="px-5 py-3 font-medium">Description</th>
                      <th className="px-5 py-3 text-right font-medium">Debit</th>
                      <th className="px-5 py-3 text-right font-medium">Credit</th>
                      <th className="px-5 py-3 text-right font-medium">Balance</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {rows.map((row, i) => (
                      <tr key={`${row.entryId}-${i}`} className="hover:bg-muted/40">
                        <td className="px-5 py-3">{row.entryDate}</td>
                        <td className="px-5 py-3 font-mono">{row.entryId}</td>
                        <td className="px-5 py-3">
                          <div>{row.description}</div>
                          {row.lineDescription && (
                            <div className="text-xs text-muted-foreground">
                              {row.lineDescription}
                            </div>
                          )}
                        </td>
                        <td className="px-5 py-3 text-right tabular-nums">
                          {row.debit > 0 ? currency(row.debit) : ""}
                        </td>
                        <td className="px-5 py-3 text-right tabular-nums">
                          {row.credit > 0 ? currency(row.credit) : ""}
                        </td>
                        <td className="px-5 py-3 text-right font-medium tabular-nums">
                          {currency(row.balance)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
