// The admissions-public draft actions (slice 10, checkpoint C2) against the
// LOCAL database and the LOCAL Storage API, with a fake Turnstile verifier
// (no call to Cloudflare): create, open, save with the version check, the
// resume email limits, the generic live-draft refusal, submit through the
// draft with the upload session's replay rule, a second window, and
// delete. No email is sent: the worker is not run here. Run on a freshly
// reset local stack from the repo root, after the probe files:
//
//   ./scripts/seed-local-dev-staff.sh
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
//        node --test supabase/functions/admissions-public/draft.integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It opens public
// applications, commits drafts, outbox rows, families, applications and
// files, and closes applications again at the end. It deletes the files it
// uploaded; `npx supabase db reset` clears the rows.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import { MESSAGES, handle, type Deps } from "./handler.ts";
import { makeStorage } from "./storage.ts";

const API_URL = process.env.API_URL ?? "";
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY ?? "";
if (
  !/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(API_URL) ||
  SERVICE_KEY === ""
) {
  throw new Error(
    "draft.integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
  );
}

const ORIGIN = "http://localhost:8080";
const IP_KEY = "integration-ip-hash-key-0123456789abcdef";
const BUCKET = "admissions-documents";
const PROJECT = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)![1];
const STATE = JSON.parse(
  readFileSync(
    "supabase/functions/admissions-public/fixtures/saved-application-state.json",
    "utf8",
  ),
) as Record<string, unknown>;

function psql(sql: string): string {
  return execFileSync(
    "docker",
    [
      "exec",
      "-i",
      `supabase_db_${PROJECT}`,
      "psql",
      "-U",
      "postgres",
      "-X",
      "-At",
      "-c",
      sql,
    ],
    { encoding: "utf8" },
  ).trim();
}

function service(path: string, init: RequestInit = {}) {
  return fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      ...(init.headers ?? {}),
    },
  });
}

const uploaded: string[] = [];
const RUN = Date.now().toString(36);
const email = (who: string) => `draft.${who}.${RUN}@example.test`;

