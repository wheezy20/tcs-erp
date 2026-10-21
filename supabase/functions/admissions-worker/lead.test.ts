// Unit tests for the worker's lead emails (slice 13) with a fake provider,
// a fake PDF reader and fake RPCs: no network, no database, no email. Run
// from the repo root with Node 22:
//
//   node --test supabase/functions/admissions-worker/lead.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  ATTACHMENT_BUCKET,
  MAX_ATTACHMENT_BYTES,
  PDF_GATE_FILENAME,
  PDF_GATE_PATH,
  makePdfGateReader,
  pdfAttachment,
} from "./attachment.ts";
import {
  ATTACHMENT_SEND_TIMEOUT_MS,
  RUN_BUDGET_MS,
  SEND_TIMEOUT_MS,
  sendTimeoutMs,
  loadMailConfig,
  makeResendSender,
  runMailJob,
  type Deps,
  type MailConfig,
  type OutgoingEmail,
  type RpcResult,
} from "./handler.ts";

const INQUIRY_URL = "https://admissions.school.example.test/inquiry";
const MAIL: MailConfig = {
  mode: "test",
  apiBase: "http://127.0.0.1:9",
  apiKey: "fake-key-for-tests",
  from: "TCS Admissions <no-reply@mail.example.test>",
  replyTo: "admissions@example.test",
  staffEmail: "staff.alerts@example.test",
  erpBaseUrl: "http://localhost:8080",
  dailyCeiling: 100,
  applyBaseUrl: null,
  pdfGateInquiryUrl: INQUIRY_URL,
};
const LEAD_ID = "13000000-0000-4000-8000-000000000a01";
const PDF = new TextEncoder().encode("%PDF-1.7\nfake fees document\n%%EOF\n");
const ALERT = {
  lead_id: LEAD_ID,
  grade_interest: "KG 1",
  consent_to_marketing: false,
  source: "pdf_gate_admissions_overview",
};

const row = (id: string, kind: string, to: string | null, params: unknown = {}) => ({
  id,
  kind,
  recipient_email: to,
  params,
  claim_token: `token-${id}`,
  attempts: 1,
});

function harness(
  opts: {
    rows?: unknown[];
    mail?: MailConfig;
    read?: (() => Promise<Uint8Array>) | null;
    alert?: RpcResult;
  } = {},
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const sent: OutgoingEmail[] = [];
  const logs: string[] = [];
  let reads = 0;
  const deps: Deps = {
    rpc: async (fn, args) => {
      calls.push({ fn, args });
      if (fn === "claim_admissions_emails") return { data: opts.rows ?? [], error: null };
      if (fn === "mark_admissions_email_result") return { data: true, error: null };
      if (fn === "get_lead_alert") return opts.alert ?? { data: ALERT, error: null };
      return { data: null, error: { message: "unexpected" } };
    },
    mail: opts.mail ?? MAIL,
    send: async (email) => {
      sent.push(email);
      return { kind: "sent", status: 200, messageId: `msg-${sent.length}` };
    },
    sleep: async () => {},
    log: (o) => logs.push(o),
    ...(opts.read === null
      ? {}
      : {
          readPdfGate: async () => {
            reads += 1;
            return (opts.read ?? (async () => PDF))();
          },
        }),
  };
  const marks = () =>
    calls
      .filter((c) => c.fn === "mark_admissions_email_result")
      .map((c) => `${c.args.p_id}:${c.args.p_outcome}:${c.args.p_error_class}`);
  return { deps, calls, sent, logs, marks, reads: () => reads };
}

// ---------------------------------------------------------------- config

test("PDF_GATE_INQUIRY_URL must be https with exactly the path /inquiry; anything else leaves PDF emails waiting", () => {
  const env = (v: string | undefined) => (n: string) =>
    ({
      MAIL_MODE: "live",
      RESEND_API_KEY: "re_live_key",
      MAIL_FROM: "TCS Admissions <no-reply@mail.example.test>",
      MAIL_REPLY_TO: "admissions@example.test",
      ADMISSIONS_STAFF_EMAIL: "staff@example.test",
      ERP_BASE_URL: "https://erp.example.test",
      MAIL_DAILY_CEILING: "60",
      PDF_GATE_INQUIRY_URL: v,
    })[n];
  assert.equal(loadMailConfig(env(` ${INQUIRY_URL} `))?.pdfGateInquiryUrl, INQUIRY_URL);
  for (const bad of [
    undefined,
    "",
    "http://admissions.school.example.test/inquiry",
    `${INQUIRY_URL}/`,
    `${INQUIRY_URL}?x=1`,
    "https://admissions.school.example.test/apply",
    "https://localhost/inquiry",
    "https://admissions.school.example.test:8443/inquiry",
    "https://10.0.0.5/inquiry",
    "https://192.168.1.20/inquiry",
  ]) {
    const c = loadMailConfig(env(bad));
    assert.ok(c, String(bad));
    assert.equal(c.pdfGateInquiryUrl, null, String(bad));
  }
});

