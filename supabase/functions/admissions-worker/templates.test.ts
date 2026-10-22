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
// Passed to every render; only the two lead emails use it.
const INQUIRY_URL = "https://admissions.school.example.test/inquiry";
const LEAD_ID = "13000000-0000-4000-8000-000000000a01";
const LEAD = {
  inquiryUrl: INQUIRY_URL,
  alert: {
    lead_id: LEAD_ID,
    grade_interest: "Nursery 1",
    consent_to_marketing: true,
    source: "pdf_gate_admissions_overview",
  },
};
// Passed to every render; only the offer email uses it.
const OFFER_TOKEN = "d".repeat(64);
const OFFER = {
  url: `https://apply.example.test/offer#token=${OFFER_TOKEN}`,
  respondBy: "2026-11-05T09:00:00+00:00",
};
const APP_ID = "11000000-0000-4000-8000-000000000b01";
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
    ["pdf_gate", {}],
    ["lead_staff", {}],
    ["offer", { references: [one("APP-2026-0012")] }],
    ["offer_staff", { references: [one("APP-2026-0012")], application_id: APP_ID, response: "accepted" }],
    ["offer_staff", { references: [one("APP-2026-0012")], application_id: APP_ID, response: "declined" }],
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
    const { subject } = renderEmail(kind, params, ERP, DRAFT, LEAD, OFFER);
    assert.doesNotMatch(subject, /[\u2012\u2013\u2014\u2015\u2212]/, `${kind}: ${subject}`);
  }
});

test("no body has an em or en dash or any other dash character", () => {
  for (const [kind, params] of cases()) {
    const { text } = renderEmail(kind, params, ERP, DRAFT, LEAD, OFFER);
    assert.doesNotMatch(text, /[\u2012\u2013\u2014\u2015\u2212]/, `${kind}: ${text}`);
  }
});

