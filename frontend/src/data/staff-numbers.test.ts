import { describe, expect, it } from "vitest";

import {
  STAFF_ID_MISSING_MESSAGE,
  canCorrectStaffNumber,
  classForPosition,
  compactStaffNumber,
  currentStaffNumber,
  payslipStaffIdRow,
  staffClassLabel,
  staffIdMergeValue,
  staffNumberDisplay,
  staffNumberHistory,
  staffNumberMatches,
  templateUsesStaffId,
  unmappedPositionMessage,
  type StaffNumber,
} from "@/data/staff-numbers";

const n = (over: Partial<StaffNumber>): StaffNumber => ({
  number: "ST26-02002",
  employeeId: "e1",
  year: 2026,
  classCode: "02",
  roll: 2,
  issuedAt: "2026-03-01T09:00:00Z",
  retiredAt: null,
  retireReason: null,
  replacedBy: null,
  ...over,
});

const corrected = [
  n({
    number: "ST26-01002",
    classCode: "01",
    retiredAt: "2026-04-01T09:00:00Z",
    replacedBy: "ST26-02007",
  }),
  n({ number: "ST26-02007", roll: 7, issuedAt: "2026-04-01T09:00:00Z" }),
  n({ number: "ST26-05003", employeeId: "e2", classCode: "05", roll: 3 }),
];

describe("display", () => {
  it("shows the current ID, or Not issued", () => {
    expect(staffNumberDisplay(currentStaffNumber(corrected, "e1"))).toBe("ST26-02007");
    expect(staffNumberDisplay(currentStaffNumber(corrected, "nobody"))).toBe("Not issued");
    expect(staffNumberDisplay(null)).toBe("Not issued");
  });

  it("lists history newest first, retired included", () => {
    expect(staffNumberHistory(corrected, "e1").map((x) => x.number)).toEqual([
      "ST26-02007",
      "ST26-01002",
    ]);
  });

  it("labels the five classes", () => {
    expect(staffClassLabel("01")).toBe("Admin");
    expect(staffClassLabel("05")).toBe("Transport");
    expect(staffClassLabel(null)).toBe("No class");
  });

  it("offers a correction once, only for Active or Suspended with a current ID", () => {
    expect(canCorrectStaffNumber(corrected, "e2", "Active")).toBe(true);
    expect(canCorrectStaffNumber(corrected, "e2", "Suspended")).toBe(true);
    expect(canCorrectStaffNumber(corrected, "e1", "Active")).toBe(false);
    expect(canCorrectStaffNumber(corrected, "e2", "Pending Approval")).toBe(false);
    expect(canCorrectStaffNumber(corrected, "nobody", "Active")).toBe(false);
  });
});

describe("search parsing", () => {
  it("ignores case and separators", () => {
    expect(compactStaffNumber(" st26-02 002 ")).toBe("ST2602002");
    for (const q of ["ST26-02002", "st2602002", "st26 02002", "26-02002", "02002", "ST26"]) {
      expect(staffNumberMatches("ST26-02002", q)).toBe(true);
    }
  });

  it("doesn't match other IDs, missing IDs or an empty query", () => {
    expect(staffNumberMatches("ST26-02002", "ST27")).toBe(false);
    expect(staffNumberMatches("ST26-02002", "02003")).toBe(false);
    expect(staffNumberMatches(null, "ST26")).toBe(false);
    expect(staffNumberMatches("ST26-02002", "")).toBe(false);
    expect(staffNumberMatches("ST26-02002", " - ")).toBe(false);
  });
});

describe("{{staff_id}} merge field", () => {
  const withField = "<p>Staff ID: {{staff_id}}</p>";
  const without = "<p>Dear {{employee_name}}</p>";

  it("detects the field", () => {
    expect(templateUsesStaffId(withField)).toBe(true);
    expect(templateUsesStaffId(without)).toBe(false);
    expect(templateUsesStaffId("{{ staff_id }}")).toBe(false);
  });

  it("refuses a template that uses it when there's no current ID, with no placeholder", () => {
    expect(staffIdMergeValue(withField, undefined)).toEqual({
      ok: false,
      message: STAFF_ID_MISSING_MESSAGE,
    });
    expect(STAFF_ID_MISSING_MESSAGE).toBe("Approve this employee first so a staff ID exists");
  });

  it("uses the current ID, never a retired one", () => {
    expect(staffIdMergeValue(withField, currentStaffNumber(corrected, "e1"))).toEqual({
      ok: true,
      value: "ST26-02007",
    });
  });

  it("doesn't block a template that doesn't use it", () => {
    expect(staffIdMergeValue(without, undefined)).toEqual({ ok: true, value: null });
  });
});

describe("payslip", () => {
  it("shows the current ID at display time", () => {
    expect(payslipStaffIdRow(currentStaffNumber(corrected, "e1"))).toEqual([
      "Staff ID",
      "ST26-02007",
    ]);
    expect(payslipStaffIdRow(undefined)).toEqual(["Staff ID", "Not issued"]);
  });
});

describe("positions", () => {
  const positions = [
    { name: "DRIVER", staffClass: "05" },
    { name: "PORTER", staffClass: null },
  ];

  it("finds the class by exact name", () => {
    expect(classForPosition(positions, "DRIVER")).toBe("05");
    expect(classForPosition(positions, "Driver")).toBeNull();
    expect(classForPosition(positions, "PORTER")).toBeNull();
    expect(classForPosition(positions, null)).toBeNull();
  });

  it("words the unmapped refusal as the database does", () => {
    expect(unmappedPositionMessage("PORTER")).toBe(
      "Set a classification for position PORTER first.",
    );
    expect(unmappedPositionMessage(null)).toBe(
      "Set a classification for position (no position) first.",
    );
  });
});
