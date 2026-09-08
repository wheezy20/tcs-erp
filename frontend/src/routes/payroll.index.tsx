import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Coins, Plus, Trash2 } from "lucide-react";
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
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import {
  createPayrollRun,
  deletePayrollRun,
  usePayroll,
  type PayrollRun,
} from "@/data/payroll-store";
import { MONTHS, periodLabel } from "@/data/payroll-format";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/payroll/")({
  component: PayrollRunsPage,
});

function PayrollRunsPage() {
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";
  const { runs, payslips, loading } = usePayroll();

  const byRun = useMemo(() => {
    const map = new Map<string, { count: number; net: number }>();
    for (const p of payslips) {
      const agg = map.get(p.payrollRunId) ?? { count: 0, net: 0 };
      agg.count += 1;
      agg.net += p.netPay;
      map.set(p.payrollRunId, agg);
    }
    return map;
  }, [payslips]);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          {runs.length} payroll run{runs.length === 1 ? "" : "s"}. A run is created as a draft; add
          a payslip per staff member, then it locks on posting.
        </p>
        {isManager && <CreateRunDialog existing={runs} />}
      </div>

      {runs.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Coins className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No payroll runs yet</p>
          {!isManager && (
            <p className="text-sm text-muted-foreground">Only a Manager can create a run.</p>
          )}
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Period</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 text-right font-medium">Payslips</th>
                  <th className="px-5 py-3 text-right font-medium">Net pay total</th>
                  <th className="px-5 py-3 font-medium">Created by</th>
                  {isManager && <th className="px-5 py-3 font-medium">&nbsp;</th>}
                </tr>
              </thead>
              <tbody className="divide-y">
                {runs.map((run) => {
                  const agg = byRun.get(run.id) ?? { count: 0, net: 0 };
                  return (
                    <tr key={run.id} className="hover:bg-muted/40">
                      <td className="px-5 py-3">
                        <Link
                          to="/payroll/$runId"
                          params={{ runId: run.id }}
                          className="font-medium hover:text-primary"
                        >
                          {periodLabel(run)}
                        </Link>
                      </td>
                      <td className="px-5 py-3">
                        <Badge variant={run.status === "Posted" ? "default" : "secondary"}>
                          {run.status}
                        </Badge>
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums">{agg.count}</td>
                      <td className="px-5 py-3 text-right tabular-nums">{currency(agg.net)}</td>
                      <td className="px-5 py-3 text-muted-foreground">
                        {run.createdByName ?? "—"}
                      </td>
                      {isManager && (
                        <td className="px-5 py-3 text-right">
                          {run.status === "Draft" && (
                            <DeleteRunButton run={run} payslipCount={agg.count} />
                          )}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function CreateRunDialog({ existing }: { existing: PayrollRun[] }) {
  const now = new Date();
  const [open, setOpen] = useState(false);
  const [month, setMonth] = useState(String(now.getMonth() + 1));
  const [year, setYear] = useState(String(now.getFullYear()));
  const [submitting, setSubmitting] = useState(false);

  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 3 + i);

  const clash = existing.some((r) => r.month === Number(month) && r.year === Number(year));

  async function submit() {
    setSubmitting(true);
    try {
      await createPayrollRun(Number(month), Number(year));
      toast.success(`Payroll run for ${MONTHS[Number(month) - 1]} ${year} created`);
      setOpen(false);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not create the payroll run."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="gap-2">
          <Plus className="size-4" /> Create run
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>New payroll run</DialogTitle>
          <DialogDescription>One run per month. It starts as a draft.</DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label>Month</Label>
            <Select value={month} onValueChange={setMonth}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {MONTHS.map((m, i) => (
                  <SelectItem key={m} value={String(i + 1)}>
                    {m}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Year</Label>
            <Select value={year} onValueChange={setYear}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {years.map((y) => (
                  <SelectItem key={y} value={String(y)}>
                    {y}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
        {clash && (
          <p className="text-sm text-destructive">
            A run for {MONTHS[Number(month) - 1]} {year} already exists.
          </p>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting || clash}>
            {submitting ? "Creating…" : "Create run"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function DeleteRunButton({ run, payslipCount }: { run: PayrollRun; payslipCount: number }) {
  const [busy, setBusy] = useState(false);
  async function onDelete() {
    if (
      !window.confirm(
        `Delete the draft payroll run for ${periodLabel(run)}?${
          payslipCount > 0 ? ` Its ${payslipCount} payslip(s) will be removed too.` : ""
        }`,
      )
    ) {
      return;
    }
    setBusy(true);
    try {
      await deletePayrollRun(run.id);
      toast.success("Draft run deleted");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not delete the run."));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Button
      variant="ghost"
      size="sm"
      className="gap-1 text-destructive"
      disabled={busy}
      onClick={onDelete}
    >
      <Trash2 className="size-3.5" /> Delete
    </Button>
  );
}
