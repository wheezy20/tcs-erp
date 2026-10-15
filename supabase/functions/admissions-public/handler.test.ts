// Unit tests for handler.ts with a fake Turnstile verifier and fake RPCs:
// no network, no database. Run from the repo root with Node 22:
//
//   node --test supabase/functions/admissions-public/handler.test.ts
//
// integration.test.ts drives the same handler against the local database.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  MAX_APPLICATION_BODY_BYTES,
  MAX_BODY_BYTES,
  MESSAGES,
  safeApplicationFieldPath,
  sniffKind,
  clientIp,
  handle,
  hmacHex,
  loadConfig,
  makeTurnstileVerifier,
  parseAllowedOrigins,
  sweepExpiredUploads,
  SWEEP_BATCH,
  type Config,
  type Deps,
  type RpcResult,
  type TurnstileOutcome,
} from "./handler.ts";

const ORIGIN = "https://app.example.test";
const SECRET = "turnstile-secret-for-tests-only";
const IP_KEY = "ip-hash-key-for-tests-only-0123456789";
const RAW_IP = "203.0.113.7";
const TOKEN = "fake-turnstile-token-abc";

const CONFIG: Config = {
  allowedOrigins: [ORIGIN, "http://localhost:8080"],
  turnstileSecret: SECRET,
  ipHashKey: IP_KEY,
};

const GOOD_TURNSTILE: TurnstileOutcome = {
  success: true,
  hostname: "app.example.test",
  action: "inquiry",
};

type Call = { fn: string; args: Record<string, unknown> };

function harness(opts: {
  config?: Config | null;
  ipOk?: boolean | "error";
  globalOk?: boolean | "error";
  turnstile?: TurnstileOutcome | "throw";
  submit?: RpcResult | "throw";
}) {
  const calls: Call[] = [];
  const order: string[] = [];
  const logs: string[] = [];
  const tokensSeen: string[] = [];
  const deps: Deps = {
    config: opts.config === undefined ? CONFIG : opts.config,
    verifyTurnstile: async (token, secret) => {
      order.push("turnstile");
      tokensSeen.push(token);
      assert.equal(secret, SECRET);
      if (opts.turnstile === "throw") throw new Error("timeout");
      return opts.turnstile ?? GOOD_TURNSTILE;
    },
    rpc: async (fn, args) => {
      calls.push({ fn, args });
      if (fn === "check_public_rate_limit") {
        const bucket = args.p_bucket;
        order.push(String(bucket));
        const v =
          bucket === "submit_ip"
            ? (opts.ipOk ?? true)
            : (opts.globalOk ?? true);
        if (v === "error")
          return { data: null, error: { code: "XX000", message: "boom" } };
        return { data: v, error: null };
      }
      order.push(fn);
      if (opts.submit === "throw") throw new Error("network");
      return opts.submit ?? { data: ["INQ-2026-0001"], error: null };
    },
    log: (o) => logs.push(o),
  };
  return { deps, calls, order, logs, tokensSeen };
}

