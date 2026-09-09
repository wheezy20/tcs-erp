import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import { reloadJournalEntries } from "@/data/journal-store";

// Payroll runs + payslips + allowance types + statutory rates. Employees,
// their pay configs and standing allowances live in employees-store.ts
// (20260909130000) — the run detail and payslip pages use both stores.
//
// RLS is the real access boundary: Manager + Accountant write; Auditor
// reads; Attendant gets empty arrays. Writes go through
// create_payroll_run() / create_payslip() / delete_payslip() /
// post_payroll_run() (Manager+Accountant RPCs); allowance_types is a plain
// RLS-gated table.

// ------------------------------------------------------------------ types

export type PayrollRunStatus = "Draft" | "Posted";

export type PayrollRun = {
  id: string;
  branchId: string;
  month: number;
  year: number;
  status: PayrollRunStatus;
  createdByName: string | null;
  postedAt: string | null;
  createdAt: string;
};

export type Payslip = {
  id: string;
  payrollRunId: string;
  employeeId: string;
  employeeName: string;
  employeePayConfigId: string;
  basicSalary: number;
  overtimeHours: number;
  overtimeRate: number;
  overtimePay: number;
  totalAllowances: number;
  totalEarning: number;
  grossSalary: number;
  taxableIncome: number;
  tax: number;
  tier2: number;
  ssnit: number;
  /** Employer's 13% SSNIT contribution — snapshot at generation, gated on
   * the same pays_ssnit flag as the employee side. NOT part of net-pay
   * math; it never touches the employee. 0 for exempt staff. */
  ssnitEmployer: number;
  fines: number;
  iou: number;
  totalDeductions: number;
  netPay: number;
  generatedAt: string;
  allowances: PayslipAllowanceLine[];
};

export type PayslipAllowanceLine = {
  id: string;
  allowanceTypeId: string;
  allowanceTypeName: string;
  amount: number;
  note: string | null;
};

export type AllowanceType = {
  id: string;
  branchId: string;
  name: string;
  taxable: boolean;
  position: number;
};

export type StatutoryRates = {
  id: string;
  ssnitEmployeePct: number;
  ssnitEmployerPct: number;
  tier2EmployeePct: number;
  tier2EmployerPct: number;
  effectiveFrom: string;
};

export type PayeBand = {
  id: string;
  effectiveFrom: string;
  lowerBound: number;
  upperBound: number | null;
  rate: number;
  bandOrder: number;
};

// ------------------------------------------------------------------ mapping

type RunRow = Database["public"]["Tables"]["payroll_runs"]["Row"] & {
  staff: { name: string } | null;
};
type PayslipRow = Database["public"]["Tables"]["payslips"]["Row"] & {
  employees: { name: string } | null;
  payslip_allowances: (Database["public"]["Tables"]["payslip_allowances"]["Row"] & {
    allowance_types: { name: string } | null;
  })[];
};
type AllowanceTypeRow = Database["public"]["Tables"]["allowance_types"]["Row"];
type RatesRow = Database["public"]["Tables"]["statutory_rates"]["Row"];
type BandRow = Database["public"]["Tables"]["paye_bands"]["Row"];

const num = (v: number | string | null | undefined) => Number(v ?? 0);

function mapRun(row: RunRow): PayrollRun {
  return {
    id: row.id,
    branchId: row.branch_id,
    month: row.month,
    year: row.year,
    status: row.status as PayrollRunStatus,
    createdByName: row.staff?.name ?? null,
    postedAt: row.posted_at,
    createdAt: row.created_at,
  };
}

function mapPayslip(row: PayslipRow): Payslip {
  return {
    id: row.id,
    payrollRunId: row.payroll_run_id,
    employeeId: row.employee_id,
    employeeName: row.employees?.name ?? "Unknown",
    employeePayConfigId: row.employee_pay_config_id,
    basicSalary: num(row.basic_salary),
    overtimeHours: num(row.overtime_hours),
    overtimeRate: num(row.overtime_rate),
    overtimePay: num(row.overtime_pay),
    totalAllowances: num(row.total_allowances),
    totalEarning: num(row.total_earning),
    grossSalary: num(row.gross_salary),
    taxableIncome: num(row.taxable_income),
    tax: num(row.tax),
    tier2: num(row.tier2),
    ssnit: num(row.ssnit),
    ssnitEmployer: num(row.ssnit_employer),
    fines: num(row.fines),
    iou: num(row.iou),
    totalDeductions: num(row.total_deductions),
    netPay: num(row.net_pay),
    generatedAt: row.generated_at,
    allowances: (row.payslip_allowances ?? []).map((a) => ({
      id: a.id,
      allowanceTypeId: a.allowance_type_id,
      allowanceTypeName: a.allowance_types?.name ?? "Allowance",
      amount: num(a.amount),
      note: a.note,
    })),
  };
}

function mapAllowanceType(row: AllowanceTypeRow): AllowanceType {
  return {
    id: row.id,
    branchId: row.branch_id,
    name: row.name,
    taxable: row.taxable,
    position: row.position,
  };
}

function mapRates(row: RatesRow): StatutoryRates {
  return {
    id: row.id,
    ssnitEmployeePct: num(row.ssnit_employee_pct),
    ssnitEmployerPct: num(row.ssnit_employer_pct),
    tier2EmployeePct: num(row.tier2_employee_pct),
    tier2EmployerPct: num(row.tier2_employer_pct),
    effectiveFrom: row.effective_from,
  };
}

