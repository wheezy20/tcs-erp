import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import {
  APPLICATION_COPY,
  APPLICATION_FEE,
  DECLARATION_COPY,
  DECLARATION_SECTIONS,
  DOCUMENTS_COPY,
  ENQUIRY_COPY,
  FEE_BOX,
  SCHOLARSHIP_COPY,
  CONFIRMATION_EMAIL_NOTE,
  applicationThankYou,
  joinNames,
  DRAFT_REFUSED,
  PRIVACY_POLICY,
  SAVE_COPY,
} from "@/modules/admissions/public-copy";

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
    for (const s of strings([
      ENQUIRY_COPY,
      APPLICATION_COPY,
      APPLICATION_FEE,
      FEE_BOX,
      DOCUMENTS_COPY,
      SCHOLARSHIP_COPY,
      DECLARATION_SECTIONS,
      DECLARATION_COPY,
      SAVE_COPY,
      PRIVACY_POLICY,
      DRAFT_REFUSED,
    ]))
      expect(s, s).not.toMatch(DASHES);
    expect(applicationThankYou("Kofi", "Grade 3", "2026/2027")).not.toMatch(DASHES);
  });

  it("carries the full fee box, with the account details and no email promise", () => {
    expect(FEE_BOX.heading).toBe("Application fee: GHS 200.00");
    expect(FEE_BOX.accountLines).toEqual([
      "Consolidated Bank Ghana",
      "Account No: 0383011100001",
      "Name: Treasures Christian School",
    ]);
    expect(FEE_BOX.process).toBe(
      "Walk in to the bank, OR dial *170#, then Option 1 (Transfer money), then Option 6 (Bank account), then Option 1 (Wallet to bank account), then # for next, then Option 16 (CBG), then Enter account number 0383011100001, then Enter amount GHS 200.00, then Enter Reference: name of the learner",
    );
    expect(FEE_BOX.intro).toContain("does NOT mean admission has been granted");
    expect(JSON.stringify(FEE_BOX)).not.toMatch(/e-?mail/i);
    expect(JSON.stringify(FEE_BOX)).not.toMatch(/\u2192|->/);
  });

  it("tells the parent a confirmation email is coming, in the wording decided on 2026-10-16", () => {
    const note =
      "You should receive a confirmation email shortly. If you do not see it within a few minutes, please check your spam folder or contact the school.";
    expect(CONFIRMATION_EMAIL_NOTE).toBe(note);
    expect(APPLICATION_COPY.keepReference).toBe(`${note} Please still keep this reference number.`);
    expect(ENQUIRY_COPY.keepReference(false)).toBe(
      `${note} Please still keep this reference number.`,
    );
    expect(ENQUIRY_COPY.keepReference(true)).toBe(
      `${note} Please still keep these reference numbers.`,
    );
    for (const s of [APPLICATION_COPY.keepReference, ENQUIRY_COPY.keepReference(true)]) {
      expect(s).not.toMatch(/won't receive|no confirmation/i);
      expect(s).not.toMatch(DASHES);
    }
  });

  it("carries the full declaration, word for word, and the media consent", () => {
    expect(DECLARATION_SECTIONS.map((s) => s.heading)).toEqual([
      "Indemnity Clause",
      "Data Protection",
      "Declaration and Policy",
    ]);
    const text = JSON.stringify(DECLARATION_SECTIONS);
    for (const phrase of [
      "except in cases of proven gross negligence",
      "in accordance with applicable data protection laws and the school's privacy policy.",
      "TCS reserves the right to recommend an alternative placement or decline admission",
      "Newly admitted pupils may be placed under observation during an initial adjustment period.",
      "(Proverbs 22:6)",
      "We look forward to welcoming your family into the TCS community.",
      "By signing this form, I consent and agree to the terms and conditions of Treasures Christian School.",
    ])
      expect(text).toContain(phrase);
    expect(DECLARATION_SECTIONS.flatMap((s) => s.paragraphs)).toHaveLength(8);
    expect(DECLARATION_COPY.mediaText).toMatch(
      /^I\/We grant permission for the learner's photographs/,
    );
    expect(DECLARATION_COPY.mediaText).toMatch(
      /a written notice must be submitted to the school administration\.$/,
    );
    expect(SCHOLARSHIP_COPY.url).toBe(
      "https://drive.google.com/file/d/12dDFJDSY2yaKT-KdMBQ7Y4DGq7_Bhbgf/view?usp=sharing",
    );
  });

  it("thanks the parent with the name, grade and year, and promises no email", () => {
    const s = applicationThankYou("Kofi Mensah", "Grade 3", "2026/2027");
    expect(s).toBe(
      "Thank you! We've received the application for Kofi Mensah (Grade 3, 2026/2027). Our admissions team will review your documents and be in touch soon.",
    );
    expect(s).not.toMatch(/e-?mail/i);
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
      "nationalities.ts",
      "components/nationality-combobox.tsx",
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

describe("save and finish later copy (slice 10)", () => {
  const consent = `${SAVE_COPY.consentBefore} ${PRIVACY_POLICY.text}${SAVE_COPY.consentAfter}`;

  it("the consent line says what is kept, what is not, how long, how to delete, and names the privacy policy", () => {
    expect(consent).toMatch(/keep the answers I have entered/);
    expect(consent).toMatch(/details about my child/);
    expect(consent).toMatch(/30 days after my last save, and for no more than 60 days in all/);
    expect(consent).toMatch(/and the email address above/);
    expect(consent).toMatch(
      /The health questions, uploaded files, the declaration, my signature and media consent are not saved/,
    );
    expect(consent).toMatch(/delete my saved application at any time from the emailed link/);
    expect(consent).toMatch(/in line with the school's privacy policy\.$/);
  });

  it("the generic refusal never says that saved applications exist", () => {
    expect(DRAFT_REFUSED).toBe(
      "We could not save your application right now. Please contact the school office.",
    );
    expect(DRAFT_REFUSED).not.toMatch(/saved|draft|already|exist/i);
  });

  it("the privacy policy has no link until one is published", () => {
    expect(PRIVACY_POLICY.url).toBeNull();
  });
});
