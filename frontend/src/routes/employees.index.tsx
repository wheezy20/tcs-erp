import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Check, Plus, Search, X } from "lucide-react";
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
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import {
  approveEmployee,
  approvePayConfig,
  currentConfigFor,
  proposeEmployee,
  rejectEmployee,
  rejectPayConfig,
  useEmployees,
  type Employee,
  type EmploymentStatus,
  type PayConfig,
} from "@/data/employees-store";
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
  const activeCount = employees.filter((e) => e.status === "Active").length;

  return (
    <>
      <PageHeader
        title="Employees"
        description="Everyone TCS pays. New records and salary / bank changes need Manager approval."
        actions={canWrite ? <ProposeEmployeeDialog /> : undefined}
      />

      {isManager && (pendingEmployees.length > 0 || pendingConfigs.length > 0) && (
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
          value={String(pendingEmployees.length + pendingConfigs.length)}
          hint={`${pendingEmployees.length} new · ${pendingConfigs.length} pay changes`}
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
                  <th className="px-5 py-3 font-medium">Bank</th>
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

function ApprovalsPanel({
  employees,
  pendingEmployees,
  pendingConfigs,
}: {
  employees: Employee[];
  pendingEmployees: Employee[];
  pendingConfigs: PayConfig[];
}) {
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

  function reject(id: string, fn: (reason: string) => Promise<void>, ok: string) {
    const reason = window.prompt("Reason for rejection?");
    if (reason === null) return;
    run(id, () => fn(reason), ok);
  }

  const empName = (id: string) => employees.find((e) => e.id === id)?.name ?? "Employee";

  return (
    <div className="card-surface mb-6 border-primary/30 p-5">
      <h2 className="text-sm font-semibold">Waiting for your approval</h2>

      {pendingEmployees.length > 0 && (
        <div className="mt-4">
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            New employee records
          </p>
          <ul className="divide-y">
            {pendingEmployees.map((e) => (
              <li key={e.id} className="flex flex-wrap items-center justify-between gap-3 py-2">
                <div className="text-sm">
                  <span className="font-medium">{e.name}</span>
                  <span className="text-muted-foreground">
                    {" "}
                    · {[e.position, e.department].filter(Boolean).join(" · ") || "no placement"}
                  </span>
                </div>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    className="gap-1.5"
                    disabled={busyId === e.id}
                    onClick={() => run(e.id, () => approveEmployee(e.id), `${e.name} approved`)}
                  >
                    <Check className="size-3.5" /> Approve
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    className="gap-1.5 text-destructive"
                    disabled={busyId === e.id}
                    onClick={() =>
                      reject(e.id, (r) => rejectEmployee(e.id, r), `${e.name} rejected`)
                    }
                  >
                    <X className="size-3.5" /> Reject
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}

      {pendingConfigs.length > 0 && (
        <div className="mt-4">
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Salary / bank changes
          </p>
          <ul className="divide-y">
            {pendingConfigs.map((c) => (
              <li key={c.id} className="flex flex-wrap items-center justify-between gap-3 py-2">
                <div className="text-sm">
                  <span className="font-medium">{empName(c.employeeId)}</span>
                  <span className="text-muted-foreground">
                    {" "}
                    · {currency(c.basicSalary)}
                    {c.bank ? ` · ${c.bank}` : ""}
                    {c.accountNo ? ` · ${c.accountNo}` : ""} · from {c.effectiveFrom}
                  </span>
                </div>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    className="gap-1.5"
                    disabled={busyId === c.id}
                    onClick={() => run(c.id, () => approvePayConfig(c.id), "Pay change approved")}
                  >
                    <Check className="size-3.5" /> Approve
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    className="gap-1.5 text-destructive"
                    disabled={busyId === c.id}
                    onClick={() =>
                      reject(c.id, (r) => rejectPayConfig(c.id, r), "Pay change rejected")
                    }
                  >
                    <X className="size-3.5" /> Reject
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/* ---------------------------------------------------- propose employee */

function ProposeEmployeeDialog() {
  const { staff: roster } = useStaff();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [position, setPosition] = useState("");
  const [department, setDepartment] = useState("");
  const [staffId, setStaffId] = useState<string>("none");
  const [withPay, setWithPay] = useState(true);
  const [basicSalary, setBasicSalary] = useState("");
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
              <Input
                value={position}
                maxLength={80}
                onChange={(e) => setPosition(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Department</Label>
              <Input
                value={department}
                maxLength={80}
                onChange={(e) => setDepartment(e.target.value)}
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
                <div className="space-y-1.5">
                  <Label>Bank</Label>
                  <Input value={bank} onChange={(e) => setBank(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label>Account number</Label>
                  <Input value={accountNo} onChange={(e) => setAccountNo(e.target.value)} />
                </div>
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
