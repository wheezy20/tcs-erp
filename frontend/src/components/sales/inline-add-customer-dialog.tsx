import { useState } from "react";
import { UserPlus } from "lucide-react";

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
import type { NewCustomer } from "@/data/customer-store";

export function InlineAddCustomerDialog({
  onAdd,
}: {
  onAdd: (customer: NewCustomer) => void | Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [address, setAddress] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    if (name.trim().length < 2) {
      setError("Enter the customer's full name.");
      return;
    }
    if (phone.trim().length < 7) {
      setError("Enter a valid phone number.");
      return;
    }
    setSaving(true);
    try {
      await onAdd({
        name: name.trim().slice(0, 80),
        phone: phone.trim().slice(0, 30),
        email: email.trim().slice(0, 120),
        address: address.trim().slice(0, 160),
      });
      setOpen(false);
      setName("");
      setPhone("");
      setEmail("");
      setAddress("");
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not add the customer.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button type="button" variant="outline" className="gap-2">
          <UserPlus className="size-4" /> New customer
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Add a customer</DialogTitle>
          <DialogDescription>
            The new customer is selected on this invoice straight away.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="ic-name">Full name</Label>
            <Input
              id="ic-name"
              value={name}
              maxLength={80}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="ic-phone">Phone</Label>
            <Input
              id="ic-phone"
              value={phone}
              maxLength={30}
              placeholder="+233 24 000 0000"
              onChange={(e) => setPhone(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="ic-email">Email (optional)</Label>
            <Input
              id="ic-email"
              type="email"
              value={email}
              maxLength={120}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="ic-address">Address (optional)</Label>
            <Input
              id="ic-address"
              value={address}
              maxLength={160}
              onChange={(e) => setAddress(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button type="button" onClick={submit} disabled={saving}>
            {saving ? "Adding…" : "Add customer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