function post(
  body: unknown,
  init: { origin?: string | null; headers?: Record<string, string> } = {},
) {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-forwarded-for": `${RAW_IP}, 10.0.0.1`,
    ...(init.headers ?? {}),
  };
  if (init.origin !== null) headers.origin = init.origin ?? ORIGIN;
  return new Request("http://fn.local/admissions-public", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const VALID = {
  action: "inquiry",
  turnstile_token: TOKEN,
  payload: { referral_source: "website" },
};

async function json(res: Response): Promise<Record<string, unknown>> {
  return (await res.json()) as Record<string, unknown>;
}

// ---------------------------------------------------------------- config

test("parseAllowedOrigins accepts exact origins and refuses anything looser", () => {
  assert.deepEqual(
    parseAllowedOrigins(" https://a.test , http://localhost:8080 "),
    ["https://a.test", "http://localhost:8080"],
  );
  assert.equal(parseAllowedOrigins(undefined), null);
  assert.equal(parseAllowedOrigins(""), null);
  assert.equal(parseAllowedOrigins("*"), null);
  assert.equal(parseAllowedOrigins("https://a.test/"), null);
  assert.equal(parseAllowedOrigins("https://a.test/path"), null);
  assert.equal(parseAllowedOrigins("https://a.test,https://*.b.test"), null);
  assert.equal(parseAllowedOrigins("ftp://a.test"), null);
});

test("loadConfig fails closed on a missing or weak secret", () => {
  const env: Record<string, string> = {
    ADMISSIONS_ALLOWED_ORIGINS: ORIGIN,
    TURNSTILE_SECRET_KEY: SECRET,
    IP_HASH_KEY: IP_KEY,
    SUPABASE_URL: "https://abcdefghijabcdefghij.supabase.co",
  };
  const get = (over: Record<string, string | undefined>) => (n: string) =>
    n in over ? over[n] : env[n];
  assert.deepEqual(loadConfig(get({}))?.allowedOrigins, [ORIGIN]);
  assert.equal(loadConfig(get({ TURNSTILE_SECRET_KEY: undefined })), null);
  assert.equal(loadConfig(get({ TURNSTILE_SECRET_KEY: "  " })), null);
  assert.equal(loadConfig(get({ IP_HASH_KEY: undefined })), null);
  assert.equal(loadConfig(get({ IP_HASH_KEY: "short" })), null);
  assert.equal(
    loadConfig(get({ ADMISSIONS_ALLOWED_ORIGINS: undefined })),
    null,
  );
});

test("loadConfig refuses localhost or http origins on a hosted project only", () => {
  const base = { TURNSTILE_SECRET_KEY: SECRET, IP_HASH_KEY: IP_KEY };
  const hosted = "https://abcdefghijabcdefghij.supabase.co";
  const cfg = (origins: string, url: string) =>
    loadConfig(
      (n) =>
        ({ ...base, ADMISSIONS_ALLOWED_ORIGINS: origins, SUPABASE_URL: url })[
          n
        ],
    );
  assert.equal(cfg(`${ORIGIN},http://localhost:8080`, hosted), null);
  assert.equal(cfg("https://localhost:8443", hosted), null);
  assert.equal(cfg("http://app.example.test", hosted), null);
  assert.notEqual(cfg(ORIGIN, hosted), null);
  assert.notEqual(cfg("http://localhost:8080", "http://kong:8000"), null);
});

// ---------------------------------------------------------------- helpers

test("clientIp takes the leftmost forwarded entry, else unknown", () => {
  assert.equal(
    clientIp(new Headers({ "x-forwarded-for": " 1.2.3.4 , 5.6.7.8" })),
    "1.2.3.4",
  );
  assert.equal(clientIp(new Headers()), "unknown");
  assert.equal(clientIp(new Headers({ "x-forwarded-for": "" })), "unknown");
  assert.equal(
    clientIp(new Headers({ "x-forwarded-for": "x".repeat(101) })),
    "unknown",
  );
});

test("hmacHex matches the RFC HMAC-SHA256 example", async () => {
  assert.equal(
    await hmacHex("key", "The quick brown fox jumps over the lazy dog"),
    "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
  );
});

// ---------------------------------------------------------------- gatekeeping

test("missing configuration refuses everything before any call", async () => {
  const h = harness({ config: null });
  const res = await handle(post(VALID), h.deps);
  assert.equal(res.status, 503);
  assert.equal((await json(res)).error, MESSAGES.office);
  assert.equal(res.headers.get("access-control-allow-origin"), null);
  assert.deepEqual(h.order, []);
});

test("an origin not on the list, or none, gets 403 with no CORS headers and no calls", async () => {
  for (const origin of [
    "https://evil.test",
    "https://app.example.test.evil.test",
    null,
  ]) {
    const h = harness({});
    const res = await handle(post(VALID, { origin }), h.deps);
    assert.equal(res.status, 403);
    assert.equal(res.headers.get("access-control-allow-origin"), null);
    assert.deepEqual(h.order, []);
  }
});

test("preflight from an allowed origin echoes exactly that origin", async () => {
  const h = harness({});
  const res = await handle(
    new Request("http://fn.local/x", {
      method: "OPTIONS",
      headers: { origin: ORIGIN },
    }),
    h.deps,
  );
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), ORIGIN);
  assert.equal(res.headers.get("vary"), "Origin");
  assert.deepEqual(h.order, []);
});

test("only POST with a JSON content type", async () => {
  const h = harness({});
  const get = await handle(
    new Request("http://fn.local/x", {
      method: "GET",
      headers: { origin: ORIGIN },
    }),
    h.deps,
  );
  assert.equal(get.status, 405);
  const plain = await handle(
    post(VALID, { headers: { "content-type": "text/plain" } }),
    h.deps,
  );
  assert.equal(plain.status, 415);
  assert.deepEqual(h.order, []);
});

test("a body over 32 KB is refused, by header or by counting", async () => {
  const big = JSON.stringify({
    ...VALID,
    payload: { comments: "x".repeat(MAX_BODY_BYTES) },
  });
  const h = harness({});
  assert.equal((await handle(post(big), h.deps)).status, 413);
  // No content-length: a streamed body is counted.
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(new TextEncoder().encode(big));
      c.close();
    },
  });
  const streamed = new Request("http://fn.local/x", {
    method: "POST",
    headers: { origin: ORIGIN, "content-type": "application/json" },
    body: stream,
    // @ts-expect-error duplex is required by Node for a stream body
    duplex: "half",
  });
  assert.equal((await handle(streamed, h.deps)).status, 413);
  // A lying header (non-numeric) is refused too.
  assert.equal(
    (
      await handle(
        post(VALID, { headers: { "content-length": "abc" } }),
        h.deps,
      )
    ).status,
    413,
  );
  assert.deepEqual(h.order, []);
});

test("a body stream that errors mid-read is a clean 400", async () => {
  const h = harness({});
  const broken = new ReadableStream<Uint8Array>({
    pull(c) {
      c.error(new Error("connection reset"));
    },
  });
  const req = new Request("http://fn.local/x", {
    method: "POST",
    headers: { origin: ORIGIN, "content-type": "application/json" },
    body: broken,
    // @ts-expect-error duplex is required by Node for a stream body
    duplex: "half",
  });
  assert.equal((await handle(req, h.deps)).status, 400);
  assert.deepEqual(h.order, []);
});

test("malformed requests get 400 before any limit or Turnstile call", async () => {
  const bad = [
    "not json",
    "[]",
    JSON.stringify({ ...VALID, action: "application" }),
    JSON.stringify({ ...VALID, extra: 1 }),
    JSON.stringify({ ...VALID, turnstile_token: "" }),
    JSON.stringify({ ...VALID, turnstile_token: "x".repeat(2049) }),
    JSON.stringify({ ...VALID, payload: [] }),
    JSON.stringify({ action: "inquiry", payload: {} }),
  ];
  for (const body of bad) {
    const h = harness({});
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 400, body.slice(0, 40));
    assert.deepEqual(h.order, []);
  }
});

// ---------------------------------------------------------------- rate limits

