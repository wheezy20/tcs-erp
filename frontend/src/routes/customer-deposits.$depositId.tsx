import { useState } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ArrowRight, Receipt, ShoppingCart } from "lucide-react";
import { toast } from "sonner";

import { statusBadge } from "@/routes/customer-deposits.index";
import { PageHeader } from "@/components/page-header";
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
import { cancelCustomerDeposit, useCustomerDeposits } from "@/data/customer-deposits-store";
import { currency } from "@/data/dashboard";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/customer-deposits/$depositId")({
  head: () => ({ meta: [{ title: "Customer deposit — TCS" }] }),
  component: CustomerDepositDetailPage,
});

function CustomerDepositDetailPage() {
  const { depositId } = Route.useParams();
  const { deposits, loading } = useCustomerDeposits();
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";
  const deposit = deposits.find((d) => d.id === depositId);

  if (loading) return null;

  if (!deposit) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">This deposit no longer exists.</p>
        <Button asChild variant="outline" className="mt-4">
          <Link to="/customer-deposits">Back to customer deposits</Link>
        </Button>
      </div>
    );
  }

  const isOpen = deposit.status === "Open";

  return (
    <>
      <PageHeader
        title={deposit.id}
        description={`${deposit.customerName} · taken ${deposit.takenAt.slice(0, 10)} by ${deposit.takenBy}`}
        actions={
          isOpen ? (
            <div className="flex flex-wrap gap-2">
              <Button asChild variant="outline" className="gap-2">
                <Link to="/pos" search={{ depositId: deposit.id }}>
                  <ShoppingCart className="size-4" /> Fulfil with a POS sale
                </Link>
              </Button>
              <Button asChild variant="outline" className="gap-2">
                <Link to="/sales/new" search={{ depositId: deposit.id }}>
                  <Receipt className="size-4" /> Fulfil with an invoice
                </Link>
              </Button>
              {isManager && <CancelDialog depositId={deposit.id} amount={deposit.amount} />}
            </div>
          ) : deposit.status === "Fulfilled" && deposit.fulfilledSaleId ? (
            <Button asChild variant="outline" className="gap-2">
              <Link to="/pos/history" search={{ q: deposit.fulfilledSaleId }}>
                View sale {deposit.fulfilledSaleId} <ArrowRight className="size-4" />
              </Link>
            </Button>
          ) : deposit.status === "Fulfilled" && deposit.fulfilledInvoiceId ? (
            <Button asChild variant="outline" className="gap-2">
              <Link to="/sales/$invoiceId" params={{ invoiceId: deposit.fulfilledInvoiceId }}>
                View invoice {deposit.fulfilledInvoiceId} <ArrowRight className="size-4" />
              </Link>
            </Button>
          ) : null
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
        <section className="card-surface p-5">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">Deposit</h2>
            {statusBadge(deposit.status)}
          </div>
          <dl className="mt-4 space-y-3 border-t pt-4 text-sm">
            <Row label="Customer" value={deposit.customerName} />
            <Row label="Reserved" value={deposit.description || "—"} />
            <Row label="Amount" value={currency(deposit.amount)} strong />
            <Row label="Paid by" value={deposit.method} />
            <Row
              label="Recorded"
              value={`${deposit.takenAt.slice(0, 16).replace("T", " ")} · ${deposit.takenBy}`}
            />
          </dl>

          {deposit.status === "Fulfilled" && (
            <p className="mt-5 rounded-2xl bg-muted/50 px-4 py-3 text-sm text-muted-foreground">
              Applied in full to{" "}
              {deposit.fulfilledSaleId
                ? `POS sale ${deposit.fulfilledSaleId}`
                : `invoice ${deposit.fulfilledInvoiceId}`}{" "}
              on {deposit.fulfilledAt?.slice(0, 10)} — the 2450 liability was cleared by that
              amount.
            </p>
          )}

          {deposit.status === "Cancelled" && (
            <dl className="mt-5 space-y-2 rounded-2xl bg-muted/50 px-4 py-3 text-sm">
              <Row
                label="Cancelled"
                value={`${deposit.cancelledAt?.slice(0, 10)} · ${deposit.cancelledBy}`}
              />
              <Row label="Fee retained" value={currency(deposit.cancellationFee ?? 0)} />
              <Row label="Refunded" value={currency(deposit.cancellationRefund ?? 0)} strong />
              {deposit.cancellationNote && <Row label="Note" value={deposit.cancellationNote} />}
            </dl>
          )}
        </section>

        <aside className="card-surface p-5 text-sm text-muted-foreground">
          <p className="font-medium text-foreground">How this settles</p>
          <p className="mt-2">
            Taking the deposit posted <span className="font-medium text-foreground">Dr</span>{" "}
            cash/bank /{" "}
            <span className="font-medium text-foreground">Cr 2450 Customer Deposits</span>.
          </p>
          <p className="mt-2">
            Fulfilling it starts a real POS sale or invoice for the reserved goods, applies this
            amount as a payment (clearing 2450), and collects the balance. VAT/WHT are handled by
            that document — the deposit itself never touches tax.
          </p>
          <p className="mt-2">
            Cancelling is Manager-only: the full amount comes back off 2450, an optional fee is kept
            as Other Income, and the rest is refunded.
          </p>
        </aside>
      </div>
    </>
  );
}

function CancelDialog({ depositId, amount }: { depositId: string; amount: number }) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [fee, setFee] = useState("0");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const feeNum = Number(fee) || 0;
  const refund = Math.round((amount - feeNum) * 100) / 100;
  const feeValid = Number.isFinite(feeNum) && feeNum >= 0 && feeNum <= amount;

  async function submit() {
    setSaving(true);
    setError(null);
    try {
      await cancelCustomerDeposit(depositId, Math.round(feeNum * 100) / 100, note);
      toast.success(`Deposit ${depositId} cancelled — ${currency(refund)} refunded`);
      setOpen(false);
      navigate({ to: "/customer-deposits" });
    } catch (err) {
      setError(getErrorMessage(err, "Could not cancel this deposit."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) {
          setFee("0");
          setNote("");
          setError(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button variant="ghost" className="text-destructive hover:text-destructive">
          Cancel deposit
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Cancel deposit {depositId}</DialogTitle>
          <DialogDescription>
            Refundable by default. Choose a fee to keep before refunding the rest — it&apos;s a real
            choice, nothing is deducted automatically. Manager only.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="cancel-fee">Fee to retain (GH₵)</Label>
            <Input
              id="cancel-fee"
              inputMode="decimal"
              value={fee}
              onChange={(e) => setFee(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              {feeValid
                ? `Refund to customer: ${currency(refund)} of ${currency(amount)}`
                : `Fee must be between GH₵0 and ${currency(amount)}`}
            </p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="cancel-note">Note (optional)</Label>
            <Textarea
              id="cancel-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="e.g. Customer changed their mind"
              rows={2}
              maxLength={240}
            />
          </div>
          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Keep deposit
          </Button>
          <Button variant="destructive" onClick={submit} disabled={saving || !feeValid}>
            {saving ? "Cancelling…" : `Cancel & refund ${currency(refund)}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-muted-foreground">{label}</span>
      <span className={strong ? "text-right font-semibold" : "text-right"}>{value}</span>
    </div>
  );
}
