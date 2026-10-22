// Unit tests for the offer actions (slice 11) with fake RPCs: no network,
// no database. Run from the repo root with Node 22:
//
//   node --test supabase/functions/admissions-public/offer.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";

import { MESSAGES, handle, hmacHex, type Config, type Deps, type RpcResult } from "./handler.ts";

const STAFF = "https://app.example.test";
const SITE = "https://www.school.example.test";
const IP_KEY = "ip-hash-key-for-tests-only-0123456789";
const RAW_IP = "203.0.113.11";
const LINK = "a".repeat(64);

const CONFIG: Config = {
  allowedOrigins: [STAFF],
  leadOrigins: [SITE],
  turnstileSecret: "turnstile-secret-for-tests-only",
  ipHashKey: IP_KEY,
};

const OPEN = {
  state: "open",
  first_name: "Ama",
  grade: "Grade 3",
  academic_year: "2027/2028",
  campus: "Main campus",
  respond_by: "2026-11-05T09:00:00+00:00",
};

function harness(
  opts: {
    ipOk?: boolean | "error";
    globalOk?: boolean | "error";
    result?: RpcResult | "throw";
  } = {},
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const order: string[] = [];
  const logs: string[] = [];
  let turnstile = 0;
  const deps: Deps = {
    config: CONFIG,
    verifyTurnstile: async () => {
      turnstile += 1;
      return { success: true };
    },
    rpc: async (fn, args) => {
      calls.push({ fn, args });
      if (fn === "check_public_rate_limit") {
        order.push(String(args.p_bucket));
        const v =
          args.p_bucket === "offer_ip"
            ? (opts.ipOk ?? true)
            : args.p_bucket === "offer_global"
              ? (opts.globalOk ?? true)
              : true;
        if (v === "error") return { data: null, error: { code: "XX000", message: "boom" } };
        return { data: v, error: null };
      }
      order.push(fn);
      if (opts.result === "throw") throw new Error("network");
      return opts.result ?? { data: OPEN, error: null };
    },
    log: (o) => logs.push(o),
  };
  return { deps, calls, order, logs, turnstileCalls: () => turnstile };
}

function post(body: unknown, origin: string | null = STAFF) {
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

const GET = { action: "offer_get", payload: { token: LINK } };
const ACCEPT = { action: "offer_respond", payload: { token: LINK, response: "accepted" } };

async function json(res: Response): Promise<Record<string, unknown>> {
  return (await res.json()) as Record<string, unknown>;
}

test("offer_get: offer_ip with an HMAC key, then offer_global, then the read; no Turnstile", async () => {
  const h = harness();
  const res = await handle(post(GET), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), OPEN);
  assert.deepEqual(h.order, ["offer_ip", "offer_global", "get_offer_by_link"]);
  assert.equal(h.calls[0].args.p_key_hash, await hmacHex(IP_KEY, RAW_IP));
  assert.equal(h.calls[1].args.p_key_hash, undefined);
  assert.deepEqual(h.calls[2].args, { p_token: LINK });
  assert.equal(h.turnstileCalls(), 0);
  assert.equal(res.headers.get("cache-control"), "no-store");
});

test("offer_respond passes the token and the answer and returns only status and response", async () => {
  const h = harness({ result: { data: { status: "recorded", response: "accepted", extra: "x" }, error: null } });
  const res = await handle(post(ACCEPT), h.deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await json(res), { status: "recorded", response: "accepted" });
  assert.deepEqual(h.calls.at(-1), {
    fn: "respond_to_offer",
    args: { p_token: LINK, p_response: "accepted" },
  });
  assert.equal(h.turnstileCalls(), 0);
});

test("an already answered offer comes back as answered, from either action", async () => {
  let h = harness({ result: { data: { state: "answered", response: "declined" }, error: null } });
  let res = await handle(post(GET), h.deps);
  assert.deepEqual(await json(res), { state: "answered", response: "declined" });
  h = harness({ result: { data: { status: "answered", response: "declined" }, error: null } });
  res = await handle(post(ACCEPT), h.deps);
  assert.deepEqual(await json(res), { status: "answered", response: "declined" });
});

test("a link that opens nothing gets one 404 with code offer_invalid, from either action", async () => {
  for (const body of [GET, ACCEPT, { action: "offer_get", payload: { token: "not-hex" } }]) {
    const h = harness({ result: { data: null, error: null } });
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 404);
    assert.deepEqual(await json(res), { error: MESSAGES.offerInvalid, code: "offer_invalid" });
  }
});

