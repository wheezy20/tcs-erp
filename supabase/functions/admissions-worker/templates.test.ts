// Unit tests for templates.ts. Run from the repo root with Node 22:
//
//   node --test supabase/functions/admissions-worker/templates.test.ts
//
// The dash and "inquiry" rules apply to email subjects and bodies only
// (decided 2026-10-16), not to code names or staff screens.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  EMAIL_KINDS,
  longDate,
  parseParams,
  renderEmail,
  type EmailKind,
} from "./templates.ts";

const ERP = "https://erp.example.test";
// Passed to every render; only the resume email uses it.
const RESUME_TOKEN = "c".repeat(64);
const DRAFT = {
  url: `https://apply.example.test/apply#resume=${RESUME_TOKEN}`,
  expiresAt: "2026-11-20T06:34:29.935916+00:00",
};
const one = (ref: string) => ({
  reference: ref,
  grade: "Grade 3",
  academic_year: "2026/2027",
});

function cases(): Array<[EmailKind, unknown]> {
  return [
    ["inquiry_parent", { references: [one("INQ-2026-0041")] }],
    [
      "inquiry_parent",
      {
        references: [
          one("INQ-2026-0041"),
          { ...one("INQ-2026-0042"), grade: "Nursery 1" },
        ],
      },
    ],
    ["inquiry_staff", { references: [one("INQ-2026-0041")] }],
    [
      "inquiry_staff",
      {
        references: [
          one("INQ-2026-0041"),
          one("INQ-2026-0042"),
          one("INQ-2026-0043"),
        ],
      },
    ],
    ["application_parent", { references: [one("APP-2026-0012")] }],
    [
      "application_staff",
      {
        references: [one("APP-2026-0012")],
        family_matched: false,
        outcome: null,
      },
    ],
    [
      "application_staff",
      {
        references: [one("APP-2026-0012")],
        family_matched: true,
        outcome: "new_application",
      },
    ],
    [
      "application_staff",
      {
        references: [one("APP-2026-0012")],
        family_matched: true,
        outcome: "inquiry_advanced",
      },
    ],
    [
      "application_staff",
      {
        references: [one("APP-2026-0012")],
        family_matched: true,
        outcome: "possible_duplicate",
      },
    ],
    ["draft_resume", {}],
  ];
}

test("every kind is covered by the cases", () => {
  assert.deepEqual(
    [...new Set(cases().map(([k]) => k))].sort(),
    [...EMAIL_KINDS].sort(),
  );
});

test("no subject has an em or en dash or any other dash character", () => {
  for (const [kind, params] of cases()) {
    const { subject } = renderEmail(kind, params, ERP, DRAFT);
    assert.doesNotMatch(
      subject,
      /[\u2012\u2013\u2014\u2015\u2212]/,
      `${kind}: ${subject}`,
    );
  }
});

test("no body has an em or en dash or any other dash character", () => {
  for (const [kind, params] of cases()) {
    const { text } = renderEmail(kind, params, ERP, DRAFT);
    assert.doesNotMatch(
      text,
      /[\u2012\u2013\u2014\u2015\u2212]/,
      `${kind}: ${text}`,
    );
  }
});

test("no subject or body uses the word inquiry; the emails say enquiry", () => {
  for (const [kind, params] of cases()) {
    const { subject, text } = renderEmail(kind, params, ERP, DRAFT);
    assert.doesNotMatch(`${subject}\n${text}`, /inquir/i, kind);
  }
  assert.equal(
    renderEmail("inquiry_parent", cases()[0][1], ERP).subject,
    "We have received your enquiry",
  );
  assert.equal(
    renderEmail("application_parent", cases()[4][1], ERP).subject,
    "We have received your application",
  );
  assert.equal(
    renderEmail("inquiry_staff", cases()[2][1], ERP).subject,
    "New enquiry INQ-2026-0041",
  );
  assert.equal(
    renderEmail("inquiry_staff", cases()[3][1], ERP).subject,
    "New enquiry INQ-2026-0041 and 2 more",
  );
  assert.equal(
    renderEmail("application_staff", cases()[5][1], ERP).subject,
    "New application APP-2026-0012",
  );
});

test("parent emails: no names, no links, the reference, the Admissions Office sign-off", () => {
  for (const [kind, params] of cases().filter(([k]) => k.endsWith("_parent"))) {
    const { text } = renderEmail(kind, params, ERP, DRAFT);
    assert.match(text, /^Dear Parent or Guardian,\n\n/);
    assert.match(
      text,
      /\n\nKind regards,\nAdmissions Office\nTreasures Christian School$/,
    );
    assert.doesNotMatch(text, /https?:|www\./);
    assert.match(text, /(INQ|APP)-2026-00\d\d \(Grade 3, 2026\/2027\)/);
    assert.match(text, /please reply to this email to let us know/);
  }
});

test("several children are listed in form order, by position, without names", () => {
  const { text } = renderEmail("inquiry_parent", cases()[1][1], ERP);
  assert.match(
    text,
    /Your reference numbers:\n  Child 1 on your form: INQ-2026-0041 \(Grade 3, 2026\/2027\)\n  Child 2 on your form: INQ-2026-0042 \(Nursery 1, 2026\/2027\)/,
  );
  assert.match(text, /Please quote these references/);
  assert.match(
    renderEmail("inquiry_parent", cases()[0][1], ERP).text,
    /Your reference number:\n  INQ-2026-0041/,
  );
});

