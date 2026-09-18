import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// Employees = everyone TCS pays, independent of ERP login (20260909130000).
// This store owns `employees`, `employee_pay_config` (every approval_status
// — pending proposals are visible to Manager/Accountant/Auditor) and
// `employee_allowances`. Payroll runs / payslips / allowance types / rates
// stay in payroll-store.ts; the run detail and payslip pages use both.
//
// Writes:
//   * propose_* -> Accountant/Manager (require_finance_writer())
//   * approve_* / reject_* -> Manager only
//   * set_employee_status / update_employee_profile /
//     set_pay_config_exemptions / withdraw_pay_config_proposal ->
//     Accountant/Manager, direct (no approval gate)
//   All are SECURITY DEFINER RPCs — employees / employee_pay_config have no
//   authenticated write policy at all.
//   * employee_allowances: plain RLS-gated writes (Manager/Accountant),
//     not approval-gated.

export type EmploymentStatus = "Pending Approval" | "Active" | "Suspended" | "Rejected";
export type PayApprovalStatus = "Pending Approval" | "Active" | "Rejected";
export type PaymentMethod = "Bank" | "Mobile Money";

export type Employee = {
  id: string;
  branchId: string;
  name: string;
  phone: string | null;
  position: string | null;
  department: string | null;
  status: EmploymentStatus;
  proposedById: string | null;
  reviewedById: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
  createdAt: string;
};

export type PayConfig = {
  id: string;
  employeeId: string;
  /** "Bank": `bank` is the bank name, `accountNo` the account number.
   * "Mobile Money": `bank` is the network name, `accountNo` the wallet
   * phone. The column names are shared; only the labels differ. */
  paymentMethod: PaymentMethod;
  bank: string | null;
  accountNo: string | null;
  basicSalary: number;
  paysSsnit: boolean;
  paysTier2: boolean;
  paysPaye: boolean;
  effectiveFrom: string;
  effectiveTo: string | null;
  approvalStatus: PayApprovalStatus;
  proposedById: string | null;
  reviewedById: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
  createdAt: string;
};

export type EmployeeAllowance = {
  id: string;
  employeeId: string;
  allowanceTypeId: string;
  defaultAmount: number;
  effectiveFrom: string;
  effectiveTo: string | null;
};

// ------------------------------------------------------------------ mapping

type EmployeeRow = Database["public"]["Tables"]["employees"]["Row"];
type PayConfigRow = Database["public"]["Tables"]["employee_pay_config"]["Row"];
type AllowanceRow = Database["public"]["Tables"]["employee_allowances"]["Row"];

const num = (v: number | string | null | undefined) => Number(v ?? 0);

function mapEmployee(row: EmployeeRow): Employee {
  return {
    id: row.id,
    branchId: row.branch_id,
    name: row.name,
    phone: row.phone,
    position: row.position,
    department: row.department,
    status: row.employment_status as EmploymentStatus,
    proposedById: row.proposed_by,
    reviewedById: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    rejectionReason: row.rejection_reason,
    createdAt: row.created_at,
  };
}

function mapConfig(row: PayConfigRow): PayConfig {
  return {
    id: row.id,
    employeeId: row.employee_id,
    paymentMethod: (row.payment_method as PaymentMethod) ?? "Bank",
    bank: row.bank,
    accountNo: row.account_no,
    basicSalary: num(row.basic_salary),
    paysSsnit: row.pays_ssnit,
    paysTier2: row.pays_tier2,
    paysPaye: row.pays_paye,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    approvalStatus: row.approval_status as PayApprovalStatus,
    proposedById: row.proposed_by,
    reviewedById: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    rejectionReason: row.rejection_reason,
    createdAt: row.created_at,
  };
}

function mapAllowance(row: AllowanceRow): EmployeeAllowance {
  return {
    id: row.id,
    employeeId: row.employee_id,
    allowanceTypeId: row.allowance_type_id,
    defaultAmount: num(row.default_amount),
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
  };
}

// ------------------------------------------------------------------ store

type State = {
  employees: Employee[];
  configs: PayConfig[];
  allowances: EmployeeAllowance[];
  loading: boolean;
  error: string | null;
};

