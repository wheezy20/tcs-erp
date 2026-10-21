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

// ------------------------------------------------------------ decisions and offers

/** The live has_admissions_capability('decide') result. Only "granted"
 * offers a decision or offer control; "checking" and "error" offer none. */
export type DecideCapability = "checking" | "error" | "granted" | "denied";

export const DECISION_TYPES = ["accepted", "waitlisted", "rejected"] as const;

const NO_DECISION_STAGES = ["inquiry", "enrolled"];

function decides(role: Role, cap: DecideCapability): boolean {
  return canWriteAdmissions(role) && cap === "granted";
}

/** record_decision: decide capability, no decision yet, not at inquiry or
 * enrolled. */
export function canRecordDecision(
  role: Role,
  cap: DecideCapability,
  stage: string,
  decisionType: string | null,
): boolean {
  return decides(role, cap) && decisionType === null && !NO_DECISION_STAGES.includes(stage);
}

/** change_decision targets. Once the parent has accepted the offer the
 * decision can't leave accepted, so only a notes edit (accepted) remains. */
export function decisionChangeTargets(
  role: Role,
  cap: DecideCapability,
  stage: string,
  decisionType: string | null,
  offerResponse: string | null,
): string[] {
  if (!decides(role, cap) || decisionType === null || NO_DECISION_STAGES.includes(stage)) {
    return [];
  }
  if (decisionType === "accepted" && offerResponse === "accepted") return ["accepted"];
  return [...DECISION_TYPES];
}

export type OfferState = { response: string; effectiveResponse: string } | null;

const GENERATE_OFFER_STAGES = ["application", "document_review", "waitlisted", "rejected"];

/** generate_offer: accepted decision, no offer row, and a stage it accepts. */
export function canGenerateOffer(
  role: Role,
  cap: DecideCapability,
  stage: string,
  decisionType: string | null,
  offer: OfferState,
): boolean {
  return (
    decides(role, cap) &&
    decisionType === "accepted" &&
    offer === null &&
    GENERATE_OFFER_STAGES.includes(stage)
  );
}

/** reset_offer: accepted decision, an offer the parent hasn't accepted
 * (pending, expired, declined or withdrawn), not at inquiry or enrolled. */
export function canResetOffer(
  role: Role,
  cap: DecideCapability,
  stage: string,
  decisionType: string | null,
  offer: OfferState,
): boolean {
  return (
    decides(role, cap) &&
    decisionType === "accepted" &&
    offer !== null &&
    offer.response !== "accepted" &&
    !NO_DECISION_STAGES.includes(stage)
  );
}

/** record_offer_response: at offer, accepted decision, the offer pending and
 * in date (the view's effective response). */
export function canRecordOfferResponse(
  role: Role,
  cap: DecideCapability,
  stage: string,
  decisionType: string | null,
  offer: OfferState,
): boolean {
  return (
    decides(role, cap) &&
    stage === "offer" &&
    decisionType === "accepted" &&
    offer?.effectiveResponse === "pending"
  );
}

/** The parent response page's link for a token. The page itself arrives in
 * slice 11 at TCS OS's path; the token is host independent. */
export function offerLink(origin: string, token: string): string {
  return `${origin}/offer?token=${encodeURIComponent(token)}`;
}

// ------------------------------------------------------------ enrolment and grade

export type EnrolState = "hidden" | "blocked_by_grade" | "available";

/** mark_enrolled: Manager only (no capability), at offer, with an accepted
 * decision and an offer the parent accepted. A null grade band (from the
 * database) means the grade has no student ID classification, which the
 * RPC refuses, so the button is shown disabled with the reason. */
export function enrolState(
  role: Role,
  stage: string,
  decisionType: string | null,
  offer: OfferState,
  gradeBand: string | null,
): EnrolState {
  if (role !== "Manager" || stage !== "offer" || decisionType !== "accepted") return "hidden";
  if (offer?.effectiveResponse !== "accepted") return "hidden";
  return gradeBand === null ? "blocked_by_grade" : "available";
}

/** correct_application_grade: Manager only, an unrecognised grade (no band),
 * not enrolled. */
export function canCorrectGrade(role: Role, stage: string, gradeBand: string | null): boolean {
  return role === "Manager" && gradeBand === null && stage !== "enrolled";
}

/** Documents to warn about before enrolment: every one not approved. A
 * warning only; enrolment doesn't depend on documents. */
export function documentsNotApproved<T extends { status: string }>(documents: T[]): T[] {
  return documents.filter((d) => d.status !== "approved");
}

/** The list's empty state. An officer sees only their assigned grades, so an
 * empty unfiltered list says so, without saying whether anything exists
 * outside them. */
export function emptyListMessage(role: Role, isFiltered: boolean): string {
  if (isFiltered) return "No applications match.";
  if (role === "Admissions Officer") {
    return "No applications in your assigned grades. A Manager sets your admissions access in Settings.";
  }
  return "No applications yet.";
}

// ------------------------------------------------------------ settings screen

/** /admissions/settings: Manager and Auditor only. Capacity and the offer
 * expiry are readable by those two roles only (RLS), so an officer never
 * reaches the page and nothing is queried for them. */
export function canViewAdmissionsSettings(role: Role): boolean {
  return role === "Manager" || role === "Auditor";
}

/** The admissions email log (slice 12): list_admissions_emails and
 * get_admissions_email_health are Manager and Auditor only. Retry is
 * Manager only (requeue_admissions_emails). */
export function canViewAdmissionsEmails(role: Role): boolean {
  return role === "Manager" || role === "Auditor";
}

/** /admissions/leads (slice 13, D-13h): list_admissions_leads lets the
 * Manager and the Admissions Officer read every lead in full and the
 * Auditor read with email and phone masked; it refuses everyone else. */
export function canViewAdmissionsLeads(role: Role): boolean {
  return role === "Manager" || role === "Admissions Officer" || role === "Auditor";
}

/** The Auditor's view of a lead has email and phone masked by the database;
 * the page says so. */
export function leadContactsMasked(role: Role): boolean {
  return role === "Auditor";
}

/** Every settings write RPC is Manager only; the Auditor reads. */
export function canEditAdmissionsSettings(role: Role): boolean {
  return role === "Manager";
}
