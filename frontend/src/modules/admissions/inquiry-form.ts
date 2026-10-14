// Pure logic for the public enquiry form (admissions slices 8 and 8b). No
// Supabase, no React. Every rule here is a convenience so a parent sees a
// problem before sending; submit_inquiry checks all of it again and is the
// only guarantee. The form never sends a grade, year or campus as free
// text: only ids from get_public_admissions_options.
//
// Parents see "enquiry"; code, the route (/inquiry) and INQ references
// keep "inquiry".

export const MAX_GUARDIANS = 2;
export const MAX_STUDENTS = 5;

/** A plus sign and digits only, as sent and stored (D-9d revised
 * 2026-10-14): +233 and exactly 9 digits (the first not 0), or another
 * country code (not starting with 0) and 8 to 15 digits in all.
 * submit_inquiry checks the same. */
export function isValidPhone(stored: string): boolean {
  if (stored.startsWith("+233")) return /^\+233[1-9][0-9]{8}$/.test(stored);
  return /^\+[1-9][0-9]{7,14}$/.test(stored);
}
export const PHONE_EXAMPLE = "+233590000000";

/** Shown under the phone field. */
export const PHONE_HINT = "Format: +233590000000. Country code and your number, no spaces.";

/** What the parent typed or pasted into the phone box. Digits typed
 * without a plus sign are a Ghana number and get +233 in front. Spaces,
 * letters, dashes or any other symbol, a leading 0 on a Ghana number, a
 * country code starting with 0 and too many digits are errors, and the
 * text is left as typed so the parent can see it. */
export function readPhoneInput(raw: string): { display: string; error: string | null } {
  if (raw === "") return { display: "", error: null };
  const plus = raw.startsWith("+");
  const digits = plus ? raw.slice(1) : raw;
  if (/\s/.test(raw)) {
    return { display: raw, error: "No spaces. Type the number as +233590000000." };
  }
  if (!/^[0-9]*$/.test(digits)) {
    return { display: raw, error: "Use digits only, with no letters, dashes or other symbols." };
  }
  // Still typing the +233 prefix (or a country code that starts like it).
  if (plus && "233".startsWith(digits)) return { display: `+${digits}`, error: null };

  if (plus && !digits.startsWith("233")) {
    if (digits.startsWith("0")) {
      return { display: raw, error: "A country code doesn't start with 0." };
    }
    if (digits.length > 15) {
      return {
        display: raw,
        error: "Too many digits. A phone number has at most 15 digits after the +.",
      };
    }
    return { display: `+${digits}`, error: null };
  }

  const national = plus ? digits.slice(3) : digits;
  if (national.startsWith("0")) {
    return { display: raw, error: "Leave out the first 0: for 0590000000, type +233590000000." };
  }
  if (national.length > 9) {
    return { display: raw, error: "Too many digits. A Ghana number has 9 digits after +233." };
  }
  return { display: `+233${national}`, error: null };
}

/** The phone as sent and stored: exactly what the box shows. */
export function storedPhone(display: string): string {
  return display;
}

/** The error to show for a phone box, or null when it is complete. */
export function phoneError(display: string): string | null {
  const read = readPhoneInput(display);
  if (read.error) return read.error;
  const stored = storedPhone(read.display);
  if (isValidPhone(stored)) return null;
  return stored === "" || stored.startsWith("+233")
    ? "Enter all 9 digits after +233, for example +233590000000."
    : "Enter the full number: country code and number, 8 to 15 digits after the +.";
}

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

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

/** Stored as the label text; submit_inquiry accepts only these. */
export const RELIGION_OPTIONS = [
  "Christian",
  "Muslim",
  "Traditional",
  "Other",
  "Prefer not to say",
] as const;

/** TCS OS's wording for January; the value sent is the month alone. */
export const MONTH_OPTIONS = [
  { value: "January", label: "January (Limited Admissions)" },
  { value: "September", label: "September" },
] as const;

export const NOT_YET_IN_SCHOOL = "not_yet_in_school";
export const OTHER = "other";

export const OFFICE_MESSAGE =
  "We couldn't take your enquiry online just now. Please call the school office and we'll help you directly.";

// ---------------------------------------------------------------- options

export type PublicGrade = { id: string; name: string; position: number };
export type PublicCampus = { id: string; name: string; acceptedGradeIds: string[] };
export type PublicOptions = {
  intakeOpen: boolean;
  applicationsOpen: boolean;
  grades: PublicGrade[];
  campuses: PublicCampus[];
  academicYears: string[];
};

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** get_public_admissions_options' jsonb, checked field by field. Anything
 * malformed reads as closed with empty lists, so the form never renders
 * choices it can't trust. intake_open is the public inquiries switch. */
