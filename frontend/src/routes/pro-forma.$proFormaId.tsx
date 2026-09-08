import { useState } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ArrowRight } from "lucide-react";
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
import { Switch } from "@/components/ui/switch";
import { currency } from "@/data/dashboard";
import { invoiceTotals, lineGross } from "@/data/invoices";
import { convertProFormaToInvoice, useProFormaInvoices } from "@/data/pro-forma-store";
import { useWhtRate } from "@/data/wht-settings-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/pro-forma/$proFormaId")({
  head: () => ({
    meta: [{ title: "Pro-forma invoice — TCS" }],
  }),
  component: ProFormaDetailPage,
});

const today = () => new Date().toISOString().slice(0, 10);
const addDays = (iso: string, days: number) => {
  const d = new Date(iso);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};

function ProFormaDetailPage() {
  const { proFormaId } = Route.useParams();
  const { proFormaInvoices, loading } = useProFormaInvoices();
  const pf = proFormaInvoices.find((p) => p.id === proFormaId);

  if (loading) return null;

  if (!pf) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">This pro-forma invoice no longer exists.</p>
        <Button asChild variant="outline" className="mt-4">
          <Link to="/pro-forma">Back to pro-forma invoices</Link>
        </Button>
      </div>
    );
  }

  const totals = invoiceTotals({
    id: pf.id,
    customerId: pf.customerId,
    customerName: pf.customerName,
    date: pf.date,
    dueDate: pf.validUntil,
    branch: "",
    issuedBy: pf.createdBy,
    notes: pf.notes,
    lines: pf.lines,
    invoiceDiscount: pf.invoiceDiscount,
    vatRate: pf.vatRate,
    payments: [],
    whtApplied: false,
    whtRate: null,
    whtAmount: 0,
    voidedAt: null,
    voidedBy: null,
    voidReason: null,
  });

  return (
    <>
      <PageHeader
        title={pf.id}
        description={`${pf.customerName} · Quoted ${pf.date} · Valid until ${pf.validUntil}`}
        actions={
          <>
            {pf.status === "open" ? (
              <ConvertDialog
                proFormaId={pf.id}
                defaultDueDate={pf.validUntil}
                total={totals.total}
              />
            ) : (
              <Button asChild variant="outline" className="gap-2">
                <Link to="/sales/$invoiceId" params={{ invoiceId: pf.convertedInvoiceId ?? "" }}>
                  View invoice {pf.convertedInvoiceId} <ArrowRight className="size-4" />
                </Link>
              </Button>
            )}
          </>
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_340px]">
        <section className="card-surface p-5">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">Line items</h2>
            {pf.status === "converted" ? (
              <Badge variant="secondary">Converted</Badge>
            ) : (
              <Badge className="bg-primary/15 text-primary hover:bg-primary/15">Open</Badge>
            )}
          </div>
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr className="border-b">
                  <th className="py-2 pr-4 font-medium">Item</th>
                  <th className="py-2 pr-4 text-right font-medium">Qty</th>
                  <th className="py-2 pr-4 text-right font-medium">Unit price</th>
                  <th className="py-2 pr-4 text-right font-medium">Discount</th>
                  <th className="py-2 pr-4 text-center font-medium">VAT</th>
                  <th className="py-2 text-right font-medium">Total</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {pf.lines.map((l) => (
                  <tr key={l.id}>
                    <td className="py-3 pr-4">
                      <p className="font-medium">{l.name}</p>
                      <p className="text-xs text-muted-foreground">{l.unit}</p>
                    </td>
                    <td className="py-3 pr-4 text-right tabular-nums">{l.quantity}</td>
                    <td className="py-3 pr-4 text-right tabular-nums">{currency(l.unitPrice)}</td>
                    <td className="py-3 pr-4 text-right tabular-nums text-muted-foreground">
                      {l.discount > 0 ? `− ${currency(l.discount)}` : "—"}
                    </td>
                    <td className="py-3 pr-4 text-center text-muted-foreground">
                      {l.vat ? `${pf.vatRate}%` : "—"}
                    </td>
                    <td className="py-3 text-right font-medium tabular-nums">
                      {currency(Math.max(0, lineGross(l) - l.discount))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {pf.notes && (
            <p className="mt-6 rounded-2xl bg-muted/50 px-4 py-3 text-sm text-muted-foreground">
              {pf.notes}
            </p>
          )}
        </section>

        <aside className="space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Totals</h2>
            <dl className="mt-4 space-y-2 border-t pt-4 text-sm">
              <Row label="Subtotal" value={currency(totals.subtotal)} />
              <Row label="Line discounts" value={`− ${currency(totals.lineDiscounts)}`} muted />
              <Row label="Quote discount" value={`− ${currency(totals.invoiceDiscount)}`} muted />
              <Row label={`VAT (${pf.vatRate}%)`} value={currency(totals.vat)} muted />
              <div className="flex items-center justify-between border-t pt-3 text-base font-semibold">
                <span>Total</span>
                <span className="tabular-nums">{currency(totals.total)}</span>
              </div>
            </dl>
            <p className="mt-4 text-xs text-muted-foreground">
              Non-binding — no stock reservation, no journal entry, no amount owed unless converted.
            </p>
          </section>

          <section className="card-surface p-5 text-sm text-muted-foreground">
            <p>Created by {pf.createdBy}</p>
            <p>Customer: {pf.customerName}</p>
          </section>
        </aside>
      </div>
    </>
  );
}

function ConvertDialog({
  proFormaId,
  defaultDueDate,
  total,
}: {
  proFormaId: string;
  defaultDueDate: string;
  total: number;
}) {
  const navigate = useNavigate();
  const { whtRate } = useWhtRate();
  const [open, setOpen] = useState(false);
  const [dueDate, setDueDate] = useState(addDays(today(), 30));
  const [whtApplied, setWhtApplied] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    setSaving(true);
    setError(null);
    try {
      const invoiceId = await convertProFormaToInvoice(proFormaId, dueDate, whtApplied);
      toast.success(`Converted to ${invoiceId}`);
      setOpen(false);
      navigate({ to: "/sales/$invoiceId", params: { invoiceId } });
    } catch (err) {
      setError(getErrorMessage(err, "Could not convert this pro-forma invoice."));
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
          setDueDate(addDays(today(), 30));
          setWhtApplied(false);
          setError(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button className="gap-2">
          Convert to invoice <ArrowRight className="size-4" />
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Convert to a real invoice</DialogTitle>
          <DialogDescription>
            Issues a new invoice today for {currency(total)}, using this quote's customer and line
            items. This can't be undone or repeated for the same quote.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="convert-due">Due date</Label>
            <Input
              id="convert-due"
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
            />
          </div>
          <div className="flex items-center justify-between gap-3 rounded-xl border p-3">
            <div className="min-w-0">
              <p className="text-sm font-medium">Apply withholding tax (WHT)</p>
              <p className="text-xs text-muted-foreground">
                At {whtRate ?? "…"}% of the taxable subtotal — deducted from what the customer pays,
                the invoice still shows full revenue.
              </p>
            </div>
            <Switch checked={whtApplied} onCheckedChange={setWhtApplied} />
          </div>
          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Converting…" : "Convert to invoice"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span className={muted ? "text-muted-foreground" : ""}>{label}</span>
      <span className={muted ? "tabular-nums text-muted-foreground" : "tabular-nums font-medium"}>
        {value}
      </span>
    </div>
  );
}
