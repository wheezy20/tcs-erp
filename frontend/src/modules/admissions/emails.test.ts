import { describe, expect, it } from "vitest";

import {
  EMAIL_FILTERS,
  EMAIL_KIND_LABELS,
  EMAIL_STATUS_NOTES,
  EMAIL_STATUSES,
  EMAIL_STATUS_LABELS,
  applicationEmailLine,
  canRetryEmail,
  healthMessages,
  recipientLabel,
  statusNote,
  statusTone,
  type EmailHealth,
} from "@/modules/admissions/emails";

const NOW = new Date("2026-10-20T12:00:00Z");
const ago = (minutes: number) => new Date(NOW.getTime() - minutes * 60000).toISOString();
const HEALTHY: EmailHealth = {
  waiting: 0,
  failed: 0,
  suppressed: 0,
  expired: 0,
  draftFailed: 0,
  lastRunAt: ago(1),
  lastSuccessAt: ago(1),
  ceilingReachedAt: null,
  configError: false,
};

describe("email labels", () => {
  it("labels every status, and expired says it was never sent", () => {
    for (const s of EMAIL_STATUSES) expect(EMAIL_STATUS_LABELS[s]).toBeTruthy();
    expect(EMAIL_STATUS_LABELS.expired).toBe("Expired, never sent");
    expect(statusTone("expired")).toBe("problem");
    expect(EMAIL_FILTERS.map((f) => f.value)).toContain("expired");
  });

  it("never shows a staff alert's address; parent rows show the masked address", () => {
    expect(recipientLabel("application_staff", null)).toBe("Staff alert address");
    expect(recipientLabel("inquiry_parent", "j•••@g•••.com")).toBe("j•••@g•••.com");
  });

  it("only a Manager can retry, and only a failed row", () => {
    expect(canRetryEmail("Manager", "failed")).toBe(true);
    expect(canRetryEmail("Manager", "expired")).toBe(false);
    expect(canRetryEmail("Manager", "suppressed")).toBe(false);
    expect(canRetryEmail("Auditor", "failed")).toBe(false);
    expect(canRetryEmail("Admissions Officer", "failed")).toBe(false);
  });
});

describe("applicationEmailLine", () => {
  it("says when there is no confirmation email", () => {
    expect(applicationEmailLine([])).toEqual({
      tone: "none",
      text: "No confirmation email for this application.",
    });
  });

  it("sums the parent emails by status", () => {
    expect(applicationEmailLine([{ status: "sent", emails: 2, lastSentAt: ago(5) }])).toEqual({
      tone: "ok",
      text: "Confirmation email: sent to 2 addresses.",
    });
    expect(
      applicationEmailLine([
        { status: "sent", emails: 1, lastSentAt: ago(5) },
        { status: "pending", emails: 1, lastSentAt: null },
      ]),
    ).toEqual({ tone: "waiting", text: "Confirmation email: sent to 1 address, 1 email waiting." });
    expect(
      applicationEmailLine([
        { status: "expired", emails: 1, lastSentAt: null },
        { status: "failed", emails: 1, lastSentAt: null },
      ]),
    ).toEqual({ tone: "problem", text: "Confirmation email: 1 failed, 1 expired and never sent." });
  });
});

