// Pure logic for the plain public Application form (admissions slice 9a,
// checkpoint 2). No Supabase, no React. Every rule here is a convenience so
// a parent sees a problem before sending; the admissions-public Edge
// Function and submit_application check all of it again and are the only
// guarantee. The full six-section form is slice 9b.
//
// The field rules are the enquiry form's (slice 8b, D-9d): the same
// religion list, current grade or not yet in school, dd/mm/yyyy shown and
// ISO sent, and the phone rule. Health details are at most 2,000
// characters (D-4e).

import { isListedNationality, listedNationality } from "@/modules/admissions/nationalities";
import { DOCUMENTS_COPY } from "@/modules/admissions/public-copy";
import {
  EMAIL_PATTERN,
  MONTH_OPTIONS,
  NOT_YET_IN_SCHOOL,
  RELATIONSHIP_OPTIONS,
  RELIGION_OPTIONS,
  currentGradeChoices,
  emptyGuardian,
  gradesForCampus,
  parseDmy,
  phoneError,
  storedPhone,
  type FieldErrors,
  type GuardianDraft,
  type PublicOptions,
} from "@/modules/admissions/inquiry-form";

export const MAX_HEALTH_DETAILS = 2000;
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
export const FEE_PROOF = "application_fee_proof";

export const APPLICATION_OFFICE_MESSAGE =
  "We couldn't take your application online just now. Please call the school office and we'll help you directly.";

/** What a parent sees for each document slot (TCS OS labels, slice 9b C3). */
export const PUBLIC_DOCUMENT_LABELS: Record<string, string> = DOCUMENTS_COPY.labels;

/** The four slots, in TCS OS order: vaccination, financial clearance,
 * report card, then (under the fee box) the fee proof. */
export const DOCUMENT_SLOTS = [
  "proof_of_vaccination",
  "financial_clearance",
  "previous_report",
  FEE_PROOF,
] as const;

/** Files one upload session may hold (D-9g); the server is the authority. */
export const MAX_FILES_PER_SESSION = 8;

/** Whether another file can still be uploaded in this visit. Each choice,
 * a replacement included, takes a new reservation. */
export function canUploadMore(filesStarted: number): boolean {
  return filesStarted < MAX_FILES_PER_SESSION;
}

export const GENDER_OPTIONS = [
  { value: "male", label: "Male" },
  { value: "female", label: "Female" },
] as const;

// ---------------------------------------------------------------- options

/** Whether /apply can be used: public applications open and something to
 * choose. The enquiries switch plays no part. */
export function applicationFormAvailable(options: PublicOptions): boolean {
  return (
    options.applicationsOpen &&
    options.grades.length > 0 &&
    options.academicYears.length > 0 &&
    options.campuses.length > 0
  );
}

export type ApplicationView =
  "loading" | "loadError" | "created" | "closed" | "unavailable" | "form";

export function applicationView(state: {
  loading: boolean;
  error: string | null;
  options: PublicOptions | undefined;
  created: boolean;
  closedAfterSubmit: boolean;
  siteKey: string;
}): ApplicationView {
  if (state.loading && !state.options) return "loading";
  if (state.error || !state.options) return "loadError";
  if (state.created) return "created";
  if (state.closedAfterSubmit || !applicationFormAvailable(state.options)) return "closed";
  if (state.siteKey.trim() === "") return "unavailable";
  return "form";
}

/** The documents this grade needs, fee proof first. The fee proof is
 * required for every grade (D-9e) even if the options were to leave it
 * out; with no grade chosen yet, only the fee proof is shown. */
export function requiredDocumentTypes(options: PublicOptions, gradeId: string): string[] {
  const grade = options.grades.find((g) => g.id === gradeId);
  const listed = (grade?.requiredDocumentTypes ?? []).filter((t) => t in PUBLIC_DOCUMENT_LABELS);
  return [FEE_PROOF, ...listed.filter((t) => t !== FEE_PROOF)];
}

// ---------------------------------------------------------------- files

const CONTENT_TYPES: Record<string, string> = {
  pdf: "application/pdf",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
};

