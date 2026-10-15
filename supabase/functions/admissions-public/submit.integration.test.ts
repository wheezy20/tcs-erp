// The admissions-public "application" action (slice 9a checkpoint 2)
// against the LOCAL database and the LOCAL Storage API, with a fake
// Turnstile verifier (no call to Cloudflare): real uploads, the real Range
// byte check, submit_application, a staff download link, and two
// submissions racing on one upload session (a double click). Run on a
// freshly reset local stack from the repo root, after the probe files:
//
//   ./scripts/seed-local-dev-staff.sh
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" ANON_KEY="$ANON_KEY" \
//        node --test supabase/functions/admissions-public/submit.integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It opens public
// applications, commits families, applications and files, and closes
// applications again at the end. It deletes the files it uploaded;
// `npx supabase db reset` clears the rows.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import { handle, type Deps } from "./handler.ts";
import { makeStorage } from "./storage.ts";

const API_URL = process.env.API_URL ?? "";
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY ?? "";
const ANON_KEY = process.env.ANON_KEY ?? "";
if (
  !/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(API_URL) ||
  SERVICE_KEY === "" ||
  ANON_KEY === ""
) {
  throw new Error(
    "submit.integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
  );
}

const ORIGIN = "http://localhost:8080";
const IP_KEY = "integration-ip-hash-key-0123456789abcdef";
const BUCKET = "admissions-documents";
const PROJECT = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)![1];

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
// Unique per run, so the test also passes on a database it has run on.
const RUN = Date.now().toString(36);
const email = (who: string) => `int.${who}.${RUN}@example.com`;
const child = (who: string) => `Integration ${who} ${RUN}`;

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
        "x-forwarded-for": `198.51.100.${150 + ipCounter}`,
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

const PDF = new TextEncoder().encode("%PDF-1.4\nsubmit test\n");
const HTML = new TextEncoder().encode(
  "<!doctype html><script>alert(1)</script>",
);

async function session(): Promise<string> {
  const s = await call({ action: "upload_session", turnstile_token: "upload" });
  assert.equal(s.status, 200, JSON.stringify(s.body));
  return String(s.body.session_token);
}

/** Reserves and uploads one file, as the browser does; the declared
 * content type is always one the bucket accepts. */
async function upload(
  sessionToken: string,
  type: string,
  bytes: Uint8Array,
  ext = "pdf",
) {
  const r = await call({
    action: "upload_url",
    payload: {
      session_token: sessionToken,
      document_type: type,
      extension: ext,
      size: bytes.length,
    },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const path = String(r.body.path);
  const put = await fetch(
    `${API_URL}/storage/v1/object/upload/sign/${BUCKET}/${path}?token=${String(r.body.upload_token)}`,
    {
      method: "PUT",
      headers: {
        "Content-Type": ext === "pdf" ? "application/pdf" : "image/png",
      },
      body: bytes,
    },
  );
  assert.ok(put.ok, `upload ${put.status}`);
  uploaded.push(path);
  return {
    document_type: type,
    reservation_id: String(r.body.reservation_id),
    path,
  };
}

function payload(email: string, child: string, documents: unknown[]) {
  const grade = (name: string) =>
    psql(`select id from public.admissions_grades where name = '${name}'`);
  return {
    guardians: [
      {
        surname: "Integration",
        first_name: "Parent",
        relationship: "father",
        religion: "Other",
        address: "2 Test Street",
        town_city: "Tema",
        phone: "+233240000001",
        email,
      },
    ],
    student: {
      full_name: child,
      date_of_birth: "2017-03-04",
      gender: "male",
      nationality: "Ghanaian",
      address: "2 Test Street",
      town_city: "Tema",
      current_school: "Test Primary",
      current_grade_id: grade("Grade 2"),
      grade_id: grade("Grade 3"),
      academic_year: "2026/2027",
      month_of_enrollment: "September",
    },
    campus_id: "00000000-0000-0000-0000-000000000001",
    emergency_contact: {
      name: "Aunt Test",
      relationship: "Aunt",
      phone: "+233200000002",
    },
    health_info: { has_medical_conditions: false },
    documents,
    declaration_signature_name: "Parent Integration",
    declaration_agreed: true,
  };
}

function submit(sessionToken: string, p: unknown) {
  return call({
    action: "application",
    turnstile_token: "application",
    session_token: sessionToken,
    payload: p,
  });
}

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

test("a real upload passes the byte check and comes back as the APP reference alone", async () => {
  const s = await session();
  const fee = await upload(s, "application_fee_proof", PDF);
  const r = await submit(s, payload(email("one"), child("One"), [fee]));
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.deepEqual(Object.keys(r.body), ["reference"]);
  assert.match(String(r.body.reference), /^APP-[0-9]{4}-[0-9]{4,}$/);
  assert.equal(
    psql(
      `select d.status || ':' || d.storage_path from public.application_documents d
       join public.applications a on a.id = d.application_id
       where a.application_reference = '${String(r.body.reference)}'`,
    ),
    `pending_review:${fee.path}`,
  );
  assert.equal(
    psql(
      `select declaration_ip_address is null from public.applications
       where application_reference = '${String(r.body.reference)}'`,
    ),
    "t",
  );
});

test("HTML bytes uploaded as a PDF are refused, and the session can still be used for a real file", async () => {
  const s = await session();
  const bad = await upload(s, "application_fee_proof", HTML);
  const p = payload(email("two"), child("Two"), [bad]);
  const r = await submit(s, p);
  assert.equal(r.status, 400);
  assert.equal(r.body.field, "documents");
  assert.equal(
    psql(
      `select count(*) from public.students where full_name = '${child("Two")}'`,
    ),
    "0",
  );
  // A PNG under a .pdf name is refused too: the kind must match the
  // extension, not just be one of the three.
  const s2 = await session();
  const png = await upload(
    s2,
    "application_fee_proof",
    new Uint8Array([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0,
    ]),
  );
  assert.equal(
    (await submit(s2, payload(email("two"), child("Two"), [png]))).status,
    400,
  );

  const good = await upload(s, "application_fee_proof", PDF);
  const ok = await submit(s, payload(email("two"), child("Two"), [good]));
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
});

test("a double click: two submits on one session make one application and both get its reference", async () => {
  const s = await session();
  const fee = await upload(s, "application_fee_proof", PDF);
  const p = payload(email("race"), child("Race"), [fee]);
  const [a, b] = await Promise.all([submit(s, p), submit(s, p)]);
  assert.equal(a.status, 200, JSON.stringify(a.body));
  assert.equal(b.status, 200, JSON.stringify(b.body));
  assert.equal(a.body.reference, b.body.reference);
  assert.equal(
    psql(
      `select count(*) from public.applications a join public.students st on st.id = a.student_id
       where st.full_name = '${child("Race")}'`,
    ),
    "1",
  );
  assert.equal(
    psql(`select count(*) from public.families f join public.guardians g on g.family_id = f.id
          where g.email = '${email("race")}'`),
    "1",
  );
  assert.equal(
    psql(
      `select count(*) from public.application_documents where storage_path = '${fee.path}'`,
    ),
    "1",
  );
  // One per-email hit: the repeat counted nothing.
  assert.equal(
    psql(
      `select coalesce(sum(count), 0) from public.public_rate_limits where bucket = 'application_email'
       and key_hash = encode(sha256(convert_to('${email("race")}', 'UTF8')), 'hex')`,
    ),
    "1",
  );
});

test("staff download links force a download (attachment), never inline", async () => {
  const s = await session();
  const fee = await upload(s, "application_fee_proof", PDF);
  const r = await submit(s, payload(email("dl"), child("Download"), [fee]));
  assert.equal(r.status, 200);

  const login = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({
      email: "dev-manager@tcs.test",
      password: "local-dev-2026",
    }),
  });
  assert.ok(login.ok, `manager sign in ${login.status}`);
  const jwt = String(
    ((await login.json()) as { access_token: string }).access_token,
  );

  const sign = await fetch(
    `${API_URL}/storage/v1/object/sign/${BUCKET}/${fee.path}`,
    {
      method: "POST",
      headers: {
        apikey: ANON_KEY,
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ expiresIn: 300 }),
    },
  );
  assert.ok(sign.ok, `sign ${sign.status}`);
  const signedUrl = String(
    ((await sign.json()) as { signedURL: string }).signedURL,
  );
  // What supabase-js's createSignedUrl(path, 300, { download: name }) does.
  const name = `${String(r.body.reference)}-application_fee_proof.pdf`;
  const res = await fetch(
    `${API_URL}/storage/v1${signedUrl}&download=${encodeURIComponent(name)}`,
  );
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-disposition") ?? "", /^attachment/);
  await res.body?.cancel();
});

