// The admissions-public upload actions (slice 9a checkpoint 1) against the
// LOCAL database and the LOCAL Storage API, with a fake Turnstile verifier
// (no call to Cloudflare). Run on a freshly reset local stack from the repo
// root:
//
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" ANON_KEY="$ANON_KEY" \
//        node --test supabase/functions/admissions-public/upload.integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It opens public
// applications, writes sessions, reservations, rate limit counters and
// small files under uploads/, and closes applications again at the end. It
// deletes the files it uploaded; `npx supabase db reset` clears the rows.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import {
  handle,
  sweepExpiredUploads,
  type Deps,
  type TurnstileOutcome,
} from "./handler.ts";
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
    "upload.integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
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

const turnstile: TurnstileOutcome = {
  success: true,
  hostname: "localhost",
  action: "upload",
};

const deps: Deps = {
  config: {
    allowedOrigins: [ORIGIN],
    turnstileSecret: "unused-fake",
    ipHashKey: IP_KEY,
  },
  verifyTurnstile: async () => turnstile,
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
  // The same Storage code index.ts uses.
  storage: makeStorage(fetch, API_URL, SERVICE_KEY),
  defer: () => {},
};

let ipCounter = 0;
function freshIp(): string {
  ipCounter += 1;
  return `198.51.100.${100 + ipCounter}`;
}

async function call(body: unknown, ip = freshIp()) {
  const res = await handle(
    new Request("http://fn.local/admissions-public", {
      method: "POST",
      headers: {
        origin: ORIGIN,
        "content-type": "application/json",
        "x-forwarded-for": ip,
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

async function openSession(ip?: string) {
  return call({ action: "upload_session", turnstile_token: "fake" }, ip);
}

async function reserve(
  session: string,
  document_type = "application_fee_proof",
  extension = "pdf",
) {
  return call({
    action: "upload_url",
    payload: { session_token: session, document_type, extension, size: 20 },
  });
}

/** PUTs bytes with the upload token, as the browser's uploadToSignedUrl does. */
async function put(path: string, token: string, bytes: Uint8Array) {
  const res = await fetch(
    `${API_URL}/storage/v1/object/upload/sign/${BUCKET}/${path}?token=${token}`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/pdf" },
      body: bytes,
    },
  );
  if (res.ok) uploaded.push(path);
  return res;
}

const PDF = new TextEncoder().encode("%PDF-1.4\nchecksum test\n");

async function setApplications(open: boolean) {
  const res = await service("/rest/v1/admissions_settings?id=eq.1", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ public_applications_open: open }),
  });
  assert.ok(res.ok, `could not set applications: ${res.status}`);
}

before(async () => {
  await setApplications(false);
});

after(async () => {
  await setApplications(false);
  if (uploaded.length > 0) await deps.storage!.remove(uploaded);
});

test("closed applications refuse a session with the closed message and store nothing", async () => {
  const before = psql(
    "select count(*) from public.application_upload_sessions",
  );
  const r = await openSession();
  assert.equal(r.status, 409);
  assert.match(String(r.body.error), /applications are closed/);
  assert.equal(
    psql("select count(*) from public.application_upload_sessions"),
    before,
  );
});

test("open: session, reservation, a real upload; only the hash is stored", async () => {
  await setApplications(true);
  const s = await openSession();
  assert.equal(s.status, 200);
  const token = String(s.body.session_token);
  assert.match(token, /^[0-9a-f]{64}$/);
  assert.equal(
    psql(
      `select count(*) from public.application_upload_sessions where token_hash = '${token}'`,
    ),
    "0",
  );

  const r = await reserve(token);
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys(r.body).sort(), [
    "expires_at",
    "path",
    "reservation_id",
    "upload_token",
  ]);
  const path = String(r.body.path);
  assert.equal(
    path,
    `uploads/${String(r.body.reservation_id)}/application_fee_proof.pdf`,
  );

  const first = await put(path, String(r.body.upload_token), PDF);
  assert.equal(first.status, 200);
  assert.equal(
    psql(
      `select count(*) from storage.objects where bucket_id = '${BUCKET}' and name = '${path}'`,
    ),
    "1",
  );
  // Overwrite is off, even when the uploader asks for it.
  const again = await fetch(
    `${API_URL}/storage/v1/object/upload/sign/${BUCKET}/${path}?token=${String(r.body.upload_token)}`,
    {
      method: "PUT",
      headers: { "Content-Type": "application/pdf", "x-upsert": "true" },
      body: new TextEncoder().encode("%PDF-1.4\nreplaced\n"),
    },
  );
  assert.ok(!again.ok);
  // The token is bound to its path.
  const elsewhere = await put(
    "uploads/00000000-0000-4000-8000-000000000000/application_fee_proof.pdf",
    String(r.body.upload_token),
    PDF,
  );
  assert.ok(!elsewhere.ok);

  // A Range read returns just the leading bytes (what checkpoint 2's byte
  // check will use).
  const head = await service(
    `/storage/v1/object/authenticated/${BUCKET}/${path}`,
    { headers: { Range: "bytes=0-15" } },
  );
  assert.equal(head.status, 206);
  const bytes = new Uint8Array(await head.arrayBuffer());
  assert.equal(bytes.length, 16);
  assert.equal(new TextDecoder().decode(bytes.slice(0, 5)), "%PDF-");
});

