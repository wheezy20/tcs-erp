import { supabase } from "@/lib/supabase";

// The admissions write RPCs (slices 5, 6a, 6b, 7b1 and 7b2). Each one re-checks
// role, scope and stage under a row lock and raises a plain message on
// refusal; callers show that message as-is through getErrorMessage().
// Nothing here decides anything.

export async function moveToDocumentReview(applicationId: string): Promise<void> {
  const { error } = await supabase.rpc("move_application_to_document_review", {
    p_application_id: applicationId,
  });
  if (error) throw error;
}

export async function setApplicationStage(applicationId: string, stage: string): Promise<void> {
  const { error } = await supabase.rpc("set_application_stage", {
    p_application_id: applicationId,
    p_stage: stage,
  });
  if (error) throw error;
}

export async function addApplicationNote(applicationId: string, content: string): Promise<void> {
  const { error } = await supabase.rpc("add_application_note", {
    p_application_id: applicationId,
    p_content: content,
  });
  if (error) throw error;
}

export async function updateApplicationNote(noteId: string, content: string): Promise<void> {
  const { error } = await supabase.rpc("update_application_note", {
    p_note_id: noteId,
    p_content: content,
  });
  if (error) throw error;
}

export async function setDocumentStatus(documentId: string, status: string): Promise<void> {
  const { error } = await supabase.rpc("set_application_document_status", {
    p_document_id: documentId,
    p_status: status,
  });
  if (error) throw error;
}

// ------------------------------------------------------------ decisions, offers, enrolment

type JsonObject = Record<string, unknown>;

function asObject(data: unknown): JsonObject {
  return data && typeof data === "object" && !Array.isArray(data) ? (data as JsonObject) : {};
}

