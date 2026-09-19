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
import {
  activeProviders,
  createProvider,
  deleteProvider,
  updateProvider,
  usePaymentProviders,
  type PaymentKind,
  type PaymentProvider,
} from "@/data/payment-providers-store";
import {
  createDepartment,
  createPosition,
  deleteDepartment,
  deletePosition,
  updateDepartment,
  updatePosition,
  useDepartments,
  usePositions,
  type RefListItem,
} from "@/data/org-lists-store";
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
  const { providers } = usePaymentProviders();
  const { items: positions } = usePositions();
  const { items: departments } = useDepartments();

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
              SSNIT/Tier 2 rates confirmed against TCS's actual payroll practice; PAYE bands sourced
              from GRA's published table (gra.gov.gh) — see docs/CONSTRAINTS.md for the one noted
              ambiguity (top-band threshold) and the still-open overtime/bonus tax treatment
              question.
            </span>
          </p>
        ) : (
          <p className="mt-1 text-destructive">No statutory rates configured.</p>
        )}
      </div>

      <AllowanceTypesSection types={allowanceTypes} canWrite={canWrite} />
      <PaymentProvidersSection providers={providers} canWrite={canWrite} />
      <RefListSection
        title="Positions"
        hint="Drives the position dropdown on the employee flow. Stored uppercase."
        placeholder="e.g. Sports Coordinator"
        items={positions}
        canWrite={canWrite}
        onCreate={createPosition}
        onToggle={(id, isActive) => updatePosition(id, { isActive })}
        onDelete={deletePosition}
      />
      <RefListSection
        title="Departments"
        hint="Drives the department dropdown on the employee flow. Stored uppercase."
        placeholder="e.g. Special Needs Unit"
        items={departments}
        canWrite={canWrite}
        onCreate={createDepartment}
        onToggle={(id, isActive) => updateDepartment(id, { isActive })}
        onDelete={deleteDepartment}
      />
    </div>
  );
}

function RefListSection({
  title,
  hint,
  placeholder,
  items,
  canWrite,
  onCreate,
  onToggle,
  onDelete,
}: {
  title: string;
  hint: string;
  placeholder: string;
  items: RefListItem[];
  canWrite: boolean;
  onCreate: (name: string) => Promise<void>;
  onToggle: (id: string, isActive: boolean) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);

  async function add() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      await onCreate(name);
      setName("");
      toast.success(`${title.replace(/s$/, "")} added`);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not add that."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <h3 className="mb-2 text-sm font-semibold text-muted-foreground">{title}</h3>
      <p className="mb-2 text-xs text-muted-foreground">{hint}</p>
      <div className="card-surface p-4">
        <div className="flex flex-wrap gap-2">
          {items.length === 0 && <p className="text-sm text-muted-foreground">Nothing yet.</p>}
          {items.map((it) => (
            <RefListChip
              key={it.id}
              item={it}
              canWrite={canWrite}
              onToggle={onToggle}
              onDelete={onDelete}
            />
          ))}
        </div>
        {canWrite && (
          <div className="mt-4 flex flex-wrap items-end gap-2 border-t pt-4">
            <div className="space-y-1.5">
              <Label className="text-xs">New entry</Label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder={placeholder}
                className="w-56"
              />
            </div>
            <Button size="sm" className="gap-1.5" disabled={busy || !name.trim()} onClick={add}>
              <Plus className="size-3.5" /> Add
            </Button>
          </div>
        )}
      </div>
    </section>
  );
}

