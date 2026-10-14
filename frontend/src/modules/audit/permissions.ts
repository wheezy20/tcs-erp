import type { StaffRole } from "@/data/auth-store";
import { AUDIT_ACTIONS, isAdmissionsAction } from "@/modules/audit/labels";

// Pure rules for showing the Audit Log. audit_log_select (20261019100000)
// is the real enforcement; these only decide what to render.

/** Manager, Accountant and Auditor; the same roles audit_log_select reads for. */
export function canViewAuditLog(role: StaffRole | undefined | null): boolean {
  return role === "Manager" || role === "Accountant" || role === "Auditor";
}

/** The Accountant reads no admissions audit rows (D-1b). */
export function canSeeAdmissionsAuditRows(role: StaffRole | undefined | null): boolean {
  return role === "Manager" || role === "Auditor";
}

/** The actions offered in the filter: no admissions ones for a role that
 * can't read them, so the filter never offers a choice that always shows
 * nothing. */
export function actionFilterOptions(role: StaffRole | undefined | null): string[] {
  if (!canViewAuditLog(role)) return [];
  return canSeeAdmissionsAuditRows(role)
    ? AUDIT_ACTIONS
    : AUDIT_ACTIONS.filter((a) => !isAdmissionsAction(a));
}