test("the per-IP key is a 64-hex HMAC and the raw IP never leaves the handler", async () => {
  const h = harness({});
  const res = await handle(post(VALID), h.deps);
  assert.equal(res.status, 200);
  const ipCall = h.calls.find((c) => c.args.p_bucket === "submit_ip");
  assert.ok(ipCall);
  assert.match(String(ipCall.args.p_key_hash), /^[0-9a-f]{64}$/);
  assert.equal(ipCall.args.p_key_hash, await hmacHex(IP_KEY, RAW_IP));
  const everything = JSON.stringify(h.calls) + JSON.stringify(h.logs);
  assert.ok(!everything.includes(RAW_IP));
  assert.ok(!everything.includes(IP_KEY));
});

test("IP limit reached: 429 with the call-the-office message, Turnstile never called", async () => {
  const h = harness({ ipOk: false });
  const res = await handle(post(VALID), h.deps);
  assert.equal(res.status, 429);
  assert.equal((await json(res)).error, MESSAGES.office);
  assert.deepEqual(h.order, ["submit_ip"]);
});

test("a rate limit error fails closed", async () => {
  for (const opts of [
    { ipOk: "error" as const },
    { globalOk: "error" as const },
  ]) {
    const h = harness(opts);
    const res = await handle(post(VALID), h.deps);
    assert.equal(res.status, 503);
    assert.ok(!h.order.includes("submit_inquiry"));
  }
});

test("the global limit is counted only after Turnstile passes", async () => {
  const ok = harness({});
  await handle(post(VALID), ok.deps);
  assert.deepEqual(ok.order, [
    "submit_ip",
    "turnstile",
    "submit_global",
    "submit_inquiry",
  ]);

  const failed = harness({ turnstile: { success: false } });
  await handle(post(VALID), failed.deps);
  assert.deepEqual(failed.order, ["submit_ip", "turnstile"]);
});

test("global limit reached: 429 with the office message, no submit", async () => {
  const h = harness({ globalOk: false });
  const res = await handle(post(VALID), h.deps);
  assert.equal(res.status, 429);
  assert.equal((await json(res)).error, MESSAGES.office);
  assert.ok(!h.order.includes("submit_inquiry"));
});

// ---------------------------------------------------------------- Turnstile

test("Turnstile timeout or error fails closed", async () => {
  const h = harness({ turnstile: "throw" });
  const res = await handle(post(VALID), h.deps);
  assert.equal(res.status, 503);
  assert.equal((await json(res)).error, MESSAGES.verify);
  assert.ok(!h.order.includes("submit_inquiry"));
});

test("Turnstile needs success true, an allowed hostname and the inquiry action", async () => {
  const refused: TurnstileOutcome[] = [
    { success: false, hostname: "app.example.test", action: "inquiry" },
    { success: "true", hostname: "app.example.test", action: "inquiry" },
    { success: true, hostname: "evil.test", action: "inquiry" },
    { success: true, action: "inquiry" },
    { success: true, hostname: "app.example.test", action: "application" },
    { success: true, hostname: "app.example.test" },
    {},
  ];
  for (const t of refused) {
    const h = harness({ turnstile: t });
    const res = await handle(post(VALID), h.deps);
    assert.equal(res.status, 400, JSON.stringify(t));
    assert.ok(!h.order.includes("submit_inquiry"));
  }
  const local = harness({
    turnstile: { success: true, hostname: "localhost", action: "inquiry" },
  });
  assert.equal(
    (await handle(post(VALID, { origin: "http://localhost:8080" }), local.deps))
      .status,
    200,
  );
});

test("the token reaches only the verifier", async () => {
  const h = harness({});
  await handle(post(VALID), h.deps);
  assert.deepEqual(h.tokensSeen, [TOKEN]);
  assert.ok(!JSON.stringify(h.calls).includes(TOKEN));
});

// ---------------------------------------------------------------- submit

test("success returns only the references", async () => {
  const h = harness({
    submit: { data: ["INQ-2026-0007", "INQ-2026-0008"], error: null },
  });
  const res = await handle(post(VALID), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), {
    references: ["INQ-2026-0007", "INQ-2026-0008"],
  });
  const sub = h.calls.find((c) => c.fn === "submit_inquiry");
  assert.deepEqual(sub?.args, { p_payload: VALID.payload });
});

test("database refusals map to fixed responses", async () => {
  const cases: [string, number, string | null][] = [
    ["TCS22", 400, "Child 1: choose a grade from the list"],
    ["TCS03", 409, MESSAGES.closed],
    ["TCS29", 429, MESSAGES.office],
    ["23514", 500, MESSAGES.error],
    ["P0001", 500, MESSAGES.error],
  ];
  for (const [code, status, message] of cases) {
    const h = harness({
      submit: {
        data: null,
        error: { code, message: "Child 1: choose a grade from the list" },
      },
    });
    const res = await handle(post(VALID), h.deps);
    assert.equal(res.status, status, code);
    assert.equal((await json(res)).error, message);
  }
});

test("a validation error passes a well formed field path, and nothing else", async () => {
  const run = async (details: string | null | undefined) => {
    const h = harness({
      submit: {
        data: null,
        error: { code: "TCS22", message: "Child 1: required", details },
      },
    });
    return json(await handle(post(VALID), h.deps));
  };
  assert.deepEqual(await run("students.0.grade_id"), {
    error: "Child 1: required",
    field: "students.0.grade_id",
  });
  assert.deepEqual(await run("guardians.1.phone"), {
    error: "Child 1: required",
    field: "guardians.1.phone",
  });
  assert.deepEqual(await run("referral_source"), {
    error: "Child 1: required",
    field: "referral_source",
  });
  for (const bad of [
    null,
    undefined,
    "",
    "students.9.grade_id",
    "Failing row contains (x@y.z)",
    "students.0.Grade",
  ]) {
    assert.deepEqual(
      await run(bad),
      { error: "Child 1: required" },
      String(bad),
    );
  }
});

