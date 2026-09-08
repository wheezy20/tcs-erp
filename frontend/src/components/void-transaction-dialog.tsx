import { useState } from "react";
import { Ban } from "lucide-react";
import { toast } from "sonner";

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
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { getErrorMessage } from "@/lib/utils";

/** Manager-only "void this whole transaction" action. A void reverses every
 * ledger entry the sale/invoice/expense produced, restores stock (POS only)
 * and marks the row dead — it is not a return. The reason is mandatory and
 * is written to the audit log. Every guard (Manager, non-blank reason,
 * closed day, existing returns, 7-day window) is also enforced
 * server-side; this dialog just surfaces whatever the RPC rejects with. */
export function VoidTransactionDialog({
  kind,
  id,
  onVoid,
}: {
  kind: "sale" | "invoice" | "expense";
  id: string;
  onVoid: (reason: string) => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const label = kind;
  const canSubmit = reason.trim().length > 0 && !saving;

  async function submit() {
    setSaving(true);
    setError(null);
    try {
      await onVoid(reason.trim());
      toast.success(`${id} voided`);
      setOpen(false);
    } catch (err) {
      setError(getErrorMessage(err, `Could not void this ${label}.`));
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
          setReason("");
          setError(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button variant="ghost" size="sm" className="gap-2 text-destructive hover:text-destructive">
          <Ban className="size-4" /> Void {label}
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Void {id}</DialogTitle>
          <DialogDescription>
            This erases the whole {label}: its ledger entry
            {kind === "invoice" ? " and every payment on it are" : " is"} reversed
            {kind === "sale" ? ", its stock is restored," : ","} and it stops counting anywhere. It
            is not a return, and it can&apos;t be undone. Manager only.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <Label htmlFor="void-reason">Reason (required)</Label>
          <Textarea
            id="void-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Rang up on the wrong customer"
            rows={3}
            maxLength={240}
          />
          {error ? <p className="text-sm font-medium text-destructive">{error}</p> : null}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Keep {label}
          </Button>
          <Button variant="destructive" onClick={submit} disabled={!canSubmit}>
            {saving ? "Voiding…" : `Void ${label}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
