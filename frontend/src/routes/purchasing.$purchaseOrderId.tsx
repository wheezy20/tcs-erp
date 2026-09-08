import { useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, PackageCheck } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
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
import { useAuth } from "@/data/auth-store";
import { currency, currencyPrecise } from "@/data/dashboard";
import { updateProduct, useInventory } from "@/data/inventory-store";
import {
  cancelPurchaseOrder,
  placePurchaseOrder,
  receivePurchaseOrder,
  recordSupplierPayment,
  usePurchaseOrders,
  type NewReceiptLine,
  type PurchaseOrder,
  type PurchaseOrderLine,
  type PurchaseOrderStatus,
  type SupplierPayment,
} from "@/data/purchasing-store";
import { getErrorMessage } from "@/lib/utils";
import { BankAccountSelect, useActiveBankAccounts } from "@/components/banking/bank-account-select";

export const Route = createFileRoute("/purchasing/$purchaseOrderId")({
  component: PurchaseOrderDetailPage,
});

const STATUS_LABELS: Record<PurchaseOrderStatus, string> = {
  draft: "Draft",
  ordered: "Ordered",
  partially_received: "Partially received",
  received: "Received",
  cancelled: "Cancelled",
};

const today = () => new Date().toISOString().slice(0, 10);

function PurchaseOrderDetailPage() {
  const { purchaseOrderId } = Route.useParams();
  const { purchaseOrders, loading } = usePurchaseOrders();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const po = purchaseOrders.find((p) => p.id === purchaseOrderId);
  if (!po) {
    return (
      <div className="mt-4 flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
        <p className="text-sm font-medium">{purchaseOrderId} no longer exists</p>
        <Button variant="outline" asChild className="mt-2 gap-2">
          <Link to="/purchasing">
            <ArrowLeft className="size-4" /> Back to purchase orders
          </Link>
        </Button>
      </div>
    );
  }

  return <PurchaseOrderDetail po={po} isManager={isManager} />;
}

