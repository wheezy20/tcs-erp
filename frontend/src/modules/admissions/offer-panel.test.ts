import { describe, expect, it } from "vitest";

import {
  OFFER_EMAIL_STATUS_LABELS,
  OFFER_LIMIT_HINT,
  OFFER_SEND_LIMIT_NOTE,
  addresses,
  correctionBody,
  correctionReasonProblem,
  offerWaitingNote,
  responseSourceLabel,
  sendConfirmBody,
  sendDone,
  sendErrorMessage,
} from "@/modules/admissions/offer-panel";

const DASHES = /[\u2013\u2014]/;

describe("the send confirm step (D-11c)", () => {
  it("says how many addresses are emailed now, for each send", () => {
    expect(sendConfirmBody("generate", 2)).toBe(
      "This moves the application to Offer. The offer link is emailed to 2 addresses now.",
    );
    expect(sendConfirmBody("reset", 1)).toContain("emailed to 1 address now.");
    expect(sendConfirmBody("reset", 1)).toContain("Any earlier link stops working at once");
    expect(sendConfirmBody("resend", 3)).toContain("The respond by date stays the same.");
    expect(sendConfirmBody("resend", 3)).toContain("3 addresses now");
  });

  it("says plainly when nobody will be emailed", () => {
    for (const kind of ["generate", "reset", "resend"] as const)
      expect(sendConfirmBody(kind, 0)).toContain("no email is sent");
    expect(sendDone("generate", 0)).toContain("No email was sent");
    expect(sendDone("resend", 2)).toBe(
      "New link queued. The link is being emailed to 2 addresses.",
    );
    expect(addresses(1)).toBe("1 address");
  });

  it("states the 3 a day limit and adds the withdrawal hint only to that refusal", () => {
    expect(OFFER_SEND_LIMIT_NOTE).toContain("at most 3 times in 24 hours");
    expect(sendErrorMessage("offer_link_limit", "Limit reached.")).toBe(
      `Limit reached. ${OFFER_LIMIT_HINT}`,
    );
    expect(sendErrorMessage(null, "Application not found")).toBe("Application not found");
  });
});

describe("the link emails", () => {
  const now = Date.parse("2026-10-23T10:00:00Z");
  it("explains a link still waiting after 10 minutes, and only then", () => {
    expect(
      offerWaitingNote([{ status: "pending", createdAt: "2026-10-23T09:55:00Z" }], now, true),
    ).toBeNull();
    expect(
      offerWaitingNote([{ status: "pending", createdAt: "2026-10-23T09:45:00Z" }], now, false),
    ).toContain("Email sending may be switched off, or today's email limit may have been reached");
    expect(
      offerWaitingNote([{ status: "sent", createdAt: "2026-10-22T09:00:00Z" }], now, true),
    ).toBeNull();
    expect(offerWaitingNote([], now, true)).toBeNull();
  });

  it("mentions an earlier link only after a reset or a resend", () => {
    const old = [{ status: "pending", createdAt: "2026-10-23T09:45:00Z" }];
    expect(offerWaitingNote(old, now, false)).not.toContain("earlier link");
    expect(offerWaitingNote(old, now, true)).toContain(
      "The earlier link has already stopped working",
    );
  });

  it("labels every status and the response source", () => {
    for (const s of ["pending", "sending", "sent", "failed", "expired"])
      expect(OFFER_EMAIL_STATUS_LABELS[s]).toBeTruthy();
    expect(responseSourceLabel("offer_link")).toBe("through the offer link");
    expect(responseSourceLabel("staff")).toBe("recorded by staff");
    expect(responseSourceLabel(null)).toBeNull();
  });
});

describe("corrections (D-11j)", () => {
  it("says what happens to the stage in each direction", () => {
    expect(correctionBody("declined")).toContain("moves the application to Offer declined");
    expect(correctionBody("accepted")).toContain("moves the application back to Offer");
  });

  it("needs a reason of 1 to 300 characters on one line, as the database does", () => {
    expect(correctionReasonProblem("  ")).toBe("Give a short reason.");
    expect(correctionReasonProblem("x".repeat(301))).toContain("300");
    expect(correctionReasonProblem("a\tb")).toBe("Keep the reason on one line.");
    expect(correctionReasonProblem("Parent phoned: wrong button")).toBeNull();
  });
});

describe("no dashes", () => {
  it("in any panel wording", () => {
    for (const s of [
      OFFER_SEND_LIMIT_NOTE,
      OFFER_LIMIT_HINT,
      ...Object.values(OFFER_EMAIL_STATUS_LABELS),
      sendConfirmBody("generate", 0),
      sendConfirmBody("reset", 2),
      sendConfirmBody("resend", 1),
      sendDone("reset", 1),
      offerWaitingNote(
        [{ status: "pending", createdAt: "2026-01-01T00:00:00Z" }],
        Date.now(),
        true,
      ) ?? "",
      correctionBody("accepted"),
      correctionBody("declined"),
    ])
      expect(s).not.toMatch(DASHES);
  });
});
