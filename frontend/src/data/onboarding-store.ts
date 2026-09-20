import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";
import { type DocumentType } from "@/data/employee-documents-store";

// Onboarding checklist + the tokenized public form (20260921100000).
//
// employee_onboarding_tasks has no direct RLS write policy at all — every
// write (manual toggle or derived recompute) goes through a SECURITY
// DEFINER RPC, same "RPC-only" shape as employees/employee_pay_config.
// This store never inserts/updates those tables directly; it only calls
// the RPCs and re-reads.
//
// The public-form functions at the bottom (getOnboardingContext,
// uploadOnboardingDocument, submitOnboardingForm) are called from an
// unauthenticated route (/onboarding/$token) — they work against the
// anon Supabase client because the RPCs/storage policy they hit are
// specifically designed for that (see the migration's security note).

const ONBOARDING_DOCUMENTS_BUCKET = "onboarding-documents";

export type DerivationKey = "pay_config_active" | "staff_account_created";

export type ChecklistItem = {
  id: string;
  name: string;
  requiresDocument: boolean;
  isDerived: boolean;
  derivationKey: DerivationKey | null;
  /** National ID / SSNIT Card / TIN Copy (20260922): completing the item
   * accepts either a document already on file or a typed number instead —
   * some people have lost the physical card but still know the number. */
  acceptsNumberInLieu: boolean;
  position: number;
  isActive: boolean;
};

type ChecklistItemRow = Database["public"]["Tables"]["onboarding_checklist_items"]["Row"];

function mapChecklistItem(row: ChecklistItemRow): ChecklistItem {
  return {
    id: row.id,
    name: row.name,
    requiresDocument: row.requires_document,
    isDerived: row.is_derived,
    derivationKey: row.derivation_key as DerivationKey | null,
    acceptsNumberInLieu: row.accepts_number_in_lieu,
    position: row.position,
    isActive: row.is_active,
  };
}

export async function listChecklistItems(): Promise<ChecklistItem[]> {
  const { data, error } = await supabase
    .from("onboarding_checklist_items")
    .select("*")
    .order("position");
  if (error) throw error;
  return (data as ChecklistItemRow[]).map(mapChecklistItem);
}

export type OnboardingTask = {
  id: string;
  employeeId: string;
  completed: boolean;
  completedAt: string | null;
  completedByName: string | null;
  providedVia: "document" | "number" | null;
  providedNumber: string | null;
  item: ChecklistItem;
};

type TaskRow = Database["public"]["Tables"]["employee_onboarding_tasks"]["Row"] & {
  onboarding_checklist_items: ChecklistItemRow;
  completed_by_staff: { name: string } | null;
};

function mapTask(row: TaskRow): OnboardingTask {
  return {
    id: row.id,
    employeeId: row.employee_id,
    completed: row.completed,
    completedAt: row.completed_at,
    completedByName: row.completed_by_staff?.name ?? null,
    providedVia: row.provided_via as "document" | "number" | null,
    providedNumber: row.provided_number,
    item: mapChecklistItem(row.onboarding_checklist_items),
  };
}

/** One employee's checklist, active items only, catalog order. Loaded on
 * demand from the employee profile page — same on-demand rationale as
 * employee-documents-store.ts (only ever viewed one employee at a time). */
export async function listOnboardingTasks(employeeId: string): Promise<OnboardingTask[]> {
  const { data, error } = await supabase
    .from("employee_onboarding_tasks")
    .select(
      "*, onboarding_checklist_items(*), completed_by_staff:staff!employee_onboarding_tasks_completed_by_fkey(name)",
    )
    .eq("employee_id", employeeId);
  if (error) throw error;
  const rows = data as unknown as TaskRow[];
  return rows.map(mapTask).sort((a, b) => a.item.position - b.item.position);
}

/** Manual items only — toggle_onboarding_task() itself rejects a derived
 * item server-side, this just avoids a round trip for the obvious case.
 * `providedVia`/`providedNumber` only apply to items with
 * `acceptsNumberInLieu` — the RPC requires one of the two when completing
 * one of those, and validates a "document" claim against a real
 * employee_documents row server-side. */
export async function toggleOnboardingTask(
  taskId: string,
  completed: boolean,
  providedVia?: "document" | "number",
  providedNumber?: string,
): Promise<void> {
  const { error } = await supabase.rpc("toggle_onboarding_task", {
    p_task_id: taskId,
    p_completed: completed,
    p_provided_via: providedVia,
    p_provided_number: providedNumber,
  });
  if (error) throw error;
}