function asText(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

export type DecisionResult = {
  stage: string;
  /** The RPC's own text: figures for a Manager, none for an officer. */
  capacityWarning: string | null;
  offerWithdrawn: boolean;
};

function decisionResult(data: unknown): DecisionResult {
  const o = asObject(data);
  return {
    stage: asText(o.stage) ?? "",
    capacityWarning: asText(o.capacity_warning),
    offerWithdrawn: o.offer_withdrawn === true,
  };
}

export async function recordDecision(
  applicationId: string,
  decisionType: string,
  notes: string,
): Promise<DecisionResult> {
  const { data, error } = await supabase.rpc("record_decision", {
    p_application_id: applicationId,
    p_decision_type: decisionType,
    p_notes: notes,
  });
  if (error) throw error;
  return decisionResult(data);
}

export async function changeDecision(
  applicationId: string,
  decisionType: string,
  notes: string,
): Promise<DecisionResult> {
  const { data, error } = await supabase.rpc("change_decision", {
    p_application_id: applicationId,
    p_decision_type: decisionType,
    p_notes: notes,
  });
  if (error) throw error;
  return decisionResult(data);
}

/** What generate_offer, reset_offer and resend_offer_link return (slice
 * 11). No token: the link is made when each email is sent, and exists only
 * in the email. */
export type SentOffer = {
  expiresAt: string | null;
  /** How many guardian addresses were queued an email (0 when none has an
   * address). */
  emailsQueued: number;
};

function sentOffer(data: unknown): SentOffer {
  const o = asObject(data);
  const n = o.emails_queued;
  return {
    expiresAt: asText(o.expires_at),
    emailsQueued: typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : 0,
  };
}

export async function generateOffer(applicationId: string): Promise<SentOffer> {
  const { data, error } = await supabase.rpc("generate_offer", {
    p_application_id: applicationId,
  });
  if (error) throw error;
  return sentOffer(data);
}

export async function resetOffer(applicationId: string): Promise<SentOffer> {
  const { data, error } = await supabase.rpc("reset_offer", { p_application_id: applicationId });
  if (error) throw error;
  return sentOffer(data);
}

/** Sends the link again for an open offer; every earlier link stops working. */
export async function resendOfferLink(applicationId: string): Promise<SentOffer> {
  const { data, error } = await supabase.rpc("resend_offer_link", {
    p_application_id: applicationId,
  });
  if (error) throw error;
  return sentOffer(data);
}

/** How many addresses a send would email right now (the confirm step). */
export async function previewOfferRecipients(applicationId: string): Promise<number> {
  const { data, error } = await supabase.rpc("preview_offer_recipients", {
    p_application_id: applicationId,
  });
  if (error) throw error;
  return typeof data === "number" ? data : 0;
}

/** Corrects a response the parent gave through the offer link (D-11j). */
export async function correctOfferResponse(
  applicationId: string,
  response: "accepted" | "declined",
  reason: string,
): Promise<void> {
  const { error } = await supabase.rpc("correct_offer_response", {
    p_application_id: applicationId,
    p_response: response,
    p_reason: reason,
  });
  if (error) throw error;
}

export async function recordOfferResponse(
  applicationId: string,
  response: "accepted" | "declined",
): Promise<void> {
  const { error } = await supabase.rpc("record_offer_response", {
    p_application_id: applicationId,
    p_response: response,
  });
  if (error) throw error;
}

export type EnrolmentResult = { studentId: string | null; studentIdAssigned: boolean };

export async function markEnrolled(applicationId: string): Promise<EnrolmentResult> {
  const { data, error } = await supabase.rpc("mark_enrolled", { p_application_id: applicationId });
  if (error) throw error;
  const o = asObject(data);
  return { studentId: asText(o.student_id), studentIdAssigned: o.student_id_assigned === true };
}

export async function correctApplicationGrade(
  applicationId: string,
  gradeId: string,
): Promise<void> {
  const { error } = await supabase.rpc("correct_application_grade", {
    p_application_id: applicationId,
    p_grade_id: gradeId,
  });
  if (error) throw error;
}

// ------------------------------------------------------------ settings (Manager only)

export async function addAcademicYear(label: string): Promise<void> {
  const { error } = await supabase.rpc("add_admissions_academic_year", { p_label: label });
  if (error) throw error;
}

export async function setAcademicYearActive(label: string, active: boolean): Promise<void> {
  const { error } = await supabase.rpc("set_admissions_academic_year_active", {
    p_label: label,
    p_active: active,
  });
  if (error) throw error;
}

/** A null campus means the figure isn't campus specific. */
export async function createCapacity(
  academicYear: string,
  gradeId: string,
  branchId: string | null,
  capacity: number,
): Promise<void> {
  const { error } = await supabase.rpc("create_admissions_capacity", {
    p_academic_year: academicYear,
    p_grade_id: gradeId,
    p_branch_id: branchId as unknown as string,
    p_capacity: capacity,
  });
  if (error) throw error;
}

export async function updateCapacity(id: string, capacity: number): Promise<void> {
  const { error } = await supabase.rpc("update_admissions_capacity", {
    p_id: id,
    p_capacity: capacity,
  });
  if (error) throw error;
}

export async function deleteCapacity(id: string): Promise<void> {
  const { error } = await supabase.rpc("delete_admissions_capacity", { p_id: id });
  if (error) throw error;
}

export async function setOfferTtlDays(days: number): Promise<void> {
  const { error } = await supabase.rpc("set_admissions_offer_ttl_days", { p_days: days });
  if (error) throw error;
}

export async function setPublicIntakeOpen(open: boolean): Promise<void> {
  const { error } = await supabase.rpc("set_admissions_public_intake", { p_open: open });
  if (error) throw error;
}

/** Manager only (slice 8b RPC, made usable in slice 9a): opens or closes
 * the public Application form. Audited as admissions_settings_changed. */
export async function setPublicApplicationsOpen(open: boolean): Promise<void> {
  const { error } = await supabase.rpc("set_admissions_public_applications", { p_open: open });
  if (error) throw error;
}

/** Manager only (slice 13): opens or closes lead capture, the school
 * website's Admissions Overview form. Independent of the two intake
 * switches. Audited as admissions_settings_changed. */
export async function setPublicLeadsOpen(open: boolean): Promise<void> {
  const { error } = await supabase.rpc("set_admissions_public_leads", { p_open: open });
  if (error) throw error;
}
