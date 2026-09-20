import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// employee_generated_documents / contract_templates (20260924100000):
// document generation for Appointment Letters, Probation Letters, and
// Contracts. RPC-only writes to employee_generated_documents (no direct
// RLS write policy at all) — this store only calls generate/issue/
// discard/record-acceptance and re-reads, same "no hand-editable legal
// record" shape as employees/employee_pay_config.
//
// Storage: private `employee-generated-documents` bucket, same
// createSignedUrls()-only read pattern as receipts/onboarding-documents.

const BUCKET = "employee-generated-documents";
const URL_EXPIRY_SECONDS = 60 * 60;

export type DocumentKind =
  "Appointment Letter" | "Probation Letter" | "Contract-Teaching" | "Contract-Non-Teaching";

export type GeneratedDocumentStatus = "Draft" | "Issued" | "Superseded";

export type GeneratedDocument = {
  id: string;
  employeeId: string;
  documentKind: DocumentKind;
  version: number;
  status: GeneratedDocumentStatus;
  storagePath: string;
  signedUrl: string | null;
  createdByName: string | null;
  createdAt: string;
  issuedByName: string | null;
  issuedAt: string | null;
  supersededAt: string | null;
  acceptanceSignatureName: string | null;
  acceptedAt: string | null;
};

type Row = Database["public"]["Tables"]["employee_generated_documents"]["Row"] & {
  creator: { name: string } | null;
  issuer: { name: string } | null;
};

async function signUrls(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrls(paths, URL_EXPIRY_SECONDS);
  if (error) throw error;
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) map.set(item.path, item.signedUrl);
  }
  return map;
}

function mapRow(row: Row, urls: Map<string, string>): GeneratedDocument {
  return {
    id: row.id,
    employeeId: row.employee_id,
    documentKind: row.document_kind as DocumentKind,
    version: row.version,
    status: row.status as GeneratedDocumentStatus,
    storagePath: row.storage_path,
    signedUrl: urls.get(row.storage_path) ?? null,
    createdByName: row.creator?.name ?? null,
    createdAt: row.created_at,
    issuedByName: row.issuer?.name ?? null,
    issuedAt: row.issued_at,
    supersededAt: row.superseded_at,
    acceptanceSignatureName: row.acceptance_signature_name,
    acceptedAt: row.accepted_at,
  };
}

/** One employee's documents, newest version first within each kind.
 * Loaded on demand from the employee profile page. */
export async function listGeneratedDocuments(employeeId: string): Promise<GeneratedDocument[]> {
  const { data, error } = await supabase
    .from("employee_generated_documents")
    .select(
      "*, creator:staff!employee_generated_documents_created_by_fkey(name), issuer:staff!employee_generated_documents_issued_by_fkey(name)",
    )
    .eq("employee_id", employeeId)
    .order("document_kind")
    .order("version", { ascending: false });
  if (error) throw error;
  const rows = data as unknown as Row[];
  const urls = await signUrls(rows.map((r) => r.storage_path));
  return rows.map((r) => mapRow(r, urls));
}

/** Uploads the rendered PDF first, then creates the Draft row referencing
 * it — same order as every other upload-then-record flow in this app.
 * `kind` is the caller's 3-way intent; for `"Contract"` the RPC itself
 * resolves Teaching/Non-Teaching from the employee's current position,
 * server-side (never trusted from the client). */
export async function generateEmployeeDocument(
  employeeId: string,
  kind: "Appointment Letter" | "Probation Letter" | "Contract",
  pdfBlob: Blob,
  mergeData: Record<string, string>,
): Promise<void> {
  const path = `${employeeId}/${crypto.randomUUID()}.pdf`;
  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(path, pdfBlob, { contentType: "application/pdf" });
  if (uploadError) throw uploadError;

  const { error } = await supabase.rpc("generate_employee_document", {
    p_employee_id: employeeId,
    p_document_kind: kind,
    p_storage_path: path,
    p_merge_data: mergeData,
  });
  if (error) throw error;
}

export async function issueGeneratedDocument(id: string): Promise<void> {
  const { error } = await supabase.rpc("issue_employee_document", { p_document_id: id });
  if (error) throw error;
}

/** Removes the storage object before the row, so a failed discard never
 * leaves a document row pointing at nothing. Draft only — the RPC
 * itself rejects an Issued/Superseded document. */
export async function discardDraftDocument(id: string, storagePath: string): Promise<void> {
  const { error: storageError } = await supabase.storage.from(BUCKET).remove([storagePath]);
  if (storageError) throw storageError;
  const { error } = await supabase.rpc("discard_draft_document", { p_document_id: id });
  if (error) throw error;
}

/** HR records that a signature was received by some other means (paper,
 * verbal, email) — not a self-service signing flow. See docs/DESIGN.md. */
export async function recordDocumentAcceptance(id: string, signatureName: string): Promise<void> {
  const { error } = await supabase.rpc("record_document_acceptance", {
    p_document_id: id,
    p_signature_name: signatureName,
  });
  if (error) throw error;
}