/** For an employee who reached Active before this feature existed, or to
 * pick up a newly-added catalog item on an already-onboarding employee. */
export async function initializeOnboardingChecklist(employeeId: string): Promise<void> {
  const { error } = await supabase.rpc("initialize_onboarding_checklist", {
    p_employee_id: employeeId,
  });
  if (error) throw error;
}

/** The raw token is returned exactly once — the caller must show/copy it
 * immediately (see the migration's security note on generate_onboarding_token()).
 * Never re-fetchable afterwards; only its hash is stored. */
export async function generateOnboardingToken(
  employeeId: string,
  ttlDays = 14,
): Promise<{ token: string; expiresAt: string }> {
  const { data, error } = await supabase.rpc("generate_onboarding_token", {
    p_employee_id: employeeId,
    p_ttl_days: ttlDays,
  });
  if (error) throw error;
  const row = (Array.isArray(data) ? data[0] : data) as { token: string; expires_at: string };
  return { token: row.token, expiresAt: row.expires_at };
}

export type OnboardingSubmission = {
  id: string;
  employeeId: string;
  dateOfBirth: string | null;
  gender: string | null;
  nationalId: string | null;
  personalEmail: string | null;
  emergencyContactName: string | null;
  emergencyContactPhone: string | null;
  residentialAddress: string | null;
  qualifications: string[] | null;
  bankName: string | null;
  accountNo: string | null;
  paymentMethod: string | null;
  contractAccepted: boolean;
  signatureName: string | null;
  /** `signedUrl` is populated by listOnboardingSubmissions() at read time —
   * see signOnboardingSubmissionUrls() below. Priority fix (20260922): a
   * pending submission previously showed only a document *count*, with no
   * way to actually see what was uploaded before clicking Approve — the
   * one path in this app anonymous strangers can write through was being
   * approved blind. The storage `onboarding_documents_select` RLS policy
   * (bucket-wide for Manager/Accountant/Auditor, not path-scoped) already
   * allows signing these paths from an authenticated session; this was a
   * frontend gap, not a missing permission. */
  uploadedDocuments: { documentType: string; storagePath: string; signedUrl: string | null }[];
  submittedAt: string;
  reviewStatus: "Pending Review" | "Approved" | "Rejected";
  reviewedByName: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
};

type SubmissionRow = Database["public"]["Tables"]["employee_onboarding_submissions"]["Row"] & {
  reviewer: { name: string } | null;
};

const SUBMISSION_DOCUMENT_URL_EXPIRY_SECONDS = 60 * 60;

async function signOnboardingSubmissionUrls(paths: string[]): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  if (paths.length === 0) return map;
  const { data, error } = await supabase.storage
    .from(ONBOARDING_DOCUMENTS_BUCKET)
    .createSignedUrls(paths, SUBMISSION_DOCUMENT_URL_EXPIRY_SECONDS);
  if (error) throw error;
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) map.set(item.path, item.signedUrl);
  }
  return map;
}

function mapSubmission(row: SubmissionRow, signedUrls: Map<string, string>): OnboardingSubmission {
  const uploaded = (row.uploaded_documents ?? []) as {
    document_type: string;
    storage_path: string;
  }[];
  return {
    id: row.id,
    employeeId: row.employee_id,
    dateOfBirth: row.date_of_birth,
    gender: row.gender,
    nationalId: row.national_id,
    personalEmail: row.personal_email,
    emergencyContactName: row.emergency_contact_name,
    emergencyContactPhone: row.emergency_contact_phone,
    residentialAddress: row.residential_address,
    qualifications: row.qualifications,
    bankName: row.bank_name,
    accountNo: row.account_no,
    paymentMethod: row.payment_method,
    contractAccepted: row.contract_accepted,
    signatureName: row.signature_name,
    uploadedDocuments: uploaded.map((d) => ({
      documentType: d.document_type,
      storagePath: d.storage_path,
      signedUrl: signedUrls.get(d.storage_path) ?? null,
    })),
    submittedAt: row.submitted_at,
    reviewStatus: row.review_status as OnboardingSubmission["reviewStatus"],
    reviewedByName: row.reviewer?.name ?? null,
    reviewedAt: row.reviewed_at,
    rejectionReason: row.rejection_reason,
  };
}

