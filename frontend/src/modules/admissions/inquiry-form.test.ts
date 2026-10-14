import { describe, expect, it } from "vitest";

import {
  NOT_YET_IN_SCHOOL,
  OFFICE_MESSAGE,
  PHONE_HINT,
  ageHint,
  buildInquiryPayload,
  cleanPhone,
  currentGradeChoices,
  effectiveGuardians,
  maskDateInput,
  parseDmy,
  serverFieldToKey,
  emptyDraft,
  formAvailable,
  gradesForCampus,
  inquiryView,
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
        phone: "+233000000000",
        email: "ama@example.com",
      },
    ],
    students: [
      {
        fullName: "Kofi Mensah",
        dateOfBirth: "03/02/2019",
        currentGrade: "g-pn",
        currentSchool: "Little Stars",
        gradeId: "g-1",
        academicYear: "2026/2027",
        campusId: "",
        month: "September",
      },
    ],
    secondSameAddress: false,
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
    expect(phoneError("+233 00-000 0000")).toBeUndefined(); // spaces and dashes
    expect(phoneError("0000000000")).toBeTruthy(); // missing plus
    expect(phoneError("+233000ABC000")).toBeTruthy(); // letters
  });

  it("cleans the phone before sending it", () => {
    expect(cleanPhone(" +233 00-000 0000 ")).toBe("+233000000000");
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
    for (const dob of ["15/10/2026", "2019-02-03", "", "31/12/1899", "30/02/2019", "3/2/2019"]) {
      const d = validDraft();
      d.students[0].dateOfBirth = dob;
      expect(validateInquiry(d, OPTIONS, TODAY)["students.0.dateOfBirth"]).toBeTruthy();
    }
  });

  it("needs the other text when Other is chosen for how you heard", () => {
    const d = validDraft();
    d.referralSource = "other";
    expect(validateInquiry(d, OPTIONS, TODAY).referralSourceOther).toBeTruthy();
  });

  it("takes religion and month only from their lists", () => {
    for (const religion of ["Christian", "Muslim", "Traditional", "Other", "Prefer not to say"]) {
      const d = validDraft();
      d.guardians[0].religion = religion;
      expect(validateInquiry(d, OPTIONS, TODAY)["guardians.0.religion"]).toBeUndefined();
    }
    const d = validDraft();
    d.guardians[0].religion = "Catholic";
    d.students[0].month = "April";
    const errors = validateInquiry(d, OPTIONS, TODAY);
    expect(errors["guardians.0.religion"]).toBeTruthy();
    expect(errors["students.0.month"]).toBeTruthy();
    d.students[0].month = "January";
    expect(validateInquiry(d, OPTIONS, TODAY)["students.0.month"]).toBeUndefined();
  });

  it("needs a current grade from the list, and a current school unless not yet in school", () => {
    const d = validDraft();
    d.students[0].currentGrade = "KG 2";
    expect(validateInquiry(d, OPTIONS, TODAY)["students.0.currentGrade"]).toBeTruthy();

    d.students[0].currentGrade = NOT_YET_IN_SCHOOL;
    d.students[0].currentSchool = "";
    expect(validateInquiry(d, OPTIONS, TODAY)).toEqual({});

    d.students[0].currentGrade = "g-pn";
    expect(validateInquiry(d, OPTIONS, TODAY)["students.0.currentSchool"]).toBeTruthy();
    d.students[0].currentSchool = "Happy Days Creche";
    expect(validateInquiry(d, OPTIONS, TODAY)).toEqual({});

    d.students[0].currentGrade = "creche_or_daycare";
    expect(validateInquiry(d, OPTIONS, TODAY)["students.0.currentGrade"]).toBeTruthy();
  });

  it("checks guardian 2's address through Same address as above", () => {
    const d = validDraft();
    d.guardians.push({ ...d.guardians[0], address: "", townCity: "" });
    expect(validateInquiry(d, OPTIONS, TODAY)["guardians.1.address"]).toBeTruthy();
    d.secondSameAddress = true;
    expect(validateInquiry(d, OPTIONS, TODAY)).toEqual({});
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
      "current_grade_id",
      "current_school",
      "date_of_birth",
      "full_name",
      "grade_id",
      "month_of_enrollment",
    ]);
    expect(s.grade_id).toBe("g-1");
    expect(s.current_grade_id).toBe("g-pn");
    expect(s.date_of_birth).toBe("2019-02-03");
    expect(s).not.toHaveProperty("year_group_applied_for");
  });

  it("adds campus, other referral and comments only when set", () => {
    const d = validDraft();
    d.students[0].campusId = "c-main";
    d.referralSource = "other";
    d.referralSourceOther = " Radio ";
    d.comments = " Hello ";
    const p = buildInquiryPayload(d);
    const s = (p.students as Record<string, unknown>[])[0];
    expect(s.campus_id).toBe("c-main");
    expect(s.month_of_enrollment).toBe("September");
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

describe("inquiryView with the live get_public_admissions_options response", () => {
  // The exact shape the live site returned (2026-10-14) when /inquiry showed
  // "The inquiry form isn't available": the parser accepts it, so only the
  // build-time site key decides between the form and that screen.
  const LIVE = {
    grades: [
      { id: "53265a8c-ce68-4e72-bd0a-d394c1d2c703", name: "Pre Nursery", position: 1 },
      { id: "28b3e354-32e3-4f2b-b3f9-921fb1ba1a27", name: "Nursery 1", position: 2 },
      { id: "ae62c3bd-0d03-4dee-a9bb-8f79c52145c7", name: "Grade 1", position: 6 },
    ],
    campuses: [
      {
        id: "00000000-0000-0000-0000-000000000002",
        name: "Annex",
        accepted_grade_ids: [
          "53265a8c-ce68-4e72-bd0a-d394c1d2c703",
          "28b3e354-32e3-4f2b-b3f9-921fb1ba1a27",
        ],
      },
      {
        id: "00000000-0000-0000-0000-000000000001",
        name: "Main",
        accepted_grade_ids: [
          "53265a8c-ce68-4e72-bd0a-d394c1d2c703",
          "28b3e354-32e3-4f2b-b3f9-921fb1ba1a27",
          "ae62c3bd-0d03-4dee-a9bb-8f79c52145c7",
        ],
      },
    ],
    intake_open: true,
    academic_years: ["2026/2027", "2027/2028"],
  };
  const base = { loading: false, error: null, created: false, closedAfterSubmit: false };

  it("parses into an open form with every list filled", () => {
    const o = parsePublicOptions(LIVE);
    expect(o.intakeOpen).toBe(true);
    expect(o.grades).toHaveLength(3);
    expect(o.campuses.map((c) => c.acceptedGradeIds.length)).toEqual([2, 3]);
    expect(o.academicYears).toEqual(["2026/2027", "2027/2028"]);
    expect(formAvailable(o)).toBe(true);
  });

  it("shows the form when the site key is built in", () => {
    const options = parsePublicOptions(LIVE);
    expect(inquiryView({ ...base, options, siteKey: "0x4AAAAAAAexample" })).toBe("form");
  });

  it("shows the unavailable screen only when the site key is missing or blank", () => {
    const options = parsePublicOptions(LIVE);
    expect(inquiryView({ ...base, options, siteKey: "" })).toBe("unavailable");
    expect(inquiryView({ ...base, options, siteKey: "  " })).toBe("unavailable");
  });

  it("orders the other screens before the site key check", () => {
    const options = parsePublicOptions(LIVE);
    const key = "0x4AAAAAAAexample";
    expect(inquiryView({ ...base, loading: true, options: undefined, siteKey: key })).toBe(
      "loading",
    );
    expect(inquiryView({ ...base, error: "x", options, siteKey: key })).toBe("loadError");
    expect(inquiryView({ ...base, created: true, options, siteKey: "" })).toBe("created");
    expect(
      inquiryView({
        ...base,
        options: parsePublicOptions({ ...LIVE, intake_open: false }),
        siteKey: key,
      }),
    ).toBe("closed");
  });
});

describe("slice 8b: date of birth, age hint, current grade, address, field errors", () => {
  it("adds slashes as the parent types and keeps digits only", () => {
    expect(maskDateInput("0")).toBe("0");
    expect(maskDateInput("030")).toBe("03/0");
    expect(maskDateInput("03022019")).toBe("03/02/2019");
    expect(maskDateInput("03/02/20199")).toBe("03/02/2019");
    expect(maskDateInput("ab03-02x2019")).toBe("03/02/2019");
  });

  it("converts a real dd/mm/yyyy date to ISO and refuses anything else", () => {
    expect(parseDmy("03/02/2019")).toBe("2019-02-03");
    expect(parseDmy("29/02/2024")).toBe("2024-02-29");
    expect(parseDmy("29/02/2023")).toBeNull();
    expect(parseDmy("31/04/2020")).toBeNull();
    expect(parseDmy("2019-02-03")).toBeNull();
    expect(parseDmy("3/2/2019")).toBeNull();
  });

  it("shows years and months under 5, whole years from 5, and nothing for a bad date", () => {
    expect(ageHint("2024-05-14", TODAY)).toBe("Age today: 2 years 5 months (a guide only)");
    expect(ageHint("2025-10-14", TODAY)).toBe("Age today: 1 year 0 months (a guide only)");
    expect(ageHint("2026-05-20", TODAY)).toBe("Age today: 4 months (a guide only)");
    expect(ageHint("2026-09-14", TODAY)).toBe("Age today: 1 month (a guide only)");
    expect(ageHint("2021-10-15", TODAY)).toBe("Age today: 4 years 11 months (a guide only)");
    expect(ageHint("2021-10-14", TODAY)).toBe("Age today: 5 years (a guide only)");
    expect(ageHint("2016-02-29", TODAY)).toBe("Age today: 10 years (a guide only)");
    expect(ageHint("2026-10-15", TODAY)).toBeNull();
    expect(ageHint(null, TODAY)).toBeNull();
  });

  it("never sends an age", () => {
    const text = JSON.stringify(buildInquiryPayload(validDraft()));
    expect(text).not.toMatch(/age/i);
  });

  it("offers not yet in school, then the active grades, and no creche option", () => {
    expect(currentGradeChoices(OPTIONS)).toEqual([
      { value: NOT_YET_IN_SCHOOL, label: "N/A (not yet in school)" },
      { value: "g-pn", label: "Pre Nursery" },
      { value: "g-n1", label: "Nursery 1" },
      { value: "g-1", label: "Grade 1" },
    ]);
  });

  it("sends prior_schooling without a current school for a child not yet in school", () => {
    const d = validDraft();
    d.students[0].currentGrade = NOT_YET_IN_SCHOOL;
    d.students[0].currentSchool = "typed before switching";
    const s = (buildInquiryPayload(d).students as Record<string, unknown>[])[0];
    expect(s.prior_schooling).toBe(NOT_YET_IN_SCHOOL);
    expect(s).not.toHaveProperty("current_school");
    expect(s).not.toHaveProperty("current_grade_id");
  });

  it("sends a Pre Nursery current grade id and the school for a child at a creche", () => {
    const d = validDraft();
    d.students[0].currentGrade = "g-pn";
    d.students[0].currentSchool = "Happy Days Creche";
    const s = (buildInquiryPayload(d).students as Record<string, unknown>[])[0];
    expect(s.current_grade_id).toBe("g-pn");
    expect(s.current_school).toBe("Happy Days Creche");
    expect(s).not.toHaveProperty("prior_schooling");
  });

  it("copies guardian 1's address to guardian 2 when Same address as above is ticked", () => {
    const d = validDraft();
    d.guardians.push({ ...d.guardians[0], address: "old", townCity: "old" });
    d.secondSameAddress = true;
    expect(effectiveGuardians(d)[1].address).toBe("1 Ring Road");
    const g = (buildInquiryPayload(d).guardians as Record<string, unknown>[])[1];
    expect(g.address).toBe("1 Ring Road");
    expect(g.town_city).toBe("Accra");
  });

  it("maps a server field path to the form's error key", () => {
    expect(serverFieldToKey("guardians.0.town_city")).toBe("guardians.0.townCity");
    expect(serverFieldToKey("guardians.1.phone")).toBe("guardians.1.phone");
    expect(serverFieldToKey("students.2.current_grade_id")).toBe("students.2.currentGrade");
    expect(serverFieldToKey("students.0.month_of_enrollment")).toBe("students.0.month");
    expect(serverFieldToKey("referral_source_other")).toBe("referralSourceOther");
    expect(serverFieldToKey("students")).toBeNull();
    expect(serverFieldToKey(undefined)).toBeNull();
  });

  it("keeps the field on a 400 so the message shows next to it", () => {
    expect(
      interpretSubmitResponse(400, { error: "Child 1: required", field: "students.0.grade_id" }),
    ).toEqual({ kind: "refused", message: "Child 1: required", field: "students.0.gradeId" });
    expect(interpretSubmitResponse(400, { error: "bad", field: "nonsense" })).toEqual({
      kind: "refused",
      message: "bad",
    });
  });

  it("reads applications_open separately from the inquiries switch", () => {
    expect(parsePublicOptions({ ...RAW, applications_open: true }).applicationsOpen).toBe(true);
    const closedInquiries = parsePublicOptions({
      ...RAW,
      intake_open: false,
      applications_open: true,
    });
    expect(formAvailable(closedInquiries)).toBe(false);
    const closedApplications = parsePublicOptions({ ...RAW, applications_open: false });
    expect(formAvailable(closedApplications)).toBe(true);
  });

  it("says enquiry to parents and has no em or en dash in the phone hint or office message", () => {
    expect(OFFICE_MESSAGE).toMatch(/enquiry/);
    expect(OFFICE_MESSAGE).not.toMatch(/inquiry/);
    for (const text of [PHONE_HINT, OFFICE_MESSAGE]) {
      expect(text).not.toMatch(/[\u2013\u2014]/);
    }
    expect(PHONE_HINT).toMatch(/plus sign/);
    expect(PHONE_HINT).toMatch(/8 to 15 digits/);
  });
});