test("the read passes only the D-11a fields, and refuses an unexpected shape", async () => {
  const h = harness({ result: { data: { ...OPEN, full_name: "Ama Serwaa Mensah", email: "x@y.z" }, error: null } });
  const res = await handle(post(GET), h.deps);
  assert.deepEqual(Object.keys(await json(res)).sort(), Object.keys(OPEN).sort());
  for (const data of [{ ...OPEN, first_name: "" }, { ...OPEN, respond_by: "soon" }, { state: "open" }, "x", { status: "weird" }]) {
    const b = harness({ result: { data, error: null } });
    assert.equal((await handle(post(GET), b.deps)).status, 500);
  }
  const answeredBad = harness({ result: { data: { status: "recorded", response: "maybe" }, error: null } });
  assert.equal((await handle(post(ACCEPT), answeredBad.deps)).status, 500);
});

test("a null campus is allowed (no campus on the application)", async () => {
  const h = harness({ result: { data: { ...OPEN, campus: null }, error: null } });
  const res = await handle(post(GET), h.deps);
  assert.equal(res.status, 200);
  assert.equal((await json(res)).campus, null);
});

test("limits: offer_ip refuses before any lookup, offer_global after it; both 429 offer_limit; an error fails closed", async () => {
  let h = harness({ ipOk: false });
  let res = await handle(post(GET), h.deps);
  assert.equal(res.status, 429);
  assert.deepEqual(await json(res), { error: MESSAGES.offerLimit, code: "offer_limit" });
  assert.deepEqual(h.order, ["offer_ip"]);
  h = harness({ globalOk: false });
  res = await handle(post(ACCEPT), h.deps);
  assert.equal(res.status, 429);
  assert.deepEqual(h.order, ["offer_ip", "offer_global"]);
  h = harness({ ipOk: "error" });
  res = await handle(post(GET), h.deps);
  assert.equal(res.status, 503);
  assert.deepEqual(h.order, ["offer_ip"]);
});

test("malformed offer requests are 400 before any call", async () => {
  const bad = [
    { action: "offer_get", payload: {} },
    { action: "offer_get", payload: { token: 5 } },
    { action: "offer_get", payload: { token: "a".repeat(201) } },
    { action: "offer_get", payload: { token: LINK, response: "accepted" } },
    { action: "offer_get", payload: { token: LINK }, turnstile_token: "t" },
    { action: "offer_respond", payload: { token: LINK } },
    { action: "offer_respond", payload: { token: LINK, response: "pending" } },
    { action: "offer_respond", payload: { token: LINK, response: "accepted", extra: 1 } },
    { action: "offer_get", token: LINK },
  ];
  for (const body of bad) {
    const h = harness();
    const res = await handle(post(body), h.deps);
    assert.equal(res.status, 400, JSON.stringify(body));
    assert.deepEqual(h.calls, []);
  }
});

test("a marketing origin can't call the offer actions; an unknown origin gets 403", async () => {
  for (const origin of [SITE, "https://evil.example.test", null]) {
    const h = harness();
    const res = await handle(post(GET, origin), h.deps);
    assert.equal(res.status, 403);
    assert.equal(h.order.includes("get_offer_by_link"), false);
  }
});

test("a database error or a thrown call is a 500, logged by code only; the token never reaches a log or a response", async () => {
  let h = harness({ result: { data: null, error: { code: "P0001", message: `boom ${LINK}` } } });
  let res = await handle(post(ACCEPT), h.deps);
  assert.equal(res.status, 500);
  const text = await res.text();
  assert.equal(text.includes(LINK), false);
  assert.ok(h.logs.includes("offer_db_error_P0001"));
  h = harness({ result: "throw" });
  res = await handle(post(GET), h.deps);
  assert.equal(res.status, 500);
  assert.equal(h.logs.join(" ").includes(LINK), false);
  for (const body of [GET, ACCEPT]) {
    const g = harness();
    const r = await handle(post(body), g.deps);
    assert.equal((await r.text()).includes(LINK), false);
    assert.equal(g.logs.join(" ").includes(LINK), false);
    assert.equal(g.logs.join(" ").includes(RAW_IP), false);
  }
});

test("no offer message has an em or en dash", () => {
  for (const m of [MESSAGES.offerInvalid, MESSAGES.offerLimit, MESSAGES.offerError]) {
    assert.equal(/[\u2013\u2014]/.test(m), false);
  }
});
