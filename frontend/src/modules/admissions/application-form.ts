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

/** What a parent sees for each document the public form can ask for. */
export const PUBLIC_DOCUMENT_LABELS: Record<string, string> = {
  application_fee_proof:
    "Proof of payment (bank deposit slip, GIP confirmation or mobile money receipt)",
  proof_of_vaccination: "Proof of vaccination",
  financial_clearance: "Financial clearance",
  previous_report: "Previous school report",
};

export const GENDER_OPTIONS = [
  { value: "female", label: "Female" },
  { value: "male", label: "Male" },
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

export type ApplicationDraft = {
  guardians: GuardianDraft[];
  secondSameAddress: boolean;
  child: {
    fullName: string;
    dateOfBirth: string; // dd/mm/yyyy as typed
    gender: string;
    nationality: string;
    address: string;
    townCity: string;
    currentGrade: string; // a grade id, NOT_YET_IN_SCHOOL, or ""
    currentSchool: string;
    gradeId: string;
    academicYear: string;
    month: string;
  };
  campusId: string;
  emergency: { name: string; relationship: string; phone: string };
  health: {
    hasNeeds: boolean;
    needs: string;
    hasMedical: boolean;
    medical: string;
    hasAllergies: boolean;
    allergies: string;
  };
  signature: string;
  agreed: boolean;
};

export function emptyApplicationDraft(): ApplicationDraft {
  return {
    guardians: [emptyGuardian()],
    secondSameAddress: false,
    child: {
      fullName: "",
      dateOfBirth: "",
      gender: "",
      nationality: "",
      address: "",
      townCity: "",
      currentGrade: "",
      currentSchool: "",
      gradeId: "",
      academicYear: "",
      month: "",
    },
    campusId: "",
    emergency: { name: "", relationship: "", phone: "" },
    health: {
      hasNeeds: false,
      needs: "",
      hasMedical: false,
      medical: "",
      hasAllergies: false,
      allergies: "",
    },
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

// ---------------------------------------------------------------- validation

/** Field keys: "guardians.0.phone", "child.gradeId", "campusId",
 * "emergency.phone", "health.medical", "documents.application_fee_proof",
 * "signature", "agreed". */
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
  required("child.nationality", c.nationality, "Nationality", 100);
  required("child.address", c.address, "Address");
  required("child.townCity", c.townCity, "Town or city");
  if (!currentGradeChoices(options).some((o) => o.value === c.currentGrade)) {
    errors["child.currentGrade"] = "Choose the current grade or class";
  }
  if (c.currentGrade !== NOT_YET_IN_SCHOOL) {
    required("child.currentSchool", c.currentSchool, "Current school");
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

  required("emergency.name", draft.emergency.name, "Name");
  required("emergency.relationship", draft.emergency.relationship, "Relationship", 100);
  const ecPhone = phoneError(draft.emergency.phone);
  if (ecPhone) errors["emergency.phone"] = ecPhone;

  const h = draft.health;
  const details = (key: string, on: boolean, value: string) => {
    if (on) required(key, value, "Details", MAX_HEALTH_DETAILS);
  };
  details("health.needs", h.hasNeeds, h.needs);
  details("health.medical", h.hasMedical, h.medical);
  details("health.allergies", h.hasAllergies, h.allergies);

  for (const type of requiredDocumentTypes(options, c.gradeId)) {
    if (!uploads[type]) errors[`documents.${type}`] = "Upload this document";
  }

  required("signature", draft.signature, "Your full name");
  if (!draft.agreed) errors.agreed = "You must agree to the declaration";
  return errors;
}

// ---------------------------------------------------------------- payload

/** The exact shape submit_application accepts. Only the documents this
 * grade requires are sent; health details only when the answer is yes; the
 * date of birth as yyyy-mm-dd. No IP, no time, no age. */
export function buildApplicationPayload(
  draft: ApplicationDraft,
  options: PublicOptions,
  uploads: Record<string, UploadedFile | undefined>,
): Record<string, unknown> {
  const c = draft.child;
  const student: Record<string, unknown> = {
    full_name: c.fullName.trim(),
    date_of_birth: parseDmy(c.dateOfBirth) ?? "",
    gender: c.gender,
    nationality: c.nationality.trim(),
    address: c.address.trim(),
    town_city: c.townCity.trim(),
    grade_id: c.gradeId,
    academic_year: c.academicYear,
    month_of_enrollment: c.month,
  };
  if (c.currentGrade === NOT_YET_IN_SCHOOL) {
    student.prior_schooling = NOT_YET_IN_SCHOOL;
  } else {
    student.current_grade_id = c.currentGrade;
    student.current_school = c.currentSchool.trim();
  }
  const h = draft.health;
  const documents = requiredDocumentTypes(options, c.gradeId).flatMap((type) => {
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
      has_learning_or_physical_needs: h.hasNeeds,
      learning_or_physical_needs_details: h.hasNeeds ? h.needs.trim() : "",
      has_medical_conditions: h.hasMedical,
      medical_conditions_details: h.hasMedical ? h.medical.trim() : "",
      has_allergies_or_dietary_requirements: h.hasAllergies,
      allergies_dietary_details: h.hasAllergies ? h.allergies.trim() : "",
    },
    documents,
    declaration_signature_name: draft.signature.trim(),
    declaration_agreed: draft.agreed,
  };
}

// ---------------------------------------------------------------- responses

export type ApplicationOutcome =
  | { kind: "created"; reference: string }
  | { kind: "closed"; message: string }
  | { kind: "refused"; message: string; field?: string };

const CHILD_KEYS: Record<string, string> = {
  full_name: "fullName",
  date_of_birth: "dateOfBirth",
  town_city: "townCity",
  current_school: "currentSchool",
  current_grade_id: "currentGrade",
  prior_schooling: "currentGrade",
  grade_id: "gradeId",
  academic_year: "academicYear",
  month_of_enrollment: "month",
};
const GUARDIAN_KEYS: Record<string, string> = { first_name: "firstName", town_city: "townCity" };
const HEALTH_KEYS: Record<string, string> = {
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
  if (status === 400) {
    const field =
      isRecord(body) && typeof body.field === "string" ? applicationFieldToKey(body.field) : null;
    return field ? { kind: "refused", message, field } : { kind: "refused", message };
  }
  if (status === 429 || status === 503 || status === 500) return { kind: "refused", message };
  return { kind: "refused", message: APPLICATION_OFFICE_MESSAGE };
}
