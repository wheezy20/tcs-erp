import { supabase } from "@/lib/supabase";

// The slice 5 write RPCs. Each one re-checks role, scope and stage under a
// row lock and raises a plain message on refusal; callers show that message
// as-is through getErrorMessage(). Nothing here decides anything.

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
