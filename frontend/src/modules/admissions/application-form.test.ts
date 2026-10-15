import { describe, expect, it } from "vitest";

import {
  FEE_PROOF,
  PUBLIC_DOCUMENT_LABELS,
  applicationFieldToKey,
  applicationView,
  buildApplicationPayload,
  checkFile,
  emptyApplicationDraft,
  interpretApplicationResponse,
  requiredDocumentTypes,
  validateApplication,
  type ApplicationDraft,
  type UploadedFile,
} from "@/modules/admissions/application-form";
import { parsePublicOptions } from "@/modules/admissions/inquiry-form";

const OPTIONS = parsePublicOptions({
  intake_open: false,
  applications_open: true,
  grades: [
    {
      id: "g-n1",
      name: "Nursery 1",
      position: 2,
      required_document_types: [FEE_PROOF, "proof_of_vaccination"],
    },
    { id: "g-3", name: "Grade 3", position: 8, required_document_types: [FEE_PROOF] },
    { id: "g-2", name: "Grade 2", position: 7 },
  ],
  campuses: [
    { id: "c-annex", name: "Annex", accepted_grade_ids: ["g-n1"] },
    { id: "c-main", name: "Main", accepted_grade_ids: ["g-n1", "g-3", "g-2"] },
  ],
  academic_years: ["2026/2027"],
});
const TODAY = "2026-10-15";
const FEE: UploadedFile = {
  reservationId: "r1",
  path: "uploads/r1/application_fee_proof.pdf",
  fileName: "slip.pdf",
};
const VAC: UploadedFile = {
  reservationId: "r2",
  path: "uploads/r2/proof_of_vaccination.png",
  fileName: "card.png",
};

function valid(): ApplicationDraft {
  const d = emptyApplicationDraft();
  d.guardians = [
    {
      surname: "Mensah",
      firstName: "Ama",
      relationship: "mother",
      religion: "Christian",
      address: "1 Ring Road",
      townCity: "Accra",
      phone: "0590000000",
      email: " Ama@Example.com ",
    },
  ];
  d.child = {
    fullName: " Kofi Mensah ",
    dateOfBirth: "03/02/2019",
    gender: "male",
    nationality: "Ghanaian",
    address: "1 Ring Road",
    townCity: "Accra",
    currentGrade: "g-2",
    currentSchool: "Little Stars",
    gradeId: "g-3",
    academicYear: "2026/2027",
    month: "September",
  };
  d.campusId = "c-main";
  d.emergency = { name: "Kojo", relationship: "Uncle", phone: "+442079460958" };
  d.signature = "Ama Mensah";
  d.agreed = true;
  return d;
}

describe("options and view", () => {
  it("reads each grade's required documents; fee proof always first", () => {
    expect(OPTIONS.grades[0].requiredDocumentTypes).toEqual([FEE_PROOF, "proof_of_vaccination"]);
    expect(requiredDocumentTypes(OPTIONS, "g-n1")).toEqual([FEE_PROOF, "proof_of_vaccination"]);
    expect(requiredDocumentTypes(OPTIONS, "g-3")).toEqual([FEE_PROOF]);
    // Missing from the options or no grade chosen: the fee proof still.
    expect(requiredDocumentTypes(OPTIONS, "g-2")).toEqual([FEE_PROOF]);
    expect(requiredDocumentTypes(OPTIONS, "")).toEqual([FEE_PROOF]);
    expect(PUBLIC_DOCUMENT_LABELS[FEE_PROOF]).toBe(
      "Proof of payment (bank deposit slip, GIP confirmation or mobile money receipt)",
    );
  });

  it("uses the applications switch only", () => {
    const base = {
      loading: false,
      error: null,
      created: false,
      closedAfterSubmit: false,
      siteKey: "k",
    };
    expect(applicationView({ ...base, options: OPTIONS })).toBe("form");
    expect(
      applicationView({
        ...base,
        options: { ...OPTIONS, applicationsOpen: false, intakeOpen: true },
      }),
    ).toBe("closed");
    expect(applicationView({ ...base, options: OPTIONS, siteKey: " " })).toBe("unavailable");
    expect(applicationView({ ...base, options: OPTIONS, closedAfterSubmit: true })).toBe("closed");
  });
});

describe("checkFile", () => {
  it("accepts PDF, JPG, JPEG and PNG of 10 MB or less, with the bucket's content type", () => {
    expect(checkFile("slip.PDF", 1)).toEqual({ extension: "pdf", contentType: "application/pdf" });
    expect(checkFile("a.jpg", 10 * 1024 * 1024)).toEqual({
      extension: "jpg",
      contentType: "image/jpeg",
    });
    expect(checkFile("a.jpeg", 5)).toEqual({ extension: "jpeg", contentType: "image/jpeg" });
    expect(checkFile("a.png", 5)).toEqual({ extension: "png", contentType: "image/png" });
  });
  it("refuses other types, empty and oversized files", () => {
    for (const [n, s] of [
      ["a.heic", 5],
      ["a.html", 5],
      ["noext", 5],
      ["a.pdf", 0],
      ["a.pdf", 10 * 1024 * 1024 + 1],
    ] as const) {
      expect("error" in checkFile(n, s)).toBe(true);
    }
  });
});

