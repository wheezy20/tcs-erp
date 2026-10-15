import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import {
  DEFAULT_COUNTRY,
  FEE_PROOF,
  GENDER_OPTIONS,
  PUBLIC_DOCUMENT_LABELS,
  applicationFieldToKey,
  applicationView,
  buildApplicationPayload,
  checkFile,
  childAddress,
  emptyApplicationDraft,
  hasEnteredData,
  interpretApplicationResponse,
  requiredDocumentTypes,
  validateApplication,
} from "@/modules/admissions/application-form";
import { FEE, OPTIONS, TODAY, VAC, validDraft } from "@/modules/admissions/application-fixtures";

describe("options and view", () => {
  it("reads each grade's required documents; fee proof always first", () => {
    expect(OPTIONS.grades[0].requiredDocumentTypes).toEqual([FEE_PROOF, "proof_of_vaccination"]);
    expect(requiredDocumentTypes(OPTIONS, "g-n1")).toEqual([FEE_PROOF, "proof_of_vaccination"]);
    expect(requiredDocumentTypes(OPTIONS, "g-3")).toEqual([FEE_PROOF]);
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

describe("the draft", () => {
  it("starts with Ghana as the country, the child's address following guardian 1, and health unanswered", () => {
    const d = emptyApplicationDraft();
    expect(d.child.country).toBe(DEFAULT_COUNTRY);
    expect(d.child.sameAddress).toBe(true);
    expect([d.health.hasNeeds, d.health.hasMedical, d.health.hasAllergies]).toEqual([
      null,
      null,
      null,
    ]);
  });

  it("lists gender Male then Female, as TCS OS", () => {
    expect(GENDER_OPTIONS.map((o) => o.value)).toEqual(["male", "female"]);
  });

  it("counts as entered only once the parent types something or uploads", () => {
    const d = emptyApplicationDraft();
    expect(hasEnteredData(d, {})).toBe(false);
    expect(hasEnteredData({ ...d, child: { ...d.child, fullName: "K" } }, {})).toBe(true);
    expect(hasEnteredData(d, { [FEE_PROOF]: FEE })).toBe(true);
  });
});

describe("the child's address follows guardian 1", () => {
  it("reads guardian 1 at the moment of use while ticked, so later edits are followed", () => {
    const d = validDraft();
    expect(childAddress(d)).toEqual({ address: "1 Ring Road", townCity: "Accra" });
    d.guardians[0] = { ...d.guardians[0], address: "2 New Street", townCity: "Tema" };
    expect(childAddress(d)).toEqual({ address: "2 New Street", townCity: "Tema" });
    const s = buildApplicationPayload(d, OPTIONS, { [FEE_PROOF]: FEE }).student as Record<
      string,
      unknown
    >;
    expect([s.address, s.town_city]).toEqual(["2 New Street", "Tema"]);
  });

  it("uses the child's own address once unticked, and then requires it", () => {
    const d = validDraft();
    d.child = { ...d.child, sameAddress: false, address: "", townCity: "" };
    const e = validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE });
    expect(Object.keys(e).sort()).toEqual(["child.address", "child.townCity"]);
    d.child = { ...d.child, address: "9 Child Lane", townCity: "Kumasi" };
    expect(childAddress(d)).toEqual({ address: "9 Child Lane", townCity: "Kumasi" });
  });

  it("while ticked, a missing guardian 1 address is reported once, on guardian 1", () => {
    const d = validDraft();
    d.guardians[0] = { ...d.guardians[0], address: "" };
    const e = validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE });
    expect(Object.keys(e)).toEqual(["guardians.0.address"]);
  });
});

describe("validateApplication", () => {
  it("passes a complete application", () => {
    expect(validateApplication(validDraft(), OPTIONS, TODAY, { [FEE_PROOF]: FEE })).toEqual({});
  });

  it("requires an explicit Yes or No for each health question, and details on Yes", () => {
    const d = validDraft();
    d.health = { ...d.health, hasNeeds: null, hasMedical: true, medical: " " };
    const e = validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE });
    expect(Object.keys(e).sort()).toEqual(["health.hasNeeds", "health.medical"]);
    d.health = { ...d.health, hasNeeds: false, medical: "x".repeat(2001) };
    expect(validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE })["health.medical"]).toMatch(
      /2000/,
    );
  });

  it("requires the fee proof for every grade, and vaccination proof where the grade needs it", () => {
    expect(validateApplication(validDraft(), OPTIONS, TODAY, {})).toHaveProperty(
      `documents.${FEE_PROOF}`,
    );
    const n1 = validDraft();
    n1.child.gradeId = "g-n1";
    expect(validateApplication(n1, OPTIONS, TODAY, { [FEE_PROOF]: FEE })).toHaveProperty(
      "documents.proof_of_vaccination",
    );
    expect(
      validateApplication(n1, OPTIONS, TODAY, { [FEE_PROOF]: FEE, proof_of_vaccination: VAC }),
    ).toEqual({});
  });

  it("caps the optional student fields", () => {
    const d = validDraft();
    d.child = {
      ...d.child,
      postalCode: "x".repeat(21),
      country: "x".repeat(101),
      previousSchoolLocation: "x".repeat(256),
    };
    expect(
      Object.keys(validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE })).sort(),
    ).toEqual(["child.country", "child.postalCode", "child.previousSchoolLocation"]);
  });

  it("asks for no current school or its location for a child not yet in school", () => {
    const d = validDraft();
    d.child = {
      ...d.child,
      currentGrade: "not_yet_in_school",
      currentSchool: "",
      previousSchoolLocation: "x".repeat(300),
    };
    expect(validateApplication(d, OPTIONS, TODAY, { [FEE_PROOF]: FEE })).toEqual({});
  });
});

