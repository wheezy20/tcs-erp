// The admissions emails (slice 12; wording decided 2026-10-16). Plain
// text only. Every value comes from the outbox row's
// params, which the database limits to references, grade names, academic
// years and, for the staff alert, the match outcome: no name, health answer
// or document name can reach an email. A confirmation email has no link; the
// staff alert links only to the ERP's admissions list, which needs a
// sign-in.
//
// The resume email (slice 10, kind draft_resume) is the one parent email
// with a link: a private link to the parent's own saved application, built
// by the worker at send time from a token it has just been given. Its
// params are always {}; the link and the date it is kept until are passed
// in separately and never stored.
//
// The PDF gate emails (slice 13; D-13f, D-13g, D-13n). pdf_gate goes to the
// lead with the fees PDF attached (the worker attaches it) and one plain
// link to the public enquiry form, with no token: the second exception to
// "no links in a parent email". lead_staff goes to the staff address with
// the grade of interest, the consent answer, the source and a link to the
// lead in the ERP, and no name, email or phone. Both rows' params are
// always {}; the link and the alert's fields are passed in separately.
//
// The offer emails (slice 11; D-11b, D-11k, decided by Eyram 2026-10-22).
// offer goes to each guardian address with a private link to the public
// offer page, made by the worker at send time (the token is passed in,
// never stored), the grade, academic year and APP reference, and the
// respond-by date: the third exception to "no links in a parent email".
// offer_staff goes to the staff address when a parent answers through the
// link: the reference, the response and a link to the application in the
// ERP. No name or contact detail in either.
//
// Rules the tests hold (templates.test.ts): no em or en dash and never the
// word "inquiry" in a subject or body (code names keep "inquiry"; the one
// exception is inside the pdf_gate email's enquiry link, /inquiry); the
// sign-off is the Admissions Office; the same params always give the same
// text, so a matched family and a new family get identical emails.
//
// No Deno globals and no npm imports, so Node's test runner can drive it.

export const EMAIL_KINDS = [
  "inquiry_parent",
  "inquiry_staff",
  "application_parent",
  "application_staff",
  "draft_resume",
  "pdf_gate",
  "lead_staff",
  "offer",
  "offer_staff",
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
  /** offer_staff only. */
  application_id?: string;
  response?: "accepted" | "declined";
};

export type RenderedEmail = { subject: string; text: string };

/** What a resume email needs that is not in the outbox row. */
export type DraftLink = { url: string; expiresAt: string };

/** What an offer email needs that is not in the outbox row. */
export type OfferLink = { url: string; respondBy: string };

/** Only a link to /offer with a 64 hex token fragment is ever printed. */
export const OFFER_LINK = /^https?:\/\/[^\s/#?]+\/offer#token=[0-9a-f]{64}$/;

/** What the lead emails need that is not in the outbox row: the enquiry
 * link (pdf_gate) or the alert's fields from get_lead_alert (lead_staff). */
export type LeadContext = {
  inquiryUrl?: string;
  alert?: {
    lead_id: string;
    grade_interest: string | null;
    consent_to_marketing: boolean;
    source: string;
  };
};

/** The only enquiry link a pdf_gate email may print: https, a host name
 * (not an IP address), and exactly the path /inquiry. */
// The host has a letter in its last label, so an IP address never matches.
export const INQUIRY_LINK = /^https:\/\/([a-z0-9-]+\.)+[a-z][a-z0-9-]*\/inquiry$/;
const LEAD_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const LEAD_SOURCES: Record<string, string> = {
  pdf_gate_admissions_overview: "Admissions Overview download on the school website",
};

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/** "20 November 2026": the date in Accra (UTC all year). */
export function longDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) throw new Error("bad date");
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

