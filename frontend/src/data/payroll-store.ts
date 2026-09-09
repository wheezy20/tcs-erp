import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import { reloadJournalEntries } from "@/data/journal-store";

// Payroll (Phase 1). One combined store: the data set is small for a
// school (dozens of staff, ~12 runs a year), so everything is loaded
// together and consumers pull what they need out of usePayroll().
//
// RLS is the real access boundary — payroll_runs / payslips / config
// tables: Manager + Accountant write; Auditor reads; Attendant none (see
// 20260908070000_payroll_schema.sql). An Attendant gets empty arrays
// back, not a load error, same as useAccounts().
//
// Writes:
//   * create_payroll_run() / create_payslip() / delete_payslip() are
//     Manager-only RPCs (server-enforced).
//   * allowance_types / staff_pay_config / staff_allowances are plain
//     RLS-gated PostgREST writes (Manager-only per their policies).

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
  staffId: string;
  staffName: string;
  staffPayConfigId: string;
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

export type StaffPayConfig = {
  id: string;
  staffId: string;
  bank: string | null;
  accountNo: string | null;
  basicSalary: number;
  paysSsnit: boolean;
  paysTier2: boolean;
  paysPaye: boolean;
  effectiveFrom: string;
  effectiveTo: string | null;
};

export type StaffAllowance = {
  id: string;
  staffId: string;
  allowanceTypeId: string;
  defaultAmount: number;
  effectiveFrom: string;
  effectiveTo: string | null;
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
  staff: { name: string } | null;
  payslip_allowances: (Database["public"]["Tables"]["payslip_allowances"]["Row"] & {
    allowance_types: { name: string } | null;
  })[];
};
type AllowanceTypeRow = Database["public"]["Tables"]["allowance_types"]["Row"];
type PayConfigRow = Database["public"]["Tables"]["staff_pay_config"]["Row"];
type StaffAllowanceRow = Database["public"]["Tables"]["staff_allowances"]["Row"];
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
    staffId: row.staff_id,
    staffName: row.staff?.name ?? "Unknown",
    staffPayConfigId: row.staff_pay_config_id,
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

function mapPayConfig(row: PayConfigRow): StaffPayConfig {
  return {
    id: row.id,
    staffId: row.staff_id,
    bank: row.bank,
    accountNo: row.account_no,
    basicSalary: num(row.basic_salary),
    paysSsnit: row.pays_ssnit,
    paysTier2: row.pays_tier2,
    paysPaye: row.pays_paye,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
  };
}

