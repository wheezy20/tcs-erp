// The admissions-public handler against the LOCAL database, through
// PostgREST with the local service role, and a fake Turnstile verifier (no
// call to Cloudflare). Run on a freshly reset local stack from the repo root:
//
//   eval "$(npx supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')" \
//     && API_URL="$API_URL" SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
//        node --test supabase/functions/admissions-public/integration.test.ts
//
// Refuses to run unless API_URL is 127.0.0.1 or localhost. It opens public
// intake, writes real inquiry rows and rate limit counters, and closes
// intake again at the end; `npx supabase db reset` clears the rest.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import {
  handle,
  hmacHex,
  type Deps,
  type TurnstileOutcome,
} from "./handler.ts";

const API_URL = process.env.API_URL ?? "";
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY ?? "";
if (
  !/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(API_URL) ||
  SERVICE_KEY === ""
) {
  throw new Error(
    "integration.test.ts runs only against the local stack (API_URL on 127.0.0.1).",
  );
}

const ORIGIN = "http://localhost:8080";
const IP_KEY = "integration-ip-hash-key-0123456789abcdef";
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

async function rest(path: string, init: RequestInit = {}) {
  return fetch(`${API_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

let turnstile: TurnstileOutcome = {
  success: true,
  hostname: "localhost",
  action: "inquiry",
};

const deps: Deps = {
  config: {
    allowedOrigins: [ORIGIN],
    turnstileSecret: "unused-fake",
    ipHashKey: IP_KEY,
  },
  verifyTurnstile: async () => turnstile,
  rpc: async (fn, args) => {
    const res = await rest(`rpc/${fn}`, {
      method: "POST",
      body: JSON.stringify(args),
    });
    const body = await res.json();
    return res.ok ? { data: body, error: null } : { data: null, error: body };
  },
  log: () => {},
};

let ipCounter = 0;
function freshIp(): string {
  ipCounter += 1;
  return `198.51.100.${ipCounter}`;
}

async function send(payload: unknown, ip = freshIp()) {
  const res = await handle(
    new Request("http://fn.local/admissions-public", {
      method: "POST",
      headers: {
        origin: ORIGIN,
        "content-type": "application/json",
        "x-forwarded-for": ip,
      },
      body: JSON.stringify({
        action: "inquiry",
        turnstile_token: "fake",
        payload,
      }),
    }),
    deps,
  );
  return {
    status: res.status,
    body: (await res.json()) as Record<string, unknown>,
  };
}

let options: {
  grades: { id: string; name: string }[];
  campuses: { id: string; name: string }[];
  academic_years: string[];
};

function inquiry(email: string, student: Record<string, unknown> = {}) {
  const grade = options.grades.find((g) => g.name === "Grade 1")!;
  const current = options.grades.find((g) => g.name === "Kindergarten 2")!;
  return {
    referral_source: "website",
    guardians: [
      {
        surname: "Mensah",
        first_name: "Ama",
        relationship: "mother",
        religion: "Christian",
        address: "1 Ring Road",
        town_city: "Accra",
        phone: "+233551794822",
        email,
      },
    ],
    students: [
      {
        full_name: "Kofi Mensah",
        date_of_birth: "2019-02-03",
        current_school: "N/A",
        current_grade_id: current.id,
        grade_id: grade.id,
        academic_year: options.academic_years[0],
        month_of_enrollment: "September",
        ...student,
      },
    ],
  };
}

async function setIntake(open: boolean) {
  const res = await rest("admissions_settings?id=eq.1", {
    method: "PATCH",
    body: JSON.stringify({ public_intake_open: open }),
  });
  assert.ok(res.ok, `could not set intake: ${res.status}`);
}

before(async () => {
  const res = await rest("rpc/get_public_admissions_options", {
    method: "POST",
    body: "{}",
  });
  options = await res.json();
  await setIntake(false);
});

after(async () => {
  await setIntake(false);
});

test("closed intake refuses with the closed message and writes nothing", async () => {
  const before = psql("select count(*) from public.families");
  const r = await send(inquiry("closed@example.test"));
  assert.equal(r.status, 409);
  assert.match(String(r.body.error), /closed/);
  assert.equal(psql("select count(*) from public.families"), before);
});

test("open intake: a valid inquiry returns only INQ references", async () => {
  await setIntake(true);
  const r = await send(inquiry("valid@example.test"));
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys(r.body), ["references"]);
  assert.match(
    String((r.body.references as string[])[0]),
    /^INQ-[0-9]{4}-[0-9]{4,}$/,
  );
  assert.equal(
    psql(
      `select a.stage || '|' || a.year_group_applied_for || '|' || g.email from public.applications a
       join public.students s on s.id = a.student_id join public.guardians g on g.family_id = s.family_id
       where a.inquiry_reference = '${(r.body.references as string[])[0]}'`,
    ),
    "inquiry|Grade 1|valid@example.test",
  );
});

test("free text for grade, year or campus is refused", async () => {
  const bad: Record<string, unknown>[] = [
    { year_group_applied_for: "Grade 1" },
    { grade_id: "Grade 1" },
    { grade_id: "00000000-0000-0000-0000-000000000000" },
    { academic_year: "2099/2100" },
    { academic_year: "Next year" },
    { campus_id: "Main" },
    { campus_id: "00000000-0000-0000-0000-0000000000ff" },
  ];
  for (const student of bad) {
    const r = await send(inquiry("freetext@example.test", student));
    assert.equal(r.status, 400, JSON.stringify(student));
  }
});

test("a campus that doesn't take the grade is refused with a contact-the-school message", async () => {
  const annex = options.campuses.find((c) => c.name === "Annex (CK Road)")!;
  const r = await send(inquiry("annex@example.test", { campus_id: annex.id }));
  assert.equal(r.status, 400);
  assert.match(String(r.body.error), /contact the school/);
});

test("the sixth inquiry for one email in a day is refused with the office message", async () => {
  for (let i = 0; i < 5; i += 1) {
    assert.equal(
      (await send(inquiry("limit@example.test"))).status,
      200,
      `attempt ${i + 1}`,
    );
  }
  const r = await send(inquiry("LIMIT@example.test"));
  assert.equal(r.status, 429);
  assert.match(String(r.body.error), /call the school office/);
});

test("the 21st request from one IP in an hour is refused before Turnstile", async () => {
  turnstile = { success: false };
  const ip = "192.0.2.77";
  for (let i = 0; i < 20; i += 1) {
    assert.equal(
      (await send(inquiry("ip@example.test"), ip)).status,
      400,
      `attempt ${i + 1}`,
    );
  }
  let verifierCalled = false;
  const saved = deps.verifyTurnstile;
  deps.verifyTurnstile = async () => {
    verifierCalled = true;
    return turnstile;
  };
  const r = await send(inquiry("ip@example.test"), ip);
  deps.verifyTurnstile = saved;
  turnstile = { success: true, hostname: "localhost", action: "inquiry" };
  assert.equal(r.status, 429);
  assert.equal(verifierCalled, false);
  // A different IP still gets through.
  assert.equal((await send(inquiry("ip2@example.test"))).status, 200);
});

test("no raw IP or raw email is stored in the rate limit table", async () => {
  const keys = psql(
    "select string_agg(key_hash, ',') from public.public_rate_limits",
  ).split(",");
  assert.ok(keys.length > 0);
  for (const k of keys) assert.match(k, /^([0-9a-f]{64}|global)$/);
  const all = psql(
    "select string_agg(bucket || key_hash, ',') from public.public_rate_limits",
  );
  assert.ok(!all.includes("192.0.2.77") && !all.includes("example.test"));
  assert.ok(keys.includes(await hmacHex(IP_KEY, "192.0.2.77")));
});