export function parsePublicOptions(raw: unknown): PublicOptions {
  const closed: PublicOptions = {
    intakeOpen: false,
    applicationsOpen: false,
    grades: [],
    campuses: [],
    academicYears: [],
  };
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
    applicationsOpen: raw.applications_open === true,
    grades: grades.map((g) => ({ id: g.id, name: g.name, position: g.position })),
    campuses,
    academicYears,
  };
}

/** Whether the enquiry form can be used: public inquiries open and
 * something to choose. The applications switch plays no part. */
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

/** Grades a child may apply into: every active grade with no campus
 * chosen, else the ones that campus accepts. */
export function gradesForCampus(options: PublicOptions, campusId: string): PublicGrade[] {
  if (campusId === "") return options.grades;
  const campus = options.campuses.find((c) => c.id === campusId);
  if (!campus) return [];
  const accepted = new Set(campus.acceptedGradeIds);
  return options.grades.filter((g) => accepted.has(g.id));
}

/** Current grade or class choices: not yet in school, then the active
 * grades. A child at a creche or daycare picks Pre Nursery. */
export function currentGradeChoices(options: PublicOptions): { value: string; label: string }[] {
  return [
    { value: NOT_YET_IN_SCHOOL, label: "N/A (not yet in school)" },
    ...options.grades.map((g) => ({ value: g.id, label: g.name })),
  ];
}

// ---------------------------------------------------------------- date of birth

/** Digits typed into the date of birth box, shown as dd/mm/yyyy with the
 * slashes added automatically. */
export function maskDateInput(raw: string): string {
  const d = raw.replace(/[^0-9]/g, "").slice(0, 8);
  if (d.length <= 2) return d;
  if (d.length <= 4) return `${d.slice(0, 2)}/${d.slice(2)}`;
  return `${d.slice(0, 2)}/${d.slice(2, 4)}/${d.slice(4)}`;
}

/** dd/mm/yyyy as yyyy-mm-dd, or null when it isn't a real calendar date. */
export function parseDmy(text: string): string | null {
  const m = /^([0-9]{2})\/([0-9]{2})\/([0-9]{4})$/.exec(text.trim());
  if (!m) return null;
  const [, dd, mm, yyyy] = m;
  const day = Number(dd);
  const month = Number(mm);
  const year = Number(yyyy);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return `${yyyy}-${mm}-${dd}`;
}

/** DISPLAY ONLY. A rough age for the parent to sanity check what they
 * typed: never sent, never stored, never trusted, and not a rule. The
 * server validates the date of birth on its own. Years and months under 5,
 * whole years from 5. Null for an invalid or future date. */
export function ageHint(dobIso: string | null, todayIso: string): string | null {
  if (!dobIso || dobIso > todayIso) return null;
  const [by, bm, bd] = dobIso.split("-").map(Number);
  const [ty, tm, td] = todayIso.split("-").map(Number);
  let months = (ty - by) * 12 + (tm - bm);
  if (td < bd) months -= 1;
  if (months < 0) return null;
  const years = Math.floor(months / 12);
  const rest = months % 12;
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
  const age =
    years >= 5
      ? plural(years, "year")
      : years === 0
        ? plural(rest, "month")
        : `${plural(years, "year")} ${plural(rest, "month")}`;
  return `Age today: ${age} (a guide only)`;
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
  dateOfBirth: string; // dd/mm/yyyy as typed
  currentGrade: string; // a grade id, NOT_YET_IN_SCHOOL, or ""
  currentSchool: string;
  gradeId: string;
  academicYear: string;
  campusId: string; // "" when no preference
  month: string; // a MONTH_OPTIONS value or ""
};

export type InquiryDraft = {
  referralSource: string;
  referralSourceOther: string;
  comments: string;
  guardians: GuardianDraft[];
  /** Guardian 2 uses guardian 1's address and town or city. */
  secondSameAddress: boolean;
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
    currentGrade: "",
    currentSchool: "",
    gradeId: "",
    academicYear: "",
    campusId: "",
    month: "",
  };
}

