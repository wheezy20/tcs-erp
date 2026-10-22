// admissions-public: the public request path (admissions slice 8,
// docs/admissions/PORT-PLAN.md; D-8a, D-8d and D-8e decided 2026-10-13).
//
// Everything a visitor who is not signed in can send to the ERP comes
// through here. Slice 8 wired "inquiry"; slice 9a checkpoint 1 adds the
// upload actions, described after this list. The inquiry order of checks:
//
//   1. configuration present, else refuse (fail closed)
//   2. exact Origin allow-list (ADMISSIONS_ALLOWED_ORIGINS), else 403 with no
//      CORS headers
//   3. POST only, JSON only, body at most 32 KB
//   4. per-IP limit (submit_ip): an HMAC of the forwarded IP made here with
//      IP_HASH_KEY, so the database never sees a raw IP. The forwarded
//      header may be spoofable on the hosted runtime (open question in
//      D-8d), so this limit is best effort.
//   5. Turnstile: success, hostname in the allow-list, action "inquiry".
//      Any error, timeout or odd answer refuses (fail closed).
//   6. global limit (submit_global), counted only after Turnstile passes,
//      so requests without a solved challenge can't use it up and close
//      intake for everyone.
//   7. submit_inquiry, which re-validates everything, refuses while intake
//      is closed, and counts the per-email limit in its own transaction.
//
// The limits themselves live in one place, the database function
// _public_rate_limit_rule(). Refusals for any limit give the same message,
// telling the visitor to call the school office. No response says whether
// an email or family already exists: success returns only INQ references.
//
// Upload actions (slice 9a checkpoint 1; D-9f, D-9g, D-9h, D-9l):
//
//   upload_session  steps 1 to 3, then upload_ip (an HMAC of the IP, as
//                   above), Turnstile with action "upload", upload_global
//                   (only after Turnstile), then
//                   open_application_upload_session(), which refuses while
//                   public applications are closed or the open-reservation
//                   cap is full. Returns the session token once. Every
//                   request that passes Turnstile also starts the sweep.
//   upload_url      steps 1 to 3, then reserve_application_upload() with
//                   the session token, which checks the session, the type,
//                   the extension, the per-session file count and the cap,
//                   and makes the storage path. This function then signs
//                   an upload for exactly that path with overwrite off and
//                   returns the reservation id, the path and the upload
//                   token. No Turnstile: the session already cost one.
//   sweep           after the response, claims up to SWEEP_BATCH
//                   reservations that expired unused, deletes their files
//                   through the Storage API and marks them cleaned. A
//                   failure leaves the claim to lapse and be retried.
//
// The application action (slice 9a checkpoint 2; D-9b, D-9c, D-9e, D-9i,
// D-9j): steps 1 to 3 with a 64 KB body cap (application only; the others
// keep 32 KB), then submit_ip (shared with enquiries, D-9l), Turnstile with
// action "application", submit_global (only after Turnstile), then the
// byte check, then submit_application.
//
//   byte check  for each document the payload names whose path has the
//               reservation shape, the first 16 bytes are read from Storage
//               and named pdf, jpeg, png or unknown (sniffKind). Any read
//               failure is "unknown". This function only reports what the
//               bytes are; submit_application decides, against the
//               reservation's own path and extension, and refuses anything
//               missing or unknown. Overwrite is off on every signed upload,
//               so the object can't change after it is read.
//   response    200 with only the APP reference, the same whether the
//               family was new or matched, an enquiry was advanced or a
//               possible duplicate was flagged. No IP is passed on (D-9i).
//
// Saved applications (slice 10; decided by Eyram 2026-10-21). Tokens travel
// only in the POST body, never in a URL, and are never logged:
//
//   draft_create   steps 1 to 3 with the 64 KB cap, then draft_ip (an HMAC
//                  of the IP), Turnstile with action "draft", draft_global
//                  (only after Turnstile), then create_application_draft,
//                  which also queues the resume email. Returns the browser's
//                  draft token once.
//   draft_save     64 KB cap, draft_use_ip, then save_application_draft
//                  (token gated, no Turnstile), optionally queuing a resume
//                  email to the draft's own stored address.
//   draft_get      draft_use_ip, then get_application_draft.
//   draft_delete   draft_use_ip, then delete_application_draft (works while
//                  public applications are closed: erasure is always
//                  allowed).
//   application    may carry draft_token; then submit_application_from_draft
//                  is called instead, which retires the draft in the same
//                  transaction.
//
// The PDF gate (slice 13; D-13a to D-13p, decided 2026-10-21). The
// marketing site (tcsch.edu.gh) posts here cross-origin:
//
//   pdf_gate       origins come from their own secret, ADMISSIONS_LEAD_ORIGINS
//                  (D-13c): an origin on that list may call only pdf_gate,
//                  and pdf_gate accepts only those origins. Steps 1 to 3
//                  with the 32 KB cap, then lead_ip (an HMAC of the IP),
//                  Turnstile with action "pdf_gate" and a hostname from the
//                  lead origins, lead_global (only after Turnstile), then
//                  capture_lead with the source set here. Only the lead
//                  fields are passed on; any other payload key is dropped,
//                  not refused, so a new marketing form field can't cost a
//                  lead. 200 {ok: true}; 400 {error, field?} (field only
//                  name, email, phone or grade_interest); 409 {error, code:
//                  "closed"} while lead capture is closed; 429 for every
//                  limit. A malformed ADMISSIONS_LEAD_ORIGINS refuses only
//                  this action; enquiries and applications keep working.
//
// Offer responses (slice 11; D-11a to D-11n, decided by Eyram 2026-10-22).
// The parent's link carries a 64 hex token in its fragment; the page sends
// it here in the POST body only, and it is never logged:
//
//   offer_get      offer_ip (an HMAC of the IP), offer_global, then
//                  get_offer_by_link: 200 {state: "open", first_name,
//                  grade, academic_year, campus, respond_by} or 200
//                  {state: "answered", response}. Writes nothing.
//   offer_respond  the same limits, then respond_to_offer: 200 {status:
//                  "recorded" | "answered", response}.
//   both           no Turnstile (D-11e: the token is the credential; the
//                  page's confirm step and a read with no side effects
//                  handle link scanners). A link that opens nothing,
//                  whatever the reason (unknown, malformed, replaced,
//                  expired, withdrawn), gets one answer: 404 {error, code:
//                  "offer_invalid"}. Every limit gets 429 {error, code:
//                  "offer_limit"}. No intake switch applies (D-11n).
//
// Draft refusals keep the database's message only for the DETAIL codes in
// DRAFT_CODES (written for parents in the database) and return the code so
// the page can act on it. A live-draft cap (draft_limit) and every rate
// limit get one generic message that never says saved applications exist.
// A resume email cap (draft_email_limit) undoes the save; the page keeps
// what the parent typed and offers to save again without the email.
//
// This file has no Deno globals and no npm imports, so Node's test runner
// can drive it with a fake verifier and fake RPCs (handler.test.ts).
// index.ts wires the real ones. Secrets are passed in, never logged, and
// never put in a response; logs carry an outcome word and, for an
// unexpected database error, only its SQLSTATE.

