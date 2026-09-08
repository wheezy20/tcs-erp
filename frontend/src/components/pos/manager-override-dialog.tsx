import { useState } from "react";
import { ShieldCheck } from "lucide-react";
import { toast } from "sonner";

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
import { requestManagerOverride } from "@/data/manager-override";
import { getErrorMessage } from "@/lib/utils";

/**
 * The Session 9 "Manager PIN" popup — reuses a Manager's real email/password
 * rather than a separate PIN (see manager-override.ts for why). Entering
 * this dialog never touches the Attendant's own signed-in session: the
 * credentials typed here are spent on a single, one-off ticket-minting call
 * and immediately discarded, so the app never sees or stores them beyond
 * this component's own local state.
 */
export function ManagerOverrideDialog({
  open,
  onOpenChange,
  requestedBy,
  onAuthorized,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  requestedBy: string;
  onAuthorized: (ticketId: string) => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);

  function reset() {
    setEmail("");
    setPassword("");
    setReason("");
  }

  async function submit() {
    if (!email || !password) return;
    setSubmitting(true);
    try {
      const ticket = await requestManagerOverride(email, password, requestedBy, reason);
      toast.success("Manager authorization confirmed for this sale.");
      onAuthorized(ticket.id);
      reset();
      onOpenChange(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not authorize the override."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) reset();
        onOpenChange(next);
      }}
    >
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <ShieldCheck className="size-4" /> Manager authorization
          </DialogTitle>
          <DialogDescription>
            Ask a Manager to sign in here to unlock an arbitrary discount or VAT override for this
            sale. Your own session stays signed in — this doesn't switch accounts.
          </DialogDescription>
        </DialogHeader>

        <form
          className="space-y-3"
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="manager-override-email">Manager email</Label>
            <Input
              id="manager-override-email"
              type="email"
              autoComplete="off"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="manager-override-password">Manager password</Label>
            <Input
              id="manager-override-password"
              type="password"
              autoComplete="off"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="manager-override-reason">Reason (optional)</Label>
            <Input
              id="manager-override-reason"
              placeholder="e.g. Bulk order, price match"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={submitting}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={submitting || !email || !password}>
              {submitting ? "Checking…" : "Authorize"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