function mapStaffAllowance(row: StaffAllowanceRow): StaffAllowance {
  return {
    id: row.id,
    staffId: row.staff_id,
    allowanceTypeId: row.allowance_type_id,
    defaultAmount: num(row.default_amount),
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
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
  payConfigs: StaffPayConfig[];
  staffAllowances: StaffAllowance[];
  rates: StatutoryRates[];
  bands: PayeBand[];
  loading: boolean;
  error: string | null;
};

let state: PayrollState = {
  runs: [],
  payslips: [],
  allowanceTypes: [],
  payConfigs: [],
  staffAllowances: [],
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
  const [runs, payslips, allowanceTypes, payConfigs, staffAllowances, rates, bands] =
    await Promise.all([
      supabase.from("payroll_runs").select("*, staff(name)").order("year", { ascending: false }),
      supabase
        .from("payslips")
        .select("*, staff(name), payslip_allowances(*, allowance_types(name))"),
      supabase.from("allowance_types").select("*").order("position"),
      supabase.from("staff_pay_config").select("*").order("effective_from", { ascending: false }),
      supabase.from("staff_allowances").select("*"),
      supabase.from("statutory_rates").select("*").order("effective_from", { ascending: false }),
      supabase.from("paye_bands").select("*").order("band_order"),
    ]);

  for (const r of [runs, payslips, allowanceTypes, payConfigs, staffAllowances, rates, bands]) {
    if (r.error) throw r.error;
  }

  setState({
    runs: (runs.data as RunRow[]).map(mapRun),
    payslips: (payslips.data as PayslipRow[]).map(mapPayslip),
    allowanceTypes: (allowanceTypes.data as AllowanceTypeRow[]).map(mapAllowanceType),
    payConfigs: (payConfigs.data as PayConfigRow[]).map(mapPayConfig),
    staffAllowances: (staffAllowances.data as StaffAllowanceRow[]).map(mapStaffAllowance),
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

/** Everything payroll, loaded together. RLS scopes it to Manager /
 * Accountant-Auditor; other roles get empty arrays, not an error. */
export function usePayroll() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

/** The current (open-ended) pay config for a staff member, if any. */
export function currentConfigFor(
  configs: StaffPayConfig[],
  staffId: string,
): StaffPayConfig | undefined {
  return configs.find((c) => c.staffId === staffId && c.effectiveTo === null);
}

/** Standing allowances currently in effect for a staff member. */
export function standingAllowancesFor(all: StaffAllowance[], staffId: string): StaffAllowance[] {
  return all.filter((a) => a.staffId === staffId && a.effectiveTo === null);
}

// ------------------------------------------------------------------ mutators

async function getBranchId(): Promise<string> {
  const { data, error } = await supabase.from("branches").select("id").limit(1).single();
  if (error) throw error;
  return data.id;
}

/** UTC-based date arithmetic on a "YYYY-MM-DD" string — no local-timezone
 * drift (new Date("2026-03-01") + getDate()/setDate() runs in local time
 * and can slip a day either side of the boundary). */
function addDaysIso(iso: string, days: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
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
  // Manager + Draft only, enforced by payroll_runs_delete RLS.
  const { error } = await supabase.from("payroll_runs").delete().eq("id", id);
  if (error) throw error;
  await reload();
}

/** Post a Draft run to the Accounting ledger — creates ONE aggregated
 * journal entry (gross → 5140, statutory withholdings → 2310/2320/2330,
 * IOU → 1350, fines → 4910, net → 2300) and flips status to 'Posted',
 * atomically. Manager/Accountant only (require_finance_writer(),
 * server-enforced). Reloads the journal store too so the ledger view and
 * the run page's embedded summary both pick the new entry up. */
export async function postPayrollRun(id: string): Promise<void> {
  const { error } = await supabase.rpc("post_payroll_run", { p_run_id: id });
  if (error) throw error;
  await Promise.all([reload(), reloadJournalEntries()]);
}

export type CreatePayslipInput = {
  payrollRunId: string;
  staffId: string;
  overtimeHours: number;
  overtimeRate: number;
  allowances: { allowanceTypeId: string; amount: number }[];
  fines: number;
  iou: number;
};

export async function createPayslip(input: CreatePayslipInput): Promise<void> {
  const { error } = await supabase.rpc("create_payslip", {
    p_payroll_run_id: input.payrollRunId,
    p_staff_id: input.staffId,
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

// --- staff pay config

export type PayConfigFields = {
  bank: string;
  accountNo: string;
  basicSalary: number;
  paysSsnit: boolean;
  paysTier2: boolean;
  paysPaye: boolean;
  effectiveFrom: string;
};

/** Save a staff member's pay config.
 *
 * v1 model (see docs/JOURNAL.md): if there's no current config, insert one.
 * If there is one and `effectiveFrom` matches it, this is a correction —
 * plain in-place update (payslips snapshot every amount, so a historical
 * payslip is unaffected either way). If `effectiveFrom` is later than the
 * current row's, it's a genuine pay change — close the current row
 * (effective_to = day before) and insert a new open-ended one, preserving
 * history. A dedicated effective-dated "pay change" flow can replace this
 * later; it's enough to exercise the end-to-end payroll flow now. */
export async function savePayConfig(staffId: string, fields: PayConfigFields): Promise<void> {
  const existing = currentConfigFor(state.payConfigs, staffId);

  const payload = {
    bank: fields.bank.trim() || null,
    account_no: fields.accountNo.trim() || null,
    basic_salary: fields.basicSalary,
    pays_ssnit: fields.paysSsnit,
    pays_tier2: fields.paysTier2,
    pays_paye: fields.paysPaye,
  };

  if (!existing) {
    const { error } = await supabase
      .from("staff_pay_config")
      .insert({ staff_id: staffId, effective_from: fields.effectiveFrom, ...payload });
    if (error) throw error;
    await reload();
    return;
  }

  if (fields.effectiveFrom <= existing.effectiveFrom) {
    // Correction to the current row.
    const { error } = await supabase.from("staff_pay_config").update(payload).eq("id", existing.id);
    if (error) throw error;
    await reload();
    return;
  }

  // Genuine pay change: close the current row, open a new one.
  const closeDate = addDaysIso(fields.effectiveFrom, -1);

  const closeRes = await supabase
    .from("staff_pay_config")
    .update({ effective_to: closeDate })
    .eq("id", existing.id);
  if (closeRes.error) throw closeRes.error;

  const insRes = await supabase
    .from("staff_pay_config")
    .insert({ staff_id: staffId, effective_from: fields.effectiveFrom, ...payload });
  if (insRes.error) throw insRes.error;
  await reload();
}

// --- standing (per-staff) allowances

/** Replace a staff member's current standing allowances with `rows`. Full
 * delete-and-reinsert of the open-ended rows for that staff member, the
 * same state-replace shape set_expense_categories() uses (the editor
 * always submits the complete list). */
export async function setStandingAllowances(
  staffId: string,
  rows: { allowanceTypeId: string; defaultAmount: number }[],
  effectiveFrom: string,
): Promise<void> {
  const current = standingAllowancesFor(state.staffAllowances, staffId);
  if (current.length > 0) {
    const del = await supabase
      .from("staff_allowances")
      .delete()
      .in(
        "id",
        current.map((c) => c.id),
      );
    if (del.error) throw del.error;
  }
  if (rows.length > 0) {
    const ins = await supabase.from("staff_allowances").insert(
      rows.map((r) => ({
        staff_id: staffId,
        allowance_type_id: r.allowanceTypeId,
        default_amount: r.defaultAmount,
        effective_from: effectiveFrom,
      })),
    );
    if (ins.error) throw ins.error;
  }
  await reload();
}
