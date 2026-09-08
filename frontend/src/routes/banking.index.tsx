import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Landmark, Pencil, Plus } from "lucide-react";
import { toast } from "sonner";

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
import { Switch } from "@/components/ui/switch";
import { useAuth } from "@/data/auth-store";
import {
  createBankAccount,
  updateBankAccount,
  useBankAccounts,
  type BankAccount,
} from "@/data/bank-accounts-store";
import { currency } from "@/data/dashboard";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/banking/")({
  component: BankAccountsPage,
});

const today = () => new Date().toISOString().slice(0, 10);

function BankAccountsPage() {
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const { accounts, loading } = useBankAccounts();
  const [editing, setEditing] = useState<BankAccount | null>(null);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  return (
    <div className="mt-4 space-y-4">
      <div className="flex justify-end">{isManager && <AddBankAccountDialog />}</div>

      {accounts.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Landmark className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No bank accounts yet</p>
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Name</th>
                  <th className="px-5 py-3 font-medium">Account number</th>
                  <th className="px-5 py-3 font-medium">Ledger account</th>
                  <th className="px-5 py-3 text-right font-medium">Opening balance</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  {isManager && <th className="px-5 py-3 font-medium">&nbsp;</th>}
                </tr>
              </thead>
              <tbody className="divide-y">
                {accounts.map((a) => (
                  <tr key={a.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3 font-medium">{a.name}</td>
                    <td className="px-5 py-3 font-mono text-xs text-muted-foreground">
                      {a.accountNumber}
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">
                      {a.glAccountCode} — {a.glAccountName}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(a.openingBalance)}{" "}
                      <span className="text-xs text-muted-foreground">
                        as of {a.openingBalanceDate}
                      </span>
                    </td>
                    <td className="px-5 py-3">
                      <Badge variant={a.active ? "default" : "secondary"}>
                        {a.active ? "Active" : "Inactive"}
                      </Badge>
                    </td>
                    {isManager && (
                      <td className="px-5 py-3 text-right">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="gap-1"
                          onClick={() => setEditing(a)}
                        >
                          <Pencil className="size-3.5" /> Edit
                        </Button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {editing && <EditBankAccountDialog account={editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function AddBankAccountDialog() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [openingBalance, setOpeningBalance] = useState("0");
  const [openingBalanceDate, setOpeningBalanceDate] = useState(today());
  const [currencyCode, setCurrencyCode] = useState("GHS");
  const [submitting, setSubmitting] = useState(false);

  function reset() {
    setName("");
    setAccountNumber("");
    setOpeningBalance("0");
    setOpeningBalanceDate(today());
    setCurrencyCode("GHS");
  }

  async function submit() {
    if (!name.trim() || !accountNumber.trim()) {
      toast.error("Name and account number are required.");
      return;
    }
    setSubmitting(true);
    try {
      const created = await createBankAccount({
        name: name.trim(),
        accountNumber: accountNumber.trim(),
        openingBalance: Number(openingBalance) || 0,
        openingBalanceDate,
        currency: currencyCode.trim() || "GHS",
      });
      toast.success(`${created.name} added`);
      reset();
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not add the bank account."));
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
          <Plus className="size-4" /> New bank account
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>New bank account</DialogTitle>
          <DialogDescription>
            A dedicated "Cash in Bank — {name.trim() || "…"}" ledger sub-account is created
            automatically and linked to this account. That link and the opening balance are fixed
            once created — they anchor every reconciliation's own math.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="ba-name">Name</Label>
            <Input
              id="ba-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. GCB Bank — Business Current Account"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ba-number">Account number</Label>
            <Input
              id="ba-number"
              value={accountNumber}
              onChange={(e) => setAccountNumber(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="ba-opening">Opening balance</Label>
              <Input
                id="ba-opening"
                inputMode="decimal"
                value={openingBalance}
                onChange={(e) => setOpeningBalance(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ba-opening-date">As of</Label>
              <Input
                id="ba-opening-date"
                type="date"
                value={openingBalanceDate}
                onChange={(e) => setOpeningBalanceDate(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ba-currency">Currency</Label>
            <Input
              id="ba-currency"
              value={currencyCode}
              maxLength={3}
              onChange={(e) => setCurrencyCode(e.target.value.toUpperCase())}
              className="w-24"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Adding…" : "Add bank account"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function EditBankAccountDialog({
  account,
  onClose,
}: {
  account: BankAccount;
  onClose: () => void;
}) {
  const [name, setName] = useState(account.name);
  const [accountNumber, setAccountNumber] = useState(account.accountNumber);
  const [currencyCode, setCurrencyCode] = useState(account.currency);
  const [active, setActive] = useState(account.active);
  const [submitting, setSubmitting] = useState(false);

  async function submit() {
    if (!name.trim() || !accountNumber.trim()) {
      toast.error("Name and account number are required.");
      return;
    }
    setSubmitting(true);
    try {
      await updateBankAccount(account.id, {
        name: name.trim(),
        accountNumber: accountNumber.trim(),
        currency: currencyCode.trim() || "GHS",
        active,
      });
      toast.success(`${account.name} updated`);
      onClose();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update the bank account."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Edit {account.name}</DialogTitle>
          <DialogDescription>
            Linked to {account.glAccountCode} — {account.glAccountName}, opening balance{" "}
            {currency(account.openingBalance)} as of {account.openingBalanceDate}. Neither can be
            changed once created — deactivate and create a new bank account instead.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="eba-name">Name</Label>
            <Input id="eba-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="eba-number">Account number</Label>
            <Input
              id="eba-number"
              value={accountNumber}
              onChange={(e) => setAccountNumber(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="eba-currency">Currency</Label>
            <Input
              id="eba-currency"
              value={currencyCode}
              maxLength={3}
              onChange={(e) => setCurrencyCode(e.target.value.toUpperCase())}
              className="w-24"
            />
          </div>
          <div className="flex items-center justify-between rounded-lg border px-3 py-2">
            <div>
              <p className="text-sm font-medium">Active</p>
              <p className="text-xs text-muted-foreground">
                Inactive accounts stay for history but drop out of new-deposit/reconciliation
                pickers.
              </p>
            </div>
            <Switch checked={active} onCheckedChange={setActive} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Saving…" : "Save changes"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
