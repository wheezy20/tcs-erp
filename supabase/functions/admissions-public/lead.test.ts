// Unit tests for the PDF gate action (slice 13) with a fake Turnstile
// verifier and fake RPCs: no network, no database. Run from the repo root
// with Node 22:
//
//   node --test supabase/functions/admissions-public/lead.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  LEAD_SOURCE,
  MESSAGES,
  handle,
  hmacHex,
  loadConfig,
  type Config,
  type Deps,
  type RpcResult,
  type TurnstileOutcome,
} from "./handler.ts";

const STAFF = "https://app.example.test";
const SITE = "https://www.school.example.test";
const SECRET = "turnstile-secret-for-tests-only";
const IP_KEY = "ip-hash-key-for-tests-only-0123456789";
const RAW_IP = "203.0.113.9";
const TOKEN = "fake-turnstile-token-lead";

const CONFIG: Config = {
  allowedOrigins: [STAFF],
  leadOrigins: [SITE, "https://school.example.test"],
  turnstileSecret: SECRET,
  ipHashKey: IP_KEY,
};

const GOOD: TurnstileOutcome = {
  success: true,
  hostname: "www.school.example.test",
  action: "pdf_gate",
};

function harness(
  opts: {
    config?: Config | null;
    ipOk?: boolean | "error";
    globalOk?: boolean | "error";
    turnstile?: TurnstileOutcome | "throw";
    capture?: RpcResult | "throw";
  } = {},
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const order: string[] = [];
  const logs: string[] = [];
  const deps: Deps = {
    config: opts.config === undefined ? CONFIG : opts.config,
    verifyTurnstile: async (_token, secret) => {
      order.push("turnstile");
      assert.equal(secret, SECRET);
      if (opts.turnstile === "throw") throw new Error("timeout");
      return opts.turnstile ?? GOOD;
    },
    rpc: async (fn, args) => {
      calls.push({ fn, args });
      if (fn === "check_public_rate_limit") {
        order.push(String(args.p_bucket));
        const v =
          args.p_bucket === "lead_ip"
            ? (opts.ipOk ?? true)
            : args.p_bucket === "lead_global"
              ? (opts.globalOk ?? true)
              : true;
        if (v === "error") return { data: null, error: { code: "XX000", message: "boom" } };
        return { data: v, error: null };
      }
      order.push(fn);
      if (opts.capture === "throw") throw new Error("network");
      return opts.capture ?? { data: true, error: null };
    },
    log: (o) => logs.push(o),
  };
  return { deps, calls, order, logs };
}

function post(body: unknown, origin: string | null = SITE) {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-forwarded-for": `${RAW_IP}, 10.0.0.1`,
  };
  if (origin !== null) headers.origin = origin;
  return new Request("http://fn.local/admissions-public", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const LEAD = {
  action: "pdf_gate",
  turnstile_token: TOKEN,
  payload: {
    name: "Ama",
    email: "ama@example.test",
    consent_to_marketing: true,
  },
};

async function json(res: Response): Promise<Record<string, unknown>> {
  return (await res.json()) as Record<string, unknown>;
}

// ---------------------------------------------------------------- config

test("loadConfig reads the lead origins; a bad list refuses only the PDF gate", () => {
  const base: Record<string, string> = {
    ADMISSIONS_ALLOWED_ORIGINS: STAFF,
    TURNSTILE_SECRET_KEY: SECRET,
    IP_HASH_KEY: IP_KEY,
    SUPABASE_URL: "https://project.supabase.co",
  };
  const get = (env: Record<string, string>) => (n: string) => env[n];
  assert.deepEqual(
    loadConfig(get({ ...base, ADMISSIONS_LEAD_ORIGINS: `${SITE}, https://school.example.test` }))
      ?.leadOrigins,
    [SITE, "https://school.example.test"],
  );
  for (const bad of [
    "https://*.vercel.app",
    `${SITE}/`,
    "http://www.school.example.test",
    "http://localhost:8080",
    "",
  ]) {
    const c = loadConfig(get({ ...base, ADMISSIONS_LEAD_ORIGINS: bad }));
    assert.ok(c, `config lost for ${bad}`);
    assert.equal(c.leadOrigins, null, bad);
    assert.deepEqual(c.allowedOrigins, [STAFF]);
  }
  assert.equal(loadConfig(get(base))?.leadOrigins, null);
});

// ---------------------------------------------------------------- origins

test("a marketing origin gets a preflight answer for itself", async () => {
  const h = harness();
  const res = await handle(
    new Request("http://fn.local/admissions-public", {
      method: "OPTIONS",
      headers: { origin: SITE },
    }),
    h.deps,
  );
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), SITE);
  assert.equal(h.calls.length, 0);
});

test("a marketing origin can't call any other action", async () => {
  for (const body of [
    { action: "inquiry", turnstile_token: TOKEN, payload: { referral_source: "website" } },
    { action: "upload_session", turnstile_token: TOKEN },
    { action: "draft_get", payload: { draft_token: "a".repeat(64) } },
  ]) {
    const h = harness();
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 403, body.action);
    assert.equal(res.headers.get("access-control-allow-origin"), null);
    assert.equal(h.calls.length, 0);
    assert.deepEqual(h.order, []);
  }
});