// ---------------------------------------------------------------- pdf_gate

test("a PDF email goes to the lead with the PDF attached and the enquiry link; the file is read once per run", async () => {
  const h = harness({
    rows: [row("p1", "pdf_gate", "a@example.test"), row("p2", "pdf_gate", "b@example.test")],
  });
  const r = await runMailJob(h.deps);
  assert.deepEqual(r, { sent: 2, claimed: 2 });
  assert.equal(h.reads(), 1);
  assert.deepEqual(
    h.sent.map((e) => e.to),
    ["a@example.test", "b@example.test"],
  );
  for (const e of h.sent) {
    assert.equal(e.idempotencyKey, `outbox-${e === h.sent[0] ? "p1" : "p2"}`);
    assert.deepEqual(e.attachments, [
      { filename: PDF_GATE_FILENAME, content: Buffer.from(PDF).toString("base64") },
    ]);
    assert.ok(e.text.includes(INQUIRY_URL));
  }
  assert.deepEqual(h.marks(), ["p1:sent:null", "p2:sent:null"]);
});

test("a missing, unreadable or non-PDF file sends nothing and retries with class config", async () => {
  for (const read of [
    null,
    async () => {
      throw new Error("read answered 404");
    },
    async () => new TextEncoder().encode("<html>not a pdf</html>"),
    async () => new Uint8Array(0),
  ]) {
    const h = harness({ rows: [row("p1", "pdf_gate", "a@example.test")], read });
    const r = await runMailJob(h.deps);
    assert.deepEqual(r, { sent: 0, claimed: 1 });
    assert.equal(h.sent.length, 0);
    assert.deepEqual(h.marks(), ["p1:retry:config"]);
    assert.ok(h.logs.includes("mail_pdf_gate_file_missing"));
  }
});

test("no enquiry link setting: PDF emails retry with class config and the file isn't read", async () => {
  const h = harness({
    rows: [row("p1", "pdf_gate", "a@example.test")],
    mail: { ...MAIL, pdfGateInquiryUrl: null },
  });
  await runMailJob(h.deps);
  assert.equal(h.sent.length, 0);
  assert.equal(h.reads(), 0);
  assert.deepEqual(h.marks(), ["p1:retry:config"]);
});

test("only a PDF email carries the attachment; other kinds in the same batch don't", async () => {
  const h = harness({
    rows: [
      row("i1", "inquiry_parent", "p@example.test", {
        references: [{ reference: "INQ-2026-0001", grade: "Grade 3", academic_year: "2026/2027" }],
      }),
      row("p1", "pdf_gate", "a@example.test"),
      row("s1", "lead_staff", null),
    ],
  });
  await runMailJob(h.deps);
  assert.deepEqual(
    h.sent.map((e) => [e.kind, e.attachments === undefined ? 0 : e.attachments.length]),
    [
      ["inquiry_parent", 0],
      ["pdf_gate", 1],
      ["lead_staff", 0],
    ],
  );
});

// ---------------------------------------------------------------- lead_staff

test("a lead alert goes to the staff address with what get_lead_alert gave, never a name, email or phone", async () => {
  const h = harness({
    rows: [row("s1", "lead_staff", null)],
    // Even if the database ever returned more, the alert prints only its own fields.
    alert: {
      data: { ...ALERT, name: "Ama Mensah", email: "ama@example.test", phone: "+233241234567" },
      error: null,
    },
  });
  await runMailJob(h.deps);
  const call = h.calls.find((c) => c.fn === "get_lead_alert");
  assert.deepEqual(call?.args, { p_outbox_id: "s1", p_claim_token: "token-s1" });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].to, MAIL.staffEmail);
  const all = `${h.sent[0].subject}\n${h.sent[0].text}`;
  assert.doesNotMatch(all, /Ama|ama@|241234567/);
  assert.match(all, new RegExp(`/admissions/leads\\?lead=${LEAD_ID}`));
  assert.deepEqual(h.marks(), ["s1:sent:null"]);
});

test("a lost claim records nothing; an error retries", async () => {
  let h = harness({ rows: [row("s1", "lead_staff", null)], alert: { data: null, error: null } });
  await runMailJob(h.deps);
  assert.equal(h.sent.length, 0);
  assert.deepEqual(h.marks(), []);

  h = harness({
    rows: [row("s1", "lead_staff", null)],
    alert: { data: null, error: { code: "XX000" } },
  });
  await runMailJob(h.deps);
  assert.equal(h.sent.length, 0);
  assert.deepEqual(h.marks(), ["s1:retry:other"]);
});

test("no log line carries an address", async () => {
  const h = harness({
    rows: [row("p1", "pdf_gate", "secret.lead@example.test"), row("s1", "lead_staff", null)],
  });
  await runMailJob(h.deps);
  assert.doesNotMatch(JSON.stringify(h.logs), /@/);
});

// ---------------------------------------------------------------- the pieces

