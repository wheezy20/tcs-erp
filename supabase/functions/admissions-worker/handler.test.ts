// Unit tests for handler.ts with a fake provider and fake RPCs: no
// network, no database, no email. Run from the repo root with Node 22:
//
//   node --test supabase/functions/admissions-worker/handler.test.ts
//
// worker.integration.test.ts drives the same handler against the local
// database and a local fake provider.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  MAIL_BATCH,
  RESEND_LIVE_BASE,
  SEND_GAP_MS,
  USER_AGENT,
  classify,
  handle,
  loadMailConfig,
  mailRequested,
  makeResendSender,
  secretMatches,
  type Deps,
  type MailConfig,
  type OutgoingEmail,
  type RpcResult,
  type SendResult,
} from "./handler.ts";

const SECRET = "a".repeat(64);
const MAIL: MailConfig = {
  mode: "test",
  apiBase: "http://127.0.0.1:9",
  apiKey: "fake-key-for-tests",
  from: "TCS Admissions <no-reply@mail.example.test>",
  replyTo: "admissions@example.test",
  staffEmail: "staff.alerts@example.test",
  erpBaseUrl: "http://localhost:8080",
  dailyCeiling: 100,
  applyBaseUrl: "http://localhost:8080",
};
const LINK_TOKEN = "b".repeat(64);
const ISSUED: RpcResult = {
  data: {
    status: "issued",
    token: LINK_TOKEN,
    expires_at: "2026-11-20T06:34:29+00:00",
  },
  error: null,
};
const REF = (r: string) => ({
  references: [{ reference: r, grade: "Grade 3", academic_year: "2026/2027" }],
});
const ROW = (
  id: string,
  kind: string,
  to: string | null,
  params: unknown = REF(
    kind.startsWith("inquiry") ? "INQ-2026-0001" : "APP-2026-0001",
  ),
) => ({
  id,
  kind,
  recipient_email: to,
  params:
    kind === "application_staff"
      ? { ...(params as object), family_matched: false, outcome: null }
      : params,
  claim_token: `token-${id}`,
  attempts: 1,
});

type Harness = {
  deps: Deps;
  calls: Array<{ fn: string; args: Record<string, unknown> }>;
  sent: OutgoingEmail[];
  sleeps: number[];
  logs: string[];
};

function harness(
  opts: {
    secret?: unknown;
    rows?: unknown[];
    results?: SendResult[];
    mail?: MailConfig | null;
    issue?: RpcResult | (() => Promise<RpcResult>);
  } = {},
): Harness {
  const calls: Harness["calls"] = [];
  const sent: OutgoingEmail[] = [];
  const sleeps: number[] = [];
  const logs: string[] = [];
  const results = [...(opts.results ?? [])];
  const deps: Deps = {
    rpc: async (fn, args): Promise<RpcResult> => {
      calls.push({ fn, args });
      if (fn === "admissions_worker_secret")
        return { data: "secret" in opts ? opts.secret : SECRET, error: null };
      if (fn === "claim_admissions_emails")
        return { data: opts.rows ?? [], error: null };
      if (fn === "mark_admissions_email_result")
        return { data: true, error: null };
      if (fn === "claim_expired_application_uploads")
        return { data: [], error: null };
      if (fn === "issue_application_draft_link" || fn === "issue_offer_link") {
        const i = opts.issue ?? ISSUED;
        return typeof i === "function" ? i() : i;
      }
      return { data: null, error: { message: "unexpected" } };
    },
    mail: opts.mail === undefined ? MAIL : opts.mail,
    send: async (email) => {
      sent.push(email);
      return (
        results.shift() ?? {
          kind: "sent",
          status: 200,
          messageId: `msg-${sent.length}`,
        }
      );
    },
    sleep: async (ms) => {
      sleeps.push(ms);
    },
    log: (o) => logs.push(o),
    storage: {
      signUpload: async () => ({ token: "x" }),
      remove: async () => {},
      readHead: async () => new Uint8Array(),
    },
  };
  return { deps, calls, sent, sleeps, logs };
}

