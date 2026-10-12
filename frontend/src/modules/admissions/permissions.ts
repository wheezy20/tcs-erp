// Which admissions screens and controls a signed-in user is shown. Pure
// functions only (no Supabase, no React) so they can be unit tested.
//
// This is presentation, never enforcement: RLS and the SECURITY DEFINER RPCs
// (slices 3a to 6b) decide every read and write, and an RPC's refusal text is
// shown as-is. Hiding a control here only avoids offering something the
// database would refuse.

import type { StaffRole } from "@/data/auth-store";
import type { Stage } from "@/modules/admissions/labels";

/** The capability fields this file needs (a subset of the store's type). */
export type OwnCapabilities = {
  gradeBands: string[];
  allGrades: boolean;
};

type Role = StaffRole | undefined | null;

/** Manager and Auditor see every application; an Admissions Officer sees
 * the grades in scope. Attendant and Accountant see nothing, so the section
 * and its routes are closed to them (applications_select returns no rows). */
export function canViewAdmissions(role: Role): boolean {
  return role === "Manager" || role === "Auditor" || role === "Admissions Officer";
}

/** Same set as _require_admissions_writer(). Auditor is read-only. */
export function canWriteAdmissions(role: Role): boolean {
  return role === "Manager" || role === "Admissions Officer";
}

export function isAdmissionsReadOnly(role: Role): boolean {
  return role === "Auditor";
}

/** move_application_to_document_review: Manager or in-scope officer, from
 * inquiry or application only. */
export function canMoveToDocumentReview(role: Role, stage: string): boolean {
  return canWriteAdmissions(role) && (stage === "inquiry" || stage === "application");
}

/** The targets set_application_stage accepts (Manager only). */
export const STAGE_CHANGE_TARGETS: Stage[] = [
  "application",
  "document_review",
  "waitlisted",
  "rejected",
];

/** Stages a Manager may pick for this application; empty for every other
 * role, and for an application at offer or enrolled (the RPC refuses both). */
export function stageChangeTargets(role: Role, stage: string): Stage[] {
  if (role !== "Manager") return [];
  if (stage === "offer" || stage === "enrolled") return [];
  return STAGE_CHANGE_TARGETS.filter((t) => t !== stage);
}

export function canAddNote(role: Role): boolean {
  return canWriteAdmissions(role);
}

/** update_application_note: the note's author only, while still a writer. */
export function canEditNote(
  role: Role,
  authorId: string | null,
  currentStaffId: string | null | undefined,
): boolean {
  return canWriteAdmissions(role) && !!authorId && authorId === currentStaffId;
}

const DOCUMENT_STATUS_TARGETS = ["pending_review", "approved", "rejected"] as const;

/** set_application_document_status: never to or from "required" (no file). */
export function documentStatusTargets(role: Role, status: string): string[] {
  if (!canWriteAdmissions(role) || status === "required") return [];
  return DOCUMENT_STATUS_TARGETS.filter((s) => s !== status);
}

// ------------------------------------------------------------ health panel

/** The live has_admissions_capability('health') result. */
export type HealthCapability = "checking" | "error" | "granted" | "denied";
/** The application_health_info read, only ever started when granted. */
export type HealthFetch = "loading" | "error" | "none" | "row";
export type HealthPanelState = "hidden" | "loading" | "error" | "empty" | "answers";

/** Nothing at all (no heading, no placeholder) unless the capability check
 * came back true. "No health information on file" ("empty") is only ever
 * for a capability holder whose read succeeded and found no row. */
export function healthPanelState(
  capability: HealthCapability,
  fetch: HealthFetch,
): HealthPanelState {
  if (capability !== "granted") return "hidden";
  switch (fetch) {
    case "loading":
      return "loading";
    case "error":
      return "error";
    case "none":
      return "empty";
    case "row":
      return "answers";
  }
}

// ------------------------------------------------------------ list filters

/** Unbanded and legacy grades ("Grade 11", "2027", "Other") are visible to
 * Manager, Auditor and all_grades officers only, so only they get the
 * filter option. */
export function canSeeUnbandedGrades(role: Role, caps: OwnCapabilities | undefined): boolean {
  if (role === "Manager" || role === "Auditor") return true;
  return role === "Admissions Officer" && !!caps?.allGrades;
}

export type GradeOption = { name: string; band: string | null };

/** Grade filter options: every grade for Manager, Auditor and all_grades
 * officers; only the grades in an officer's bands otherwise. Display only,
 * RLS decides the rows. */
export function gradeFilterOptions(
  role: Role,
  caps: OwnCapabilities | undefined,
  grades: GradeOption[],
): GradeOption[] {
  if (role === "Manager" || role === "Auditor") return grades;
  if (role !== "Admissions Officer" || !caps) return [];
  if (caps.allGrades) return grades;
  return grades.filter((g) => g.band !== null && caps.gradeBands.includes(g.band));
}

/** An officer whose own capability row grants no grade scope sees an empty
 * list; say why instead of "no applications". */
export function officerHasNoScope(role: Role, caps: OwnCapabilities | undefined): boolean {
  if (role !== "Admissions Officer") return false;
  return !caps || (!caps.allGrades && caps.gradeBands.length === 0);
}

// ------------------------------------------------------------ detail route

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A malformed id is "not found" without a query, so it can't produce a
 * different error from an unknown or out-of-scope id. */
export function isApplicationId(value: string): boolean {
  return UUID_PATTERN.test(value);
}
