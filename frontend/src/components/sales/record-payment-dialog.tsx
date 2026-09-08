import { useState } from "react";
import { toast } from "sonner";
import { BanknoteArrowUp } from "lucide-react";

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
import { currency } from "@/data/dashboard";
import { INVOICE_BANK_METHODS, PAYMENT_METHODS, type PaymentMethod } from "@/data/invoices";
import { addPayment } from "@/data/sales-store";
import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";

export function RecordPaymentDialog({
  invoiceId,
  balance,
  storeCreditBalance = 0,
}: {
  invoiceId: string;
  balance: number;
  /** The invoice's customer's spendable store credit — every invoice has a
   * real customer (no Walk-in concept), so this is always the right
   * customer to check against. Store Credit only appears as a method once
   * there's something to spend. */
  storeCreditBalance?: number;
}) {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<PaymentMethod>("Mobile Money");
  const [reference, setReference] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [bankAccountId, setBankAccountId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();
  const needsBankAccount = INVOICE_BANK_METHODS.includes(method);
  const effectiveBankAccountId = bankAccountId || defaultBankAccountId;

  const methodOptions: PaymentMethod[] =
    storeCreditBalance > 0 ? [...PAYMENT_METHODS, "Store Credit"] : PAYMENT_METHODS;

  const submit = async () => {
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) {
      setError("Enter a payment amount greater than zero.");
      return;
    }
    if (value > balance + 0.01) {
      setError(`Amount cannot exceed the remaining balance of ${currency(balance)}.`);
      return;
    }
    if (method === "Store Credit" && value > storeCreditBalance + 0.01) {
      setError(
        `Amount cannot exceed the customer's store credit of ${currency(storeCreditBalance)}.`,
      );
      return;
    }
    if (reference.trim().length < 2) {
      setError("Add a short reference (receipt, till or transaction ID).");
      return;
    }
    if (needsBankAccount && !effectiveBankAccountId) {
      setError(`Pick the bank account this ${method} settled into.`);
      return;
    }
    setSaving(true);
    try {
      await addPayment(invoiceId, {
        date,
        amount: Math.round(value * 100) / 100,
        method,
        reference: reference.trim().slice(0, 60),
        bankAccountId: needsBankAccount ? effectiveBankAccountId : null,
      });
      toast.success(`${currency(value)} recorded against ${invoiceId}`);
      setOpen(false);
      setAmount("");
      setReference("");
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save the payment.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) {
          setAmount(String(balance || ""));
          setError(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button className="gap-2" disabled={balance <= 0}>
          <BanknoteArrowUp className="size-4" /> Record payment
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Record a payment</DialogTitle>
          <DialogDescription>
            Remaining balance on {invoiceId} is {currency(balance)}. Partial payments are allowed.
            {storeCreditBalance > 0 && ` ${currency(storeCreditBalance)} store credit available.`}
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="pay-amount">Amount (GHS)</Label>
            <Input
              id="pay-amount"
              type="number"
              min={0}
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          <div className="grid gap-2 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label>Method</Label>
              <Select value={method} onValueChange={(v) => setMethod(v as PaymentMethod)}>
                <SelectTrigger className="rounded-xl">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {methodOptions.map((m) => (
                    <SelectItem key={m} value={m}>
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="pay-date">Date</Label>
              <Input
                id="pay-date"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
          </div>
          {needsBankAccount && (
            <div className="grid gap-2">
              <Label htmlFor="pay-bank">Bank account</Label>
              <BankAccountSelect
                id="pay-bank"
                value={effectiveBankAccountId}
                onChange={setBankAccountId}
                placeholder={`Which bank received this ${method}?`}
              />
            </div>
          )}
          <div className="grid gap-2">
            <Label htmlFor="pay-ref">Reference</Label>
            <Input
              id="pay-ref"
              value={reference}
              maxLength={60}
              placeholder="MTN 8841, Till 04, GCB 33021…"
              onChange={(e) => setReference(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Saving…" : "Save payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
