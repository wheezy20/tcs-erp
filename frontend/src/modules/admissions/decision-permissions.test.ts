import { describe, expect, it } from "vitest";

import type { StaffRole } from "@/data/auth-store";
import {
  canCorrectGrade,
  canGenerateOffer,
  canRecordDecision,
  canRecordOfferResponse,
  canResetOffer,
  decisionChangeTargets,
  documentsNotApproved,
  enrolState,
  offerLink,
  type DecideCapability,
} from "@/modules/admissions/permissions";
import { STAGES } from "@/modules/admissions/labels";

const ROLES: StaffRole[] = ["Attendant", "Manager", "Accountant", "Auditor", "Admissions Officer"];
const CAPS: DecideCapability[] = ["checking", "error", "granted", "denied"];
const PENDING = { response: "pending", effectiveResponse: "pending" };
const EXPIRED = { response: "pending", effectiveResponse: "expired" };
const ACCEPTED = { response: "accepted", effectiveResponse: "accepted" };
const DECLINED = { response: "declined", effectiveResponse: "declined" };
const WITHDRAWN = { response: "withdrawn", effectiveResponse: "withdrawn" };

describe("decide capability", () => {
  it("offers decision and offer controls only to writers whose check came back granted", () => {
    for (const role of ROLES) {
      for (const cap of CAPS) {
        const expected = cap === "granted" && (role === "Manager" || role === "Admissions Officer");
        expect(canRecordDecision(role, cap, "application", null)).toBe(expected);
        expect(decisionChangeTargets(role, cap, "application", "waitlisted", null).length > 0).toBe(
          expected,
        );
        expect(canGenerateOffer(role, cap, "application", "accepted", null)).toBe(expected);
        expect(canResetOffer(role, cap, "offer", "accepted", PENDING)).toBe(expected);
        expect(canRecordOfferResponse(role, cap, "offer", "accepted", PENDING)).toBe(expected);
      }
    }
  });
});

describe("decisions", () => {
  it("records only when there is no decision, never at inquiry or enrolled", () => {
    const ok = STAGES.filter((s) => canRecordDecision("Manager", "granted", s, null));
    expect(ok).not.toContain("inquiry");
    expect(ok).not.toContain("enrolled");
    expect(ok).toContain("offer_declined");
    expect(canRecordDecision("Manager", "granted", "application", "accepted")).toBe(false);
  });

  it("changes only an existing decision, and only a notes edit once the parent accepted", () => {
    expect(decisionChangeTargets("Manager", "granted", "application", null, null)).toEqual([]);
    expect(decisionChangeTargets("Manager", "granted", "enrolled", "accepted", "accepted")).toEqual(
      [],
    );
    expect(decisionChangeTargets("Manager", "granted", "offer", "accepted", "accepted")).toEqual([
      "accepted",
    ]);
    expect(decisionChangeTargets("Manager", "granted", "offer", "accepted", "pending")).toEqual([
      "accepted",
      "waitlisted",
      "rejected",
    ]);
  });
});

describe("offers", () => {
  it("generates only with an accepted decision, no offer, and an allowed stage", () => {
    expect(canGenerateOffer("Manager", "granted", "document_review", "accepted", null)).toBe(true);
    expect(canGenerateOffer("Manager", "granted", "document_review", "waitlisted", null)).toBe(
      false,
    );
    expect(canGenerateOffer("Manager", "granted", "offer", "accepted", PENDING)).toBe(false);
    expect(canGenerateOffer("Manager", "granted", "inquiry", "accepted", null)).toBe(false);
    expect(canGenerateOffer("Manager", "granted", "offer_declined", "accepted", null)).toBe(false);
  });

  it("resets any offer the parent hasn't accepted, never an accepted one", () => {
    for (const offer of [PENDING, EXPIRED, DECLINED, WITHDRAWN]) {
      expect(canResetOffer("Manager", "granted", "offer", "accepted", offer)).toBe(true);
    }
    expect(canResetOffer("Manager", "granted", "offer", "accepted", ACCEPTED)).toBe(false);
    expect(canResetOffer("Manager", "granted", "offer", "accepted", null)).toBe(false);
    expect(canResetOffer("Manager", "granted", "offer", "rejected", PENDING)).toBe(false);
    expect(canResetOffer("Manager", "granted", "enrolled", "accepted", PENDING)).toBe(false);
  });

  it("records a response only for a pending, in-date offer at offer", () => {
    expect(canRecordOfferResponse("Manager", "granted", "offer", "accepted", EXPIRED)).toBe(false);
    expect(canRecordOfferResponse("Manager", "granted", "offer", "accepted", ACCEPTED)).toBe(false);
    expect(
      canRecordOfferResponse("Manager", "granted", "offer_declined", "accepted", PENDING),
    ).toBe(false);
  });

  it("builds the parent link at TCS OS's path with the token as given", () => {
    expect(offerLink("https://example.test", "ab12")).toBe("https://example.test/offer?token=ab12");
  });
});

describe("enrolment and grade correction", () => {
  it("offers Mark enrolled to a Manager only, at offer with an accepted offer", () => {
    for (const role of ROLES) {
      expect(enrolState(role, "offer", "accepted", ACCEPTED, "primary")).toBe(
        role === "Manager" ? "available" : "hidden",
      );
    }
    expect(enrolState("Manager", "offer", "accepted", PENDING, "primary")).toBe("hidden");
    expect(enrolState("Manager", "offer_declined", "accepted", ACCEPTED, "primary")).toBe("hidden");
    expect(enrolState("Manager", "offer", "rejected", ACCEPTED, "primary")).toBe("hidden");
  });

  it("blocks Mark enrolled when the grade has no band", () => {
    expect(enrolState("Manager", "offer", "accepted", ACCEPTED, null)).toBe("blocked_by_grade");
  });

  it("offers grade correction to a Manager only, for an unbanded grade, before enrolment", () => {
    for (const role of ROLES) {
      expect(canCorrectGrade(role, "offer", null)).toBe(role === "Manager");
    }
    expect(canCorrectGrade("Manager", "offer", "primary")).toBe(false);
    expect(canCorrectGrade("Manager", "enrolled", null)).toBe(false);
  });

  it("warns about every document that isn't approved", () => {
    const docs = [
      { id: "a", status: "approved" },
      { id: "b", status: "required" },
      { id: "c", status: "pending_review" },
      { id: "d", status: "rejected" },
    ];
    expect(documentsNotApproved(docs).map((d) => d.id)).toEqual(["b", "c", "d"]);
    expect(documentsNotApproved([])).toEqual([]);
  });
});
