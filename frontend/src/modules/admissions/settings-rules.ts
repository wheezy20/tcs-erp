// Pure display rules for the admissions settings screen (slice 7b2). No
// Supabase, no React. Every figure is still checked by the RPC that saves
// it; these only decide what is shown and stop text that isn't a whole
// number from being sent at all.

/** Where a capacity row's year stands against the academic year list.
 * Matched as exact text, as the database does (D-6o). */
export type YearStatus = "active" | "retired" | "unlisted";

export function yearStatus(
  year: string,
  years: { label: string; isActive: boolean }[],
): YearStatus {
  const found = years.find((y) => y.label === year);
  if (!found) return "unlisted";
  return found.isActive ? "active" : "retired";
}

/** Years a new capacity row may use: active ones only, in list order. */
export function capacityYearOptions(years: { label: string; isActive: boolean }[]): string[] {
  return years.filter((y) => y.isActive).map((y) => y.label);
}

/** Digits only (surrounding spaces allowed), else null. The range is the
 * RPC's to check, so its own message is shown. */
export function parseWholeNumber(text: string): number | null {
  const t = text.trim();
  if (!/^[0-9]{1,9}$/.test(t)) return null;
  return Number(t);
}

/** Campus grade rules for display: a campus with rules lists those grades
 * in school order; a campus without rules accepts every grade (null). */
export function campusGradeSummary(
  campuses: { id: string; name: string }[],
  rules: { branchId: string; gradeId: string }[],
  grades: { id: string; name: string; position: number }[],
): { campusId: string; campusName: string; grades: string[] | null }[] {
  return campuses.map((c) => {
    const ids = new Set(rules.filter((r) => r.branchId === c.id).map((r) => r.gradeId));
    if (ids.size === 0) return { campusId: c.id, campusName: c.name, grades: null };
    const names = grades
      .filter((g) => ids.has(g.id))
      .sort((a, b) => a.position - b.position)
      .map((g) => g.name);
    const known = new Set(grades.map((g) => g.id));
    const unknown = [...ids].filter((id) => !known.has(id)).length;
    return {
      campusId: c.id,
      campusName: c.name,
      grades: unknown > 0 ? [...names, `${unknown} unknown grade(s)`] : names,
    };
  });
}
