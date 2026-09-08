import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AlertTriangle, BookText, ChevronDown, ChevronUp, Plus, Undo2 } from "lucide-react";
import { toast } from "sonner";

import { AccountPicker } from "@/components/accounting/account-picker";
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
import { Textarea } from "@/components/ui/textarea";
import { useAuth } from "@/data/auth-store";
import { useAccounts, type Account } from "@/data/accounts-store";
import { currency } from "@/data/dashboard";
import {
  postJournalEntry,
  reverseJournalEntry,
  sourceLabel,
  useJournalEntries,
  type JournalEntry,
  type NewJournalLine,
} from "@/data/journal-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/accounting/journal-entries")({
  component: JournalEntriesPage,
});

const today = () => new Date().toISOString().slice(0, 10);

function entryTotal(entry: JournalEntry) {
  return entry.lines.reduce((sum, l) => sum + l.debit, 0);
}

function JournalEntriesPage() {
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const { entries, loading } = useJournalEntries();
  const { accounts } = useAccounts();
  const [expanded, setExpanded] = useState<string | null>(null);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          {entries.length} entr{entries.length === 1 ? "y" : "ies"} posted. Once posted, an entry is
          immutable — corrections are a reversing entry, never an edit.
        </p>
        {isManager && <NewEntryDialog accounts={accounts} />}
      </div>

      {entries.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <BookText className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No journal entries posted yet</p>
          {!isManager && (
            <p className="text-sm text-muted-foreground">Only a Manager can post an entry.</p>
          )}
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="w-8 px-3 py-3" />
                  <th className="px-5 py-3 font-medium">Number</th>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 font-medium">Description</th>
                  <th className="px-5 py-3 font-medium">Reference</th>
                  <th className="px-5 py-3 font-medium">Source</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 font-medium">Created by</th>
                  {isManager && <th className="px-5 py-3 font-medium">&nbsp;</th>}
                </tr>
              </thead>
              <tbody className="divide-y">
                {entries.map((entry) => (
                  <EntryRow
                    key={entry.id}
                    entry={entry}
                    isManager={isManager}
                    expanded={expanded === entry.id}
                    onToggle={() => setExpanded(expanded === entry.id ? null : entry.id)}
                  />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function EntryRow({
  entry,
  isManager,
  expanded,
  onToggle,
}: {
  entry: JournalEntry;
  isManager: boolean;
  expanded: boolean;
  onToggle: () => void;
}) {
  const [reversing, setReversing] = useState(false);
  const isReversal = !!entry.reversesEntryId;
  const alreadyReversed = !!entry.reversedByEntryId;

  async function reverse() {
    setReversing(true);
    try {
      const reversal = await reverseJournalEntry(entry.id);
      toast.success(`${reversal.id} posted, reversing ${entry.id}`);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not reverse the entry."));
    } finally {
      setReversing(false);
    }
  }

  return (
    <>
      <tr className="cursor-pointer hover:bg-muted/40" onClick={onToggle}>
        <td className="px-3 py-3 text-muted-foreground">
          {expanded ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}
        </td>
        <td className="px-5 py-3 font-mono tabular-nums">{entry.id}</td>
        <td className="px-5 py-3">{entry.entryDate}</td>
        <td className="px-5 py-3">
          <div className="font-medium">{entry.description}</div>
          <div className="flex gap-1.5">
            {isReversal && (
              <Badge variant="secondary" className="mt-1">
                Reverses {entry.reversesEntryId}
              </Badge>
            )}
            {alreadyReversed && (
              <Badge variant="secondary" className="mt-1">
                Reversed by {entry.reversedByEntryId}
              </Badge>
            )}
            {entry.costDataIncomplete && (
              <Badge
                variant="outline"
                className="mt-1 gap-1 border-amber-500/30 bg-amber-500/15 text-amber-700 dark:text-amber-400"
              >
                <AlertTriangle className="size-3" /> Cost estimated — cost price missing
              </Badge>
            )}
          </div>
        </td>
        <td className="px-5 py-3 text-muted-foreground">{entry.reference || "—"}</td>
        <td className="px-5 py-3">
          <Badge variant={entry.sourceTable ? "outline" : "secondary"}>{sourceLabel(entry)}</Badge>
        </td>
        <td className="px-5 py-3 text-right font-medium tabular-nums">
          {currency(entryTotal(entry))}
        </td>
        <td className="px-5 py-3 text-muted-foreground">{entry.createdBy}</td>
        {isManager && (
          <td className="px-5 py-3 text-right" onClick={(e) => e.stopPropagation()}>
            {!alreadyReversed && (
              <Button
                variant="ghost"
                size="sm"
                className="gap-1"
                onClick={reverse}
                disabled={reversing}
              >
                <Undo2 className="size-3.5" /> {reversing ? "Reversing…" : "Reverse"}
              </Button>
            )}
          </td>
        )}
      </tr>
      {expanded && (
        <tr>
          <td colSpan={isManager ? 9 : 8} className="bg-muted/20 px-5 py-3">
            <table className="w-full text-xs">
              <thead className="text-left uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="py-1.5 pr-4 font-medium">Account</th>
                  <th className="py-1.5 pr-4 font-medium">Line description</th>
                  <th className="py-1.5 pr-4 text-right font-medium">Debit</th>
                  <th className="py-1.5 text-right font-medium">Credit</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/60">
                {entry.lines.map((line) => (
                  <tr key={line.id}>
                    <td className="py-1.5 pr-4 font-mono">
                      {line.accountCode} — {line.accountName}
                    </td>
                    <td className="py-1.5 pr-4 text-muted-foreground">{line.description || "—"}</td>
                    <td className="py-1.5 pr-4 text-right tabular-nums">
                      {line.debit > 0 ? currency(line.debit) : ""}
                    </td>
                    <td className="py-1.5 text-right tabular-nums">
                      {line.credit > 0 ? currency(line.credit) : ""}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </td>
        </tr>
      )}
    </>
  );
}

type DraftLine = { accountId: string; debit: string; credit: string; description: string };

function emptyLine(): DraftLine {
  return { accountId: "", debit: "", credit: "", description: "" };
}

function NewEntryDialog({ accounts }: { accounts: Account[] }) {
  const [open, setOpen] = useState(false);
  const [date, setDate] = useState(today());
  const [description, setDescription] = useState("");
  const [reference, setReference] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([emptyLine(), emptyLine()]);
  const [submitting, setSubmitting] = useState(false);

  const totals = useMemo(() => {
    const debit = lines.reduce((sum, l) => sum + (Number(l.debit) || 0), 0);
    const credit = lines.reduce((sum, l) => sum + (Number(l.credit) || 0), 0);
    return { debit, credit, diff: Math.round((debit - credit) * 100) / 100 };
  }, [lines]);

  const balanced = totals.diff === 0 && totals.debit > 0;

  function reset() {
    setDate(today());
    setDescription("");
    setReference("");
    setLines([emptyLine(), emptyLine()]);
  }

  function updateLine(index: number, patch: Partial<DraftLine>) {
    setLines((prev) => prev.map((l, i) => (i === index ? { ...l, ...patch } : l)));
  }

  function addLine() {
    setLines((prev) => [...prev, emptyLine()]);
  }

  function removeLine(index: number) {
    setLines((prev) => (prev.length <= 2 ? prev : prev.filter((_, i) => i !== index)));
  }

  async function submit() {
    if (!description.trim()) {
      toast.error("Enter a description for this entry.");
      return;
    }
    if (!balanced) {
      toast.error("Debits and credits must be equal before this entry can be posted.");
      return;
    }
    const newLines: NewJournalLine[] = [];
    for (const l of lines) {
      const debit = Number(l.debit) || 0;
      const credit = Number(l.credit) || 0;
      if (debit === 0 && credit === 0) continue;
      if (!l.accountId) {
        toast.error("Every line with an amount needs an account.");
        return;
      }
      newLines.push({ accountId: l.accountId, debit, credit, description: l.description });
    }
    if (newLines.length < 2) {
      toast.error("A journal entry needs at least two lines.");
      return;
    }

    setSubmitting(true);
    try {
      const posted = await postJournalEntry({ date, description, reference, lines: newLines });
      toast.success(`${posted.id} posted`);
      reset();
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not post the entry."));
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
        <Button className="gap-2">
          <Plus className="size-4" /> New entry
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>New journal entry</DialogTitle>
          <DialogDescription>
            Debits and credits must be equal — this can't be posted otherwise.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="je-date">Date</Label>
              <Input
                id="je-date"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="je-reference">Reference (optional)</Label>
              <Input
                id="je-reference"
                value={reference}
                onChange={(e) => setReference(e.target.value)}
                placeholder="e.g. source document"
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="je-description">Description</Label>
            <Textarea
              id="je-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={2}
              autoFocus
            />
          </div>

          <div className="space-y-2">
            <Label>Lines</Label>
            <div className="space-y-2">
              {lines.map((line, i) => (
                <div key={i} className="flex items-start gap-2">
                  <div className="min-w-0 flex-1">
                    <AccountPicker
                      accounts={accounts}
                      value={line.accountId}
                      onChange={(v) => updateLine(i, { accountId: v })}
                    />
                  </div>
                  <Input
                    className="w-28"
                    inputMode="decimal"
                    placeholder="Debit"
                    value={line.debit}
                    onChange={(e) => updateLine(i, { debit: e.target.value, credit: "" })}
                  />
                  <Input
                    className="w-28"
                    inputMode="decimal"
                    placeholder="Credit"
                    value={line.credit}
                    onChange={(e) => updateLine(i, { credit: e.target.value, debit: "" })}
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => removeLine(i)}
                    disabled={lines.length <= 2}
                  >
                    ✕
                  </Button>
                </div>
              ))}
            </div>
            <Button variant="outline" size="sm" onClick={addLine} className="gap-1">
              <Plus className="size-3.5" /> Add line
            </Button>
          </div>

          <div
            className={`flex items-center justify-between rounded-lg border px-3 py-2 text-sm ${
              balanced
                ? "border-primary/30 bg-primary/5 text-primary"
                : "border-destructive/30 bg-destructive/5 text-destructive"
            }`}
          >
            <span>
              Debits {currency(totals.debit)} · Credits {currency(totals.credit)}
            </span>
            <span className="font-medium">
              {balanced ? "Balanced" : `Out of balance by ${currency(Math.abs(totals.diff))}`}
            </span>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting || !balanced}>
            {submitting ? "Posting…" : "Post entry"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
