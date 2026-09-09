import { useState } from "react";
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

/** A Reject action that collects a reason in a proper dialog (not
 * window.prompt) before calling `onReject`. The reason is optional —
 * reject_employee() / reject_pay_config() both accept a null reason — but
 * the field is always offered. */
export function RejectButton({
  title,
  description,
  onReject,
  successMessage,
  label = "Reject",
  size = "sm",
  className,
}: {
  title: string;
  description?: string;
  onReject: (reason: string) => Promise<void>;
  successMessage: string;
  label?: string;
  size?: "sm" | "default";
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true);
    try {
      await onReject(reason.trim());
      toast.success(successMessage);
      setOpen(false);
      setReason("");
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not reject that."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !busy && setOpen(next)}>
      <DialogTrigger asChild>
        <Button size={size} variant="outline" className={className ?? "text-destructive"}>
          {label}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        <div className="space-y-1.5">
          <Label>Reason (optional)</Label>
          <Textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Why is this being rejected? The proposer sees this."
            rows={3}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={submit} disabled={busy}>
            {busy ? "Rejecting…" : "Reject"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
