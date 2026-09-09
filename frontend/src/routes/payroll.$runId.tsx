import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import {
  ArrowLeft,
  Ban,
  BookOpen,
  CheckCircle2,
  FileText,
  Mail,
  Plus,
  RotateCcw,
  Send,
  Trash2,
} from "lucide-react";
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
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { currentConfigFor, standingAllowancesFor, useEmployees } from "@/data/employees-store";
import {
  createPayslip,
  createPayslipsBulk,
  deletePayslip,
  excludeEmployeeFromRun,
  includeEmployeeInRun,
  postPayrollRun,
  rejectPayrollRun,
  submitPayrollRunForReview,
  usePayroll,
  type Payslip,
  type PayrollRunExclusion,
} from "@/data/payroll-store";
import { useJournalEntries, type JournalEntry } from "@/data/journal-store";
import { useStaff } from "@/data/staff-store";
import { periodLabel } from "@/data/payroll-format";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/payroll/$runId")({
  component: RunDetailPage,
});

const fmtDate = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString() : "—");

function RunDetailPage() {
  const { runId } = Route.useParams();
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const isManager = currentStaff?.role === "Manager";
  const { runs, payslips, exclusions, allowanceTypes, loading } = usePayroll();
  const { employees, configs, allowances } = useEmployees();
  const { entries: journalEntries } = useJournalEntries();
  const { staff: roster } = useStaff();
  const [generateFor, setGenerateFor] = useState<string | null>(null);
  const [excludeFor, setExcludeFor] = useState<string | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkBusy, setBulkBusy] = useState(false);
  const [busy, setBusy] = useState(false);

  const run = runs.find((r) => r.id === runId);
  const runPayslips = useMemo(
    () => payslips.filter((p) => p.payrollRunId === runId),
    [payslips, runId],
  );
  const runExclusions = useMemo(
    () => exclusions.filter((x) => x.payrollRunId === runId),
    [exclusions, runId],
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

  const staffName = (id: string | null) =>
    id ? (roster.find((s) => s.id === id)?.name ?? "someone") : "someone";

  const paidEmployeeIds = new Set(runPayslips.map((p) => p.employeeId));
  const excludedEmployeeIds = new Set(runExclusions.map((x) => x.employeeId));
  const activeRoster = employees.filter((e) => e.status === "Active");
  const withConfig = activeRoster.filter((e) => currentConfigFor(configs, e.id));
  const notAccountedFor = withConfig.filter(
    (e) => !paidEmployeeIds.has(e.id) && !excludedEmployeeIds.has(e.id),
  );
  const missingConfig = activeRoster.filter((e) => !currentConfigFor(configs, e.id));

  const totals = runPayslips.reduce(
    (acc, p) => ({
      gross: acc.gross + p.grossSalary,
      deductions: acc.deductions + p.totalDeductions,
      net: acc.net + p.netPay,
    }),
    { gross: 0, deductions: 0, net: 0 },
  );

  const isDraft = run.status === "Draft";
  const isReview = run.status === "Ready for Review";
  const isPosted = run.status === "Posted";
  const canGenerate = canWrite && isDraft;
  const isComplete = canWrite && runPayslips.length > 0 && notAccountedFor.length === 0;
  const runEntry = journalEntries.find(
    (e) => e.sourceTable === "payroll_runs" && e.sourceId === run.id,
  );

  async function withBusy(fn: () => Promise<void>, ok: string): Promise<boolean> {
    setBusy(true);
    try {
      await fn();
      toast.success(ok);
      return true;
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not complete that."));
      return false;
    } finally {
      setBusy(false);
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
            <Badge variant={isPosted ? "default" : isReview ? "outline" : "secondary"}>
              {run.status}
            </Badge>
          </div>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <SummaryCard label="Gross pay" value={currency(totals.gross)} />
        <SummaryCard label="Total deductions" value={currency(totals.deductions)} />
        <SummaryCard label="Net pay" value={currency(totals.net)} strong />
      </div>

      {isDraft && run.rejectionReason && (
        <div className="rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm">
          <span className="font-semibold text-destructive">Returned for revision</span> by{" "}
          {staffName(run.reviewedById)} on {fmtDate(run.reviewedAt)} — {run.rejectionReason}
        </div>
      )}

      {isPosted ? (
        <>
          <PostedEntryCard entry={runEntry} />
          <div className="flex justify-end">
            <EmailPayslipsButton />
          </div>
        </>
      ) : isReview ? (
        <ReviewPanel
          period={periodLabel(run)}
          isManager={isManager}
          submittedByName={staffName(run.submittedById)}
          submittedAt={run.submittedAt}
          payslips={runPayslips}
          missingCount={missingConfig.length}
          busy={busy}
          onApprove={() =>
            withBusy(() => postPayrollRun(run.id), "Payroll run approved and posted to Accounting")
          }
          onReject={(reason) =>
            withBusy(() => rejectPayrollRun(run.id, reason), "Run returned to Draft")
          }
        />
      ) : isDraft && canWrite ? (
        <div className="card-surface p-4">
          {isComplete ? (
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="text-sm font-medium">Ready to submit for review</p>
                <p className="text-xs text-muted-foreground">
                  {runPayslips.length} payslip{runPayslips.length === 1 ? "" : "s"}
                  {runExclusions.length > 0 ? ` · ${runExclusions.length} excluded` : ""} · net{" "}
                  {currency(totals.net)}. A Manager approves it, which posts the run.
                </p>
                {missingConfig.length > 0 && (
                  <p className="mt-1 text-xs text-amber-600 dark:text-amber-500">
                    {missingConfig.length} active employee
                    {missingConfig.length === 1 ? " has" : "s have"} no approved pay config and will
                    be excluded: {missingConfig.map((e) => e.name).join(", ")}.
                  </p>
                )}
              </div>
              <Button
                className="gap-2"
                disabled={busy}
                onClick={() =>
                  withBusy(() => submitPayrollRunForReview(run.id), "Submitted for Manager review")
                }
              >
                <Send className="size-4" /> Submit for review
              </Button>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              {runPayslips.length === 0
                ? "Generate at least one payslip before submitting this run for review."
                : `Generate or exclude the remaining ${notAccountedFor.length} employee${
                    notAccountedFor.length === 1 ? "" : "s"
                  } before submitting this run for review.`}
            </p>
          )}
        </div>
      ) : null}

      {isDraft && canGenerate && notAccountedFor.length > 0 && (
        <div className="card-surface p-4">
          {(() => {
            const ids = notAccountedFor.map((e) => e.id);
            const sel = ids.filter((id) => selected.has(id));
            const allChecked = sel.length === ids.length && ids.length > 0;
            const toggle = (id: string) =>
              setSelected((prev) => {
                const next = new Set(prev);
                if (next.has(id)) next.delete(id);
                else next.add(id);
                return next;
              });
            const toggleAll = () => setSelected(allChecked ? new Set() : new Set(ids));
            async function bulkGenerate() {
              setBulkBusy(true);
              try {
                const inputs = sel.map((id) => ({
                  payrollRunId: run!.id,
                  employeeId: id,
                  overtimeHours: 0,
                  overtimeRate: 0,
                  allowances: standingAllowancesFor(allowances, id).map((a) => ({
                    allowanceTypeId: a.allowanceTypeId,
                    amount: a.defaultAmount,
                  })),
                  fines: 0,
                  iou: 0,
                }));
                const { ok, failed } = await createPayslipsBulk(inputs);
                setSelected(new Set());
                if (failed.length === 0) {
                  toast.success(`Generated ${ok} payslip${ok === 1 ? "" : "s"}`);
                } else {
                  toast.error(`${ok} generated, ${failed.length} failed — ${failed[0].message}`);
                }
              } finally {
                setBulkBusy(false);
              }
            }
            return (
              <>
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                  <label className="flex items-center gap-2 text-sm font-medium">
                    <Checkbox checked={allChecked} onCheckedChange={toggleAll} />
                    Not yet on this run ({notAccountedFor.length})
                  </label>
                  <Button
                    size="sm"
                    className="gap-1.5"
                    disabled={sel.length === 0 || bulkBusy}
                    onClick={bulkGenerate}
                  >
                    <Plus className="size-3.5" />
                    {bulkBusy
                      ? "Generating…"
                      : `Generate ${sel.length || ""} payslip${sel.length === 1 ? "" : "s"}`.trim()}
                  </Button>
                </div>
                <p className="mb-2 text-xs text-muted-foreground">
                  Bulk generate uses each employee's standing config and allowances with no
                  overtime, fines or IOU. Use “Adjust” for month-specific figures.
                </p>
                <div className="flex flex-col divide-y">
                  {notAccountedFor.map((e) => (
                    <div
                      key={e.id}
                      className="flex flex-wrap items-center justify-between gap-2 py-2"
                    >
                      <label className="flex items-center gap-2 text-sm">
                        <Checkbox
                          checked={selected.has(e.id)}
                          onCheckedChange={() => toggle(e.id)}
                        />
                        {e.name}
                      </label>
                      <div className="flex gap-2">
                        <Button
                          variant="outline"
                          size="sm"
                          className="gap-1.5"
                          onClick={() => setGenerateFor(e.id)}
                        >
                          <Plus className="size-3.5" /> Adjust
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="gap-1.5 text-muted-foreground"
                          onClick={() => setExcludeFor(e.id)}
                        >
                          <Ban className="size-3.5" /> Exclude
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            );
          })()}
        </div>
      )}

      {runExclusions.length > 0 && (
        <div className="card-surface p-4">
          <p className="mb-2 text-sm font-medium">Excluded this cycle</p>
          <ul className="divide-y">
            {runExclusions.map((x) => (
              <li key={x.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <div className="text-sm">
                  <span className="font-medium">{x.employeeName}</span>
                  <span className="text-muted-foreground">
                    {x.reason ? ` · ${x.reason}` : " · no reason given"}
                  </span>
                </div>
                {canWrite && isDraft && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="gap-1.5"
                    disabled={busy}
                    onClick={() =>
                      withBusy(
                        () => includeEmployeeInRun(run.id, x.employeeId),
                        `${x.employeeName} back on this run`,
                      )
                    }
                  >
                    <RotateCcw className="size-3.5" /> Include
                  </Button>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      {missingConfig.length > 0 && (
        <p className="text-xs text-muted-foreground">
          No approved pay config yet for: {missingConfig.map((e) => e.name).join(", ")}. Set one
          from{" "}
          <Link to="/employees" className="text-primary hover:underline">
            Employees
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
                  <th className="px-5 py-3 font-medium">Employee</th>
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
                    <td className="px-5 py-3 font-medium">{p.employeeName}</td>
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
                        {canWrite && isDraft && <DeletePayslipButton payslip={p} />}
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
          employeeId={generateFor}
          employeeName={employees.find((e) => e.id === generateFor)?.name ?? "Employee"}
          allowanceTypes={allowanceTypes}
          standing={standingAllowancesFor(allowances, generateFor)}
          onClose={() => setGenerateFor(null)}
        />
      )}

      {excludeFor && (
        <ExcludeDialog
          employeeName={employees.find((e) => e.id === excludeFor)?.name ?? "Employee"}
          onClose={() => setExcludeFor(null)}
          onConfirm={async (reason) => {
            const ok = await withBusy(
              () => excludeEmployeeFromRun(run.id, excludeFor, reason),
              "Employee excluded from this run",
            );
            if (ok) setExcludeFor(null);
          }}
        />
      )}
    </div>
  );
}

const POSTING_NOTE =
  "Includes the employer's 13% SSNIT contribution (Dr 5145 Employer SSNIT Contribution / Cr 2310 SSNIT Payable) on top of the amounts withheld from staff, so total staffing cost is 5140 + 5145.";

function EmailPayslipsButton() {
  return (
    <span title="Coming soon — needs an email provider and staff email addresses.">
      <Button variant="outline" className="gap-2" disabled>
        <Mail className="size-4" /> Email payslips
      </Button>
    </span>
  );
}

function ReviewPanel({
  period,
  isManager,
  submittedByName,
  submittedAt,
  payslips,
  missingCount,
  busy,
  onApprove,
  onReject,
}: {
  period: string;
  isManager: boolean;
  submittedByName: string;
  submittedAt: string | null;
  payslips: Payslip[];
  missingCount: number;
  busy: boolean;
  onApprove: () => Promise<boolean>;
  onReject: (reason: string) => Promise<boolean>;
}) {
  return (
    <div className="card-surface space-y-3 p-4">
      <div>
        <p className="text-sm font-medium">Awaiting Manager review</p>
        <p className="text-xs text-muted-foreground">
          Submitted by {submittedByName} on {fmtDate(submittedAt)}. Payslips are locked while the
          run is in review.
        </p>
      </div>
      {isManager ? (
        <div className="flex flex-wrap gap-2">
          <PostRunDialog
            periodLabel={period}
            payslips={payslips}
            missingCount={missingCount}
            posting={busy}
            onConfirm={onApprove}
          />
          <RejectRunDialog busy={busy} onReject={onReject} />
        </div>
      ) : (
        <p className="text-xs text-muted-foreground">
          A Manager approves it from here — approval posts the run to Accounting.
        </p>
      )}
    </div>
  );
}

function RejectRunDialog({
  busy,
  onReject,
}: {
  busy: boolean;
  onReject: (reason: string) => Promise<boolean>;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");

  return (
    <Dialog open={open} onOpenChange={(next) => !busy && setOpen(next)}>
      <DialogTrigger asChild>
        <Button variant="outline" className="text-destructive">
          Reject
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Return this run for revision</DialogTitle>
          <DialogDescription>
            It goes back to Draft and the submitter sees your reason. Payslips become editable
            again.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label>Reason</Label>
          <Textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="What needs to change before this can be approved?"
            rows={3}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>
            Cancel
          </Button>
          <Button
            variant="destructive"
            disabled={busy || !reason.trim()}
            onClick={async () => {
              const ok = await onReject(reason.trim());
              if (ok) {
                setOpen(false);
                setReason("");
              }
            }}
          >
            {busy ? "Returning…" : "Return to Draft"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ExcludeDialog({
  employeeName,
  onClose,
  onConfirm,
}: {
  employeeName: string;
  onClose: () => void;
  onConfirm: (reason: string) => Promise<void>;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  return (
    <Dialog open onOpenChange={(next) => !next && !busy && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Exclude {employeeName} from this run</DialogTitle>
          <DialogDescription>
            Marks this person as deliberately not paid this cycle, so the run can be submitted
            without a payslip for them. Reversible while the run is a Draft.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label>Reason (optional)</Label>
          <Input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. joined mid-month, paid next cycle"
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              try {
                await onConfirm(reason.trim());
              } finally {
                setBusy(false);
              }
            }}
          >
            {busy ? "Excluding…" : "Exclude"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

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
      ssnitEmployer: a.ssnitEmployer + p.ssnitEmployer,
      tier2: a.tier2 + p.tier2,
      paye: a.paye + p.tax,
      fines: a.fines + p.fines,
      iou: a.iou + p.iou,
      net: a.net + p.netPay,
    }),
    { gross: 0, ssnit: 0, ssnitEmployer: 0, tier2: 0, paye: 0, fines: 0, iou: 0, net: 0 },
  );
  const lines = [
    { key: "5140", code: "5140", name: "Salaries & Wages Expense", debit: sums.gross, credit: 0 },
    {
      key: "5145",
      code: "5145",
      name: "Employer SSNIT Contribution",
      debit: sums.ssnitEmployer,
      credit: 0,
    },
    { key: "2300", code: "2300", name: "Salaries & Wages Payable", debit: 0, credit: sums.net },
    { key: "2310e", code: "2310", name: "SSNIT Payable (employee)", debit: 0, credit: sums.ssnit },
    {
      key: "2310r",
      code: "2310",
      name: "SSNIT Payable (employer)",
      debit: 0,
      credit: sums.ssnitEmployer,
    },
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
          <BookOpen className="size-4" /> Approve &amp; post
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Approve {period} payroll &amp; post to Accounting</DialogTitle>
          <DialogDescription>
            Approving posts the run: one journal entry is created and the run locks — no payslip can
            be generated, edited or deleted against it afterward. A mistake after posting is
            corrected with a reversing entry.
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
            {posting ? "Posting…" : "Approve & post"}
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
    if (!window.confirm(`Delete ${payslip.employeeName}'s payslip? You can regenerate it.`)) return;
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
  employeeId,
  employeeName,
  allowanceTypes,
  standing,
  onClose,
}: {
  runId: string;
  employeeId: string;
  employeeName: string;
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
        employeeId,
        overtimeHours: Number(overtimeHours) || 0,
        overtimeRate: Number(overtimeRate) || 0,
        allowances,
        fines: Number(fines) || 0,
        iou: Number(iou) || 0,
      });
      toast.success(`Payslip generated for ${employeeName}`);
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
          <DialogTitle>Generate payslip — {employeeName}</DialogTitle>
          <DialogDescription>
            Basic salary, SSNIT, Tier 2 and PAYE are computed server-side from this employee's
            approved pay config. Adjust the month-specific figures below.
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
