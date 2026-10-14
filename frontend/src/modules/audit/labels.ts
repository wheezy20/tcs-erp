// Display labels for every audit_log action (the audit_log_action_check
// list, 37 values as of 20261018110000). An action missing here still
// shows, as its raw value.

/** Admissions actions start with one of these, and no other action does
 * (20261019100000 relies on it; the 7c probe file pins the split). */
const ADMISSIONS_ACTION_PREFIXES = ["application_", "admissions_"];

export function isAdmissionsAction(action: string): boolean {
  return ADMISSIONS_ACTION_PREFIXES.some((p) => action.startsWith(p));
}

export const AUDIT_ACTION_LABELS: Record<string, string> = {
  discount_applied: "Discount applied",
  vat_override: "VAT override",
  return_processed: "Return processed",
  sale_voided: "Sale voided",
  invoice_voided: "Invoice voided",
  expense_voided: "Expense voided",
  employee_created: "Employee created",
  employee_approved: "Employee approved",
  employee_rejected: "Employee rejected",
  employee_suspended: "Employee suspended",
  employee_reactivated: "Employee reactivated",
  employees_imported: "Employees imported",
  pay_config_proposed: "Pay config proposed",
  pay_config_approved: "Pay config approved",
  pay_config_amended_and_approved: "Pay config amended and approved",
  pay_config_rejected: "Pay config rejected",
  pay_config_exemptions_changed: "Pay config exemptions changed",
  payroll_run_submitted: "Payroll run submitted",
  payroll_run_approved: "Payroll run approved",
  payroll_run_rejected: "Payroll run rejected",
  payroll_run_exclusion_added: "Payroll run exclusion added",
  payroll_run_exclusion_removed: "Payroll run exclusion removed",
  staff_advance_proposed: "Staff advance proposed",
  staff_advance_approved: "Staff advance approved",
  staff_advance_rejected: "Staff advance rejected",
  staff_advance_change_proposed: "Staff advance change proposed",
  staff_advance_change_approved: "Staff advance change approved",
  staff_advance_change_rejected: "Staff advance change rejected",
  admissions_capabilities_changed: "Admissions access changed",
  application_stage_changed: "Application stage changed",
  application_document_status_changed: "Application document status changed",
  application_decision_changed: "Application decision changed",
  application_offer_changed: "Application offer changed",
  application_grade_corrected: "Application grade corrected",
  admissions_capacity_changed: "Admissions capacity changed",
  admissions_settings_changed: "Admissions settings changed",
  admissions_academic_year_changed: "Admissions academic year changed",
};

export const AUDIT_ACTIONS = Object.keys(AUDIT_ACTION_LABELS);

export function actionLabel(action: string): string {
  return AUDIT_ACTION_LABELS[action] ?? action;
}