test("an unexpected database error logs only its code, never the message", async () => {
  const h = harness({
    submit: {
      data: null,
      error: { code: "23514", message: "Failing row contains (ama@x.test)" },
    },
  });
  await handle(post(VALID), h.deps);
  assert.deepEqual(h.logs.at(-1), "submit_failed_23514");
  assert.ok(!JSON.stringify(h.logs).includes("ama@x.test"));
});

test("a thrown submit or an odd result is a 500, not a success", async () => {
  for (const submit of [
    "throw" as const,
    { data: [], error: null },
    { data: "x", error: null },
  ]) {
    const h = harness({ submit });
    assert.equal((await handle(post(VALID), h.deps)).status, 500);
  }
});

test("no response or log ever carries a secret, the token or the raw IP", async () => {
  const scenarios: Parameters<typeof harness>[0][] = [
    {},
    { ipOk: false },
    { globalOk: false },
    { turnstile: "throw" },
    { turnstile: { success: false } },
    { submit: { data: null, error: { code: "TCS03", message: "closed" } } },
    { submit: { data: null, error: { code: "XX000", message: "internal" } } },
  ];
  for (const s of scenarios) {
    const h = harness(s);
    const res = await handle(post(VALID), h.deps);
    const text =
      (await res.text()) +
      JSON.stringify([...res.headers]) +
      JSON.stringify(h.logs);
    for (const needle of [SECRET, IP_KEY, TOKEN, RAW_IP]) {
      assert.ok(
        !text.includes(needle),
        `${needle} leaked in ${JSON.stringify(s)}`,
      );
    }
  }
});

// ---------------------------------------------------------------- real verifier, fake fetch

test("the verifier posts secret and token, and throws on a bad answer or timeout", async () => {
  let sent: URLSearchParams | null = null;
  const okFetch = (async (_url: string, init: RequestInit) => {
    sent = init.body as URLSearchParams;
    return new Response(JSON.stringify(GOOD_TURNSTILE), { status: 200 });
  }) as unknown as typeof fetch;
  assert.deepEqual(
    await makeTurnstileVerifier(okFetch)(TOKEN, SECRET),
    GOOD_TURNSTILE,
  );
  assert.equal(sent!.get("secret"), SECRET);
  assert.equal(sent!.get("response"), TOKEN);

  const status500 = (async () =>
    new Response("nope", { status: 500 })) as unknown as typeof fetch;
  await assert.rejects(makeTurnstileVerifier(status500)(TOKEN, SECRET));

  const notJson = (async () =>
    new Response("<html>", { status: 200 })) as unknown as typeof fetch;
  await assert.rejects(makeTurnstileVerifier(notJson)(TOKEN, SECRET));

  const hang = ((_url: string, init: RequestInit) =>
    new Promise((_resolve, reject) => {
      init.signal?.addEventListener("abort", () =>
        reject(new Error("aborted")),
      );
    })) as unknown as typeof fetch;
  // AbortSignal.timeout's timer doesn't hold Node's event loop open.
  const keepAlive = setTimeout(() => {}, 1000);
  await assert.rejects(makeTurnstileVerifier(hang, 50)(TOKEN, SECRET));
  clearTimeout(keepAlive);
});

// ---------------------------------------------------------------- uploads (slice 9a checkpoint 1)

const SESSION = "a".repeat(64);
const RES_ID = "4d44e2df-9e85-4139-a906-986359e0e8f9";
const RES_PATH = `uploads/${RES_ID}/application_fee_proof.pdf`;

function uploadHarness(opts: {
  ipOk?: boolean | "error";
  globalOk?: boolean | "error";
  turnstile?: TurnstileOutcome | "throw";
  open?: RpcResult | "throw";
  reserve?: RpcResult | "throw";
  sign?: { token: string } | "throw";
  claim?: RpcResult;
  remove?: "throw";
  noStorage?: boolean;
}) {
  const order: string[] = [];
  const logs: string[] = [];
  const signed: string[] = [];
  const removed: string[][] = [];
  const finished: unknown[] = [];
  const deferred: Promise<unknown>[] = [];
  const deps: Deps = {
    config: CONFIG,
    verifyTurnstile: async () => {
      order.push("turnstile");
      if (opts.turnstile === "throw") throw new Error("timeout");
      return opts.turnstile ?? { ...GOOD_TURNSTILE, action: "upload" };
    },
    rpc: async (fn, args) => {
      if (fn === "check_public_rate_limit") {
        order.push(String(args.p_bucket));
        const v =
          args.p_bucket === "upload_ip"
            ? (opts.ipOk ?? true)
            : (opts.globalOk ?? true);
        if (v === "error")
          return { data: null, error: { code: "XX000", message: "boom" } };
        return { data: v, error: null };
      }
      order.push(fn);
      if (fn === "open_application_upload_session") {
        if (opts.open === "throw") throw new Error("network");
        return (
          opts.open ?? {
            data: {
              session_token: SESSION,
              expires_at: "2026-10-15T00:00:00Z",
              max_files: 8,
            },
            error: null,
          }
        );
      }
      if (fn === "reserve_application_upload") {
        if (opts.reserve === "throw") throw new Error("network");
        return (
          opts.reserve ?? {
            data: {
              reservation_id: RES_ID,
              storage_path: RES_PATH,
              expires_at: "2026-10-15T00:00:00Z",
            },
            error: null,
          }
        );
      }
      if (fn === "claim_expired_application_uploads")
        return opts.claim ?? { data: [], error: null };
      if (fn === "finish_application_upload_cleanup") {
        finished.push(args.p_reservation_ids);
        return { data: 1, error: null };
      }
      throw new Error(`unexpected rpc ${fn}`);
    },
    log: (o) => logs.push(o),
    storage: opts.noStorage
      ? undefined
      : {
          signUpload: async (path) => {
            signed.push(path);
            if (opts.sign === "throw") throw new Error("sign");
            return opts.sign ?? { token: "signed-upload-token" };
          },
          remove: async (paths) => {
            removed.push(paths);
            if (opts.remove === "throw") throw new Error("remove");
          },
          readHead: async () => {
            throw new Error("not used by the upload actions");
          },
        },
    defer: (work) => {
      deferred.push(work);
    },
  };
  return { deps, order, logs, signed, removed, finished, deferred };
}