function req(
  body: unknown,
  secret: string | null = SECRET,
  method = "POST",
): Request {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (secret !== null) headers["x-admissions-worker-secret"] = secret;
  return new Request("http://fn.local/admissions-worker", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const marks = (h: Harness) =>
  h.calls
    .filter((c) => c.fn === "mark_admissions_email_result")
    .map((c) => c.args);

// ---------------------------------------------------------------- the secret

test("only POST is accepted", async () => {
  const h = harness();
  assert.equal((await handle(req(null, SECRET, "GET"), h.deps)).status, 405);
  assert.equal(h.calls.length, 0);
});

test("a missing secret header is refused before any database call, and nothing is sent", async () => {
  const h = harness({ rows: [ROW("1", "inquiry_parent", "p@example.test")] });
  const res = await handle(req({ job: "mail" }, null), h.deps);
  assert.equal(res.status, 401);
  assert.deepEqual(h.calls, []);
  assert.deepEqual(h.sent, []);
});

test("an empty header is refused even when the database secret is unset", async () => {
  const h = harness({
    secret: "",
    rows: [ROW("1", "inquiry_parent", "p@example.test")],
  });
  const res = await handle(req({ job: "mail" }, ""), h.deps);
  assert.equal(res.status, 401);
  assert.deepEqual(h.calls, []);
  assert.deepEqual(h.sent, []);
});

test("a wrong secret is refused after reading only the secret: nothing claimed, swept or sent", async () => {
  for (const job of ["mail", "sweep"]) {
    const h = harness({ rows: [ROW("1", "inquiry_parent", "p@example.test")] });
    const res = await handle(req({ job }, "b".repeat(64)), h.deps);
    assert.equal(res.status, 401);
    assert.deepEqual(
      h.calls.map((c) => c.fn),
      ["admissions_worker_secret"],
    );
    assert.deepEqual(h.sent, []);
  }
});

test("an unset or empty database secret refuses every request", async () => {
  for (const secret of [null, "", 42]) {
    const h = harness({
      secret,
      rows: [ROW("1", "inquiry_parent", "p@example.test")],
    });
    const res = await handle(req({ job: "mail" }, SECRET), h.deps);
    assert.equal(res.status, 503);
    assert.deepEqual(
      h.calls.map((c) => c.fn),
      ["admissions_worker_secret"],
    );
    assert.deepEqual(h.sent, []);
  }
});

test("secretMatches: equal values match; different, longer, shorter or empty values don't", async () => {
  assert.equal(await secretMatches(SECRET, SECRET), true);
  assert.equal(await secretMatches("b".repeat(64), SECRET), false);
  assert.equal(await secretMatches(SECRET + "a", SECRET), false);
  assert.equal(await secretMatches(SECRET.slice(1), SECRET), false);
  assert.equal(await secretMatches("", ""), false);
  assert.equal(await secretMatches("x", ""), false);
});

test("an unknown job is refused after the secret check", async () => {
  const h = harness();
  assert.equal((await handle(req({ job: "other" }), h.deps)).status, 400);
  assert.equal((await handle(req("not json"), h.deps)).status, 400);
});

// ---------------------------------------------------------------- mail

test("mail off: nothing is claimed and nothing is sent", async () => {
  const h = harness({
    mail: null,
    rows: [ROW("1", "inquiry_parent", "p@example.test")],
  });
  const res = await handle(req({ job: "mail" }), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(
    h.calls.map((c) => c.fn),
    ["admissions_worker_secret"],
  );
  assert.deepEqual(h.sent, []);
});

test("mail asked for but misconfigured: nothing claimed or sent, and the log says misconfigured", async () => {
  const h = harness({
    mail: null,
    rows: [ROW("1", "inquiry_parent", "p@example.test")],
  });
  h.deps.mailMisconfigured = true;
  await handle(req({ job: "mail" }), h.deps);
  assert.deepEqual(
    h.calls.map((c) => c.fn),
    ["admissions_worker_secret"],
  );
  assert.deepEqual(h.sent, []);
  assert.ok(h.logs.includes("mail_misconfigured"));
  assert.equal(
    mailRequested((n) => ({ MAIL_MODE: "live" })[n]),
    true,
  );
  assert.equal(
    mailRequested(() => undefined),
    false,
  );
});

test("mail: claims with the batch size and ceiling; sends each row once with its own idempotency key; staff alerts go to the staff address", async () => {
  const h = harness({
    rows: [
      ROW("r1", "inquiry_parent", "first@example.test"),
      ROW("r2", "inquiry_staff", null),
    ],
  });
  const res = await handle(req({ job: "mail" }), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(h.calls[1], {
    fn: "claim_admissions_emails",
    args: { p_limit: MAIL_BATCH, p_daily_ceiling: 100 },
  });
  assert.deepEqual(
    h.sent.map((e) => [e.idempotencyKey, e.to, e.from, e.replyTo, e.subject]),
    [
      [
        "outbox-r1",
        "first@example.test",
        MAIL.from,
        MAIL.replyTo,
        "We have received your enquiry",
      ],
      [
        "outbox-r2",
        "staff.alerts@example.test",
        MAIL.from,
        MAIL.replyTo,
        "New enquiry INQ-2026-0001",
      ],
    ],
  );
  assert.deepEqual(marks(h), [
    {
      p_id: "r1",
      p_claim_token: "token-r1",
      p_outcome: "sent",
      p_error_class: null,
      p_http_status: 200,
      p_provider_message_id: "msg-1",
    },
    {
      p_id: "r2",
      p_claim_token: "token-r2",
      p_outcome: "sent",
      p_error_class: null,
      p_http_status: 200,
      p_provider_message_id: "msg-2",
    },
  ]);
  assert.deepEqual(h.sleeps, [SEND_GAP_MS]);
});

test("the idempotency key is the row id alone, the same on every attempt", async () => {
  const keys: string[] = [];
  for (let attempt = 0; attempt < 2; attempt++) {
    const h = harness({
      rows: [ROW("same-row", "inquiry_parent", "p@example.test")],
      results: [{ kind: "http", status: 503 }],
    });
    await handle(req({ job: "mail" }), h.deps);
    keys.push(h.sent[0].idempotencyKey);
  }
  assert.deepEqual(keys, ["outbox-same-row", "outbox-same-row"]);
});

test("classify: each provider answer is recorded as decided", () => {
  const c = (r: SendResult) => {
    const o = classify(r);
    return `${o.outcome}/${o.errorClass}/${o.status}/${o.stop}`;
  };
  assert.equal(
    c({ kind: "sent", status: 200, messageId: "m" }),
    "sent/null/200/false",
  );
  assert.equal(
    c({ kind: "http", status: 400 }),
    "failed/invalid_recipient/400/false",
  );
  assert.equal(
    c({ kind: "http", status: 422 }),
    "failed/invalid_recipient/422/false",
  );
  assert.equal(c({ kind: "http", status: 401 }), "retry/config/401/true");
  assert.equal(c({ kind: "http", status: 403 }), "retry/config/403/true");
  assert.equal(c({ kind: "http", status: 409 }), "retry/conflict/409/false");
  assert.equal(c({ kind: "http", status: 429 }), "retry/rate_limited/429/true");
  assert.equal(
    c({ kind: "http", status: 500 }),
    "retry/provider_error/500/false",
  );
  assert.equal(
    c({ kind: "http", status: 503 }),
    "retry/provider_error/503/false",
  );
  assert.equal(c({ kind: "http", status: 404 }), "failed/other/404/false");
  assert.equal(c({ kind: "network" }), "retry/network/null/false");
  assert.equal(c({ kind: "timeout" }), "retry/timeout/null/false");
});

test("a 429 or a 401 stops the batch: the rest are put back as retries without being sent", async () => {
  for (const [status, cls] of [
    [429, "rate_limited"],
    [401, "config"],
  ] as const) {
    const h = harness({
      rows: [
        ROW("a", "inquiry_parent", "a@example.test"),
        ROW("b", "inquiry_parent", "b@example.test"),
        ROW("c", "inquiry_staff", null),
      ],
      results: [{ kind: "http", status }],
    });
    await handle(req({ job: "mail" }), h.deps);
    assert.equal(h.sent.length, 1);
    assert.deepEqual(
      marks(h).map((m) => `${m.p_id}:${m.p_outcome}:${m.p_error_class}`),
      [`a:retry:${cls}`, `b:retry:${cls}`, `c:retry:${cls}`],
    );
    assert.deepEqual(
      marks(h).map((m) => m.p_http_status),
      [status, null, null],
    );
  }
});

test("a 422 fails only that row and the batch goes on", async () => {
  const h = harness({
    rows: [
      ROW("a", "inquiry_parent", "a@example.test"),
      ROW("b", "inquiry_parent", "b@example.test"),
    ],
    results: [{ kind: "http", status: 422 }],
  });
  await handle(req({ job: "mail" }), h.deps);
  assert.equal(h.sent.length, 2);
  assert.deepEqual(
    marks(h).map((m) => `${m.p_id}:${m.p_outcome}`),
    ["a:failed", "b:sent"],
  );
});

test("a row whose params can't be rendered is failed without sending", async () => {
  const h = harness({
    rows: [
      ROW("a", "inquiry_parent", "a@example.test", {
        references: [
          {
            reference: "INQ-2026-0001",
            grade: "Grade 3",
            academic_year: "2026/2027",
          },
        ],
        child_name: "X",
      }),
    ],
  });
  await handle(req({ job: "mail" }), h.deps);
  assert.deepEqual(h.sent, []);
  assert.deepEqual(
    marks(h).map((m) => `${m.p_outcome}:${m.p_error_class}`),
    ["failed:other"],
  );
});

test("a malformed claim answer sends nothing", async () => {
  const h = harness({ rows: "not a list" as unknown as unknown[] });
  await handle(req({ job: "mail" }), h.deps);
  assert.deepEqual(h.sent, []);
  assert.ok(h.logs.includes("mail_claim_failed"));
});

test("a row this worker can't read is failed on its own and the rest of the batch still goes", async () => {
  const h = harness({
    rows: [
      ROW("1", "inquiry_parent", "a@example.test"),
      {
        ...ROW("2", "inquiry_parent", "b@example.test"),
        kind: "a_future_kind",
      },
      { id: 3 },
      ROW("4", "application_parent", "d@example.test"),
    ],
  });
  await handle(req({ job: "mail" }), h.deps);
  assert.deepEqual(
    h.sent.map((e) => e.to),
    ["a@example.test", "d@example.test"],
  );
  assert.deepEqual(
    marks(h).map((m) => `${m.p_id}:${m.p_outcome}:${m.p_error_class}`),
    ["2:failed:other", "1:sent:null", "4:sent:null"],
  );
  assert.ok(h.logs.includes("mail_unreadable_row"));
});

// ---------------------------------------------------------------- resume emails (slice 10)

const DRAFT_ROW = (id = "d1", attempts = 1) => ({
  ...ROW(id, "draft_resume", "parent@example.test", {}),
  attempts,
});

test("a resume email: the link is minted for this claim and sent once, keyed by row and attempt", async () => {
  const h = harness({
    rows: [DRAFT_ROW("d1", 3), ROW("5", "inquiry_parent", "e@example.test")],
  });
  await handle(req({ job: "mail" }), h.deps);
  const issue = h.calls.filter((c) => c.fn === "issue_application_draft_link");
  assert.deepEqual(
    issue.map((c) => c.args),
    [{ p_outbox_id: "d1", p_claim_token: "token-d1" }],
  );
  assert.equal(h.sent.length, 2);
  const [draft, other] = h.sent;
  assert.equal(draft.to, "parent@example.test");
  assert.equal(draft.kind, "draft_resume");
  assert.equal(draft.idempotencyKey, "outbox-d1-3");
  assert.equal(other.idempotencyKey, "outbox-5");
  assert.ok(
    draft.text.includes(`http://localhost:8080/apply#resume=${LINK_TOKEN}`),
  );
  assert.deepEqual(
    marks(h).map((m) => `${m.p_id}:${m.p_outcome}`),
    ["d1:sent", "5:sent"],
  );
});

test("the resume token is never logged and never passed to any other call", async () => {
  for (const results of [
    [],
    [{ kind: "http", status: 503 } as SendResult],
    [{ kind: "network" } as SendResult],
  ]) {
    const h = harness({ rows: [DRAFT_ROW()], results });
    await handle(req({ job: "mail" }), h.deps);
    assert.equal(h.sent.length, 1);
    for (const l of h.logs) assert.ok(!l.includes(LINK_TOKEN), `logged: ${l}`);
    for (const c of h.calls)
      assert.ok(
        !JSON.stringify(c.args).includes(LINK_TOKEN),
        `passed to ${c.fn}`,
      );
  }
});

test("a resume email no longer needed is left as the database marked it; a refused one is failed; a lost claim records nothing", async () => {
  const expired = harness({
    rows: [DRAFT_ROW()],
    issue: { data: { status: "expired" }, error: null },
  });
  await handle(req({ job: "mail" }), expired.deps);
  assert.deepEqual(expired.sent, []);
  assert.deepEqual(marks(expired), []);

  for (const data of [
    { status: "failed" },
    { status: "issued", token: "short", expires_at: "2026-11-20" },
    { status: "issued", token: LINK_TOKEN, expires_at: "soon" },
    ["odd"],
  ]) {
    const h = harness({ rows: [DRAFT_ROW()], issue: { data, error: null } });
    await handle(req({ job: "mail" }), h.deps);
    assert.deepEqual(h.sent, [], JSON.stringify(data));
    assert.deepEqual(
      marks(h).map((m) => `${m.p_outcome}:${m.p_error_class}`),
      ["failed:other"],
    );
  }

  const lost = harness({
    rows: [DRAFT_ROW()],
    issue: { data: null, error: null },
  });
  await handle(req({ job: "mail" }), lost.deps);
  assert.deepEqual(lost.sent, []);
  assert.deepEqual(marks(lost), []);
});

test("a link request that errors (a second request for one claim, or the database) counts as a failed attempt", async () => {
  for (const issue of [
    {
      data: null,
      error: {
        code: "P0001",
        message: "A link was already issued for this claim",
      },
    },
    async (): Promise<RpcResult> => {
      throw new Error("network");
    },
  ]) {
    const h = harness({
      rows: [DRAFT_ROW(), ROW("6", "inquiry_parent", "f@example.test")],
      issue,
    });
    await handle(req({ job: "mail" }), h.deps);
    assert.deepEqual(
      h.sent.map((e) => e.to),
      ["f@example.test"],
    );
    assert.deepEqual(
      marks(h).map((m) => `${m.p_id}:${m.p_outcome}:${m.p_error_class}`),
      ["d1:retry:other", "6:sent:null"],
    );
  }
});

test("without PUBLIC_APPLY_BASE_URL resume emails wait with class config and confirmation emails still go", async () => {
  const h = harness({
    rows: [DRAFT_ROW(), ROW("7", "application_parent", "g@example.test")],
    mail: { ...MAIL, applyBaseUrl: null },
  });
  await handle(req({ job: "mail" }), h.deps);
  assert.ok(!h.calls.some((c) => c.fn === "issue_application_draft_link"));
  assert.deepEqual(
    h.sent.map((e) => e.to),
    ["g@example.test"],
  );
  assert.deepEqual(
    marks(h).map((m) => `${m.p_id}:${m.p_outcome}:${m.p_error_class}`),
    ["d1:retry:config", "7:sent:null"],
  );
});

test("a batch stopped by a 429 mints no link for the resume emails it puts back", async () => {
  const h = harness({
    rows: [ROW("8", "inquiry_parent", "h@example.test"), DRAFT_ROW()],
    results: [{ kind: "http", status: 429 }],
  });
  await handle(req({ job: "mail" }), h.deps);
  assert.ok(!h.calls.some((c) => c.fn === "issue_application_draft_link"));
  assert.deepEqual(
    marks(h).map((m) => `${m.p_id}:${m.p_outcome}`),
    ["8:retry", "d1:retry"],
  );
});

// ---------------------------------------------------------------- sweep

test("sweep runs the upload sweep's claim", async () => {
  const h = harness();
  const res = await handle(req({ job: "sweep" }), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(
    h.calls.map((c) => c.fn),
    ["admissions_worker_secret", "claim_expired_application_uploads"],
  );
});

// ---------------------------------------------------------------- config

const ENV: Record<string, string> = {
  PUBLIC_APPLY_BASE_URL: "https://apply.example.test",
  MAIL_MODE: "live",
  RESEND_API_KEY: "re_live_key_value",
  MAIL_FROM: "TCS Admissions <no-reply@mail.tcsch.edu.gh>",
  MAIL_REPLY_TO: "admissions@tcsch.edu.gh",
  ADMISSIONS_STAFF_EMAIL: "staff@example.test",
  ERP_BASE_URL: "https://erp.example.test",
  MAIL_DAILY_CEILING: "90",
  SUPABASE_URL: "https://project.supabase.co",
};
const cfg = (over: Record<string, string | undefined>) =>
  loadMailConfig((n) => (n in over ? over[n] : ENV[n]));

test("mail is off unless MAIL_MODE is exactly live or test", () => {
  for (const mode of [undefined, "", "off", "LIVE", "on", "true"]) {
    assert.equal(cfg({ MAIL_MODE: mode }), null, String(mode));
  }
  assert.ok(cfg({}));
});

test("live: every value is required; the provider address is always Resend's, whatever RESEND_API_BASE says", () => {
  const live = cfg({ RESEND_API_BASE: "http://127.0.0.1:9" })!;
  assert.equal(live.apiBase, RESEND_LIVE_BASE);
  assert.equal(live.dailyCeiling, 90);
  for (const key of [
    "RESEND_API_KEY",
    "MAIL_FROM",
    "MAIL_REPLY_TO",
    "ADMISSIONS_STAFF_EMAIL",
    "ERP_BASE_URL",
    "MAIL_DAILY_CEILING",
  ]) {
    assert.equal(cfg({ [key]: "" }), null, key);
  }
  assert.equal(cfg({ MAIL_DAILY_CEILING: "0" }), null);
  assert.equal(cfg({ MAIL_DAILY_CEILING: "ten" }), null);
  assert.equal(
    cfg({ MAIL_FROM: "TCS Admissions no-reply@mail.tcsch.edu.gh" }),
    null,
  );
  assert.equal(cfg({ ERP_BASE_URL: "http://erp.example.test" }), null);
  assert.equal(cfg({ ERP_BASE_URL: "https://localhost:8080" }), null);
});

test("test mode: local stack only, a local provider, never a real-looking key", () => {
  const local = {
    MAIL_MODE: "test",
    RESEND_API_KEY: "fake-key",
    RESEND_API_BASE: "http://127.0.0.1:9999",
    SUPABASE_URL: "http://127.0.0.1:54321",
    ERP_BASE_URL: "http://localhost:8080",
  };
  assert.equal(cfg(local)!.apiBase, "http://127.0.0.1:9999");
  assert.equal(cfg({ ...local, RESEND_API_KEY: "re_123" }), null);
  assert.equal(
    cfg({ ...local, RESEND_API_BASE: "https://api.resend.com" }),
    null,
  );
  assert.equal(cfg({ ...local, RESEND_API_BASE: undefined }), null);
  assert.equal(
    cfg({ ...local, SUPABASE_URL: "https://project.supabase.co" }),
    null,
  );
});

// ---------------------------------------------------------------- provider

test("the Resend request: one recipient, Reply-To, idempotency key, user agent, plain text, no html", async () => {
  let seen: { url: string; init: RequestInit } | null = null;
  const send = makeResendSender((async (url: string, init: RequestInit) => {
    seen = { url, init };
    return new Response(JSON.stringify({ id: "provider-id" }), { status: 200 });
  }) as unknown as typeof fetch);
  const email: OutgoingEmail = {
    idempotencyKey: "outbox-1",
    from: MAIL.from,
    to: "p@example.test",
    replyTo: MAIL.replyTo,
    subject: "S",
    text: "T",
    kind: "inquiry_parent",
  };
  assert.deepEqual(await send(email, MAIL), {
    kind: "sent",
    status: 200,
    messageId: "provider-id",
  });
  const s = seen!;
  assert.equal(s.url, "http://127.0.0.1:9/emails");
  const h = s.init.headers as Record<string, string>;
  assert.equal(h["Idempotency-Key"], "outbox-1");
  assert.equal(h["User-Agent"], USER_AGENT);
  assert.equal(h.Authorization, "Bearer fake-key-for-tests");
  assert.deepEqual(JSON.parse(String(s.init.body)), {
    from: MAIL.from,
    to: ["p@example.test"],
    reply_to: MAIL.replyTo,
    subject: "S",
    text: "T",
    tags: [{ name: "kind", value: "inquiry_parent" }],
  });
});

test("the Resend sender never throws: errors become network or timeout, HTTP errors keep only the status", async () => {
  const email = {
    idempotencyKey: "k",
    from: "a@b.cd",
    to: "c@d.ef",
    replyTo: "a@b.cd",
    subject: "s",
    text: "t",
    kind: "inquiry_parent",
  } as OutgoingEmail;
  const throwing = (err: Error) =>
    makeResendSender((async () => {
      throw err;
    }) as unknown as typeof fetch);
  assert.deepEqual(await throwing(new TypeError("fetch failed"))(email, MAIL), {
    kind: "network",
  });
  const timeout = new Error("t");
  timeout.name = "TimeoutError";
  assert.deepEqual(await throwing(timeout)(email, MAIL), { kind: "timeout" });
  const http = makeResendSender(
    (async () =>
      new Response('{"message":"p@example.test is invalid"}', {
        status: 422,
      })) as unknown as typeof fetch,
  );
  assert.deepEqual(await http(email, MAIL), { kind: "http", status: 422 });
});

test("PUBLIC_APPLY_BASE_URL is optional: missing or malformed leaves mail on with no resume link base", () => {
  assert.equal(
    loadMailConfig((n) => ENV[n])?.applyBaseUrl,
    "https://apply.example.test",
  );
  for (const v of [
    undefined,
    "",
    "http://apply.example.test",
    "https://apply.example.test/path",
    "https://localhost",
    "https://apply.example.test?x=1",
  ]) {
    const c = loadMailConfig((n) =>
      n === "PUBLIC_APPLY_BASE_URL" ? v : ENV[n],
    );
    assert.ok(c, String(v));
    assert.equal(c.applyBaseUrl, null, String(v));
  }
  assert.equal(
    loadMailConfig((n) =>
      n === "PUBLIC_APPLY_BASE_URL" ? "https://apply.example.test/" : ENV[n],
    )?.applyBaseUrl,
    "https://apply.example.test",
  );
});

// ---------------------------------------------------------------- offer emails (slice 11)

const APP_ID = "11000000-0000-4000-8000-000000000b01";
const OFFER_ROW = (id = "o1", attempts = 1) => ({
  ...ROW(id, "offer", "guardian@example.test"),
  attempts,
});

test("an offer email: the link is minted for this claim, printed as /offer#token=, keyed by row and attempt", async () => {
  const h = harness({ rows: [OFFER_ROW("o1", 2)] });
  await handle(req({ job: "mail" }), h.deps);
  assert.deepEqual(
    h.calls.filter((c) => c.fn === "issue_offer_link").map((c) => c.args),
    [{ p_outbox_id: "o1", p_claim_token: "token-o1" }],
  );
  assert.equal(h.sent.length, 1);
  const [e] = h.sent;
  assert.equal(e.to, "guardian@example.test");
  assert.equal(e.kind, "offer");
  assert.equal(e.idempotencyKey, "outbox-o1-2");
  assert.equal(e.subject, "An offer of a place at Treasures Christian School");
  assert.ok(e.text.includes(`http://localhost:8080/offer#token=${LINK_TOKEN}`));
  assert.ok(e.text.includes("open until 20 November 2026"));
  assert.deepEqual(marks(h).map((m) => `${m.p_id}:${m.p_outcome}`), ["o1:sent"]);
  for (const l of h.logs) assert.ok(!l.includes(LINK_TOKEN), `logged: ${l}`);
  for (const c of h.calls)
    assert.ok(!JSON.stringify(c.args).includes(LINK_TOKEN), `passed to ${c.fn}`);
});

test("an offer email no longer needed is left as marked; a refused link is failed; a lost claim records nothing; an error retries", async () => {
  const expired = harness({ rows: [OFFER_ROW()], issue: { data: { status: "expired" }, error: null } });
  await handle(req({ job: "mail" }), expired.deps);
  assert.deepEqual(expired.sent, []);
  assert.deepEqual(marks(expired), []);
  for (const data of [{ status: "failed" }, { status: "issued", token: "short", expires_at: "2026-11-20" }, ["odd"]]) {
    const h = harness({ rows: [OFFER_ROW()], issue: { data, error: null } });
    await handle(req({ job: "mail" }), h.deps);
    assert.deepEqual(h.sent, []);
    assert.deepEqual(marks(h).map((m) => `${m.p_outcome}:${m.p_error_class}`), ["failed:other"]);
  }
  const lost = harness({ rows: [OFFER_ROW()], issue: { data: null, error: null } });
  await handle(req({ job: "mail" }), lost.deps);
  assert.deepEqual(marks(lost), []);
  const err = harness({ rows: [OFFER_ROW()], issue: { data: null, error: { code: "P0001", message: "x" } } });
  await handle(req({ job: "mail" }), err.deps);
  assert.deepEqual(err.sent, []);
  assert.deepEqual(marks(err).map((m) => `${m.p_outcome}:${m.p_error_class}`), ["retry:other"]);
});

test("without PUBLIC_APPLY_BASE_URL an offer email is retried with class config and nothing is minted", async () => {
  const h = harness({ rows: [OFFER_ROW()], mail: { ...MAIL, applyBaseUrl: null } });
  await handle(req({ job: "mail" }), h.deps);
  assert.deepEqual(h.sent, []);
  assert.equal(h.calls.some((c) => c.fn === "issue_offer_link"), false);
  assert.deepEqual(marks(h).map((m) => `${m.p_outcome}:${m.p_error_class}`), ["retry:config"]);
});

test("the offer staff alert goes to the staff address with the reference, the response and the ERP link only", async () => {
  const h = harness({
    rows: [
      ROW("s1", "offer_staff", null, {
        ...REF("APP-2026-0001"),
        application_id: APP_ID,
        response: "accepted",
      }),
    ],
  });
  await handle(req({ job: "mail" }), h.deps);
  assert.equal(h.sent.length, 1);
  const [e] = h.sent;
  assert.equal(e.to, "staff.alerts@example.test");
  assert.equal(e.idempotencyKey, "outbox-s1");
  assert.equal(e.subject, "Offer APP-2026-0001 accepted through the offer link");
  assert.ok(e.text.endsWith(`http://localhost:8080/admissions/${APP_ID}`));
  assert.equal(h.calls.some((c) => c.fn === "issue_offer_link"), false);
});