let state: State = { employees: [], configs: [], allowances: [], loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function load() {
  const [employees, configs, allowances] = await Promise.all([
    supabase.from("employees").select("*").order("name"),
    supabase.from("employee_pay_config").select("*").order("effective_from", { ascending: false }),
    supabase.from("employee_allowances").select("*"),
  ]);
  for (const r of [employees, configs, allowances]) {
    if (r.error) throw r.error;
  }
  setState({
    employees: (employees.data as EmployeeRow[]).map(mapEmployee),
    configs: (configs.data as PayConfigRow[]).map(mapConfig),
    allowances: (allowances.data as AllowanceRow[]).map(mapAllowance),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = load().catch((err) => {
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

/** Everyone TCS pays, their pay configs (all approval states) and standing
 * allowances. RLS scopes it to Manager / Accountant / Auditor; other roles
 * get empty arrays. */
export function useEmployees() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

// ------------------------------------------------------------------ selectors

/** The current approved, open-ended pay config for an employee. */
export function currentConfigFor(configs: PayConfig[], employeeId: string): PayConfig | undefined {
  return configs.find(
    (c) => c.employeeId === employeeId && c.approvalStatus === "Active" && c.effectiveTo === null,
  );
}

/** A pending pay-change proposal for an employee, if one is outstanding. */
export function pendingConfigFor(configs: PayConfig[], employeeId: string): PayConfig | undefined {
  return configs.find(
    (c) => c.employeeId === employeeId && c.approvalStatus === "Pending Approval",
  );
}

/** Approved config rows for an employee, newest effective_from first. */
export function configHistoryFor(configs: PayConfig[], employeeId: string): PayConfig[] {
  return configs
    .filter((c) => c.employeeId === employeeId && c.approvalStatus === "Active")
    .sort((a, b) => (a.effectiveFrom < b.effectiveFrom ? 1 : -1));
}

/** Split pending pay configs into *bundled* (proposed together with a
 * still-pending employee record — approved/rejected via that record) and
 * *standalone* salary/bank changes on an already-active employee. The
 * Manager approval UI uses this so a bundled new hire shows one
 * Approve/Reject, not two competing pairs. */
export function splitPendingConfigs(employees: Employee[], pendingConfigs: PayConfig[]) {
  const isPendingEmp = (id: string) =>
    employees.find((e) => e.id === id)?.status === "Pending Approval";
  const bundledByEmployee = new Map<string, PayConfig>();
  const standalone: PayConfig[] = [];
  for (const c of pendingConfigs) {
    if (isPendingEmp(c.employeeId)) bundledByEmployee.set(c.employeeId, c);
    else standalone.push(c);
  }
  return { bundledByEmployee, standalone };
}

/** Standing allowances currently in effect for an employee. */
export function standingAllowancesFor(
  all: EmployeeAllowance[],
  employeeId: string,
): EmployeeAllowance[] {
  return all.filter((a) => a.employeeId === employeeId && a.effectiveTo === null);
}

// ------------------------------------------------------------------ mutators

async function getBranchId(): Promise<string> {
  const { data, error } = await supabase.from("branches").select("id").limit(1).single();
  if (error) throw error;
  return data.id;
}

export type ProposeEmployeeInput = {
  name: string;
  phone?: string;
  position?: string;
  department?: string;
  staffId?: string;
  /** Optional bundled initial pay config (one proposal, one approval). */
  basicSalary?: number;
  paymentMethod?: PaymentMethod;
  bank?: string;
  accountNo?: string;
  paysSsnit?: boolean;
  paysTier2?: boolean;
  paysPaye?: boolean;
  effectiveFrom?: string;
};

export async function proposeEmployee(input: ProposeEmployeeInput): Promise<void> {
  const branchId = await getBranchId();
  const { error } = await supabase.rpc("propose_employee", {
    p_name: input.name,
    p_branch_id: branchId,
    p_phone: input.phone ?? "",
    p_position: input.position ?? "",
    p_department: input.department ?? "",
    p_staff_id: input.staffId ?? undefined,
    p_basic_salary: input.basicSalary ?? undefined,
    p_payment_method: input.paymentMethod ?? "Bank",
    p_bank: input.bank ?? "",
    p_account_no: input.accountNo ?? "",
    p_pays_ssnit: input.paysSsnit ?? true,
    p_pays_tier2: input.paysTier2 ?? true,
    p_pays_paye: input.paysPaye ?? true,
    p_effective_from: input.effectiveFrom ?? undefined,
  });
  if (error) throw error;
  await reload();
}

/** A Manager's amendment to a proposed pay config, applied in the same
 * approval statement so the audit trigger can diff original-vs-approved
 * (20260918, pay_config_amended_and_approved). `undefined`/omitted means
 * approve-as-submitted, unchanged from before this existed. */
export type PayConfigOverride = {
  basicSalary: number;
  paymentMethod: PaymentMethod;
  bank: string;
  accountNo: string;
};

export async function approveEmployee(id: string, override?: PayConfigOverride): Promise<void> {
  const { error } = await supabase.rpc("approve_employee", {
    p_employee_id: id,
    p_basic_salary: override?.basicSalary,
    p_payment_method: override?.paymentMethod,
    p_bank: override?.bank,
    p_account_no: override?.accountNo,
  });
  if (error) throw error;
  await reload();
}

export async function rejectEmployee(id: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("reject_employee", { p_employee_id: id, p_reason: reason });
  if (error) throw error;
  await reload();
}

export async function setEmployeeStatus(id: string, status: "Active" | "Suspended"): Promise<void> {
  const { error } = await supabase.rpc("set_employee_status", {
    p_employee_id: id,
    p_status: status,
  });
  if (error) throw error;
  await reload();
}

export async function updateEmployeeProfile(
  id: string,
  patch: { phone: string; position: string; department: string },
): Promise<void> {
  const { error } = await supabase.rpc("update_employee_profile", {
    p_employee_id: id,
    p_phone: patch.phone,
    p_position: patch.position,
    p_department: patch.department,
  });
  if (error) throw error;
  await reload();
}

export type ProposePayConfigInput = {
  employeeId: string;
  effectiveFrom: string;
  basicSalary: number;
  paymentMethod: PaymentMethod;
  bank: string;
  accountNo: string;
  paysSsnit: boolean;
  paysTier2: boolean;
  paysPaye: boolean;
};

export async function proposePayConfigChange(input: ProposePayConfigInput): Promise<void> {
  const { error } = await supabase.rpc("propose_pay_config_change", {
    p_employee_id: input.employeeId,
    p_effective_from: input.effectiveFrom,
    p_basic_salary: input.basicSalary,
    p_payment_method: input.paymentMethod,
    p_bank: input.bank,
    p_account_no: input.accountNo,
    p_pays_ssnit: input.paysSsnit,
    p_pays_tier2: input.paysTier2,
    p_pays_paye: input.paysPaye,
  });
  if (error) throw error;
  await reload();
}

export async function approvePayConfig(
  configId: string,
  override?: PayConfigOverride,
): Promise<void> {
  const { error } = await supabase.rpc("approve_pay_config", {
    p_config_id: configId,
    p_basic_salary: override?.basicSalary,
    p_payment_method: override?.paymentMethod,
    p_bank: override?.bank,
    p_account_no: override?.accountNo,
  });
  if (error) throw error;
  await reload();
}

export async function rejectPayConfig(configId: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("reject_pay_config", {
    p_config_id: configId,
    p_reason: reason,
  });
  if (error) throw error;
  await reload();
}

export async function withdrawPayConfigProposal(configId: string): Promise<void> {
  const { error } = await supabase.rpc("withdraw_pay_config_proposal", { p_config_id: configId });
  if (error) throw error;
  await reload();
}

export async function setPayConfigExemptions(
  employeeId: string,
  paysSsnit: boolean,
  paysTier2: boolean,
  paysPaye: boolean,
): Promise<void> {
  const { error } = await supabase.rpc("set_pay_config_exemptions", {
    p_employee_id: employeeId,
    p_pays_ssnit: paysSsnit,
    p_pays_tier2: paysTier2,
    p_pays_paye: paysPaye,
  });
  if (error) throw error;
  await reload();
}

/** Replace an employee's standing allowances with `rows` — full
 * delete-and-reinsert of the open-ended rows. Not approval-gated: plain
 * RLS write (Manager/Accountant). */
export async function setStandingAllowances(
  employeeId: string,
  rows: { allowanceTypeId: string; defaultAmount: number }[],
  effectiveFrom: string,
): Promise<void> {
  const current = standingAllowancesFor(state.allowances, employeeId);
  if (current.length > 0) {
    const del = await supabase
      .from("employee_allowances")
      .delete()
      .in(
        "id",
        current.map((c) => c.id),
      );
    if (del.error) throw del.error;
  }
  if (rows.length > 0) {
    const ins = await supabase.from("employee_allowances").insert(
      rows.map((r) => ({
        employee_id: employeeId,
        allowance_type_id: r.allowanceTypeId,
        default_amount: r.defaultAmount,
        effective_from: effectiveFrom,
      })),
    );
    if (ins.error) throw ins.error;
  }
  await reload();
}
