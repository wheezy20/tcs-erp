import { describe, expect, it } from "vitest";

import {
  canEditAdmissionsSettings,
  canViewAdmissionsSettings,
} from "@/modules/admissions/permissions";
import {
  campusGradeSummary,
  capacityYearOptions,
  parseWholeNumber,
  yearStatus,
} from "@/modules/admissions/settings-rules";

const years = [
  { label: "2026/2027", isActive: true },
  { label: "2027/2028", isActive: false },
];

describe("settings access", () => {
  it("is Manager and Auditor only", () => {
    expect(canViewAdmissionsSettings("Manager")).toBe(true);
    expect(canViewAdmissionsSettings("Auditor")).toBe(true);
    for (const r of ["Admissions Officer", "Attendant", "Accountant", undefined, null] as const) {
      expect(canViewAdmissionsSettings(r)).toBe(false);
    }
  });

  it("lets only a Manager edit", () => {
    expect(canEditAdmissionsSettings("Manager")).toBe(true);
    for (const r of [
      "Auditor",
      "Admissions Officer",
      "Attendant",
      "Accountant",
      undefined,
    ] as const) {
      expect(canEditAdmissionsSettings(r)).toBe(false);
    }
  });
});

describe("yearStatus", () => {
  it("flags active, retired and unlisted years by exact text", () => {
    expect(yearStatus("2026/2027", years)).toBe("active");
    expect(yearStatus("2027/2028", years)).toBe("retired");
    expect(yearStatus("2019/2020", years)).toBe("unlisted");
    expect(yearStatus(" 2026/2027", years)).toBe("unlisted");
  });
});

describe("capacityYearOptions", () => {
  it("offers active years only, in list order", () => {
    expect(capacityYearOptions(years)).toEqual(["2026/2027"]);
    expect(capacityYearOptions([])).toEqual([]);
  });
});

describe("parseWholeNumber", () => {
  it("accepts digits only", () => {
    expect(parseWholeNumber("0")).toBe(0);
    expect(parseWholeNumber(" 14 ")).toBe(14);
    expect(parseWholeNumber("100001")).toBe(100001);
    for (const t of ["", " ", "-1", "1.5", "1e3", "abc", "1,000", "0x10", "1234567890"]) {
      expect(parseWholeNumber(t)).toBeNull();
    }
  });
});

describe("campusGradeSummary", () => {
  const campuses = [
    { id: "main", name: "Main" },
    { id: "annex", name: "Annex" },
  ];
  const grades = [
    { id: "g2", name: "Nursery", position: 2 },
    { id: "g1", name: "Pre Nursery", position: 1 },
  ];

  it("shows every grade for a campus without rules, and the listed ones in order otherwise", () => {
    const rules = [
      { branchId: "annex", gradeId: "g2" },
      { branchId: "annex", gradeId: "g1" },
    ];
    expect(campusGradeSummary(campuses, rules, grades)).toEqual([
      { campusId: "main", campusName: "Main", grades: null },
      { campusId: "annex", campusName: "Annex", grades: ["Pre Nursery", "Nursery"] },
    ]);
  });

  it("never turns a rule for an unknown grade into 'every grade'", () => {
    const rules = [{ branchId: "annex", gradeId: "gone" }];
    expect(campusGradeSummary(campuses, rules, grades)[1].grades).toEqual(["1 unknown grade(s)"]);
  });
});