/** A chosen file's extension and the content type to upload it with, or
 * the message to show. A quick check only: the bucket checks the size and
 * type, and the server reads the file's first bytes before accepting it. */
export function checkFile(
  name: string,
  size: number,
): { extension: string; contentType: string } | { error: string } {
  const dot = name.lastIndexOf(".");
  const extension = dot >= 0 ? name.slice(dot + 1).toLowerCase() : "";
  const contentType = CONTENT_TYPES[extension];
  if (!contentType) return { error: "Choose a PDF, JPG or PNG file." };
  if (size <= 0) return { error: "That file is empty. Choose another." };
  if (size > MAX_UPLOAD_BYTES) return { error: "That file is over 10 MB. Choose a smaller one." };
  return { extension, contentType };
}

/** One uploaded file: what the server reserved for it. */
export type UploadedFile = { reservationId: string; path: string; fileName: string };

// ---------------------------------------------------------------- draft

/** A Yes/No answer with no default: null until the parent picks one. */
export type YesNo = boolean | null;

export type ApplicationDraft = {
  guardians: GuardianDraft[];
  secondSameAddress: boolean;
  child: {
    fullName: string;
    dateOfBirth: string; // dd/mm/yyyy as typed
    gender: string;
    nationality: string;
    /** "Same address as Parent/Guardian 1", ticked by default (TCS OS):
     * the child's address and town follow guardian 1 when sent. */
    sameAddress: boolean;
    address: string;
    townCity: string;
    postalCode: string;
    country: string;
    currentGrade: string; // a grade id, NOT_YET_IN_SCHOOL, or ""
    currentSchool: string;
    /** "Location/address of that school": only for a child in school. */
    previousSchoolLocation: string;
    gradeId: string;
    academicYear: string;
    month: string;
  };
  campusId: string;
  emergency: { name: string; relationship: string; phone: string };
  health: {
    hasNeeds: YesNo;
    needs: string;
    hasMedical: YesNo;
    medical: string;
    hasAllergies: YesNo;
    allergies: string;
  };
  /** "Are you interested in scholarship information?" No by default, as
   * in TCS OS; the details are sent only on Yes. */
  wantsScholarship: boolean;
  scholarshipDetails: string;
  mediaConsent: boolean;
  signature: string;
  agreed: boolean;
};

export const DEFAULT_COUNTRY = "Ghana";

export function emptyApplicationDraft(): ApplicationDraft {
  return {
    guardians: [emptyGuardian()],
    secondSameAddress: false,
    child: {
      fullName: "",
      dateOfBirth: "",
      gender: "",
      nationality: "",
      sameAddress: true,
      address: "",
      townCity: "",
      postalCode: "",
      country: DEFAULT_COUNTRY,
      currentGrade: "",
      currentSchool: "",
      previousSchoolLocation: "",
      gradeId: "",
      academicYear: "",
      month: "",
    },
    campusId: "",
    emergency: { name: "", relationship: "", phone: "" },
    health: {
      hasNeeds: null,
      needs: "",
      hasMedical: null,
      medical: "",
      hasAllergies: null,
      allergies: "",
    },
    wantsScholarship: false,
    scholarshipDetails: "",
    mediaConsent: false,
    signature: "",
    agreed: false,
  };
}

function guardiansToSend(draft: ApplicationDraft): GuardianDraft[] {
  return draft.guardians.map((g, i) =>
    i === 1 && draft.secondSameAddress
      ? { ...g, address: draft.guardians[0].address, townCity: draft.guardians[0].townCity }
      : g,
  );
}

/** The child's address and town as they will be sent: guardian 1's while
 * "Same address as Parent/Guardian 1" is ticked, read at the moment of
 * use, so a later change to guardian 1 is followed. */
export function childAddress(draft: ApplicationDraft): { address: string; townCity: string } {
  return draft.child.sameAddress
    ? { address: draft.guardians[0]?.address ?? "", townCity: draft.guardians[0]?.townCity ?? "" }
    : { address: draft.child.address, townCity: draft.child.townCity };
}

/** Whether the parent has entered anything yet: the leave-this-page
 * warning shows only then. The prefilled country and the ticked address
 * box don't count. */