const deps: Deps = {
  config: {
    allowedOrigins: [ORIGIN],
    turnstileSecret: "unused-fake",
    ipHashKey: IP_KEY,
  },
  // The fake answers for whichever widget the request names.
  verifyTurnstile: async (token) => ({
    success: true,
    hostname: "localhost",
    action: token,
  }),
  rpc: async (fn, args) => {
    const res = await service(`/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    const body = await res.json();
    return res.ok ? { data: body, error: null } : { data: null, error: body };
  },
  log: () => {},
  storage: makeStorage(fetch, API_URL, SERVICE_KEY),
  defer: () => {},
};

let ipCounter = 0;
async function call(body: unknown) {
  ipCounter += 1;
  const res = await handle(
    new Request("http://fn.local/admissions-public", {
      method: "POST",
      headers: {
        origin: ORIGIN,
        "content-type": "application/json",
        "x-forwarded-for": `198.51.100.${10 + (ipCounter % 200)}`,
      },
      body: JSON.stringify(body),
    }),
    deps,
  );
  return {
    status: res.status,
    body: (await res.json()) as Record<string, unknown>,
  };
}

const create = (to: string, state: unknown = STATE) =>
  call({
    action: "draft_create",
    turnstile_token: "draft",
    payload: { email: to, state, step: 3, consent: true },
  });
const save = (
  token: string,
  version: number,
  sendEmail = false,
  state: unknown = STATE,
) =>
  call({
    action: "draft_save",
    payload: {
      draft_token: token,
      state,
      step: 4,
      version,
      send_email: sendEmail,
    },
  });
const get = (token: string) =>
  call({ action: "draft_get", payload: { draft_token: token } });

const PDF = new TextEncoder().encode("%PDF-1.4\ndraft test\n");

async function session(): Promise<string> {
  const s = await call({ action: "upload_session", turnstile_token: "upload" });
  assert.equal(s.status, 200, JSON.stringify(s.body));
  return String(s.body.session_token);
}

async function upload(sessionToken: string) {
  const r = await call({
    action: "upload_url",
    payload: {
      session_token: sessionToken,
      document_type: "application_fee_proof",
      extension: "pdf",
      size: PDF.length,
    },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const path = String(r.body.path);
  const put = await fetch(
    `${API_URL}/storage/v1/object/upload/sign/${BUCKET}/${path}?token=${String(r.body.upload_token)}`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/pdf" },
      body: PDF,
    },
  );
  assert.ok(put.ok, `upload ${put.status}`);
  uploaded.push(path);
  return {
    document_type: "application_fee_proof",
    reservation_id: String(r.body.reservation_id),
    path,
  };
}

function payload(to: string, child: string, documents: unknown[]) {
  const grade = (name: string) =>
    psql(`select id from public.admissions_grades where name = '${name}'`);
  return {
    guardians: [
      {
        surname: "Draft",
        first_name: "Parent",
        relationship: "mother",
        religion: "Other",
        address: "3 Draft Street",
        town_city: "Tema",
        phone: "+233240000021",
        email: to,
      },
    ],
    student: {
      full_name: child,
      date_of_birth: "2017-03-04",
      gender: "female",
      nationality: "Ghanaian",
      address: "3 Draft Street",
      town_city: "Tema",
      current_school: "Test Primary",
      current_grade_id: grade("Grade 2"),
      grade_id: grade("Grade 3"),
      academic_year: "2026/2027",
      month_of_enrollment: "September",
    },
    campus_id: "00000000-0000-0000-0000-000000000001",
    emergency_contact: {
      name: "Aunt Draft",
      relationship: "Aunt",
      phone: "+233200000022",
    },
    health_info: { has_medical_conditions: false },
    documents,
    declaration_signature_name: "Parent Draft",
    declaration_agreed: true,
  };
}

const submit = (sessionToken: string, p: unknown, draftToken?: string) =>
  call({
    action: "application",
    turnstile_token: "application",
    session_token: sessionToken,
    payload: p,
    ...(draftToken ? { draft_token: draftToken } : {}),
  });

async function setApplications(open: boolean) {
  const res = await service("/rest/v1/admissions_settings?id=eq.1", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ public_applications_open: open }),
  });
  assert.ok(res.ok, `could not set applications: ${res.status}`);
}

before(async () => {
  await setApplications(true);
});

after(async () => {
  await setApplications(false);
  if (uploaded.length > 0) await deps.storage!.remove(uploaded);
});

test("create and open: the fixture state round-trips; the token comes back once and is stored only as its hash; one resume email is queued with no params", async () => {
  const c = await create(email("one"));
  assert.equal(c.status, 200, JSON.stringify(c.body));
  assert.deepEqual(Object.keys(c.body).sort(), [
    "draft_token",
    "email_masked",
    "expires_at",
    "version",
  ]);
  const token = String(c.body.draft_token);
  assert.match(token, /^[0-9a-f]{64}$/);
  assert.equal(c.body.email_masked, "d•••@e•••.test");

  const g = await get(token);
  assert.equal(g.status, 200, JSON.stringify(g.body));
  assert.deepEqual(g.body.state, STATE);
  assert.equal(g.body.step, 3);
  assert.equal(g.body.version, 1);
  assert.equal(g.body.email_masked, c.body.email_masked);
  assert.equal("email" in g.body, false);

  const draftId = psql(
    `select id from public.application_drafts where email = '${email("one")}'`,
  );
  assert.equal(
    psql(`select kind || '|' || params::text || '|' || cardinality(application_ids) || '|' || status
          from public.admissions_email_outbox where draft_id = '${draftId}'`),
    "draft_resume|{}|0|pending",
  );
  for (const table of [
    "application_drafts",
    "application_draft_links",
    "admissions_email_outbox",
  ]) {
    assert.equal(
      psql(
        `select count(*) from public.${table} x where row_to_json(x)::text like '%${token}%'`,
      ),
      "0",
      table,
    );
  }
});

test("save: the version must match and goes up; a refused state changes nothing; health is refused", async () => {
  const token = String((await create(email("two"))).body.draft_token);
  const changed = { ...STATE, campusId: "", scholarshipDetails: "Changed." };
  const ok = await save(token, 1, false, changed);
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.deepEqual(ok.body.version, 2);
  assert.equal(ok.body.email_queued, false);

  const stale = await save(token, 1, false, STATE);
  assert.equal(stale.status, 409);
  assert.equal(stale.body.code, "draft_version");

  for (const bad of [
    { ...STATE, health: { hasMedical: true } },
    { ...STATE, signature: "Ama" },
    { ...STATE, documents: [] },
  ]) {
    const r = await save(token, 2, false, bad);
    assert.equal(r.status, 400, JSON.stringify(bad));
    assert.equal(r.body.code, "draft_state");
  }
  const g = await get(token);
  assert.deepEqual(g.body.state, changed);
  assert.equal(g.body.version, 2);
  assert.equal(g.body.step, 4);
});

test("the resume email limit refuses with its own code and undoes the save; the same save without the email goes through", async () => {
  const to = email("three");
  const token = String((await create(to)).body.draft_token);
  assert.equal((await save(token, 1, true)).body.email_queued, true);
  assert.equal((await save(token, 2, true)).body.email_queued, true);
  const fourth = await save(token, 3, true, {
    ...STATE,
    scholarshipDetails: "Lost?",
  });
  assert.equal(fourth.status, 429);
  assert.equal(fourth.body.code, "draft_email_limit");
  assert.match(
    String(fourth.body.error),
    /^Too many emails have been sent to this address today/,
  );
  assert.equal((await get(token)).body.version, 3);
  const kept = await save(token, 3, false, {
    ...STATE,
    scholarshipDetails: "Kept.",
  });
  assert.equal(kept.status, 200);
  assert.equal(
    ((await get(token)).body.state as Record<string, unknown>)
      .scholarshipDetails,
    "Kept.",
  );
  assert.equal(
    psql(
      `select count(*) from public.admissions_email_outbox where recipient_email = '${to}'`,
    ),
    "3",
  );
});

test("a fourth live draft for one address gets the generic refusal, which never says drafts exist", async () => {
  const to = email("four");
  // Three drafts, made directly so the resume email limit plays no part.
  psql(`insert into public.application_drafts (email, data, consented_at, expires_at)
        select '${to}', '{}', now(), now() + interval '1 day' from generate_series(1, 3)`);
  const r = await create(to);
  assert.equal(r.status, 429);
  assert.deepEqual(r.body, {
    error: MESSAGES.draftRefused,
    code: "draft_limit",
  });
  assert.doesNotMatch(String(r.body.error), /saved|draft|already/i);
  assert.equal(
    psql(
      `select count(*) from public.application_drafts where email = '${to}'`,
    ),
    "3",
  );
});

test("submit through the draft: the reference, the draft retired and wiped, a repeat gives the same reference, a second window is refused", async () => {
  const to = email("five");
  const token = String((await create(to)).body.draft_token);
  const s1 = await session();
  const fee1 = await upload(s1);
  const p1 = payload(to, `Draft Child One ${RUN}`, [fee1]);
  const r1 = await submit(s1, p1, token);
  assert.equal(r1.status, 200, JSON.stringify(r1.body));
  assert.deepEqual(Object.keys(r1.body), ["reference"]);
  const ref = String(r1.body.reference);
  assert.equal(
    psql(`select (d.submitted_at is not null) || '|' || d.data::text || '|' || coalesce(d.email, '-') || '|' || a.application_reference
          from public.application_drafts d join public.applications a on a.id = d.submitted_application_id
          where d.id = (select draft_id from public.application_draft_links
                        where token_hash = encode(sha256(convert_to('${token}', 'UTF8')), 'hex'))`),
    `true|{}|-|${ref}`,
  );
  assert.equal(
    psql(
      `select count(*) from public.admissions_email_outbox where kind = 'draft_resume' and recipient_email = '${to}'`,
    ),
    "0",
  );

  const again = await submit(s1, p1, token);
  assert.equal(again.status, 200);
  assert.equal(again.body.reference, ref);

  const s2 = await session();
  const fee2 = await upload(s2);
  const r2 = await submit(
    s2,
    payload(to, `Draft Child Two ${RUN}`, [fee2]),
    token,
  );
  assert.equal(r2.status, 400);
  assert.equal(r2.body.code, "draft_submitted");
  assert.equal(
    psql(
      `select count(*) from public.students where full_name = 'Draft Child Two ${RUN}'`,
    ),
    "0",
  );

  const g = await get(token);
  assert.equal(g.status, 400);
  assert.equal(g.body.code, "draft_submitted");
});

test("delete erases the draft, its links and its queued emails, even while applications are closed", async () => {
  const to = email("six");
  const token = String((await create(to)).body.draft_token);
  await setApplications(false);
  try {
    assert.equal((await get(token)).status, 409);
    const d = await call({
      action: "draft_delete",
      payload: { draft_token: token },
    });
    assert.equal(d.status, 200);
    assert.deepEqual(d.body, { deleted: true });
  } finally {
    await setApplications(true);
  }
  assert.equal(
    psql(
      `select count(*) from public.application_drafts where email = '${to}'`,
    ),
    "0",
  );
  assert.equal(
    psql(
      `select count(*) from public.admissions_email_outbox where recipient_email = '${to}'`,
    ),
    "0",
  );
  const g = await get(token);
  assert.equal(g.status, 400);
  assert.equal(g.body.code, "draft_invalid");
});
