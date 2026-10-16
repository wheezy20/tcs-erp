import { describe, expect, it } from "vitest";

import { AUDIT_ACTIONS, actionLabel, isAdmissionsAction } from "@/modules/audit/labels";
import {
  actionFilterOptions,
  canSeeAdmissionsAuditRows,
  canViewAuditLog,
} from "@/modules/audit/permissions";

// The 9 admissions actions, as the 7c probe file lists them.
const ADMISSIONS = [
  "admissions_capabilities_changed",
  "application_stage_changed",
  "application_document_status_changed",
  "application_decision_changed",
  "admissions_capacity_changed",
  "application_offer_changed",
  "admissions_settings_changed",
  "application_grade_corrected",
  "admissions_academic_year_changed",
];

describe("audit action labels", () => {
  it("label all 40 actions, with no duplicate label", () => {
    expect(AUDIT_ACTIONS).toHaveLength(40);
    const labels = AUDIT_ACTIONS.map(actionLabel);
    expect(new Set(labels).size).toBe(40);
  });

  it("split into the 9 admissions actions and 31 others", () => {
    expect(AUDIT_ACTIONS.filter(isAdmissionsAction).sort()).toEqual([...ADMISSIONS].sort());
  });

  it("fall back to the raw value for an unknown action", () => {
    expect(actionLabel("something_new")).toBe("something_new");
  });
});

describe("audit log permissions", () => {
  it("open the page to Manager, Accountant and Auditor only", () => {
    expect(canViewAuditLog("Manager")).toBe(true);
    expect(canViewAuditLog("Accountant")).toBe(true);
    expect(canViewAuditLog("Auditor")).toBe(true);
    expect(canViewAuditLog("Attendant")).toBe(false);
    expect(canViewAuditLog("Admissions Officer")).toBe(false);
    expect(canViewAuditLog(undefined)).toBe(false);
  });

  it("show admissions rows to Manager and Auditor, not the Accountant", () => {
    expect(canSeeAdmissionsAuditRows("Manager")).toBe(true);
    expect(canSeeAdmissionsAuditRows("Auditor")).toBe(true);
    expect(canSeeAdmissionsAuditRows("Accountant")).toBe(false);
  });

  it("offer every action to Manager and Auditor", () => {
    expect(actionFilterOptions("Manager")).toHaveLength(40);
    expect(actionFilterOptions("Auditor")).toHaveLength(40);
  });

  it("offer the Accountant the 31 non-admissions actions, payroll and employee ones included", () => {
    const options = actionFilterOptions("Accountant");
    expect(options).toHaveLength(31);
    expect(options.some(isAdmissionsAction)).toBe(false);
    expect(options).toContain("payroll_run_approved");
    expect(options).toContain("employee_approved");
    expect(options).toContain("pay_config_approved");
  });

  it("offer nothing to roles that can't open the page", () => {
    expect(actionFilterOptions("Attendant")).toEqual([]);
    expect(actionFilterOptions("Admissions Officer")).toEqual([]);
  });
});
