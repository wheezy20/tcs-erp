import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, BookOpen, CheckCircle2, FileText, Plus, Trash2 } from "lucide-react";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { useStaff } from "@/data/staff-store";
import {
  createPayslip,
  currentConfigFor,
  deletePayslip,
  postPayrollRun,
  standingAllowancesFor,
  usePayroll,
  type Payslip,
} from "@/data/payroll-store";
import { useJournalEntries, type JournalEntry } from "@/data/journal-store";
import { periodLabel } from "@/data/payroll-format";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/payroll/$runId")({
  component: RunDetailPage,
});

function RunDetailPage() {
  const { runId } = Route.useParams();
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const { runs, payslips, payConfigs, allowanceTypes, staffAllowances, loading } = usePayroll();
  const { staff: roster } = useStaff();
  const { entries: journalEntries } = useJournalEntries();
  const [generateFor, setGenerateFor] = useState<string | null>(null);
  const [posting, setPosting] = useState(false);

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

  const canGenerate = canWrite && run.status === "Draft";
  const runEntry = journalEntries.find(
    (e) => e.sourceTable === "payroll_runs" && e.sourceId === run.id,
  );
  // "Complete" = every active staff member who has a pay config already has
  // a payslip on this run. Staff with no config can't be paid at all, so
  // they don't block the post — they're surfaced as a warning instead.
  const readyToPost =
    canWrite && run.status === "Draft" && runPayslips.length > 0 && notYetPaid.length === 0;

  async function onPost(): Promise<boolean> {
    setPosting(true);
    try {
      await postPayrollRun(run!.id);
      toast.success("Payroll run posted to Accounting");
      return true;
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not post the payroll run."));
      return false;
    } finally {
      setPosting(false);
    }
  }

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

      {run.status === "Posted" ? (
        <PostedEntryCard entry={runEntry} />
      ) : runPayslips.length > 0 && canWrite ? (
        <div className="card-surface p-4">
          {readyToPost ? (
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="text-sm font-medium">Ready to post to Accounting</p>
                <p className="text-xs text-muted-foreground">
                  {runPayslips.length} payslip{runPayslips.length === 1 ? "" : "s"} · net{" "}
                  {currency(totals.net)}. Posting creates one journal entry and locks the run.
                </p>
                {missingConfig.length > 0 && (
                  <p className="mt-1 text-xs text-amber-600 dark:text-amber-500">
                    {missingConfig.length} active staff member
                    {missingConfig.length === 1 ? " has" : "s have"} no pay config and will be
                    excluded: {missingConfig.map((s) => s.name).join(", ")}.
                  </p>
                )}
              </div>
              <PostRunDialog
                periodLabel={periodLabel(run)}
                payslips={runPayslips}
                missingCount={missingConfig.length}
                posting={posting}
                onConfirm={onPost}
              />
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              Generate the remaining {notYetPaid.length} payslip
              {notYetPaid.length === 1 ? "" : "s"} before posting this run to Accounting.
            </p>
          )}
        </div>
      ) : null}

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
                        {canWrite && run.status === "Draft" && <DeletePayslipButton payslip={p} />}
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

const POSTING_NOTE =
  "Employer SSNIT (13%) is not included — it isn't calculated on payslips yet (see the go-live checklist in docs/CONSTRAINTS.md), so this entry understates true staffing cost by that amount.";

function EntryLinesTable({
  lines,
}: {
  lines: { key: string; code: string; name: string; debit: number; credit: number }[];
}) {
  const totalDebit = lines.reduce((s, l) => s + l.debit, 0);
  const totalCredit = lines.reduce((s, l) => s + l.credit, 0);
  return (
    <div className="overflow-x-auto rounded-lg border text-sm">
      <table className="w-full">
        <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
          <tr>
            <th className="px-3 py-2 font-medium">Account</th>
            <th className="px-3 py-2 text-right font-medium">Debit</th>
            <th className="px-3 py-2 text-right font-medium">Credit</th>
          </tr>
        </thead>
        <tbody className="divide-y">
          {lines.map((l) => (
            <tr key={l.key}>
              <td className="px-3 py-2">
                <span className="font-mono text-xs text-muted-foreground">{l.code}</span> {l.name}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">
                {l.debit ? currency(l.debit) : "—"}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">
                {l.credit ? currency(l.credit) : "—"}
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot className="border-t bg-muted/40 font-medium">
          <tr>
            <td className="px-3 py-2">Total</td>
            <td className="px-3 py-2 text-right tabular-nums">{currency(totalDebit)}</td>
            <td className="px-3 py-2 text-right tabular-nums">{currency(totalCredit)}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}

function PostedEntryCard({ entry }: { entry: JournalEntry | undefined }) {
  if (!entry) {
    return (
      <div className="card-surface flex items-center gap-2 p-4 text-sm text-muted-foreground">
        <CheckCircle2 className="size-4 text-primary" />
        Posted to Accounting — loading the journal entry…
      </div>
    );
  }
  return (
    <div className="card-surface space-y-3 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="flex items-center gap-2 text-sm font-medium">
          <CheckCircle2 className="size-4 text-primary" />
          Posted to Accounting · <span className="font-mono">{entry.id}</span>
        </p>
        <Button asChild variant="ghost" size="sm" className="gap-1.5">
          <Link to="/accounting/journal-entries">
            <BookOpen className="size-3.5" /> Open in ledger
          </Link>
        </Button>
      </div>
      <p className="text-xs text-muted-foreground">
        {entry.description} · {entry.entryDate}
      </p>
      <EntryLinesTable
        lines={entry.lines.map((l) => ({
          key: l.id,
          code: l.accountCode,
          name: l.accountName,
          debit: l.debit,
          credit: l.credit,
        }))}
      />
      <p className="text-xs text-muted-foreground">{POSTING_NOTE}</p>
    </div>
  );
}

function PostRunDialog({
  periodLabel: period,
  payslips,
  missingCount,
  posting,
  onConfirm,
}: {
  periodLabel: string;
  payslips: Payslip[];
  missingCount: number;
  posting: boolean;
  onConfirm: () => Promise<boolean>;
}) {
  const [open, setOpen] = useState(false);
  const sums = payslips.reduce(
    (a, p) => ({
      gross: a.gross + p.grossSalary,
      ssnit: a.ssnit + p.ssnit,
      tier2: a.tier2 + p.tier2,
      paye: a.paye + p.tax,
      fines: a.fines + p.fines,
      iou: a.iou + p.iou,
      net: a.net + p.netPay,
    }),
    { gross: 0, ssnit: 0, tier2: 0, paye: 0, fines: 0, iou: 0, net: 0 },
  );
  const lines = [
    { key: "5140", code: "5140", name: "Salaries & Wages Expense", debit: sums.gross, credit: 0 },
    { key: "2300", code: "2300", name: "Salaries & Wages Payable", debit: 0, credit: sums.net },
    { key: "2310", code: "2310", name: "SSNIT Payable", debit: 0, credit: sums.ssnit },
    {
      key: "2320",
      code: "2320",
      name: "Provident Fund (Tier 2) Payable",
      debit: 0,
      credit: sums.tier2,
    },
    { key: "2330", code: "2330", name: "PAYE Payable", debit: 0, credit: sums.paye },
    { key: "1350", code: "1350", name: "Advances to Staff", debit: 0, credit: sums.iou },
    { key: "4910", code: "4910", name: "Staff Fines Recovered", debit: 0, credit: sums.fines },
  ].filter((l) => l.debit > 0 || l.credit > 0);

  return (
    <Dialog open={open} onOpenChange={(next) => !posting && setOpen(next)}>
      <DialogTrigger asChild>
        <Button className="gap-2">
          <BookOpen className="size-4" /> Post to Accounting
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Post {period} payroll to Accounting</DialogTitle>
          <DialogDescription>
            Creates one journal entry and locks the run — no payslip can be generated, edited or
            deleted against it afterward. A mistake after posting is corrected with a reversing
            entry.
          </DialogDescription>
        </DialogHeader>

        <EntryLinesTable lines={lines} />

        <p className="text-xs text-muted-foreground">{POSTING_NOTE}</p>
        {missingCount > 0 && (
          <p className="text-xs text-amber-600 dark:text-amber-500">
            {missingCount} active staff member{missingCount === 1 ? "" : "s"} with no pay config
            {missingCount === 1 ? " is" : " are"} excluded from this run.
          </p>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={posting}>
            Cancel
          </Button>
          <Button
            onClick={async () => {
              const ok = await onConfirm();
              if (ok) setOpen(false);
            }}
            disabled={posting}
          >
            {posting ? "Posting…" : "Post to Accounting"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
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
