import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Pencil, Plus, Trash2 } from "lucide-react";
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
import { Switch } from "@/components/ui/switch";
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { useStaff } from "@/data/staff-store";
import {
  createAllowanceType,
  currentConfigFor,
  deleteAllowanceType,
  savePayConfig,
  setStandingAllowances,
  standingAllowancesFor,
  updateAllowanceType,
  usePayroll,
  type AllowanceType,
  type PayConfigFields,
  type StaffPayConfig,
} from "@/data/payroll-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/payroll/pay-config")({
  component: PayConfigPage,
});

const today = () => new Date().toISOString().slice(0, 10);
const firstOfThisMonth = () => `${today().slice(0, 7)}-01`;

function PayConfigPage() {
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";
  const { payConfigs, staffAllowances, allowanceTypes, rates, bands, loading } = usePayroll();
  const { staff: roster } = useStaff();
  const [editing, setEditing] = useState<string | null>(null);

  const activeRates = rates[0];

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const activeRoster = roster.filter((s) => s.active);

  return (
    <div className="mt-4 space-y-6">
      <div className="card-surface p-4 text-sm">
        <p className="font-medium">Statutory rates in effect</p>
        {activeRates ? (
          <p className="mt-1 text-muted-foreground">
            SSNIT {activeRates.ssnitEmployeePct}% employee / {activeRates.ssnitEmployerPct}%
            employer · Tier 2 {activeRates.tier2EmployeePct}% employee · PAYE {bands.length}{" "}
            graduated band
            {bands.length === 1 ? "" : "s"}. <br />
            <span className="text-amber-600 dark:text-amber-500">
              Placeholder figures — verify against SSNIT / GRA before running real payroll (see
              docs/CONSTRAINTS.md).
            </span>
          </p>
        ) : (
          <p className="mt-1 text-destructive">No statutory rates configured.</p>
        )}
      </div>

      <section>
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-sm font-semibold text-muted-foreground">Staff pay configuration</h3>
        </div>
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Staff</th>
                  <th className="px-5 py-3 font-medium">Position</th>
                  <th className="px-5 py-3 text-right font-medium">Basic salary</th>
                  <th className="px-5 py-3 font-medium">Statutory</th>
                  <th className="px-5 py-3 font-medium">Bank</th>
                  {isManager && <th className="px-5 py-3 font-medium">&nbsp;</th>}
                </tr>
              </thead>
              <tbody className="divide-y">
                {activeRoster.map((s) => {
                  const config = currentConfigFor(payConfigs, s.id);
                  const standing = standingAllowancesFor(staffAllowances, s.id);
                  return (
                    <tr key={s.id} className="hover:bg-muted/40">
                      <td className="px-5 py-3">
                        <div className="font-medium">{s.name}</div>
                        <div className="text-xs text-muted-foreground">{s.role}</div>
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">
                        {config?.position ?? "—"}
                        {config?.department ? ` · ${config.department}` : ""}
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums">
                        {config ? (
                          currency(config.basicSalary)
                        ) : (
                          <span className="text-muted-foreground">Not set</span>
                        )}
                      </td>
                      <td className="px-5 py-3">
                        {config ? (
                          <div className="flex flex-wrap gap-1">
                            {config.paysSsnit && <Badge variant="secondary">SSNIT</Badge>}
                            {config.paysTier2 && <Badge variant="secondary">Tier 2</Badge>}
                            {config.paysPaye && <Badge variant="secondary">PAYE</Badge>}
                            {!config.paysSsnit && !config.paysTier2 && !config.paysPaye && (
                              <Badge variant="outline">Exempt (all)</Badge>
                            )}
                          </div>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">
                        {config?.bank
                          ? `${config.bank}${config.accountNo ? ` · ${config.accountNo}` : ""}`
                          : "—"}
                        {standing.length > 0 && (
                          <div className="text-xs">
                            {standing.length} standing allowance{standing.length === 1 ? "" : "s"}
                          </div>
                        )}
                      </td>
                      {isManager && (
                        <td className="px-5 py-3 text-right">
                          <Button
                            variant="ghost"
                            size="sm"
                            className="gap-1"
                            onClick={() => setEditing(s.id)}
                          >
                            <Pencil className="size-3.5" /> {config ? "Edit" : "Set up"}
                          </Button>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <AllowanceTypesSection types={allowanceTypes} isManager={isManager} />

      {editing && (
        <PayConfigDialog
          staffId={editing}
          staffName={roster.find((s) => s.id === editing)?.name ?? "Staff"}
          config={currentConfigFor(payConfigs, editing)}
          allowanceTypes={allowanceTypes}
          standing={standingAllowancesFor(staffAllowances, editing)}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  );
}

function AllowanceTypesSection({
  types,
  isManager,
}: {
  types: AllowanceType[];
  isManager: boolean;
}) {
  const [name, setName] = useState("");
  const [taxable, setTaxable] = useState(true);
  const [busy, setBusy] = useState(false);

  async function add() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      await createAllowanceType(name, taxable);
      setName("");
      setTaxable(true);
      toast.success("Allowance type added");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not add the allowance type."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <h3 className="mb-2 text-sm font-semibold text-muted-foreground">Allowance types</h3>
      <div className="card-surface p-4">
        <div className="flex flex-wrap gap-2">
          {types.length === 0 && (
            <p className="text-sm text-muted-foreground">No allowance types yet.</p>
          )}
          {types.map((t) => (
            <AllowanceTypeChip key={t.id} type={t} isManager={isManager} />
          ))}
        </div>

        {isManager && (
          <div className="mt-4 flex flex-wrap items-end gap-2 border-t pt-4">
            <div className="space-y-1.5">
              <Label className="text-xs">New allowance type</Label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g. Extra Classes"
                className="w-52"
              />
            </div>
            <label className="flex items-center gap-2 pb-2 text-sm">
              <Switch checked={taxable} onCheckedChange={setTaxable} />
              Taxable
            </label>
            <Button size="sm" className="gap-1.5" disabled={busy || !name.trim()} onClick={add}>
              <Plus className="size-3.5" /> Add
            </Button>
          </div>
        )}
      </div>
    </section>
  );
}

function AllowanceTypeChip({ type, isManager }: { type: AllowanceType; isManager: boolean }) {
  const [busy, setBusy] = useState(false);
  async function toggleTaxable() {
    setBusy(true);
    try {
      await updateAllowanceType(type.id, { taxable: !type.taxable });
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update the allowance type."));
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (!window.confirm(`Delete allowance type "${type.name}"?`)) return;
    setBusy(true);
    try {
      await deleteAllowanceType(type.id);
      toast.success("Allowance type deleted");
    } catch (error) {
      toast.error(
        getErrorMessage(error, "Could not delete — it may be used on a payslip or standing list."),
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <span className="inline-flex items-center gap-2 rounded-full border px-3 py-1 text-sm">
      {type.name}
      <button
        type="button"
        disabled={!isManager || busy}
        onClick={toggleTaxable}
        className="text-xs text-muted-foreground hover:text-foreground disabled:cursor-default"
      >
        {type.taxable ? "taxable" : "non-taxable"}
      </button>
      {isManager && (
        <button type="button" disabled={busy} onClick={remove} className="text-destructive">
          <Trash2 className="size-3" />
        </button>
      )}
    </span>
  );
}

type StandingRow = { key: string; allowanceTypeId: string; amount: string };

function PayConfigDialog({
  staffId,
  staffName,
  config,
  allowanceTypes,
  standing,
  onClose,
}: {
  staffId: string;
  staffName: string;
  config: StaffPayConfig | undefined;
  allowanceTypes: AllowanceType[];
  standing: { allowanceTypeId: string; defaultAmount: number }[];
  onClose: () => void;
}) {
  const [position, setPosition] = useState(config?.position ?? "");
  const [department, setDepartment] = useState(config?.department ?? "");
  const [bank, setBank] = useState(config?.bank ?? "");
  const [accountNo, setAccountNo] = useState(config?.accountNo ?? "");
  const [basicSalary, setBasicSalary] = useState(config ? String(config.basicSalary) : "");
  const [paysSsnit, setPaysSsnit] = useState(config?.paysSsnit ?? true);
  const [paysTier2, setPaysTier2] = useState(config?.paysTier2 ?? true);
  const [paysPaye, setPaysPaye] = useState(config?.paysPaye ?? true);
  const [effectiveFrom, setEffectiveFrom] = useState(config?.effectiveFrom ?? firstOfThisMonth());
  const [rows, setRows] = useState<StandingRow[]>(() =>
    standing.map((s, i) => ({
      key: `s${i}`,
      allowanceTypeId: s.allowanceTypeId,
      amount: String(s.defaultAmount),
    })),
  );
  const [submitting, setSubmitting] = useState(false);

  const isCorrection = !!config && effectiveFrom <= config.effectiveFrom;
  const usedTypeIds = new Set(rows.map((r) => r.allowanceTypeId));
  const addableTypes = allowanceTypes.filter((t) => !usedTypeIds.has(t.id));

  async function submit() {
    if (!basicSalary || Number(basicSalary) < 0) {
      toast.error("Enter a basic salary.");
      return;
    }
    const fields: PayConfigFields = {
      position,
      department,
      bank,
      accountNo,
      basicSalary: Number(basicSalary),
      paysSsnit,
      paysTier2,
      paysPaye,
      effectiveFrom,
    };
    setSubmitting(true);
    try {
      await savePayConfig(staffId, fields);
      await setStandingAllowances(
        staffId,
        rows
          .filter((r) => r.allowanceTypeId)
          .map((r) => ({
            allowanceTypeId: r.allowanceTypeId,
            defaultAmount: Number(r.amount) || 0,
          })),
        effectiveFrom > (config?.effectiveFrom ?? "") ? effectiveFrom : today(),
      );
      toast.success(`Pay config saved for ${staffName}`);
      onClose();
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not save the pay config."));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Pay config — {staffName}</DialogTitle>
          <DialogDescription>
            {config
              ? isCorrection
                ? "Editing the current config in place (a correction). Historical payslips are unaffected — every amount is snapshotted when a payslip is generated."
                : "A later effective date records a pay change: the current config is closed and a new one opens, preserving history."
              : "Set this staff member's pay configuration."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Position</Label>
              <Input value={position} onChange={(e) => setPosition(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Department</Label>
              <Input value={department} onChange={(e) => setDepartment(e.target.value)} />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
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
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Bank</Label>
              <Input value={bank} onChange={(e) => setBank(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Account number</Label>
              <Input value={accountNo} onChange={(e) => setAccountNo(e.target.value)} />
            </div>
          </div>

          <div className="rounded-lg border p-3">
            <p className="text-sm font-medium">Statutory deductions</p>
            <p className="mb-2 text-xs text-muted-foreground">
              Turn off for staff exempt from a scheme (e.g. National Service personnel).
            </p>
            <div className="space-y-2">
              <ToggleRow
                label="Pays SSNIT (0.5% employee)"
                checked={paysSsnit}
                onChange={setPaysSsnit}
              />
              <ToggleRow
                label="Pays Tier 2 (5% employee)"
                checked={paysTier2}
                onChange={setPaysTier2}
              />
              <ToggleRow label="Pays PAYE (graduated)" checked={paysPaye} onChange={setPaysPaye} />
            </div>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label>Standing monthly allowances</Label>
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
              <p className="text-xs text-muted-foreground">
                None. These pre-fill each payslip and stay editable per month.
              </p>
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
                    onChange={(e) =>
                      setRows((rs) =>
                        rs.map((r) => (r.key === row.key ? { ...r, amount: e.target.value } : r)),
                      )
                    }
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
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting}>
            {submitting ? "Saving…" : "Save pay config"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ToggleRow({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="flex items-center justify-between text-sm">
      <span>{label}</span>
      <Switch checked={checked} onCheckedChange={onChange} />
    </label>
  );
}
