import { supabase } from "@/lib/supabase";

// The admissions write RPCs (slices 5, 6a, 6b and 7b1). Each one re-checks
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

export type IssuedOffer = {
  /** The raw token, returned exactly once. Never stored anywhere. */
  token: string;
  expiresAt: string | null;
};

function issuedOffer(data: unknown): IssuedOffer {
  const o = asObject(data);
  const token = asText(o.token);
  if (!token) throw new Error("The offer was saved but no link came back. Reset the offer.");
  return { token, expiresAt: asText(o.expires_at) };
}

export async function generateOffer(applicationId: string): Promise<IssuedOffer> {
  const { data, error } = await supabase.rpc("generate_offer", {
    p_application_id: applicationId,
  });
  if (error) throw error;
  return issuedOffer(data);
}

export async function resetOffer(applicationId: string): Promise<IssuedOffer> {
  const { data, error } = await supabase.rpc("reset_offer", { p_application_id: applicationId });
  if (error) throw error;
  return issuedOffer(data);
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
