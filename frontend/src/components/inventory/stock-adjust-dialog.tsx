import { useState } from "react";
import { toast } from "sonner";
import { SlidersHorizontal } from "lucide-react";

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
import { adjustStock } from "@/data/inventory-store";
import type { Product } from "@/data/inventory";

export function StockAdjustDialog({ product }: { product: Product }) {
  const [open, setOpen] = useState(false);
  const [quantity, setQuantity] = useState(String(product.stock));
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    const qty = Number(quantity);
    if (!Number.isInteger(qty) || qty < 0 || qty > 1_000_000) {
      setError("Enter a whole number between 0 and 1,000,000.");
      return;
    }
    if (reason.trim().length < 4) {
      setError("Give a reason of at least 4 characters.");
      return;
    }
    setSaving(true);
    try {
      await adjustStock(product.id, qty, reason.trim());
      toast.success(
        `Stock corrected to ${qty.toLocaleString("en-GH")} ${product.unit.toLowerCase()}`,
      );
      setReason("");
      setError(null);
      setOpen(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save the correction.");
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
          setQuantity(String(product.stock));
          setReason("");
          setError(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button variant="outline" className="gap-2">
          <SlidersHorizontal className="size-4" /> Adjust stock
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Manual stock correction</DialogTitle>
          <DialogDescription>
            Current count is {product.stock.toLocaleString("en-GH")} {product.unit.toLowerCase()}.
            Corrections are recorded in the inventory history.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="adjust-qty">New quantity in stock</Label>
            <Input
              id="adjust-qty"
              type="number"
              min={0}
              step={1}
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="adjust-reason">Reason for correction</Label>
            <Textarea
              id="adjust-reason"
              rows={3}
              maxLength={200}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Stock count variance, breakage, damaged goods…"
            />
          </div>
          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Saving…" : "Save correction"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
