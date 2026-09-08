import { useEffect, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { CheckCircle2, Loader2, Lock, Printer, RefreshCw } from "lucide-react";
import { toast } from "sonner";

import { DayCloseFigures } from "@/components/end-of-day/day-close-figures";
import { PrintableDayClose } from "@/components/end-of-day/printable-day-close";
import { PrintDocument } from "@/components/print/print-document";
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
import { Textarea } from "@/components/ui/textarea";
import { useAuth } from "@/data/auth-store";
import { useCurrentBranch } from "@/data/branch-store";
import { currency } from "@/data/dashboard";
import {
  closeDay,
  fetchDayTotals,
  openDay,
  useEndOfDay,
  type DayTotals,
} from "@/data/end-of-day-store";
import { useDocumentSettings } from "@/data/settings-store";
import { cn, getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/end-of-day/")({
  component: TodayPage,
});

const today = () => new Date().toISOString().slice(0, 10);

function TodayPage() {
  const { closes, deposits, loading } = useEndOfDay();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const settings = useDocumentSettings();
  const { name: branchName } = useCurrentBranch();

  const todayRow = closes.find((c) => c.businessDate === today());
  const isOpen = !!todayRow;
  const isClosed = !!todayRow?.closedAt;

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  if (isClosed) {
    return <ClosedTodaySummary settings={settings} branchName={branchName} row={todayRow!} />;
  }

  if (!isOpen) {
    return (
      <OpenDayPanel
        isManager={isManager}
        closes={closes}
        deposits={deposits}
        currentStaffName={currentStaff?.name ?? ""}
      />
    );
  }

  return <LiveDayPreview openingFloat={todayRow!.openingFloat} isManager={isManager} />;
}

// ============================================================ Not yet open

