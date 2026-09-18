import { useEffect, useState } from "react";

import { currency } from "@/data/dashboard";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// Read-only view onto `audit_log`, scoped to one employee. `audit_log` has
// no client-callable write path (trigger-written-only, SECURITY DEFINER —
// see docs/DESIGN.md) and its own RLS select policy already restricts reads
// to Manager/Accountant/Auditor, so this queries the table directly rather
// than going through an RPC. `entity_id` is `text`, and a pay-config change
// is recorded against the *config row's* id, not the employee's — so a
// full per-employee history needs both `entity_table = 'employees'` (the
// employee's own id) and `entity_table = 'employee_pay_config'` (every
// config row ever proposed for this employee, any approval_status, which
// the caller passes in from the already-loaded `employees-store` data
// rather than this module re-querying for it).

type AuditLogRow = Database["public"]["Tables"]["audit_log"]["Row"];

export type AuditLogEntry = {
  id: string;
  actorId: string;
  action: string;
  entityTable: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
  occurredAt: string;
};

function mapRow(row: AuditLogRow): AuditLogEntry {
  return {
    id: row.id,
    actorId: row.actor_id,
    action: row.action,
    entityTable: row.entity_table,
    before: (row.before as Record<string, unknown> | null) ?? null,
    after: (row.after as Record<string, unknown> | null) ?? null,
    occurredAt: row.occurred_at,
  };
}

async function fetchEmployeeAuditHistory(
  employeeId: string,
  payConfigIds: string[],
): Promise<AuditLogEntry[]> {
  const clauses = [`and(entity_table.eq.employees,entity_id.eq.${employeeId})`];
  if (payConfigIds.length > 0) {
    clauses.push(
      `and(entity_table.eq.employee_pay_config,entity_id.in.(${payConfigIds.join(",")}))`,
    );
  }
  const { data, error } = await supabase
    .from("audit_log")
    .select("id, actor_id, action, entity_table, before, after, occurred_at")
    .or(clauses.join(","))
    .order("occurred_at", { ascending: false });
  if (error) throw error;
  return (data as AuditLogRow[]).map(mapRow);
}

/** `payConfigIds` should be every `employee_pay_config` row id for this
 * employee regardless of approval_status (rejected/withdrawn proposals are
 * still part of the history). Re-fetches whenever the id list changes —
 * pass a stable/memoized array. */