const SESSION_REQ = { action: "upload_session", turnstile_token: TOKEN };
const URL_REQ = {
  action: "upload_url",
  payload: {
    session_token: SESSION,
    document_type: "application_fee_proof",
    extension: "PDF",
    size: 1000,
  },
};

test("upload_session: upload_ip, Turnstile, sweep, upload_global, then the session; only three keys back", async () => {
  const h = uploadHarness({});
  const res = await handle(post(SESSION_REQ), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), {
    session_token: SESSION,
    expires_at: "2026-10-15T00:00:00Z",
    max_files: 8,
  });
  assert.equal(h.order[0], "upload_ip");
  assert.equal(h.order[1], "turnstile");
  assert.ok(h.order.indexOf("upload_global") > h.order.indexOf("turnstile"));
  assert.equal(h.order.at(-1), "open_application_upload_session");
  assert.equal(h.deferred.length, 1);
  assert.equal(h.signed.length, 0);
});

test("upload_session: the IP key is a 64-hex HMAC, the IP limit refuses before Turnstile", async () => {
  const seen: unknown[] = [];
  const h = uploadHarness({ ipOk: false });
  const rpc = h.deps.rpc;
  h.deps.rpc = async (fn, args) => {
    seen.push(args.p_key_hash);
    return rpc(fn, args);
  };
  const res = await handle(post(SESSION_REQ), h.deps);
  assert.equal(res.status, 429);
  assert.equal((await json(res)).error, MESSAGES.appOffice);
  assert.equal(seen[0], await hmacHex(IP_KEY, RAW_IP));
  assert.ok(!h.order.includes("turnstile"));
  assert.equal(h.deferred.length, 0);
});

test("upload_session: Turnstile must carry the upload action; an inquiry token is refused, and the reverse", async () => {
  for (const turnstile of [
    { ...GOOD_TURNSTILE, action: "inquiry" },
    { ...GOOD_TURNSTILE, action: "upload", hostname: "evil.test" },
    { ...GOOD_TURNSTILE, action: "upload", success: false },
  ]) {
    const h = uploadHarness({ turnstile });
    const res = await handle(post(SESSION_REQ), h.deps);
    assert.equal(res.status, 400);
    assert.ok(!h.order.includes("open_application_upload_session"));
    assert.equal(h.deferred.length, 0);
  }
  const inquiry = harness({
    turnstile: { ...GOOD_TURNSTILE, action: "upload" },
  });
  assert.equal((await handle(post(VALID), inquiry.deps)).status, 400);
});

test("upload_session: the global limit refuses after Turnstile, and the sweep still runs", async () => {
  const h = uploadHarness({ globalOk: false });
  const res = await handle(post(SESSION_REQ), h.deps);
  assert.equal(res.status, 429);
  assert.equal(h.deferred.length, 1);
  assert.ok(!h.order.includes("open_application_upload_session"));
});

test("upload_session: closed, cap full and unexpected errors map to fixed answers", async () => {
  const cases: [RpcResult, number, string][] = [
    [
      { data: null, error: { code: "TCS03", message: "x" } },
      409,
      MESSAGES.appClosed,
    ],
    [
      { data: null, error: { code: "TCS29", message: "x" } },
      429,
      MESSAGES.appOffice,
    ],
    [
      { data: null, error: { code: "42501", message: "secret detail" } },
      500,
      MESSAGES.error,
    ],
    [{ data: { session_token: "short" }, error: null }, 500, MESSAGES.error],
  ];
  for (const [open, status, message] of cases) {
    const h = uploadHarness({ open });
    const res = await handle(post(SESSION_REQ), h.deps);
    assert.equal(res.status, status);
    assert.equal((await json(res)).error, message);
  }
});

test("upload requests with the wrong keys are refused before any call", async () => {
  for (const body of [
    { ...SESSION_REQ, payload: {} },
    { action: "upload_session" },
    { ...URL_REQ, turnstile_token: TOKEN },
    {
      action: "upload_url",
      payload: { ...URL_REQ.payload, path: "uploads/x" },
    },
    {
      action: "upload_url",
      payload: { ...URL_REQ.payload, session_token: "A".repeat(64) },
    },
    {
      action: "upload_url",
      payload: { ...URL_REQ.payload, session_token: 12 },
    },
  ]) {
    const h = uploadHarness({});
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 400, JSON.stringify(body));
    assert.deepEqual(h.order, []);
  }
});

