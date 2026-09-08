import { useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Plus, Truck } from "lucide-react";
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
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { createSupplier, useSuppliers } from "@/data/suppliers-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/purchasing/suppliers/")({
  component: SuppliersPage,
});

function SuppliersPage() {
  const { suppliers, loading } = useSuppliers();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const [search, setSearch] = useState("");

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const term = search.trim().toLowerCase();
  const filtered = term
    ? suppliers.filter((s) => s.name.toLowerCase().includes(term) || s.phone.includes(term))
    : suppliers;

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by name or phone…"
          className="h-9 w-64 rounded-xl"
        />
        {isManager && <AddSupplierDialog />}
      </div>

      {filtered.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Truck className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No suppliers match "{search}"</p>
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Name</th>
                  <th className="px-5 py-3 font-medium">Contact</th>
                  <th className="px-5 py-3 font-medium">Phone</th>
                  <th className="px-5 py-3 text-right font-medium">Owed</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((s) => (
                  <tr key={s.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/purchasing/suppliers/$supplierId"
                        params={{ supplierId: s.id }}
                        className="font-medium text-primary hover:underline"
                      >
                        {s.name}
                      </Link>
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{s.contactName || "—"}</td>
                    <td className="px-5 py-3 text-muted-foreground">{s.phone || "—"}</td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(s.balance)}
                    </td>
                    <td className="px-5 py-3">
                      <Badge variant={s.active ? "default" : "secondary"}>
                        {s.active ? "Active" : "Inactive"}
                      </Badge>
                    </td>
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

function AddSupplierDialog() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [contactName, setContactName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [address, setAddress] = useState("");
  const [submitting, setSubmitting] = useState(false);

  function reset() {
    setName("");
    setContactName("");
    setPhone("");
    setEmail("");
    setAddress("");
  }

  async function submit() {
    if (!name.trim()) {
      toast.error("Supplier name is required.");
      return;
    }
    setSubmitting(true);
    try {
      const created = await createSupplier({ name, contactName, phone, email, address });
      toast.success(`${created.name} added`);
      reset();
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not add the supplier."));
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
          <Plus className="size-4" /> New supplier
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>New supplier</DialogTitle>
          <DialogDescription>
            Only the name is required — fill in the rest as you learn it.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="sup-name">Name</Label>
            <Input id="sup-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sup-contact">Contact person</Label>
            <Input
              id="sup-contact"
              value={contactName}
              onChange={(e) => setContactName(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="sup-phone">Phone</Label>
              <Input id="sup-phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="sup-email">Email</Label>
              <Input
                id="sup-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sup-address">Address</Label>
            <Input id="sup-address" value={address} onChange={(e) => setAddress(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Adding…" : "Add supplier"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
