import { useEffect, useState } from "react";
import { Clock, PauseCircle, Trash2 } from "lucide-react";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { discardHeldSale, resumeHeldSale, useHeldSales } from "@/data/held-sales-store";
import type { HeldSale } from "@/data/pos";
import { getErrorMessage } from "@/lib/utils";

function relativeHeld(heldAtIso: string, now: number): string {
  const seconds = Math.max(0, Math.floor((now - new Date(heldAtIso).getTime()) / 1000));
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}h ${remainingMinutes}m ago`;
}

/** The "Held sales" list — visible to every staff member signed in at the
 * branch (not scoped to whoever parked each one, matching held_sales_select's
 * RLS), so a busy till can juggle several parked customers and any coworker
 * can pick one back up. Resuming replaces the active cart wholesale — a
 * confirming AlertDialog guards that when the cart isn't already empty, so
 * in-progress work is never silently discarded. */
export function HeldSalesDialog({
  open,
  onOpenChange,
  hasActiveCart,
  onResume,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  hasActiveCart: boolean;
  onResume: (sale: HeldSale) => void;
}) {
  const { heldSales, loading } = useHeldSales();
  const [resumingId, setResumingId] = useState<string | null>(null);
  const [discardingId, setDiscardingId] = useState<string | null>(null);
  const [confirmId, setConfirmId] = useState<string | null>(null);

  async function doResume(id: string) {
    setResumingId(id);
    try {
      const sale = await resumeHeldSale(id);
      onResume(sale);
      onOpenChange(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not resume this held sale."));
    } finally {
      setResumingId(null);
      setConfirmId(null);
    }
  }

  function requestResume(id: string) {
    if (hasActiveCart) {
      setConfirmId(id);
    } else {
      void doResume(id);
    }
  }

  async function doDiscard(id: string) {
    setDiscardingId(id);
    try {
      await discardHeldSale(id);
      toast.success("Held sale discarded.");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not discard this held sale."));
    } finally {
      setDiscardingId(null);
    }
  }

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <PauseCircle className="size-4.5" /> Held sales
            </DialogTitle>
          </DialogHeader>

          {loading ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Loading…</p>
          ) : heldSales.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No sales are currently on hold.
            </p>
          ) : (
            <div className="max-h-[60vh] space-y-2 overflow-y-auto">
              {heldSales.map((sale) => (
                <HeldSaleRow
                  key={sale.id}
                  sale={sale}
                  onResume={() => requestResume(sale.id)}
                  onDiscard={() => void doDiscard(sale.id)}
                  resuming={resumingId === sale.id}
                  discarding={discardingId === sale.id}
                  busy={resumingId !== null || discardingId !== null}
                />
              ))}
            </div>
          )}
        </DialogContent>
      </Dialog>

      <AlertDialog open={confirmId !== null} onOpenChange={(next) => !next && setConfirmId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Replace the current cart?</AlertDialogTitle>
            <AlertDialogDescription>
              The active cart has items in it. Resuming this held sale replaces everything currently
              in the cart — hold the current sale first if you don&apos;t want to lose it.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={resumingId !== null}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={resumingId !== null}
              onClick={() => confirmId && void doResume(confirmId)}
            >
              {resumingId !== null ? "Resuming…" : "Replace cart"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

function HeldSaleRow({
  sale,
  onResume,
  onDiscard,
  resuming,
  discarding,
  busy,
}: {
  sale: HeldSale;
  onResume: () => void;
  onDiscard: () => void;
  resuming: boolean;
  discarding: boolean;
  busy: boolean;
}) {
  // Self-ticking, same "Synced Xs/Xm/Xh ago" pattern SyncStatus already
  // established, so "how long has this customer been waiting" stays honest
  // without a page refresh while the dialog sits open.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 15_000);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="flex items-center justify-between gap-3 rounded-xl border p-3">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <p className="truncate text-sm font-medium">{sale.customerName}</p>
          <Badge variant="secondary" className="shrink-0">
            {sale.lines.length} item{sale.lines.length === 1 ? "" : "s"}
          </Badge>
        </div>
        <p className="mt-0.5 flex items-center gap-1 text-xs text-muted-foreground">
          <Clock className="size-3" />
          Held {relativeHeld(sale.heldAt, now)} by {sale.heldBy}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-1.5">
        <Button
          size="sm"
          variant="ghost"
          className="text-muted-foreground hover:text-destructive"
          onClick={onDiscard}
          disabled={busy}
          aria-label={`Discard held sale for ${sale.customerName}`}
        >
          {discarding ? "…" : <Trash2 className="size-4" />}
        </Button>
        <Button size="sm" onClick={onResume} disabled={busy}>
          {resuming ? "Resuming…" : "Resume"}
        </Button>
      </div>
    </div>
  );
}