export function hasEnteredData(
  draft: ApplicationDraft,
  uploads: Record<string, UploadedFile | undefined>,
): boolean {
  if (Object.values(uploads).some(Boolean)) return true;
  const empty = emptyApplicationDraft();
  return JSON.stringify(draft) !== JSON.stringify(empty);
}

// ---------------------------------------------------------------- validation

/** Field keys: "guardians.0.phone", "child.gradeId", "campusId",
 * "emergency.phone", "health.hasMedical", "health.medical",
 * "documents.application_fee_proof", "signature", "agreed". Every key
 * belongs to exactly one step (application-steps.ts). */
export function validateApplication(
  draft: ApplicationDraft,
  options: PublicOptions,
  todayIso: string,
  uploads: Record<string, UploadedFile | undefined>,
): FieldErrors {
  const errors: FieldErrors = {};
  const required = (key: string, value: string, label: string, max = 255) => {
    const v = value.trim();
    if (v === "") errors[key] = `${label} is required`;
    else if (v.length > max) errors[key] = `${label} must be ${max} characters or fewer`;
  };
  const optional = (key: string, value: string, label: string, max: number) => {
    if (value.trim().length > max) errors[key] = `${label} must be ${max} characters or fewer`;
  };

  guardiansToSend(draft).forEach((g, i) => {
    const k = (f: string) => `guardians.${i}.${f}`;
    required(k("surname"), g.surname, "Surname");
    required(k("firstName"), g.firstName, "First name");
    if (!RELATIONSHIP_OPTIONS.some((o) => o.value === g.relationship)) {
      errors[k("relationship")] = "Choose a relationship";
    }
    if (!(RELIGION_OPTIONS as readonly string[]).includes(g.religion)) {
      errors[k("religion")] = "Choose a religion";
    }
    required(k("address"), g.address, "Address");
    required(k("townCity"), g.townCity, "Town or city");
    const phone = phoneError(g.phone);
    if (phone) errors[k("phone")] = phone;
    const email = g.email.trim();
    if (!EMAIL_PATTERN.test(email) || email.length > 254) {
      errors[k("email")] = "Enter a valid email address";
    }
  });

  const c = draft.child;
  required("child.fullName", c.fullName, "Full name");
  const dob = parseDmy(c.dateOfBirth);
  if (!dob || dob > todayIso || dob < "1900-01-01") {
    errors["child.dateOfBirth"] = "Enter the date of birth as dd/mm/yyyy";
  }
  if (!GENDER_OPTIONS.some((o) => o.value === c.gender)) errors["child.gender"] = "Choose one";
  // From the list only (decision Q5); the server caps the length.
  if (c.nationality.trim() === "") errors["child.nationality"] = "Nationality is required";
  else if (!isListedNationality(c.nationality)) {
    errors["child.nationality"] = "Choose a country from the list";
  }
  // With the box ticked, guardian 1's address is used: a gap there shows
  // on guardian 1 (step 1), not twice.
  if (!c.sameAddress) {
    required("child.address", c.address, "Address");
    required("child.townCity", c.townCity, "Town or city");
  }
  optional("child.postalCode", c.postalCode, "Postal code", 20);
  optional("child.country", c.country, "Country", 100);
  if (!currentGradeChoices(options).some((o) => o.value === c.currentGrade)) {
    errors["child.currentGrade"] = "Choose the current grade or class";
  }
  if (c.currentGrade !== NOT_YET_IN_SCHOOL) {
    required("child.currentSchool", c.currentSchool, "Current school");
    optional("child.previousSchoolLocation", c.previousSchoolLocation, "Location", 255);
  }
  if (!options.campuses.some((x) => x.id === draft.campusId)) {
    errors.campusId = "Choose a campus";
  }
  if (!gradesForCampus(options, draft.campusId).some((g) => g.id === c.gradeId)) {
    errors["child.gradeId"] = "Choose a grade from the list";
  }
  if (!options.academicYears.includes(c.academicYear)) {
    errors["child.academicYear"] = "Choose an academic year";
  }
  if (!MONTH_OPTIONS.some((m) => m.value === c.month)) {
    errors["child.month"] = "Choose a month of enrolment";
  }

  required("emergency.name", draft.emergency.name, "Full name");
  required("emergency.relationship", draft.emergency.relationship, "Relationship", 100);
  const ecPhone = phoneError(draft.emergency.phone);
  if (ecPhone) errors["emergency.phone"] = ecPhone;

  // Health: each question needs an explicit Yes or No (no default), and a
  // Yes needs details.
  const h = draft.health;
  const answer = (flagKey: string, flag: YesNo, detailKey: string, value: string) => {
    if (flag === null) errors[flagKey] = "Choose Yes or No";
    else if (flag) required(detailKey, value, "Details", MAX_HEALTH_DETAILS);
  };
  answer("health.hasNeeds", h.hasNeeds, "health.needs", h.needs);
  answer("health.hasMedical", h.hasMedical, "health.medical", h.medical);
  answer("health.hasAllergies", h.hasAllergies, "health.allergies", h.allergies);

  for (const type of requiredDocumentTypes(options, c.gradeId)) {
    if (!uploads[type]) errors[`documents.${type}`] = "Upload this document";
  }

  if (draft.wantsScholarship)
    optional("scholarshipDetails", draft.scholarshipDetails, "Details", 10000);
  required("signature", draft.signature, "Your full name");
  if (!draft.agreed) errors.agreed = "You must agree to the declaration";
  return errors;
}

