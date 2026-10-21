import {
  emptyApplicationDraft,
  hasEnteredData,
  type ApplicationDraft,
  type UploadedFile,
} from "@/modules/admissions/application-form";
import {
  MAX_GUARDIANS,
  MONTH_OPTIONS,
  NOT_YET_IN_SCHOOL,
  RELATIONSHIP_OPTIONS,
  RELIGION_OPTIONS,
  emptyGuardian,
  type GuardianDraft,
  type PublicOptions,
} from "@/modules/admissions/inquiry-form";
import { NATIONALITIES } from "@/modules/admissions/nationalities";
import { LAST_STEP } from "@/modules/admissions/application-steps";

// Saved applications ("Save and finish later", admissions slice 10). The
// in-browser form state is ApplicationDraft; what the server keeps is a
// "saved application": the same state with the health answers, the
// declaration, the signature and media consent left out (decided by Eyram
// 2026-10-21), and never any file. The database refuses those keys at
// every level, so toSavedState is a courtesy, not the guard.
//
// On resume nothing from the server is trusted as a form value: every
// field is checked again against today's options (a grade, campus or year
// that is gone, or a value not in a list, comes back blank), and anything
// unknown is dropped. Validation still happens only at submit.

/** How long a saved application is kept: 30 days from the last save, at
 * most 60 days from the first. The database's _application_draft_lifetime
 * holds the same numbers; saved-application.test.ts reads the migration
 * and fails if they differ. */
export const SAVED_DAYS = 30;
export const SAVED_CEILING_DAYS = 60;

export type SavedApplicationState = Omit<
  ApplicationDraft,
  "health" | "mediaConsent" | "signature" | "agreed"
>;

/** The state the server may keep. */
export function toSavedState(draft: ApplicationDraft): SavedApplicationState {
  const { health: _h, mediaConsent: _m, signature: _s, agreed: _a, ...kept } = draft;
  return {
    ...kept,
    guardians: kept.guardians.map((g) => ({ ...g })),
    child: { ...kept.child },
    emergency: { ...kept.emergency },
  };
}

