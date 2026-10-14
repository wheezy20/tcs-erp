// Unit tests for handler.ts with a fake Turnstile verifier and fake RPCs:
// no network, no database. Run from the repo root with Node 22:
//
//   node --test supabase/functions/admissions-public/handler.test.ts
//
// integration.test.ts drives the same handler against the local database.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  MAX_BODY_BYTES,
  MESSAGES,
  clientIp,
  handle,
  hmacHex,
  loadConfig,
  makeTurnstileVerifier,
  parseAllowedOrigins,
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
