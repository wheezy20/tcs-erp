import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { CheckCircle2, Landmark, Plus, Undo2 } from "lucide-react";
import { toast } from "sonner";

import { ImportDialog, type ImportConfig, type RowCheck } from "@/components/import/import-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import {
  ledgerActivityForAccount,
  suggestMatches,
  unmatchedLedgerActivity,
} from "@/data/bank-matching";
import { useBankAccounts } from "@/data/bank-accounts-store";
import {
  addStatementLine,
  cancelBankReconciliation,
  clearStatementLine,
  completeBankReconciliation,
  importBankStatementLines,
  matchStatementLine,
  startBankReconciliation,
  unmatchStatementLine,
  useBankReconciliationData,
  type NewStatementLine,
} from "@/data/bank-reconciliation-store";
import { currency } from "@/data/dashboard";
import { useJournalEntries } from "@/data/journal-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/banking/reconcile")({
  component: ReconcilePage,
});

const today = () => new Date().toISOString().slice(0, 10);

function ReconcilePage() {
  const { accounts, loading: accountsLoading } = useBankAccounts();
  const { lines, reconciliations, loading: reconLoading } = useBankReconciliationData();
  const { entries, loading: entriesLoading } = useJournalEntries();
  const [bankAccountId, setBankAccountId] = useState<string>("");

  const account =
    accounts.find((a) => a.id === bankAccountId) ?? accounts.find((a) => a.active) ?? accounts[0];

  // Every hook has to run before any early return below (loading, no
  // accounts yet) — ledgerActivityForAccount() falls back to an empty
  // glAccountId, harmlessly returning no rows, when there's no account yet.
  const ledgerActivity = useMemo(
    () => ledgerActivityForAccount(entries, account?.glAccountId ?? ""),
    [entries, account?.glAccountId],
  );

  if (accountsLoading || reconLoading || entriesLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  if (accounts.length === 0) {
    return (
      <div className="mt-4 flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
        <Landmark className="size-8 text-muted-foreground" />
        <p className="text-sm font-medium">Add a bank account first</p>
        <p className="max-w-sm text-sm text-muted-foreground">
          The Accounts tab is where a real bank account gets linked to its ledger account.
        </p>
      </div>
    );
  }

  if (!account) return null;

  const openRecon = reconciliations.find((r) => r.bankAccountId === account.id && !r.completedAt);
  const accountLines = lines.filter((l) => l.bankAccountId === account.id);
  const unmatched = accountLines.filter((l) => l.status === "unmatched");
  const resolvedThisSession = openRecon
    ? accountLines.filter((l) => l.reconciliationId === openRecon.id)
    : [];

  const matchedJournalLineIds = new Set(
    accountLines.filter((l) => l.matchedJournalLineId).map((l) => l.matchedJournalLineId as string),
  );
  const unmatchedLedger = unmatchedLedgerActivity(ledgerActivity, matchedJournalLineIds);

  const previousCompleted = reconciliations
    .filter((r) => r.bankAccountId === account.id && r.completedAt)
    .sort((a, b) => (a.statementDate < b.statementDate ? 1 : -1))[0];
  const nextOpeningPreview = previousCompleted
    ? previousCompleted.statementEndingBalance
    : account.openingBalance;

  return (
    <div className="mt-4 space-y-4">
      <div className="max-w-sm space-y-1.5">
        <Label>Bank account</Label>
        <Select value={account.id} onValueChange={setBankAccountId}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {accounts.map((a) => (
              <SelectItem key={a.id} value={a.id}>
                {a.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {!openRecon ? (
        <StartReconciliationCard bankAccountId={account.id} openingPreview={nextOpeningPreview} />
      ) : (
        <ActiveSession
          bankAccountId={account.id}
          reconciliation={openRecon}
          unmatched={unmatched}
          resolved={resolvedThisSession}
          unmatchedLedger={unmatchedLedger}
        />
      )}

      {unmatchedLedger.length > 0 && (
        <div className="card-surface overflow-hidden">
          <div className="border-b border-border px-5 py-3">
            <h3 className="text-sm font-semibold">Unmatched ledger activity</h3>
            <p className="text-xs text-muted-foreground">
              What the books show for this account with no statement line matched to it yet —
              informational, not a blocker. A payment that hasn't cleared the bank yet is normal and
              expected to carry forward to the next statement.
            </p>
          </div>
          <table className="w-full text-sm">
            <tbody className="divide-y">
              {unmatchedLedger.slice(0, 20).map((row) => (
                <tr key={row.journalLineId} className="hover:bg-muted/40">
                  <td className="px-5 py-2 text-muted-foreground">{row.entryDate}</td>
                  <td className="px-5 py-2">{row.description}</td>
                  <td className="px-5 py-2 text-right tabular-nums">{currency(row.amount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {unmatchedLedger.length > 20 && (
            <p className="px-5 py-2 text-xs text-muted-foreground">
              +{unmatchedLedger.length - 20} more
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function StartReconciliationCard({
  bankAccountId,
  openingPreview,
}: {
  bankAccountId: string;
  openingPreview: number;
}) {
  const [statementDate, setStatementDate] = useState(today());
  const [statementEndingBalance, setStatementEndingBalance] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function submit() {
    const value = Number(statementEndingBalance);
    if (!Number.isFinite(value)) {
      toast.error("Enter the statement's ending balance.");
      return;
    }
    setSubmitting(true);
    try {
      await startBankReconciliation({
        bankAccountId,
        statementDate,
        statementEndingBalance: value,
      });
      toast.success("Reconciliation started");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not start the reconciliation."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="card-surface p-5">
      <h3 className="text-sm font-semibold">Start a reconciliation</h3>
      <p className="mt-1 text-sm text-muted-foreground">
        Opening balance will be {currency(openingPreview)} — reference only, not editable, and never
        recomputed after this reconciliation starts.
      </p>
      <div className="mt-4 grid gap-3 sm:grid-cols-[200px_200px_auto] sm:items-end">
        <div className="space-y-1.5">
          <Label htmlFor="recon-date">Statement date</Label>
          <Input
            id="recon-date"
            type="date"
            value={statementDate}
            onChange={(e) => setStatementDate(e.target.value)}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="recon-balance">Statement ending balance</Label>
          <Input
            id="recon-balance"
            inputMode="decimal"
            value={statementEndingBalance}
            onChange={(e) => setStatementEndingBalance(e.target.value)}
            placeholder="0.00"
          />
        </div>
        <Button onClick={submit} disabled={submitting}>
          {submitting ? "Starting…" : "Start reconciliation"}
        </Button>
      </div>
    </div>
  );
}

function ActiveSession({
  bankAccountId,
  reconciliation,
  unmatched,
  resolved,
  unmatchedLedger,
}: {
  bankAccountId: string;
  reconciliation: ReturnType<typeof useBankReconciliationData>["reconciliations"][number];
  unmatched: ReturnType<typeof useBankReconciliationData>["lines"];
  resolved: ReturnType<typeof useBankReconciliationData>["lines"];
  unmatchedLedger: ReturnType<typeof ledgerActivityForAccount>;
}) {
  const resolvedSum = resolved.reduce((sum, l) => sum + l.amount, 0);
  const previewReconciled = reconciliation.openingBalance + resolvedSum;
  const previewDiff = reconciliation.statementEndingBalance - previewReconciled;
  const blockedByUnmatched = unmatched.filter((l) => l.date <= reconciliation.statementDate).length;
  const [completing, setCompleting] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  async function complete() {
    setCompleting(true);
    try {
      await completeBankReconciliation(reconciliation.id);
      toast.success("Reconciliation completed — it ties out.");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not complete the reconciliation."));
    } finally {
      setCompleting(false);
    }
  }

  async function cancel() {
    setCancelling(true);
    try {
      await cancelBankReconciliation(reconciliation.id);
      toast.success("Reconciliation cancelled");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not cancel the reconciliation."));
    } finally {
      setCancelling(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="card-surface p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h3 className="text-sm font-semibold">
              Reconciling as of {reconciliation.statementDate}
            </h3>
            <p className="text-xs text-muted-foreground">Started by {reconciliation.startedBy}</p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={cancel} disabled={cancelling}>
              {cancelling ? "Cancelling…" : "Cancel session"}
            </Button>
            <Button size="sm" onClick={complete} disabled={completing || blockedByUnmatched > 0}>
              {completing ? "Completing…" : "Complete reconciliation"}
            </Button>
          </div>
        </div>

        <div className="mt-4 grid gap-4 sm:grid-cols-4">
          <Stat label="Opening balance" value={currency(reconciliation.openingBalance)} />
          <Stat
            label="Statement ending balance"
            value={currency(reconciliation.statementEndingBalance)}
          />
          <Stat label="Reconciled so far" value={currency(previewReconciled)} />
          <Stat
            label="Difference"
            value={currency(previewDiff)}
            tone={Math.abs(previewDiff) < 0.005 ? "good" : "warning"}
          />
        </div>

        {blockedByUnmatched > 0 && (
          <p className="mt-3 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-400">
            {blockedByUnmatched} statement line{blockedByUnmatched > 1 ? "s" : ""} on or before{" "}
            {reconciliation.statementDate} still need{blockedByUnmatched === 1 ? "s" : ""} to be
            matched or cleared before this can complete.
          </p>
        )}
      </div>

      <div className="card-surface overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3">
          <h3 className="text-sm font-semibold">Unmatched statement lines ({unmatched.length})</h3>
          <div className="flex gap-2">
            <AddLineDialog bankAccountId={bankAccountId} />
            <ImportStatementLinesDialog bankAccountId={bankAccountId} />
          </div>
        </div>
        {unmatched.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-muted-foreground">
            No unmatched lines — add or import statement lines to start resolving this account.
          </p>
        ) : (
          <ul className="divide-y">
            {unmatched.map((line) => (
              <StatementLineRow key={line.id} line={line} candidates={unmatchedLedger} />
            ))}
          </ul>
        )}
      </div>

      {resolved.length > 0 && (
        <div className="card-surface overflow-hidden">
          <div className="border-b border-border px-5 py-3">
            <h3 className="text-sm font-semibold">Resolved this session ({resolved.length})</h3>
          </div>
          <ul className="divide-y">
            {resolved.map((line) => (
              <li
                key={line.id}
                className="flex items-center justify-between gap-3 px-5 py-3 text-sm"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{line.description}</span>
                    <Badge variant={line.status === "matched" ? "default" : "secondary"}>
                      {line.status === "matched" ? "Matched" : "Cleared"}
                    </Badge>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {line.date} · {line.reference || "no reference"}
                    {line.status === "cleared" && line.clearNote ? ` · ${line.clearNote}` : ""}
                  </p>
                </div>
                <span className="tabular-nums">{currency(line.amount)}</span>
                <Button
                  variant="ghost"
                  size="sm"
                  className="gap-1"
                  onClick={() =>
                    unmatchStatementLine(line.id).catch((error) =>
                      toast.error(getErrorMessage(error, "Could not unmatch this line.")),
                    )
                  }
                >
                  <Undo2 className="size-3.5" /> Unmatch
                </Button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "good" | "warning" }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p
        className={
          "text-lg font-semibold tabular-nums " +
          (tone === "good"
            ? "text-emerald-600 dark:text-emerald-400"
            : tone === "warning"
              ? "text-amber-600 dark:text-amber-400"
              : "")
        }
      >
        {value}
      </p>
    </div>
  );
}

function StatementLineRow({
  line,
  candidates,
}: {
  line: ReturnType<typeof useBankReconciliationData>["lines"][number];
  candidates: ReturnType<typeof ledgerActivityForAccount>;
}) {
  const suggested = suggestMatches(line, candidates);
  const ranked = [...suggested, ...candidates.filter((c) => !suggested.includes(c))];
  const [selected, setSelected] = useState(suggested[0]?.journalLineId ?? "");
  const [matching, setMatching] = useState(false);
  const [clearOpen, setClearOpen] = useState(false);

  async function match() {
    if (!selected) {
      toast.error("Choose a ledger line to match against.");
      return;
    }
    setMatching(true);
    try {
      await matchStatementLine(line.id, selected);
      toast.success("Matched");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not match this line."));
    } finally {
      setMatching(false);
    }
  }

  return (
    <li className="flex flex-wrap items-center gap-3 px-5 py-3 text-sm">
      <div className="min-w-0 flex-1">
        <p className="font-medium">{line.description}</p>
        <p className="text-xs text-muted-foreground">
          {line.date} · {line.reference || "no reference"}
        </p>
      </div>
      <span className="w-24 text-right tabular-nums">{currency(line.amount)}</span>

      {ranked.length > 0 && (
        <Select value={selected} onValueChange={setSelected}>
          <SelectTrigger className="h-9 w-64">
            <SelectValue placeholder="Choose a ledger line…" />
          </SelectTrigger>
          <SelectContent>
            {suggested.length > 0 && (
              <>
                {suggested.map((c) => (
                  <SelectItem key={c.journalLineId} value={c.journalLineId}>
                    Suggested — {c.description} · {c.entryDate} · {currency(c.amount)}
                  </SelectItem>
                ))}
              </>
            )}
            {candidates
              .filter((c) => !suggested.includes(c))
              .map((c) => (
                <SelectItem key={c.journalLineId} value={c.journalLineId}>
                  {c.description} · {c.entryDate} · {currency(c.amount)}
                </SelectItem>
              ))}
          </SelectContent>
        </Select>
      )}
      <Button size="sm" onClick={match} disabled={matching || !selected} className="gap-1">
        <CheckCircle2 className="size-3.5" /> Match
      </Button>
      <Button variant="outline" size="sm" onClick={() => setClearOpen(true)}>
        Mark cleared
      </Button>

      {clearOpen && <ClearLineDialog lineId={line.id} onClose={() => setClearOpen(false)} />}
    </li>
  );
}

function ClearLineDialog({ lineId, onClose }: { lineId: string; onClose: () => void }) {
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function submit() {
    if (!note.trim()) {
      toast.error("A reason is required to clear a line without a ledger match.");
      return;
    }
    setSubmitting(true);
    try {
      await clearStatementLine(lineId, note.trim());
      toast.success("Marked cleared");
      onClose();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not clear this line."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Mark cleared</DialogTitle>
          <DialogDescription>
            Accept this line as real bank activity with no matching ledger entry — e.g. a bank fee
            not yet recorded as an expense. Needs a reason.
          </DialogDescription>
        </DialogHeader>
        <Textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Why is this cleared without a match?"
          rows={3}
          autoFocus
        />
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Saving…" : "Mark cleared"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AddLineDialog({ bankAccountId }: { bankAccountId: string }) {
  const [open, setOpen] = useState(false);
  const [date, setDate] = useState(today());
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [reference, setReference] = useState("");
  const [submitting, setSubmitting] = useState(false);

  function reset() {
    setDate(today());
    setDescription("");
    setAmount("");
    setReference("");
  }

  async function submit() {
    const value = Number(amount);
    if (!description.trim() || !Number.isFinite(value) || value === 0) {
      toast.error("Enter a description and a non-zero amount (negative for money out).");
      return;
    }
    setSubmitting(true);
    try {
      await addStatementLine(bankAccountId, {
        date,
        description: description.trim(),
        amount: value,
        reference: reference.trim(),
      });
      toast.success("Statement line added");
      reset();
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not add the statement line."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) reset();
      }}
    >
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="gap-1">
          <Plus className="size-3.5" /> Add line
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Add a statement line</DialogTitle>
          <DialogDescription>
            What the bank statement itself shows — positive for money in, negative for money out.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="sl-date">Date</Label>
            <Input
              id="sl-date"
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sl-desc">Description</Label>
            <Input
              id="sl-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sl-amount">Amount</Label>
            <Input
              id="sl-amount"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="294.00 or -1200.00"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sl-ref">Reference (optional)</Label>
            <Input id="sl-ref" value={reference} onChange={(e) => setReference(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Adding…" : "Add line"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ImportStatementLinesDialog({ bankAccountId }: { bankAccountId: string }) {
  const config: ImportConfig<NewStatementLine> = {
    entity: "bank statement lines",
    description:
      "Bring in a statement export from your bank. Nothing is saved until you confirm, and rows with errors are never imported.",
    templateFile: "tcs-bank-statement-template.csv",
    columns: ["date", "description", "amount", "reference"],
    exampleRow: ["2026-08-04", "Card settlement — POS-26080001", "294.00", "TRF-2201"],
    validate: (row): RowCheck<NewStatementLine> => {
      const errors: string[] = [];
      const date = (row["date"] ?? "").trim();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) errors.push("Date must be YYYY-MM-DD");
      const description = (row["description"] ?? "").trim();
      if (!description) errors.push("Description is required");
      const amount = Number(row["amount"]);
      if (!Number.isFinite(amount) || amount === 0) {
        errors.push("Amount must be a non-zero number (negative for money out)");
      }
      const reference = (row["reference"] ?? "").trim();

      if (errors.length > 0) return { value: null, errors };
      return { value: { date, description, amount, reference }, errors: [] };
    },
    onImport: (values) => importBankStatementLines(bankAccountId, values),
  };

  return (
    <ImportDialog
      config={config}
      trigger={
        <Button variant="outline" size="sm" className="gap-1">
          Import CSV
        </Button>
      }
    />
  );
}