/** Only a link to /apply with a 64 hex resume fragment is ever printed. */
const RESUME_LINK = /^https?:\/\/[^\s/#?]+\/apply#resume=[0-9a-f]{64}$/;

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
  if (kind === "draft_resume" || kind === "pdf_gate" || kind === "lead_staff") {
    if (Object.keys(raw).length !== 0) throw new Error(`a ${kind} email has no params`);
    return { references: [] };
  }
  const allowed =
    kind === "application_staff"
      ? ["references", "family_matched", "outcome"]
      : kind === "offer_staff"
        ? ["references", "application_id", "response"]
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
  if (kind === "offer_staff") {
    if (typeof raw.application_id !== "string" || !LEAD_ID.test(raw.application_id))
      throw new Error("application_id malformed");
    if (raw.response !== "accepted" && raw.response !== "declined")
      throw new Error("response malformed");
    params.application_id = raw.application_id;
    params.response = raw.response;
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
  draft?: DraftLink,
  lead?: LeadContext,
  offer?: OfferLink,
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
    case "draft_resume": {
      if (!draft || !RESUME_LINK.test(draft.url))
        throw new Error("a resume email needs its link");
      return {
        subject: "Your saved application",
        text: [
          "Dear Parent or Guardian,",
          "You asked us to keep your application to Treasures Christian School so that you can finish it later. Use this private link to continue where you left off:",
          `  ${draft.url}`,
          "Anyone with this link can open and change your saved application, so please do not forward it.",
          `Your saved application will be kept until ${longDate(draft.expiresAt)}. The health questions, uploaded files and the declaration are not saved, so you will be asked for them again when you continue.`,
          "If you did not ask for this, you can ignore this email. The saved information will be deleted automatically.",
          SIGN_OFF,
        ].join("\n\n"),
      };
    }
    case "pdf_gate": {
      const url = lead?.inquiryUrl;
      if (!url || !INQUIRY_LINK.test(url)) throw new Error("a PDF email needs its enquiry link");
      return {
        subject: "Your TCS Admissions Overview and Fees",
        text: [
          "Dear Parent or Guardian,",
          "Thank you for your interest in Treasures Christian School. Our Admissions Overview and Fees document is attached.",
          "If you would like to take the next step, you can start an enquiry here:",
          `  ${url}`,
          "If you did not ask for this document, you can ignore this email.",
          SIGN_OFF,
        ].join("\n\n"),
      };
    }
    case "lead_staff": {
      const a = lead?.alert;
      if (
        !a ||
        typeof a.lead_id !== "string" ||
        !LEAD_ID.test(a.lead_id) ||
        typeof a.consent_to_marketing !== "boolean" ||
        !(a.source in LEAD_SOURCES) ||
        (a.grade_interest !== null && typeof a.grade_interest !== "string")
      )
        throw new Error("a lead alert needs its fields");
      const grade = a.grade_interest === null ? "" : clean(a.grade_interest).slice(0, 50);
      return {
        subject: "New lead: Admissions Overview download",
        text: [
          "Someone asked for the Admissions Overview and Fees document.",
          [
            `Grade of interest: ${grade === "" ? "not given" : grade}`,
            `Agreed to marketing emails: ${a.consent_to_marketing ? "yes" : "no"}`,
            `Source: ${LEAD_SOURCES[a.source]}`,
          ].join("\n"),
          `Open the lead in the ERP to see the contact details: ${erpBaseUrl.replace(/\/+$/, "")}/admissions/leads?lead=${a.lead_id}`,
        ].join("\n\n"),
      };
    }
    case "offer": {
      if (!offer || !OFFER_LINK.test(offer.url)) throw new Error("an offer email needs its link");
      const r = refs[0];
      return {
        subject: "An offer of a place at Treasures Christian School",
        text: [
          "Dear Parent or Guardian,",
          `We are pleased to offer your child a place at Treasures Christian School in ${r.grade} for the ${r.academic_year} academic year. Your application reference is ${r.reference}.`,
          "Please use this private link to accept or decline the offer:",
          `  ${offer.url}`,
          `The offer is open until ${longDate(offer.respondBy)}. Anyone with this link can answer the offer, so please do not forward this email.`,
          "If you would rather give your answer by phone, or if you have any questions, please contact the admissions office or reply to this email.",
          SIGN_OFF,
        ].join("\n\n"),
      };
    }
    case "offer_staff": {
      const word = p.response === "accepted" ? "accepted" : "declined";
      return {
        subject: `Offer ${refs[0].reference} ${word} through the offer link`,
        text: [
          `A parent ${word} an offer through the offer link.`,
          `Reference: ${refs[0].reference}`,
          `Open the application in the ERP: ${erpBaseUrl.replace(/\/+$/, "")}/admissions/${p.application_id}`,
        ].join("\n\n"),
      };
    }
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
