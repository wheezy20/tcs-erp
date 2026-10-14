// Pure logic for the public Inquiry form (admissions slice 8). No Supabase,
// no React. Every rule here is a convenience so a parent sees a problem
// before sending; submit_inquiry checks all of it again and is the only
// guarantee. The form never sends a grade, year or campus as free text:
// only ids from get_public_admissions_options.

export const MAX_GUARDIANS = 2;
export const MAX_STUDENTS = 5;

/** A plus sign then 8 to 15 digits, checked after spaces and dashes are
 * removed (D-9d, decided 2026-10-14). */
export const PHONE_PATTERN = /^\+[0-9]{8,15}$/;

/** The phone as stored: spaces and dashes removed, so a plus sign and digits. */
export function cleanPhone(phone: string): string {
  return phone.replace(/[\s-]/g, "");
}
const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const ISO_DATE = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;

export const REFERRAL_OPTIONS = [
  { value: "current_parent", label: "Current parent of TCS" },
  { value: "former_parent", label: "Former parent of TCS" },
  { value: "parent_referral", label: "Parent referral" },
  { value: "staff_referral", label: "Staff referral" },
  { value: "website", label: "Website" },
  { value: "friend_colleague", label: "Friend or colleague" },
  { value: "social_media", label: "Social media" },
  { value: "other", label: "Other" },
] as const;

export const RELATIONSHIP_OPTIONS = [
  { value: "father", label: "Father" },
  { value: "mother", label: "Mother" },
  { value: "guardian", label: "Legal guardian" },
  { value: "other", label: "Other" },
] as const;

/** TCS OS's month choices; "Other" opens a text box (month stays free text). */
export const MONTH_OPTIONS = ["January", "September"] as const;
export const OTHER = "other";

export const OFFICE_MESSAGE =
  "We couldn't take your inquiry online just now. Please call the school office and we'll help you directly.";

// ---------------------------------------------------------------- options

export type PublicGrade = { id: string; name: string; position: number };
export type PublicCampus = { id: string; name: string; acceptedGradeIds: string[] };
export type PublicOptions = {
  intakeOpen: boolean;
  grades: PublicGrade[];
  campuses: PublicCampus[];
  academicYears: string[];
};

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** get_public_admissions_options' jsonb, checked field by field. Anything
 * malformed reads as closed with empty lists, so the form never renders
 * choices it can't trust. */
export function parsePublicOptions(raw: unknown): PublicOptions {
  const closed: PublicOptions = { intakeOpen: false, grades: [], campuses: [], academicYears: [] };
  if (!isRecord(raw)) return closed;
  const grades = Array.isArray(raw.grades)
    ? raw.grades.filter(
        (g): g is PublicGrade =>
          isRecord(g) &&
          typeof g.id === "string" &&
          typeof g.name === "string" &&
          typeof g.position === "number",
      )
    : [];
  const campuses = Array.isArray(raw.campuses)
    ? raw.campuses.flatMap((c) =>
        isRecord(c) &&
        typeof c.id === "string" &&
        typeof c.name === "string" &&
        Array.isArray(c.accepted_grade_ids)
          ? [
              {
                id: c.id,
                name: c.name,
                acceptedGradeIds: c.accepted_grade_ids.filter(
                  (id): id is string => typeof id === "string",
                ),
              },
            ]
          : [],
      )
    : [];
  const academicYears = Array.isArray(raw.academic_years)
    ? raw.academic_years.filter((y): y is string => typeof y === "string")
    : [];
  return {
    intakeOpen: raw.intake_open === true,
    grades: grades.map((g) => ({ id: g.id, name: g.name, position: g.position })),
    campuses,
    academicYears,
  };
}

/** Whether the form can be used: intake open and something to choose. */
export function formAvailable(options: PublicOptions): boolean {
  return options.intakeOpen && options.grades.length > 0 && options.academicYears.length > 0;
}

/** Which screen /inquiry shows, in order. "unavailable" means the build
 * has no Turnstile site key (VITE_TURNSTILE_SITE_KEY was empty when the
 * site was built), so the form can't pass the security check. */
export type InquiryView = "loading" | "loadError" | "created" | "closed" | "unavailable" | "form";