test("pdfAttachment needs %PDF- at the start and at most 10 MB", () => {
  assert.equal(pdfAttachment(PDF).filename, PDF_GATE_FILENAME);
  assert.throws(() => pdfAttachment(new TextEncoder().encode(" %PDF-1.7")));
  const big = new Uint8Array(MAX_ATTACHMENT_BYTES + 1);
  big.set(PDF);
  assert.throws(() => pdfAttachment(big));
});

test("the reader asks Storage for the fixed path only, and refuses an oversize body", async () => {
  const urls: string[] = [];
  const read = makePdfGateReader(
    (async (url: string) => {
      urls.push(url);
      return new Response(PDF, { status: 200 });
    }) as unknown as typeof fetch,
    "http://127.0.0.1:54321",
    "service-key",
  );
  assert.deepEqual(await read(), PDF);
  assert.deepEqual(urls, [
    `http://127.0.0.1:54321/storage/v1/object/authenticated/${ATTACHMENT_BUCKET}/${PDF_GATE_PATH}`,
  ]);
  const tooBig = makePdfGateReader(
    (async () =>
      new Response(new Uint8Array(MAX_ATTACHMENT_BYTES + 10), {
        status: 200,
      })) as unknown as typeof fetch,
    "http://127.0.0.1:54321",
    "service-key",
  );
  await assert.rejects(tooBig());
  const missing = makePdfGateReader(
    (async () => new Response("{}", { status: 400 })) as unknown as typeof fetch,
    "http://127.0.0.1:54321",
    "service-key",
  );
  await assert.rejects(missing());
});

test("the sender puts attachments in the request only when there are some", async () => {
  const bodies: Record<string, unknown>[] = [];
  const send = makeResendSender((async (_url: string, init: RequestInit) => {
    bodies.push(JSON.parse(String(init.body)));
    return new Response(JSON.stringify({ id: "m1" }), { status: 200 });
  }) as unknown as typeof fetch);
  const base: OutgoingEmail = {
    idempotencyKey: "outbox-x",
    from: MAIL.from,
    to: "a@example.test",
    replyTo: MAIL.replyTo,
    subject: "s",
    text: "t",
    kind: "pdf_gate",
  };
  await send(base, MAIL);
  await send({ ...base, attachments: [{ filename: PDF_GATE_FILENAME, content: "QQ==" }] }, MAIL);
  assert.equal("attachments" in bodies[0], false);
  assert.deepEqual(bodies[1].attachments, [{ filename: PDF_GATE_FILENAME, content: "QQ==" }]);
  assert.equal(ATTACHMENT_SEND_TIMEOUT_MS, 30_000);
});

// ---------------------------------------------------------------- fix round 1

test("a run stops starting sends once its time budget is spent and puts the rest back", async () => {
  let t = 0;
  const h = harness({
    rows: [
      row("p1", "pdf_gate", "a@example.test"),
      row("p2", "pdf_gate", "b@example.test"),
      row("p3", "pdf_gate", "c@example.test"),
    ],
  });
  h.deps.now = () => t;
  const send = h.deps.send;
  h.deps.send = async (email, config) => {
    t += RUN_BUDGET_MS / 2 + 1;
    return send(email, config);
  };
  const r = await runMailJob(h.deps);
  assert.equal(r.sent, 2);
  assert.deepEqual(h.marks(), ["p1:sent:null", "p2:sent:null", "p3:retry:timeout"]);
  assert.ok(h.logs.includes("mail_run_budget_spent"));
});

test("only a send with the PDF gets the long timeout", () => {
  assert.equal(sendTimeoutMs({}), SEND_TIMEOUT_MS);
  assert.equal(
    sendTimeoutMs({ attachments: [{ filename: PDF_GATE_FILENAME, content: "QQ==" }] }),
    ATTACHMENT_SEND_TIMEOUT_MS,
  );
});

test("base64 of a file many chunks long matches Node's encoder", () => {
  const big = new Uint8Array(200_003);
  for (let i = 0; i < big.length; i++) big[i] = (i * 31 + 7) & 0xff;
  big.set(new TextEncoder().encode("%PDF-"));
  assert.equal(pdfAttachment(big).content, Buffer.from(big).toString("base64"));
});

test("the reader refuses a declared size over the cap before reading the body", async () => {
  let pulled = false;
  const body = new ReadableStream<Uint8Array>(
    {
      pull(c) {
        pulled = true;
        c.enqueue(PDF);
        c.close();
      },
      // No pull until something reads, so "pulled" means the body was read.
    },
    { highWaterMark: 0 },
  );
  const read = makePdfGateReader(
    (async () =>
      new Response(body, {
        status: 200,
        headers: { "content-length": String(MAX_ATTACHMENT_BYTES + 1) },
      })) as unknown as typeof fetch,
    "http://127.0.0.1:54321",
    "service-key",
  );
  await assert.rejects(read(), /too large/);
  assert.equal(pulled, false);
});