function PurchaseOrderDetail({ po, isManager }: { po: PurchaseOrder; isManager: boolean }) {
  const [placing, setPlacing] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  async function place() {
    setPlacing(true);
    try {
      await placePurchaseOrder(po.id);
      toast.success(`${po.id} placed with the supplier`);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not place the purchase order."));
    } finally {
      setPlacing(false);
    }
  }

  async function cancel() {
    setCancelling(true);
    try {
      await cancelPurchaseOrder(po.id);
      toast.success(`${po.id} cancelled`);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not cancel the purchase order."));
    } finally {
      setCancelling(false);
    }
  }

  const canPlace = isManager && po.status === "draft";
  const canCancel = isManager && (po.status === "draft" || po.status === "ordered");
  const canReceive = isManager && (po.status === "ordered" || po.status === "partially_received");
  const canPay = isManager && po.balance > 0.01;

  return (
    <>
      <PageHeader
        title={po.id}
        description={`${po.supplierName} · ordered ${po.orderDate}${po.expectedDate ? ` · expected ${po.expectedDate}` : ""}`}
        actions={
          <>
            <Button variant="outline" asChild>
              <Link to="/purchasing">
                <ArrowLeft className="size-4" /> Back
              </Link>
            </Button>
            {canCancel && (
              <Button variant="outline" onClick={cancel} disabled={cancelling}>
                {cancelling ? "Cancelling…" : "Cancel order"}
              </Button>
            )}
            {canPlace && (
              <Button onClick={place} disabled={placing}>
                {placing ? "Placing…" : "Place order"}
              </Button>
            )}
            {/* Always mounted, not just when canReceive — a successful
                receive that fully completes the PO flips canReceive to
                false on the very next render (po.status becomes
                "received"), and conditionally mounting this component on
                canReceive would unmount it — and lose its in-progress cost
                review step — at exactly that moment. canReceive instead
                only gates the trigger button inside the component, while
                the controlled Dialog itself stays mounted regardless. */}
            <ReceiveGoodsDialog po={po} canReceive={canReceive} />
            {canPay && <RecordSupplierPaymentDialog po={po} />}
          </>
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
        <div className="space-y-6">
          <section className="card-surface overflow-hidden">
            <div className="border-b border-border px-5 py-3">
              <h2 className="text-sm font-semibold">Line items</h2>
            </div>
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Product</th>
                  <th className="px-5 py-3 text-right font-medium">Ordered</th>
                  <th className="px-5 py-3 text-right font-medium">Received</th>
                  <th className="px-5 py-3 text-right font-medium">Unit cost</th>
                  <th className="px-5 py-3 text-right font-medium">Line total</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {po.lines.map((line) => (
                  <tr key={line.id}>
                    <td className="px-5 py-3">
                      <div className="font-medium">{line.name}</div>
                      <div className="text-xs text-muted-foreground">{line.unit}</div>
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">{line.quantityOrdered}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {line.quantityReceived}
                      {line.quantityReceived >= line.quantityOrdered ? (
                        <PackageCheck className="ml-1 inline size-3.5 text-emerald-500" />
                      ) : null}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">{currency(line.unitCost)}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(line.quantityOrdered * line.unitCost)}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t-2 border-border font-semibold">
                <tr>
                  <td className="px-5 py-3" colSpan={4}>
                    Total
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">{currency(po.total)}</td>
                </tr>
              </tfoot>
            </table>
          </section>

          {po.notes && (
            <section className="card-surface p-5">
              <h2 className="text-sm font-semibold">Notes</h2>
              <p className="mt-1 text-sm text-muted-foreground">{po.notes}</p>
            </section>
          )}

          <section className="card-surface overflow-hidden">
            <div className="border-b border-border px-5 py-3">
              <h2 className="text-sm font-semibold">Goods received ({po.receipts.length})</h2>
            </div>
            {po.receipts.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-muted-foreground">
                Nothing received yet
              </p>
            ) : (
              <ul className="divide-y">
                {po.receipts.map((r) => (
                  <li key={r.id} className="px-5 py-3 text-sm">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="font-medium">{r.receivedDate}</span>
                      <span className="tabular-nums">{currency(r.totalValue)}</span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      Received by {r.receivedBy}
                      {r.notes ? ` · ${r.notes}` : ""}
                    </p>
                    <ul className="mt-1.5 space-y-0.5 text-xs text-muted-foreground">
                      {r.lines.map((rl) => {
                        const line = po.lines.find((l) => l.id === rl.purchaseOrderLineId);
                        return (
                          <li key={rl.id}>
                            {rl.quantity} × {line?.name ?? "Unknown item"} @ {currency(rl.unitCost)}
                          </li>
                        );
                      })}
                    </ul>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="card-surface overflow-hidden">
            <div className="border-b border-border px-5 py-3">
              <h2 className="text-sm font-semibold">Payments ({po.payments.length})</h2>
            </div>
            {po.payments.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-muted-foreground">
                No payments recorded yet
              </p>
            ) : (
              <ul className="divide-y">
                {po.payments.map((p) => (
                  <li
                    key={p.id}
                    className="flex items-center justify-between gap-3 px-5 py-3 text-sm"
                  >
                    <div>
                      <p className="font-medium">
                        {p.method}
                        {p.reference ? ` · ${p.reference}` : ""}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {p.paidAt.slice(0, 10)} · recorded by {p.recordedBy}
                      </p>
                    </div>
                    <span className="tabular-nums">{currency(p.amount)}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <aside className="space-y-4">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Status</h2>
            <Badge variant="outline" className="mt-2">
              {STATUS_LABELS[po.status]}
            </Badge>
            <dl className="mt-4 space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Ordered total</dt>
                <dd className="tabular-nums">{currency(po.total)}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Received value</dt>
                <dd className="tabular-nums">{currency(po.receivedValue)}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Paid</dt>
                <dd className="tabular-nums">{currency(po.amountPaid)}</dd>
              </div>
              <div className="flex justify-between border-t pt-2 font-semibold">
                <dt>Balance owed</dt>
                <dd className="tabular-nums">{currency(po.balance)}</dd>
              </div>
            </dl>
            <p className="mt-3 text-xs text-muted-foreground">
              Balance is what's owed for goods actually received, not the full ordered total — you
              only owe for what's arrived.
            </p>
          </section>
        </aside>
      </div>
    </>
  );
}

/** A PO line just received at a cost that differs from the product's own
 * currently recorded cost — surfaced for a Manager to confirm or decline,
 * never applied on its own. `currentCost: null` means the product has no
 * cost recorded at all yet, which still counts as "differs." */
type CostDiff = {
  productId: string;
  productName: string;
  poCost: number;
  currentCost: number | null;
};

function ReceiveGoodsDialog({ po, canReceive }: { po: PurchaseOrder; canReceive: boolean }) {
  const { products } = useInventory();
  const [open, setOpen] = useState(false);
  const [receivedDate, setReceivedDate] = useState(today());
  const [notes, setNotes] = useState("");
  const outstanding = po.lines.filter((l) => l.quantityReceived < l.quantityOrdered);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [submitting, setSubmitting] = useState(false);
  // Non-null once a receipt with at least one cost difference has just been
  // recorded — switches the dialog into the review step instead of closing.
  const [costDiffs, setCostDiffs] = useState<CostDiff[] | null>(null);
  const [resolution, setResolution] = useState<Record<string, "updated" | "kept">>({});
  const [applyingId, setApplyingId] = useState<string | null>(null);

  function reset() {
    setReceivedDate(today());
    setNotes("");
    setQuantities({});
    setCostDiffs(null);
    setResolution({});
    setApplyingId(null);
  }

  function quantityFor(lineId: string, remaining: number) {
    return quantities[lineId] ?? remaining;
  }

  async function submit() {
    const lines: NewReceiptLine[] = outstanding
      .map((l) => ({
        purchaseOrderLineId: l.id,
        quantity: quantityFor(l.id, l.quantityOrdered - l.quantityReceived),
      }))
      .filter((l) => l.quantity > 0);
    if (lines.length === 0) {
      toast.error("Enter a quantity greater than zero for at least one item.");
      return;
    }
    setSubmitting(true);
    try {
      await receivePurchaseOrder(po.id, { receivedDate, notes, lines });
      toast.success("Goods received recorded");

      // Cost paid is always the PO line's own unit_cost — receive_purchase_order()
      // has no separate "cost paid" input, it snapshots purchase_order_lines.unit_cost
      // onto the receipt (see the migration). So the comparison is exactly
      // "what this PO line was costed at" vs. the product's own current
      // recorded cost, both already available client-side with no extra
      // round trip: po.lines for the former, useInventory() for the latter.
      const diffs = lines
        .map((l) => po.lines.find((pl) => pl.id === l.purchaseOrderLineId))
        .filter((pl): pl is PurchaseOrderLine => Boolean(pl))
        .map((pl): CostDiff | null => {
          const product = products.find((p) => p.id === pl.productId);
          if (!product) return null;
          return {
            productId: pl.productId,
            productName: pl.name,
            poCost: pl.unitCost,
            currentCost: product.cost,
          };
        })
        .filter((d): d is CostDiff => d !== null)
        // A cent or less is a rounding artifact, not a real difference
        // worth interrupting a Manager for.
        .filter((d) => d.currentCost === null || Math.abs(d.currentCost - d.poCost) > 0.005);

      setQuantities({});
      setNotes("");
      setReceivedDate(today());
      if (diffs.length > 0) {
        setCostDiffs(diffs);
        setResolution({});
      } else {
        reset();
        setOpen(false);
      }
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not record goods received."));
    } finally {
      setSubmitting(false);
    }
  }

  // Deliberate, per-item action a Manager takes or declines — never
  // automatic. Declining (or just closing the dialog without choosing)
  // leaves the product's cost completely untouched, no side effects.
  async function applyCostUpdate(diff: CostDiff) {
    setApplyingId(diff.productId);
    try {
      await updateProduct(diff.productId, { cost: diff.poCost });
      toast.success(`${diff.productName}'s cost updated to ${currencyPrecise(diff.poCost)}`);
      setResolution((prev) => ({ ...prev, [diff.productId]: "updated" }));
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update the product's cost."));
    } finally {
      setApplyingId(null);
    }
  }

  function keepCurrentCost(diff: CostDiff) {
    setResolution((prev) => ({ ...prev, [diff.productId]: "kept" }));
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) reset();
      }}
    >
      {/* Gated on canReceive, not on whether this component is mounted at
          all (see the parent's own comment) — once a receipt is recorded
          and the PO moves to "received", canReceive goes false and this
          trigger correctly disappears, but the Dialog itself (and any
          in-progress cost review inside it) stays exactly as it was. */}
      {canReceive && (
        <DialogTrigger asChild>
          <Button className="gap-2">
            <PackageCheck className="size-4" /> Receive goods
          </Button>
        </DialogTrigger>
      )}
      <DialogContent className="max-w-lg">
        {costDiffs === null ? (
          <>
            <DialogHeader>
              <DialogTitle>Receive goods against {po.id}</DialogTitle>
              <DialogDescription>
                Defaults to what's still outstanding on each line — adjust for a short shipment.
                Updates stock and posts Dr Inventory / Cr Accounts Payable for the value received.
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="recv-date">Received date</Label>
                  <Input
                    id="recv-date"
                    type="date"
                    value={receivedDate}
                    onChange={(e) => setReceivedDate(e.target.value)}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="recv-notes">Notes (optional)</Label>
                  <Input id="recv-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
                </div>
              </div>
              <div className="space-y-2">
                {outstanding.map((l) => {
                  const remaining = l.quantityOrdered - l.quantityReceived;
                  return (
                    <div
                      key={l.id}
                      className="flex items-center justify-between gap-3 rounded-lg border p-3"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium">{l.name}</p>
                        <p className="text-xs text-muted-foreground">{remaining} outstanding</p>
                      </div>
                      <Input
                        type="number"
                        min={0}
                        max={remaining}
                        step="1"
                        value={quantityFor(l.id, remaining)}
                        onChange={(e) =>
                          setQuantities((prev) => ({
                            ...prev,
                            [l.id]: Math.max(0, Math.min(remaining, Number(e.target.value) || 0)),
                          }))
                        }
                        className="h-9 w-24"
                      />
                    </div>
                  );
                })}
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
                Cancel
              </Button>
              <Button onClick={submit} disabled={submitting}>
                {submitting ? "Recording…" : "Record receipt"}
              </Button>
            </DialogFooter>
          </>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>Update product cost?</DialogTitle>
              <DialogDescription>
                {costDiffs.length} item{costDiffs.length === 1 ? "" : "s"} on this receipt{" "}
                {costDiffs.length === 1 ? "was" : "were"} paid at a different cost than what's
                currently recorded for the product. This never happens automatically — decide per
                item, or close this without choosing to leave every cost exactly as it is.
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-2">
              {costDiffs.map((d) => {
                const outcome = resolution[d.productId];
                const isApplying = applyingId === d.productId;
                const delta = d.currentCost === null ? null : d.poCost - d.currentCost;
                return (
                  <div key={d.productId} className="rounded-lg border p-3">
                    <p className="text-sm font-medium">{d.productName}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      Currently recorded:{" "}
                      {d.currentCost === null ? "not recorded" : currencyPrecise(d.currentCost)} ·
                      Paid on this receipt: {currencyPrecise(d.poCost)}
                      {delta !== null && delta !== 0 && (
                        <>
                          {" "}
                          · {currencyPrecise(Math.abs(delta))} {delta > 0 ? "higher" : "lower"} than
                          recorded
                        </>
                      )}
                    </p>
                    {outcome ? (
                      <p className="mt-2 text-xs font-medium text-primary">
                        {outcome === "updated"
                          ? `Cost updated to ${currencyPrecise(d.poCost)}`
                          : `Kept at ${d.currentCost === null ? "not recorded" : currencyPrecise(d.currentCost)}`}
                      </p>
                    ) : (
                      <div className="mt-2 flex gap-2">
                        <Button
                          size="sm"
                          onClick={() => void applyCostUpdate(d)}
                          disabled={isApplying}
                        >
                          {isApplying ? "Updating…" : `Update to ${currencyPrecise(d.poCost)}`}
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => keepCurrentCost(d)}
                          disabled={isApplying}
                        >
                          Keep{" "}
                          {d.currentCost === null ? "unrecorded" : currencyPrecise(d.currentCost)}
                        </Button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
            <DialogFooter>
              <Button
                onClick={() => {
                  reset();
                  setOpen(false);
                }}
              >
                Done
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

const PAYMENT_METHODS: SupplierPayment["method"][] = [
  "Cash",
  "Mobile Money",
  "Bank Transfer",
  "Cheque",
];
const SUPPLIER_BANK_METHODS: SupplierPayment["method"][] = ["Bank Transfer", "Cheque"];

function RecordSupplierPaymentDialog({ po }: { po: PurchaseOrder }) {
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<SupplierPayment["method"]>("Bank Transfer");
  const [reference, setReference] = useState("");
  const [bankAccountId, setBankAccountId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const { defaultId: defaultBankAccountId } = useActiveBankAccounts();
  const needsBankAccount = SUPPLIER_BANK_METHODS.includes(method);
  const effectiveBankAccountId = bankAccountId || defaultBankAccountId;

  async function submit() {
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) {
      setError("Enter a payment amount greater than zero.");
      return;
    }
    if (value > po.balance + 0.01) {
      setError(`Amount cannot exceed the outstanding balance of ${currency(po.balance)}.`);
      return;
    }
    if (needsBankAccount && !effectiveBankAccountId) {
      setError(`Pick the bank account this ${method} was paid from.`);
      return;
    }
    setSubmitting(true);
    try {
      await recordSupplierPayment(po.id, {
        amount: value,
        method,
        reference,
        bankAccountId: needsBankAccount ? effectiveBankAccountId : null,
      });
      toast.success(`${currency(value)} paid to ${po.supplierName}`);
      setAmount("");
      setReference("");
      setError(null);
      setOpen(false);
    } catch (err) {
      setError(getErrorMessage(err, "Could not record the payment."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) {
          setAmount(String(po.balance || ""));
          setError(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button variant="outline">Record payment</Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Pay {po.supplierName}</DialogTitle>
          <DialogDescription>
            Outstanding balance on {po.id} is {currency(po.balance)}. Partial payments are allowed.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="sp-amount">Amount (GHS)</Label>
            <Input
              id="sp-amount"
              type="number"
              min={0}
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label>Method</Label>
            <Select value={method} onValueChange={(v) => setMethod(v as SupplierPayment["method"])}>
              <SelectTrigger className="rounded-xl">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {PAYMENT_METHODS.map((m) => (
                  <SelectItem key={m} value={m}>
                    {m}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {needsBankAccount && (
            <div className="grid gap-2">
              <Label htmlFor="sp-bank">Bank account</Label>
              <BankAccountSelect
                id="sp-bank"
                value={effectiveBankAccountId}
                onChange={setBankAccountId}
                placeholder={`Which bank account paid this ${method}?`}
              />
            </div>
          )}
          <div className="grid gap-2">
            <Label htmlFor="sp-ref">Reference</Label>
            <Input
              id="sp-ref"
              value={reference}
              maxLength={60}
              placeholder="Bank transfer ref, cheque number…"
              onChange={(e) => setReference(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Saving…" : "Save payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