function RefListChip({
  item,
  canWrite,
  onToggle,
  onDelete,
}: {
  item: RefListItem;
  canWrite: boolean;
  onToggle: (id: string, isActive: boolean) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  async function toggle() {
    setBusy(true);
    try {
      await onToggle(item.id, !item.isActive);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update that."));
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (!window.confirm(`Delete "${item.name}"?`)) return;
    setBusy(true);
    try {
      await onDelete(item.id);
      toast.success("Deleted");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not delete that."));
    } finally {
      setBusy(false);
    }
  }
  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full border px-3 py-1 text-sm ${
        item.isActive ? "" : "opacity-50"
      }`}
    >
      {item.name}
      {canWrite && (
        <>
          <button
            type="button"
            disabled={busy}
            onClick={toggle}
            className="text-xs text-muted-foreground hover:text-foreground"
          >
            {item.isActive ? "active" : "inactive"}
          </button>
          <button type="button" disabled={busy} onClick={remove} className="text-destructive">
            <Trash2 className="size-3" />
          </button>
        </>
      )}
    </span>
  );
}

function PaymentProvidersSection({
  providers,
  canWrite,
}: {
  providers: PaymentProvider[];
  canWrite: boolean;
}) {
  const [name, setName] = useState("");
  const [kind, setKind] = useState<PaymentKind>("Bank");
  const [busy, setBusy] = useState(false);

  async function add() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      await createProvider(name, kind);
      setName("");
      toast.success(`${kind === "Mobile Money" ? "Network" : "Bank"} added`);
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not add the provider."));
    } finally {
      setBusy(false);
    }
  }

  const banks = providers.filter((p) => p.kind === "Bank");
  const networks = providers.filter((p) => p.kind === "Mobile Money");

  return (
    <section>
      <h3 className="mb-2 text-sm font-semibold text-muted-foreground">Payment providers</h3>
      <p className="mb-2 text-xs text-muted-foreground">
        Drives the bank / mobile-money picker when proposing an employee or a pay-config change.
        Deactivate one to hide it from the picker without losing configs that already reference it.
      </p>
      <div className="card-surface space-y-4 p-4">
        <div>
          <p className="mb-1.5 text-xs font-medium text-muted-foreground">Banks</p>
          <div className="flex flex-wrap gap-2">
            {banks.length === 0 && <p className="text-sm text-muted-foreground">No banks yet.</p>}
            {banks.map((p) => (
              <ProviderChip key={p.id} provider={p} canWrite={canWrite} />
            ))}
          </div>
        </div>
        <div>
          <p className="mb-1.5 text-xs font-medium text-muted-foreground">Mobile money</p>
          <div className="flex flex-wrap gap-2">
            {networks.length === 0 && (
              <p className="text-sm text-muted-foreground">No networks yet.</p>
            )}
            {networks.map((p) => (
              <ProviderChip key={p.id} provider={p} canWrite={canWrite} />
            ))}
          </div>
        </div>

        {canWrite && (
          <div className="flex flex-wrap items-end gap-2 border-t pt-4">
            <div className="space-y-1.5">
              <Label className="text-xs">New provider</Label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g. Bank of Ghana"
                className="w-56"
              />
            </div>
            <label className="flex items-center gap-2 pb-2 text-sm">
              <Switch
                checked={kind === "Mobile Money"}
                onCheckedChange={(v) => setKind(v ? "Mobile Money" : "Bank")}
              />
              Mobile money
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

function ProviderChip({ provider, canWrite }: { provider: PaymentProvider; canWrite: boolean }) {
  const [busy, setBusy] = useState(false);
  async function toggleActive() {
    setBusy(true);
    try {
      await updateProvider(provider.id, { isActive: !provider.isActive });
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not update the provider."));
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (!window.confirm(`Delete "${provider.name}"?`)) return;
    setBusy(true);
    try {
      await deleteProvider(provider.id);
      toast.success("Provider deleted");
    } catch (error) {
      toast.error(getErrorMessage(error, "Could not delete the provider."));
    } finally {
      setBusy(false);
    }
  }
  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full border px-3 py-1 text-sm ${
        provider.isActive ? "" : "opacity-50"
      }`}
    >
      {provider.name}
      {canWrite && (
        <>
          <button
            type="button"
            disabled={busy}
            onClick={toggleActive}
            className="text-xs text-muted-foreground hover:text-foreground"
          >
            {provider.isActive ? "active" : "inactive"}
          </button>
          <button type="button" disabled={busy} onClick={remove} className="text-destructive">
            <Trash2 className="size-3" />
          </button>
        </>
      )}
    </span>
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
