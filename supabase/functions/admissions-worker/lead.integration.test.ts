// The PDF gate end to end (slice 13) against the LOCAL database, the local
// Storage API and a LOCAL fake provider (a small HTTP server on 127.0.0.1
// that records requests): no email is ever sent and Resend is never
// called. A lead captured through admissions-public's handler (with a fake
// Turnstile answer) is mailed by the worker with an invented PDF from the
// local admissions-attachments bucket; a missing file sends no PDF and
// retries with class config; a closed switch refuses. Run on a freshly
// reset local stack from the repo root, after the probe files:
//
//   ./scripts/seed-local-dev-staff.sh
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
//        node --test supabase/functions/admissions-worker/lead.integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It commits
// leads and outbox rows and leaves the lead switch closed;
// `npx supabase db reset` clears them.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";

import { handle as handlePublic, type Config } from "../admissions-public/handler.ts";
import {
  ATTACHMENT_BUCKET,
  PDF_GATE_FILENAME,
  PDF_GATE_PATH,
  makePdfGateReader,
} from "./attachment.ts";
import { loadMailConfig, makeResendSender, runMailJob, type MailConfig } from "./handler.ts";

const API_URL = process.env.API_URL ?? "";
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY ?? "";
if (!/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(API_URL) || SERVICE_KEY === "") {
  throw new Error(
    "lead.integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
  );
}
const PROJECT = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)![1];
const RUN = Date.now().toString(36);
const SITE = "https://www.school.example.test";
const INQUIRY_URL = "https://admissions.school.example.test/inquiry";
const STAFF = `staff.${RUN}@example.test`;
const PDF = new TextEncoder().encode(`%PDF-1.7\ninvented fees document ${RUN}\n%%EOF\n`);

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
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      sql,
    ],
    { encoding: "utf8" },
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

const objectUrl = `${API_URL}/storage/v1/object/${ATTACHMENT_BUCKET}/${PDF_GATE_PATH}`;
const storageHeaders = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

async function uploadPdf() {
  const res = await fetch(objectUrl, {
    method: "POST",
    headers: { ...storageHeaders, "Content-Type": "application/pdf", "x-upsert": "true" },
    body: PDF,
  });
  assert.ok(res.ok, `upload answered ${res.status}`);
}

async function removePdf() {
  const res = await fetch(`${API_URL}/storage/v1/object/${ATTACHMENT_BUCKET}`, {
    method: "DELETE",
    headers: { ...storageHeaders, "Content-Type": "application/json" },
    body: JSON.stringify({ prefixes: [PDF_GATE_PATH] }),
  });
  assert.ok(res.ok, `remove answered ${res.status}`);
}

// ---------------------------------------------------------------- fake provider

const seen: Record<string, unknown>[] = [];
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
  psql("update public.admissions_settings set public_leads_open = true where id = 1");
});
after(async () => {
  psql("update public.admissions_settings set public_leads_open = false where id = 1");
  await removePdf();
  server.close();
});

function mail(): MailConfig {
  const config = loadMailConfig(
    (n) =>
      ({
        MAIL_MODE: "test",
        RESEND_API_KEY: "fake-integration-key",
        RESEND_API_BASE: providerBase,
        MAIL_FROM: "TCS Admissions <no-reply@mail.example.test>",
        MAIL_REPLY_TO: "admissions@example.test",
        ADMISSIONS_STAFF_EMAIL: STAFF,
        ERP_BASE_URL: "http://localhost:8080",
        PDF_GATE_INQUIRY_URL: INQUIRY_URL,
        MAIL_DAILY_CEILING: "1000",
        SUPABASE_URL: API_URL,
      })[n],
  );
  assert.ok(config?.pdfGateInquiryUrl, "test mail config refused");
  return config;
}

const CONFIG: Config = {
  allowedOrigins: ["http://localhost:8080"],
  leadOrigins: [SITE],
  turnstileSecret: "unused-fake-secret",
  ipHashKey: "integration-ip-hash-key-0123456789abcdef",
};

async function capture(email: string) {
  return handlePublic(
    new Request("http://fn.local/admissions-public", {
      method: "POST",
      headers: {
        origin: SITE,
        "content-type": "application/json",
        "x-forwarded-for": `198.51.100.${seen.length + 1}`,
      },
      body: JSON.stringify({
        action: "pdf_gate",
        turnstile_token: "fake",
        payload: { name: "Integration Lead", email, consent_to_marketing: true },
      }),
    }),
    {
      config: CONFIG,
      verifyTurnstile: async () => ({
        success: true,
        hostname: "www.school.example.test",
        action: "pdf_gate",
      }),
      rpc,
      log: () => {},
    },
  );
}

async function sendAll() {
  return runMailJob({
    rpc,
    mail: mail(),
    send: makeResendSender(fetch),
    sleep: async () => {},
    log: () => {},
    readPdfGate: makePdfGateReader(fetch, API_URL, SERVICE_KEY),
  });
}

test("a lead gets the PDF attached with the enquiry link; staff get an alert linking to the lead, with no contact details", async () => {
  await uploadPdf();
  const to = `lead.one.${RUN}@example.test`;
  const res = await capture(to);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  const leadId = psql(`select id from public.admissions_leads where email = '${to}'`);
  assert.match(leadId, /^[0-9a-f-]{36}$/);

  seen.length = 0;
  await sendAll();
  const pdfMail = seen.find((b) => (b.to as string[])[0] === to);
  const alert = seen.find((b) => (b.to as string[])[0] === STAFF);
  assert.ok(pdfMail && alert, "both emails sent");
  assert.deepEqual(pdfMail.attachments, [
    { filename: PDF_GATE_FILENAME, content: Buffer.from(PDF).toString("base64") },
  ]);
  assert.ok(String(pdfMail.text).includes(INQUIRY_URL));
  assert.equal(alert.attachments, undefined);
  assert.ok(String(alert.text).includes(`/admissions/leads?lead=${leadId}`));
  assert.doesNotMatch(`${alert.subject}\n${alert.text}`, new RegExp(`Integration Lead|${to}`));
  assert.equal(
    psql(
      `select string_agg(kind || ':' || status, ',' order by kind) from public.admissions_email_outbox where lead_id = '${leadId}'`,
    ),
    "lead_staff:sent,pdf_gate:sent",
  );
});

test("no file: the staff alert goes, the PDF email waits with class config and nothing is sent to the lead", async () => {
  await removePdf();
  const to = `lead.two.${RUN}@example.test`;
  assert.equal((await capture(to)).status, 200);
  seen.length = 0;
  await sendAll();
  assert.equal(seen.filter((b) => (b.to as string[])[0] === to).length, 0);
  assert.equal(seen.filter((b) => (b.to as string[])[0] === STAFF).length, 1);
  assert.equal(
    psql(
      `select status || ':' || last_error_class from public.admissions_email_outbox where kind = 'pdf_gate' and recipient_email = '${to}'`,
    ),
    "pending:config",
  );
});

test("lead capture closed: 409 with code closed and no lead", async () => {
  psql("update public.admissions_settings set public_leads_open = false where id = 1");
  const to = `lead.three.${RUN}@example.test`;
  const res = await capture(to);
  assert.equal(res.status, 409);
  assert.equal(((await res.json()) as { code?: string }).code, "closed");
  assert.equal(psql(`select count(*) from public.admissions_leads where email = '${to}'`), "0");
});