export async function listOnboardingSubmissions(
  employeeId: string,
): Promise<OnboardingSubmission[]> {
  const { data, error } = await supabase
    .from("employee_onboarding_submissions")
    .select("*, reviewer:staff!employee_onboarding_submissions_reviewed_by_fkey(name)")
    .eq("employee_id", employeeId)
    .order("submitted_at", { ascending: false });
  if (error) throw error;
  const rows = data as unknown as SubmissionRow[];
  const allPaths = rows.flatMap((r) =>
    ((r.uploaded_documents ?? []) as { document_type: string; storage_path: string }[]).map(
      (d) => d.storage_path,
    ),
  );
  const signedUrls = await signOnboardingSubmissionUrls(allPaths);
  return rows.map((r) => mapSubmission(r, signedUrls));
}

export async function approveOnboardingSubmission(submissionId: string): Promise<void> {
  const { error } = await supabase.rpc("approve_onboarding_submission", {
    p_submission_id: submissionId,
  });
  if (error) throw error;
}

export async function rejectOnboardingSubmission(
  submissionId: string,
  reason: string,
): Promise<void> {
  const { error } = await supabase.rpc("reject_onboarding_submission", {
    p_submission_id: submissionId,
    p_reason: reason || undefined,
  });
  if (error) throw error;
}

// --------------------------------------------------------------------
// Public-form functions — called from the unauthenticated /onboarding/$token
// route with the anon client. No session exists; every check happens
// server-side inside the RPCs / the storage policy.
// --------------------------------------------------------------------

export async function getOnboardingContext(token: string): Promise<{
  employeeName: string | null;
  position: string | null;
  department: string | null;
  valid: boolean;
}> {
  const { data, error } = await supabase.rpc("get_onboarding_context", { p_token: token });
  if (error) throw error;
  const row = (Array.isArray(data) ? data[0] : data) as {
    employee_name: string | null;
    employee_position: string | null;
    department: string | null;
    valid: boolean;
  };
  return {
    employeeName: row.employee_name,
    position: row.employee_position,
    department: row.department,
    valid: row.valid,
  };
}

/** Uploads straight to the private bucket under `onboarding/{token}/...` —
 * the storage RLS policy hashes this same token and checks it's still
 * unexpired/unused (see is_valid_onboarding_token() in the migration).
 * Must happen BEFORE submitOnboardingForm(), which marks the token used. */
export async function uploadOnboardingDocument(
  token: string,
  documentType: DocumentType,
  file: File,
): Promise<{ document_type: string; storage_path: string }> {
  const extension = file.name.split(".").pop() || "bin";
  const path = `onboarding/${token}/${crypto.randomUUID()}.${extension}`;
  const { error } = await supabase.storage
    .from(ONBOARDING_DOCUMENTS_BUCKET)
    .upload(path, file, { contentType: file.type });
  if (error) throw error;
  return { document_type: documentType, storage_path: path };
}

export type OnboardingFormPayload = {
  dateOfBirth?: string;
  gender?: string;
  nationalId?: string;
  personalEmail?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;
  residentialAddress?: string;
  qualifications?: string[];
  bankName?: string;
  accountNo?: string;
  paymentMethod?: "Bank" | "Mobile Money";
  contractAccepted: boolean;
  signatureName: string;
  uploadedDocuments: { document_type: string; storage_path: string }[];
};

/** Marks the token used server-side, inside the same transaction as the
 * validity check — see the migration's security note for the exact
 * single-use race protection. Can only ever succeed once per token. */
export async function submitOnboardingForm(
  token: string,
  payload: OnboardingFormPayload,
): Promise<string> {
  const { data, error } = await supabase.rpc("submit_onboarding_form", {
    p_token: token,
    p_date_of_birth: payload.dateOfBirth || undefined,
    p_gender: payload.gender,
    p_national_id: payload.nationalId,
    p_personal_email: payload.personalEmail,
    p_emergency_contact_name: payload.emergencyContactName,
    p_emergency_contact_phone: payload.emergencyContactPhone,
    p_residential_address: payload.residentialAddress,
    p_qualifications: payload.qualifications,
    p_bank_name: payload.bankName,
    p_account_no: payload.accountNo,
    p_payment_method: payload.paymentMethod,
    p_contract_accepted: payload.contractAccepted,
    p_signature_name: payload.signatureName,
    p_uploaded_documents: payload.uploadedDocuments,
  });
  if (error) throw error;
  return data as string;
}
