// The six steps of the public Application form (admissions slice 9b C2),
// as in TCS OS backend/templates/public/apply.html: free navigation in any
// order, a tick in the sidebar once a step's required fields are valid,
// and at submit a list of the steps still incomplete. Pure logic, no
// React: which step a field belongs to, which steps are complete, and
// where a server error sends the parent.

import {
  applicationFieldToKey,
  validateApplication,
  type ApplicationDraft,
  type UploadedFile,
} from "@/modules/admissions/application-form";
import type { FieldErrors, PublicOptions } from "@/modules/admissions/inquiry-form";

export type StepKey =
  "guardians" | "student" | "emergency" | "health" | "documents" | "declaration";

export type Step = { key: StepKey; nav: string; title: string };

/** In TCS OS order: the short sidebar label and the section heading. */
export const STEPS: readonly Step[] = [
  { key: "guardians", nav: "Guardian(s)", title: "Parent / Guardian information" },
  { key: "student", nav: "Student", title: "Student information" },
  { key: "emergency", nav: "Emergency", title: "Emergency Contact" },
  { key: "health", nav: "Health", title: "Health & Wellbeing" },
  { key: "documents", nav: "Documents", title: "Documents & Payment" },
  { key: "declaration", nav: "Declaration", title: "Declaration" },
];

export const LAST_STEP = STEPS.length - 1;

/** The step index a form error key belongs to, or null for a key no step
 * owns (which validateApplication never produces; the tests check that). */
export function stepForField(key: string): number | null {
  const head = key.split(".")[0];
  switch (head) {
    case "guardians":
      return 0;
    case "child":
    case "campusId":
      return 1;
    case "emergency":
      return 2;
    case "health":
      return 3;
    case "documents":
      return 4;
    case "scholarshipDetails":
      return 4;
    case "signature":
    case "agreed":
      return 5;
    default:
      return null;
  }
}

/** The step of each failing field, in step order, without repeats. */
export function incompleteSteps(errors: FieldErrors): number[] {
  const steps = new Set<number>();
  for (const key of Object.keys(errors)) {
    const s = stepForField(key);
    if (s !== null) steps.add(s);
  }
  return [...steps].sort((a, b) => a - b);
}

/** For the sidebar: a step is complete when none of its fields fails the
 * same checks the submit runs. */
export function completeSteps(
  draft: ApplicationDraft,
  options: PublicOptions,
  todayIso: string,
  uploads: Record<string, UploadedFile | undefined>,
): boolean[] {
  const failing = new Set(incompleteSteps(validateApplication(draft, options, todayIso, uploads)));
  return STEPS.map((_, i) => !failing.has(i));
}

/** Where a server refusal goes: the form field key to mark (or null when
 * it names no single field) and the step to show. The child's address and
 * town are guardian 1's while "Same address as Parent/Guardian 1" is
 * ticked, so an error on them is shown on guardian 1. A path that names
 * only a section ("student", "documents") still opens that section. */
export function routeServerError(
  path: string | undefined,
  draft: ApplicationDraft,
): { field: string | null; step: number | null } {
  if (!path) return { field: null, step: null };
  let field = applicationFieldToKey(path);
  if (draft.child.sameAddress && (field === "child.address" || field === "child.townCity")) {
    field = field === "child.address" ? "guardians.0.address" : "guardians.0.townCity";
  }
  if (field) return { field, step: stepForField(field) };
  const head = path.split(".")[0];
  const section: Record<string, number> = {
    guardians: 0,
    student: 1,
    campus_id: 1,
    emergency_contact: 2,
    health_info: 3,
    documents: 4,
    wants_scholarship_info: 4,
    scholarship_interest_details: 4,
    media_consent_agreed: 5,
    declaration_signature_name: 5,
    declaration_agreed: 5,
  };
  return { field: null, step: head in section ? section[head] : null };
}
