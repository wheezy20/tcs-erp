import { useState } from "react";
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
import { Textarea } from "@/components/ui/textarea";
import { RejectButton } from "@/components/employees/reject-reason-dialog";
import { useBankAccounts } from "@/data/bank-accounts-store";
import { currencyPrecise } from "@/data/dashboard";
import { useEmployees } from "@/data/employees-store";
import { formatDate } from "@/data/settings-store";
import {
  approveStaffAdvance,
  approveStaffAdvanceChange,
  proposeStaffAdvance,
  proposeStaffAdvanceChange,
  rejectStaffAdvance,
  rejectStaffAdvanceChange,
  withdrawStaffAdvanceChange,
  withdrawStaffAdvanceProposal,
  type ChangeKind,
  type PayoutMethod,
  type StaffAdvance,
  type StaffAdvanceChangeRequest,
  type StaffAdvanceDisplayStatus,
} from "@/data/staff-advances-store";
import { getErrorMessage } from "@/lib/utils";
import { ACCOUNT_1350_NOTE, monthLabel } from "@/data/staff-advances-format";

export function AdvanceStatusBadge({ status }: { status: StaffAdvanceDisplayStatus }) {
  const variant =
    status === "Active"
      ? "default"
      : status === "Proposed"
        ? "outline"
        : status === "Rejected" || status === "Cancelled"
          ? "destructive"
          : "secondary";
  return <Badge variant={variant}>{status}</Badge>;
}

const CHANGE_LABEL: Record<ChangeKind, string> = {
  Pause: "Pause deductions",
  Resume: "Resume deductions",
  Cancel: "Cancel (stop deductions)",
  Instalment: "Change the monthly instalment",
};

function changeSummary(c: StaffAdvanceChangeRequest) {
  return c.kind === "Instalment"
    ? `New instalment ${currencyPrecise(c.newInstalment ?? 0)}`
    : CHANGE_LABEL[c.kind];
}

/** Every advance in `advances` with its balance and status, the approvals
 * waiting on each, and the actions the viewer may take. */