test("the application email keeps the TCS OS decision and fee sentence, without bank details", () => {
  const { text } = renderEmail("application_parent", cases()[4][1], ERP);
  assert.match(
    text,
    /the school will contact you regarding an admission decision after due process/,
  );
  assert.match(text, /does not mean admission has been granted/);
  assert.doesNotMatch(text, /Account|0383011100001|\*170#/);
});

test("staff alerts link to the admissions list and state the match outcome", () => {
  const plain = renderEmail("application_staff", cases()[5][1], ERP).text;
  assert.match(plain, /https:\/\/erp\.example\.test\/admissions$/);
  assert.doesNotMatch(plain, /matched|duplicate|continues/);
  assert.match(
    renderEmail("application_staff", cases()[6][1], ERP).text,
    /matched a family already on record/,
  );
  assert.match(
    renderEmail("application_staff", cases()[7][1], ERP).text,
    /continues an earlier enquiry/,
  );
  assert.match(
    renderEmail("application_staff", cases()[8][1], ERP).text,
    /may repeat an earlier application/,
  );
});

test("params outside the allowed shape are refused, so nothing else can be printed", () => {
  const bad: Array<[EmailKind, unknown]> = [
    [
      "inquiry_parent",
      { references: [one("INQ-2026-0041")], child_name: "Someone" },
    ],
    [
      "inquiry_parent",
      { references: [{ ...one("INQ-2026-0041"), health: "asthma" }] },
    ],
    ["inquiry_parent", { references: [one("APP-2026-0041")] }],
    ["inquiry_parent", { references: [] }],
    [
      "application_parent",
      { references: [one("APP-2026-0012"), one("APP-2026-0013")] },
    ],
    [
      "application_parent",
      { references: [one("APP-2026-0012")], family_matched: true },
    ],
    ["application_staff", { references: [one("APP-2026-0012")] }],
    [
      "application_staff",
      {
        references: [one("APP-2026-0012")],
        family_matched: true,
        outcome: "other",
      },
    ],
    [
      "inquiry_parent",
      { references: [{ ...one("INQ-2026-0041"), grade: "" }] },
    ],
  ];
  for (const [kind, params] of bad) {
    assert.throws(
      () => parseParams(kind, params),
      Error,
      JSON.stringify(params),
    );
  }
});

test("control characters and line breaks in a grade are flattened to one line", () => {
  const { text } = renderEmail(
    "inquiry_parent",
    { references: [{ ...one("INQ-2026-0041"), grade: "Grade\n3\r\nBCC: x" }] },
    ERP,
  );
  assert.match(text, /INQ-2026-0041 \(Grade 3 BCC: x, 2026\/2027\)/);
});

// ---------------------------------------------------------------- resume email (slice 10)

test("the resume email: the private link, the date it is kept until, what is not saved, no name, no dash", () => {
  const { subject, text } = renderEmail("draft_resume", {}, ERP, DRAFT);
  assert.equal(subject, "Your saved application");
  assert.ok(text.startsWith("Dear Parent or Guardian,"));
  assert.ok(text.includes(`\n  ${DRAFT.url}\n`));
  assert.equal(
    text.split(RESUME_TOKEN).length,
    2,
    "the link appears exactly once",
  );
  assert.match(text, /kept until 20 November 2026\./);
  assert.match(text, /please do not forward it/);
  assert.match(
    text,
    /health questions, uploaded files and the declaration are not saved/,
  );
  assert.match(
    text,
    /If you did not ask for this, you can ignore this email\./,
  );
  assert.ok(
    text.endsWith(
      "Kind regards,\nAdmissions Office\nTreasures Christian School",
    ),
  );
  assert.doesNotMatch(
    text,
    /[\u2012\u2013\u2014\u2015\u2212]|inquir|https?:\/\/erp/i,
  );
});

test("the resume email needs its link, takes only a /apply resume link, and refuses any params", () => {
  assert.throws(() => renderEmail("draft_resume", {}, ERP));
  for (const url of [
    `https://apply.example.test/apply?resume=${RESUME_TOKEN}`,
    `https://apply.example.test/other#resume=${RESUME_TOKEN}`,
    "https://apply.example.test/apply#resume=short",
    `javascript:alert(1)//apply#resume=${RESUME_TOKEN}`,
  ]) {
    assert.throws(
      () => renderEmail("draft_resume", {}, ERP, { ...DRAFT, url }),
      url,
    );
  }
  assert.throws(() =>
    renderEmail("draft_resume", {}, ERP, { ...DRAFT, expiresAt: "soon" }),
  );
  assert.throws(() => parseParams("draft_resume", { token: RESUME_TOKEN }));
  assert.throws(() => parseParams("draft_resume", { references: [] }));
});

test("longDate writes the Accra date in full", () => {
  assert.equal(longDate("2026-01-01T00:30:00Z"), "1 January 2026");
  assert.equal(longDate("2026-12-31T23:59:59Z"), "31 December 2026");
});
