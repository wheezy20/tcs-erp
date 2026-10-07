import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import { reloadJournalEntries } from "@/data/journal-store";
import { getErrorMessage } from "@/lib/utils";

// Staff advances (IOU loans), 20261008100000. A loan is recorded once and
// repaid automatically by create_payslip() through the payslip's IOU line
// until its balance reaches 0 or it is paused or cancelled.
//
// Every figure comes from the database: balance, display status (Settled
// is computed, never stored), what a payslip would deduct, and the balance
// after a payslip. The client never computes a balance or an instalment.
//
// RLS is the real access boundary: Manager, Accountant and Auditor read;
// nobody writes the tables directly. Manager + Accountant propose and
// withdraw through the RPCs below; only a Manager approves or rejects.
// Approving an advance posts the payout (Dr 1350 / Cr the payout account);
// account 1350 is not yet confirmed by the accountant.

// ------------------------------------------------------------------ types

export type StaffAdvanceStatus = "Proposed" | "Active" | "Paused" | "Cancelled" | "Rejected";
export type StaffAdvanceDisplayStatus = StaffAdvanceStatus | "Settled";
export type PayoutMethod = "Cash" | "Mobile Money" | "Bank Transfer";
export type ChangeKind = "Pause" | "Resume" | "Cancel" | "Instalment";

export type StaffAdvance = {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeStatus: string;
  amount: number;
  instalment: number;
  firstRepaymentMonth: string;
  disbursedOn: string;
  disbursementMethod: PayoutMethod;
  bankAccountId: string | null;
  note: string | null;
  status: StaffAdvanceStatus;
  displayStatus: StaffAdvanceDisplayStatus;
  repaid: number;
  balance: number;
  proposedById: string | null;
  proposedAt: string;
  reviewedById: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
};

export type StaffAdvanceChangeRequest = {
  id: string;
  advanceId: string;
  kind: ChangeKind;
  newInstalment: number | null;
  reason: string | null;
  status: "Pending Approval" | "Approved" | "Rejected";
  proposedById: string | null;
  proposedAt: string;
  reviewedById: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
};

/** One advance as create_payslip would treat it for a given run, before
 * the net-pay cap: `due` is what it would deduct, or `skipReason` why not. */
export type AdvanceDeductionPreview = {
  advanceId: string;
  instalment: number;
  balance: number;
  due: number;
  skipReason: string | null;
};

/** One advance repayment on a payslip, with the balance remaining after
 * that payslip's month (computed by the database at display time). */
export type PayslipAdvanceLine = {
  advanceId: string;
  advanceAmount: number;
  disbursedOn: string;
  instalmentDue: number;
  amount: number;
  balanceAfter: number;
};

type SummaryRow = Database["public"]["Functions"]["staff_advance_summary"]["Returns"][number];
type ChangeRow = Database["public"]["Tables"]["staff_advance_change_requests"]["Row"];

const num = (v: number | string | null | undefined) => Number(v ?? 0);

function mapAdvance(row: SummaryRow): StaffAdvance {
  return {
    id: row.id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    employeeStatus: row.employee_status,
    amount: num(row.amount),
    instalment: num(row.instalment),
    firstRepaymentMonth: row.first_repayment_month,
    disbursedOn: row.disbursed_on,
    disbursementMethod: row.disbursement_method as PayoutMethod,
    bankAccountId: row.bank_account_id,
    note: row.note,
    status: row.status as StaffAdvanceStatus,
    displayStatus: row.display_status as StaffAdvanceDisplayStatus,
    repaid: num(row.repaid),
    balance: num(row.balance),
    proposedById: row.proposed_by,
    proposedAt: row.proposed_at,
    reviewedById: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    rejectionReason: row.rejection_reason,
  };
}

function mapChange(row: ChangeRow): StaffAdvanceChangeRequest {
  return {
    id: row.id,
    advanceId: row.advance_id,
    kind: row.kind as ChangeKind,
    newInstalment: row.new_instalment === null ? null : num(row.new_instalment),
    reason: row.reason,
    status: row.status as StaffAdvanceChangeRequest["status"],
    proposedById: row.proposed_by,
    proposedAt: row.proposed_at,
    reviewedById: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    rejectionReason: row.rejection_reason,
  };
}

// ------------------------------------------------------------------ store

type StaffAdvancesState = {
  advances: StaffAdvance[];
  changeRequests: StaffAdvanceChangeRequest[];
  loading: boolean;
  error: string | null;
};

let state: StaffAdvancesState = { advances: [], changeRequests: [], loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: StaffAdvancesState) {
  state = next;
  listeners.forEach((l) => l());
}

let loadPromise: Promise<void> | null = null;

