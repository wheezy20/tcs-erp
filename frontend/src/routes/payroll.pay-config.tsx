import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import {
  createAllowanceType,
  deleteAllowanceType,
  updateAllowanceType,
  usePayroll,
  type AllowanceType,
} from "@/data/payroll-store";
import { getErrorMessage } from "@/lib/utils";

export const Route = createFileRoute("/payroll/pay-config")({
  component: PayrollSetupPage,
});

// Payroll setup: statutory rates in effect + the school-editable allowance
// type list. Per-employee pay configuration moved to the Employees screens
// (20260909130000), behind the propose/approve workflow.
function PayrollSetupPage() {
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const { allowanceTypes, rates, bands, loading } = usePayroll();

  const activeRates = rates[0];

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

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

      <AllowanceTypesSection types={allowanceTypes} canWrite={canWrite} />
    </div>
  );
}

function AllowanceTypesSection({ types, canWrite }: { types: AllowanceType[]; canWrite: boolean }) {
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
            <AllowanceTypeChip key={t.id} type={t} canWrite={canWrite} />
          ))}
        </div>

        {canWrite && (
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

function AllowanceTypeChip({ type, canWrite }: { type: AllowanceType; canWrite: boolean }) {
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
        disabled={!canWrite || busy}
        onClick={toggleTaxable}
        className="text-xs text-muted-foreground hover:text-foreground disabled:cursor-default"
      >
        {type.taxable ? "taxable" : "non-taxable"}
      </button>
      {canWrite && (
        <button type="button" disabled={busy} onClick={remove} className="text-destructive">
          <Trash2 className="size-3" />
        </button>
      )}
    </span>
  );
}
