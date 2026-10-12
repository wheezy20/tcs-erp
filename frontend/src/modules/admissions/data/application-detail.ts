import { supabase } from "@/lib/supabase";

// Reads for the application detail page. Every read goes through RLS (slices
// 3a and 4), so an out-of-scope application returns nothing, exactly like a
// nonexistent one. Explicit columns only: never a token hash, never the
// declaration IP address. Health is read only by the health panel, and only
// after the live capability check (see health.ts).

// ------------------------------------------------------------ header

export type ApplicationSummary = {
  id: string;
  studentId: string;
  studentName: string;
  branchId: string | null;
  branchName: string | null;
  academicYear: string;
  gradeAsEntered: string;
  gradeName: string | null;
  gradeBand: string | null;
  monthOfEnrollment: string;
  stage: string;
  inquiryReference: string | null;
  applicationReference: string | null;
  createdAt: string;
  updatedAt: string;
};

/** The header row, from the list view. Null when the id doesn't exist or
 * isn't visible to the caller: the two are deliberately indistinguishable. */
export async function getApplicationSummary(id: string): Promise<ApplicationSummary | null> {
  const { data, error } = await supabase
    .from("admissions_application_list")
    .select(
      "id, student_id, student_full_name, branch_id, branch_name, academic_year, year_group_applied_for, grade_name, grade_band, month_of_enrollment, stage, inquiry_reference, application_reference, created_at, updated_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    id: data.id!,
    studentId: data.student_id!,
    studentName: data.student_full_name ?? "",
    branchId: data.branch_id,
    branchName: data.branch_name,
    academicYear: data.academic_year ?? "",
    gradeAsEntered: data.year_group_applied_for ?? "",
    gradeName: data.grade_name,
    gradeBand: data.grade_band,
    monthOfEnrollment: data.month_of_enrollment ?? "",
    stage: data.stage ?? "",
    inquiryReference: data.inquiry_reference,
    applicationReference: data.application_reference,
    createdAt: data.created_at ?? "",
    updatedAt: data.updated_at ?? "",
  };
}

// ------------------------------------------------------------ application

export type ApplicationDeclaration = {
  wantsScholarshipInfo: boolean;
  scholarshipInterestDetails: string;
  declarationSignatureName: string;
  declarationAgreed: boolean;
  declarationAgreedAt: string | null;
  mediaConsentAgreed: boolean;
};

export async function getApplicationDeclaration(id: string): Promise<ApplicationDeclaration> {
  const { data, error } = await supabase
    .from("applications")
    .select(
      "wants_scholarship_info, scholarship_interest_details, declaration_signature_name, declaration_agreed, declaration_agreed_at, media_consent_agreed",
    )
    .eq("id", id)
    .single();
  if (error) throw error;
  return {
    wantsScholarshipInfo: data.wants_scholarship_info,
    scholarshipInterestDetails: data.scholarship_interest_details,
    declarationSignatureName: data.declaration_signature_name,
    declarationAgreed: data.declaration_agreed,
    declarationAgreedAt: data.declaration_agreed_at,
    mediaConsentAgreed: data.media_consent_agreed,
  };
}

// ------------------------------------------------------------ applicant and family

export type Student = {
  id: string;
  familyId: string;
  fullName: string;
  dateOfBirth: string | null;
  gender: string;
  nationality: string;
  address: string;
  townCity: string;
  postalCode: string;
  country: string;
  currentSchool: string;
  previousSchoolLocation: string;
  currentGrade: string;
  studentNumber: string | null;
};

export type Guardian = {
  id: string;
  firstName: string;
  surname: string;
  email: string;
  phone: string;
  relationship: string;
  religion: string;
  address: string;
  townCity: string;
};

export type Family = {
  id: string;
  referralSource: string;
  referralSourceOther: string;
  comments: string;
  guardians: Guardian[];
};