/** A comparable snapshot of what a save keeps. */
export function savedKey(draft: ApplicationDraft): string {
  return JSON.stringify(toSavedState(draft));
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function str(v: unknown, max = 10000): string {
  return typeof v === "string" ? v.slice(0, max) : "";
}

function oneOf(v: unknown, allowed: readonly string[]): string {
  return typeof v === "string" && allowed.includes(v) ? v : "";
}

/** The form state rebuilt from a saved application, checked against
 * today's options. Never throws. */
export function fromSavedState(raw: unknown, options: PublicOptions): ApplicationDraft {
  const out = emptyApplicationDraft();
  if (!isRecord(raw)) return out;

  const relationships = RELATIONSHIP_OPTIONS.map((o) => o.value as string);
  const religions = RELIGION_OPTIONS as readonly string[];
  if (Array.isArray(raw.guardians)) {
    const gs = raw.guardians.filter(isRecord).slice(0, MAX_GUARDIANS);
    if (gs.length > 0) {
      out.guardians = gs.map((g): GuardianDraft => ({
        ...emptyGuardian(),
        surname: str(g.surname, 255),
        firstName: str(g.firstName, 255),
        relationship: oneOf(g.relationship, relationships),
        religion: oneOf(g.religion, religions),
        address: str(g.address, 255),
        townCity: str(g.townCity, 255),
        phone: str(g.phone, 32),
        email: str(g.email, 254),
      }));
    }
  }
  out.secondSameAddress = out.guardians.length > 1 && raw.secondSameAddress === true;

  const gradeIds = options.grades.map((g) => g.id);
  const campusIds = options.campuses.map((c) => c.id);
  if (isRecord(raw.child)) {
    const c = raw.child;
    const campusId = oneOf(raw.campusId, campusIds);
    const campus = options.campuses.find((x) => x.id === campusId);
    const gradeId = oneOf(c.gradeId, gradeIds);
    out.campusId = campusId;
    out.child = {
      ...out.child,
      fullName: str(c.fullName, 255),
      dateOfBirth: /^[0-9/]{0,10}$/.test(str(c.dateOfBirth)) ? str(c.dateOfBirth) : "",
      gender: oneOf(c.gender, ["male", "female"]),
      nationality: oneOf(c.nationality, NATIONALITIES),
      sameAddress: c.sameAddress !== false,
      address: str(c.address, 255),
      townCity: str(c.townCity, 255),
      postalCode: str(c.postalCode, 20),
      country: typeof c.country === "string" ? str(c.country, 100) : out.child.country,
      currentGrade: oneOf(c.currentGrade, [...gradeIds, NOT_YET_IN_SCHOOL]),
      currentSchool: str(c.currentSchool, 255),
      previousSchoolLocation: str(c.previousSchoolLocation, 255),
      // A grade the chosen campus no longer takes comes back blank.
      gradeId: campus && !campus.acceptedGradeIds.includes(gradeId) ? "" : gradeId,
      academicYear: oneOf(c.academicYear, options.academicYears),
      month: oneOf(
        c.month,
        MONTH_OPTIONS.map((m) => m.value as string),
      ),
    };
  } else {
    out.campusId = oneOf(raw.campusId, campusIds);
  }

  if (isRecord(raw.emergency)) {
    out.emergency = {
      name: str(raw.emergency.name, 255),
      relationship: str(raw.emergency.relationship, 100),
      phone: str(raw.emergency.phone, 32),
    };
  }
  out.wantsScholarship = raw.wantsScholarship === true;
  out.scholarshipDetails = out.wantsScholarship ? str(raw.scholarshipDetails) : "";
  return out;
}

/** A saved step, clamped to the form's steps. */
export function savedStep(raw: unknown): number {
  return typeof raw === "number" && Number.isInteger(raw) && raw >= 0 && raw <= LAST_STEP ? raw : 0;
}

/** Whether leaving now would lose something: any attached file (files are
 * never saved), anything typed in a part that is never saved (health, the
 * declaration, the signature, media consent), or, once saved, any change
 * since the last save; before any save, anything entered at all. */
export function hasUnsavedChanges(
  draft: ApplicationDraft,
  lastSaved: string | null,
  uploads: Record<string, UploadedFile | undefined>,
): boolean {
  if (Object.values(uploads).some(Boolean)) return true;
  if (lastSaved === null) return hasEnteredData(draft, uploads);
  const empty = emptyApplicationDraft();
  const unsavedParts =
    JSON.stringify(draft.health) !== JSON.stringify(empty.health) ||
    draft.mediaConsent ||
    draft.agreed ||
    draft.signature !== "";
  return unsavedParts || savedKey(draft) !== lastSaved;
}

const RESUME = /^#resume=([0-9a-f]{64})$/;

/** The resume token from a URL fragment ("#resume=<64 hex>"), or null. */
export function readResumeFragment(hash: string): string | null {
  return RESUME.exec(hash)?.[1] ?? null;
}

/** A sensible email to prefill: guardian 1's, when it looks like one. */
export function defaultSaveEmail(draft: ApplicationDraft): string {
  const e = draft.guardians[0]?.email.trim() ?? "";
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e : "";
}

// ---------------------------------------------------------------- answers

export type DraftErrorCode =
  | "draft_invalid"
  | "draft_expired"
  | "draft_submitted"
  | "draft_version"
  | "draft_state"
  | "email"
  | "consent"
  | "draft_email_limit"
  | "draft_limit"
  | "closed"
  | "error";

export type DraftError = { ok: false; code: DraftErrorCode; message: string };

const CODES: readonly DraftErrorCode[] = [
  "draft_invalid",
  "draft_expired",
  "draft_submitted",
  "draft_version",
  "draft_state",
  "email",
  "consent",
  "draft_email_limit",
  "draft_limit",
  "closed",
];

/** A refusal from a draft action. The message is the server's when it
 * sent one, else the fallback; the code says what the page should do. */
export function draftError(status: number, body: unknown, fallback: string): DraftError {
  const b = isRecord(body) ? body : {};
  const message = typeof b.error === "string" && b.error.trim() !== "" ? b.error : fallback;
  const code = CODES.find((c) => c === b.code) ?? (status === 409 ? "closed" : "error");
  // The live-draft limit never shows anything but the generic wording.
  return { ok: false, code, message: code === "draft_limit" ? fallback : message };
}

export type SavedInfo = { version: number; expiresAt: string; emailMasked: string };

function savedInfo(b: Record<string, unknown>): SavedInfo | null {
  return typeof b.version === "number" &&
    typeof b.expires_at === "string" &&
    typeof b.email_masked === "string"
    ? { version: b.version, expiresAt: b.expires_at, emailMasked: b.email_masked }
    : null;
}

export type CreateAnswer = ({ ok: true; token: string } & SavedInfo) | DraftError;

export function interpretCreate(status: number, body: unknown, fallback: string): CreateAnswer {
  if (status === 200 && isRecord(body) && typeof body.draft_token === "string") {
    const info = savedInfo(body);
    if (info && /^[0-9a-f]{64}$/.test(body.draft_token))
      return { ok: true, token: body.draft_token, ...info };
  }
  return draftError(status === 200 ? 500 : status, body, fallback);
}

export type SaveAnswer = ({ ok: true; emailQueued: boolean } & SavedInfo) | DraftError;

export function interpretSave(status: number, body: unknown, fallback: string): SaveAnswer {
  if (status === 200 && isRecord(body) && typeof body.email_queued === "boolean") {
    const info = savedInfo(body);
    if (info) return { ok: true, emailQueued: body.email_queued, ...info };
  }
  return draftError(status === 200 ? 500 : status, body, fallback);
}

export type LoadAnswer = ({ ok: true; state: unknown; step: number } & SavedInfo) | DraftError;

export function interpretLoad(status: number, body: unknown, fallback: string): LoadAnswer {
  if (status === 200 && isRecord(body) && isRecord(body.state)) {
    const info = savedInfo(body);
    if (info) return { ok: true, state: body.state, step: savedStep(body.step), ...info };
  }
  return draftError(status === 200 ? 500 : status, body, fallback);
}

/** The date a saved application is kept until, as the email writes it. */
export function keptUntil(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "Africa/Accra",
  });
}
