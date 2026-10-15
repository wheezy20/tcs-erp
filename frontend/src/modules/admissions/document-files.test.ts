import { describe, expect, it } from "vitest";

import {
  FEE_PROOF_NOTE,
  documentDownloadName,
  feeProofFirst,
  signedDownloadOptions,
} from "@/modules/admissions/document-files";

describe("staff document downloads", () => {
  it("always signs with a forced download", () => {
    expect(signedDownloadOptions("APP-2026-0001-application_fee_proof.pdf")).toEqual({
      download: "APP-2026-0001-application_fee_proof.pdf",
    });
  });
  it("names the file from database values only", () => {
    expect(
      documentDownloadName(
        "APP-2026-0001",
        "application_fee_proof",
        "uploads/x/application_fee_proof.PDF",
      ),
    ).toBe("APP-2026-0001-application_fee_proof.pdf");
    expect(documentDownloadName(null, "previous_report", "uploads/x/previous_report.png")).toBe(
      "application-previous_report.png",
    );
    expect(documentDownloadName("../../etc", "a/b", "x.exe")).toBe("application-document.bin");
  });
  it("lists the fee proof first and keeps the rest in order", () => {
    const docs = [
      { documentType: "previous_report", id: 1 },
      { documentType: "proof_of_vaccination", id: 2 },
      { documentType: "application_fee_proof", id: 3 },
    ];
    expect(feeProofFirst(docs).map((d) => d.id)).toEqual([3, 1, 2]);
    expect(FEE_PROOF_NOTE).toMatch(/bank or mobile money record/);
  });
});