export const MAX_BODY_BYTES = 32 * 1024;
/** The application carries health details and a long scholarship text. */
export const MAX_APPLICATION_BODY_BYTES = 64 * 1024;
export const SNIFF_BYTES = 16;
export const MAX_APPLICATION_DOCUMENTS = 4;
export const MAX_TOKEN_LENGTH = 2048;
export const TURNSTILE_VERIFY_URL =
  "https://challenges.cloudflare.com/turnstile/v0/siteverify";
export const TURNSTILE_TIMEOUT_MS = 5000;

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
export const SWEEP_BATCH = 20;
export const UPLOAD_DOCUMENT_TYPES = [
  "proof_of_vaccination",
  "financial_clearance",
  "previous_report",
  "application_fee_proof",
] as const;
export const UPLOAD_EXTENSIONS = ["pdf", "jpg", "jpeg", "png"] as const;

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
// Only paths the database makes for a reservation are ever signed or
// deleted, so nothing else in the bucket can be reached through here.
export const UPLOAD_PATH = new RegExp(
  `^uploads/${UUID}/(${UPLOAD_DOCUMENT_TYPES.join("|")})\\.(${UPLOAD_EXTENSIONS.join("|")})$`,
);
const UUID_ONLY = new RegExp(`^${UUID}$`);

export const MESSAGES = {
  office:
    "We couldn't take your enquiry online just now. Please call the school office and we'll help you directly.",
  closed:
    "Online enquiries are closed at the moment. Please call the school office to make an enquiry.",
  verify:
    "We couldn't complete the security check. Please try again, or call the school office if it keeps happening.",
  badRequest:
    "Something about the form didn't come through. Please reload the page and try again.",
  error:
    "Something went wrong on our side. Please try again later, or call the school office.",
  appOffice:
    "We couldn't take your application online just now. Please call the school office and we'll help you directly.",
  appClosed:
    "Online applications are closed at the moment. Please call the school office to apply.",
  fileRejected: "Only PDF, JPG or PNG files of 10 MB or less can be uploaded.",
  appError:
    "Something went wrong on our side. Please try again later, or call the school office to apply.",
  draftRefused: "We could not save your application right now. Please contact the school office.",
  leadOffice:
    "We couldn't send the Admissions Overview just now. Please contact the school office.",
  leadClosed:
    "The Admissions Overview download is not available right now. Please contact the school office.",
  offerInvalid:
    "This link can no longer be used. It may have expired or been replaced by a newer one. Please contact the admissions office.",
  offerLimit:
    "There have been too many attempts from this connection. Please wait a few minutes and try again, or contact the admissions office.",
  offerError:
    "Something went wrong on our side. Please try again later, or contact the admissions office.",
} as const;

/** The lead fields capture_lead reads; anything else in the payload is
 * dropped here. */
export const LEAD_PAYLOAD_KEYS = [
  "name",
  "email",
  "phone",
  "grade_interest",
  "consent_to_marketing",
  "utm_source",
  "utm_medium",
  "utm_campaign",
] as const;
export const LEAD_SOURCE = "pdf_gate_admissions_overview";
const LEAD_FIELDS = ["name", "email", "phone", "grade_interest"];

/** The draft refusals whose database message is shown to the parent. */
export const DRAFT_CODES = [
  "draft_invalid",
  "draft_expired",
  "draft_submitted",
  "draft_version",
  "draft_state",
  "email",
  "consent",
] as const;

const DRAFT_TOKEN = /^[0-9a-f]{64}$/;
export const MAX_DRAFT_EMAIL_LENGTH = 254;

export type Config = {
  allowedOrigins: string[];
  /** The marketing site's origins (ADMISSIONS_LEAD_ORIGINS), which may call
   * only pdf_gate. Null when unset or malformed: pdf_gate is refused. */
  leadOrigins: string[] | null;
  turnstileSecret: string;
  ipHashKey: string;
};

export type TurnstileOutcome = {
  success?: unknown;
  hostname?: unknown;
  action?: unknown;
};

export type RpcResult = {
  data: unknown;
  error: { code?: string; message?: string; details?: string | null } | null;
};

// The payload path submit_inquiry names in a TCS22 error's DETAIL (slice
// 8b), e.g. "guardians.0.phone" or "students.1.grade_id". Passed to the
// form only when it has exactly this shape, so nothing else from the
// database can ride along in the response.
const FIELD_PATH =
  /^(referral_source|referral_source_other|comments|guardians|students|(guardians|students)\.[0-4](\.[a-z_]{1,40})?)$/;

export function safeFieldPath(
  details: string | null | undefined,
): string | null {
  return typeof details === "string" && FIELD_PATH.test(details)
    ? details
    : null;
}

// The payload paths submit_application names (slice 9a), e.g.
// "guardians.1.phone", "student.date_of_birth" or "documents".
const APPLICATION_FIELD_PATH =
  /^(guardians|student|campus_id|emergency_contact|health_info|documents|wants_scholarship_info|scholarship_interest_details|media_consent_agreed|declaration_signature_name|declaration_agreed|guardians\.[01](\.[a-z_]{1,40})?|(student|emergency_contact|health_info)\.[a-z_]{1,40})$/;

export function safeApplicationFieldPath(
  details: string | null | undefined,
): string | null {
  return typeof details === "string" && APPLICATION_FIELD_PATH.test(details)
    ? details
    : null;
}

export type FileKind = "pdf" | "jpeg" | "png" | "unknown";

/** What the leading bytes say a file is. PDF must start with %PDF- at
 * offset 0 (strict: a stranger's file gets no leading junk). */
export function sniffKind(bytes: Uint8Array): FileKind {
  const starts = (sig: number[]) =>
    bytes.length >= sig.length && sig.every((b, i) => bytes[i] === b);
  if (starts([0x25, 0x50, 0x44, 0x46, 0x2d])) return "pdf";
  if (starts([0xff, 0xd8, 0xff])) return "jpeg";
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  return "unknown";
}

export type StorageDeps = {
  /** Signs one upload to exactly this path, overwrite off. Resolves with
   * the upload token; throws on any error. */
  signUpload: (path: string) => Promise<{ token: string }>;
  /** Deletes these paths in the admissions bucket; throws on any error. A
   * path with no file is not an error. */
  remove: (paths: string[]) => Promise<void>;
  /** Up to n leading bytes of the object at this path; throws on any
   * error, including a missing object. */
  readHead: (path: string, n: number) => Promise<Uint8Array>;
};

export type Deps = {
  /** null when a secret is missing or malformed: every request is refused. */
  config: Config | null;
  /** Resolves with Cloudflare's answer; throws on timeout or any error. */
  verifyTurnstile: (token: string, secret: string) => Promise<TurnstileOutcome>;
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RpcResult>;
  log: (outcome: string) => void;
  /** Needed by the upload actions only; without it they refuse. */
  storage?: StorageDeps;
  /** Runs work after the response (EdgeRuntime.waitUntil). Needed by the
   * upload actions only. */
  defer?: (work: Promise<unknown>) => void;
};

