import { describe, expect, it } from "vitest";

import { emptyApplicationDraft, validateApplication } from "@/modules/admissions/application-form";
import { FEE, OPTIONS, TODAY, validDraft } from "@/modules/admissions/application-fixtures";
import {
  LAST_STEP,
  STEPS,
  completeSteps,
  incompleteSteps,
  routeServerError,
  stepForField,
} from "@/modules/admissions/application-steps";
import { APPLICATION_COPY } from "@/modules/admissions/public-copy";

const FEE_UPLOAD = { application_fee_proof: FEE };

describe("the six steps", () => {
  it("are TCS OS's, in order, with its headings", () => {
    expect(STEPS.map((s) => s.nav)).toEqual([
      "Guardian(s)",
      "Student",
      "Emergency",
      "Health",
      "Documents",
      "Declaration",
    ]);
    expect(STEPS.map((s) => s.title)).toEqual([
      "Parent / Guardian information",
      "Student information",
      "Emergency Contact",
      "Health & Wellbeing",
      "Documents & Payment",
      "Declaration",
    ]);
    expect(LAST_STEP).toBe(5);
    for (const s of STEPS) expect(`${s.nav} ${s.title}`).not.toMatch(/[–—]/);
    expect(JSON.stringify(APPLICATION_COPY)).not.toMatch(/[–—]/);
  });
});

describe("every field belongs to a step", () => {
  it("maps every key validation can produce, from an empty form and from bad values", () => {
    const empty = emptyApplicationDraft();
    const bad = validDraft();
    bad.guardians.push({ ...bad.guardians[0], email: "x", phone: "1" });
    bad.child = {
      ...bad.child,
      sameAddress: false,
      address: "",
      townCity: "",
      postalCode: "x".repeat(30),
      country: "x".repeat(200),
      previousSchoolLocation: "x".repeat(300),
    };
    bad.health = { ...bad.health, hasNeeds: true, hasMedical: true, hasAllergies: true };
    bad.wantsScholarship = true;
    bad.scholarshipDetails = "x".repeat(10001);
    const keys = new Set([
      ...Object.keys(validateApplication(empty, OPTIONS, TODAY, {})),
      ...Object.keys(validateApplication(bad, OPTIONS, TODAY, {})),
    ]);
    expect(keys.size).toBeGreaterThan(25);
    for (const key of keys) expect(stepForField(key), key).not.toBeNull();
  });

  it("puts each field in its own step", () => {
    expect(stepForField("guardians.1.phone")).toBe(0);
    expect(stepForField("child.postalCode")).toBe(1);
    expect(stepForField("campusId")).toBe(1);
    expect(stepForField("emergency.relationship")).toBe(2);
    expect(stepForField("health.hasAllergies")).toBe(3);
    expect(stepForField("documents.application_fee_proof")).toBe(4);
    expect(stepForField("documents")).toBe(4);
    expect(stepForField("signature")).toBe(5);
    expect(stepForField("agreed")).toBe(5);
    expect(stepForField("nonsense")).toBeNull();
  });
});

describe("completeness", () => {
  it("a complete application ticks every step", () => {
    expect(completeSteps(validDraft(), OPTIONS, TODAY, FEE_UPLOAD)).toEqual([
      true,
      true,
      true,
      true,
      true,
      true,
    ]);
  });

  it("an empty form ticks none", () => {
    expect(completeSteps(emptyApplicationDraft(), OPTIONS, TODAY, {})).toEqual([
      false,
      false,
      false,
      false,
      false,
      false,
    ]);
  });

  it("a step stays open while one of its required fields is invalid, not just empty", () => {
    const d = validDraft();
    d.emergency.phone = "0590";
    expect(completeSteps(d, OPTIONS, TODAY, FEE_UPLOAD)).toEqual([
      true,
      true,
      false,
      true,
      true,
      true,
    ]);
  });

  it("an unanswered health question keeps the Health step open", () => {
    const d = validDraft();
    d.health.hasAllergies = null;
    expect(completeSteps(d, OPTIONS, TODAY, FEE_UPLOAD)[3]).toBe(false);
  });

  it("the documents step needs the fee proof", () => {
    expect(completeSteps(validDraft(), OPTIONS, TODAY, {})[4]).toBe(false);
  });

  it("lists the incomplete steps in order, once each", () => {
    const d = validDraft();
    d.signature = "";
    d.guardians[0].email = "";
    d.guardians[0].surname = "";
    expect(incompleteSteps(validateApplication(d, OPTIONS, TODAY, {}))).toEqual([0, 4, 5]);
  });
});

describe("server errors go to the right step and field", () => {
  it("routes each section's paths", () => {
    const d = validDraft();
    expect(routeServerError("guardians.1.email", d)).toEqual({
      field: "guardians.1.email",
      step: 0,
    });
    expect(routeServerError("student.date_of_birth", d)).toEqual({
      field: "child.dateOfBirth",
      step: 1,
    });
    expect(routeServerError("campus_id", d)).toEqual({ field: "campusId", step: 1 });
    expect(routeServerError("emergency_contact.phone", d)).toEqual({
      field: "emergency.phone",
      step: 2,
    });
    expect(routeServerError("health_info.medical_conditions_details", d)).toEqual({
      field: "health.medical",
      step: 3,
    });
    expect(routeServerError("documents", d)).toEqual({ field: "documents", step: 4 });
    expect(routeServerError("declaration_agreed", d)).toEqual({ field: "agreed", step: 5 });
  });

  it("opens a section for a path that names only the section", () => {
    const d = validDraft();
    expect(routeServerError("student", d)).toEqual({ field: null, step: 1 });
    expect(routeServerError("guardians", d)).toEqual({ field: null, step: 0 });
    expect(routeServerError("health_info", d)).toEqual({ field: null, step: 3 });
    expect(routeServerError("media_consent_agreed", d)).toEqual({ field: null, step: 5 });
    expect(routeServerError(undefined, d)).toEqual({ field: null, step: null });
    expect(routeServerError("something_else", d)).toEqual({ field: null, step: null });
  });

  it("shows a child address error on guardian 1 while the address follows guardian 1", () => {
    const d = validDraft();
    expect(routeServerError("student.address", d)).toEqual({
      field: "guardians.0.address",
      step: 0,
    });
    expect(routeServerError("student.town_city", d)).toEqual({
      field: "guardians.0.townCity",
      step: 0,
    });
    d.child.sameAddress = false;
    expect(routeServerError("student.address", d)).toEqual({ field: "child.address", step: 1 });
  });
});
