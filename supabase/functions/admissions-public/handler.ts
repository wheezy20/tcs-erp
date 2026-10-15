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
// This file has no Deno globals and no npm imports, so Node's test runner
// can drive it with a fake verifier and fake RPCs (handler.test.ts).
// index.ts wires the real ones. Secrets are passed in, never logged, and
// never put in a response; logs carry an outcome word and, for an
// unexpected database error, only its SQLSTATE.

export const MAX_BODY_BYTES = 32 * 1024;
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
} as const;

export type Config = {
  allowedOrigins: string[];
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

export type StorageDeps = {
  /** Signs one upload to exactly this path, overwrite off. Resolves with
   * the upload token; throws on any error. */
  signUpload: (path: string) => Promise<{ token: string }>;
  /** Deletes these paths in the admissions bucket; throws on any error. A
   * path with no file is not an error. */
  remove: (paths: string[]) => Promise<void>;
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
  if (
    hosted &&
    allowedOrigins.some((o) => {
      const url = new URL(o);
      return url.protocol !== "https:" || LOOPBACK_HOSTS.includes(url.hostname);
    })
  ) {
    return null;
  }
  return { allowedOrigins, turnstileSecret, ipHashKey };
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
    };

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
  if (!onlyKeys(b, ["action", "turnstile_token", "payload"])) return null;

  if (b.action === "inquiry") {
    const token = turnstileToken(b.turnstile_token);
    if (token === null || !isObject(b.payload)) return null;
    return { action: "inquiry", token, payload: b.payload };
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

  const origin = req.headers.get("origin");
  if (origin === null || !config.allowedOrigins.includes(origin)) {
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

  let text: string | null;
  try {
    text = await readCapped(req, MAX_BODY_BYTES);
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
  if (parsed.action === "upload_session")
    return handleUploadSession(req, parsed.token, deps, config, origin);
  if (parsed.action === "upload_url")
    return handleUploadUrl(parsed, deps, origin);

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

/** success, a hostname from the allow-list, and exactly this action. */
function turnstilePassed(
  outcome: TurnstileOutcome,
  config: Config,
  action: string,
): boolean {
  const hostnames = config.allowedOrigins.map((o) => new URL(o).hostname);
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