export function inquiryView(state: {
  loading: boolean;
  error: string | null;
  options: PublicOptions | undefined;
  created: boolean;
  closedAfterSubmit: boolean;
  siteKey: string;
}): InquiryView {
  if (state.loading && !state.options) return "loading";
  if (state.error || !state.options) return "loadError";
  if (state.created) return "created";
  if (state.closedAfterSubmit || !formAvailable(state.options)) return "closed";
  if (state.siteKey.trim() === "") return "unavailable";
  return "form";
}

/** Grades a child may pick: every active grade with no campus chosen, else
 * the ones that campus accepts. */
export function gradesForCampus(options: PublicOptions, campusId: string): PublicGrade[] {
  if (campusId === "") return options.grades;
  const campus = options.campuses.find((c) => c.id === campusId);
  if (!campus) return [];
  const accepted = new Set(campus.acceptedGradeIds);
  return options.grades.filter((g) => accepted.has(g.id));
}

// ---------------------------------------------------------------- drafts

export type GuardianDraft = {
  surname: string;
  firstName: string;
  relationship: string;
  religion: string;
  address: string;
  townCity: string;
  phone: string;
  email: string;
};

export type StudentDraft = {
  fullName: string;
  dateOfBirth: string; // yyyy-mm-dd from a date input
  currentSchool: string;
  currentGrade: string;
  gradeId: string;
  academicYear: string;
  campusId: string; // "" when no preference
  month: string; // a MONTH_OPTIONS value, OTHER, or ""
  monthOther: string;
};

export type InquiryDraft = {
  referralSource: string;
  referralSourceOther: string;
  comments: string;
  guardians: GuardianDraft[];
  students: StudentDraft[];
};

export function emptyGuardian(): GuardianDraft {
  return {
    surname: "",
    firstName: "",
    relationship: "",
    religion: "",
    address: "",
    townCity: "",
    phone: "",
    email: "",
  };
}

export function emptyStudent(): StudentDraft {
  return {
    fullName: "",
    dateOfBirth: "",
    currentSchool: "",
    currentGrade: "",
    gradeId: "",
    academicYear: "",
    campusId: "",
    month: "",
    monthOther: "",
  };
}

export function emptyDraft(): InquiryDraft {
  return {
    referralSource: "",
    referralSourceOther: "",
    comments: "",
    guardians: [emptyGuardian()],
    students: [emptyStudent()],
  };
}

/** Changing a child's campus drops a grade that campus doesn't take. */
export function withCampus(
  student: StudentDraft,
  campusId: string,
  options: PublicOptions,
): StudentDraft {
  const allowed = gradesForCampus(options, campusId).some((g) => g.id === student.gradeId);
  return { ...student, campusId, gradeId: allowed ? student.gradeId : "" };
}

// ---------------------------------------------------------------- validation

export type FieldErrors = Record<string, string>;