// ---------------------------------------------------------------- payload

/** The exact shape submit_application accepts. Every document slot with
 * an upload is sent, in slot order; health details
 * only when the answer is yes; the child's address follows guardian 1 when
 * ticked; the previous school location only for a child in school; the
 * date of birth as yyyy-mm-dd. No IP, no time, no age. */
export function buildApplicationPayload(
  draft: ApplicationDraft,
  options: PublicOptions,
  uploads: Record<string, UploadedFile | undefined>,
): Record<string, unknown> {
  const c = draft.child;
  const where = childAddress(draft);
  const inSchool = c.currentGrade !== NOT_YET_IN_SCHOOL;
  const student: Record<string, unknown> = {
    full_name: c.fullName.trim(),
    date_of_birth: parseDmy(c.dateOfBirth) ?? "",
    gender: c.gender,
    nationality: listedNationality(c.nationality) ?? c.nationality.trim(),
    address: where.address.trim(),
    town_city: where.townCity.trim(),
    postal_code: c.postalCode.trim(),
    country: c.country.trim(),
    grade_id: c.gradeId,
    academic_year: c.academicYear,
    month_of_enrollment: c.month,
  };
  if (inSchool) {
    student.current_grade_id = c.currentGrade;
    student.current_school = c.currentSchool.trim();
    student.previous_school_location = c.previousSchoolLocation.trim();
  } else {
    student.prior_schooling = NOT_YET_IN_SCHOOL;
  }
  const h = draft.health;
  // Every slot with an upload, required or not (one file per type).
  const documents = DOCUMENT_SLOTS.flatMap((type) => {
    const u = uploads[type];
    return u ? [{ document_type: type, reservation_id: u.reservationId, path: u.path }] : [];
  });
  return {
    guardians: guardiansToSend(draft).map((g) => ({
      surname: g.surname.trim(),
      first_name: g.firstName.trim(),
      relationship: g.relationship,
      religion: g.religion,
      address: g.address.trim(),
      town_city: g.townCity.trim(),
      phone: storedPhone(g.phone),
      email: g.email.trim(),
    })),
    student,
    campus_id: draft.campusId,
    emergency_contact: {
      name: draft.emergency.name.trim(),
      relationship: draft.emergency.relationship.trim(),
      phone: storedPhone(draft.emergency.phone),
    },
    health_info: {
      has_learning_or_physical_needs: h.hasNeeds === true,
      learning_or_physical_needs_details: h.hasNeeds === true ? h.needs.trim() : "",
      has_medical_conditions: h.hasMedical === true,
      medical_conditions_details: h.hasMedical === true ? h.medical.trim() : "",
      has_allergies_or_dietary_requirements: h.hasAllergies === true,
      allergies_dietary_details: h.hasAllergies === true ? h.allergies.trim() : "",
    },
    documents,
    wants_scholarship_info: draft.wantsScholarship,
    scholarship_interest_details: draft.wantsScholarship ? draft.scholarshipDetails.trim() : "",
    media_consent_agreed: draft.mediaConsent,
    declaration_signature_name: draft.signature.trim(),
    declaration_agreed: draft.agreed,
  };
}

