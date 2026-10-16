// Staff ID numbers (20261026100000): pure display, search and merge-field
// helpers, no Supabase. The database issues, corrects and enforces every
// rule; these only read what it returned.
//
// Format: ST + two digit approval year + '-' + two digit class + three
// digit roll, e.g. ST26-02002. The roll runs across all classes within a
// year, so ST26-02002 is the second person approved in 2026, not the
// second teacher.

export type StaffClassCode = "01" | "02" | "03" | "04" | "05";

export const STAFF_CLASSES: { code: StaffClassCode; label: string }[] = [
  { code: "01", label: "Admin" },
  { code: "02", label: "Teaching" },
  { code: "03", label: "Kitchen" },
  { code: "04", label: "Janitorial" },
  { code: "05", label: "Transport" },
];

export function staffClassLabel(code: string | null | undefined): string {
  return STAFF_CLASSES.find((c) => c.code === code)?.label ?? "No class";
}

export type StaffNumber = {
  number: string;
  employeeId: string;
  year: number;
  classCode: StaffClassCode;
  roll: number;
  issuedAt: string;
  retiredAt: string | null;
  retireReason: string | null;
  replacedBy: string | null;
};

/** The one current (unretired) ID for an employee, if any. */
export function currentStaffNumber(
  numbers: StaffNumber[],
  employeeId: string,
): StaffNumber | undefined {
  return numbers.find((n) => n.employeeId === employeeId && n.retiredAt === null);
}

/** Every ID an employee has held, newest first. */
export function staffNumberHistory(numbers: StaffNumber[], employeeId: string): StaffNumber[] {
  return numbers
    .filter((n) => n.employeeId === employeeId)
    .sort((a, b) => (a.issuedAt < b.issuedAt ? 1 : a.issuedAt > b.issuedAt ? -1 : 0));
}

/** The correction is offered once: Active or Suspended, a current ID, and
 * no earlier correction. The database checks the same thing. */
export function canCorrectStaffNumber(
  numbers: StaffNumber[],
  employeeId: string,
  status: string,
): boolean {
  if (status !== "Active" && status !== "Suspended") return false;
  const mine = numbers.filter((n) => n.employeeId === employeeId);
  return mine.some((n) => n.retiredAt === null) && !mine.some((n) => n.retiredAt !== null);
}

/** What a screen shows for an employee's ID: the number, or "Not issued"
 * for anyone approved before staff IDs existed (no backfill) or not yet
 * approved. Documents never use this: see staffIdMergeValue. */
export function staffNumberDisplay(current: StaffNumber | undefined | null): string {
  return current?.number ?? "Not issued";
}

/** Uppercase with every space, dash and other separator removed, so
 * "st26 02002", "ST26-02002" and "st2602002" all compare equal. */
export function compactStaffNumber(value: string): string {
  return value.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

/** Whether a search box query matches an ID. Separators and case are
 * ignored and any part matches ("02002", "ST26", "26-02"). A query with
 * no letters or digits matches nothing, so it never matches every row. */
export function staffNumberMatches(number: string | null | undefined, query: string): boolean {
  if (!number) return false;
  const q = compactStaffNumber(query);
  if (!q) return false;
  return compactStaffNumber(number).includes(q);
}

// ------------------------------------------------------------ {{staff_id}}

export const STAFF_ID_MERGE_FIELD = "staff_id";
export const STAFF_ID_MISSING_MESSAGE = "Approve this employee first so a staff ID exists";

export function templateUsesStaffId(htmlBody: string): boolean {
  return htmlBody.includes(`{{${STAFF_ID_MERGE_FIELD}}}`);
}

/** The {{staff_id}} value for a document, or the refusal. There is no
 * placeholder text: a template that uses the field can't be generated
 * until the employee has a current ID. generate_employee_document refuses
 * the same case; this lets the dialog say so before anything is rendered
 * or uploaded. */
export function staffIdMergeValue(
  htmlBody: string,
  current: StaffNumber | undefined | null,
): { ok: true; value: string | null } | { ok: false; message: string } {
  if (!templateUsesStaffId(htmlBody)) return { ok: true, value: current?.number ?? null };
  if (!current) return { ok: false, message: STAFF_ID_MISSING_MESSAGE };
  return { ok: true, value: current.number };
}

// ------------------------------------------------------------ payslip

/** The payslip's "Staff ID" row, read when the payslip is shown (no
 * payslip column), so a reprint shows the employee's current ID. */
export function payslipStaffIdRow(current: StaffNumber | undefined | null): [string, string] {
  return ["Staff ID", staffNumberDisplay(current)];
}

// ------------------------------------------------------------ positions

/** The class an approval would use: an exact match of the employee's
 * position to a listed position, active or not, as the database does. */
export function classForPosition(
  positions: { name: string; staffClass?: string | null }[],
  position: string | null | undefined,
): string | null {
  if (!position) return null;
  return positions.find((p) => p.name === position)?.staffClass ?? null;
}

/** The approval refusal for an unmapped position, worded as the database
 * words it, shown before the Manager clicks Approve. */
export function unmappedPositionMessage(position: string | null | undefined): string {
  return `Set a classification for position ${position || "(no position)"} first.`;
}
