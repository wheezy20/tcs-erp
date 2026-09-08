import { useMemo, useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { InlineAddCustomerDialog } from "@/components/sales/inline-add-customer-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { useCurrentBranch } from "@/data/branch-store";
import { currency } from "@/data/dashboard";
import type { NewCustomer } from "@/data/customer-store";
import { hasPrice, useInventory } from "@/data/inventory-store";
import { DEFAULT_VAT_RATE, invoiceTotals, lineGross, type InvoiceLine } from "@/data/invoices";
import { createProFormaInvoice, type NewProFormaInvoice } from "@/data/pro-forma-store";
import { addCustomer, useSales } from "@/data/sales-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/pro-forma/new")({
  head: () => ({
    meta: [
      { title: "New pro-forma invoice — TCS" },
      {
        name: "description",
        content: "Build a non-binding quote — no stock or ledger impact until it's converted.",
      },
    ],
  }),
  component: NewProFormaPage,
});

const today = () => new Date().toISOString().slice(0, 10);
const addDays = (iso: string, days: number) => {
  const d = new Date(iso);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};
const emptyLine = (): InvoiceLine => ({
  id: `L${Math.floor(Math.random() * 100000)}`,
  productId: null,
  name: "",
  unit: "Pieces",
  quantity: 1,
  unitPrice: 0,
  discount: 0,
  vat: true,
});