function OpenDayPanel({
  isManager,
  closes,
  deposits,
  currentStaffName,
}: {
  isManager: boolean;
  closes: ReturnType<typeof useEndOfDay>["closes"];
  deposits: ReturnType<typeof useEndOfDay>["deposits"];
  currentStaffName: string;
}) {
  const [float, setFloat] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const previousClose = closes.find((c) => c.closedAt && c.businessDate < today());
  const depositsSince = previousClose
    ? deposits.filter((d) => d.date > previousClose.businessDate && d.date <= today())
    : [];
  const depositsSinceTotal = depositsSince.reduce((sum, d) => sum + d.amount, 0);

  async function confirm() {
    const value = Number(float);
    if (!Number.isFinite(value) || value < 0) {
      toast.error("Enter a valid, non-negative opening float.");
      return;
    }
    setSubmitting(true);
    try {
      await openDay(value);
      toast.success("Opening float confirmed for today.");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not confirm opening float."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto mt-6 max-w-xl">
      <div className="card-surface p-6 text-center">
        <Lock className="mx-auto size-8 text-muted-foreground" />
        <h2 className="mt-3 text-lg font-semibold">Today hasn't been opened yet</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          {isManager
            ? "Confirm the real opening float in the till before today's figures can be tracked."
            : `Only a Manager can confirm the opening float. Ask ${currentStaffName ? "a Manager" : "one"} to open today.`}
        </p>

        {(previousClose || depositsSinceTotal > 0) && (
          <div className="mt-5 space-y-2 rounded-xl border border-dashed p-4 text-left text-sm">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Reference — not auto-filled
            </p>
            {previousClose && (
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">
                  {previousClose.businessDate} closing count
                </span>
                <span className="font-medium tabular-nums">
                  {currency(previousClose.countedCash ?? 0)}
                </span>
              </div>
            )}
            {depositsSinceTotal > 0 && (
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">
                  Deposited since ({depositsSince.length})
                </span>
                <span className="font-medium tabular-nums">-{currency(depositsSinceTotal)}</span>
              </div>
            )}
          </div>
        )}

        {isManager && (
          <div className="mt-5 space-y-3">
            <div className="text-left">
              <Label htmlFor="opening-float">Opening float (cash in the till right now)</Label>
              <Input
                id="opening-float"
                inputMode="decimal"
                value={float}
                onChange={(e) => setFloat(e.target.value)}
                placeholder="0.00"
                className="mt-1.5"
                autoFocus
              />
            </div>
            <Button className="w-full" onClick={confirm} disabled={submitting || !float}>
              {submitting ? "Confirming…" : "Confirm opening float"}
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}

// ================================================================ Open, live

function LiveDayPreview({ openingFloat, isManager }: { openingFloat: number; isManager: boolean }) {
  const { branchId } = useEndOfDay();
  const [totals, setTotals] = useState<DayTotals | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [closeOpen, setCloseOpen] = useState(false);

  async function refresh() {
    if (!branchId) return;
    setRefreshing(true);
    try {
      setTotals(await fetchDayTotals(branchId, today()));
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not load today's figures."));
    } finally {
      setRefreshing(false);
    }
  }

  useEffect(() => {
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [branchId]);

  const expectedCash = totals
    ? openingFloat +
      totals.cashSales -
      totals.cashRefunds -
      totals.cashExpenses -
      totals.cashDeposits
    : null;

  return (
    <div className="mt-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Badge variant="secondary" className="gap-1.5">
            <CheckCircle2 className="size-3.5" /> Today is open
          </Badge>
          <span className="text-sm text-muted-foreground">
            Opening float {currency(openingFloat)}
          </span>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={refresh} disabled={refreshing}>
            <RefreshCw className={cn("size-3.5", refreshing && "animate-spin")} /> Refresh
          </Button>
          {isManager && (
            <Button size="sm" onClick={() => setCloseOpen(true)} disabled={!totals}>
              <Lock className="size-3.5" /> Close day
            </Button>
          )}
        </div>
      </div>

      {!totals ? (
        <div className="py-16 text-center text-sm text-muted-foreground">
          <Loader2 className="mx-auto mb-2 size-5 animate-spin" /> Loading today's figures…
        </div>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard label="POS cash sales" value={currency(totals.posCashSales)} />
            <StatCard label="Invoice cash sales" value={currency(totals.invoiceCashSales)} />
            <StatCard label="Cash sales (total)" value={currency(totals.cashSales)} />
            <StatCard
              label="Mobile Money sales"
              value={currency(totals.mobileMoneySales)}
              hint="POS + invoices"
            />
            <StatCard label="Card sales" value={currency(totals.cardSales)} />
            <StatCard
              label="Bank transfer sales"
              value={currency(totals.bankTransferSales)}
              hint="POS + invoices"
            />
            <StatCard label="Invoice cheque sales" value={currency(totals.invoiceChequeSales)} />
            <StatCard label="VAT collected" value={currency(totals.vatCollected)} />
            <StatCard label="Discounts given" value={currency(totals.discountsGiven)} />
            <StatCard label="Cash refunds" value={currency(totals.cashRefunds)} tone="warning" />
            <StatCard label="Cash expenses" value={currency(totals.cashExpenses)} tone="warning" />
            <StatCard
              label="Cash deposits"
              value={currency(totals.cashDeposits)}
              tone="warning"
              hint="Banked from the drawer"
            />
          </div>

          <div className="card-surface p-5">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Expected cash right now</p>
                <p className="mt-1 text-2xl font-semibold tabular-nums">
                  {currency(expectedCash ?? 0)}
                </p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Opening float + cash sales (POS + invoices) − cash refunds − cash expenses − cash
                  deposits
                </p>
              </div>
              <div className="text-right text-sm text-muted-foreground">
                <p>
                  {totals.systemTransactionCount} sale
                  {totals.systemTransactionCount === 1 ? "" : "s"} so far
                </p>
                <p>System total {currency(totals.systemSalesTotal)}</p>
              </div>
            </div>
          </div>
        </>
      )}

      {isManager && totals && branchId && (
        <CloseDayDialog
          open={closeOpen}
          onOpenChange={setCloseOpen}
          openingFloat={openingFloat}
          totals={totals}
        />
      )}
    </div>
  );
}

function StatCard({
  label,
  value,
  tone = "default",
  hint,
}: {
  label: string;
  value: string;
  tone?: "default" | "warning";
  hint?: string;
}) {
  return (
    <div className="card-surface p-4">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p
        className={cn(
          "mt-1.5 text-lg font-semibold tabular-nums",
          tone === "warning" && "text-amber-600 dark:text-amber-400",
        )}
      >
        {value}
      </p>
      {hint && <p className="mt-0.5 text-[11px] text-muted-foreground">{hint}</p>}
    </div>
  );
}

// ============================================================= Close dialog

function CloseDayDialog({
  open,
  onOpenChange,
  openingFloat,
  totals,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  openingFloat: number;
  totals: DayTotals;
}) {
  const [countedCash, setCountedCash] = useState("");
  const [manualSalesTotal, setManualSalesTotal] = useState("");
  const [manualTransactionCount, setManualTransactionCount] = useState("");
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const expectedCash =
    openingFloat +
    totals.cashSales -
    totals.cashRefunds -
    totals.cashExpenses -
    totals.cashDeposits;
  const countedNum = Number(countedCash);
  const manualSalesNum = Number(manualSalesTotal);
  const manualCountNum = Number(manualTransactionCount);
  const cashVariance = countedCash ? countedNum - expectedCash : null;
  const tallySalesVariance = manualSalesTotal ? manualSalesNum - totals.systemSalesTotal : null;
  const tallyCountVariance = manualTransactionCount
    ? manualCountNum - totals.systemTransactionCount
    : null;

  function reset() {
    setCountedCash("");
    setManualSalesTotal("");
    setManualTransactionCount("");
    setNotes("");
  }

  async function submit() {
    if (!Number.isFinite(countedNum) || countedNum < 0) {
      toast.error("Enter a valid counted cash amount.");
      return;
    }
    if (!Number.isFinite(manualSalesNum) || manualSalesNum < 0) {
      toast.error("Enter a valid manual sales total.");
      return;
    }
    if (!Number.isInteger(manualCountNum) || manualCountNum < 0) {
      toast.error("Enter a valid manual transaction count.");
      return;
    }
    setSubmitting(true);
    try {
      await closeDay({
        countedCash: countedNum,
        manualSalesTotal: manualSalesNum,
        manualTransactionCount: manualCountNum,
        notes,
      });
      toast.success("Today is closed and locked.");
      reset();
      onOpenChange(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not close the day."));
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
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Close today</DialogTitle>
          <DialogDescription>
            This locks today's figures permanently. It can't be reopened or edited afterward.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="rounded-xl border bg-muted/30 p-3 text-sm">
            {totals.cashDeposits > 0 && (
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Cash deposits (banked from drawer)</span>
                <span className="font-medium tabular-nums">-{currency(totals.cashDeposits)}</span>
              </div>
            )}
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Expected cash</span>
              <span className="font-medium tabular-nums">{currency(expectedCash)}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">System sales total</span>
              <span className="font-medium tabular-nums">{currency(totals.systemSalesTotal)}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">System transaction count</span>
              <span className="font-medium tabular-nums">{totals.systemTransactionCount}</span>
            </div>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="counted-cash">Counted cash</Label>
            <Input
              id="counted-cash"
              inputMode="decimal"
              value={countedCash}
              onChange={(e) => setCountedCash(e.target.value)}
              placeholder="0.00"
            />
            {cashVariance !== null && <VarianceLine label="Cash variance" value={cashVariance} />}
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="manual-sales-total">Manual sales total (written log)</Label>
              <Input
                id="manual-sales-total"
                inputMode="decimal"
                value={manualSalesTotal}
                onChange={(e) => setManualSalesTotal(e.target.value)}
                placeholder="0.00"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="manual-count">Manual transaction count</Label>
              <Input
                id="manual-count"
                inputMode="numeric"
                value={manualTransactionCount}
                onChange={(e) => setManualTransactionCount(e.target.value)}
                placeholder="0"
              />
            </div>
          </div>
          {(tallySalesVariance !== null || tallyCountVariance !== null) && (
            <div className="space-y-1">
              {tallySalesVariance !== null && (
                <VarianceLine label="Tally sales variance" value={tallySalesVariance} />
              )}
              {tallyCountVariance !== null && (
                <VarianceLine label="Tally count variance" value={tallyCountVariance} isCount />
              )}
            </div>
          )}

          <div className="space-y-1.5">
            <Label htmlFor="close-notes">Note (optional)</Label>
            <Textarea
              id="close-notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="e.g. till was GHS10 short, cashier confirmed a rounding error"
              rows={2}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Closing…" : "Close and lock today"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function VarianceLine({
  label,
  value,
  isCount = false,
}: {
  label: string;
  value: number;
  isCount?: boolean;
}) {
  const balanced = Math.abs(value) < (isCount ? 1 : 0.01);
  return (
    <div className="flex items-center justify-between text-xs">
      <span className="text-muted-foreground">{label}</span>
      <span
        className={cn(
          "font-medium tabular-nums",
          balanced ? "text-primary" : "text-amber-600 dark:text-amber-400",
        )}
      >
        {value > 0 ? "+" : ""}
        {isCount ? value : currency(value)}
      </span>
    </div>
  );
}

// ================================================================== Closed

function ClosedTodaySummary({
  settings,
  branchName,
  row,
}: {
  settings: ReturnType<typeof useDocumentSettings>;
  branchName: string | null;
  row: ReturnType<typeof useEndOfDay>["closes"][number];
}) {
  const [printing, setPrinting] = useState(false);

  return (
    <div className="mx-auto mt-6 max-w-2xl space-y-4">
      <div className="card-surface p-6 text-center">
        <CheckCircle2 className="mx-auto size-8 text-primary" />
        <h2 className="mt-3 text-lg font-semibold">Today is closed</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Locked by {row.closedBy} at{" "}
          {new Date(row.closedAt!).toLocaleTimeString("en-GB", {
            hour: "2-digit",
            minute: "2-digit",
          })}
          . Figures can't be changed.
        </p>
        <Button className="mt-4" variant="outline" onClick={() => setPrinting(true)}>
          <Printer className="size-4" /> Print summary
        </Button>
      </div>

      <DayCloseFigures row={row} />

      {printing && (
        <PrintDocument pageSize="A4" margin="14mm">
          <PrintableDayClose row={row} settings={settings} branchName={branchName ?? ""} />
        </PrintDocument>
      )}
      {printing && <PrintTrigger onDone={() => setPrinting(false)} />}
    </div>
  );
}

function PrintTrigger({ onDone }: { onDone: () => void }) {
  useEffect(() => {
    const id = setTimeout(() => {
      window.print();
      onDone();
    }, 50);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return null;
}
