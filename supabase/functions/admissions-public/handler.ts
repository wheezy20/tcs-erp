// admissions-public: the public request path (admissions slice 8,
// docs/admissions/PORT-PLAN.md; D-8a, D-8d and D-8e decided 2026-10-13).
//
// Everything a visitor who is not signed in can send to the ERP comes
// through here. Slice 8 wires one action, "inquiry". The order of checks:
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

export const MESSAGES = {
  office:
    "We couldn't take your inquiry online just now. Please call the school office and we'll help you directly.",
  closed:
    "Online inquiries are closed at the moment. Please call the school office to make an inquiry.",
  verify:
    "We couldn't complete the security check. Please try again, or call the school office if it keeps happening.",
  badRequest:
    "Something about the form didn't come through. Please reload the page and try again.",
  error:
    "Something went wrong on our side. Please try again later, or call the school office.",
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
  error: { code?: string; message?: string } | null;
};

export type Deps = {
  /** null when a secret is missing or malformed: every request is refused. */
  config: Config | null;
  /** Resolves with Cloudflare's answer; throws on timeout or any error. */
  verifyTurnstile: (token: string, secret: string) => Promise<TurnstileOutcome>;
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RpcResult>;
  log: (outcome: string) => void;
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

type InquiryRequest = { token: string; payload: Record<string, unknown> };

function parseRequest(text: string): InquiryRequest | "unknown_action" | null {
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof body !== "object" || body === null || Array.isArray(body))
    return null;
  const b = body as Record<string, unknown>;
  for (const key of Object.keys(b)) {
    if (key !== "action" && key !== "turnstile_token" && key !== "payload")
      return null;
  }
  if (b.action !== "inquiry") return "unknown_action";
  const token = b.turnstile_token;
  if (
    typeof token !== "string" ||
    token === "" ||
    token.length > MAX_TOKEN_LENGTH
  )
    return null;
  const payload = b.payload;
  if (typeof payload !== "object" || payload === null || Array.isArray(payload))
    return null;
  return { token, payload: payload as Record<string, unknown> };
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
  const hostnames = config.allowedOrigins.map((o) => new URL(o).hostname);
  if (
    outcome.success !== true ||
    typeof outcome.hostname !== "string" ||
    !hostnames.includes(outcome.hostname) ||
    outcome.action !== "inquiry"
  ) {
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
      case "TCS22":
        deps.log("invalid");
        return respond(
          400,
          { error: result.error.message ?? MESSAGES.badRequest },
          origin,
        );
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