function NewProFormaPage() {
  const navigate = useNavigate();
  const { customers, vatRate: defaultVatRate } = useSales();
  const { products } = useInventory();
  const { name: branchName } = useCurrentBranch();

  const [customerId, setCustomerId] = useState("");
  const [date, setDate] = useState(today());
  const [validUntil, setValidUntil] = useState(addDays(today(), 14));
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<InvoiceLine[]>([emptyLine()]);
  const [invoiceDiscount, setInvoiceDiscount] = useState("0");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const vatRate = defaultVatRate ?? DEFAULT_VAT_RATE;
  const allVat = lines.length > 0 && lines.every((l) => l.vat);

  // invoiceTotals() only needs the fields it actually reads (lines,
  // invoiceDiscount, vatRate, payments) — a pro-forma has no payments yet,
  // so this preview object is deliberately narrower than a real Invoice.
  const totals = useMemo(
    () =>
      invoiceTotals({
        id: "DRAFT",
        customerId,
        customerName: "",
        date,
        dueDate: validUntil,
        branch: branchName ?? "",
        issuedBy: "",
        notes,
        lines,
        invoiceDiscount: Number(invoiceDiscount) || 0,
        vatRate,
        payments: [],
        whtApplied: false,
        whtRate: null,
        whtAmount: 0,
        voidedAt: null,
        voidedBy: null,
        voidReason: null,
      }),
    [customerId, date, validUntil, branchName, notes, lines, invoiceDiscount, vatRate],
  );

  const updateLine = (id: string, patch: Partial<InvoiceLine>) =>
    setLines((prev) => prev.map((l) => (l.id === id ? { ...l, ...patch } : l)));

  const pickProduct = (id: string, productId: string) => {
    const product = products.find((p) => p.id === productId);
    if (!product) return;
    updateLine(id, {
      productId: product.id,
      name: product.name,
      unit: product.unit,
      // Unlike POS/invoicing, a pro-forma is a non-binding quote — no
      // ledger/stock/AR consequence until it's converted to a real
      // invoice, at which point create_invoice() enforces the same
      // priced-product rule. Quoting a customer on an item whose price
      // isn't finalized yet is a reasonable thing to do here, so this
      // starts the line at 0 (editable, same as every other field) rather
      // than blocking the pick outright.
      unitPrice: product.price ?? 0,
    });
  };

  const onNewCustomer = async (input: NewCustomer) => {
    const created = await addCustomer(input);
    setCustomerId(created.id);
  };

  const submit = async () => {
    if (!customerId) {
      setError("Select a customer for this quote.");
      return;
    }
    if (lines.length === 0 || lines.some((l) => !l.name.trim() || l.quantity <= 0)) {
      setError("Every line item needs a product and a quantity above zero.");
      return;
    }

    setSaving(true);
    try {
      const customerName = customers.find((c) => c.id === customerId)?.name ?? "";
      const pf: NewProFormaInvoice = {
        customerId,
        customerName,
        date,
        validUntil,
        notes: notes.trim().slice(0, 240),
        lines,
        invoiceDiscount: Number(invoiceDiscount) || 0,
        vatRate,
        total: totals.total,
      };
      const created = await createProFormaInvoice(pf);
      toast.success(`${created.id} created`);
      navigate({ to: "/pro-forma/$proFormaId", params: { proFormaId: created.id } });
    } catch (err) {
      setError(getErrorMessage(err, "Could not save the pro-forma invoice."));
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <PageHeader
        title="New pro-forma invoice"
        description={`A non-binding quote — no stock or ledger impact until converted · ${branchName ?? "…"}`}
        actions={
          <>
            <Button
              variant="outline"
              onClick={() => navigate({ to: "/pro-forma" })}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button onClick={submit} disabled={saving}>
              {saving ? "Saving…" : "Create pro-forma"}
            </Button>
          </>
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_340px]">
        <div className="space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Customer & dates</h2>
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <div className="grid gap-2 sm:col-span-2">
                <Label>Customer</Label>
                <div className="flex gap-2">
                  <Select value={customerId} onValueChange={setCustomerId}>
                    <SelectTrigger className="rounded-xl">
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
                  <InlineAddCustomerDialog onAdd={onNewCustomer} />
                </div>
              </div>
              <div className="grid gap-2">
                <Label htmlFor="pf-date">Quote date</Label>
                <Input
                  id="pf-date"
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="pf-valid">Valid until</Label>
                <Input
                  id="pf-valid"
                  type="date"
                  value={validUntil}
                  onChange={(e) => setValidUntil(e.target.value)}
                />
              </div>
            </div>
          </section>

          <section className="card-surface p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-sm font-semibold">Line items</h2>
              <div className="flex items-center gap-3">
                <label className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Switch
                    checked={allVat}
                    onCheckedChange={(v) => setLines((prev) => prev.map((l) => ({ ...l, vat: v })))}
                  />
                  VAT on all items
                </label>
                <Button
                  variant="outline"
                  size="sm"
                  className="gap-1.5"
                  onClick={() => setLines((prev) => [...prev, emptyLine()])}
                >
                  <Plus className="size-4" /> Add item
                </Button>
              </div>
            </div>

            <div className="mt-4 space-y-3">
              {lines.map((l, index) => (
                <div key={l.id} className="rounded-2xl border p-4">
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      Item {index + 1}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="size-8 text-muted-foreground hover:text-destructive"
                      onClick={() => setLines((prev) => prev.filter((x) => x.id !== l.id))}
                      aria-label="Remove line item"
                    >
                      <Trash2 className="size-4" />
                    </Button>
                  </div>

                  <div className="mt-3 grid gap-3 md:grid-cols-2">
                    <div className="grid gap-2 md:col-span-2">
                      <Label>Product</Label>
                      <Select value={l.productId ?? ""} onValueChange={(v) => pickProduct(l.id, v)}>
                        <SelectTrigger className="rounded-xl">
                          <SelectValue placeholder="Choose from inventory" />
                        </SelectTrigger>
                        <SelectContent>
                          {products.map((p) => (
                            <SelectItem key={p.id} value={p.id}>
                              {p.name} — {hasPrice(p) ? currency(p.price) : "No price set"} /{" "}
                              {p.unit.toLowerCase()}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="grid gap-2">
                      <Label>Quantity ({l.unit.toLowerCase()})</Label>
                      <Input
                        type="number"
                        min={0}
                        step="1"
                        value={l.quantity}
                        onChange={(e) =>
                          updateLine(l.id, { quantity: Number(e.target.value) || 0 })
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label>Unit price (GHS)</Label>
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        value={l.unitPrice}
                        onChange={(e) =>
                          updateLine(l.id, { unitPrice: Number(e.target.value) || 0 })
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label>Line discount (GHS)</Label>
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        value={l.discount}
                        onChange={(e) =>
                          updateLine(l.id, { discount: Number(e.target.value) || 0 })
                        }
                      />
                    </div>
                    <div className="flex items-end justify-between gap-3 rounded-xl bg-muted/50 px-3 py-2">
                      <label className="flex items-center gap-2 text-sm">
                        <Switch
                          checked={l.vat}
                          onCheckedChange={(v) => updateLine(l.id, { vat: v })}
                        />
                        VAT {vatRate}%
                      </label>
                      <span className="text-sm font-medium tabular-nums">
                        {currency(Math.max(0, lineGross(l) - l.discount))}
                      </span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="card-surface p-5">
            <Label htmlFor="pf-notes">Notes</Label>
            <Textarea
              id="pf-notes"
              className="mt-2"
              rows={3}
              maxLength={240}
              value={notes}
              placeholder="Delivery instructions, site reference, terms of the quote…"
              onChange={(e) => setNotes(e.target.value)}
            />
          </section>

          {error && <p className="text-sm font-medium text-destructive">{error}</p>}
        </div>

        <aside className="space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Totals</h2>
            <div className="mt-4 grid gap-3">
              <div className="grid gap-2">
                <Label htmlFor="pf-discount">Quote discount (GHS)</Label>
                <Input
                  id="pf-discount"
                  type="number"
                  min={0}
                  step="0.01"
                  value={invoiceDiscount}
                  onChange={(e) => setInvoiceDiscount(e.target.value)}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="pf-vat">VAT rate (%)</Label>
                <Input id="pf-vat" type="number" value={vatRate} disabled readOnly />
              </div>
            </div>

            <dl className="mt-5 space-y-2 border-t pt-4 text-sm">
              <Row label="Subtotal" value={currency(totals.subtotal)} />
              <Row label="Line discounts" value={`− ${currency(totals.lineDiscounts)}`} muted />
              <Row label="Quote discount" value={`− ${currency(totals.invoiceDiscount)}`} muted />
              <Row label={`VAT (${vatRate}%)`} value={currency(totals.vat)} muted />
              <div className="flex items-center justify-between border-t pt-3 text-base font-semibold">
                <span>Total</span>
                <span className="tabular-nums">{currency(totals.total)}</span>
              </div>
            </dl>
            <p className="mt-4 text-xs text-muted-foreground">
              Non-binding — no stock reservation, no journal entry, no amount owed until this quote
              is converted into a real invoice.
            </p>
          </section>
        </aside>
      </div>
    </>
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
