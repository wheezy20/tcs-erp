// The offer path end to end (slice 11) against the LOCAL database and a
// LOCAL fake provider (a small HTTP server on 127.0.0.1): no email is ever
// sent and Resend is never called. A Manager generates an offer for a
// family with two guardian addresses; the worker mints one link per email
// at send time; admissions-public's offer_get and offer_respond open and
// answer it; sending the link again kills the old links; the second
// guardian sees the offer as answered; the staff alert carries only the
// reference, the response and the ERP link. Run on a freshly reset local
// stack from the repo root, after the probe files:
//
//   ./scripts/seed-local-dev-staff.sh
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
//        node --test supabase/functions/admissions-worker/offer.integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It commits a
// family, an application, its offer, outbox rows and a capability row for
// the dev Manager; `npx supabase db reset` clears them.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";

import {
  handle as handlePublic,
  type Config as PublicConfig,
  type Deps as PublicDeps,
} from "../admissions-public/handler.ts";
import { handle, loadMailConfig, makeResendSender, type Deps, type MailConfig } from "./handler.ts";

const API_URL = process.env.API_URL ?? "";
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY ?? "";
if (!/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(API_URL) || SERVICE_KEY === "") {
  throw new Error(
    "offer.integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
  );
}
const PROJECT = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)![1];
const RUN = Date.now().toString(36);
const G1 = `offer.one.${RUN}@example.test`;
const G2 = `offer.two.${RUN}@example.test`;
const STAFF = `offer.staff.${RUN}@example.test`;
const ORIGIN = "http://localhost:8080";