function mapBand(row: BandRow): PayeBand {
  return {
    id: row.id,
    effectiveFrom: row.effective_from,
    lowerBound: num(row.lower_bound),
    upperBound: row.upper_bound === null ? null : num(row.upper_bound),
    rate: num(row.rate),
    bandOrder: row.band_order,
  };
}

// ------------------------------------------------------------------ store

type PayrollState = {
  runs: PayrollRun[];
  payslips: Payslip[];
  allowanceTypes: AllowanceType[];
  rates: StatutoryRates[];
  bands: PayeBand[];
  loading: boolean;
  error: string | null;
};

let state: PayrollState = {
  runs: [],
  payslips: [],
  allowanceTypes: [],
  rates: [],
  bands: [],
  loading: true,
  error: null,
};

const listeners = new Set<() => void>();

function setState(next: PayrollState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadPayroll() {
  const [runs, payslips, allowanceTypes, rates, bands] = await Promise.all([
    supabase.from("payroll_runs").select("*, staff(name)").order("year", { ascending: false }),
    supabase
      .from("payslips")
      .select("*, employees(name), payslip_allowances(*, allowance_types(name))"),
    supabase.from("allowance_types").select("*").order("position"),
    supabase.from("statutory_rates").select("*").order("effective_from", { ascending: false }),
    supabase.from("paye_bands").select("*").order("band_order"),
  ]);

  for (const r of [runs, payslips, allowanceTypes, rates, bands]) {
    if (r.error) throw r.error;
  }

  setState({
    runs: (runs.data as RunRow[]).map(mapRun),
    payslips: (payslips.data as PayslipRow[]).map(mapPayslip),
    allowanceTypes: (allowanceTypes.data as AllowanceTypeRow[]).map(mapAllowanceType),
    rates: (rates.data as RatesRow[]).map(mapRates),
    bands: (bands.data as BandRow[]).map(mapBand),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadPayroll().catch((err) => {
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    });
  }
  return loadPromise;
}

async function reload() {
  loadPromise = null;
  await ensureLoaded();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

/** Runs, payslips, allowance types and statutory rates. RLS scopes it to
 * Manager / Accountant / Auditor; other roles get empty arrays. */
export function usePayroll() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

// ------------------------------------------------------------------ mutators

async function getBranchId(): Promise<string> {
  const { data, error } = await supabase.from("branches").select("id").limit(1).single();
  if (error) throw error;
  return data.id;
}

export async function createPayrollRun(month: number, year: number): Promise<PayrollRun> {
  const branchId = await getBranchId();
  const { data, error } = await supabase.rpc("create_payroll_run", {
    p_branch_id: branchId,
    p_month: month,
    p_year: year,
  });
  if (error) throw error;
  const row = (Array.isArray(data) ? data[0] : data) as { id: string } | null;
  if (!row?.id) throw new Error("Run created but no id returned.");
  await reload();
  const created = state.runs.find((r) => r.id === row.id);
  if (!created) throw new Error("Run created but not found after reload.");
  return created;
}

export async function deletePayrollRun(id: string): Promise<void> {
  // Manager + Accountant + Draft only, enforced by payroll_runs_delete RLS.
  const { error } = await supabase.from("payroll_runs").delete().eq("id", id);
  if (error) throw error;
  await reload();
}

/** Post a Draft run to the Accounting ledger — creates ONE aggregated
 * journal entry and flips status to 'Posted', atomically. Manager/Accountant
 * only. Reloads the journal store too. */
export async function postPayrollRun(id: string): Promise<void> {
  const { error } = await supabase.rpc("post_payroll_run", { p_run_id: id });
  if (error) throw error;
  await Promise.all([reload(), reloadJournalEntries()]);
}

export type CreatePayslipInput = {
  payrollRunId: string;
  employeeId: string;
  overtimeHours: number;
  overtimeRate: number;
  allowances: { allowanceTypeId: string; amount: number }[];
  fines: number;
  iou: number;
};

export async function createPayslip(input: CreatePayslipInput): Promise<void> {
  const { error } = await supabase.rpc("create_payslip", {
    p_payroll_run_id: input.payrollRunId,
    p_employee_id: input.employeeId,
    p_overtime_hours: input.overtimeHours,
    p_overtime_rate: input.overtimeRate,
    p_allowances: input.allowances.map((a) => ({
      allowance_type_id: a.allowanceTypeId,
      amount: a.amount,
    })),
    p_fines: input.fines,
    p_iou: input.iou,
  });
  if (error) throw error;
  await reload();
}

export async function deletePayslip(id: string): Promise<void> {
  const { error } = await supabase.rpc("delete_payslip", { p_payslip_id: id });
  if (error) throw error;
  await reload();
}

// --- allowance types

export async function createAllowanceType(name: string, taxable: boolean): Promise<void> {
  const branchId = await getBranchId();
  const position = state.allowanceTypes.length;
  const { error } = await supabase
    .from("allowance_types")
    .insert({ branch_id: branchId, name: name.trim(), taxable, position });
  if (error) throw error;
  await reload();
}

export async function updateAllowanceType(
  id: string,
  patch: { name?: string; taxable?: boolean },
): Promise<void> {
  const { error } = await supabase
    .from("allowance_types")
    .update({
      ...(patch.name !== undefined ? { name: patch.name.trim() } : {}),
      ...(patch.taxable !== undefined ? { taxable: patch.taxable } : {}),
    })
    .eq("id", id);
  if (error) throw error;
  await reload();
}

export async function deleteAllowanceType(id: string): Promise<void> {
  const { error } = await supabase.from("allowance_types").delete().eq("id", id);
  if (error) throw error;
  await reload();
}