describe("validateApplication", () => {
  it("passes a complete application", () => {
    expect(validateApplication(valid(), OPTIONS, TODAY, { [FEE_PROOF]: FEE })).toEqual({});
  });
  it("requires the fee proof for every grade, and vaccination proof where the grade needs it", () => {
    expect(validateApplication(valid(), OPTIONS, TODAY, {})).toHaveProperty(
      `documents.${FEE_PROOF}`,
    );
    const n1 = valid();
    n1.child.gradeId = "g-n1";
    const e = validateApplication(n1, OPTIONS, TODAY, { [FEE_PROOF]: FEE });
    expect(e).toHaveProperty("documents.proof_of_vaccination");
    expect(
      validateApplication(n1, OPTIONS, TODAY, { [FEE_PROOF]: FEE, proof_of_vaccination: VAC }),
    ).toEqual({});
  });
  it("applies the campus grade rule, the phone rule, health details and the declaration", () => {
    const d = valid();
    d.campusId = "c-annex";
    d.emergency.phone = "12345";
    d.health.hasMedical = true;
    d.agreed = false;
    d.signature = " ";
    const e = validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE });
    expect(Object.keys(e).sort()).toEqual(
      ["agreed", "child.gradeId", "emergency.phone", "health.medical", "signature"].sort(),
    );
    d.health.medical = "x".repeat(2001);
    expect(validateApplication(d, OPTIONS, TODAY, {})["health.medical"]).toMatch(/2000/);
  });
  it("needs no current school for a child not yet in school", () => {
    const d = valid();
    d.child.currentGrade = "not_yet_in_school";
    d.child.currentSchool = "";
    expect(validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE })).toEqual({});
  });
});

describe("buildApplicationPayload", () => {
  it("is exactly the shape submit_application accepts, with only the required documents", () => {
    const d = valid();
    d.health.hasAllergies = true;
    d.health.allergies = " peanuts ";
    d.health.medical = "left over";
    const p = buildApplicationPayload(d, OPTIONS, { [FEE_PROOF]: FEE, proof_of_vaccination: VAC });
    expect(Object.keys(p).sort()).toEqual(
      [
        "campus_id",
        "declaration_agreed",
        "declaration_signature_name",
        "documents",
        "emergency_contact",
        "guardians",
        "health_info",
        "student",
      ].sort(),
    );
    expect(p.documents).toEqual([
      {
        document_type: FEE_PROOF,
        reservation_id: "r1",
        path: "uploads/r1/application_fee_proof.pdf",
      },
    ]);
    expect(p.guardians).toEqual([
      {
        surname: "Mensah",
        first_name: "Ama",
        relationship: "mother",
        religion: "Christian",
        address: "1 Ring Road",
        town_city: "Accra",
        phone: "+233590000000",
        email: "Ama@Example.com",
      },
    ]);
    expect(p.student).toEqual({
      full_name: "Kofi Mensah",
      date_of_birth: "2019-02-03",
      gender: "male",
      nationality: "Ghanaian",
      address: "1 Ring Road",
      town_city: "Accra",
      grade_id: "g-3",
      academic_year: "2026/2027",
      month_of_enrollment: "September",
      current_grade_id: "g-2",
      current_school: "Little Stars",
    });
    expect(p.health_info).toEqual({
      has_learning_or_physical_needs: false,
      learning_or_physical_needs_details: "",
      has_medical_conditions: false,
      medical_conditions_details: "",
      has_allergies_or_dietary_requirements: true,
      allergies_dietary_details: "peanuts",
    });
    expect(p.emergency_contact).toEqual({
      name: "Kojo",
      relationship: "Uncle",
      phone: "+442079460958",
    });
    expect(JSON.stringify(p)).not.toMatch(/ip_address|agreed_at|"ip"/);
  });
  it("sends prior_schooling and no current school for a child not yet in school", () => {
    const d = valid();
    d.child.currentGrade = "not_yet_in_school";
    const s = buildApplicationPayload(d, OPTIONS, {}).student as Record<string, unknown>;
    expect(s.prior_schooling).toBe("not_yet_in_school");
    expect(s).not.toHaveProperty("current_grade_id");
    expect(s).not.toHaveProperty("current_school");
  });
});

describe("responses", () => {
  it("takes only an APP reference as success", () => {
    expect(interpretApplicationResponse(200, { reference: "APP-2026-0042" })).toEqual({
      kind: "created",
      reference: "APP-2026-0042",
    });
    for (const body of [{ reference: "INQ-2026-0001" }, { references: ["APP-2026-0001"] }, null]) {
      expect(interpretApplicationResponse(200, body).kind).toBe("refused");
    }
  });
  it("maps refusals and field paths", () => {
    expect(interpretApplicationResponse(409, { error: "closed" })).toEqual({
      kind: "closed",
      message: "closed",
    });
    expect(
      interpretApplicationResponse(400, { error: "m", field: "student.date_of_birth" }),
    ).toEqual({
      kind: "refused",
      message: "m",
      field: "child.dateOfBirth",
    });
    expect(applicationFieldToKey("guardians.1.town_city")).toBe("guardians.1.townCity");
    expect(applicationFieldToKey("emergency_contact.phone")).toBe("emergency.phone");
    expect(applicationFieldToKey("health_info.allergies_dietary_details")).toBe("health.allergies");
    expect(applicationFieldToKey("declaration_agreed")).toBe("agreed");
    expect(applicationFieldToKey("students.0.grade_id")).toBeNull();
    expect(interpretApplicationResponse(0, null).kind).toBe("refused");
  });
});