/** Exact origins from a comma-separated secret. A value that isn't a bare
 * http(s) origin (a path, a wildcard, a trailing slash) makes the whole
 * list invalid, so a typo refuses everything rather than allowing more. */
export function parseAllowedOrigins(
  raw: string | undefined | null,
): string[] | null {
  if (!raw) return null;
  const items = raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s !== "");
  if (items.length === 0) return null;
  for (const item of items) {
    let url: URL;
    try {
      url = new URL(item);
    } catch {
      return null;
    }
    if (
      (url.protocol !== "https:" && url.protocol !== "http:") ||
      url.origin !== item
    )
      return null;
    // URL accepts "*" in a host name, so wildcards are refused explicitly.
    if (!/^([a-z0-9-]+\.)*[a-z0-9-]+$|^\[[0-9a-f:]+\]$/.test(url.hostname))
      return null;
  }
  return items;
}

const LOOPBACK_HOSTS = ["localhost", "127.0.0.1", "[::1]"];

/** The full config, or null when anything is missing or too weak. On a
 * hosted project (an https SUPABASE_URL) every origin must be https and
 * not loopback: localhost is for local development only (D-8e). */
export function loadConfig(
  get: (name: string) => string | undefined,
): Config | null {
  const allowedOrigins = parseAllowedOrigins(get("ADMISSIONS_ALLOWED_ORIGINS"));
  const turnstileSecret = get("TURNSTILE_SECRET_KEY")?.trim() ?? "";
  const ipHashKey = get("IP_HASH_KEY")?.trim() ?? "";
  if (!allowedOrigins || turnstileSecret === "" || ipHashKey.length < 32)
    return null;
  const hosted = (get("SUPABASE_URL") ?? "").startsWith("https://");
  const unsafe = (o: string) => {
    const url = new URL(o);
    return url.protocol !== "https:" || LOOPBACK_HOSTS.includes(url.hostname);
  };
  if (hosted && allowedOrigins.some(unsafe)) return null;
  let leadOrigins = parseAllowedOrigins(get("ADMISSIONS_LEAD_ORIGINS"));
  if (leadOrigins && hosted && leadOrigins.some(unsafe)) leadOrigins = null;
  return { allowedOrigins, leadOrigins, turnstileSecret, ipHashKey };
}

/** The leftmost x-forwarded-for entry, else "unknown". Best effort: see
 * step 4 above. Never logged or stored; only its HMAC leaves this file. */
export function clientIp(headers: Headers): string {
  const first =
    (headers.get("x-forwarded-for") ?? "").split(",")[0]?.trim() ?? "";
  return first !== "" && first.length <= 100 ? first : "unknown";
}

/** Lowercase hex HMAC-SHA256 of value under key (Web Crypto). */
export async function hmacHex(key: string, value: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(value)),
  );
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** The real verifier, given a fetch. Throws on timeout, a non-200 answer or
 * a body that isn't JSON; the handler treats every throw as a refusal. */
export function makeTurnstileVerifier(
  fetchImpl: typeof fetch,
  timeoutMs = TURNSTILE_TIMEOUT_MS,
): Deps["verifyTurnstile"] {
  return async (token, secret) => {
    const res = await fetchImpl(TURNSTILE_VERIFY_URL, {
      method: "POST",
      body: new URLSearchParams({ secret, response: token }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) throw new Error(`siteverify answered ${res.status}`);
    const body: unknown = await res.json();
    if (typeof body !== "object" || body === null)
      throw new Error("siteverify body is not an object");
    return body as TurnstileOutcome;
  };
}

function corsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "600",
    Vary: "Origin",
  };
}

function respond(
  status: number,
  body: unknown,
  origin: string | null,
): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: {
      ...(origin ? corsHeaders(origin) : {}),
      ...(body === null ? {} : { "Content-Type": "application/json" }),
      "Cache-Control": "no-store",
    },
  });
}

/** The body as text, or null when it is over the cap (by header or by
 * actually counting, since a header can lie or be absent). */
async function readCapped(req: Request, max: number): Promise<string | null> {
  const declared = req.headers.get("content-length");
  if (
    declared !== null &&
    (!/^[0-9]+$/.test(declared) || Number(declared) > max)
  )
    return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    all.set(c, offset);
    offset += c.byteLength;
  }
  return new TextDecoder().decode(all);
}

type ParsedRequest =
  | { action: "inquiry"; token: string; payload: Record<string, unknown> }
  | { action: "upload_session"; token: string }
  | {
      action: "upload_url";
      sessionToken: string;
      documentType: string;
      extension: string;
      size: unknown;
    }
  | {
      action: "application";
      token: string;
      sessionToken: string;
      payload: Record<string, unknown>;
      draftToken: string | null;
    }
  | {
      action: "draft_create";
      token: string;
      email: string;
      state: Record<string, unknown>;
      step: number;
      consent: boolean;
    }
  | {
      action: "draft_save";
      draftToken: string;
      state: Record<string, unknown>;
      step: number;
      version: number;
      sendEmail: boolean;
    }
  | { action: "draft_get"; draftToken: string }
  | { action: "draft_delete"; draftToken: string }
  | { action: "pdf_gate"; token: string; payload: Record<string, unknown> }
  | { action: "offer_get"; offerToken: string }
  | { action: "offer_respond"; offerToken: string; response: "accepted" | "declined" };

/** Actions whose body may use the larger cap. */
const LARGE_BODY_ACTIONS = ["application", "draft_create", "draft_save"];

function turnstileToken(value: unknown): string | null {
  return typeof value === "string" &&
    value !== "" &&
    value.length <= MAX_TOKEN_LENGTH
    ? value
    : null;
}

