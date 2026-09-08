import { AlertTriangle, CheckCircle2 } from "lucide-react";

import { currency } from "@/data/dashboard";
import type { DayClose } from "@/data/end-of-day-store";
import { cn } from "@/lib/utils";

/** The full figures for one closed (or currently open) day — shared between
 * the Today tab's "already closed" state and the History tab's detail view,
 * so both read exactly the same breakdown rather than two copies drifting. */
export function DayCloseFigures({ row }: { row: DayClose }) {
  const cashOk = Math.abs(row.cashVariance ?? 0) < 0.01;
  const tallyOk =
    Math.abs(row.tallySalesVariance ?? 0) < 0.01 && (row.tallyCountVariance ?? 0) === 0;

  return (
    <div className="grid gap-4 sm:grid-cols-2">
      <div className="card-surface space-y-2 p-5">
        <h3 className="text-sm font-semibold">Sales by payment method</h3>
        <Row label="Cash — POS" value={currency(row.posCashSales ?? 0)} />
        <Row label="Cash — invoices" value={currency(row.invoiceCashSales ?? 0)} />
        <Row label="Cash — total" value={currency(row.cashSales ?? 0)} strong />
        <Row label="Mobile Money (POS + invoices)" value={currency(row.mobileMoneySales ?? 0)} />
        <Row label="Card" value={currency(row.cardSales ?? 0)} />
        <Row label="Bank transfer (POS + invoices)" value={currency(row.bankTransferSales ?? 0)} />
        <Row label="Cheque — invoices" value={currency(row.invoiceChequeSales ?? 0)} />
        <Row label="VAT collected" value={currency(row.vatCollected ?? 0)} />
        <Row label="Discounts given" value={currency(row.discountsGiven ?? 0)} />
      </div>
      <div className="card-surface space-y-2 p-5">
        <h3 className="text-sm font-semibold">Cash reconciliation</h3>
        <Row label="Opening float" value={currency(row.openingFloat)} />
        <Row label="Cash refunds" value={`-${currency(row.cashRefunds ?? 0)}`} />
        <Row label="Cash expenses" value={`-${currency(row.cashExpenses ?? 0)}`} />
        <Row label="Cash deposits (banked)" value={`-${currency(row.cashDeposits ?? 0)}`} />
        <Row label="Expected cash" value={currency(row.expectedCash ?? 0)} strong />
        <Row label="Counted cash" value={currency(row.countedCash ?? 0)} strong />
        <div className="flex items-center justify-between pt-1 text-sm">
          <span className="flex items-center gap-1.5 font-medium">
            {cashOk ? (
              <CheckCircle2 className="size-3.5 text-primary" />
            ) : (
              <AlertTriangle className="size-3.5 text-amber-600 dark:text-amber-400" />
            )}
            Cash variance
          </span>
          <span
            className={cn(
              "font-semibold tabular-nums",
              cashOk ? "text-primary" : "text-amber-600 dark:text-amber-400",
            )}
          >
            {(row.cashVariance ?? 0) > 0 ? "+" : ""}
            {currency(row.cashVariance ?? 0)}
          </span>
        </div>
      </div>
      <div className="card-surface space-y-2 p-5 sm:col-span-2">
        <h3 className="text-sm font-semibold">Manual tally cross-check</h3>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <Row label="System sales total" value={currency(row.systemSalesTotal ?? 0)} />
            <Row label="Manual sales total" value={currency(row.manualSalesTotal ?? 0)} />
          </div>
          <div>
            <Row label="System transactions" value={String(row.systemTransactionCount ?? 0)} />
            <Row label="Manual transactions" value={String(row.manualTransactionCount ?? 0)} />
          </div>
        </div>
        <div className="flex items-center justify-between pt-1 text-sm">
          <span className="flex items-center gap-1.5 font-medium">
            {tallyOk ? (
              <CheckCircle2 className="size-3.5 text-primary" />
            ) : (
              <AlertTriangle className="size-3.5 text-amber-600 dark:text-amber-400" />
            )}
            Tally variance
          </span>
          <span
            className={cn(
              "font-semibold tabular-nums",
              tallyOk ? "text-primary" : "text-amber-600 dark:text-amber-400",
            )}
          >
            {(row.tallySalesVariance ?? 0) > 0 ? "+" : ""}
            {currency(row.tallySalesVariance ?? 0)} · {(row.tallyCountVariance ?? 0) > 0 ? "+" : ""}
            {row.tallyCountVariance ?? 0} txns
          </span>
        </div>
        {row.notes && (
          <p className="border-t pt-2 text-sm text-muted-foreground">Note: {row.notes}</p>
        )}
      </div>
    </div>
  );
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className={cn("tabular-nums", strong ? "font-semibold" : "font-medium")}>{value}</span>
    </div>
  );
}