describe("buildApplicationPayload", () => {
  it("is exactly the shape submit_application accepts", () => {
    const d = validDraft();
    d.health = { ...d.health, hasAllergies: true, allergies: " peanuts ", medical: "left over" };
    const p = buildApplicationPayload(d, OPTIONS, { [FEE_PROOF]: FEE, proof_of_vaccination: VAC });
    expect(p.documents).toEqual([
      {
        document_type: FEE_PROOF,
        reservation_id: "r1",
        path: "uploads/r1/application_fee_proof.pdf",
      },
    ]);
    expect(p.student).toEqual({
      full_name: "Kofi Mensah",
      date_of_birth: "2019-02-03",
      gender: "male",
      nationality: "Ghana",
      address: "1 Ring Road",
      town_city: "Accra",
      postal_code: "",
      country: "Ghana",
      grade_id: "g-3",
      academic_year: "2026/2027",
      month_of_enrollment: "September",
      current_grade_id: "g-2",
      current_school: "Little Stars",
      previous_school_location: "Spintex Road",
    });
    expect(p.health_info).toEqual({
      has_learning_or_physical_needs: false,
      learning_or_physical_needs_details: "",
      has_medical_conditions: false,
      medical_conditions_details: "",
      has_allergies_or_dietary_requirements: true,
      allergies_dietary_details: "peanuts",
    });
    expect([
      p.wants_scholarship_info,
      p.scholarship_interest_details,
      p.media_consent_agreed,
    ]).toEqual([false, "", false]);
    expect(JSON.stringify(p)).not.toMatch(/ip_address|agreed_at|"ip"/);
  });

  it("has exactly the keys of the full-contract fixture the integration test submits", () => {
    const fixture = JSON.parse(
      readFileSync(
        resolve(
          __dirname,
          "../../../../supabase/functions/admissions-public/fixtures/full-application-payload.json",
        ),
        "utf8",
      ),
    ) as Record<string, unknown>;
    const d = validDraft();
    d.guardians.push({ ...d.guardians[0], email: "second@example.com" });
    d.wantsScholarship = true;
    d.scholarshipDetails = "x";
    d.mediaConsent = true;
    const p = buildApplicationPayload(d, OPTIONS, { [FEE_PROOF]: FEE });
    const shape = (v: unknown): unknown =>
      Array.isArray(v)
        ? v.map(shape)
        : v && typeof v === "object"
          ? Object.fromEntries(
              Object.keys(v)
                .sort()
                .map((k) => [k, shape((v as Record<string, unknown>)[k])]),
            )
          : typeof v;
    expect(shape(p)).toEqual(shape(fixture));
  });

  it("sends prior_schooling and no school fields for a child not yet in school", () => {
    const d = validDraft();
    d.child.currentGrade = "not_yet_in_school";
    const s = buildApplicationPayload(d, OPTIONS, {}).student as Record<string, unknown>;
    expect(s.prior_schooling).toBe("not_yet_in_school");
    expect(s).not.toHaveProperty("current_grade_id");
    expect(s).not.toHaveProperty("current_school");
    expect(s).not.toHaveProperty("previous_school_location");
  });

  it("sends scholarship details only on Yes", () => {
    const d = validDraft();
    d.scholarshipDetails = "kept back";
    expect(buildApplicationPayload(d, OPTIONS, {}).scholarship_interest_details).toBe("");
    d.wantsScholarship = true;
    expect(buildApplicationPayload(d, OPTIONS, {}).scholarship_interest_details).toBe("kept back");
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

  it("maps refusals, keeping the server's path", () => {
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
      path: "student.date_of_birth",
    });
    expect(interpretApplicationResponse(400, { error: "m", field: "documents" })).toEqual({
      kind: "refused",
      message: "m",
      field: "documents",
      path: "documents",
    });
    expect(applicationFieldToKey("guardians.1.town_city")).toBe("guardians.1.townCity");
    expect(applicationFieldToKey("student.postal_code")).toBe("child.postalCode");
    expect(applicationFieldToKey("student.previous_school_location")).toBe(
      "child.previousSchoolLocation",
    );
    expect(applicationFieldToKey("health_info.has_medical_conditions")).toBe("health.hasMedical");
    expect(applicationFieldToKey("emergency_contact.phone")).toBe("emergency.phone");
    expect(applicationFieldToKey("declaration_agreed")).toBe("agreed");
    expect(applicationFieldToKey("students.0.grade_id")).toBeNull();
    expect(interpretApplicationResponse(0, null).kind).toBe("refused");
  });
});