test("upload_url: a bad type, extension or size is refused before the database", async () => {
  for (const change of [
    { document_type: "passport_photo" },
    { extension: "heic" },
    { extension: "exe" },
    { size: 0 },
    { size: 10 * 1024 * 1024 + 1 },
    { size: 1.5 },
    { size: "100" },
  ]) {
    const h = uploadHarness({});
    const res = await handle(
      post({
        action: "upload_url",
        payload: { ...URL_REQ.payload, ...change },
      }),
      h.deps,
    );
    assert.equal(res.status, 400);
    assert.equal((await json(res)).error, MESSAGES.fileRejected);
    assert.deepEqual(h.order, []);
  }
});

test("upload_url: reserves, signs exactly the database's path, no Turnstile and no limit call", async () => {
  const h = uploadHarness({});
  const res = await handle(post(URL_REQ), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), {
    reservation_id: RES_ID,
    path: RES_PATH,
    upload_token: "signed-upload-token",
    expires_at: "2026-10-15T00:00:00Z",
  });
  assert.deepEqual(h.order, ["reserve_application_upload"]);
  assert.deepEqual(h.signed, [RES_PATH]);
});

test("upload_url: a path that isn't this reservation's shape is never signed", async () => {
  for (const storage_path of [
    "uploads/other/application_fee_proof.pdf",
    `uploads/${RES_ID}/application_fee_proof.html`,
    `uploads/${"0".repeat(8)}-0000-4000-8000-000000000000/application_fee_proof.pdf`,
    `receipts/${RES_ID}/application_fee_proof.pdf`,
  ]) {
    const h = uploadHarness({
      reserve: {
        data: { reservation_id: RES_ID, storage_path, expires_at: "x" },
        error: null,
      },
    });
    const res = await handle(post(URL_REQ), h.deps);
    assert.equal(res.status, 500);
    assert.deepEqual(h.signed, []);
  }
});

test("upload_url: database refusals map like the session's, and a TCS22 message is shown", async () => {
  const h = uploadHarness({
    reserve: {
      data: null,
      error: { code: "TCS22", message: "Your upload session has expired." },
    },
  });
  const res = await handle(post(URL_REQ), h.deps);
  assert.equal(res.status, 400);
  assert.equal((await json(res)).error, "Your upload session has expired.");
  assert.deepEqual(h.signed, []);
  const closed = uploadHarness({
    reserve: { data: null, error: { code: "TCS03", message: "x" } },
  });
  assert.equal((await handle(post(URL_REQ), closed.deps)).status, 409);
});

test("upload_url: a signing failure or missing storage refuses with the office message", async () => {
  const h = uploadHarness({ sign: "throw" });
  const res = await handle(post(URL_REQ), h.deps);
  assert.equal(res.status, 503);
  assert.equal((await json(res)).error, MESSAGES.appOffice);
  const none = uploadHarness({ noStorage: true });
  assert.equal((await handle(post(URL_REQ), none.deps)).status, 503);
  assert.equal((await handle(post(SESSION_REQ), none.deps)).status, 503);
});

test("sweep: deletes only reservation-shaped paths, then marks exactly those", async () => {
  const good = { reservation_id: RES_ID, storage_path: RES_PATH };
  const h = uploadHarness({
    claim: {
      data: [good, { reservation_id: RES_ID, storage_path: "receipts/x.png" }],
      error: null,
    },
  });
  await sweepExpiredUploads(h.deps);
  assert.deepEqual(h.removed, [[RES_PATH]]);
  assert.deepEqual(h.finished, [[RES_ID]]);
  assert.ok(h.logs.includes("sweep_odd_rows"));
  assert.equal(SWEEP_BATCH, 20);
});

test("sweep: a failed delete leaves the claim to lapse; a failed claim deletes nothing; never throws", async () => {
  const good = { reservation_id: RES_ID, storage_path: RES_PATH };
  const h = uploadHarness({
    claim: { data: [good], error: null },
    remove: "throw",
  });
  await sweepExpiredUploads(h.deps);
  assert.deepEqual(h.finished, []);
  assert.ok(h.logs.includes("sweep_failed"));
  const c = uploadHarness({ claim: { data: null, error: { code: "XX000" } } });
  await sweepExpiredUploads(c.deps);
  assert.deepEqual(c.removed, []);
});

// ---------------------------------------------------------------- application

const PDF = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37]);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);
const HTML = new TextEncoder().encode("<!doctype html><script>");
const RES_ID_2 = "5e55f3e0-0f96-4a4a-b017-097470f1f9a0";
const RES_PATH_2 = `uploads/${RES_ID_2}/previous_report.png`;

