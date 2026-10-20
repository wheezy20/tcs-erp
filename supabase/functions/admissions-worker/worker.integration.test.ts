// admissions-worker against the LOCAL database and a LOCAL fake provider
// (a small HTTP server on 127.0.0.1 that records requests): no email is
// ever sent and Resend is never called. Covers a missing or wrong secret
// doing nothing, a real enquiry's emails end to end, retries and
// failures, a second run sending nothing, mail off, and two database
// sessions claiming the same rows at once. Run on a freshly reset local
// stack from the repo root, after the probe files:
//
//   ./scripts/seed-local-dev-staff.sh
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
//        node --test supabase/functions/admissions-worker/worker.integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It commits
// outbox rows, an enquiry and its family; `npx supabase db reset` clears
// them. Run it after the probe files: probes E7 and E19 count outbox rows.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";

import {
  handle,
  loadMailConfig,
  makeResendSender,
  type Deps,
  type MailConfig,
} from "./handler.ts";

const API_URL = process.env.API_URL ?? "";
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY ?? "";
if (
  !/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(API_URL) ||
  SERVICE_KEY === ""
) {
  throw new Error(
    "worker.integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
  );
}
const PROJECT = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)![1];
const RUN = Date.now().toString(36);
const email = (who: string) => `worker.${who}.${RUN}@example.test`;

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

type Seen = {
  headers: IncomingMessage["headers"];
  body: Record<string, unknown>;
};
const seen: Seen[] = [];
let server: Server;
let providerBase = "";

/** Answers by recipient: an address containing "fail422" gets 422,
 * "fail503" gets 503; anything else is accepted with an id. */