function psql(sql: string): string {
  return execFileSync(
    "docker",
    ["exec", "-i", `supabase_db_${PROJECT}`, "psql", "-U", "postgres", "-X", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
    { encoding: "utf8" },
  ).trim();
}

/** Runs a staff RPC as the dev Manager, in its own committed transaction. */
function asManager(sql: string): string {
  const mgr = psql("select id from public.staff where role = 'Manager' and active order by id limit 1");
  return execFileSync(
    "docker",
    ["exec", "-i", `supabase_db_${PROJECT}`, "psql", "-U", "postgres", "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1"],
    {
      encoding: "utf8",
      input: `begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"${mgr}","role":"authenticated"}';
${sql};
commit;`,
    },
  ).trim();
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const res = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const body = await res.json();
  return res.ok ? { data: body, error: null } : { data: null, error: body };
}

// ---------------------------------------------------------------- fake provider

const seen: Array<Record<string, unknown>> = [];
let server: Server;
let providerBase = "";

before(async () => {
  server = createServer((req, res) => {
    let raw = "";
    req.on("data", (d) => (raw += String(d)));
    req.on("end", () => {
      seen.push(JSON.parse(raw) as Record<string, unknown>);
      res
        .writeHead(200, { "content-type": "application/json" })
        .end(JSON.stringify({ id: `fake-${seen.length}` }));
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  providerBase = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  // Nothing due from earlier runs or other files.
  psql(
    "update public.admissions_email_outbox set status = 'failed', claim_token = null, claimed_at = null where status in ('pending', 'sending')",
  );
});
after(() => server.close());

function mailDeps(): Deps {
  const config = loadMailConfig(
    (n) =>
      ({
        MAIL_MODE: "test",
        RESEND_API_KEY: "fake-integration-key",
        RESEND_API_BASE: providerBase,
        MAIL_FROM: "TCS Admissions <no-reply@mail.example.test>",
        MAIL_REPLY_TO: "admissions@example.test",
        ADMISSIONS_STAFF_EMAIL: STAFF,
        ERP_BASE_URL: ORIGIN,
        PUBLIC_APPLY_BASE_URL: ORIGIN,
        MAIL_DAILY_CEILING: "1000",
        SUPABASE_URL: API_URL,
      })[n],
  ) as MailConfig;
  assert.ok(config, "test mail config refused");
  return { rpc, mail: config, send: makeResendSender(fetch), sleep: async () => {}, log: () => {} };
}

async function runMail() {
  const secret = psql(
    "select decrypted_secret from vault.decrypted_secrets where name = 'admissions_worker_secret'",
  );
  const res = await handle(
    new Request("http://fn.local/admissions-worker", {
      method: "POST",
      headers: { "content-type": "application/json", "x-admissions-worker-secret": secret },
      body: JSON.stringify({ job: "mail" }),
    }),
    mailDeps(),
  );
  assert.equal(res.status, 200);
}

const publicConfig: PublicConfig = {
  allowedOrigins: [ORIGIN],
  leadOrigins: null,
  turnstileSecret: "unused-for-offers",
  ipHashKey: "ip-hash-key-for-integration-tests-0123",
};
const publicLogs: string[] = [];
const publicDeps: PublicDeps = {
  config: publicConfig,
  verifyTurnstile: async () => {
    throw new Error("the offer actions never call Turnstile");
  },
  rpc,
  log: (o) => publicLogs.push(o),
};

async function offerCall(body: unknown) {
  const res = await handlePublic(
    new Request("http://fn.local/admissions-public", {
      method: "POST",
      headers: { "content-type": "application/json", origin: ORIGIN, "x-forwarded-for": "198.51.100.23" },
      body: JSON.stringify(body),
    }),
    publicDeps,
  );
  return { status: res.status, body: (await res.json()) as Record<string, unknown> };
}

/** The token in the newest offer email to this address. */
function tokenFor(to: string): string {
  const email = [...seen].reverse().find((e) => (e.to as string[])[0] === to && e.subject !== undefined && String(e.text).includes("/offer#token="));
  assert.ok(email, `no offer email to ${to}`);
  const m = /\/offer#token=([0-9a-f]{64})/.exec(String(email.text));
  assert.ok(m);
  return m[1];
}

// ---------------------------------------------------------------- fixture

let APP = "";
let REF = "";

before(() => {
  const fam = psql("insert into public.families default values returning id").split("\n")[0];
  const stu = psql(
    `insert into public.students (family_id, full_name) values ('${fam}', 'Kofi Offer Fixture') returning id`,
  ).split("\n")[0];
  psql(`insert into public.guardians (family_id, first_name, surname, email, phone, relationship) values
    ('${fam}', 'One', 'Fixture', '${G1}', '0240000000', 'guardian'),
    ('${fam}', 'Two', 'Fixture', '${G2}', '0240000000', 'guardian')`);
  APP = psql(`insert into public.applications (student_id, academic_year, year_group_applied_for, stage, branch_id)
    values ('${stu}', '2027/2028', 'Grade 3', 'document_review', (select id from public.branches order by created_at limit 1))
    returning id`).split("\n")[0];
  REF = psql(`select application_reference from public.applications where id = '${APP}'`);
  psql(`insert into public.staff_admissions_capabilities (staff_id, grade_bands, all_grades, can_decide, can_view_health)
    values ((select id from public.staff where role = 'Manager' and active order by id limit 1), '{}', false, true, false)
    on conflict (staff_id) do update set can_decide = true`);
  psql(`insert into public.application_decisions (application_id, decision_type, notes) values ('${APP}', 'accepted', 'offer integration')`);
});

// ---------------------------------------------------------------- tests

test("generate: one offer email per guardian, each with its own link, minted at send time and never stored", async () => {
  const out = asManager(`select public.generate_offer('${APP}')`);
  assert.match(out, /"emails_queued": 2/);
  assert.doesNotMatch(out, /token/);
  const before = seen.length;
  await runMail();
  const offerEmails = seen.slice(before).filter((e) => e.subject === "An offer of a place at Treasures Christian School");
  assert.equal(offerEmails.length, 2);
  const t1 = tokenFor(G1);
  const t2 = tokenFor(G2);
  assert.notEqual(t1, t2);
  for (const e of offerEmails) {
    assert.match(String(e.text), new RegExp(`reference is ${REF}\\.`));
    assert.doesNotMatch(String(e.text), /Kofi|Fixture/);
    assert.ok(String(e.text).includes(`${ORIGIN}/offer#token=`));
  }
  for (const t of [t1, t2]) {
    assert.equal(psql(`select count(*) from public.admissions_email_outbox x where row_to_json(x)::text like '%${t}%'`), "0");
    assert.equal(psql(`select count(*) from public.application_offer_links x where row_to_json(x)::text like '%${t}%'`), "0");
    assert.equal(
      psql(`select count(*) from public.application_offer_links where token_hash = encode(extensions.digest('${t}', 'sha256'), 'hex')`),
      "1",
    );
  }
});

test("offer_get opens the offer with only the D-11a fields; a made-up token gets the generic 404", async () => {
  const r = await offerCall({ action: "offer_get", payload: { token: tokenFor(G1) } });
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys(r.body).sort(), ["academic_year", "campus", "first_name", "grade", "respond_by", "state"]);
  assert.equal(r.body.first_name, "Kofi");
  assert.equal(r.body.grade, "Grade 3");
  const bad = await offerCall({ action: "offer_get", payload: { token: "f".repeat(64) } });
  assert.equal(bad.status, 404);
  assert.equal(bad.body.code, "offer_invalid");
});

test("sending the link again kills both old links; the new ones work", async () => {
  const old1 = tokenFor(G1);
  const old2 = tokenFor(G2);
  assert.match(asManager(`select public.resend_offer_link('${APP}')`), /"emails_queued": 2/);
  for (const t of [old1, old2]) {
    const r = await offerCall({ action: "offer_get", payload: { token: t } });
    assert.equal(r.status, 404);
    const a = await offerCall({ action: "offer_respond", payload: { token: t, response: "accepted" } });
    assert.equal(a.status, 404);
  }
  await runMail();
  assert.notEqual(tokenFor(G1), old1);
  const r = await offerCall({ action: "offer_get", payload: { token: tokenFor(G1) } });
  assert.equal(r.body.state, "open");
});

test("the first guardian accepts once; the second sees it answered; the staff alert has only the reference, the response and the link", async () => {
  const a = await offerCall({ action: "offer_respond", payload: { token: tokenFor(G1), response: "accepted" } });
  assert.deepEqual(a, { status: 200, body: { status: "recorded", response: "accepted" } });
  const again = await offerCall({ action: "offer_respond", payload: { token: tokenFor(G1), response: "declined" } });
  assert.deepEqual(again.body, { status: "answered", response: "accepted" });
  const other = await offerCall({ action: "offer_respond", payload: { token: tokenFor(G2), response: "declined" } });
  assert.deepEqual(other.body, { status: "answered", response: "accepted" });
  assert.equal(
    psql(`select response || '|' || response_source from public.application_offers where application_id = '${APP}'`),
    "accepted|offer_link",
  );
  assert.equal(
    psql(`select count(*) from public.audit_log where action = 'application_offer_responded' and actor_id is null
          and entity_id = (select id::text from public.application_offers where application_id = '${APP}')`),
    "1",
  );
  const before = seen.length;
  await runMail();
  const alert = seen.slice(before).find((e) => (e.to as string[])[0] === STAFF);
  assert.ok(alert, "no staff alert");
  assert.equal(alert.subject, `Offer ${REF} accepted through the offer link`);
  assert.ok(String(alert.text).endsWith(`${ORIGIN}/admissions/${APP}`));
  assert.doesNotMatch(String(alert.text), /Kofi|Fixture|example\.test/);
  for (const l of publicLogs) assert.doesNotMatch(l, /[0-9a-f]{64}/);
});
