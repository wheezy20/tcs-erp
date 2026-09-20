import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// employee_documents / the onboarding-documents bucket (20260920100000):
// private storage bucket + RLS-gated employee_documents table, both scoped
// Manager/Accountant/Auditor read, Manager/Accountant write — applying the
// receipts-bucket lesson (20260918110000) from this feature's first
// commit, never a public bucket fixed up later.

const ONBOARDING_DOCUMENTS_BUCKET = "onboarding-documents";

/** Same re-sign-on-every-load rationale as expenses-store.ts's
 * RECEIPT_URL_EXPIRY_SECONDS: bounds how long a leaked URL keeps working,
 * not how long a normal viewing session lasts. */
const DOCUMENT_URL_EXPIRY_SECONDS = 60 * 60;

// Widened 20260921 (Phase 3) from a 4-value placeholder guess to the real
// 8 document-backed onboarding checklist item names, once the actual
// 18-item tracker (not just the Apps Script source) showed what's really
// asked for — see onboarding-store.ts and the Phase 3 migration. These
// names double as onboarding_checklist_items.name for document-backed
// items, so approve_onboarding_submission() can write document_type
// straight from the checklist item with no separate mapping table.
export type DocumentType =
  | "ID Copy"
  | "SSNIT Card"
  | "TIN Copy"
  | "Academic Certs"
  | "Passport Photos"
  | "Guarantor Form"
  | "Medical Clearance"
  | "Background Check"
  | "Other";
export const DOCUMENT_TYPES: DocumentType[] = [
  "ID Copy",
  "SSNIT Card",
  "TIN Copy",
  "Academic Certs",
  "Passport Photos",
  "Guarantor Form",
  "Medical Clearance",
  "Background Check",
  "Other",
];

export type EmployeeDocument = {
  id: string;
  employeeId: string;
  documentType: DocumentType;
  storagePath: string;
  signedUrl: string | null;
  uploadedByName: string | null;
  uploadedAt: string;
  notes: string | null;
};

type DocumentRow = Database["public"]["Tables"]["employee_documents"]["Row"] & {
  uploader: { name: string } | null;
};

async function signDocumentUrls(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data, error } = await supabase.storage
    .from(ONBOARDING_DOCUMENTS_BUCKET)
    .createSignedUrls(paths, DOCUMENT_URL_EXPIRY_SECONDS);
  if (error) throw error;
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) map.set(item.path, item.signedUrl);
  }
  return map;
}

function mapDocumentRow(row: DocumentRow, signedUrls: Map<string, string>): EmployeeDocument {
  return {
    id: row.id,
    employeeId: row.employee_id,
    documentType: row.document_type as DocumentType,
    storagePath: row.storage_path,
    signedUrl: signedUrls.get(row.storage_path) ?? null,
    uploadedByName: row.uploader?.name ?? null,
    uploadedAt: row.uploaded_at,
    notes: row.notes,
  };
}

/** Loaded on demand per employee, not a global store like employees-store's
 * allowances — documents are only ever viewed one employee at a time from
 * the profile page, so there's no reason to sign every employee's files on
 * every page load. */
export async function listEmployeeDocuments(employeeId: string): Promise<EmployeeDocument[]> {
  const { data, error } = await supabase
    .from("employee_documents")
    .select("*, uploader:staff!employee_documents_uploaded_by_fkey(name)")
    .eq("employee_id", employeeId)
    .order("uploaded_at", { ascending: false });
  if (error) throw error;
  const rows = data as DocumentRow[];
  const signedUrls = await signDocumentUrls(rows.map((r) => r.storage_path));
  return rows.map((r) => mapDocumentRow(r, signedUrls));
}

/** Uploads to the private bucket first, then inserts the metadata row —
 * same order as createExpense()'s receipt upload, so a failed insert never
 * leaves a row pointing at nothing. Path is `{employeeId}/{uuid}.{ext}`;
 * the per-employee prefix is for tidy browsing in the Storage dashboard
 * only — the RLS policy itself is role-based, not path-based, so any
 * Manager/Accountant/Auditor can read any employee's documents, same as
 * the employee_documents table's own select policy. */
export async function uploadEmployeeDocument(
  employeeId: string,
  documentType: DocumentType,
  file: File,
  notes?: string,
): Promise<void> {
  const extension = file.name.split(".").pop() || "bin";
  const path = `${employeeId}/${crypto.randomUUID()}.${extension}`;
  const { error: uploadError } = await supabase.storage
    .from(ONBOARDING_DOCUMENTS_BUCKET)
    .upload(path, file, { contentType: file.type });
  if (uploadError) throw uploadError;

  const { error } = await supabase.from("employee_documents").insert({
    employee_id: employeeId,
    document_type: documentType,
    storage_path: path,
    notes: notes?.trim() || null,
  });
  if (error) throw error;
}

/** Removes the storage object before the row, so a failed delete never
 * leaves a document row pointing at nothing — the reverse order risks an
 * orphaned file instead, the safer of the two failure modes. */
export async function deleteEmployeeDocument(doc: {
  id: string;
  storagePath: string;
}): Promise<void> {
  const { error: storageError } = await supabase.storage
    .from(ONBOARDING_DOCUMENTS_BUCKET)
    .remove([doc.storagePath]);
  if (storageError) throw storageError;

  const { error } = await supabase.from("employee_documents").delete().eq("id", doc.id);
  if (error) throw error;
}