/** Runs SQL in its own database session; resolves with its output. */
function psqlAsync(sql: string): Promise<{ code: number; out: string }> {
  return new Promise((resolve) => {
    const p = spawn("docker", [
      "exec",
      "-i",
      `supabase_db_${PROJECT}`,
      "psql",
      "-U",
      "postgres",
      "-X",
      "-At",
      "-v",
      "ON_ERROR_STOP=1",
    ]);
    let out = "";
    p.stdout.on("data", (d) => (out += String(d)));
    p.stderr.on("data", (d) => (out += String(d)));
    p.on("close", (code) => resolve({ code: code ?? 1, out: out.trim() }));
    p.stdin.end(sql);
  });
}

test("two database sessions submitting one upload session: the second waits, then gets the same reference", async () => {
  const s = await session();
  const fee = await upload(s, "application_fee_proof", PDF);
  const p = JSON.stringify(payload(email("lock"), child("Lock"), [fee]));
  const sniffed = JSON.stringify([
    { reservation_id: fee.reservation_id, path: fee.path, kind: "pdf" },
  ]);
  const call = `set role service_role; set request.jwt.claims = '{"role":"service_role"}';
    select public.submit_application($j$${p}$j$::jsonb, '${s}', $j$${sniffed}$j$::jsonb);`;
  // A submits and holds its transaction open for 3 seconds; B starts while
  // A still holds it. With the session row lock, B waits for A's commit
  // and answers as a repeat. Without it, B gets past the session check,
  // then finds the reservation used and is refused.
  const a = psqlAsync(`begin; ${call} select pg_sleep(3); commit;`);
  await new Promise((r) => setTimeout(r, 1000));
  const b = psqlAsync(call);
  const [ra, rb] = await Promise.all([a, b]);
  assert.equal(ra.code, 0, ra.out);
  assert.equal(rb.code, 0, rb.out);
  const refA = ra.out.split("\n").find((l) => /^APP-/.test(l));
  const refB = rb.out.split("\n").find((l) => /^APP-/.test(l));
  assert.ok(refA, ra.out);
  assert.equal(refB, refA);
  assert.equal(
    psql(
      `select count(*) from public.applications a join public.students st on st.id = a.student_id
       where st.full_name = '${child("Lock")}'`,
    ),
    "1",
  );
});
