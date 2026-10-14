import { describe, expect, it } from "vitest";

import {
  OFFICE_MESSAGE,
  buildInquiryPayload,
  cleanPhone,
  emptyDraft,
  formAvailable,
  gradesForCampus,
  interpretSubmitResponse,
  parsePublicOptions,
  todayInAccra,
  validateInquiry,
  withCampus,
  type InquiryDraft,
  type PublicOptions,
} from "@/modules/admissions/inquiry-form";

const RAW = {
  intake_open: true,
  grades: [
    { id: "g-pn", name: "Pre Nursery", position: 1 },
    { id: "g-n1", name: "Nursery 1", position: 2 },
    { id: "g-1", name: "Grade 1", position: 6 },
  ],
  campuses: [
    { id: "c-annex", name: "Annex", accepted_grade_ids: ["g-pn", "g-n1"] },
    { id: "c-main", name: "Main", accepted_grade_ids: ["g-pn", "g-n1", "g-1"] },
  ],
  academic_years: ["2026/2027", "2027/2028"],
};
const OPTIONS: PublicOptions = parsePublicOptions(RAW);
const TODAY = "2026-10-14";

function validDraft(): InquiryDraft {
  return {
    referralSource: "website",
    referralSourceOther: "",
    comments: "",
    guardians: [
      {
        surname: " Mensah ",
        firstName: "Ama",
        relationship: "mother",
        religion: "Christian",
        address: "1 Ring Road",
        townCity: "Accra",
        phone: "+233551794822",
        email: "ama@example.com",
      },
    ],
    students: [
      {
        fullName: "Kofi Mensah",
        dateOfBirth: "2019-02-03",
        currentSchool: "N/A",
        currentGrade: "KG 2",
        gradeId: "g-1",
        academicYear: "2026/2027",
        campusId: "",
        month: "September",
        monthOther: "",
      },
    ],
  };
}

describe("parsePublicOptions", () => {
  it("maps the RPC's jsonb", () => {
    expect(OPTIONS.intakeOpen).toBe(true);
    expect(OPTIONS.grades.map((g) => g.name)).toEqual(["Pre Nursery", "Nursery 1", "Grade 1"]);
    expect(OPTIONS.campuses[0]).toEqual({
      id: "c-annex",
      name: "Annex",
      acceptedGradeIds: ["g-pn", "g-n1"],
    });
    expect(OPTIONS.academicYears).toEqual(["2026/2027", "2027/2028"]);
  });

  it("reads anything malformed as closed with nothing to choose", () => {
    for (const raw of [null, "x", [], { intake_open: "true" }]) {
      const o = parsePublicOptions(raw);
      expect(o.intakeOpen).toBe(false);
      expect(formAvailable(o)).toBe(false);
    }
    const partial = parsePublicOptions({
      intake_open: true,
      grades: [
        { id: 1, name: "x", position: 1 },
        { id: "ok", name: "OK", position: 2 },
      ],
      campuses: [{ id: "c", name: "C" }],
      academic_years: ["2026/2027", 7],
    });
    expect(partial.grades.map((g) => g.id)).toEqual(["ok"]);
    expect(partial.campuses).toEqual([]);
    expect(partial.academicYears).toEqual(["2026/2027"]);
  });
});

describe("formAvailable", () => {
  it("needs intake open and something to choose", () => {
    expect(formAvailable(OPTIONS)).toBe(true);
    expect(formAvailable({ ...OPTIONS, intakeOpen: false })).toBe(false);
    expect(formAvailable({ ...OPTIONS, grades: [] })).toBe(false);
    expect(formAvailable({ ...OPTIONS, academicYears: [] })).toBe(false);
  });
});

describe("gradesForCampus and withCampus", () => {
  it("narrows grades to the campus, or all with no campus", () => {
    expect(gradesForCampus(OPTIONS, "").length).toBe(3);
    expect(gradesForCampus(OPTIONS, "c-annex").map((g) => g.id)).toEqual(["g-pn", "g-n1"]);
    expect(gradesForCampus(OPTIONS, "c-unknown")).toEqual([]);
  });

  it("drops a grade the new campus doesn't take, keeps one it does", () => {
    const s = validDraft().students[0];
    expect(withCampus(s, "c-annex", OPTIONS).gradeId).toBe("");
    expect(withCampus({ ...s, gradeId: "g-n1" }, "c-annex", OPTIONS).gradeId).toBe("g-n1");
    expect(withCampus(s, "c-main", OPTIONS).gradeId).toBe("g-1");
  });
});

