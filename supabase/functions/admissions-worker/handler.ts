// admissions-worker: sends the admissions outbox and sweeps abandoned
// uploads (admissions slice 12, docs/admissions/PORT-PLAN.md). It is not a
// public endpoint: only the pg_cron jobs call it, through pg_net, with the
// worker secret the database made in Vault.
//
// Order of work for every request:
//
//   1. POST only. The x-admissions-worker-secret header must be present
//      (else 401, before any database call).
//   2. The expected secret is read from the database
//      (admissions_worker_secret(), service role only). If it is missing or
//      empty, every request is refused (503). The two are compared as
//      SHA-256 digests in constant time; a mismatch is 401. Nothing is
//      claimed, swept or sent before this passes.
//   3. Body {"job": "mail" | "sweep"}, at most 1 KB.
//
// The mail job:
//
//   - MAIL_MODE "off" (or unset, or anything unknown) sends nothing and
//     claims nothing; rows wait as pending. "live" sends through
//     https://api.resend.com. "test" is for the local stack only: it needs
//     a local SUPABASE_URL, sends to RESEND_API_BASE on a local host, and
//     refuses a key that looks real (re_...), so no test can reach Resend.
//     "live" does not look at where the database is: a local `functions
//     serve` run with MAIL_MODE=live and a real key would send real mail
//     for local rows. Never set live outside the hosted project.
//   - Every value it needs is a function secret with no default: the key,
//     MAIL_FROM, MAIL_REPLY_TO, ADMISSIONS_STAFF_EMAIL, ERP_BASE_URL and
//     MAIL_DAILY_CEILING. One missing or malformed value stops the job and
//     logs mail_misconfigured (mail off logs mail_off); rows wait as
//     pending either way.
//   - claim_admissions_emails(MAIL_BATCH, ceiling), then for each row:
//     render the template, send one email with Idempotency-Key
//     "outbox-<row id>" (Resend keeps it 24 hours, longer than every retry
//     window), and record the result with mark_admissions_email_result.
//     Sends are paced at SEND_GAP_MS. The provider's error text is never
//     logged or stored, only a class and the HTTP status:
//       2xx              sent (with the provider's id when it gives one)
//       400, 422         failed at once (invalid_recipient)
//       401, 403         retry (config); the rest of the batch is put back
//       409              retry (conflict: the same key is still in flight)
//       429              retry (rate_limited); the rest of the batch is put back
//       5xx              retry (provider_error)
//       other 4xx        failed (other)
//       network error    retry (network); timeout: retry (timeout)
//
// The sweep job runs admissions-public's sweepExpiredUploads unchanged:
// files are deleted only through the Storage API (D-4d).
//
// No Deno globals and no npm imports, so Node's test runner can drive it
// with a fake provider and fake RPCs (handler.test.ts). index.ts wires the
// real ones.

import {
  sweepExpiredUploads,
  type StorageDeps,
} from "../admissions-public/handler.ts";
import { EMAIL_KINDS, renderEmail, type EmailKind } from "./templates.ts";

export const MAX_BODY_BYTES = 1024;
export const MAX_SECRET_LENGTH = 200;
// 10 sends of at most 10.5 s each stay inside the hosted function's time
// limit; a function stopped mid-batch is safe (the lease lapses and the
// retry reuses the idempotency key).
export const MAIL_BATCH = 10;
export const SEND_GAP_MS = 500;
export const SEND_TIMEOUT_MS = 10_000;
export const RESEND_LIVE_BASE = "https://api.resend.com";
export const USER_AGENT = "tcs-erp-admissions-worker/1.0";