before(async () => {
  server = createServer((req, res) => {
    let raw = "";
    req.on("data", (d) => (raw += String(d)));
    req.on("end", () => {
      const body = JSON.parse(raw) as Record<string, unknown>;
      seen.push({ headers: req.headers, body });
      const to = String((body.to as string[])[0]);
      if (to.includes("fail422")) {
        res
          .writeHead(422, { "content-type": "application/json" })
          .end(JSON.stringify({ message: `${to} is invalid` }));
      } else if (to.includes("fail503")) {
        res.writeHead(503).end();
      } else {
        res
          .writeHead(200, { "content-type": "application/json" })
          .end(JSON.stringify({ id: `fake-${seen.length}` }));
      }
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  providerBase = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

function mailConfig(): MailConfig {
  const config = loadMailConfig(
    (n) =>
      ({
        MAIL_MODE: "test",
        RESEND_API_KEY: "fake-integration-key",
        RESEND_API_BASE: providerBase,
        MAIL_FROM: "TCS Admissions <no-reply@mail.example.test>",
        MAIL_REPLY_TO: "admissions@example.test",
        ADMISSIONS_STAFF_EMAIL: `staff.${RUN}@example.test`,
        ERP_BASE_URL: "http://localhost:8080",
        MAIL_DAILY_CEILING: "1000",
        SUPABASE_URL: API_URL,
      })[n],
  );
  assert.ok(config, "test mail config refused");
  assert.equal(config.apiBase, providerBase);
  return config;
}

function deps(mail: MailConfig | null): Deps {
  return {
    rpc,
    mail,
    send: makeResendSender(fetch),
    sleep: async () => {},
    log: () => {},
  };
}

const secret = () =>
  psql(
    "select decrypted_secret from vault.decrypted_secrets where name = 'admissions_worker_secret'",
  );

function call(d: Deps, job: string, header: string | null) {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (header !== null) headers["x-admissions-worker-secret"] = header;
  return handle(
    new Request("http://fn.local/admissions-worker", {
      method: "POST",
      headers,
      body: JSON.stringify({ job }),
    }),
    d,
  );
}

/** Inserts one due outbox row for this run and returns its id. */
function row(to: string): string {
  return psql(`insert into public.admissions_email_outbox (event_key, kind, recipient_email, application_ids, params)
    values ('inquiry:' || gen_random_uuid(), 'inquiry_parent', '${to}', array[gen_random_uuid()],
      '{"references":[{"reference":"INQ-2026-9001","grade":"Grade 1","academic_year":"2026/2027"}]}')
    returning id`).split("\n")[0];
}

const status = (id: string) =>
  psql(
    `select status || '/' || attempts || '/' || coalesce(last_error_class, '-') from public.admissions_email_outbox where id = '${id}'`,
  );

// Leaves nothing due from earlier runs or other files, so each test sees
// only its own rows.
before(() => {
  psql(
    "update public.admissions_email_outbox set status = 'failed', claim_token = null, claimed_at = null where status in ('pending', 'sending')",
  );
});

// ---------------------------------------------------------------- tests

test("a missing or wrong secret header does nothing and sends nothing", async () => {
  const id = row(email("guarded"));
  const before = seen.length;
  for (const header of [null, "", "0".repeat(64), `${secret()}x`]) {
    const res = await call(deps(mailConfig()), "mail", header);
    assert.equal(res.status, 401, String(header));
  }
  assert.equal(seen.length, before);
  assert.equal(status(id), "pending/0/-");
  psql(
    `update public.admissions_email_outbox set status = 'failed' where id = '${id}'`,
  );
});

test("a real enquiry: two parent emails and one staff alert, sent once each, with the right addresses and no name", async () => {
  const p = (who: string) => ({
    surname: "Mensah",
    first_name: who,
    relationship: who === "One" ? "mother" : "father",
    religion: "Christian",
    address: "1 Ring Road",
    town_city: "Accra",
    phone: who === "One" ? "+233590000001" : "+233590000002",
    email: email(`parent${who}`),
  });
  psql(
    "update public.admissions_settings set public_intake_open = true where id = 1",
  );
  const grade = psql(
    "select id from public.admissions_grades where name = 'Grade 1'",
  );
  const inq = await rpc("submit_inquiry", {
    p_payload: {
      referral_source: "website",
      guardians: [p("One"), p("Two")],
      students: [
        {
          full_name: `Worker Child ${RUN}`,
          date_of_birth: "2019-02-03",
          current_school: "Little Stars",
          current_grade_id: psql(
            "select id from public.admissions_grades where name = 'Kindergarten 2'",
          ),
          grade_id: grade,
          academic_year: "2026/2027",
          month_of_enrollment: "September",
        },
      ],
    },
  });
  psql(
    "update public.admissions_settings set public_intake_open = false where id = 1",
  );
  assert.equal(inq.error, null, JSON.stringify(inq.error));
  const ref = (inq.data as string[])[0];

  const before = seen.length;
  const res = await call(deps(mailConfig()), "mail", secret());
  assert.equal(res.status, 200);
  const mine = seen.slice(before);
  assert.deepEqual(
    mine.map((s) => (s.body.to as string[])[0]).sort(),
    [
      email("parentone"),
      email("parenttwo"),
      `staff.${RUN}@example.test`,
    ].sort(),
  );
  for (const s of mine) {
    assert.equal(s.body.from, "TCS Admissions <no-reply@mail.example.test>");
    assert.equal(s.body.reply_to, "admissions@example.test");
    assert.match(
      String(s.headers["idempotency-key"]),
      /^outbox-[0-9a-f-]{36}$/,
    );
    assert.equal(s.headers.authorization, "Bearer fake-integration-key");
    assert.match(String(s.body.text), new RegExp(ref));
    assert.doesNotMatch(
      String(s.body.text),
      /Worker Child|Mensah|\u2013|\u2014|inquir/i,
    );
    assert.equal(s.body.html, undefined);
  }
  assert.equal(new Set(mine.map((s) => s.headers["idempotency-key"])).size, 3);
  assert.equal(
    psql(
      `select string_agg(status, ',' order by status) from public.admissions_email_outbox where params -> 'references' -> 0 ->> 'reference' = '${ref}' and provider_message_id like 'fake-%' and sent_at is not null`,
    ),
    "sent,sent,sent",
  );

  const again = seen.length;
  await call(deps(mailConfig()), "mail", secret());
  assert.equal(seen.length, again, "a second run sent again");
});

test("a 503 is retried later and a 422 fails at once; neither stores the provider's message", async () => {
  const soft = row(email("fail503"));
  const hard = row(email("fail422"));
  await call(deps(mailConfig()), "mail", secret());
  assert.equal(status(soft), "pending/1/provider_error");
  assert.equal(status(hard), "failed/1/invalid_recipient");
  assert.equal(
    psql(
      `select count(*) from public.admissions_email_outbox o where row_to_json(o)::text like '%is invalid%'`,
    ),
    "0",
  );
  psql(
    `update public.admissions_email_outbox set status = 'failed' where id = '${soft}'`,
  );
});

test("mail off: nothing is claimed and nothing is sent", async () => {
  const id = row(email("off"));
  const before = seen.length;
  assert.equal((await call(deps(null), "mail", secret())).status, 200);
  assert.equal(seen.length, before);
  assert.equal(status(id), "pending/0/-");
  psql(
    `update public.admissions_email_outbox set status = 'failed' where id = '${id}'`,
  );
});

test("two database sessions claiming the same due rows: each row is claimed once", async () => {
  const ids = [1, 2, 3, 4, 5].map((i) => row(email(`race${i}`)));
  const list = ids.map((i) => `'${i}'`).join(",");
  const a = psqlAsync(`begin;
select 'A ' || count(*) from public.claim_admissions_emails(50, 1000);
select pg_sleep(3);
commit;`);
  await new Promise((r) => setTimeout(r, 1000));
  const b = await psqlAsync(
    "select 'B ' || count(*) from public.claim_admissions_emails(50, 1000);",
  );
  const aOut = await a;
  assert.equal(aOut.code, 0, aOut.out);
  assert.equal(b.code, 0, b.out);
  assert.match(aOut.out, /^A 5$/m);
  assert.match(b.out, /^B 0$/m);
  assert.equal(
    psql(
      `select string_agg(distinct status || '/' || attempts, ',') from public.admissions_email_outbox where id in (${list})`,
    ),
    "sending/1",
  );
  psql(
    `update public.admissions_email_outbox set status = 'failed', claim_token = null, claimed_at = null where id in (${list})`,
  );
});