export function useEmployeeAuditHistory(employeeId: string, payConfigIds: string[]) {
  const [entries, setEntries] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const configKey = payConfigIds.join(",");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchEmployeeAuditHistory(employeeId, configKey ? configKey.split(",") : [])
      .then((rows) => {
        if (!cancelled) {
          setEntries(rows);
          setLoading(false);
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : String(err));
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [employeeId, configKey]);

  return { entries, loading, error };
}

const ACTION_LABELS: Record<string, string> = {
  employee_created: "Record created",
  employee_approved: "Record approved",
  employee_rejected: "Record rejected",
  employee_suspended: "Suspended",
  employee_reactivated: "Reactivated",
  pay_config_proposed: "Pay change proposed",
  pay_config_approved: "Pay change approved",
  pay_config_amended_and_approved: "Pay change amended & approved",
  pay_config_rejected: "Pay change rejected",
  pay_config_exemptions_changed: "Statutory exemptions changed",
};

export function actionLabel(action: string): string {
  return ACTION_LABELS[action] ?? action;
}

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" ? v : null);
const bool = (v: unknown): boolean | undefined => (typeof v === "boolean" ? v : undefined);
const yesNo = (v: boolean | undefined) => (v === undefined ? null : v ? "Yes" : "No");

/** A short, human-readable summary of what changed — never raw JSON. Each
 * line is only emitted for fields that actually differ (or, where there is
 * no "before" to diff against, the proposed/approved values themselves). */
export function summarizeAuditEntry(
  entry: Pick<AuditLogEntry, "action" | "before" | "after">,
): string[] {
  const { action, before, after } = entry;
  const b = before ?? {};
  const a = after ?? {};

  switch (action) {
    case "employee_created": {
      const lines = [];
      if (str(a.position)) lines.push(`Position: ${a.position}`);
      if (str(a.department)) lines.push(`Department: ${a.department}`);
      return lines.length > 0 ? lines : ["No position or department set yet"];
    }
    case "employee_approved":
    case "employee_suspended":
    case "employee_reactivated":
      return [`${str(b.employment_status) ?? "—"} → ${str(a.employment_status) ?? "—"}`];
    case "employee_rejected":
      return [
        `${str(b.employment_status) ?? "—"} → ${str(a.employment_status) ?? "—"}`,
        ...(str(a.reason) ? [`Reason: ${a.reason}`] : []),
      ];
    case "pay_config_proposed": {
      const lines = [];
      if (num(a.basic_salary) !== null)
        lines.push(`Basic salary: ${currency(num(a.basic_salary)!)}`);
      if (str(a.payment_method)) lines.push(`Payment method: ${a.payment_method}`);
      if (str(a.bank)) lines.push(`Bank/network: ${a.bank}`);
      if (str(a.account_no)) lines.push(`Account/wallet: ${a.account_no}`);
      if (str(a.effective_from)) lines.push(`Effective from: ${a.effective_from}`);
      return lines;
    }
    case "pay_config_approved": {
      const lines = [];
      if (num(a.basic_salary) !== null)
        lines.push(`Basic salary: ${currency(num(a.basic_salary)!)}`);
      if (str(a.payment_method)) lines.push(`Payment method: ${a.payment_method}`);
      if (str(a.bank)) lines.push(`Bank/network: ${a.bank}`);
      if (str(a.account_no)) lines.push(`Account/wallet: ${a.account_no}`);
      return lines.length > 0 ? lines : ["Approved as proposed"];
    }
    case "pay_config_amended_and_approved": {
      const lines = [];
      const beforeSalary = num(b.basic_salary);
      const afterSalary = num(a.basic_salary);
      if (beforeSalary !== afterSalary && beforeSalary !== null && afterSalary !== null) {
        lines.push(`Basic salary: ${currency(beforeSalary)} → ${currency(afterSalary)}`);
      }
      if (str(b.payment_method) !== str(a.payment_method)) {
        lines.push(
          `Payment method: ${str(b.payment_method) ?? "—"} → ${str(a.payment_method) ?? "—"}`,
        );
      }
      if (str(b.bank) !== str(a.bank)) {
        lines.push(`Bank/network: ${str(b.bank) ?? "—"} → ${str(a.bank) ?? "—"}`);
      }
      if (str(b.account_no) !== str(a.account_no)) {
        lines.push(`Account/wallet: ${str(b.account_no) ?? "—"} → ${str(a.account_no) ?? "—"}`);
      }
      return lines.length > 0 ? lines : ["Approved (amendment recorded, but no field differs)"];
    }
    case "pay_config_rejected":
      return str(a.reason) ? [`Reason: ${a.reason}`] : ["Rejected"];
    case "pay_config_exemptions_changed": {
      const lines = [];
      if (bool(b.pays_ssnit) !== bool(a.pays_ssnit)) {
        lines.push(`Pays SSNIT: ${yesNo(bool(b.pays_ssnit))} → ${yesNo(bool(a.pays_ssnit))}`);
      }
      if (bool(b.pays_tier2) !== bool(a.pays_tier2)) {
        lines.push(`Pays Tier 2: ${yesNo(bool(b.pays_tier2))} → ${yesNo(bool(a.pays_tier2))}`);
      }
      if (bool(b.pays_paye) !== bool(a.pays_paye)) {
        lines.push(`Pays PAYE: ${yesNo(bool(b.pays_paye))} → ${yesNo(bool(a.pays_paye))}`);
      }
      return lines;
    }
    default:
      return [];
  }
}