/** Field keys: "referralSource", "guardians.0.phone", "students.1.gradeId". */
export function validateInquiry(
  draft: InquiryDraft,
  options: PublicOptions,
  todayIso: string,
): FieldErrors {
  const errors: FieldErrors = {};
  const required = (key: string, value: string, label: string, max = 255) => {
    const v = value.trim();
    if (v === "") errors[key] = `${label} is required`;
    else if (v.length > max) errors[key] = `${label} must be ${max} characters or fewer`;
  };

  if (!REFERRAL_OPTIONS.some((o) => o.value === draft.referralSource)) {
    errors.referralSource = "Choose how you heard about us";
  }
  if (draft.referralSource === OTHER) {
    required(
      "referralSourceOther",
      draft.referralSourceOther,
      "Please tell us how you heard about us",
    );
  }
  if (draft.comments.trim().length > 10000) {
    errors.comments = "Comments must be 10,000 characters or fewer";
  }

  if (draft.guardians.length < 1 || draft.guardians.length > MAX_GUARDIANS) {
    errors.guardians = "Give one or two parents or guardians";
  }
  draft.guardians.forEach((g, i) => {
    const k = (f: string) => `guardians.${i}.${f}`;
    required(k("surname"), g.surname, "Surname");
    required(k("firstName"), g.firstName, "First name");
    if (!RELATIONSHIP_OPTIONS.some((o) => o.value === g.relationship)) {
      errors[k("relationship")] = "Choose a relationship";
    }
    required(k("religion"), g.religion, "Religion");
    required(k("address"), g.address, "Address");
    required(k("townCity"), g.townCity, "Town or city");
    if (!PHONE_PATTERN.test(cleanPhone(g.phone))) {
      errors[k("phone")] =
        "Enter + then the country code and number, 8 to 15 digits, e.g. +233551794822";
    }
    const email = g.email.trim();
    if (!EMAIL_PATTERN.test(email) || email.length > 254) {
      errors[k("email")] = "Enter a valid email address";
    }
  });

  if (draft.students.length < 1 || draft.students.length > MAX_STUDENTS) {
    errors.students = "Give between one and five children";
  }
  draft.students.forEach((s, i) => {
    const k = (f: string) => `students.${i}.${f}`;
    required(k("fullName"), s.fullName, "Full name");
    if (!ISO_DATE.test(s.dateOfBirth) || s.dateOfBirth > todayIso || s.dateOfBirth < "1900-01-01") {
      errors[k("dateOfBirth")] = "Enter a valid date of birth";
    }
    required(k("currentSchool"), s.currentSchool, "Current school");
    required(k("currentGrade"), s.currentGrade, "Current grade or class", 50);
    if (s.campusId !== "" && !options.campuses.some((c) => c.id === s.campusId)) {
      errors[k("campusId")] = "Choose a campus from the list";
    }
    if (!gradesForCampus(options, s.campusId).some((g) => g.id === s.gradeId)) {
      errors[k("gradeId")] = "Choose a grade from the list";
    }
    if (!options.academicYears.includes(s.academicYear)) {
      errors[k("academicYear")] = "Choose an academic year";
    }
    if (s.month === OTHER) required(k("monthOther"), s.monthOther, "Month of enrolment", 50);
    else if (!(MONTH_OPTIONS as readonly string[]).includes(s.month)) {
      errors[k("month")] = "Choose a month of enrolment";
    }
  });

  return errors;
}

// ---------------------------------------------------------------- payload

/** The exact shape submit_inquiry accepts: no other keys. A campus is sent
 * only when one was chosen. */
export function buildInquiryPayload(draft: InquiryDraft): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    referral_source: draft.referralSource,
    guardians: draft.guardians.map((g) => ({
      surname: g.surname.trim(),
      first_name: g.firstName.trim(),
      relationship: g.relationship,
      religion: g.religion.trim(),
      address: g.address.trim(),
      town_city: g.townCity.trim(),
      phone: cleanPhone(g.phone),
      email: g.email.trim(),
    })),
    students: draft.students.map((s) => {
      const student: Record<string, unknown> = {
        full_name: s.fullName.trim(),
        date_of_birth: s.dateOfBirth,
        current_school: s.currentSchool.trim(),
        current_grade: s.currentGrade.trim(),
        grade_id: s.gradeId,
        academic_year: s.academicYear,
        month_of_enrollment: s.month === OTHER ? s.monthOther.trim() : s.month,
      };
      if (s.campusId !== "") student.campus_id = s.campusId;
      return student;
    }),
  };
  if (draft.referralSource === OTHER)
    payload.referral_source_other = draft.referralSourceOther.trim();
  if (draft.comments.trim() !== "") payload.comments = draft.comments.trim();
  return payload;
}

// ---------------------------------------------------------------- responses

export type SubmitOutcome =
  | { kind: "created"; references: string[] }
  | { kind: "closed"; message: string }
  | { kind: "refused"; message: string };

/** The Edge Function's answer as something the page can show. Anything
 * unexpected, including a network failure (status 0), tells the parent to
 * call the office. */
export function interpretSubmitResponse(status: number, body: unknown): SubmitOutcome {
  const message =
    isRecord(body) && typeof body.error === "string" && body.error.trim() !== ""
      ? body.error
      : OFFICE_MESSAGE;
  if (status === 200) {
    const refs = isRecord(body) ? body.references : undefined;
    if (Array.isArray(refs) && refs.length > 0 && refs.every((r) => typeof r === "string")) {
      return { kind: "created", references: refs };
    }
    return { kind: "refused", message: OFFICE_MESSAGE };
  }
  if (status === 409) return { kind: "closed", message };
  if (status === 400 || status === 429 || status === 503 || status === 500) {
    return { kind: "refused", message };
  }
  return { kind: "refused", message: OFFICE_MESSAGE };
}

/** Today in Africa/Accra (UTC, no daylight saving) as yyyy-mm-dd. */
export function todayInAccra(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}