function onlyKeys(obj: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(obj).every((k) => allowed.includes(k));
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRequest(text: string): ParsedRequest | "unknown_action" | null {
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isObject(body)) return null;
  const b = body;
  if (b.action === "application") {
    if (
      !onlyKeys(b, [
        "action",
        "turnstile_token",
        "session_token",
        "payload",
        "draft_token",
      ])
    )
      return null;
    const token = turnstileToken(b.turnstile_token);
    if (
      token === null ||
      !isObject(b.payload) ||
      typeof b.session_token !== "string" ||
      !/^[0-9a-f]{64}$/.test(b.session_token)
    )
      return null;
    if (
      "draft_token" in b &&
      (typeof b.draft_token !== "string" || !DRAFT_TOKEN.test(b.draft_token))
    )
      return null;
    return {
      action: "application",
      token,
      sessionToken: b.session_token,
      payload: b.payload,
      draftToken: typeof b.draft_token === "string" ? b.draft_token : null,
    };
  }
  if (typeof b.action === "string" && b.action.startsWith("draft_"))
    return parseDraftRequest(b);
  if (b.action === "offer_get" || b.action === "offer_respond") return parseOfferRequest(b);
  if (!onlyKeys(b, ["action", "turnstile_token", "payload"])) return null;

  if (b.action === "inquiry") {
    const token = turnstileToken(b.turnstile_token);
    if (token === null || !isObject(b.payload)) return null;
    return { action: "inquiry", token, payload: b.payload };
  }
  if (b.action === "pdf_gate") {
    const token = turnstileToken(b.turnstile_token);
    if (token === null || !isObject(b.payload)) return null;
    const payload: Record<string, unknown> = {};
    for (const key of LEAD_PAYLOAD_KEYS) {
      if (key in b.payload) payload[key] = b.payload[key];
    }
    return { action: "pdf_gate", token, payload };
  }
  if (b.action === "upload_session") {
    const token = turnstileToken(b.turnstile_token);
    if (token === null || "payload" in b) return null;
    return { action: "upload_session", token };
  }
  if (b.action === "upload_url") {
    const p = b.payload;
    if ("turnstile_token" in b || !isObject(p)) return null;
    if (!onlyKeys(p, ["session_token", "document_type", "extension", "size"]))
      return null;
    if (
      typeof p.session_token !== "string" ||
      !/^[0-9a-f]{64}$/.test(p.session_token) ||
      typeof p.document_type !== "string" ||
      typeof p.extension !== "string"
    )
      return null;
    return {
      action: "upload_url",
      sessionToken: p.session_token,
      documentType: p.document_type,
      extension: p.extension.toLowerCase(),
      size: p.size,
    };
  }
  return "unknown_action";
}

/** The two offer actions. Only the shape is checked here: any string token
 * up to 200 characters goes to the database, so a malformed token gets the
 * same answer as an unknown one. */
function parseOfferRequest(b: Record<string, unknown>): ParsedRequest | null {
  const p = b.payload;
  if (!onlyKeys(b, ["action", "payload"]) || !isObject(p)) return null;
  if (typeof p.token !== "string" || p.token.length > 200) return null;
  if (b.action === "offer_get") {
    if (!onlyKeys(p, ["token"])) return null;
    return { action: "offer_get", offerToken: p.token };
  }
  if (!onlyKeys(p, ["token", "response"])) return null;
  if (p.response !== "accepted" && p.response !== "declined") return null;
  return { action: "offer_respond", offerToken: p.token, response: p.response };
}

function isStep(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 5;
}

/** The four draft actions. Shapes only: the database checks the state's
 * keys, its size, the step, the email and the token. */
function parseDraftRequest(
  b: Record<string, unknown>,
): ParsedRequest | "unknown_action" | null {
  const p = b.payload;
  if (b.action === "draft_create") {
    if (!onlyKeys(b, ["action", "turnstile_token", "payload"]) || !isObject(p))
      return null;
    if (!onlyKeys(p, ["email", "state", "step", "consent"])) return null;
    const token = turnstileToken(b.turnstile_token);
    if (
      token === null ||
      typeof p.email !== "string" ||
      p.email.length > MAX_DRAFT_EMAIL_LENGTH ||
      !isObject(p.state) ||
      !isStep(p.step) ||
      typeof p.consent !== "boolean"
    )
      return null;
    return {
      action: "draft_create",
      token,
      email: p.email,
      state: p.state,
      step: p.step,
      consent: p.consent,
    };
  }
  if (!onlyKeys(b, ["action", "payload"]) || !isObject(p)) {
    return ["draft_save", "draft_get", "draft_delete"].includes(String(b.action))
      ? null
      : "unknown_action";
  }
  if (typeof p.draft_token !== "string" || !DRAFT_TOKEN.test(p.draft_token)) {
    return ["draft_save", "draft_get", "draft_delete"].includes(String(b.action))
      ? null
      : "unknown_action";
  }
  if (b.action === "draft_save") {
    if (!onlyKeys(p, ["draft_token", "state", "step", "version", "send_email"]))
      return null;
    if (
      !isObject(p.state) ||
      !isStep(p.step) ||
      typeof p.version !== "number" ||
      !Number.isInteger(p.version) ||
      p.version < 1 ||
      typeof p.send_email !== "boolean"
    )
      return null;
    return {
      action: "draft_save",
      draftToken: p.draft_token,
      state: p.state,
      step: p.step,
      version: p.version,
      sendEmail: p.send_email,
    };
  }
  if (b.action === "draft_get" || b.action === "draft_delete") {
    if (!onlyKeys(p, ["draft_token"])) return null;
    return b.action === "draft_get"
      ? { action: "draft_get", draftToken: p.draft_token }
      : { action: "draft_delete", draftToken: p.draft_token };
  }
  return "unknown_action";
}