function applicationHarness(opts: {
  ipOk?: boolean | "error";
  globalOk?: boolean | "error";
  turnstile?: TurnstileOutcome | "throw";
  submit?: RpcResult | "throw";
  heads?: Record<string, Uint8Array | "throw">;
  noStorage?: boolean;
}) {
  const order: string[] = [];
  const logs: string[] = [];
  const submits: Record<string, unknown>[] = [];
  const reads: string[] = [];
  const deps: Deps = {
    config: CONFIG,
    verifyTurnstile: async () => {
      order.push("turnstile");
      if (opts.turnstile === "throw") throw new Error("timeout");
      return opts.turnstile ?? { ...GOOD_TURNSTILE, action: "application" };
    },
    rpc: async (fn, args) => {
      if (fn === "check_public_rate_limit") {
        order.push(String(args.p_bucket));
        const v =
          args.p_bucket === "submit_ip"
            ? (opts.ipOk ?? true)
            : (opts.globalOk ?? true);
        if (v === "error")
          return { data: null, error: { code: "XX000", message: "boom" } };
        return { data: v, error: null };
      }
      order.push(fn);
      if (fn === "submit_application") {
        submits.push(args);
        if (opts.submit === "throw") throw new Error("network");
        return opts.submit ?? { data: "APP-2026-0042", error: null };
      }
      throw new Error(`unexpected rpc ${fn}`);
    },
    log: (o) => logs.push(o),
    storage: opts.noStorage
      ? undefined
      : {
          signUpload: async () => {
            throw new Error("not used");
          },
          remove: async () => {
            throw new Error("not used");
          },
          readHead: async (path, n) => {
            order.push("read");
            reads.push(path);
            assert.equal(n, 16);
            const h = (opts.heads ?? { [RES_PATH]: PDF })[path];
            if (h === undefined || h === "throw") throw new Error("no object");
            return h.subarray(0, n);
          },
        },
  };
  return { deps, order, logs, submits, reads };
}

function appReq(payload: Record<string, unknown> = {}) {
  return {
    action: "application",
    turnstile_token: TOKEN,
    session_token: SESSION,
    payload: {
      documents: [
        {
          document_type: "application_fee_proof",
          reservation_id: RES_ID,
          path: RES_PATH,
        },
      ],
      ...payload,
    },
  };
}

test("sniffKind: PDF strict at offset 0, JPEG, PNG; anything else unknown", () => {
  assert.equal(sniffKind(PDF), "pdf");
  assert.equal(sniffKind(JPEG), "jpeg");
  assert.equal(sniffKind(PNG), "png");
  assert.equal(sniffKind(HTML), "unknown");
  assert.equal(sniffKind(new Uint8Array([0x20, ...PDF])), "unknown");
  assert.equal(sniffKind(new Uint8Array([0x25, 0x50])), "unknown");
  assert.equal(sniffKind(new Uint8Array([])), "unknown");
  assert.equal(sniffKind(new Uint8Array([0xff, 0xd8])), "unknown");
});

test("application: submit_ip, Turnstile, submit_global, byte check, then submit_application; only the reference back", async () => {
  const h = applicationHarness({});
  const res = await handle(post(appReq()), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), { reference: "APP-2026-0042" });
  assert.deepEqual(h.order, [
    "submit_ip",
    "turnstile",
    "submit_global",
    "read",
    "submit_application",
  ]);
  assert.deepEqual(h.submits, [
    {
      p_payload: appReq().payload,
      p_session_token: SESSION,
      p_sniffed: [{ reservation_id: RES_ID, path: RES_PATH, kind: "pdf" }],
    },
  ]);
  // No IP of any form reaches the database.
  assert.ok(!JSON.stringify(h.submits).includes(RAW_IP));
  assert.deepEqual(h.logs, ["application_created"]);
});

test("application: the extension isn't trusted; the bytes are read and reported as they are", async () => {
  const h = applicationHarness({ heads: { [RES_PATH]: HTML } });
  await handle(post(appReq()), h.deps);
  assert.deepEqual(h.submits[0].p_sniffed, [
    { reservation_id: RES_ID, path: RES_PATH, kind: "unknown" },
  ]);
  const p = applicationHarness({ heads: { [RES_PATH]: PNG } });
  await handle(post(appReq()), p.deps);
  assert.equal(
    (p.submits[0].p_sniffed as { kind: string }[])[0].kind,
    "png",
  );
});

test("application: a failed read is unknown and still goes to the database, which decides", async () => {
  const h = applicationHarness({ heads: { [RES_PATH]: "throw" } });
  const res = await handle(post(appReq()), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(h.submits[0].p_sniffed, [
    { reservation_id: RES_ID, path: RES_PATH, kind: "unknown" },
  ]);
});

test("application: only reservation-shaped paths are read, at most four, never other bucket paths", async () => {
  const docs = [
    { document_type: "x", reservation_id: RES_ID, path: "receipts/a.pdf" },
    { document_type: "x", reservation_id: RES_ID, path: RES_PATH_2 },
    { document_type: "x", reservation_id: RES_ID_2, path: RES_PATH_2 },
    "not an object",
    { document_type: "x", reservation_id: RES_ID, path: RES_PATH },
    { document_type: "x", reservation_id: "nope", path: RES_PATH },
  ];
  const h = applicationHarness({ heads: { [RES_PATH_2]: PNG } });
  await handle(post(appReq({ documents: docs })), h.deps);
  // The fifth entry is past the four the database could accept.
  assert.deepEqual(h.reads, [RES_PATH_2]);
  assert.deepEqual(h.submits[0].p_sniffed, [
    { reservation_id: RES_ID_2, path: RES_PATH_2, kind: "png" },
  ]);
  const none = applicationHarness({});
  await handle(post(appReq({ documents: "x" })), none.deps);
  assert.deepEqual(none.reads, []);
  assert.deepEqual(none.submits[0].p_sniffed, []);
});

test("application: Turnstile must be for the application action; a refusal reads and submits nothing", async () => {
  for (const action of ["upload", "inquiry", undefined]) {
    const h = applicationHarness({
      turnstile: { ...GOOD_TURNSTILE, action },
    });
    const res = await handle(post(appReq()), h.deps);
    assert.equal(res.status, 400);
    assert.equal((await json(res)).error, MESSAGES.verify);
    assert.ok(!h.order.includes("read"));
    assert.ok(!h.order.includes("submit_application"));
    assert.ok(!h.order.includes("submit_global"));
  }
  const t = applicationHarness({ turnstile: "throw" });
  assert.equal((await handle(post(appReq()), t.deps)).status, 503);
  assert.ok(!t.order.includes("submit_application"));
});

test("application: IP and global limits refuse before any read or submit", async () => {
  const ip = applicationHarness({ ipOk: false });
  const r1 = await handle(post(appReq()), ip.deps);
  assert.equal(r1.status, 429);
  assert.equal((await json(r1)).error, MESSAGES.appOffice);
  assert.deepEqual(ip.order, ["submit_ip"]);
  const g = applicationHarness({ globalOk: false });
  assert.equal((await handle(post(appReq()), g.deps)).status, 429);
  assert.deepEqual(g.order, ["submit_ip", "turnstile", "submit_global"]);
  const e = applicationHarness({ ipOk: "error" });
  assert.equal((await handle(post(appReq()), e.deps)).status, 503);
});

test("application: request shape: exact keys, a 64-hex session token, an object payload", async () => {
  const bad = [
    { ...appReq(), extra: 1 },
    { ...appReq(), session_token: "abc" },
    { ...appReq(), session_token: undefined },
    { ...appReq(), payload: [] },
    { ...appReq(), turnstile_token: "" },
  ];
  for (const body of bad) {
    const h = applicationHarness({});
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 400);
    assert.deepEqual(h.order, []);
  }
  // session_token is for the application action only.
  const h = applicationHarness({});
  const res = await handle(
    post({ action: "inquiry", turnstile_token: TOKEN, session_token: SESSION, payload: {} }),
    h.deps,
  );
  assert.equal(res.status, 400);
});

