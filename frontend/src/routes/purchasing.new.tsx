import { useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { ProductSearchSelect } from "@/components/product-search-select";
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
import { Textarea } from "@/components/ui/textarea";
import { currency } from "@/data/dashboard";
import { useInventory } from "@/data/inventory-store";
import { createPurchaseOrder, type NewPurchaseOrderLine } from "@/data/purchasing-store";
import { useSuppliers } from "@/data/suppliers-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/purchasing/new")({
  component: NewPurchaseOrderPage,
});

const today = () => new Date().toISOString().slice(0, 10);

type DraftLine = NewPurchaseOrderLine & { key: string };
const emptyLine = (): DraftLine => ({
  key: `L${Math.random().toString(36).slice(2)}`,
  productId: "",
  name: "",
  unit: "",
  quantity: 1,
  unitCost: 0,
});

function NewPurchaseOrderPage() {
  const navigate = useNavigate();
  const { suppliers } = useSuppliers();
  const { products } = useInventory();

  const [supplierId, setSupplierId] = useState("");
  const [orderDate, setOrderDate] = useState(today());
  const [expectedDate, setExpectedDate] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([emptyLine()]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supplier = suppliers.find((s) => s.id === supplierId) ?? null;
  const total = lines.reduce((sum, l) => sum + l.quantity * l.unitCost, 0);

  function updateLine(key: string, patch: Partial<DraftLine>) {
    setLines((prev) => prev.map((l) => (l.key === key ? { ...l, ...patch } : l)));
  }

  function pickProduct(key: string, productId: string) {
    const product = products.find((p) => p.id === productId);
    if (!product) return;
    updateLine(key, {
      productId: product.id,
      name: product.name,
      unit: product.unit,
      // Prefilled from the product's last recorded cost purely as a
      // starting point — this is the price actually being paid on this
      // purchase, which the supplier may quote differently, so it stays
      // editable regardless. Falls back to 0 (not left blank) when the
      // product has no cost recorded yet, same as every other numeric
      // input on this form.
      unitCost: product.cost ?? 0,
    });
  }

  async function submit() {
    if (!supplier) {
      setError("Select a supplier.");
      return;
    }
    const validLines = lines.filter((l) => l.productId && l.quantity > 0);
    if (validLines.length === 0) {
      setError("Add at least one line with a product and a quantity greater than zero.");
      return;
    }
    setError(null);
    setSaving(true);
    try {
      const created = await createPurchaseOrder({
        supplierId: supplier.id,
        supplierName: supplier.name,
        orderDate,
        expectedDate: expectedDate || null,
        notes,
        lines: validLines,
      });
      toast.success(`${created.id} created as a draft`);
      navigate({ to: "/purchasing/$purchaseOrderId", params: { purchaseOrderId: created.id } });
    } catch (err) {
      setError(getErrorMessage(err, "Could not create the purchase order."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <PageHeader
        title="New purchase order"
        description="Cost price only — a purchase order deals in what you pay a supplier, not what you'll sell for."
        actions={
          <>
            <Button
              variant="outline"
              onClick={() => navigate({ to: "/purchasing" })}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button onClick={submit} disabled={saving}>
              {saving ? "Creating…" : "Create draft"}
            </Button>
          </>
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
        <div className="space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Supplier & dates</h2>
            <div className="mt-4 grid gap-4 sm:grid-cols-3">
              <div className="grid gap-2 sm:col-span-3">
                <Label>Supplier</Label>
                <Select value={supplierId} onValueChange={setSupplierId}>
                  <SelectTrigger className="rounded-xl">
                    <SelectValue placeholder="Select a supplier" />
                  </SelectTrigger>
                  <SelectContent>
                    {suppliers.map((s) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label>Order date</Label>
                <Input
                  type="date"
                  value={orderDate}
                  onChange={(e) => setOrderDate(e.target.value)}
                />
              </div>
              <div className="grid gap-2">
                <Label>Expected date (optional)</Label>
                <Input
                  type="date"
                  value={expectedDate}
                  onChange={(e) => setExpectedDate(e.target.value)}
                />
              </div>
              <div className="grid gap-2">
                <Label>Notes (optional)</Label>
                <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={1} />
              </div>
            </div>
          </section>

          <section className="card-surface p-5">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Line items</h2>
              <Button
                variant="outline"
                size="sm"
                className="gap-1"
                onClick={() => setLines((prev) => [...prev, emptyLine()])}
              >
                <Plus className="size-4" /> Add item
              </Button>
            </div>

            <div className="mt-4 space-y-3">
              {lines.map((l, index) => (
                <div key={l.key} className="rounded-2xl border p-4">
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      Item {index + 1}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="size-8 text-muted-foreground hover:text-destructive"
                      onClick={() => setLines((prev) => prev.filter((x) => x.key !== l.key))}
                      aria-label="Remove line item"
                    >
                      <Trash2 className="size-4" />
                    </Button>
                  </div>

                  <div className="mt-3 grid gap-3 md:grid-cols-3">
                    <div className="grid gap-2 md:col-span-3">
                      <Label>Product</Label>
                      <ProductSearchSelect
                        products={products}
                        value={l.productId || null}
                        onSelect={(p) => pickProduct(l.key, p.id)}
                        optionLabel={(p) =>
                          `${p.name} — ${p.cost !== null ? `${currency(p.cost)} cost` : "cost not recorded"} / ${p.unit.toLowerCase()}`
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label>Quantity {l.unit ? `(${l.unit.toLowerCase()})` : ""}</Label>
                      <Input
                        type="number"
                        min={1}
                        step="1"
                        value={l.quantity}
                        onChange={(e) =>
                          updateLine(l.key, { quantity: Number(e.target.value) || 0 })
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label>Unit cost (GHS)</Label>
                      <Input
                        type="number"
                        min={0}
                        step="0.01"
                        value={l.unitCost}
                        onChange={(e) =>
                          updateLine(l.key, { unitCost: Number(e.target.value) || 0 })
                        }
                      />
                    </div>
                    <div className="flex items-end justify-between rounded-xl bg-muted/50 px-3 py-2">
                      <span className="text-xs text-muted-foreground">Line total</span>
                      <span className="text-sm font-medium tabular-nums">
                        {currency(l.quantity * l.unitCost)}
                      </span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </section>

          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>

        <aside className="space-y-4">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Summary</h2>
            <div className="mt-4 flex items-center justify-between text-sm">
              <span className="text-muted-foreground">Total</span>
              <span className="text-lg font-semibold tabular-nums">{currency(total)}</span>
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              Nothing is owed and no journal entry posts yet — a purchase order is a request.
              Accounts Payable only grows once goods are actually received against it.
            </p>
          </section>
        </aside>
      </div>
    </>
  );
}
