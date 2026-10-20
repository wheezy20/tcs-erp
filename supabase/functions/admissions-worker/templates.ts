// The admissions emails (slice 12; wording decided 2026-10-16). Plain
// text only. Every value comes from the outbox row's
// params, which the database limits to references, grade names, academic
// years and, for the staff alert, the match outcome: no name, health answer
// or document name can reach an email. A parent email has no link; the
// staff alert links only to the ERP's admissions list, which needs a
// sign-in.
//
// Rules the tests hold (templates.test.ts): no em or en dash and never the
// word "inquiry" in a subject or body (code names keep "inquiry"); the
// sign-off is the Admissions Office; the same params always give the same
// text, so a matched family and a new family get identical emails.
//
// No Deno globals and no npm imports, so Node's test runner can drive it.

export const EMAIL_KINDS = [
  "inquiry_parent",
  "inquiry_staff",
  "application_parent",
  "application_staff",
] as const;
export type EmailKind = (typeof EMAIL_KINDS)[number];

export type ReferenceLine = {
  reference: string;
  grade: string;
  academic_year: string;
};

export type EmailParams = {
  references: ReferenceLine[];
  family_matched?: boolean;
  outcome?:
    "new_application" | "inquiry_advanced" | "possible_duplicate" | null;
};

export type RenderedEmail = { subject: string; text: string };

const SIGN_OFF = "Kind regards,\nAdmissions Office\nTreasures Christian School";

const INQ_REF = /^INQ-[0-9]{4}-[0-9]{4,}$/;
const APP_REF = /^APP-[0-9]{4}-[0-9]{4,}$/;

/** A grade or year as one plain line: no control characters, no line
 * breaks, single spaces. Values come from the database's own lists. */
function clean(value: string): string {
  return value
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** The params, checked again here so a template never prints anything the
 * database check would have refused. Throws on anything else. */
export function parseParams(kind: EmailKind, raw: unknown): EmailParams {
  if (!isObject(raw)) throw new Error("params is not an object");
  const allowed =
    kind === "application_staff"
      ? ["references", "family_matched", "outcome"]
      : ["references"];
  for (const key of Object.keys(raw)) {
    if (!allowed.includes(key)) throw new Error(`unexpected params key ${key}`);
  }
  const pattern = kind.startsWith("inquiry") ? INQ_REF : APP_REF;
  const refs = raw.references;
  if (!Array.isArray(refs) || refs.length < 1 || refs.length > 20)
    throw new Error("references missing");
  if (pattern === APP_REF && refs.length !== 1)
    throw new Error("an application has one reference");
  const references = refs.map((r) => {
    if (!isObject(r)) throw new Error("reference is not an object");
    for (const key of Object.keys(r)) {
      if (!["reference", "grade", "academic_year"].includes(key))
        throw new Error(`unexpected reference key ${key}`);
    }
    const { reference, grade, academic_year } = r;
    if (
      typeof reference !== "string" ||
      !pattern.test(reference) ||
      typeof grade !== "string" ||
      typeof academic_year !== "string"
    )
      throw new Error("reference line malformed");
    const g = clean(grade);
    const y = clean(academic_year);
    if (g === "" || g.length > 100 || y === "" || y.length > 20)
      throw new Error("grade or year malformed");
    return { reference, grade: g, academic_year: y };
  });
  const params: EmailParams = { references };
  if (kind === "application_staff") {
    if (typeof raw.family_matched !== "boolean")
      throw new Error("family_matched missing");
    const outcome = raw.outcome ?? null;
    if (
      outcome !== null &&
      outcome !== "new_application" &&
      outcome !== "inquiry_advanced" &&
      outcome !== "possible_duplicate"
    )
      throw new Error("outcome malformed");
    params.family_matched = raw.family_matched;
    params.outcome = outcome;
  }
  return params;
}

function line(r: ReferenceLine): string {
  return `${r.reference} (${r.grade}, ${r.academic_year})`;
}

/** One reference as a single line; several in form order, "Child 1 on
 * your form", so siblings in the same grade can be told apart without a
 * name. */
function parentReferences(refs: ReferenceLine[]): string {
  if (refs.length === 1) return `Your reference number:\n  ${line(refs[0])}`;
  return (
    "Your reference numbers:\n" +
    refs.map((r, i) => `  Child ${i + 1} on your form: ${line(r)}`).join("\n")
  );
}

function quote(refs: ReferenceLine[]): string {
  return refs.length === 1 ? "this reference" : "these references";
}

/** The subject and plain-text body for one outbox row. erpBaseUrl is the
 * staff app's origin (staff alerts only). Throws on params it can't use. */
export function renderEmail(
  kind: EmailKind,
  rawParams: unknown,
  erpBaseUrl: string,
): RenderedEmail {
  const p = parseParams(kind, rawParams);
  const refs = p.references;
  const listUrl = `${erpBaseUrl.replace(/\/+$/, "")}/admissions`;

  switch (kind) {
    case "inquiry_parent":
      return {
        subject: "We have received your enquiry",
        text: [
          "Dear Parent or Guardian,",
          "Thank you for your enquiry to Treasures Christian School. Our admissions team has received it and will contact you soon about the next steps.",
          parentReferences(refs),
          `Please quote ${quote(refs)} when you contact us. If you did not make this enquiry, please reply to this email to let us know.`,
          SIGN_OFF,
        ].join("\n\n"),
      };
    case "application_parent":
      return {
        subject: "We have received your application",
        text: [
          "Dear Parent or Guardian,",
          "Thank you for submitting an application to Treasures Christian School. Our admissions team has received your documents and will review your application soon.",
          "Once your application has been reviewed, the school will contact you regarding an admission decision after due process. Submission of an application form and payment of the application fee does not mean admission has been granted.",
          parentReferences(refs),
          `Please quote ${quote(refs)} when you contact us. If you did not make this application, please reply to this email to let us know.`,
          SIGN_OFF,
        ].join("\n\n"),
      };
    case "inquiry_staff":
      return {
        subject:
          refs.length === 1
            ? `New enquiry ${refs[0].reference}`
            : `New enquiry ${refs[0].reference} and ${refs.length - 1} more`,
        text: [
          refs.length === 1
            ? "A new enquiry was submitted for one child."
            : `A new enquiry was submitted for ${refs.length} children.`,
          "References:\n" + refs.map((r) => `  ${line(r)}`).join("\n"),
          `Open the admissions list in the ERP to see the family: ${listUrl}`,
        ].join("\n\n"),
      };
    case "application_staff": {
      const notes: string[] = [];
      if (p.outcome === "inquiry_advanced")
        notes.push("This application continues an earlier enquiry.");
      if (p.outcome === "possible_duplicate")
        notes.push(
          "This may repeat an earlier application for the same child.",
        );
      if (p.family_matched)
        notes.push(
          "The family matched a family already on record. Check the Submission check panel before acting on it.",
        );
      return {
        subject: `New application ${refs[0].reference}`,
        text: [
          "A new application was submitted.",
          `Reference: ${line(refs[0])}`,
          ...(notes.length ? [notes.join("\n")] : []),
          `Open the admissions list in the ERP to see it: ${listUrl}`,
        ].join("\n\n"),
      };
    }
  }
}
