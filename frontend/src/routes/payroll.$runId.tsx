import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, FileText, Plus, Trash2 } from "lucide-react";
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
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
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
import { useStaff } from "@/data/staff-store";
import {
  createPayslip,
  currentConfigFor,
  deletePayslip,
  standingAllowancesFor,
  usePayroll,
  type Payslip,
} from "@/data/payroll-store";
import { periodLabel } from "@/data/payroll-format";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/payroll/$runId")({
  component: RunDetailPage,
});

function RunDetailPage() {
  const { runId } = Route.useParams();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const { runs, payslips, payConfigs, allowanceTypes, staffAllowances, loading } = usePayroll();
  const { staff: roster } = useStaff();
  const [generateFor, setGenerateFor] = useState<string | null>(null);

  const run = runs.find((r) => r.id === runId);
  const runPayslips = useMemo(
    () => payslips.filter((p) => p.payrollRunId === runId),
    [payslips, runId],
  );

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  if (!run) {
    return (
      <div className="card-surface mt-4 p-10 text-center">
        <p className="text-sm font-medium">This payroll run no longer exists</p>
        <Link to="/payroll" className="mt-3 inline-block text-sm text-primary hover:underline">
          Back to payroll runs
        </Link>
      </div>
    );
  }

  const paidStaffIds = new Set(runPayslips.map((p) => p.staffId));
  const activeRoster = roster.filter((s) => s.active);
  const withConfig = activeRoster.filter((s) => currentConfigFor(payConfigs, s.id));
  const notYetPaid = withConfig.filter((s) => !paidStaffIds.has(s.id));
  const missingConfig = activeRoster.filter((s) => !currentConfigFor(payConfigs, s.id));

  const totals = runPayslips.reduce(
    (acc, p) => ({
      gross: acc.gross + p.grossSalary,
      deductions: acc.deductions + p.totalDeductions,
      net: acc.net + p.netPay,
    }),
    { gross: 0, deductions: 0, net: 0 },
  );

  const canGenerate = isManager && run.status === "Draft";

  return (
    <div className="mt-4 space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link
            to="/payroll"
            className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
          >
            <ArrowLeft className="size-4" /> All runs
          </Link>
          <div className="mt-1 flex items-center gap-3">
            <h2 className="text-xl font-semibold tracking-tight">{periodLabel(run)}</h2>
            <Badge variant={run.status === "Posted" ? "default" : "secondary"}>{run.status}</Badge>
          </div>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <SummaryCard label="Gross pay" value={currency(totals.gross)} />
        <SummaryCard label="Total deductions" value={currency(totals.deductions)} />
        <SummaryCard label="Net pay" value={currency(totals.net)} strong />
      </div>

      {/* TODO (accounting follow-up): a "Post to Accounting" action goes
          here — it should call a post_payroll_run() RPC that creates the
          payroll journal entry (salary expense / statutory liabilities /
          net pay payable) and flips status to Posted. Not built yet;
          Draft/Posted currently only gates payslip edits. */}

      {run.status === "Draft" && canGenerate && notYetPaid.length > 0 && (
        <div className="card-surface p-4">
          <p className="mb-2 text-sm font-medium">Generate a payslip</p>
          <div className="flex flex-wrap gap-2">
            {notYetPaid.map((s) => (
              <Button
                key={s.id}
                variant="outline"
                size="sm"
                className="gap-1.5"
                onClick={() => setGenerateFor(s.id)}
              >
                <Plus className="size-3.5" /> {s.name}
              </Button>
            ))}
          </div>
        </div>
      )}

      {missingConfig.length > 0 && (
        <p className="text-xs text-muted-foreground">
          No pay config yet for: {missingConfig.map((s) => s.name).join(", ")}. Set one under{" "}
          <Link to="/payroll/pay-config" className="text-primary hover:underline">
            Staff Pay Config
          </Link>
          .
        </p>
      )}

      {runPayslips.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <FileText className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No payslips generated for this run yet</p>
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Staff</th>
                  <th className="px-5 py-3 text-right font-medium">Basic</th>
                  <th className="px-5 py-3 text-right font-medium">Allowances</th>
                  <th className="px-5 py-3 text-right font-medium">Overtime</th>
                  <th className="px-5 py-3 text-right font-medium">Gross</th>
                  <th className="px-5 py-3 text-right font-medium">Deductions</th>
                  <th className="px-5 py-3 text-right font-medium">Net pay</th>
                  <th className="px-5 py-3 font-medium">&nbsp;</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {runPayslips.map((p) => (
                  <tr key={p.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3 font-medium">{p.staffName}</td>
                    <td className="px-5 py-3 text-right tabular-nums">{currency(p.basicSalary)}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(p.totalAllowances)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">{currency(p.overtimePay)}</td>
                    <td className="px-5 py-3 text-right tabular-nums">{currency(p.grossSalary)}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(p.totalDeductions)}
                    </td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(p.netPay)}
                    </td>
                    <td className="px-5 py-3 text-right">
                      <div className="flex justify-end gap-1">
                        <Button asChild variant="ghost" size="sm">
                          <Link to="/payslips/$payslipId" params={{ payslipId: p.id }}>
                            View
                          </Link>
                        </Button>
                        {isManager && run.status === "Draft" && <DeletePayslipButton payslip={p} />}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {generateFor && (
        <GeneratePayslipDialog
          runId={run.id}
          staffId={generateFor}
          staffName={roster.find((s) => s.id === generateFor)?.name ?? "Staff"}
          allowanceTypes={allowanceTypes}
          standing={standingAllowancesFor(staffAllowances, generateFor)}
          onClose={() => setGenerateFor(null)}
        />
      )}
    </div>
  );
}

function SummaryCard({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="card-surface p-4">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p
        className={strong ? "mt-1 text-lg font-semibold tabular-nums" : "mt-1 text-lg tabular-nums"}
      >
        {value}
      </p>
    </div>
  );
}

function DeletePayslipButton({ payslip }: { payslip: Payslip }) {
  const [busy, setBusy] = useState(false);
  async function onDelete() {
    if (!window.confirm(`Delete ${payslip.staffName}'s payslip? You can regenerate it.`)) return;
    setBusy(true);
    try {
      await deletePayslip(payslip.id);
      toast.success("Payslip deleted");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not delete the payslip."));
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
      <Trash2 className="size-3.5" />
    </Button>
  );
}

type AllowanceRow = { key: string; allowanceTypeId: string; amount: string };

function GeneratePayslipDialog({
  runId,
  staffId,
  staffName,
  allowanceTypes,
  standing,
  onClose,
}: {
  runId: string;
  staffId: string;
  staffName: string;
  allowanceTypes: { id: string; name: string }[];
  standing: { allowanceTypeId: string; defaultAmount: number }[];
  onClose: () => void;
}) {
  const [overtimeHours, setOvertimeHours] = useState("0");
  const [overtimeRate, setOvertimeRate] = useState("0");
  const [fines, setFines] = useState("0");
  const [iou, setIou] = useState("0");
  const [rows, setRows] = useState<AllowanceRow[]>(() =>
    standing.map((s, i) => ({
      key: `s${i}`,
      allowanceTypeId: s.allowanceTypeId,
      amount: String(s.defaultAmount),
    })),
  );
  const [submitting, setSubmitting] = useState(false);

  const usedTypeIds = new Set(rows.map((r) => r.allowanceTypeId));
  const addableTypes = allowanceTypes.filter((t) => !usedTypeIds.has(t.id));

  function updateRow(key: string, patch: Partial<AllowanceRow>) {
    setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  }

  async function submit() {
    const allowances = rows
      .filter((r) => r.allowanceTypeId)
      .map((r) => ({ allowanceTypeId: r.allowanceTypeId, amount: Number(r.amount) || 0 }));
    setSubmitting(true);
    try {
      await createPayslip({
        payrollRunId: runId,
        staffId,
        overtimeHours: Number(overtimeHours) || 0,
        overtimeRate: Number(overtimeRate) || 0,
        allowances,
        fines: Number(fines) || 0,
        iou: Number(iou) || 0,
      });
      toast.success(`Payslip generated for ${staffName}`);
      onClose();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not generate the payslip."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Generate payslip — {staffName}</DialogTitle>
          <DialogDescription>
            Basic salary, SSNIT, Tier 2 and PAYE are computed server-side from this staff member's
            pay config. Adjust the month-specific figures below.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Overtime hours</Label>
              <Input
                type="number"
                min="0"
                step="0.5"
                value={overtimeHours}
                onChange={(e) => setOvertimeHours(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Overtime rate (per hour)</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={overtimeRate}
                onChange={(e) => setOvertimeRate(e.target.value)}
              />
            </div>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label>Allowances</Label>
              {addableTypes.length > 0 && (
                <Select
                  value=""
                  onValueChange={(v) =>
                    setRows((rs) => [
                      ...rs,
                      { key: `n${Date.now()}`, allowanceTypeId: v, amount: "0" },
                    ])
                  }
                >
                  <SelectTrigger className="h-8 w-40 text-xs">
                    <SelectValue placeholder="Add allowance" />
                  </SelectTrigger>
                  <SelectContent>
                    {addableTypes.map((t) => (
                      <SelectItem key={t.id} value={t.id}>
                        {t.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            {rows.length === 0 && (
              <p className="text-xs text-muted-foreground">No allowances for this payslip.</p>
            )}
            {rows.map((row) => {
              const type = allowanceTypes.find((t) => t.id === row.allowanceTypeId);
              return (
                <div key={row.key} className="flex items-center gap-2">
                  <span className="flex-1 text-sm">{type?.name ?? "—"}</span>
                  <Input
                    type="number"
                    min="0"
                    step="0.01"
                    className="w-32"
                    value={row.amount}
                    onChange={(e) => updateRow(row.key, { amount: e.target.value })}
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setRows((rs) => rs.filter((r) => r.key !== row.key))}
                  >
                    <Trash2 className="size-3.5" />
                  </Button>
                </div>
              );
            })}
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Fines</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={fines}
                onChange={(e) => setFines(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>IOU / advance recovery</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={iou}
                onChange={(e) => setIou(e.target.value)}
              />
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Generating…" : "Generate payslip"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