test("the PDF gate refuses the staff origin, an unknown origin, no origin, and every origin when the lead list is unset", async () => {
  for (const [origin, config] of [
    [STAFF, CONFIG],
    ["https://evil.example.test", CONFIG],
    [null, CONFIG],
    [SITE, { ...CONFIG, leadOrigins: null }],
  ] as const) {
    const h = harness({ config });
    const res = await handle(post(LEAD, origin), h.deps);
    assert.equal(res.status, 403, String(origin));
    assert.equal(h.calls.length, 0);
    assert.deepEqual(h.order, []);
  }
});

// ---------------------------------------------------------------- the flow

test("a lead: lead_ip, Turnstile, lead_global, then capture_lead with the server's source and only the lead fields", async () => {
  const h = harness();
  const res = await handle(
    post({
      ...LEAD,
      payload: {
        ...LEAD.payload,
        source: "quick_interest_widget",
        utm_source: "facebook",
        favourite_colour: "blue",
      },
    }),
    h.deps,
  );
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), { ok: true });
  assert.equal(res.headers.get("access-control-allow-origin"), SITE);
  assert.deepEqual(h.order, ["lead_ip", "turnstile", "lead_global", "capture_lead"]);
  const ip = h.calls.find((c) => c.args.p_bucket === "lead_ip");
  assert.equal(ip?.args.p_key_hash, await hmacHex(IP_KEY, RAW_IP));
  const capture = h.calls.find((c) => c.fn === "capture_lead");
  assert.deepEqual(capture?.args, {
    p_source: LEAD_SOURCE,
    p_payload: {
      name: "Ama",
      email: "ama@example.test",
      consent_to_marketing: true,
      utm_source: "facebook",
    },
  });
  assert.ok(!JSON.stringify(h.logs).includes(RAW_IP));
  assert.ok(!JSON.stringify(h.logs).includes("ama@example.test"));
});

test("Turnstile must name the pdf_gate action and a marketing host; any failure refuses before the global count", async () => {
  for (const t of [
    { ...GOOD, action: "inquiry" },
    { ...GOOD, action: undefined },
    { ...GOOD, hostname: "app.example.test" },
    { ...GOOD, success: false },
  ]) {
    const h = harness({ turnstile: t });
    const res = await handle(post(LEAD), h.deps);
    assert.equal(res.status, 400);
    assert.equal((await json(res)).error, MESSAGES.verify);
    assert.deepEqual(h.order, ["lead_ip", "turnstile"]);
  }
  const h = harness({ turnstile: "throw" });
  assert.equal((await handle(post(LEAD), h.deps)).status, 503);
  assert.deepEqual(h.order, ["lead_ip", "turnstile"]);
});

test("every limit gives the same 429; the IP limit stops before Turnstile", async () => {
  let h = harness({ ipOk: false });
  let res = await handle(post(LEAD), h.deps);
  assert.equal(res.status, 429);
  assert.deepEqual(await json(res), { error: MESSAGES.leadOffice });
  assert.deepEqual(h.order, ["lead_ip"]);

  h = harness({ globalOk: false });
  res = await handle(post(LEAD), h.deps);
  assert.equal(res.status, 429);
  assert.deepEqual(await json(res), { error: MESSAGES.leadOffice });
  assert.deepEqual(h.order, ["lead_ip", "turnstile", "lead_global"]);

  h = harness({ ipOk: "error" });
  assert.equal((await handle(post(LEAD), h.deps)).status, 503);
});

test("closed: 409 with the agreed message and code closed", async () => {
  const h = harness({
    capture: { data: null, error: { code: "TCS03", message: "anything the database says" } },
  });
  const res = await handle(post(LEAD), h.deps);
  assert.equal(res.status, 409);
  assert.deepEqual(await json(res), {
    error:
      "The Admissions Overview download is not available right now. Please contact the school office.",
    code: "closed",
  });
});

test("invalid input: the database message, and the field only when it is a lead field", async () => {
  let h = harness({
    capture: {
      data: null,
      error: { code: "TCS22", message: "Enter a valid email address", details: "email" },
    },
  });
  let res = await handle(post(LEAD), h.deps);
  assert.equal(res.status, 400);
  assert.deepEqual(await json(res), { error: "Enter a valid email address", field: "email" });

  h = harness({
    capture: {
      data: null,
      error: { code: "TCS22", message: "The form could not be read", details: "guardians.0" },
    },
  });
  res = await handle(post(LEAD), h.deps);
  assert.deepEqual(await json(res), { error: "The form could not be read" });
});

test("anything but true from capture_lead, an unknown error or a thrown call is a 500 with no detail", async () => {
  for (const capture of [
    { data: "lead id", error: null },
    {
      data: null,
      error: { code: "42501", message: "permission denied for table admissions_leads" },
    },
    "throw",
  ] as const) {
    const h = harness({ capture });
    const res = await handle(post(LEAD), h.deps);
    assert.equal(res.status, 500);
    assert.deepEqual(await json(res), { error: MESSAGES.error });
  }
});

test("bad shapes are refused before any call", async () => {
  for (const body of [
    { action: "pdf_gate", payload: LEAD.payload },
    { action: "pdf_gate", turnstile_token: TOKEN },
    { action: "pdf_gate", turnstile_token: TOKEN, payload: [] },
    { ...LEAD, extra: 1 },
  ]) {
    const h = harness();
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 400);
    assert.equal(h.calls.length, 0);
  }
});
