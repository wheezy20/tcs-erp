import { describe, expect, it } from "vitest";

import {
  consentLabel,
  leadSourceLabel,
  pageRangeLabel,
  parseLeadParam,
  utmSummary,
} from "@/modules/admissions/leads";
import { canViewAdmissionsLeads, leadContactsMasked } from "@/modules/admissions/permissions";

describe("lead list access (D-13h)", () => {
  it("is open to Manager, Admissions Officer and Auditor only", () => {
    expect(canViewAdmissionsLeads("Manager")).toBe(true);
    expect(canViewAdmissionsLeads("Admissions Officer")).toBe(true);
    expect(canViewAdmissionsLeads("Auditor")).toBe(true);
    expect(canViewAdmissionsLeads("Attendant")).toBe(false);
    expect(canViewAdmissionsLeads("Accountant")).toBe(false);
    expect(canViewAdmissionsLeads(undefined)).toBe(false);
  });

  it("says contacts are masked for the Auditor only", () => {
    expect(leadContactsMasked("Auditor")).toBe(true);
    expect(leadContactsMasked("Manager")).toBe(false);
    expect(leadContactsMasked("Admissions Officer")).toBe(false);
  });
});

describe("lead labels", () => {
  it("names the source, and passes an unknown one through", () => {
    expect(leadSourceLabel("pdf_gate_admissions_overview")).toBe("Admissions Overview download");
    expect(leadSourceLabel("something_new")).toBe("something_new");
  });

  it("words consent, with unsubscribed winning", () => {
    expect(consentLabel(true, null)).toBe("Agreed to marketing emails");
    expect(consentLabel(false, null)).toBe("No marketing emails");
    expect(consentLabel(true, "2026-10-21T10:00:00Z")).toBe("Unsubscribed");
  });

  it("joins the campaign parts that are there", () => {
    expect(utmSummary({ utmSource: "facebook", utmMedium: null, utmCampaign: "open-day" })).toBe(
      "facebook / open-day",
    );
    expect(utmSummary({ utmSource: null, utmMedium: "", utmCampaign: null })).toBe("");
  });

  it("shows the page range", () => {
    expect(pageRangeLabel(0, 100, 340)).toBe("Showing 1 to 100 of 340");
    expect(pageRangeLabel(300, 40, 340)).toBe("Showing 301 to 340 of 340");
    expect(pageRangeLabel(0, 0, 0)).toBe("No leads");
  });

  it("takes only a lead id from the alert link", () => {
    expect(parseLeadParam("13000000-0000-4000-8000-000000000a01")).toBe(
      "13000000-0000-4000-8000-000000000a01",
    );
    expect(parseLeadParam("13000000-0000-4000-8000-000000000A01")).toBeUndefined();
    expect(parseLeadParam("../admin")).toBeUndefined();
    expect(parseLeadParam(5)).toBeUndefined();
  });
});