export async function getStudentAndFamily(
  studentId: string,
): Promise<{ student: Student; family: Family | null }> {
  const { data: s, error } = await supabase
    .from("students")
    .select(
      "id, family_id, full_name, date_of_birth, gender, nationality, address, town_city, postal_code, country, current_school, previous_school_location, current_grade, student_id",
    )
    .eq("id", studentId)
    .single();
  if (error) throw error;
  const student: Student = {
    id: s.id,
    familyId: s.family_id,
    fullName: s.full_name,
    dateOfBirth: s.date_of_birth,
    gender: s.gender,
    nationality: s.nationality,
    address: s.address,
    townCity: s.town_city,
    postalCode: s.postal_code,
    country: s.country,
    currentSchool: s.current_school,
    previousSchoolLocation: s.previous_school_location,
    currentGrade: s.current_grade,
    studentNumber: s.student_id,
  };

  const [familyRes, guardiansRes] = await Promise.all([
    supabase
      .from("families")
      .select("id, referral_source, referral_source_other, comments")
      .eq("id", student.familyId)
      .maybeSingle(),
    supabase
      .from("guardians")
      .select("id, first_name, surname, email, phone, relationship, religion, address, town_city")
      .eq("family_id", student.familyId)
      .order("surname")
      .order("id"),
  ]);
  if (familyRes.error) throw familyRes.error;
  if (guardiansRes.error) throw guardiansRes.error;
  const f = familyRes.data;
  return {
    student,
    family: f
      ? {
          id: f.id,
          referralSource: f.referral_source,
          referralSourceOther: f.referral_source_other,
          comments: f.comments,
          guardians: (guardiansRes.data ?? []).map((g) => ({
            id: g.id,
            firstName: g.first_name,
            surname: g.surname,
            email: g.email,
            phone: g.phone,
            relationship: g.relationship,
            religion: g.religion,
            address: g.address,
            townCity: g.town_city,
          })),
        }
      : null,
  };
}

// ------------------------------------------------------------ emergency contacts

export type EmergencyContact = { id: string; name: string; relationship: string; phone: string };

export async function listEmergencyContacts(applicationId: string): Promise<EmergencyContact[]> {
  const { data, error } = await supabase
    .from("application_emergency_contacts")
    .select("id, name, relationship, phone")
    .eq("application_id", applicationId)
    .order("name")
    .order("id");
  if (error) throw error;
  return data ?? [];
}

// ------------------------------------------------------------ notes

export type ApplicationNote = {
  id: string;
  authorId: string | null;
  content: string;
  createdAt: string;
  editedAt: string | null;
};

export async function listNotes(applicationId: string): Promise<ApplicationNote[]> {
  const { data, error } = await supabase
    .from("application_notes")
    .select("id, author_id, content, created_at, edited_at")
    .eq("application_id", applicationId)
    .order("created_at", { ascending: false })
    .order("id");
  if (error) throw error;
  return (data ?? []).map((n) => ({
    id: n.id,
    authorId: n.author_id,
    content: n.content,
    createdAt: n.created_at,
    editedAt: n.edited_at,
  }));
}

// ------------------------------------------------------------ documents

export type ApplicationDocument = {
  id: string;
  documentType: string;
  status: string;
  /** Set exactly when a file exists (slice 4's upload pair check). */
  uploadedAt: string | null;
};

/** The storage path is deliberately not read here: it's fetched per click
 * by openApplicationDocument() and never kept. */
export async function listDocuments(applicationId: string): Promise<ApplicationDocument[]> {
  const { data, error } = await supabase
    .from("application_documents")
    .select("id, document_type, status, uploaded_at")
    .eq("application_id", applicationId)
    .order("document_type")
    .order("id");
  if (error) throw error;
  return (data ?? []).map((d) => ({
    id: d.id,
    documentType: d.document_type,
    status: d.status,
    uploadedAt: d.uploaded_at,
  }));
}