describe("validateInquiry", () => {
  it("passes a complete draft", () => {
    expect(validateInquiry(validDraft(), OPTIONS, TODAY)).toEqual({});
  });

  it("flags an empty draft field by field", () => {
    const errors = validateInquiry(emptyDraft(), OPTIONS, TODAY);
    for (const key of [
      "referralSource",
      "guardians.0.surname",
      "guardians.0.relationship",
      "guardians.0.phone",
      "guardians.0.email",
      "students.0.fullName",
      "students.0.dateOfBirth",
      "students.0.gradeId",
      "students.0.academicYear",
      "students.0.month",
    ]) {
      expect(errors[key]).toBeTruthy();
    }
  });

  it("applies the phone rule: a plus sign and 8 to 15 digits after cleaning", () => {
    const phoneError = (phone: string) => {
      const d = validDraft();
      d.guardians[0].phone = phone;
      return validateInquiry(d, OPTIONS, TODAY)["guardians.0.phone"];
    };
    expect(phoneError("+1234567")).toBeTruthy(); // 7 digits
    expect(phoneError("+12345678")).toBeUndefined(); // 8 digits
    expect(phoneError("+123456789012345")).toBeUndefined(); // 15 digits
    expect(phoneError("+1234567890123456")).toBeTruthy(); // 16 digits
    expect(phoneError("+233 55-179 4822")).toBeUndefined(); // spaces and dashes
    expect(phoneError("0551794822")).toBeTruthy(); // missing plus
    expect(phoneError("+233551ABC822")).toBeTruthy(); // letters
  });

  it("cleans the phone before sending it", () => {
    expect(cleanPhone(" +233 55-179 4822 ")).toBe("+233551794822");
    const d = validDraft();
    d.guardians[0].phone = "+44 20-7946 0958";
    const g = (buildInquiryPayload(d).guardians as Record<string, unknown>[])[0];
    expect(g.phone).toBe("+442079460958");
  });

  it("refuses a grade, year or campus not in the lists", () => {
    const d = validDraft();
    d.students[0].gradeId = "Grade 1";
    d.students[0].academicYear = "2099/2100";
    d.students[0].campusId = "Main";
    const errors = validateInquiry(d, OPTIONS, TODAY);
    expect(errors["students.0.gradeId"]).toBeTruthy();
    expect(errors["students.0.academicYear"]).toBeTruthy();
    expect(errors["students.0.campusId"]).toBeTruthy();
  });

  it("refuses a grade the chosen campus doesn't take", () => {
    const d = validDraft();
    d.students[0].campusId = "c-annex";
    expect(validateInquiry(d, OPTIONS, TODAY)["students.0.gradeId"]).toBeTruthy();
  });

  it("refuses a future or malformed date of birth", () => {
    for (const dob of ["2026-10-15", "03/02/2019", "", "1899-12-31"]) {
      const d = validDraft();
      d.students[0].dateOfBirth = dob;
      expect(validateInquiry(d, OPTIONS, TODAY)["students.0.dateOfBirth"]).toBeTruthy();
    }
  });

  it("needs the other text when Other is chosen", () => {
    const d = validDraft();
    d.referralSource = "other";
    d.students[0].month = "other";
    const errors = validateInquiry(d, OPTIONS, TODAY);
    expect(errors.referralSourceOther).toBeTruthy();
    expect(errors["students.0.monthOther"]).toBeTruthy();
  });

  it("caps guardians at two and children at five", () => {
    const d = validDraft();
    d.guardians = [d.guardians[0], d.guardians[0], d.guardians[0]];
    d.students = Array.from({ length: 6 }, () => validDraft().students[0]);
    const errors = validateInquiry(d, OPTIONS, TODAY);
    expect(errors.guardians).toBeTruthy();
    expect(errors.students).toBeTruthy();
  });
});

describe("buildInquiryPayload", () => {
  it("sends exactly the keys submit_inquiry accepts, trimmed, ids only", () => {
    const p = buildInquiryPayload(validDraft());
    expect(Object.keys(p).sort()).toEqual(["guardians", "referral_source", "students"]);
    const g = (p.guardians as Record<string, unknown>[])[0];
    expect(Object.keys(g).sort()).toEqual([
      "address",
      "email",
      "first_name",
      "phone",
      "relationship",
      "religion",
      "surname",
      "town_city",
    ]);
    expect(g.surname).toBe("Mensah");
    const s = (p.students as Record<string, unknown>[])[0];
    expect(Object.keys(s).sort()).toEqual([
      "academic_year",
      "current_grade",
      "current_school",
      "date_of_birth",
      "full_name",
      "grade_id",
      "month_of_enrollment",
    ]);
    expect(s.grade_id).toBe("g-1");
    expect(s).not.toHaveProperty("year_group_applied_for");
  });

  it("adds campus, other referral, other month and comments only when set", () => {
    const d = validDraft();
    d.students[0].campusId = "c-main";
    d.students[0].month = "other";
    d.students[0].monthOther = " April ";
    d.referralSource = "other";
    d.referralSourceOther = " Radio ";
    d.comments = " Hello ";
    const p = buildInquiryPayload(d);
    const s = (p.students as Record<string, unknown>[])[0];
    expect(s.campus_id).toBe("c-main");
    expect(s.month_of_enrollment).toBe("April");
    expect(p.referral_source_other).toBe("Radio");
    expect(p.comments).toBe("Hello");
  });

  it("drops stale other text when Other isn't chosen", () => {
    const d = validDraft();
    d.referralSourceOther = "left over";
    expect(buildInquiryPayload(d)).not.toHaveProperty("referral_source_other");
  });
});

describe("interpretSubmitResponse", () => {
  it("reads a success as the references", () => {
    expect(interpretSubmitResponse(200, { references: ["INQ-2026-0001"] })).toEqual({
      kind: "created",
      references: ["INQ-2026-0001"],
    });
  });

  it("never treats a malformed 200 as a success", () => {
    for (const body of [null, {}, { references: [] }, { references: [1] }]) {
      expect(interpretSubmitResponse(200, body).kind).toBe("refused");
    }
  });

  it("maps closed, refusals, and network failure", () => {
    expect(interpretSubmitResponse(409, { error: "closed" })).toEqual({
      kind: "closed",
      message: "closed",
    });
    expect(interpretSubmitResponse(429, { error: "call the office" })).toEqual({
      kind: "refused",
      message: "call the office",
    });
    expect(interpretSubmitResponse(0, null)).toEqual({ kind: "refused", message: OFFICE_MESSAGE });
    expect(interpretSubmitResponse(403, { error: "Origin not allowed" })).toEqual({
      kind: "refused",
      message: OFFICE_MESSAGE,
    });
  });
});

describe("todayInAccra", () => {
  it("is the UTC date", () => {
    expect(todayInAccra(new Date("2026-10-14T23:30:00Z"))).toBe("2026-10-14");
  });
});
