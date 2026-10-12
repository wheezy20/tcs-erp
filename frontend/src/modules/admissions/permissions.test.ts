import { describe, expect, it } from "vitest";

import type { StaffRole } from "@/data/auth-store";
import {
  canAddNote,
  canEditNote,
  canMoveToDocumentReview,
  canSeeUnbandedGrades,
  canViewAdmissions,
  canWriteAdmissions,
  documentStatusTargets,
  emptyListMessage,
  gradeFilterOptions,
  healthPanelState,
  isAdmissionsReadOnly,
  isApplicationId,
  officerHasNoScope,
  stageChangeTargets,
  type HealthCapability,
  type HealthFetch,
} from "@/modules/admissions/permissions";
import { STAGES } from "@/modules/admissions/labels";

const ROLES: StaffRole[] = ["Attendant", "Manager", "Accountant", "Auditor", "Admissions Officer"];
const BANDED = { gradeBands: ["primary"], allGrades: false };
const ALL = { gradeBands: [], allGrades: true };
const NONE = { gradeBands: [], allGrades: false };

describe("route guard", () => {
  it("opens admissions to Manager, Auditor and Admissions Officer only", () => {
    expect(ROLES.filter((r) => canViewAdmissions(r))).toEqual([
      "Manager",
      "Auditor",
      "Admissions Officer",
    ]);
  });

  it("closes admissions to a missing role", () => {
    expect(canViewAdmissions(undefined)).toBe(false);
    expect(canViewAdmissions(null)).toBe(false);
  });
});

describe("Auditor is read-only", () => {
  it("is flagged read-only and offered no write control in any stage or status", () => {
    expect(isAdmissionsReadOnly("Auditor")).toBe(true);
    expect(canWriteAdmissions("Auditor")).toBe(false);
    expect(canAddNote("Auditor")).toBe(false);
    expect(canEditNote("Auditor", "me", "me")).toBe(false);
    for (const stage of STAGES) {
      expect(canMoveToDocumentReview("Auditor", stage)).toBe(false);
      expect(stageChangeTargets("Auditor", stage)).toEqual([]);
    }
    for (const status of ["required", "pending_review", "approved", "rejected"]) {
      expect(documentStatusTargets("Auditor", status)).toEqual([]);
    }
  });

  it("gives Attendant and Accountant no write control either", () => {
    for (const role of ["Attendant", "Accountant"] as StaffRole[]) {
      expect(canWriteAdmissions(role)).toBe(false);
      expect(canMoveToDocumentReview(role, "inquiry")).toBe(false);
      expect(documentStatusTargets(role, "pending_review")).toEqual([]);
    }
  });
});

describe("write controls", () => {
  it("offers Move to Document Review from inquiry and application only", () => {
    for (const role of ["Manager", "Admissions Officer"] as StaffRole[]) {
      expect(STAGES.filter((s) => canMoveToDocumentReview(role, s))).toEqual([
        "inquiry",
        "application",
      ]);
    }
  });

  it("offers a direct stage change to a Manager only, never from offer or enrolled", () => {
    expect(stageChangeTargets("Admissions Officer", "application")).toEqual([]);
    expect(stageChangeTargets("Manager", "offer")).toEqual([]);
    expect(stageChangeTargets("Manager", "enrolled")).toEqual([]);
    expect(stageChangeTargets("Manager", "application")).toEqual([
      "document_review",
      "waitlisted",
      "rejected",
    ]);
    expect(stageChangeTargets("Manager", "inquiry")).not.toContain("inquiry");
  });

  it("lets only the author edit a note", () => {
    expect(canEditNote("Admissions Officer", "a", "a")).toBe(true);
    expect(canEditNote("Admissions Officer", "a", "b")).toBe(false);
    expect(canEditNote("Manager", null, "a")).toBe(false);
  });

  it("never offers a status change on a document with no file", () => {
    expect(documentStatusTargets("Manager", "required")).toEqual([]);
    expect(documentStatusTargets("Manager", "pending_review")).toEqual(["approved", "rejected"]);
  });
});

describe("health panel", () => {
  const caps: HealthCapability[] = ["checking", "error", "denied"];
  const fetches: HealthFetch[] = ["loading", "error", "none", "row"];

  it("renders nothing at all unless the live capability check returned true", () => {
    for (const cap of caps) {
      for (const fetch of fetches) {
        expect(healthPanelState(cap, fetch)).toBe("hidden");
      }
    }
  });

  it("says 'no health information' only to a holder whose read found no row", () => {
    expect(healthPanelState("granted", "none")).toBe("empty");
    expect(healthPanelState("granted", "error")).toBe("error");
    expect(healthPanelState("granted", "loading")).toBe("loading");
    expect(healthPanelState("granted", "row")).toBe("answers");
  });
});

describe("grade filters", () => {
  const grades = [
    { name: "Nursery 1", band: "preschool" },
    { name: "Grade 3", band: "primary" },
    { name: "Grade 8", band: "jhs" },
  ];

  it("offers the unbanded option to Manager, Auditor and all_grades officers only", () => {
    expect(canSeeUnbandedGrades("Manager", undefined)).toBe(true);
    expect(canSeeUnbandedGrades("Auditor", undefined)).toBe(true);
    expect(canSeeUnbandedGrades("Admissions Officer", ALL)).toBe(true);
    expect(canSeeUnbandedGrades("Admissions Officer", BANDED)).toBe(false);
    expect(canSeeUnbandedGrades("Admissions Officer", undefined)).toBe(false);
    expect(canSeeUnbandedGrades("Attendant", undefined)).toBe(false);
  });

  it("limits a banded officer's grade options to their bands", () => {
    expect(gradeFilterOptions("Admissions Officer", BANDED, grades).map((g) => g.name)).toEqual([
      "Grade 3",
    ]);
    expect(gradeFilterOptions("Admissions Officer", ALL, grades)).toHaveLength(3);
    expect(gradeFilterOptions("Manager", undefined, grades)).toHaveLength(3);
    expect(gradeFilterOptions("Accountant", ALL, grades)).toEqual([]);
  });

  it("explains an empty list to an officer with no grade scope", () => {
    expect(officerHasNoScope("Admissions Officer", undefined)).toBe(true);
    expect(officerHasNoScope("Admissions Officer", NONE)).toBe(true);
    expect(officerHasNoScope("Admissions Officer", BANDED)).toBe(false);
    expect(officerHasNoScope("Manager", undefined)).toBe(false);
  });
});

describe("detail route id", () => {
  it("treats a malformed id as not found without querying", () => {
    expect(isApplicationId("d7a00000-0000-4000-8000-000400000001")).toBe(true);
    expect(isApplicationId("not-a-uuid")).toBe(false);
    expect(isApplicationId("d7a00000-0000-4000-8000-000400000001x")).toBe(false);
    expect(isApplicationId("")).toBe(false);
  });
});

describe("empty list message", () => {
  it("tells an officer about assigned grades without hinting at other applications", () => {
    const msg = emptyListMessage("Admissions Officer", false);
    expect(msg).toBe(
      "No applications in your assigned grades. A Manager sets your admissions access in Settings.",
    );
    expect(msg).not.toMatch(/\d/);
    expect(msg).not.toMatch(/other|outside|hidden/i);
  });

  it("keeps the plain messages for other roles and for a filtered list", () => {
    expect(emptyListMessage("Manager", false)).toBe("No applications yet.");
    expect(emptyListMessage("Auditor", false)).toBe("No applications yet.");
    expect(emptyListMessage("Admissions Officer", true)).toBe("No applications match.");
  });
});
