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
// submit_payroll_run_for_review() / exclude_employee_from_run() (finance
// writers), and reject_payroll_run() / post_payroll_run() (Manager only —
// approval and posting are one step, 20260909150000); allowance_types is a
// plain RLS-gated table.

// ------------------------------------------------------------------ types

export type PayrollRunStatus = "Draft" | "Ready for Review" | "Posted";

export type PayrollRun = {
  id: string;
  branchId: string;
  month: number;
  year: number;
  status: PayrollRunStatus;
  createdByName: string | null;
  submittedById: string | null;
  submittedAt: string | null;
  reviewedById: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
  postedAt: string | null;
  createdAt: string;
};

export type PayrollRunExclusion = {
  id: string;
  payrollRunId: string;
  employeeId: string;
  employeeName: string;
  reason: string | null;
  excludedAt: string;
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
type ExclusionRow = Database["public"]["Tables"]["payroll_run_exclusions"]["Row"] & {
  employees: { name: string } | null;
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
    submittedById: row.submitted_by,
    submittedAt: row.submitted_at,
    reviewedById: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    rejectionReason: row.rejection_reason,
    postedAt: row.posted_at,
    createdAt: row.created_at,
  };
}

function mapExclusion(row: ExclusionRow): PayrollRunExclusion {
  return {
    id: row.id,
    payrollRunId: row.payroll_run_id,
    employeeId: row.employee_id,
    employeeName: row.employees?.name ?? "Unknown",
    reason: row.reason,
    excludedAt: row.excluded_at,
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
  exclusions: PayrollRunExclusion[];
  allowanceTypes: AllowanceType[];
  rates: StatutoryRates[];
  bands: PayeBand[];
  loading: boolean;
  error: string | null;
};

let state: PayrollState = {
  runs: [],
  payslips: [],
  exclusions: [],
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
  const [runs, payslips, exclusions, allowanceTypes, rates, bands] = await Promise.all([
    supabase
      .from("payroll_runs")
      .select("*, staff!payroll_runs_created_by_fkey(name)")
      .order("year", { ascending: false }),
    supabase
      .from("payslips")
      .select("*, employees(name), payslip_allowances(*, allowance_types(name))"),
    supabase.from("payroll_run_exclusions").select("*, employees(name)"),
    supabase.from("allowance_types").select("*").order("position"),
    supabase.from("statutory_rates").select("*").order("effective_from", { ascending: false }),
    supabase.from("paye_bands").select("*").order("band_order"),
  ]);

  for (const r of [runs, payslips, exclusions, allowanceTypes, rates, bands]) {
    if (r.error) throw r.error;
  }

  setState({
    runs: (runs.data as RunRow[]).map(mapRun),
    payslips: (payslips.data as PayslipRow[]).map(mapPayslip),
    exclusions: (exclusions.data as ExclusionRow[]).map(mapExclusion),
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

/** Draft -> Ready for Review. Any finance writer. Server-side rejects a
 * run that isn't complete (an active employee with a config but no payslip
 * and no exclusion). */
export async function submitPayrollRunForReview(id: string): Promise<void> {
  const { error } = await supabase.rpc("submit_payroll_run_for_review", { p_run_id: id });
  if (error) throw error;
  await reload();
}

/** Ready for Review -> Draft, with a required reason. Manager only. */
export async function rejectPayrollRun(id: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("reject_payroll_run", {
    p_run_id: id,
    p_reason: reason,
  });
  if (error) throw error;
  await reload();
}

/** The Manager "approve" step: posts a Ready-for-Review run to the ledger —
 * creates ONE aggregated journal entry and flips status to 'Posted',
 * atomically. Manager only. Reloads the journal store too. */
export async function postPayrollRun(id: string): Promise<void> {
  const { error } = await supabase.rpc("post_payroll_run", { p_run_id: id });
  if (error) throw error;
  await Promise.all([reload(), reloadJournalEntries()]);
}

/** Mark an active employee as deliberately not paid on this Draft run. */
export async function excludeEmployeeFromRun(
  runId: string,
  employeeId: string,
  reason: string,
): Promise<void> {
  const { error } = await supabase.rpc("exclude_employee_from_run", {
    p_run_id: runId,
    p_employee_id: employeeId,
    p_reason: reason || undefined,
  });
  if (error) throw error;
  await reload();
}

/** Undo an exclusion (Draft runs only). */
export async function includeEmployeeInRun(runId: string, employeeId: string): Promise<void> {
  const { error } = await supabase.rpc("include_employee_in_run", {
    p_run_id: runId,
    p_employee_id: employeeId,
  });
  if (error) throw error;
  await reload();
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

async function callCreatePayslip(input: CreatePayslipInput) {
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
}

export async function createPayslip(input: CreatePayslipInput): Promise<void> {
  await callCreatePayslip(input);
  await reload();
}

/** Generate several payslips in one action — each at its standing config
 * with zero adjustments (no overtime / fines / IOU; allowances default to
 * the employee's standing list, passed in by the caller). Continues past a
 * failure and reports the tally; reloads once at the end. */
export async function createPayslipsBulk(
  inputs: CreatePayslipInput[],
): Promise<{ ok: number; failed: { employeeId: string; message: string }[] }> {
  let ok = 0;
  const failed: { employeeId: string; message: string }[] = [];
  for (const input of inputs) {
    try {
      await callCreatePayslip(input);
      ok += 1;
    } catch (err) {
      failed.push({
        employeeId: input.employeeId,
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }
  await reload();
  return { ok, failed };
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
