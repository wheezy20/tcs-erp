import { useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Pencil } from "lucide-react";
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
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { usePurchaseOrders } from "@/data/purchasing-store";
import { updateSupplier, useSuppliers, type Supplier } from "@/data/suppliers-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/purchasing/suppliers/$supplierId")({
  component: SupplierDetailPage,
});

function SupplierDetailPage() {
  const { supplierId } = Route.useParams();
  const { suppliers, loading: suppliersLoading } = useSuppliers();
  const { purchaseOrders, loading: poLoading } = usePurchaseOrders();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const [editing, setEditing] = useState(false);

  if (suppliersLoading || poLoading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const supplier = suppliers.find((s) => s.id === supplierId);
  if (!supplier) {
    return (
      <div className="mt-4 flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
        <p className="text-sm font-medium">This supplier no longer exists</p>
        <Button variant="outline" asChild className="mt-2 gap-2">
          <Link to="/purchasing/suppliers">
            <ArrowLeft className="size-4" /> Back to suppliers
          </Link>
        </Button>
      </div>
    );
  }

  const orders = purchaseOrders.filter((po) => po.supplierId === supplier.id);

  return (
    <>
      <PageHeader
        title={supplier.name}
        description={supplier.contactName || "No contact person on file"}
        actions={
          <>
            <Button variant="outline" asChild>
              <Link to="/purchasing/suppliers">
                <ArrowLeft className="size-4" /> Back
              </Link>
            </Button>
            {isManager && (
              <Button variant="outline" className="gap-2" onClick={() => setEditing(true)}>
                <Pencil className="size-4" /> Edit
              </Button>
            )}
          </>
        }
      />

      <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
        <div className="space-y-6">
          <section className="card-surface overflow-hidden">
            <div className="border-b border-border px-5 py-3">
              <h2 className="text-sm font-semibold">Purchase orders ({orders.length})</h2>
            </div>
            {orders.length === 0 ? (
              <p className="px-5 py-10 text-center text-sm text-muted-foreground">
                No purchase orders with this supplier yet
              </p>
            ) : (
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="px-5 py-3 font-medium">PO number</th>
                    <th className="px-5 py-3 font-medium">Status</th>
                    <th className="px-5 py-3 font-medium">Order date</th>
                    <th className="px-5 py-3 text-right font-medium">Total</th>
                    <th className="px-5 py-3 text-right font-medium">Balance</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {orders.map((po) => (
                    <tr key={po.id} className="hover:bg-muted/40">
                      <td className="px-5 py-3">
                        <Link
                          to="/purchasing/$purchaseOrderId"
                          params={{ purchaseOrderId: po.id }}
                          className="font-medium text-primary hover:underline"
                        >
                          {po.id}
                        </Link>
                      </td>
                      <td className="px-5 py-3 capitalize text-muted-foreground">
                        {po.status.replace("_", " ")}
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">{po.orderDate}</td>
                      <td className="px-5 py-3 text-right tabular-nums">{currency(po.total)}</td>
                      <td className="px-5 py-3 text-right font-medium tabular-nums">
                        {currency(po.balance)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>
        </div>

        <aside className="space-y-4">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Contact</h2>
            <dl className="mt-3 space-y-2 text-sm">
              <div className="flex justify-between gap-3">
                <dt className="text-muted-foreground">Phone</dt>
                <dd>{supplier.phone || "—"}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-muted-foreground">Email</dt>
                <dd className="truncate">{supplier.email || "—"}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-muted-foreground">Address</dt>
                <dd className="truncate text-right">{supplier.address || "—"}</dd>
              </div>
            </dl>
            <Badge variant={supplier.active ? "default" : "secondary"} className="mt-3">
              {supplier.active ? "Active" : "Inactive"}
            </Badge>
          </section>

          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Outstanding bills</h2>
            <p className="mt-2 text-2xl font-semibold tabular-nums">{currency(supplier.balance)}</p>
            <p className="mt-1 text-xs text-muted-foreground">
              What we currently owe this supplier
            </p>
            <div className="mt-4 flex justify-between border-t pt-3 text-sm">
              <span className="text-muted-foreground">Lifetime received</span>
              <span className="tabular-nums">{currency(supplier.lifetimeTotal)}</span>
            </div>
          </section>
        </aside>
      </div>

      {editing && <EditSupplierDialog supplier={supplier} onClose={() => setEditing(false)} />}
    </>
  );
}

function EditSupplierDialog({ supplier, onClose }: { supplier: Supplier; onClose: () => void }) {
  const [name, setName] = useState(supplier.name);
  const [contactName, setContactName] = useState(supplier.contactName);
  const [phone, setPhone] = useState(supplier.phone);
  const [email, setEmail] = useState(supplier.email);
  const [address, setAddress] = useState(supplier.address);
  const [active, setActive] = useState(supplier.active);
  const [submitting, setSubmitting] = useState(false);

  async function submit() {
    if (!name.trim()) {
      toast.error("Supplier name is required.");
      return;
    }
    setSubmitting(true);
    try {
      await updateSupplier(supplier.id, { name, contactName, phone, email, address, active });
      toast.success(`${name} updated`);
      onClose();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update the supplier."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Edit {supplier.name}</DialogTitle>
          <DialogDescription>
            Contact details only — balance and history stay untouched.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="esup-name">Name</Label>
            <Input id="esup-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="esup-contact">Contact person</Label>
            <Input
              id="esup-contact"
              value={contactName}
              onChange={(e) => setContactName(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="esup-phone">Phone</Label>
              <Input id="esup-phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="esup-email">Email</Label>
              <Input
                id="esup-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="esup-address">Address</Label>
            <Input id="esup-address" value={address} onChange={(e) => setAddress(e.target.value)} />
          </div>
          <div className="flex items-center justify-between rounded-lg border px-3 py-2">
            <div>
              <p className="text-sm font-medium">Active</p>
              <p className="text-xs text-muted-foreground">Inactive suppliers stay for history.</p>
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
