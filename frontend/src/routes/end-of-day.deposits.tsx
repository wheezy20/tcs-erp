import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Banknote, Plus } from "lucide-react";
import { toast } from "sonner";

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
import { useBankAccounts } from "@/data/bank-accounts-store";
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { recordDeposit, useEndOfDay, type DepositSource } from "@/data/end-of-day-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/end-of-day/deposits")({
  component: DepositsPage,
});

const today = () => new Date().toISOString().slice(0, 10);

function DepositsPage() {
  const { deposits, loading } = useEndOfDay();
  const { accounts: bankAccounts, loading: bankLoading } = useBankAccounts();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const bankAccountName = (id: string) => bankAccounts.find((a) => a.id === id)?.name ?? "—";

  if (loading || bankLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const total = deposits.reduce((sum, d) => sum + d.amount, 0);

  return (
    <div className="mt-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm text-muted-foreground">
            {deposits.length} deposit{deposits.length === 1 ? "" : "s"} recorded · {currency(total)}{" "}
            total
          </p>
          <p className="text-xs text-muted-foreground">
            A lightweight log of cash/Mobile Money banked, so opening float has something real to
            reconcile against — not the full Bank Reconciliation module.
          </p>
        </div>
        {isManager && <AddDepositDialog />}
      </div>

      {deposits.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Banknote className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No deposits recorded yet</p>
          {!isManager && (
            <p className="text-sm text-muted-foreground">
              Only a Manager can record a bank or Mobile Money deposit.
            </p>
          )}
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                  <th className="px-5 py-3 font-medium">Source</th>
                  <th className="px-5 py-3 font-medium">Bank account</th>
                  <th className="px-5 py-3 font-medium">Deposited by</th>
                  <th className="px-5 py-3 font-medium">Reference</th>
                  <th className="px-5 py-3 font-medium">Note</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {deposits.map((d) => (
                  <tr key={d.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3">{d.date}</td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(d.amount)}
                    </td>
                    <td className="px-5 py-3">{d.source}</td>
                    <td className="px-5 py-3 text-muted-foreground">
                      {bankAccountName(d.bankAccountId)}
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{d.depositedBy}</td>
                    <td className="px-5 py-3 text-muted-foreground">{d.reference || "—"}</td>
                    <td className="px-5 py-3 text-muted-foreground">{d.note || "—"}</td>
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

function AddDepositDialog() {
  const { accounts: bankAccounts } = useBankAccounts();
  const [open, setOpen] = useState(false);
  const [bankAccountId, setBankAccountId] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(today());
  const [source, setSource] = useState<DepositSource>("Cash");
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const activeAccounts = bankAccounts.filter((a) => a.active);
  // Prefill only when there's exactly one account — with more than one, the
  // person must choose which bank actually received the deposit rather than
  // it being silently posted to whichever happens to sort first.
  const selectedBankAccountId =
    bankAccountId || (activeAccounts.length === 1 ? activeAccounts[0].id : "");

  function reset() {
    setBankAccountId("");
    setAmount("");
    setDate(today());
    setSource("Cash");
    setReference("");
    setNote("");
  }

  async function submit() {
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) {
      toast.error("Enter a deposit amount greater than zero.");
      return;
    }
    if (!selectedBankAccountId) {
      toast.error("Add a bank account first, under Banking.");
      return;
    }
    setSubmitting(true);
    try {
      await recordDeposit({
        bankAccountId: selectedBankAccountId,
        amount: value,
        date,
        source,
        reference,
        note,
      });
      toast.success(`${currency(value)} deposit recorded`);
      reset();
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not record the deposit."));
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
          <Plus className="size-4" /> Record deposit
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Record a bank/Mobile Money deposit</DialogTitle>
          <DialogDescription>
            Where cash or Mobile Money balance actually went — a reference for opening float, not an
            accounting entry.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="deposit-account">Deposited into</Label>
            <Select value={selectedBankAccountId} onValueChange={setBankAccountId}>
              <SelectTrigger id="deposit-account">
                <SelectValue placeholder="Select a bank account…" />
              </SelectTrigger>
              <SelectContent>
                {activeAccounts.map((a) => (
                  <SelectItem key={a.id} value={a.id}>
                    {a.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="deposit-amount">Amount</Label>
              <Input
                id="deposit-amount"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
                autoFocus
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="deposit-date">Date</Label>
              <Input
                id="deposit-date"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="deposit-source">Source</Label>
            <Select value={source} onValueChange={(v) => setSource(v as DepositSource)}>
              <SelectTrigger id="deposit-source">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="Cash">Cash</SelectItem>
                <SelectItem value="Mobile Money">Mobile Money</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="deposit-reference">Reference (optional)</Label>
            <Input
              id="deposit-reference"
              value={reference}
              onChange={(e) => setReference(e.target.value)}
              placeholder="e.g. bank slip number"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="deposit-note">Note (optional)</Label>
            <Textarea
              id="deposit-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Recording…" : "Record deposit"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
