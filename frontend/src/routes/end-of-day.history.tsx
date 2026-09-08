import { useEffect, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AlertTriangle, CheckCircle2, History, Printer } from "lucide-react";

import { DayCloseFigures } from "@/components/end-of-day/day-close-figures";
import { PrintableDayClose } from "@/components/end-of-day/printable-day-close";
import { PrintDocument } from "@/components/print/print-document";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useCurrentBranch } from "@/data/branch-store";
import { currency } from "@/data/dashboard";
import { type DayClose, useEndOfDay } from "@/data/end-of-day-store";
import { useDocumentSettings } from "@/data/settings-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/end-of-day/history")({
  component: HistoryPage,
});

function HistoryPage() {
  const { closes, loading } = useEndOfDay();
  const [viewing, setViewing] = useState<DayClose | null>(null);
  const closed = closes.filter((c) => c.closedAt);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  if (closed.length === 0) {
    return (
      <div className="mt-6 flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
        <History className="size-8 text-muted-foreground" />
        <p className="text-sm font-medium">No closed days yet</p>
        <p className="text-sm text-muted-foreground">
          Once a Manager closes a day on the Today tab, it shows up here as a locked record.
        </p>
      </div>
    );
  }

  return (
    <div className="card-surface mt-6 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="px-5 py-3 font-medium">Date</th>
              <th className="px-5 py-3 text-right font-medium">Opening float</th>
              <th className="px-5 py-3 text-right font-medium">Counted cash</th>
              <th className="px-5 py-3 text-right font-medium">Cash variance</th>
              <th className="px-5 py-3 text-right font-medium">Tally variance</th>
              <th className="px-5 py-3 font-medium">Closed by</th>
              <th className="px-5 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y">
            {closed.map((row) => {
              const cashOk = Math.abs(row.cashVariance ?? 0) < 0.01;
              const tallyOk =
                Math.abs(row.tallySalesVariance ?? 0) < 0.01 && (row.tallyCountVariance ?? 0) === 0;
              return (
                <tr key={row.id} className="hover:bg-muted/40">
                  <td className="px-5 py-3 font-medium">{row.businessDate}</td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    {currency(row.openingFloat)}
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    {currency(row.countedCash ?? 0)}
                  </td>
                  <td
                    className={cn(
                      "px-5 py-3 text-right tabular-nums font-medium",
                      cashOk ? "text-primary" : "text-amber-600 dark:text-amber-400",
                    )}
                  >
                    <span className="inline-flex items-center gap-1">
                      {cashOk ? (
                        <CheckCircle2 className="size-3.5" />
                      ) : (
                        <AlertTriangle className="size-3.5" />
                      )}
                      {(row.cashVariance ?? 0) > 0 ? "+" : ""}
                      {currency(row.cashVariance ?? 0)}
                    </span>
                  </td>
                  <td
                    className={cn(
                      "px-5 py-3 text-right tabular-nums font-medium",
                      tallyOk ? "text-primary" : "text-amber-600 dark:text-amber-400",
                    )}
                  >
                    {(row.tallySalesVariance ?? 0) > 0 ? "+" : ""}
                    {currency(row.tallySalesVariance ?? 0)}
                  </td>
                  <td className="px-5 py-3 text-muted-foreground">{row.closedBy}</td>
                  <td className="px-5 py-3 text-right">
                    <Button variant="ghost" size="sm" onClick={() => setViewing(row)}>
                      View
                    </Button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {viewing && <DayDetailDialog row={viewing} onClose={() => setViewing(null)} />}
    </div>
  );
}

function DayDetailDialog({ row, onClose }: { row: DayClose; onClose: () => void }) {
  const settings = useDocumentSettings();
  const { name: branchName } = useCurrentBranch();
  const [printing, setPrinting] = useState(false);

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center justify-between gap-4">
            <span>{row.businessDate}</span>
            <Button variant="outline" size="sm" onClick={() => setPrinting(true)}>
              <Printer className="size-3.5" /> Print
            </Button>
          </DialogTitle>
        </DialogHeader>
        <DayCloseFigures row={row} />
      </DialogContent>

      {printing && (
        <PrintDocument pageSize="A4" margin="14mm">
          <PrintableDayClose row={row} settings={settings} branchName={branchName ?? ""} />
        </PrintDocument>
      )}
      {printing && <PrintOnce onDone={() => setPrinting(false)} />}
    </Dialog>
  );
}

function PrintOnce({ onDone }: { onDone: () => void }) {
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
