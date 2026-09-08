import { useState } from "react";
import { toast } from "sonner";

import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";
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
import { useCurrentBranch } from "@/data/branch-store";
import { useCustomers } from "@/data/customer-store";
import {
  createCustomerDeposit,
  type DepositMethod,
  type CustomerDeposit,
} from "@/data/customer-deposits-store";
import { getErrorMessage } from "@/lib/utils";

const METHODS: DepositMethod[] = ["Cash", "Mobile Money", "Card", "Bank Transfer"];
const BANK_METHODS: DepositMethod[] = ["Card", "Bank Transfer"];

export function RecordDepositDialog({ onRecorded }: { onRecorded?: (d: CustomerDeposit) => void }) {
  const { id: branchId } = useCurrentBranch();
  const { customers } = useCustomers();
  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();

  const [open, setOpen] = useState(false);
  const [customerId, setCustomerId] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<DepositMethod>("Cash");
  const [bankAccountId, setBankAccountId] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const amountNum = Number(amount);
  const needsBank = BANK_METHODS.includes(method);
  const effectiveBank = bankAccountId || defaultBankAccountId;
  const canSubmit =
    !!customerId &&
    Number.isFinite(amountNum) &&
    amountNum > 0 &&
    (!needsBank || !!effectiveBank) &&
    !saving;

  function reset() {
    setCustomerId("");
    setDescription("");
    setAmount("");
    setMethod("Cash");
    setBankAccountId("");
    setError(null);
  }

  async function submit() {
    if (!branchId) {
      setError("No branch is configured.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const created = await createCustomerDeposit(branchId, {
        customerId,
        description: description.trim().slice(0, 240),
        amount: Math.round(amountNum * 100) / 100,
        method,
        bankAccountId: needsBank ? effectiveBank : null,
      });
      toast.success(`Deposit ${created.id} recorded — ${created.customerName}`);
      setOpen(false);
      onRecorded?.(created);
    } catch (err) {
      setError(getErrorMessage(err, "Could not record the deposit."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) reset();
      }}
    >
      <DialogTrigger asChild>
        <Button className="gap-2">Record deposit</Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Record a customer deposit</DialogTitle>
          <DialogDescription>
            Real money taken up front to reserve goods. Posts to the ledger and shows as a liability
            the moment it&apos;s saved. Always tied to a real customer — never a Walk-in.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="dep-customer">Customer</Label>
            <Select value={customerId} onValueChange={setCustomerId}>
              <SelectTrigger id="dep-customer">
                <SelectValue placeholder="Select a customer" />
              </SelectTrigger>
              <SelectContent>
                {customers.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name} · {c.phone}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="dep-desc">What&apos;s being reserved</Label>
            <Textarea
              id="dep-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="e.g. 2× Dulux Weathershield 20L — awaiting restock"
              rows={2}
              maxLength={240}
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="dep-amount">Amount (GH₵)</Label>
              <Input
                id="dep-amount"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="dep-method">Paid by</Label>
              <Select value={method} onValueChange={(v) => setMethod(v as DepositMethod)}>
                <SelectTrigger id="dep-method">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {METHODS.map((m) => (
                    <SelectItem key={m} value={m}>
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {needsBank && (
            <div className="space-y-2">
              <Label htmlFor="dep-bank">Into bank account</Label>
              <BankAccountSelect
                id="dep-bank"
                value={bankAccountId || defaultBankAccountId}
                onChange={setBankAccountId}
                placeholder={`Which bank received this ${method}?`}
              />
            </div>
          )}

          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={!canSubmit}>
            {saving ? "Recording…" : "Record deposit"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