test("application: 64 KB body cap for the application, 32 KB still for the other actions", async () => {
  const pad = (n: number) => "x".repeat(n);
  const base = JSON.stringify(appReq({ scholarship_interest_details: "" })).length;
  const fits = appReq({ scholarship_interest_details: pad(MAX_APPLICATION_BODY_BYTES - base) });
  assert.equal(JSON.stringify(fits).length, MAX_APPLICATION_BODY_BYTES);
  assert.equal((await handle(post(fits), applicationHarness({}).deps)).status, 200);
  const over = appReq({ scholarship_interest_details: pad(MAX_APPLICATION_BODY_BYTES - base + 1) });
  assert.equal((await handle(post(over), applicationHarness({}).deps)).status, 413);
  const inquiry = {
    action: "inquiry",
    turnstile_token: TOKEN,
    payload: { comments: pad(MAX_BODY_BYTES) },
  };
  const h = applicationHarness({});
  assert.equal((await handle(post(inquiry), h.deps)).status, 413);
  assert.deepEqual(h.order, []);
});

test("application: database refusals map to fixed answers; only a safe field path is passed on", async () => {
  const cases: [RpcResult, number, string | null][] = [
    [{ data: null, error: { code: "TCS22", message: "Child: enter a valid date of birth", details: "student.date_of_birth" } }, 400, "student.date_of_birth"],
    [{ data: null, error: { code: "TCS22", message: "m", details: "guardians.1.phone" } }, 400, "guardians.1.phone"],
    [{ data: null, error: { code: "TCS22", message: "m", details: "documents" } }, 400, "documents"],
    [{ data: null, error: { code: "TCS22", message: "m", details: "student; drop table" } }, 400, null],
    [{ data: null, error: { code: "TCS22", message: "m", details: "guardians.5.phone" } }, 400, null],
  ];
  for (const [submit, status, field] of cases) {
    const h = applicationHarness({ submit });
    const res = await handle(post(appReq()), h.deps);
    assert.equal(res.status, status);
    const body = await json(res);
    assert.equal(body.field, field ?? undefined);
  }
  const closed = applicationHarness({ submit: { data: null, error: { code: "TCS03", message: "x" } } });
  const c = await handle(post(appReq()), closed.deps);
  assert.equal(c.status, 409);
  assert.equal((await json(c)).error, MESSAGES.appClosed);
  const limited = applicationHarness({ submit: { data: null, error: { code: "TCS29", message: "x" } } });
  const l = await handle(post(appReq()), limited.deps);
  assert.equal(l.status, 429);
  assert.equal((await json(l)).error, MESSAGES.appOffice);
  const odd = applicationHarness({ submit: { data: null, error: { code: "23505", message: "secret detail" } } });
  const o = await handle(post(appReq()), odd.deps);
  assert.equal(o.status, 500);
  assert.equal((await json(o)).error, MESSAGES.appError);
  assert.deepEqual(odd.logs, ["application_failed_23505"]);
  for (const data of [null, 42, { reference: "APP-2026-0001" }, "INQ-2026-0001", "APP-2026-1"]) {
    const h = applicationHarness({ submit: { data, error: null } });
    assert.equal((await handle(post(appReq()), h.deps)).status, 500);
  }
  const thrown = applicationHarness({ submit: "throw" });
  assert.equal((await handle(post(appReq()), thrown.deps)).status, 500);
  const nostore = applicationHarness({ noStorage: true });
  assert.equal((await handle(post(appReq()), nostore.deps)).status, 503);
});

test("safeApplicationFieldPath: only the application's field paths", () => {
  for (const ok of ["guardians.0.email", "student.grade_id", "emergency_contact.phone", "health_info.medical_conditions_details", "campus_id", "declaration_agreed", "documents"])
    assert.equal(safeApplicationFieldPath(ok), ok);
  for (const no of ["students.0.grade_id", "guardians.2.email", "student.", "x", "", null, "student.A"])
    assert.equal(safeApplicationFieldPath(no), null);
});
