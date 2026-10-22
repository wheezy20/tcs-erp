// The public offer page's pure logic (admissions slice 11; D-11a, D-11f,
// D-11m). No React and no Supabase, so it can be unit tested. The
// admissions-public Edge Function and the database decide everything; this
// file reads the link and words their answers.

/** The emailed link is /offer#token=<64 hex>. A browser never sends the
 * fragment to a server, and the page removes it from the address bar at
 * once. A legacy ?token= link is ignored, so it reads as missing. */
const OFFER_FRAGMENT = /^#token=([0-9a-f]{64})$/;

export function readOfferFragment(hash: string): string | null {
  return OFFER_FRAGMENT.exec(hash)?.[1] ?? null;
}

export type OfferResponse = "accepted" | "declined";

/** What the page may show before the parent answers (D-11a). */
export type OfferDetails = {
  firstName: string;
  grade: string;
  academicYear: string;
  campus: string | null;
  respondBy: string;
};

export type OfferRead =
  | { kind: "open"; details: OfferDetails }
  | { kind: "answered"; response: OfferResponse }
  | { kind: "invalid" }
  | { kind: "limit" }
  | { kind: "error" };

export type OfferAnswer =
  | { kind: "recorded"; response: OfferResponse }
  | { kind: "answered"; response: OfferResponse }
  | { kind: "invalid" }
  | { kind: "limit" }
  | { kind: "error" };

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isResponse(v: unknown): v is OfferResponse {
  return v === "accepted" || v === "declined";
}

function text(v: unknown, max: number): string | null {
  return typeof v === "string" && v.trim() !== "" && v.length <= max ? v : null;
}

/** A refusal by status: 404 is the one generic answer for a link that
 * opens nothing, 429 a rate limit; anything else (including no answer at
 * all) is an error the parent can retry. */
function refusal(status: number): { kind: "invalid" } | { kind: "limit" } | { kind: "error" } {
  if (status === 404) return { kind: "invalid" };
  if (status === 429) return { kind: "limit" };
  return { kind: "error" };
}

export function interpretOfferRead(status: number, body: unknown): OfferRead {
  if (status !== 200 || !isObject(body)) return refusal(status);
  if (body.state === "answered" && isResponse(body.response)) {
    return { kind: "answered", response: body.response };
  }
  const firstName = text(body.first_name, 255);
  const grade = text(body.grade, 100);
  const academicYear = text(body.academic_year, 20);
  const campus = body.campus === null ? null : text(body.campus, 255);
  const respondBy =
    typeof body.respond_by === "string" && !Number.isNaN(Date.parse(body.respond_by))
      ? body.respond_by
      : null;
  if (
    body.state !== "open" ||
    !firstName ||
    !grade ||
    !academicYear ||
    (body.campus !== null && !campus) ||
    !respondBy
  ) {
    return { kind: "error" };
  }
  return { kind: "open", details: { firstName, grade, academicYear, campus, respondBy } };
}

export function interpretOfferAnswer(status: number, body: unknown): OfferAnswer {
  if (status !== 200 || !isObject(body)) return refusal(status);
  if ((body.status === "recorded" || body.status === "answered") && isResponse(body.response)) {
    return { kind: body.status, response: body.response };
  }
  return { kind: "error" };
}

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

/** "5 November 2026": the date in Accra (UTC all year), as the email
 * writes it. */
export function offerDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}