const EMAIL = /^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$/;
const FROM =
  /^(?:[A-Za-z0-9 .'&()]{1,80} <[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+>|[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+)$/;
const LOCAL_HOSTS = [
  "localhost",
  "127.0.0.1",
  "[::1]",
  "host.docker.internal",
  "kong",
];

export type RpcResult = {
  data: unknown;
  error: { code?: string; message?: string; details?: string } | null;
};

export type MailConfig = {
  mode: "live" | "test";
  apiBase: string;
  apiKey: string;
  from: string;
  replyTo: string;
  staffEmail: string;
  erpBaseUrl: string;
  dailyCeiling: number;
};

/** What the provider said, already reduced to what the worker records. */
export type SendResult =
  | { kind: "sent"; status: number; messageId: string }
  | { kind: "http"; status: number }
  | { kind: "network" }
  | { kind: "timeout" };

export type OutgoingEmail = {
  idempotencyKey: string;
  from: string;
  to: string;
  replyTo: string;
  subject: string;
  text: string;
  kind: EmailKind;
};

export type Deps = {
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RpcResult>;
  /** The mail configuration, or null when mail is off or misconfigured. */
  mail: MailConfig | null;
  /** True when MAIL_MODE asks for mail but a value is missing or bad. */
  mailMisconfigured?: boolean;
  /** Sends one email; never throws. */
  send: (email: OutgoingEmail, config: MailConfig) => Promise<SendResult>;
  sleep: (ms: number) => Promise<void>;
  log: (outcome: string) => void;
  /** Needed by the sweep job only; without it the sweep does nothing. */
  storage?: StorageDeps;
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isLocalUrl(raw: string): boolean {
  try {
    const url = new URL(raw);
    return url.protocol === "http:" || url.protocol === "https:"
      ? LOCAL_HOSTS.includes(url.hostname)
      : false;
  } catch {
    return false;
  }
}

function isHttpsUrl(raw: string): boolean {
  try {
    return new URL(raw).protocol === "https:";
  } catch {
    return false;
  }
}

/** True when MAIL_MODE asks for mail (live or test), whether or not the
 * rest of the configuration is usable. */
export function mailRequested(
  get: (name: string) => string | undefined,
): boolean {
  const mode = (get("MAIL_MODE") ?? "").trim();
  return mode === "live" || mode === "test";
}

/** The mail configuration from the function's environment, or null (mail
 * off). Every value is required; nothing has a default, so a stale default
 * can never decide what production sends. */
export function loadMailConfig(
  get: (name: string) => string | undefined,
): MailConfig | null {
  const mode = (get("MAIL_MODE") ?? "").trim();
  if (mode !== "live" && mode !== "test") return null;
  const apiKey = (get("RESEND_API_KEY") ?? "").trim();
  const from = (get("MAIL_FROM") ?? "").trim();
  const replyTo = (get("MAIL_REPLY_TO") ?? "").trim();
  const staffEmail = (get("ADMISSIONS_STAFF_EMAIL") ?? "").trim();
  const erpBaseUrl = (get("ERP_BASE_URL") ?? "").trim().replace(/\/+$/, "");
  const ceilingRaw = (get("MAIL_DAILY_CEILING") ?? "").trim();
  const supabaseUrl = (get("SUPABASE_URL") ?? "").trim();
  if (
    apiKey === "" ||
    !FROM.test(from) ||
    !EMAIL.test(replyTo) ||
    !EMAIL.test(staffEmail) ||
    !/^[1-9][0-9]{0,5}$/.test(ceilingRaw)
  )
    return null;
  const dailyCeiling = Number(ceilingRaw);

  if (mode === "live") {
    if (!isHttpsUrl(erpBaseUrl) || isLocalUrl(erpBaseUrl)) return null;
    return {
      mode,
      apiBase: RESEND_LIVE_BASE,
      apiKey,
      from,
      replyTo,
      staffEmail,
      erpBaseUrl,
      dailyCeiling,
    };
  }
  // Test mode: local stack only, a local fake provider, never a real key.
  const apiBase = (get("RESEND_API_BASE") ?? "").trim().replace(/\/+$/, "");
  if (
    !isLocalUrl(supabaseUrl) ||
    !isLocalUrl(apiBase) ||
    apiKey.startsWith("re_")
  )
    return null;
  if (!isLocalUrl(erpBaseUrl)) return null;
  return {
    mode,
    apiBase,
    apiKey,
    from,
    replyTo,
    staffEmail,
    erpBaseUrl,
    dailyCeiling,
  };
}

async function sha256(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

/** Constant time over fixed-length digests: the time taken doesn't depend
 * on where the two values differ. An empty expected value never matches. */
export async function secretMatches(
  presented: string,
  expected: string,
): Promise<boolean> {
  if (expected === "" || presented === "") return false;
  const [a, b] = await Promise.all([sha256(presented), sha256(expected)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Calls Resend's send endpoint once. Never throws. */
export function makeResendSender(fetchImpl: typeof fetch) {
  return async (
    email: OutgoingEmail,
    config: MailConfig,
  ): Promise<SendResult> => {
    try {
      const res = await fetchImpl(`${config.apiBase}/emails`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${config.apiKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": email.idempotencyKey,
          "User-Agent": USER_AGENT,
        },
        body: JSON.stringify({
          from: email.from,
          to: [email.to],
          reply_to: email.replyTo,
          subject: email.subject,
          text: email.text,
          tags: [{ name: "kind", value: email.kind }],
        }),
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      });
      if (res.status >= 200 && res.status < 300) {
        const body: unknown = await res.json().catch(() => null);
        const id =
          typeof body === "object" &&
          body !== null &&
          typeof (body as { id?: unknown }).id === "string"
            ? (body as { id: string }).id
            : "";
        return {
          kind: "sent",
          status: res.status,
          messageId: id.slice(0, 200),
        };
      }
      await res.body?.cancel().catch(() => {});
      return { kind: "http", status: res.status };
    } catch (err) {
      const name = (err as { name?: string } | null)?.name;
      return name === "TimeoutError" || name === "AbortError"
        ? { kind: "timeout" }
        : { kind: "network" };
    }
  };
}

type Outcome = {
  outcome: "sent" | "retry" | "failed";
  errorClass: string | null;
  status: number | null;
  messageId: string | null;
  /** Stop sending the rest of this batch and put it back. */
  stop: boolean;
};

/** How one provider answer is recorded. */
export function classify(result: SendResult): Outcome {
  switch (result.kind) {
    case "sent":
      return {
        outcome: "sent",
        errorClass: null,
        status: result.status,
        messageId: result.messageId,
        stop: false,
      };
    case "network":
      return {
        outcome: "retry",
        errorClass: "network",
        status: null,
        messageId: null,
        stop: false,
      };
    case "timeout":
      return {
        outcome: "retry",
        errorClass: "timeout",
        status: null,
        messageId: null,
        stop: false,
      };
    case "http": {
      const s = result.status;
      const r = (
        outcome: Outcome["outcome"],
        errorClass: string,
        stop = false,
      ): Outcome => ({
        outcome,
        errorClass,
        status: s,
        messageId: null,
        stop,
      });
      if (s === 400 || s === 422) return r("failed", "invalid_recipient");
      if (s === 401 || s === 403) return r("retry", "config", true);
      if (s === 409) return r("retry", "conflict");
      if (s === 429) return r("retry", "rate_limited", true);
      if (s >= 500) return r("retry", "provider_error");
      return r("failed", "other");
    }
  }
}

type ClaimedRow = {
  id: string;
  kind: EmailKind;
  recipient_email: string | null;
  params: unknown;
  claim_token: string;
};

function claimedRows(data: unknown): ClaimedRow[] | null {
  if (!Array.isArray(data)) return null;
  const rows: ClaimedRow[] = [];
  for (const r of data) {
    if (
      typeof r !== "object" ||
      r === null ||
      typeof (r as ClaimedRow).id !== "string" ||
      typeof (r as ClaimedRow).claim_token !== "string" ||
      !EMAIL_KINDS.includes((r as ClaimedRow).kind)
    )
      return null;
    rows.push(r as ClaimedRow);
  }
  return rows;
}

async function mark(
  deps: Deps,
  row: ClaimedRow,
  o: Omit<Outcome, "stop">,
): Promise<void> {
  const res = await deps.rpc("mark_admissions_email_result", {
    p_id: row.id,
    p_claim_token: row.claim_token,
    p_outcome: o.outcome,
    p_error_class: o.errorClass,
    p_http_status: o.status,
    p_provider_message_id: o.messageId,
  });
  if (res.error || res.data !== true) deps.log("mail_mark_failed");
}

/** Claims and sends one batch. Returns how many were sent. */
export async function runMailJob(
  deps: Deps,
): Promise<{ sent: number; claimed: number }> {
  const config = deps.mail;
  if (!config) {
    deps.log(deps.mailMisconfigured ? "mail_misconfigured" : "mail_off");
    return { sent: 0, claimed: 0 };
  }
  const claim = await deps.rpc("claim_admissions_emails", {
    p_limit: MAIL_BATCH,
    p_daily_ceiling: config.dailyCeiling,
  });
  const rows = claim.error ? null : claimedRows(claim.data);
  if (!rows) {
    deps.log("mail_claim_failed");
    return { sent: 0, claimed: 0 };
  }

  let sent = 0;
  let stopped: Outcome | null = null;
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (stopped) {
      // Never sent: keep the reason, but no HTTP status of its own.
      await mark(deps, row, { ...stopped, status: null, messageId: null });
      continue;
    }
    const to = row.kind.endsWith("_staff")
      ? config.staffEmail
      : row.recipient_email;
    let rendered;
    try {
      if (!to || !EMAIL.test(to)) throw new Error("no recipient");
      rendered = renderEmail(row.kind, row.params, config.erpBaseUrl);
    } catch {
      deps.log("mail_render_failed");
      await mark(deps, row, {
        outcome: "failed",
        errorClass: "other",
        status: null,
        messageId: null,
      });
      continue;
    }
    if (i > 0) await deps.sleep(SEND_GAP_MS);
    const result = await deps.send(
      {
        idempotencyKey: `outbox-${row.id}`,
        from: config.from,
        to,
        replyTo: config.replyTo,
        subject: rendered.subject,
        text: rendered.text,
        kind: row.kind,
      },
      config,
    );
    const o = classify(result);
    await mark(deps, row, o);
    if (o.outcome === "sent") sent += 1;
    else deps.log(`mail_${o.errorClass}`);
    if (o.stop) stopped = o;
  }
  deps.log(`mail_done_${sent}_of_${rows.length}`);
  return { sent, claimed: rows.length };
}

async function readCapped(req: Request, max: number): Promise<string | null> {
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
  let off = 0;
  for (const c of chunks) {
    all.set(c, off);
    off += c.byteLength;
  }
  return new TextDecoder().decode(all);
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method" });

  const presented = req.headers.get("x-admissions-worker-secret") ?? "";
  if (presented === "" || presented.length > MAX_SECRET_LENGTH) {
    deps.log("refused_no_secret");
    return json(401, { error: "unauthorised" });
  }
  const expected = await deps.rpc("admissions_worker_secret", {});
  if (
    expected.error ||
    typeof expected.data !== "string" ||
    expected.data === ""
  ) {
    deps.log("refused_secret_unset");
    return json(503, { error: "unavailable" });
  }
  if (!(await secretMatches(presented, expected.data))) {
    deps.log("refused_wrong_secret");
    return json(401, { error: "unauthorised" });
  }

  const raw = await readCapped(req, MAX_BODY_BYTES);
  let job: unknown = null;
  try {
    job = raw ? (JSON.parse(raw) as { job?: unknown }).job : null;
  } catch {
    job = null;
  }

  if (job === "mail") {
    const r = await runMailJob(deps);
    return json(200, { job, ...r });
  }
  if (job === "sweep") {
    if (deps.storage) {
      await sweepExpiredUploads({
        config: null,
        verifyTurnstile: async () => {
          throw new Error("not used by the sweep");
        },
        rpc: deps.rpc,
        log: deps.log,
        storage: deps.storage,
      });
    } else {
      deps.log("sweep_no_storage");
    }
    return json(200, { job });
  }
  return json(400, { error: "job" });
}