export function AdvancesTable({
  advances,
  changeRequests,
  showEmployee,
  canWrite,
  isManager,
  currentStaffId,
  staffName,
}: {
  advances: StaffAdvance[];
  changeRequests: StaffAdvanceChangeRequest[];
  showEmployee: boolean;
  canWrite: boolean;
  isManager: boolean;
  currentStaffId: string | null;
  staffName: (id: string | null) => string;
}) {
  const [changing, setChanging] = useState<StaffAdvance | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function run(id: string, fn: () => Promise<void>, ok: string) {
    setBusyId(id);
    try {
      await fn();
      toast.success(ok);
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not complete that."));
    } finally {
      setBusyId(null);
    }
  }

  if (advances.length === 0) {
    return <p className="text-sm text-muted-foreground">No staff advances.</p>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
          <tr>
            {showEmployee && <th className="px-4 py-3 font-medium">Employee</th>}
            <th className="px-4 py-3 text-right font-medium">Advanced</th>
            <th className="px-4 py-3 text-right font-medium">Monthly</th>
            <th className="px-4 py-3 text-right font-medium">Repaid</th>
            <th className="px-4 py-3 text-right font-medium">Balance</th>
            <th className="px-4 py-3 font-medium">Status</th>
            <th className="px-4 py-3 font-medium">Details</th>
            <th className="px-4 py-3 font-medium">&nbsp;</th>
          </tr>
        </thead>
        <tbody className="divide-y">
          {advances.map((a) => {
            const pending = changeRequests.find(
              (c) => c.advanceId === a.id && c.status === "Pending Approval",
            );
            const busy = busyId === a.id || busyId === pending?.id;
            const canChange =
              canWrite &&
              !pending &&
              (a.displayStatus === "Active" || a.displayStatus === "Paused");
            const ownProposal = (by: string | null) => by !== null && by === currentStaffId;
            return (
              <tr key={a.id} className="align-top">
                {showEmployee && <td className="px-4 py-3 font-medium">{a.employeeName}</td>}
                <td className="px-4 py-3 text-right tabular-nums">{currencyPrecise(a.amount)}</td>
                <td className="px-4 py-3 text-right tabular-nums">
                  {currencyPrecise(a.instalment)}
                </td>
                <td className="px-4 py-3 text-right tabular-nums">{currencyPrecise(a.repaid)}</td>
                <td className="px-4 py-3 text-right font-medium tabular-nums">
                  {currencyPrecise(a.balance)}
                </td>
                <td className="px-4 py-3">
                  <AdvanceStatusBadge status={a.displayStatus} />
                  {a.displayStatus === "Cancelled" && a.balance > 0 && (
                    <p className="mt-1 text-xs text-muted-foreground">
                      {currencyPrecise(a.balance)} outstanding
                    </p>
                  )}
                  {a.employeeStatus !== "Active" && a.balance > 0 && a.status !== "Rejected" && (
                    <p className="mt-1 text-xs text-destructive">
                      Employee not active: not being deducted
                    </p>
                  )}
                </td>
                <td className="px-4 py-3 text-xs text-muted-foreground">
                  <p>
                    Paid out {formatDate(a.disbursedOn)} ({a.disbursementMethod}); repayments from{" "}
                    {monthLabel(a.firstRepaymentMonth)}
                  </p>
                  <p>
                    Proposed by {staffName(a.proposedById)}
                    {a.reviewedById && a.status !== "Proposed" && (
                      <>
                        {" · "}
                        {a.status === "Rejected" ? "Rejected" : "Approved"} by{" "}
                        {staffName(a.reviewedById)}
                      </>
                    )}
                  </p>
                  {a.rejectionReason && <p>Reason: {a.rejectionReason}</p>}
                  {a.note && <p>Note: {a.note}</p>}
                  {pending && (
                    <p className="mt-1 font-medium text-foreground">
                      Pending change: {changeSummary(pending)} (by {staffName(pending.proposedById)}
                      ){pending.reason ? ` — ${pending.reason}` : ""}
                    </p>
                  )}
                </td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap justify-end gap-2">
                    {a.status === "Proposed" && isManager && (
                      <Button
                        size="sm"
                        disabled={busy}
                        onClick={() =>
                          run(a.id, () => approveStaffAdvance(a.id), "Advance approved and posted")
                        }
                      >
                        Approve
                      </Button>
                    )}
                    {a.status === "Proposed" && isManager && (
                      <RejectButton
                        title="Reject this advance"
                        onReject={(reason) => rejectStaffAdvance(a.id, reason)}
                        successMessage="Advance rejected"
                      />
                    )}
                    {a.status === "Proposed" &&
                      canWrite &&
                      (isManager || ownProposal(a.proposedById)) && (
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy}
                          onClick={() =>
                            run(
                              a.id,
                              () => withdrawStaffAdvanceProposal(a.id),
                              "Proposal withdrawn",
                            )
                          }
                        >
                          Withdraw
                        </Button>
                      )}
                    {pending && isManager && (
                      <Button
                        size="sm"
                        disabled={busy}
                        onClick={() =>
                          run(
                            pending.id,
                            () => approveStaffAdvanceChange(pending.id),
                            "Change approved",
                          )
                        }
                      >
                        Approve change
                      </Button>
                    )}
                    {pending && isManager && (
                      <RejectButton
                        title="Reject this change"
                        label="Reject change"
                        onReject={(reason) => rejectStaffAdvanceChange(pending.id, reason)}
                        successMessage="Change rejected"
                      />
                    )}
                    {pending && canWrite && (isManager || ownProposal(pending.proposedById)) && (
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={busy}
                        onClick={() =>
                          run(
                            pending.id,
                            () => withdrawStaffAdvanceChange(pending.id),
                            "Change withdrawn",
                          )
                        }
                      >
                        Withdraw change
                      </Button>
                    )}
                    {canChange && (
                      <Button size="sm" variant="outline" onClick={() => setChanging(a)}>
                        Request change
                      </Button>
                    )}
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {changing && <ChangeRequestDialog advance={changing} onClose={() => setChanging(null)} />}
    </div>
  );
}

function ChangeRequestDialog({ advance, onClose }: { advance: StaffAdvance; onClose: () => void }) {
  const kinds: ChangeKind[] =
    advance.status === "Paused"
      ? ["Resume", "Cancel", "Instalment"]
      : ["Pause", "Cancel", "Instalment"];
  const [kind, setKind] = useState<ChangeKind>(kinds[0]);
  const [newInstalment, setNewInstalment] = useState(String(advance.instalment));
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (kind === "Instalment" && newInstalment.trim() === "") {
      setError("Enter the new monthly instalment.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await proposeStaffAdvanceChange({
        advanceId: advance.id,
        kind,
        newInstalment: kind === "Instalment" ? Number(newInstalment) : null,
        reason,
      });
      toast.success("Change proposed — waiting for Manager approval");
      onClose();
    } catch (err) {
      setError(getErrorMessage(err, "Could not propose the change."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && !saving && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Request a change — {advance.employeeName}</DialogTitle>
          <DialogDescription>
            A Manager approves this before it takes effect. It applies to payslips generated after
            approval; a draft payslip already generated keeps its deduction until it is deleted and
            generated again. Cancelling stops deductions only: the balance stays outstanding.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Change</Label>
            <Select value={kind} onValueChange={(v) => setKind(v as ChangeKind)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {kinds.map((k) => (
                  <SelectItem key={k} value={k}>
                    {CHANGE_LABEL[k]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {kind === "Instalment" && (
            <div className="space-y-1.5">
              <Label>New monthly instalment</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={newInstalment}
                onChange={(e) => setNewInstalment(e.target.value)}
              />
            </div>
          )}
          <div className="space-y-1.5">
            <Label>Reason (optional)</Label>
            <Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={2} />
          </div>
          {error && <p className="text-sm font-medium text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Submitting…" : "Submit for approval"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function thisMonthInput() {
  return new Date().toISOString().slice(0, 7);
}

/** Propose a new advance. With `employee`, the employee is fixed (profile
 * page); otherwise any active employee can be chosen. */
export function ProposeAdvanceDialog({
  employee,
  onClose,
}: {
  employee?: { id: string; name: string };
  onClose: () => void;
}) {
  const { employees } = useEmployees();
  const { accounts: bankAccounts } = useBankAccounts();
  const active = employees.filter((e) => e.status === "Active");
  const [employeeId, setEmployeeId] = useState(employee?.id ?? "");
  const [amount, setAmount] = useState("");
  const [instalment, setInstalment] = useState("");
  const [firstMonth, setFirstMonth] = useState(thisMonthInput());
  const [disbursedOn, setDisbursedOn] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState<PayoutMethod>("Cash");
  const [bankAccountId, setBankAccountId] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!employeeId) {
      setError("Choose the employee.");
      return;
    }
    if (amount.trim() === "" || instalment.trim() === "") {
      setError("Enter the amount advanced and the monthly instalment.");
      return;
    }
    if (!firstMonth || !disbursedOn) {
      setError("Enter the payout date and the first repayment month.");
      return;
    }
    if (method === "Bank Transfer" && !bankAccountId) {
      setError("Choose the bank account the advance was paid from.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await proposeStaffAdvance({
        employeeId,
        amount: Number(amount),
        instalment: Number(instalment),
        firstRepaymentMonth: `${firstMonth}-01`,
        disbursedOn,
        method,
        bankAccountId: method === "Bank Transfer" ? bankAccountId : null,
        note,
      });
      toast.success("Advance proposed — waiting for Manager approval");
      onClose();
    } catch (err) {
      setError(getErrorMessage(err, "Could not propose the advance."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && !saving && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Propose a staff advance</DialogTitle>
          <DialogDescription>
            A Manager approves it before anything is posted or deducted. Once approved, each payslip
            from the first repayment month deducts the monthly instalment (the last one is smaller)
            until the balance is repaid.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Employee</Label>
            {employee ? (
              <p className="text-sm font-medium">{employee.name}</p>
            ) : (
              <Select value={employeeId} onValueChange={setEmployeeId}>
                <SelectTrigger>
                  <SelectValue placeholder="Choose an active employee" />
                </SelectTrigger>
                <SelectContent>
                  {active.map((e) => (
                    <SelectItem key={e.id} value={e.id}>
                      {e.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Amount advanced</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Monthly instalment</Label>
              <Input
                type="number"
                min="0"
                step="0.01"
                value={instalment}
                onChange={(e) => setInstalment(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Paid out on</Label>
              <Input
                type="date"
                value={disbursedOn}
                onChange={(e) => setDisbursedOn(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>First repayment month</Label>
              <Input
                type="month"
                value={firstMonth}
                onChange={(e) => setFirstMonth(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Paid out by</Label>
              <Select value={method} onValueChange={(v) => setMethod(v as PayoutMethod)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="Cash">Cash</SelectItem>
                  <SelectItem value="Mobile Money">Mobile Money</SelectItem>
                  <SelectItem value="Bank Transfer">Bank Transfer</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {method === "Bank Transfer" && (
              <div className="space-y-1.5">
                <Label>From bank account</Label>
                <Select value={bankAccountId} onValueChange={setBankAccountId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Choose" />
                  </SelectTrigger>
                  <SelectContent>
                    {bankAccounts
                      .filter((b) => b.active)
                      .map((b) => (
                        <SelectItem key={b.id} value={b.id}>
                          {b.name}
                        </SelectItem>
                      ))}
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>
          <div className="space-y-1.5">
            <Label>Note (optional)</Label>
            <Textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} />
          </div>
          <p className="text-xs text-muted-foreground">{ACCOUNT_1350_NOTE}</p>
          {error && <p className="text-sm font-medium text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Submitting…" : "Submit for approval"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** The employee profile's advances card: this employee's advances with
 * balance and status, and (for a finance writer) a propose button. */
export function EmployeeAdvancesSection({
  employee,
  advances,
  changeRequests,
  canWrite,
  isManager,
  currentStaffId,
  staffName,
}: {
  employee: { id: string; name: string; status: string };
  advances: StaffAdvance[];
  changeRequests: StaffAdvanceChangeRequest[];
  canWrite: boolean;
  isManager: boolean;
  currentStaffId: string | null;
  staffName: (id: string | null) => string;
}) {
  const [proposing, setProposing] = useState(false);
  const mine = advances.filter((a) => a.employeeId === employee.id);
  const hasOutstanding = mine.some(
    (a) => a.status !== "Proposed" && a.status !== "Rejected" && a.balance > 0,
  );

  return (
    <section className="card-surface overflow-hidden">
      <div className="flex flex-wrap items-start justify-between gap-3 px-6 pt-6">
        <div>
          <h2 className="text-sm font-semibold">Staff advances</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Repaid automatically from each payslip until settled.
          </p>
        </div>
        {canWrite && employee.status === "Active" && (
          <Button size="sm" variant="outline" onClick={() => setProposing(true)}>
            Propose an advance
          </Button>
        )}
      </div>
      {employee.status !== "Active" && hasOutstanding && (
        <p className="mx-6 mt-3 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
          This employee is not active and has an advance balance outstanding (below), so nothing is
          being deducted. How a leaver&apos;s balance is settled or written off is not yet decided.
        </p>
      )}
      <div className="mt-3">
        <AdvancesTable
          advances={mine}
          changeRequests={changeRequests}
          showEmployee={false}
          canWrite={canWrite}
          isManager={isManager}
          currentStaffId={currentStaffId}
          staffName={staffName}
        />
      </div>
      {proposing && (
        <ProposeAdvanceDialog employee={employee} onClose={() => setProposing(false)} />
      )}
    </section>
  );
}