async function underLimit(
  deps: Deps,
  args: Record<string, unknown>,
): Promise<boolean | "error"> {
  try {
    const { data, error } = await deps.rpc("check_public_rate_limit", args);
    if (error || typeof data !== "boolean") return "error";
    return data;
  } catch {
    return "error";
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const config = deps.config;
  if (!config) {
    deps.log("misconfigured");
    return respond(503, { error: MESSAGES.office }, null);
  }

  // An origin on either list gets a preflight answer; which actions it may
  // call is checked once the action is known.
  const origin = req.headers.get("origin");
  const staffOrigin = origin !== null && config.allowedOrigins.includes(origin);
  const leadOrigin = origin !== null && (config.leadOrigins ?? []).includes(origin);
  if (origin === null || (!staffOrigin && !leadOrigin)) {
    deps.log("origin_refused");
    return respond(403, { error: "Origin not allowed" }, null);
  }

  if (req.method === "OPTIONS") return respond(204, null, origin);
  if (req.method !== "POST") {
    deps.log("method_refused");
    return respond(405, { error: MESSAGES.badRequest }, origin);
  }
  const contentType = (req.headers.get("content-type") ?? "").toLowerCase();
  if (!contentType.startsWith("application/json")) {
    deps.log("content_type_refused");
    return respond(415, { error: MESSAGES.badRequest }, origin);
  }

  // Read up to the application's cap; every other action is held to the
  // smaller one once its action is known.
  let text: string | null;
  try {
    text = await readCapped(req, MAX_APPLICATION_BODY_BYTES);
  } catch {
    deps.log("body_unreadable");
    return respond(400, { error: MESSAGES.badRequest }, origin);
  }
  if (text === null) {
    deps.log("too_large");
    return respond(413, { error: MESSAGES.badRequest }, origin);
  }
  const parsed = parseRequest(text);
  if (parsed === "unknown_action" || parsed === null) {
    deps.log(parsed === null ? "bad_request" : "unknown_action");
    return respond(400, { error: MESSAGES.badRequest }, origin);
  }
  if (
    !LARGE_BODY_ACTIONS.includes(parsed.action) &&
    new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES
  ) {
    deps.log("too_large");
    return respond(413, { error: MESSAGES.badRequest }, origin);
  }
  // A marketing origin reaches only the PDF gate, and the PDF gate only
  // from a marketing origin (D-13c).
  if (!(parsed.action === "pdf_gate" ? leadOrigin : staffOrigin)) {
    deps.log("origin_refused");
    return respond(403, { error: "Origin not allowed" }, null);
  }
  if (parsed.action === "pdf_gate") return handlePdfGate(req, parsed, deps, config, origin);
  if (parsed.action === "application") return handleApplication(req, parsed, deps, config, origin);
  if (parsed.action === "upload_session")
    return handleUploadSession(req, parsed.token, deps, config, origin);
  if (parsed.action === "upload_url")
    return handleUploadUrl(parsed, deps, origin);
  if (
    parsed.action === "draft_create" ||
    parsed.action === "draft_save" ||
    parsed.action === "draft_get" ||
    parsed.action === "draft_delete"
  )
    return handleDraft(req, parsed, deps, config, origin);
  if (parsed.action === "offer_get" || parsed.action === "offer_respond")
    return handleOffer(req, parsed, deps, config, origin);

  // 4. per-IP, before spending a Turnstile call.
  let ipKey: string;
  try {
    ipKey = await hmacHex(config.ipHashKey, clientIp(req.headers));
  } catch {
    deps.log("ip_hash_failed");
    return respond(503, { error: MESSAGES.office }, origin);
  }
  const ipOk = await underLimit(deps, {
    p_bucket: "submit_ip",
    p_key_hash: ipKey,
  });
  if (ipOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.office }, origin);
  }
  if (!ipOk) {
    deps.log("ip_limited");
    return respond(429, { error: MESSAGES.office }, origin);
  }

  // 5. Turnstile, failing closed.
  let outcome: TurnstileOutcome;
  try {
    outcome = await deps.verifyTurnstile(parsed.token, config.turnstileSecret);
  } catch {
    deps.log("turnstile_unavailable");
    return respond(503, { error: MESSAGES.verify }, origin);
  }
  if (!turnstilePassed(outcome, config, "inquiry")) {
    deps.log("turnstile_refused");
    return respond(400, { error: MESSAGES.verify }, origin);
  }

  // 6. global, only for solved challenges.
  const globalOk = await underLimit(deps, { p_bucket: "submit_global" });
  if (globalOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.office }, origin);
  }
  if (!globalOk) {
    deps.log("global_limited");
    return respond(429, { error: MESSAGES.office }, origin);
  }

  // 7. the write.
  let result: RpcResult;
  try {
    result = await deps.rpc("submit_inquiry", { p_payload: parsed.payload });
  } catch {
    deps.log("submit_error");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  if (result.error) {
    switch (result.error.code) {
      case "TCS22": {
        deps.log("invalid");
        const field = safeFieldPath(result.error.details);
        return respond(
          400,
          {
            error: result.error.message ?? MESSAGES.badRequest,
            ...(field ? { field } : {}),
          },
          origin,
        );
      }
      case "TCS03":
        deps.log("closed");
        return respond(409, { error: MESSAGES.closed }, origin);
      case "TCS29":
        deps.log("email_limited");
        return respond(429, { error: MESSAGES.office }, origin);
      default: {
        const code = /^[0-9A-Z]{5}$/.test(result.error.code ?? "")
          ? result.error.code
          : "unknown";
        deps.log(`submit_failed_${code}`);
        return respond(500, { error: MESSAGES.error }, origin);
      }
    }
  }
  const refs = result.data;
  if (
    !Array.isArray(refs) ||
    refs.length === 0 ||
    !refs.every((r) => typeof r === "string")
  ) {
    deps.log("submit_bad_result");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  deps.log("created");
  return respond(200, { references: refs }, origin);
}

/** success, a hostname from the allow-list, and exactly this action. The
 * PDF gate checks against the marketing origins instead. */
function turnstilePassed(outcome: TurnstileOutcome, config: Config, action: string): boolean {
  const origins = action === "pdf_gate" ? (config.leadOrigins ?? []) : config.allowedOrigins;
  const hostnames = origins.map((o) => new URL(o).hostname);
  return (
    outcome.success === true &&
    typeof outcome.hostname === "string" &&
    hostnames.includes(outcome.hostname) &&
    outcome.action === action
  );
}

/** Maps the upload RPCs' refusals. TCS22 messages are written for parents
 * in the database and are shown as they are; nothing else is passed on. */
function uploadRefusal(
  error: NonNullable<RpcResult["error"]>,
  deps: Deps,
  origin: string,
  prefix: string,
): Response {
  switch (error.code) {
    case "TCS22":
      deps.log(`${prefix}_invalid`);
      return respond(
        400,
        { error: error.message ?? MESSAGES.badRequest },
        origin,
      );
    case "TCS03":
      deps.log(`${prefix}_closed`);
      return respond(409, { error: MESSAGES.appClosed }, origin);
    case "TCS29":
      deps.log(`${prefix}_limited`);
      return respond(429, { error: MESSAGES.appOffice }, origin);
    default: {
      const code = /^[0-9A-Z]{5}$/.test(error.code ?? "")
        ? error.code
        : "unknown";
      deps.log(`${prefix}_failed_${code}`);
      return respond(500, { error: MESSAGES.error }, origin);
    }
  }
}

async function handleUploadSession(
  req: Request,
  token: string,
  deps: Deps,
  config: Config,
  origin: string,
): Promise<Response> {
  if (!deps.storage || !deps.defer) {
    deps.log("misconfigured");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }

  let ipKey: string;
  try {
    ipKey = await hmacHex(config.ipHashKey, clientIp(req.headers));
  } catch {
    deps.log("ip_hash_failed");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  const ipOk = await underLimit(deps, {
    p_bucket: "upload_ip",
    p_key_hash: ipKey,
  });
  if (ipOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  if (!ipOk) {
    deps.log("upload_ip_limited");
    return respond(429, { error: MESSAGES.appOffice }, origin);
  }

  let outcome: TurnstileOutcome;
  try {
    outcome = await deps.verifyTurnstile(token, config.turnstileSecret);
  } catch {
    deps.log("turnstile_unavailable");
    return respond(503, { error: MESSAGES.verify }, origin);
  }
  if (!turnstilePassed(outcome, config, "upload")) {
    deps.log("turnstile_refused");
    return respond(400, { error: MESSAGES.verify }, origin);
  }

  // Every solved request sweeps, whatever happens next, so a full cap can
  // still drain.
  deps.defer(sweepExpiredUploads(deps));

  const globalOk = await underLimit(deps, { p_bucket: "upload_global" });
  if (globalOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  if (!globalOk) {
    deps.log("upload_global_limited");
    return respond(429, { error: MESSAGES.appOffice }, origin);
  }

  let result: RpcResult;
  try {
    result = await deps.rpc("open_application_upload_session", {});
  } catch {
    deps.log("upload_session_error");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  if (result.error)
    return uploadRefusal(result.error, deps, origin, "upload_session");
  const d = result.data;
  if (
    !isObject(d) ||
    typeof d.session_token !== "string" ||
    !/^[0-9a-f]{64}$/.test(d.session_token) ||
    typeof d.expires_at !== "string" ||
    typeof d.max_files !== "number"
  ) {
    deps.log("upload_session_bad_result");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  deps.log("upload_session_opened");
  return respond(
    200,
    {
      session_token: d.session_token,
      expires_at: d.expires_at,
      max_files: d.max_files,
    },
    origin,
  );
}

async function handleUploadUrl(
  parsed: Extract<ParsedRequest, { action: "upload_url" }>,
  deps: Deps,
  origin: string,
): Promise<Response> {
  if (!deps.storage) {
    deps.log("misconfigured");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  // A fast refusal for the parent; the bucket checks the real bytes.
  const size = parsed.size;
  if (
    !(UPLOAD_DOCUMENT_TYPES as readonly string[]).includes(
      parsed.documentType,
    ) ||
    !(UPLOAD_EXTENSIONS as readonly string[]).includes(parsed.extension) ||
    typeof size !== "number" ||
    !Number.isInteger(size) ||
    size < 1 ||
    size > MAX_UPLOAD_BYTES
  ) {
    deps.log("upload_file_refused");
    return respond(400, { error: MESSAGES.fileRejected }, origin);
  }

  let result: RpcResult;
  try {
    result = await deps.rpc("reserve_application_upload", {
      p_session_token: parsed.sessionToken,
      p_document_type: parsed.documentType,
      p_extension: parsed.extension,
    });
  } catch {
    deps.log("upload_reserve_error");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  if (result.error)
    return uploadRefusal(result.error, deps, origin, "upload_reserve");
  const d = result.data;
  if (
    !isObject(d) ||
    typeof d.reservation_id !== "string" ||
    !UUID_ONLY.test(d.reservation_id) ||
    typeof d.storage_path !== "string" ||
    !UPLOAD_PATH.test(d.storage_path) ||
    !d.storage_path.startsWith(`uploads/${d.reservation_id}/`) ||
    typeof d.expires_at !== "string"
  ) {
    deps.log("upload_reserve_bad_result");
    return respond(500, { error: MESSAGES.error }, origin);
  }

  let signed: { token: string };
  try {
    signed = await deps.storage.signUpload(d.storage_path);
  } catch {
    // The reservation stays unused and the sweep removes it later.
    deps.log("upload_sign_failed");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  if (typeof signed?.token !== "string" || signed.token === "") {
    deps.log("upload_sign_failed");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  deps.log("upload_reserved");
  return respond(
    200,
    {
      reservation_id: d.reservation_id,
      path: d.storage_path,
      upload_token: signed.token,
      expires_at: d.expires_at,
    },
    origin,
  );
}

/** Deletes the files of up to SWEEP_BATCH reservations that expired unused,
 * then marks them cleaned. Never throws; logs one outcome word. Only paths
 * of the reservation shape are deleted, whatever the database returns. */
export async function sweepExpiredUploads(deps: Deps): Promise<void> {
  try {
    if (!deps.storage) return;
    const claim = await deps.rpc("claim_expired_application_uploads", {
      p_limit: SWEEP_BATCH,
    });
    if (claim.error || !Array.isArray(claim.data)) {
      deps.log("sweep_claim_failed");
      return;
    }
    const rows = claim.data.filter(
      (r): r is { reservation_id: string; storage_path: string } =>
        isObject(r) &&
        typeof r.reservation_id === "string" &&
        UUID_ONLY.test(r.reservation_id) &&
        typeof r.storage_path === "string" &&
        UPLOAD_PATH.test(r.storage_path) &&
        r.storage_path.startsWith(`uploads/${r.reservation_id}/`),
    );
    if (rows.length !== claim.data.length) deps.log("sweep_odd_rows");
    if (rows.length === 0) return;
    await deps.storage.remove(rows.map((r) => r.storage_path));
    const done = await deps.rpc("finish_application_upload_cleanup", {
      p_reservation_ids: rows.map((r) => r.reservation_id),
    });
    deps.log(done.error ? "sweep_finish_failed" : "sweep_cleaned");
  } catch {
    deps.log("sweep_failed");
  }
}

/** The {reservation_id, path, kind} report for each document the payload
 * names with a reservation-shaped path, at most
 * MAX_APPLICATION_DOCUMENTS. Anything else is left out, and the database
 * refuses a document with no report. Reads run in parallel; a failed read
 * is "unknown". */
export async function sniffDocuments(
  payload: Record<string, unknown>,
  storage: StorageDeps,
): Promise<{ reservation_id: string; path: string; kind: FileKind }[]> {
  const docs = Array.isArray(payload.documents) ? payload.documents : [];
  const wanted = docs
    .slice(0, MAX_APPLICATION_DOCUMENTS)
    .filter(
      (d): d is { reservation_id: string; path: string } =>
        isObject(d) &&
        typeof d.reservation_id === "string" &&
        UUID_ONLY.test(d.reservation_id) &&
        typeof d.path === "string" &&
        UPLOAD_PATH.test(d.path) &&
        d.path.startsWith(`uploads/${d.reservation_id}/`),
    );
  return Promise.all(
    wanted.map(async (d) => {
      let kind: FileKind = "unknown";
      try {
        kind = sniffKind(await storage.readHead(d.path, SNIFF_BYTES));
      } catch {
        kind = "unknown";
      }
      return { reservation_id: d.reservation_id, path: d.path, kind };
    }),
  );
}

async function handleApplication(
  req: Request,
  parsed: Extract<ParsedRequest, { action: "application" }>,
  deps: Deps,
  config: Config,
  origin: string,
): Promise<Response> {
  if (!deps.storage) {
    deps.log("misconfigured");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }

  let ipKey: string;
  try {
    ipKey = await hmacHex(config.ipHashKey, clientIp(req.headers));
  } catch {
    deps.log("ip_hash_failed");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  const ipOk = await underLimit(deps, {
    p_bucket: "submit_ip",
    p_key_hash: ipKey,
  });
  if (ipOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  if (!ipOk) {
    deps.log("ip_limited");
    return respond(429, { error: MESSAGES.appOffice }, origin);
  }

  let outcome: TurnstileOutcome;
  try {
    outcome = await deps.verifyTurnstile(parsed.token, config.turnstileSecret);
  } catch {
    deps.log("turnstile_unavailable");
    return respond(503, { error: MESSAGES.verify }, origin);
  }
  if (!turnstilePassed(outcome, config, "application")) {
    deps.log("turnstile_refused");
    return respond(400, { error: MESSAGES.verify }, origin);
  }

  const globalOk = await underLimit(deps, { p_bucket: "submit_global" });
  if (globalOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.appOffice }, origin);
  }
  if (!globalOk) {
    deps.log("global_limited");
    return respond(429, { error: MESSAGES.appOffice }, origin);
  }

  const sniffed = await sniffDocuments(parsed.payload, deps.storage);

  let result: RpcResult;
  try {
    result = parsed.draftToken
      ? await deps.rpc("submit_application_from_draft", {
          p_payload: parsed.payload,
          p_session_token: parsed.sessionToken,
          p_sniffed: sniffed,
          p_draft_token: parsed.draftToken,
        })
      : await deps.rpc("submit_application", {
          p_payload: parsed.payload,
          p_session_token: parsed.sessionToken,
          p_sniffed: sniffed,
        });
  } catch {
    deps.log("application_error");
    return respond(500, { error: MESSAGES.appError }, origin);
  }
  if (result.error) {
    switch (result.error.code) {
      case "TCS22": {
        // A second window submitting a draft already submitted: the page
        // locks the form rather than showing an error.
        if (result.error.details === "draft_submitted") {
          deps.log("application_draft_submitted");
          return respond(
            400,
            { error: result.error.message ?? MESSAGES.badRequest, code: "draft_submitted" },
            origin,
          );
        }
        deps.log("application_invalid");
        const field = safeApplicationFieldPath(result.error.details);
        return respond(
          400,
          {
            error: result.error.message ?? MESSAGES.badRequest,
            ...(field ? { field } : {}),
          },
          origin,
        );
      }
      case "TCS03":
        deps.log("application_closed");
        return respond(409, { error: MESSAGES.appClosed }, origin);
      case "TCS29":
        deps.log("application_email_limited");
        return respond(429, { error: MESSAGES.appOffice }, origin);
      default: {
        const code = /^[0-9A-Z]{5}$/.test(result.error.code ?? "")
          ? result.error.code
          : "unknown";
        deps.log(`application_failed_${code}`);
        return respond(500, { error: MESSAGES.appError }, origin);
      }
    }
  }
  const reference = result.data;
  if (
    typeof reference !== "string" ||
    !/^APP-[0-9]{4}-[0-9]{4,}$/.test(reference)
  ) {
    deps.log("application_bad_result");
    return respond(500, { error: MESSAGES.appError }, origin);
  }
  deps.log("application_created");
  return respond(200, { reference }, origin);
}

/** Maps the draft RPCs' refusals (see the header). */
export function draftRefusal(
  error: NonNullable<RpcResult["error"]>,
  deps: Deps,
  origin: string,
): Response {
  const detail = error.details ?? "";
  switch (error.code) {
    case "TCS22":
      if ((DRAFT_CODES as readonly string[]).includes(detail)) {
        deps.log(`draft_${detail.replace(/^draft_/, "")}`);
        return respond(
          detail === "draft_version" ? 409 : 400,
          { error: error.message ?? MESSAGES.badRequest, code: detail },
          origin,
        );
      }
      deps.log("draft_invalid_other");
      return respond(400, { error: MESSAGES.badRequest }, origin);
    case "TCS03":
      deps.log("draft_closed");
      return respond(409, { error: MESSAGES.appClosed, code: "closed" }, origin);
    case "TCS29":
      if (detail === "draft_email_limit" && error.message) {
        deps.log("draft_email_limited");
        return respond(429, { error: error.message, code: "draft_email_limit" }, origin);
      }
      deps.log("draft_limited");
      return respond(429, { error: MESSAGES.draftRefused, code: "draft_limit" }, origin);
    default: {
      const code = /^[0-9A-Z]{5}$/.test(error.code ?? "") ? error.code : "unknown";
      deps.log(`draft_failed_${code}`);
      return respond(500, { error: MESSAGES.appError }, origin);
    }
  }
}

function limited(deps: Deps, origin: string, outcome: string): Response {
  deps.log(outcome);
  return respond(429, { error: MESSAGES.draftRefused, code: "draft_limit" }, origin);
}

function isIso(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function isMasked(value: unknown): value is string {
  return typeof value === "string" && value.length <= 300 && value.includes("\u2022");
}

type OfferRequest = Extract<ParsedRequest, { action: "offer_get" | "offer_respond" }>;

function offerInvalid(deps: Deps, origin: string, outcome: string): Response {
  deps.log(outcome);
  return respond(404, { error: MESSAGES.offerInvalid, code: "offer_invalid" }, origin);
}

function shortText(value: unknown, max: number): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= max;
}

/** offer_get and offer_respond (slice 11). The limits come before any
 * token lookup; the database decides everything about the token. Only the
 * fields listed here ever reach the response. */
async function handleOffer(
  req: Request,
  parsed: OfferRequest,
  deps: Deps,
  config: Config,
  origin: string,
): Promise<Response> {
  let ipKey: string;
  try {
    ipKey = await hmacHex(config.ipHashKey, clientIp(req.headers));
  } catch {
    deps.log("ip_hash_failed");
    return respond(503, { error: MESSAGES.offerError }, origin);
  }
  for (const args of [{ p_bucket: "offer_ip", p_key_hash: ipKey }, { p_bucket: "offer_global" }]) {
    const ok = await underLimit(deps, args);
    if (ok === "error") {
      deps.log("rate_limit_error");
      return respond(503, { error: MESSAGES.offerError }, origin);
    }
    if (!ok) {
      deps.log(args.p_bucket === "offer_ip" ? "offer_ip_limited" : "offer_global_limited");
      return respond(429, { error: MESSAGES.offerLimit, code: "offer_limit" }, origin);
    }
  }

  let result: RpcResult;
  try {
    result =
      parsed.action === "offer_get"
        ? await deps.rpc("get_offer_by_link", { p_token: parsed.offerToken })
        : await deps.rpc("respond_to_offer", {
            p_token: parsed.offerToken,
            p_response: parsed.response,
          });
  } catch {
    deps.log("offer_error");
    return respond(500, { error: MESSAGES.offerError }, origin);
  }
  if (result.error) {
    deps.log(`offer_db_error_${result.error.code ?? "unknown"}`);
    return respond(500, { error: MESSAGES.offerError }, origin);
  }
  const d = result.data;
  if (d === null || d === undefined) return offerInvalid(deps, origin, "offer_invalid");
  const bad = () => {
    deps.log("offer_bad_result");
    return respond(500, { error: MESSAGES.offerError }, origin);
  };
  if (!isObject(d)) return bad();
  const answered = (r: unknown) => r === "accepted" || r === "declined";

  if (parsed.action === "offer_get") {
    if (d.state === "answered" && answered(d.response)) {
      deps.log("offer_read_answered");
      return respond(200, { state: "answered", response: d.response }, origin);
    }
    if (
      d.state !== "open" ||
      !shortText(d.first_name, 255) ||
      !shortText(d.grade, 100) ||
      !shortText(d.academic_year, 20) ||
      !(d.campus === null || shortText(d.campus, 255)) ||
      !isIso(d.respond_by)
    )
      return bad();
    deps.log("offer_read_open");
    return respond(
      200,
      {
        state: "open",
        first_name: d.first_name,
        grade: d.grade,
        academic_year: d.academic_year,
        campus: d.campus,
        respond_by: d.respond_by,
      },
      origin,
    );
  }
  if ((d.status !== "recorded" && d.status !== "answered") || !answered(d.response)) return bad();
  deps.log(d.status === "recorded" ? "offer_recorded" : "offer_already_answered");
  return respond(200, { status: d.status, response: d.response }, origin);
}

type DraftRequest = Extract<
  ParsedRequest,
  { action: "draft_create" | "draft_save" | "draft_get" | "draft_delete" }
>;

async function handleDraft(
  req: Request,
  parsed: DraftRequest,
  deps: Deps,
  config: Config,
  origin: string,
): Promise<Response> {
  let ipKey: string;
  try {
    ipKey = await hmacHex(config.ipHashKey, clientIp(req.headers));
  } catch {
    deps.log("ip_hash_failed");
    return respond(503, { error: MESSAGES.draftRefused }, origin);
  }
  const ipOk = await underLimit(deps, {
    p_bucket: parsed.action === "draft_create" ? "draft_ip" : "draft_use_ip",
    p_key_hash: ipKey,
  });
  if (ipOk === "error") {
    deps.log("rate_limit_error");
    return respond(503, { error: MESSAGES.draftRefused }, origin);
  }
  if (!ipOk) return limited(deps, origin, "draft_ip_limited");

  if (parsed.action === "draft_create") {
    let outcome: TurnstileOutcome;
    try {
      outcome = await deps.verifyTurnstile(parsed.token, config.turnstileSecret);
    } catch {
      deps.log("turnstile_unavailable");
      return respond(503, { error: MESSAGES.verify }, origin);
    }
    if (!turnstilePassed(outcome, config, "draft")) {
      deps.log("turnstile_refused");
      return respond(400, { error: MESSAGES.verify }, origin);
    }
    const globalOk = await underLimit(deps, { p_bucket: "draft_global" });
    if (globalOk === "error") {
      deps.log("rate_limit_error");
      return respond(503, { error: MESSAGES.draftRefused }, origin);
    }
    if (!globalOk) return limited(deps, origin, "draft_global_limited");
  }

  let result: RpcResult;
  try {
    switch (parsed.action) {
      case "draft_create":
        result = await deps.rpc("create_application_draft", {
          p_email: parsed.email,
          p_state: parsed.state,
          p_step: parsed.step,
          p_consent: parsed.consent,
        });
        break;
      case "draft_save":
        result = await deps.rpc("save_application_draft", {
          p_token: parsed.draftToken,
          p_state: parsed.state,
          p_step: parsed.step,
          p_expected_version: parsed.version,
          p_send_email: parsed.sendEmail,
        });
        break;
      case "draft_get":
        result = await deps.rpc("get_application_draft", { p_token: parsed.draftToken });
        break;
      case "draft_delete":
        result = await deps.rpc("delete_application_draft", { p_token: parsed.draftToken });
        break;
    }
  } catch {
    deps.log("draft_error");
    return respond(500, { error: MESSAGES.appError }, origin);
  }
  if (result.error) return draftRefusal(result.error, deps, origin);

  const d = result.data;
  const bad = () => {
    deps.log("draft_bad_result");
    return respond(500, { error: MESSAGES.appError }, origin);
  };
  switch (parsed.action) {
    case "draft_create":
      if (
        !isObject(d) ||
        typeof d.token !== "string" ||
        !DRAFT_TOKEN.test(d.token) ||
        !isIso(d.expires_at) ||
        typeof d.version !== "number" ||
        !isMasked(d.email_masked)
      )
        return bad();
      deps.log("draft_created");
      return respond(
        200,
        {
          draft_token: d.token,
          expires_at: d.expires_at,
          version: d.version,
          email_masked: d.email_masked,
        },
        origin,
      );
    case "draft_save":
      if (
        !isObject(d) ||
        typeof d.version !== "number" ||
        !isIso(d.expires_at) ||
        typeof d.email_queued !== "boolean" ||
        !isMasked(d.email_masked)
      )
        return bad();
      deps.log("draft_saved");
      return respond(
        200,
        {
          version: d.version,
          expires_at: d.expires_at,
          email_queued: d.email_queued,
          email_masked: d.email_masked,
        },
        origin,
      );
    case "draft_get":
      if (
        !isObject(d) ||
        !isObject(d.state) ||
        !isStep(d.step) ||
        typeof d.version !== "number" ||
        !isIso(d.expires_at) ||
        !isMasked(d.email_masked)
      )
        return bad();
      deps.log("draft_opened");
      return respond(
        200,
        {
          state: d.state,
          step: d.step,
          version: d.version,
          expires_at: d.expires_at,
          email_masked: d.email_masked,
        },
        origin,
      );
    case "draft_delete":
      if (d !== true) return bad();
      deps.log("draft_deleted");
      return respond(200, { deleted: true }, origin);
  }
}

/** The PDF gate (see the header): lead_ip, Turnstile, lead_global, then
 * capture_lead. Every limit gives the same 429. */
async function handlePdfGate(
  req: Request,
  parsed: Extract<ParsedRequest, { action: "pdf_gate" }>,
  deps: Deps,
  config: Config,
  origin: string,
): Promise<Response> {
  const office = (outcome: string, status = 429) => {
    deps.log(outcome);
    return respond(status, { error: MESSAGES.leadOffice }, origin);
  };

  let ipKey: string;
  try {
    ipKey = await hmacHex(config.ipHashKey, clientIp(req.headers));
  } catch {
    return office("lead_ip_hash_failed", 503);
  }
  const ipOk = await underLimit(deps, { p_bucket: "lead_ip", p_key_hash: ipKey });
  if (ipOk === "error") return office("lead_rate_limit_error", 503);
  if (!ipOk) return office("lead_ip_limited");

  let outcome: TurnstileOutcome;
  try {
    outcome = await deps.verifyTurnstile(parsed.token, config.turnstileSecret);
  } catch {
    deps.log("lead_turnstile_unavailable");
    return respond(503, { error: MESSAGES.verify }, origin);
  }
  if (!turnstilePassed(outcome, config, "pdf_gate")) {
    deps.log("lead_turnstile_refused");
    return respond(400, { error: MESSAGES.verify }, origin);
  }

  const globalOk = await underLimit(deps, { p_bucket: "lead_global" });
  if (globalOk === "error") return office("lead_rate_limit_error", 503);
  if (!globalOk) return office("lead_global_limited");

  let result: RpcResult;
  try {
    result = await deps.rpc("capture_lead", {
      p_source: LEAD_SOURCE,
      p_payload: parsed.payload,
    });
  } catch {
    deps.log("lead_error");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  if (result.error) {
    switch (result.error.code) {
      case "TCS22": {
        deps.log("lead_invalid");
        const details = result.error.details;
        const field = typeof details === "string" && LEAD_FIELDS.includes(details) ? details : null;
        return respond(
          400,
          {
            error: result.error.message ?? MESSAGES.badRequest,
            ...(field ? { field } : {}),
          },
          origin,
        );
      }
      case "TCS03":
        deps.log("lead_closed");
        return respond(409, { error: MESSAGES.leadClosed, code: "closed" }, origin);
      default: {
        const code = /^[0-9A-Z]{5}$/.test(result.error.code ?? "") ? result.error.code : "unknown";
        deps.log(`lead_failed_${code}`);
        return respond(500, { error: MESSAGES.error }, origin);
      }
    }
  }
  if (result.data !== true) {
    deps.log("lead_bad_result");
    return respond(500, { error: MESSAGES.error }, origin);
  }
  deps.log("lead_captured");
  return respond(200, { ok: true }, origin);
}