// ---------------------------------------------------------------- responses

export type ApplicationOutcome =
  | { kind: "created"; reference: string }
  | { kind: "closed"; message: string }
  /** The saved application this form came from was already submitted, from
   * another window (slice 10): the page locks instead of showing an error. */
  | { kind: "alreadySubmitted"; message: string }
  | { kind: "refused"; message: string; field?: string; path?: string };

const CHILD_KEYS: Record<string, string> = {
  full_name: "fullName",
  date_of_birth: "dateOfBirth",
  town_city: "townCity",
  postal_code: "postalCode",
  previous_school_location: "previousSchoolLocation",
  current_school: "currentSchool",
  current_grade_id: "currentGrade",
  prior_schooling: "currentGrade",
  grade_id: "gradeId",
  academic_year: "academicYear",
  month_of_enrollment: "month",
};
const GUARDIAN_KEYS: Record<string, string> = { first_name: "firstName", town_city: "townCity" };
const HEALTH_KEYS: Record<string, string> = {
  has_learning_or_physical_needs: "hasNeeds",
  has_medical_conditions: "hasMedical",
  has_allergies_or_dietary_requirements: "hasAllergies",
  learning_or_physical_needs_details: "needs",
  medical_conditions_details: "medical",
  allergies_dietary_details: "allergies",
};

/** The server's field path as this form's error key, or null when it names
 * no single field the form shows. */
export function applicationFieldToKey(path: string | undefined): string | null {
  if (!path) return null;
  let m = /^guardians\.([01])\.([a-z_]+)$/.exec(path);
  if (m) return `guardians.${m[1]}.${GUARDIAN_KEYS[m[2]] ?? m[2]}`;
  m = /^student\.([a-z_]+)$/.exec(path);
  if (m) return `child.${CHILD_KEYS[m[1]] ?? m[1]}`;
  m = /^emergency_contact\.(name|relationship|phone)$/.exec(path);
  if (m) return `emergency.${m[1]}`;
  m = /^health_info\.([a-z_]+)$/.exec(path);
  if (m && HEALTH_KEYS[m[1]]) return `health.${HEALTH_KEYS[m[1]]}`;
  if (path === "campus_id") return "campusId";
  if (path === "declaration_signature_name") return "signature";
  if (path === "declaration_agreed") return "agreed";
  if (path === "scholarship_interest_details") return "scholarshipDetails";
  if (path === "documents") return "documents";
  return null;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** The Edge Function's answer as something the page can show. Anything
 * unexpected, including a network failure (status 0), tells the parent to
 * call the office. */
export function interpretApplicationResponse(status: number, body: unknown): ApplicationOutcome {
  const message =
    isRecord(body) && typeof body.error === "string" && body.error.trim() !== ""
      ? body.error
      : APPLICATION_OFFICE_MESSAGE;
  if (status === 200) {
    const ref = isRecord(body) ? body.reference : undefined;
    if (typeof ref === "string" && /^APP-[0-9]{4}-[0-9]{4,}$/.test(ref)) {
      return { kind: "created", reference: ref };
    }
    return { kind: "refused", message: APPLICATION_OFFICE_MESSAGE };
  }
  if (status === 409) return { kind: "closed", message };
  if (status === 400 && isRecord(body) && body.code === "draft_submitted")
    return { kind: "alreadySubmitted", message };
  if (status === 400) {
    const path = isRecord(body) && typeof body.field === "string" ? body.field : undefined;
    const field = applicationFieldToKey(path);
    return {
      kind: "refused",
      message,
      ...(field ? { field } : {}),
      ...(path !== undefined ? { path } : {}),
    };
  }
  if (status === 429 || status === 503 || status === 500) return { kind: "refused", message };
  return { kind: "refused", message: APPLICATION_OFFICE_MESSAGE };
}
