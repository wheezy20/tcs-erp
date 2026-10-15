import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { ENQUIRY_COPY, joinNames } from "@/modules/admissions/public-copy";

const DASHES = /[–—]/;

function strings(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (typeof value === "function") {
    return [
      String((value as (...a: unknown[]) => unknown)("Ama", true)),
      String((value as (...a: unknown[]) => unknown)("Ama", false)),
    ];
  }
  if (value && typeof value === "object") return Object.values(value).flatMap(strings);
  return [];
}

describe("public form copy", () => {
  it("has no em or en dashes anywhere", () => {
    for (const s of strings(ENQUIRY_COPY)) expect(s, s).not.toMatch(DASHES);
  });

  it("keeps the TCS OS headings", () => {
    expect(ENQUIRY_COPY.title).toBe("Admissions Enquiry");
    expect(ENQUIRY_COPY.sections).toEqual({
      referral: "How did you hear about us?",
      guardians: "Parent / Guardian information",
      enquiry: "The enquiry",
      other: "Other information",
    });
    expect(ENQUIRY_COPY.thankYouFor("Ama and Kofi")).toBe(
      "Thank you! We've received your enquiry for Ama and Kofi. Our admissions team will be in touch soon.",
    );
  });

  it("the public page sources and stylesheet carry no em or en dashes either", () => {
    for (const file of [
      "components/inquiry-page.tsx",
      "components/application-page.tsx",
      "application-steps.ts",
      "application-form.ts",
      "components/public-page-parts.tsx",
      "public-form.css",
      "public-copy.ts",
    ]) {
      const text = readFileSync(resolve(__dirname, file), "utf8");
      expect(DASHES.test(text), file).toBe(false);
    }
  });
});

describe("joinNames", () => {
  it("joins the names as typed, skipping blanks", () => {
    expect(joinNames([" Ama "])).toBe("Ama");
    expect(joinNames(["Ama", "Kofi"])).toBe("Ama and Kofi");
    expect(joinNames(["Ama", "", "Kofi", "Esi"])).toBe("Ama, Kofi and Esi");
    expect(joinNames(["", " "])).toBe("");
  });
});