test("no subject or body uses the word inquiry; the emails say enquiry", () => {
  for (const [kind, params] of cases()) {
    const { subject, text } = renderEmail(kind, params, ERP, DRAFT, LEAD, OFFER);
    // The one exception: the path of the PDF email's enquiry link.
    assert.doesNotMatch(`${subject}\n${text}`.replaceAll(INQUIRY_URL, ""), /inquir/i, kind);
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
    const { text } = renderEmail(kind, params, ERP, DRAFT, LEAD, OFFER);
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

// ---------------------------------------------------------------- lead emails

test("pdf_gate: no name, the document named as attached, exactly one link, the enquiry link", () => {
  const { subject, text } = renderEmail("pdf_gate", {}, ERP, undefined, {
    inquiryUrl: INQUIRY_URL,
  });
  assert.equal(subject, "Your TCS Admissions Overview and Fees");
  assert.ok(text.startsWith("Dear Parent or Guardian,"));
  assert.match(text, /Admissions Overview and Fees document is attached/);
  assert.deepEqual(text.match(/https?:\/\/\S+/g), [INQUIRY_URL]);
  assert.ok(text.endsWith("Kind regards,\nAdmissions Office\nTreasures Christian School"));
});

test("pdf_gate refuses a missing or wrong enquiry link", () => {
  for (const inquiryUrl of [
    undefined,
    "http://admissions.school.example.test/inquiry",
    "https://admissions.school.example.test/inquiry?ref=x",
    "https://admissions.school.example.test/inquiry#x",
    "https://admissions.school.example.test/apply",
    "https://user@admissions.school.example.test/inquiry",
    "https://localhost/inquiry",
  ]) {
    assert.throws(
      () => renderEmail("pdf_gate", {}, ERP, undefined, { inquiryUrl }),
      String(inquiryUrl),
    );
  }
  assert.throws(() =>
    renderEmail("pdf_gate", { references: [] }, ERP, undefined, { inquiryUrl: INQUIRY_URL }),
  );
});

test("lead_staff: grade, consent, source and the ERP link to the lead; no name in the subject", () => {
  const { subject, text } = renderEmail("lead_staff", {}, `${ERP}/`, undefined, {
    alert: LEAD.alert,
  });
  assert.equal(subject, "New lead: Admissions Overview download");
  assert.match(text, /Grade of interest: Nursery 1\n/);
  assert.match(text, /Agreed to marketing emails: yes\n/);
  assert.match(text, /Source: Admissions Overview download on the school website/);
  assert.match(text, new RegExp(`${ERP}/admissions/leads\\?lead=${LEAD_ID}$`));
  const none = renderEmail("lead_staff", {}, ERP, undefined, {
    alert: { ...LEAD.alert, grade_interest: null, consent_to_marketing: false },
  }).text;
  assert.match(none, /Grade of interest: not given\n/);
  assert.match(none, /Agreed to marketing emails: no\n/);
});

test("lead_staff keeps a typed grade to one plain line of at most 50 characters", () => {
  const { text } = renderEmail("lead_staff", {}, ERP, undefined, {
    alert: { ...LEAD.alert, grade_interest: "KG 1\r\nBcc: x@example.test\u2028" + "y".repeat(80) },
  });
  const line = text.split("\n").find((l) => l.startsWith("Grade of interest: "))!;
  assert.ok(line.length <= "Grade of interest: ".length + 50, line);
  assert.doesNotMatch(text, /\r|\u2028/);
});

test("lead_staff refuses an alert that isn't the database's shape", () => {
  for (const alert of [
    undefined,
    { ...LEAD.alert, lead_id: "../admin" },
    { ...LEAD.alert, source: "quick_interest_widget" },
    { ...LEAD.alert, consent_to_marketing: "yes" },
    { ...LEAD.alert, grade_interest: 5 },
  ]) {
    assert.throws(
      () => renderEmail("lead_staff", {}, ERP, undefined, { alert: alert as typeof LEAD.alert }),
      JSON.stringify(alert),
    );
  }
});

test("offer: the grade, year and reference, the private link, the respond-by date, no name, Reply-To wording, the sign-off", () => {
  const { subject, text } = renderEmail("offer", cases().find(([k]) => k === "offer")![1], ERP, undefined, undefined, OFFER);
  assert.equal(subject, "An offer of a place at Treasures Christian School");
  assert.match(text, /^Dear Parent or Guardian,\n\n/);
  assert.match(text, /a place at Treasures Christian School in Grade 3 for the 2026\/2027 academic year/);
  assert.match(text, /reference is APP-2026-0012\./);
  assert.equal(text.match(/https?:\/\/\S+/g)?.length, 1);
  assert.ok(text.includes(`\n  ${OFFER.url}\n`));
  assert.match(text, /open until 5 November 2026\./);
  assert.match(text, /please do not forward this email/);
  assert.match(text, /reply to this email/);
  assert.match(text, /\n\nKind regards,\nAdmissions Office\nTreasures Christian School$/);
  assert.doesNotMatch(`${subject}\n${text}`, /[\u2012\u2013\u2014\u2015\u2212]/);
});

test("offer needs its link and takes only an /offer token link; params are the one APP reference", () => {
  const params = { references: [one("APP-2026-0012")] };
  assert.throws(() => renderEmail("offer", params, ERP));
  for (const url of [
    `https://apply.example.test/apply#resume=${OFFER_TOKEN}`,
    `https://apply.example.test/offer?token=${OFFER_TOKEN}`,
    `https://apply.example.test/offer#token=${OFFER_TOKEN.slice(1)}`,
    `https://apply.example.test/x/offer#token=${OFFER_TOKEN}`,
  ])
    assert.throws(() => renderEmail("offer", params, ERP, undefined, undefined, { ...OFFER, url }), url);
  assert.throws(() => parseParams("offer", { references: [one("INQ-2026-0001")] }));
  assert.throws(() => parseParams("offer", { references: [one("APP-2026-0012"), one("APP-2026-0013")] }));
  assert.throws(() => parseParams("offer", { references: [one("APP-2026-0012")], application_id: APP_ID }));
});

test("offer_staff: the reference, the response and the ERP link to the application only", () => {
  const { subject, text } = renderEmail(
    "offer_staff",
    { references: [one("APP-2026-0012")], application_id: APP_ID, response: "declined" },
    ERP + "/",
  );
  assert.equal(subject, "Offer APP-2026-0012 declined through the offer link");
  assert.equal(
    text,
    [
      "A parent declined an offer through the offer link.",
      "Reference: APP-2026-0012",
      `Open the application in the ERP: ${ERP}/admissions/${APP_ID}`,
    ].join("\n\n"),
  );
  assert.doesNotMatch(text, /Grade 3|2026\/2027|@/);
  for (const bad of [
    { references: [one("APP-2026-0012")], application_id: "x", response: "accepted" },
    { references: [one("APP-2026-0012")], application_id: APP_ID, response: "pending" },
    { references: [one("APP-2026-0012")], application_id: APP_ID },
    { references: [one("APP-2026-0012")], application_id: APP_ID, response: "accepted", name: "Ama" },
  ])
    assert.throws(() => parseParams("offer_staff", bad), JSON.stringify(bad));
});
