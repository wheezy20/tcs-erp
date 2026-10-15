// Pure logic for the staff Submission check panel (admissions slice 9a).
// No Supabase, no React. A public application that matched an existing
// family has an application_match_flags row; its differences hold only
// what the parent submitted that differs from the record, which was never
// changed (D-9b). There are never health answers in it (D-9j).

export type MatchOutcome = "new_application" | "inquiry_advanced" | "possible_duplicate";

export const MATCH_OUTCOME_LABELS: Record<MatchOutcome, string> = {
  new_application: "New application for a family already on record",
  inquiry_advanced: "Earlier enquiry moved to application (it keeps its INQ reference)",
  possible_duplicate:
    "Possible duplicate: this child already has an application for this year and grade",
};

const FIELD_LABELS: Record<string, string> = {
  surname: "Surname",
  first_name: "First name",
  relationship: "Relationship",
  religion: "Religion",
  address: "Address",
  town_city: "Town or city",
  phone: "Phone",
  gender: "Gender",
  nationality: "Nationality",
  postal_code: "Postal code",
  country: "Country",
  current_school: "Current school",
  previous_school_location: "Previous school location",
  current_grade_id: "Current grade",
  prior_schooling: "Current grade",
};

export type DifferenceRow = { who: string; field: string; submitted: string };

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function show(field: string, value: unknown, gradeNames: Record<string, string>): string {
  if (value === null || value === undefined || value === "") return "(blank)";
  const text = String(value);
  if (field === "current_grade_id") return gradeNames[text] ?? "(a grade no longer listed)";
  if (field === "prior_schooling" && text === "not_yet_in_school") return "Not yet in school";
  return text;
}

/** The snapshot as rows for a table. Unknown shapes are skipped, never
 * guessed at. The text is a stranger's: React escapes it when shown. */
export function differenceRows(
  differences: unknown,
  gradeNames: Record<string, string>,
): DifferenceRow[] {
  if (!isRecord(differences)) return [];
  const rows: DifferenceRow[] = [];
  const guardians = Array.isArray(differences.guardians) ? differences.guardians : [];
  for (const g of guardians) {
    if (!isRecord(g) || typeof g.email !== "string" || !isRecord(g.fields)) continue;
    const who = g.new === true ? `New guardian (not added): ${g.email}` : `Guardian ${g.email}`;
    for (const [field, value] of Object.entries(g.fields)) {
      if (!(field in FIELD_LABELS)) continue;
      rows.push({ who, field: FIELD_LABELS[field], submitted: show(field, value, gradeNames) });
    }
  }
  if (isRecord(differences.student)) {
    for (const [field, value] of Object.entries(differences.student)) {
      if (!(field in FIELD_LABELS)) continue;
      rows.push({
        who: "Child",
        field: FIELD_LABELS[field],
        submitted: show(field, value, gradeNames),
      });
    }
  }
  return rows;
}