async function loadStaffAdvances() {
  const [advances, changes] = await Promise.all([
    supabase.rpc("staff_advance_summary", {}),
    supabase
      .from("staff_advance_change_requests")
      .select("*")
      .order("proposed_at", { ascending: false }),
  ]);
  if (advances.error) throw advances.error;
  if (changes.error) throw changes.error;
  setState({
    advances: (advances.data ?? []).map(mapAdvance),
    changeRequests: (changes.data ?? []).map(mapChange),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadStaffAdvances().catch((err) => {
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: getErrorMessage(err, "Could not load staff advances."),
      });
      throw err;
    });
  }
  return loadPromise;
}

export async function reloadStaffAdvances() {
  loadPromise = null;
  await ensureLoaded();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded().catch(() => {});
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

export function useStaffAdvances() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

// ------------------------------------------------------------------ reads

export async function fetchAdvanceDeductionPreview(
  employeeId: string,
  payrollRunId: string,
): Promise<AdvanceDeductionPreview[]> {
  const { data, error } = await supabase.rpc("staff_advance_deduction_preview", {
    p_employee_id: employeeId,
    p_payroll_run_id: payrollRunId,
  });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    advanceId: r.advance_id,
    instalment: num(r.instalment),
    balance: num(r.balance),
    due: num(r.due),
    skipReason: r.skip_reason,
  }));
}

export async function fetchPayslipAdvanceLines(payslipId: string): Promise<PayslipAdvanceLine[]> {
  const { data, error } = await supabase.rpc("staff_advance_payslip_lines", {
    p_payslip_id: payslipId,
  });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    advanceId: r.advance_id,
    advanceAmount: num(r.advance_amount),
    disbursedOn: r.disbursed_on,
    instalmentDue: num(r.instalment_due),
    amount: num(r.amount),
    balanceAfter: num(r.balance_after),
  }));
}

// ------------------------------------------------------------------ writes

export type NewStaffAdvance = {
  employeeId: string;
  amount: number;
  instalment: number;
  /** Any day in the month; the database keeps the 1st. */
  firstRepaymentMonth: string;
  disbursedOn: string;
  method: PayoutMethod;
  bankAccountId: string | null;
  note: string;
};

export async function proposeStaffAdvance(input: NewStaffAdvance): Promise<void> {
  const { error } = await supabase.rpc("propose_staff_advance", {
    p_employee_id: input.employeeId,
    p_amount: input.amount,
    p_instalment: input.instalment,
    p_first_repayment_month: input.firstRepaymentMonth,
    p_disbursed_on: input.disbursedOn,
    p_method: input.method,
    p_bank_account_id: input.bankAccountId ?? undefined,
    p_note: input.note || undefined,
  });
  if (error) throw error;
  await reloadStaffAdvances();
}

/** Manager only. Also posts the payout journal entry. */
export async function approveStaffAdvance(id: string): Promise<void> {
  const { error } = await supabase.rpc("approve_staff_advance", { p_advance_id: id });
  if (error) throw error;
  await reloadStaffAdvances();
  await reloadJournalEntries().catch(() => {});
}

export async function rejectStaffAdvance(id: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("reject_staff_advance", {
    p_advance_id: id,
    p_reason: reason,
  });
  if (error) throw error;
  await reloadStaffAdvances();
}

export async function withdrawStaffAdvanceProposal(id: string): Promise<void> {
  const { error } = await supabase.rpc("withdraw_staff_advance_proposal", { p_advance_id: id });
  if (error) throw error;
  await reloadStaffAdvances();
}

export async function proposeStaffAdvanceChange(input: {
  advanceId: string;
  kind: ChangeKind;
  newInstalment: number | null;
  reason: string;
}): Promise<void> {
  const { error } = await supabase.rpc("propose_staff_advance_change", {
    p_advance_id: input.advanceId,
    p_kind: input.kind,
    p_new_instalment: input.newInstalment ?? undefined,
    p_reason: input.reason || undefined,
  });
  if (error) throw error;
  await reloadStaffAdvances();
}

export async function approveStaffAdvanceChange(id: string): Promise<void> {
  const { error } = await supabase.rpc("approve_staff_advance_change", { p_request_id: id });
  if (error) throw error;
  await reloadStaffAdvances();
}

export async function rejectStaffAdvanceChange(id: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("reject_staff_advance_change", {
    p_request_id: id,
    p_reason: reason,
  });
  if (error) throw error;
  await reloadStaffAdvances();
}

export async function withdrawStaffAdvanceChange(id: string): Promise<void> {
  const { error } = await supabase.rpc("withdraw_staff_advance_change", { p_request_id: id });
  if (error) throw error;
  await reloadStaffAdvances();
}