export function emptyDraft(): InquiryDraft {
  return {
    referralSource: "",
    referralSourceOther: "",
    comments: "",
    guardians: [emptyGuardian()],
    secondSameAddress: false,
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

/** The guardians as they will be sent: with "Same address as above"
 * ticked, guardian 2 takes guardian 1's address and town or city. */
export function effectiveGuardians(draft: InquiryDraft): GuardianDraft[] {
  return draft.guardians.map((g, i) =>
    i === 1 && draft.secondSameAddress
      ? { ...g, address: draft.guardians[0].address, townCity: draft.guardians[0].townCity }
      : g,
  );
}

/** The current school field is hidden and not needed for a child not yet
 * in school. */
export function needsCurrentSchool(student: StudentDraft): boolean {
  return student.currentGrade !== NOT_YET_IN_SCHOOL;
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

  const guardians = effectiveGuardians(draft);
  if (guardians.length < 1 || guardians.length > MAX_GUARDIANS) {
    errors.guardians = "Give one or two parents or guardians";
  }
  guardians.forEach((g, i) => {
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

  if (draft.students.length < 1 || draft.students.length > MAX_STUDENTS) {
    errors.students = "Give between one and five children";
  }
  const currentChoices = new Set(currentGradeChoices(options).map((c) => c.value));
  draft.students.forEach((s, i) => {
    const k = (f: string) => `students.${i}.${f}`;
    required(k("fullName"), s.fullName, "Full name");
    const dob = parseDmy(s.dateOfBirth);
    if (!dob || dob > todayIso || dob < "1900-01-01") {
      errors[k("dateOfBirth")] = "Enter the date of birth as dd/mm/yyyy";
    }
    if (!currentChoices.has(s.currentGrade)) {
      errors[k("currentGrade")] = "Choose the current grade or class";
    }
    if (needsCurrentSchool(s)) required(k("currentSchool"), s.currentSchool, "Current school");
    if (s.campusId !== "" && !options.campuses.some((c) => c.id === s.campusId)) {
      errors[k("campusId")] = "Choose a campus from the list";
    }
    if (!gradesForCampus(options, s.campusId).some((g) => g.id === s.gradeId)) {
      errors[k("gradeId")] = "Choose a grade from the list";
    }
    if (!options.academicYears.includes(s.academicYear)) {
      errors[k("academicYear")] = "Choose an academic year";
    }
    if (!MONTH_OPTIONS.some((m) => m.value === s.month)) {
      errors[k("month")] = "Choose a month of enrolment";
    }
  });

  return errors;
}

// ---------------------------------------------------------------- payload

/** The exact shape submit_inquiry accepts: no other keys. A campus is sent
 * only when one was chosen; the current school is left out for a child
 * not yet in school; the date of birth goes as yyyy-mm-dd. No age. */
export function buildInquiryPayload(draft: InquiryDraft): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    referral_source: draft.referralSource,
    guardians: effectiveGuardians(draft).map((g) => ({
      surname: g.surname.trim(),
      first_name: g.firstName.trim(),
      relationship: g.relationship,
      religion: g.religion,
      address: g.address.trim(),
      town_city: g.townCity.trim(),
      phone: storedPhone(g.phone),
      email: g.email.trim(),
    })),
    students: draft.students.map((s) => {
      const student: Record<string, unknown> = {
        full_name: s.fullName.trim(),
        date_of_birth: parseDmy(s.dateOfBirth) ?? "",
        grade_id: s.gradeId,
        academic_year: s.academicYear,
        month_of_enrollment: s.month,
      };
      if (s.currentGrade === NOT_YET_IN_SCHOOL) {
        student.prior_schooling = s.currentGrade;
      } else {
        student.current_grade_id = s.currentGrade;
      }
      if (needsCurrentSchool(s)) student.current_school = s.currentSchool.trim();
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
  | { kind: "refused"; message: string; field?: string };

const SERVER_FIELD_KEYS: Record<string, string> = {
  first_name: "firstName",
  town_city: "townCity",
  full_name: "fullName",
  date_of_birth: "dateOfBirth",
  current_school: "currentSchool",
  current_grade_id: "currentGrade",
  prior_schooling: "currentGrade",
  grade_id: "gradeId",
  academic_year: "academicYear",
  campus_id: "campusId",
  month_of_enrollment: "month",
  referral_source: "referralSource",
  referral_source_other: "referralSourceOther",
};

/** The server's field path (guardians.0.town_city) as this form's error key
 * (guardians.0.townCity), or null when it names no single field. */
export function serverFieldToKey(path: string | undefined): string | null {
  if (!path) return null;
  const m = /^(guardians|students)\.([0-4])\.([a-z_]+)$/.exec(path);
  if (m) return `${m[1]}.${m[2]}.${SERVER_FIELD_KEYS[m[3]] ?? m[3]}`;
  if (path === "referral_source" || path === "referral_source_other" || path === "comments") {
    return SERVER_FIELD_KEYS[path] ?? path;
  }
  return null;
}

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
  if (status === 400) {
    const field =
      isRecord(body) && typeof body.field === "string" ? serverFieldToKey(body.field) : null;
    return field ? { kind: "refused", message, field } : { kind: "refused", message };
  }
  if (status === 429 || status === 503 || status === 500) {
    return { kind: "refused", message };
  }
  return { kind: "refused", message: OFFICE_MESSAGE };
}

/** Today in Africa/Accra (UTC, no daylight saving) as yyyy-mm-dd. */
export function todayInAccra(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}