describe("healthMessages", () => {
  it("is calm when nothing is waiting", () => {
    expect(healthMessages(HEALTHY, NOW)).toEqual([
      { tone: "ok", text: "Nothing waiting. Sending is working." },
    ]);
  });

  it("flags waiting emails when sending hasn't run lately or ever", () => {
    expect(healthMessages({ ...HEALTHY, waiting: 3, lastRunAt: ago(30) }, NOW)[0]).toEqual({
      tone: "problem",
      text: "3 emails are waiting and sending last ran 30 minutes ago. Sending may be switched off or stopped.",
    });
    expect(healthMessages({ ...HEALTHY, waiting: 1, lastRunAt: null }, NOW)[0].text).toContain(
      "has never run",
    );
    expect(healthMessages({ ...HEALTHY, waiting: 1, lastRunAt: null }, NOW)[1]).toEqual({
      tone: "waiting",
      text: "Any email that has waited more than 48 hours will be marked expired, and never sent, the next time sending runs.",
    });
    expect(healthMessages({ ...HEALTHY, waiting: 2, lastRunAt: ago(1) }, NOW)).toEqual([
      { tone: "ok", text: "Sending. 2 emails are waiting." },
    ]);
  });

  it("puts a settings problem first and shows expired, failed, held and the ceiling", () => {
    const m = healthMessages(
      {
        ...HEALTHY,
        configError: true,
        failed: 1,
        expired: 2,
        suppressed: 1,
        ceilingReachedAt: ago(2),
      },
      NOW,
    );
    expect(m[0].text).toContain("A mail setting is missing or was refused");
    expect(m[0].text).toContain("Admissions Overview PDF is missing");
    expect(m.map((x) => x.text)).toEqual(
      expect.arrayContaining([
        "1 email failed. A Manager can retry them.",
        "2 emails expired: each waited more than 48 hours and was never sent.",
        "1 email was held back because an address reached its daily limit.",
        "The daily sending limit, or the half of it kept for Admissions Overview emails, was reached. Waiting emails go out as the limit allows.",
      ]),
    );
  });

  it("has no em or en dash in any message", () => {
    const all = healthMessages(
      {
        ...HEALTHY,
        configError: true,
        waiting: 2,
        lastRunAt: null,
        failed: 2,
        expired: 1,
        suppressed: 2,
        ceilingReachedAt: ago(1),
      },
      NOW,
    );
    for (const x of all) expect(x.text).not.toMatch(/[\u2013\u2014]/);
  });
});

describe("saved application link emails (slice 10)", () => {
  it("a failed count shows as a problem, says it can't be retried here, and names nobody", () => {
    const m = healthMessages({ ...HEALTHY, draftFailed: 2 }, NOW);
    expect(m[0]).toEqual({
      tone: "problem",
      text: "2 saved application link emails failed. These are not listed and can't be retried here; a parent who saves again gets a new link.",
    });
    expect(healthMessages({ ...HEALTHY, draftFailed: 1 }, NOW)[0].text).toMatch(
      /^1 saved application link email failed\./,
    );
  });
});

describe("lead emails (slice 13)", () => {
  it("labels the two lead kinds and keeps the staff alert's address hidden", () => {
    expect(EMAIL_KIND_LABELS.pdf_gate).toBe("Admissions Overview PDF");
    expect(EMAIL_KIND_LABELS.lead_staff).toBe("Lead staff alert");
    expect(recipientLabel("lead_staff", null)).toBe("Staff alert address");
    expect(recipientLabel("pdf_gate", "a•••@e•••.test")).toBe("a•••@e•••.test");
  });

  it("explains a held back PDF by its own limit of 2, and confirmations by theirs", () => {
    expect(statusNote("pdf_gate", "suppressed")).toContain("2 Admissions Overview emails");
    expect(statusNote("inquiry_parent", "suppressed")).toContain("4 confirmation emails");
    expect(statusNote("pdf_gate", "failed")).toBe(EMAIL_STATUS_NOTES.failed);
    expect(statusNote("pdf_gate", "sent")).toBeUndefined();
  });
});

describe("offer emails (slice 11)", () => {
  it("labels the two offer kinds and keeps the staff alert's address hidden", () => {
    expect(EMAIL_KIND_LABELS.offer).toBe("Offer link");
    expect(EMAIL_KIND_LABELS.offer_staff).toBe("Offer response staff alert");
    expect(recipientLabel("offer_staff", null)).toBe("Staff alert address");
    expect(recipientLabel("offer", "g•••@e•••.test")).toBe("g•••@e•••.test");
  });

  it("explains a dropped offer link email by its own rules, not the 48 hour one", () => {
    expect(statusNote("offer", "expired")).toContain("a newer link replaced it");
    expect(statusNote("offer", "expired")).toContain("7 days");
    expect(statusNote("offer_staff", "expired")).toBe(EMAIL_STATUS_NOTES.expired);
  });
});
