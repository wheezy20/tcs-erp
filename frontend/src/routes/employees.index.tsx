import { Fragment, useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Check, ChevronRight, Plus, Search } from "lucide-react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
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
import { Switch } from "@/components/ui/switch";
import { PaymentDestinationFields } from "@/components/employees/payment-fields";
import { RefListSelect } from "@/components/employees/ref-list-select";
import { RejectButton } from "@/components/employees/reject-reason-dialog";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import {
  approveEmployee,
  approvePayConfig,
  currentConfigFor,
  proposeEmployee,
  rejectEmployee,
  rejectPayConfig,
  splitPendingConfigs,
  useEmployees,
  type Employee,
  type EmploymentStatus,
  type PayConfig,
  type PaymentMethod,
} from "@/data/employees-store";
import { activeNames, useDepartments, usePositions } from "@/data/org-lists-store";
import { useStaff } from "@/data/staff-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/employees/")({
  component: EmployeesListPage,
});

const firstOfThisMonth = () => `${new Date().toISOString().slice(0, 7)}-01`;

const STATUS_TONE: Record<EmploymentStatus, "secondary" | "outline" | "destructive"> = {
  "Pending Approval": "outline",
  Active: "secondary",
  Suspended: "outline",
  Rejected: "destructive",
};

function EmployeesListPage() {
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const isManager = currentStaff?.role === "Manager";
  const { employees, configs, loading } = useEmployees();
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"all" | EmploymentStatus>("all");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return employees
      .filter((e) => (status === "all" ? e.status !== "Rejected" : e.status === status))
      .filter((e) => {
        if (!q) return true;
        return (
          e.name.toLowerCase().includes(q) ||
          (e.position ?? "").toLowerCase().includes(q) ||
          (e.department ?? "").toLowerCase().includes(q)
        );
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [employees, query, status]);

  const pendingEmployees = employees.filter((e) => e.status === "Pending Approval");
  const pendingConfigs = configs.filter((c) => c.approvalStatus === "Pending Approval");
  // A bundled config (pending config on a still-pending employee) is not a
  // separate item — it's approved with the employee record.
  const { standalone: standalonePendingConfigs } = splitPendingConfigs(employees, pendingConfigs);
  const pendingCount = pendingEmployees.length + standalonePendingConfigs.length;
  const activeCount = employees.filter((e) => e.status === "Active").length;

  return (
    <>
      <PageHeader
        title="Employees"
        description="Everyone TCS pays. New records and salary / bank changes need Manager approval."
        actions={canWrite ? <ProposeEmployeeDialog /> : undefined}
      />

      {isManager && pendingCount > 0 && (
        <ApprovalsPanel
          employees={employees}
          pendingEmployees={pendingEmployees}
          pendingConfigs={pendingConfigs}
        />
      )}

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard label="Active employees" value={String(activeCount)} hint="Payable" />
        <SummaryCard
          label="Pending approval"
          value={String(pendingCount)}
          hint={`${pendingEmployees.length} new · ${standalonePendingConfigs.length} pay changes`}
        />
        <SummaryCard
          label="All records"
          value={String(employees.filter((e) => e.status !== "Rejected").length)}
          hint="Excludes rejected"
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 border-b p-4">
          <div className="relative max-w-sm flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search name, position or department"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
          <Select value={status} onValueChange={(v) => setStatus(v as typeof status)}>
            <SelectTrigger className="w-44">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Active + pending</SelectItem>
              <SelectItem value="Active">Active</SelectItem>
              <SelectItem value="Pending Approval">Pending approval</SelectItem>
              <SelectItem value="Suspended">Suspended</SelectItem>
              <SelectItem value="Rejected">Rejected</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {loading ? (
          <p className="p-10 text-center text-sm text-muted-foreground">Loading…</p>
        ) : filtered.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">No employees match.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Name</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 font-medium">Position</th>
                  <th className="px-5 py-3 text-right font-medium">Basic salary</th>
                  <th className="px-5 py-3 font-medium">Paid to</th>
                  <th className="px-5 py-3 font-medium">Phone</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((e) => {
                  const cfg = currentConfigFor(configs, e.id);
                  return (
                    <tr key={e.id} className="group hover:bg-muted/40">
                      <td className="px-5 py-3">
                        <Link
                          to="/employees/$employeeId"
                          params={{ employeeId: e.id }}
                          className="font-medium group-hover:text-primary"
                        >
                          {e.name}
                        </Link>
                        <p className="text-xs text-muted-foreground">{e.department ?? "—"}</p>
                      </td>
                      <td className="px-5 py-3">
                        <Badge variant={STATUS_TONE[e.status]}>{e.status}</Badge>
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">{e.position ?? "—"}</td>
                      <td className="px-5 py-3 text-right tabular-nums">
                        {cfg ? (
                          currency(cfg.basicSalary)
                        ) : (
                          <span className="text-muted-foreground">Not set</span>
                        )}
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">
                        {cfg?.bank
                          ? `${cfg.bank}${cfg.accountNo ? ` · ${cfg.accountNo}` : ""}`
                          : "—"}
                      </td>
                      <td className="px-5 py-3 tabular-nums text-muted-foreground">
                        {e.phone ?? "—"}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function SummaryCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tracking-tight">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}

/* -------------------------------------------------------- approvals panel */

type PendingRow =
  | { kind: "employee"; id: string; emp: Employee; pay: PayConfig | undefined; when: string }
  | { kind: "config"; id: string; emp: Employee | undefined; cfg: PayConfig; when: string };

function ApprovalsPanel({
  employees,
  pendingEmployees,
  pendingConfigs,
}: {
  employees: Employee[];
  pendingEmployees: Employee[];
  pendingConfigs: PayConfig[];
}) {
  const { staff: roster } = useStaff();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);

  const { bundledByEmployee, standalone } = splitPendingConfigs(employees, pendingConfigs);
  const staffName = (id: string | null) =>
    id ? (roster.find((s) => s.id === id)?.name ?? "someone") : "someone";
  const empName = (id: string) => employees.find((e) => e.id === id)?.name ?? "Employee";

  const rows: PendingRow[] = [
    ...pendingEmployees.map((emp) => ({
      kind: "employee" as const,
      id: emp.id,
      emp,
      pay: bundledByEmployee.get(emp.id),
      when: emp.createdAt,
    })),
    ...standalone.map((cfg) => ({
      kind: "config" as const,
      id: cfg.id,
      emp: employees.find((e) => e.id === cfg.employeeId),
      cfg,
      when: cfg.createdAt,
    })),
  ].sort((a, b) => (a.when < b.when ? 1 : -1));

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

  return (
    <div className="card-surface mb-6 overflow-hidden border-primary/30">
      <div className="border-b px-5 py-3">
        <h2 className="text-sm font-semibold">
          Waiting for your approval <span className="text-muted-foreground">({rows.length})</span>
        </h2>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="w-8 px-3 py-2" />
              <th className="px-3 py-2 font-medium">Name</th>
              <th className="px-3 py-2 font-medium">Change</th>
              <th className="px-3 py-2 font-medium">Proposed by</th>
              <th className="px-3 py-2 font-medium">Submitted</th>
              <th className="px-3 py-2" />
            </tr>
          </thead>
          <tbody className="divide-y">
            {rows.map((row) => {
              const name =
                row.kind === "employee"
                  ? row.emp.name
                  : (row.emp?.name ?? empName(row.cfg.employeeId));
              const proposedBy =
                row.kind === "employee" ? row.emp.proposedById : row.cfg.proposedById;
              const changeLabel =
                row.kind === "employee"
                  ? row.pay
                    ? "New employee + pay"
                    : "New employee"
                  : "Salary / bank change";
              const isOpen = expanded === row.id;
              const busy = busyId === row.id;
              return (
                <Fragment key={row.id}>
                  <tr
                    className="cursor-pointer hover:bg-muted/40"
                    onClick={() => setExpanded(isOpen ? null : row.id)}
                  >
                    <td className="px-3 py-2 text-muted-foreground">
                      <ChevronRight
                        className={`size-4 transition-transform ${isOpen ? "rotate-90" : ""}`}
                      />
                    </td>
                    <td className="px-3 py-2 font-medium">{name}</td>
                    <td className="px-3 py-2">
                      <Badge variant="outline">{changeLabel}</Badge>
                    </td>
                    <td className="px-3 py-2 text-muted-foreground">{staffName(proposedBy)}</td>
                    <td className="px-3 py-2 text-muted-foreground tabular-nums">
                      {row.when.slice(0, 10)}
                    </td>
                    <td className="px-3 py-2 text-right text-xs text-muted-foreground">
                      {isOpen ? "Hide" : "Review"}
                    </td>
                  </tr>
                  {isOpen && (
                    <tr className="bg-muted/20">
                      <td />
                      <td colSpan={5} className="px-3 pb-4 pt-1">
                        {row.kind === "employee" ? (
                          <NewEmployeeDetail
                            emp={row.emp}
                            pay={row.pay}
                            busy={busy}
                            onApprove={() =>
                              run(
                                row.id,
                                () => approveEmployee(row.emp.id),
                                `${row.emp.name} approved`,
                              )
                            }
                            onReject={(reason) => rejectEmployee(row.emp.id, reason)}
                          />
                        ) : (
                          <ConfigChangeDetail
                            cfg={row.cfg}
                            emp={row.emp}
                            busy={busy}
                            onApprove={() =>
                              run(row.id, () => approvePayConfig(row.cfg.id), "Pay change approved")
                            }
                            onReject={(reason) => rejectPayConfig(row.cfg.id, reason)}
                          />
                        )}
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function DetailField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 text-sm">{value}</dd>
    </div>
  );
}

function payLine(pay: PayConfig): string {
  return [
    currency(pay.basicSalary),
    pay.paymentMethod === "Mobile Money" ? "Mobile Money" : "Bank",
    pay.bank ?? "—",
    pay.accountNo ?? undefined,
    `from ${pay.effectiveFrom}`,
  ]
    .filter(Boolean)
    .join(" · ");
}

function NewEmployeeDetail({
  emp,
  pay,
  busy,
  onApprove,
  onReject,
}: {
  emp: Employee;
  pay: PayConfig | undefined;
  busy: boolean;
  onApprove: () => void;
  onReject: (reason: string) => Promise<void>;
}) {
  return (
    <div className="space-y-3">
      <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-3">
        <DetailField label="Name" value={emp.name} />
        <DetailField label="Position" value={emp.position ?? "—"} />
        <DetailField label="Department" value={emp.department ?? "—"} />
        <DetailField label="Phone" value={emp.phone ?? "—"} />
        <DetailField
          label="Initial pay"
          value={pay ? payLine(pay) : "No initial pay config proposed"}
        />
      </dl>
      <p className="text-xs text-muted-foreground">
        Approving the record also approves its bundled pay config, in one step.
      </p>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" className="gap-1.5" disabled={busy} onClick={onApprove}>
          <Check className="size-3.5" /> Approve
        </Button>
        <RejectButton
          title={`Reject ${emp.name}'s record`}
          onReject={onReject}
          successMessage={`${emp.name} rejected`}
        />
        <Button asChild size="sm" variant="ghost">
          <Link to="/employees/$employeeId" params={{ employeeId: emp.id }}>
            Open record
          </Link>
        </Button>
      </div>
    </div>
  );
}

function ConfigChangeDetail({
  cfg,
  emp,
  busy,
  onApprove,
  onReject,
}: {
  cfg: PayConfig;
  emp: Employee | undefined;
  busy: boolean;
  onApprove: () => void;
  onReject: (reason: string) => Promise<void>;
}) {
  return (
    <div className="space-y-3">
      <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-3">
        <DetailField label="Basic salary" value={currency(cfg.basicSalary)} />
        <DetailField label="Payment method" value={cfg.paymentMethod} />
        <DetailField
          label={cfg.paymentMethod === "Mobile Money" ? "Network" : "Bank"}
          value={cfg.bank ?? "—"}
        />
        <DetailField
          label={cfg.paymentMethod === "Mobile Money" ? "Wallet number" : "Account number"}
          value={cfg.accountNo ?? "—"}
        />
        <DetailField label="Effective from" value={cfg.effectiveFrom} />
      </dl>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" className="gap-1.5" disabled={busy} onClick={onApprove}>
          <Check className="size-3.5" /> Approve
        </Button>
        <RejectButton
          title="Reject this pay change"
          onReject={onReject}
          successMessage="Pay change rejected"
        />
        {emp && (
          <Button asChild size="sm" variant="ghost">
            <Link to="/employees/$employeeId" params={{ employeeId: emp.id }}>
              Open record
            </Link>
          </Button>
        )}
      </div>
    </div>
  );
}

/* ---------------------------------------------------- propose employee */

function ProposeEmployeeDialog() {
  const { staff: roster } = useStaff();
  const { items: positions } = usePositions();
  const { items: departments } = useDepartments();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [position, setPosition] = useState("");
  const [department, setDepartment] = useState("");
  const [staffId, setStaffId] = useState<string>("none");
  const [withPay, setWithPay] = useState(true);
  const [basicSalary, setBasicSalary] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("Bank");
  const [bank, setBank] = useState("");
  const [accountNo, setAccountNo] = useState("");
  const [effectiveFrom, setEffectiveFrom] = useState(firstOfThisMonth());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const linkableLogins = roster.filter((s) => s.active && !s.employeeId);

  async function submit() {
    if (!name.trim()) {
      setError("A name is required.");
      return;
    }
    if (withPay && (!basicSalary || Number(basicSalary) < 0)) {
      setError("Enter a basic salary, or turn off the initial pay config.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await proposeEmployee({
        name: name.trim(),
        phone,
        position,
        department,
        staffId: staffId === "none" ? undefined : staffId,
        basicSalary: withPay ? Number(basicSalary) : undefined,
        paymentMethod: withPay ? paymentMethod : undefined,
        bank: withPay ? bank : undefined,
        accountNo: withPay ? accountNo : undefined,
        effectiveFrom: withPay ? effectiveFrom : undefined,
      });
      toast.success(`${name.trim()} proposed — waiting for Manager approval`);
      setOpen(false);
      setName("");
      setPhone("");
      setPosition("");
      setDepartment("");
      setStaffId("none");
      setBasicSalary("");
      setPaymentMethod("Bank");
      setBank("");
      setAccountNo("");
    } catch (err) {
      setError(getErrorMessage(err, "Could not propose the employee."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !saving && setOpen(next)}>
      <DialogTrigger asChild>
        <Button className="gap-2">
          <Plus className="size-4" /> Propose employee
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Propose a new employee</DialogTitle>
          <DialogDescription>
            The record starts as <strong>Pending Approval</strong> and can't be paid until a Manager
            approves it.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Name</Label>
              <Input value={name} maxLength={80} onChange={(e) => setName(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Phone</Label>
              <Input value={phone} maxLength={40} onChange={(e) => setPhone(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Position</Label>
              <RefListSelect
                options={activeNames(positions)}
                value={position}
                onChange={setPosition}
                placeholder="Select position"
              />
            </div>
            <div className="space-y-1.5">
              <Label>Department</Label>
              <RefListSelect
                options={activeNames(departments)}
                value={department}
                onChange={setDepartment}
                placeholder="Select department"
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Link an ERP login (optional)</Label>
            <Select value={staffId} onValueChange={setStaffId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">No login</SelectItem>
                {linkableLogins.map((s) => (
                  <SelectItem key={s.id} value={s.id}>
                    {s.name} ({s.email})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="rounded-lg border p-3">
            <label className="flex items-center justify-between text-sm font-medium">
              Include initial pay config
              <Switch checked={withPay} onCheckedChange={setWithPay} />
            </label>
            {withPay && (
              <div className="mt-3 grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label>Basic salary (monthly)</Label>
                  <Input
                    type="number"
                    min="0"
                    step="0.01"
                    value={basicSalary}
                    onChange={(e) => setBasicSalary(e.target.value)}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Effective from</Label>
                  <Input
                    type="date"
                    value={effectiveFrom}
                    onChange={(e) => setEffectiveFrom(e.target.value)}
                  />
                </div>
                <PaymentDestinationFields
                  method={paymentMethod}
                  provider={bank}
                  number={accountNo}
                  onMethod={(m) => {
                    setPaymentMethod(m);
                    setBank("");
                  }}
                  onProvider={setBank}
                  onNumber={setAccountNo}
                />
              </div>
            )}
          </div>

          {error && <p className="text-sm font-medium text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
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