test("anon cannot write to the bucket without a signed upload", async () => {
  const res = await fetch(
    `${API_URL}/storage/v1/object/${BUCKET}/uploads/anon-test/application_fee_proof.pdf`,
    {
      method: "POST",
      headers: {
        apikey: ANON_KEY,
        Authorization: `Bearer ${ANON_KEY}`,
        "Content-Type": "application/pdf",
      },
      body: PDF,
    },
  );
  assert.ok(!res.ok);
});

test("a session holds at most 8 reservations; an unknown or expired session is refused", async () => {
  await setApplications(true);
  const s = await openSession();
  const token = String(s.body.session_token);
  for (let i = 0; i < 8; i += 1)
    assert.equal((await reserve(token)).status, 200, `file ${i + 1}`);
  const ninth = await reserve(token);
  assert.equal(ninth.status, 400);
  assert.match(String(ninth.body.error), /file limit/);

  assert.equal((await reserve("b".repeat(64))).status, 400);

  const t2 = String((await openSession()).body.session_token);
  psql(
    `update public.application_upload_sessions set created_at = now() - interval '7 hours', expires_at = now() - interval '1 hour'
     where token_hash = encode(sha256(convert_to('${t2}', 'UTF8')), 'hex')`,
  );
  const expired = await reserve(t2);
  assert.equal(expired.status, 400);
  assert.match(String(expired.body.error), /expired/);
});

test("the 11th session from one IP in an hour is refused before Turnstile", async () => {
  await setApplications(true);
  const ip = "192.0.2.88";
  for (let i = 0; i < 10; i += 1)
    assert.equal((await openSession(ip)).status, 200, `session ${i + 1}`);
  let verifierCalled = false;
  const saved = deps.verifyTurnstile;
  deps.verifyTurnstile = async () => {
    verifierCalled = true;
    return turnstile;
  };
  const r = await openSession(ip);
  deps.verifyTurnstile = saved;
  assert.equal(r.status, 429);
  assert.equal(verifierCalled, false);
});

test("the global session cap and the open-reservation cap refuse with the office message", async () => {
  await setApplications(true);
  psql(
    `insert into public.public_rate_limits (bucket, key_hash, window_start, count)
     values ('upload_global', 'global', date_bin(interval '1 hour', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00'), 100)
     on conflict (bucket, key_hash, window_start) do update set count = 100`,
  );
  const g = await openSession();
  assert.equal(g.status, 429);
  assert.match(String(g.body.error), /call the school office/);
  psql("delete from public.public_rate_limits where bucket = 'upload_global'");

  const s = await openSession();
  const token = String(s.body.session_token);
  const open = Number(
    psql(
      "select count(*) from public.application_upload_reservations where consumed_at is null and cleaned_at is null",
    ),
  );
  psql(
    `insert into public.application_upload_sessions (id, token_hash, expires_at)
     values ('99999999-0000-4000-8000-000000000001', repeat('9', 64), now() + interval '1 hour');
     insert into public.application_upload_reservations (session_id, document_type, extension, expires_at)
     select '99999999-0000-4000-8000-000000000001', 'previous_report', 'pdf', now() + interval '1 hour'
     from generate_series(1, ${400 - open})`,
  );
  const r = await reserve(token);
  assert.equal(r.status, 429);
  assert.equal((await openSession()).status, 429);
  psql(
    `delete from public.application_upload_reservations where session_id = '99999999-0000-4000-8000-000000000001';
     delete from public.application_upload_sessions where id = '99999999-0000-4000-8000-000000000001'`,
  );
  assert.equal((await reserve(token)).status, 200);
});

test("the sweep deletes an expired, unused upload's file and marks it cleaned", async () => {
  await setApplications(true);
  const s = await openSession();
  const r = await reserve(String(s.body.session_token), "previous_report");
  const path = String(r.body.path);
  assert.equal((await put(path, String(r.body.upload_token), PDF)).status, 200);
  // Not yet expired: the sweep leaves it alone.
  await sweepExpiredUploads(deps);
  assert.equal(
    psql(`select count(*) from storage.objects where name = '${path}'`),
    "1",
  );

  psql(
    `update public.application_upload_reservations set created_at = now() - interval '3 hours', expires_at = now() - interval '31 minutes'
     where id = '${String(r.body.reservation_id)}'`,
  );
  await sweepExpiredUploads(deps);
  assert.equal(
    psql(`select count(*) from storage.objects where name = '${path}'`),
    "0",
  );
  assert.equal(
    psql(
      `select cleaned_at is not null from public.application_upload_reservations where id = '${String(r.body.reservation_id)}'`,
    ),
    "t",
  );
});
