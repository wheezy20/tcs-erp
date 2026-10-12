// Pure helpers for the applications list query (unit tested; no Supabase).

/** Longest search the list accepts. */
export const SEARCH_MAX_LENGTH = 80;

/** The list's search term as a PostgREST ilike pattern, or null for no
 * search. Anything other than letters, digits, spaces, apostrophes,
 * periods and hyphens is dropped, so the value can't break PostgREST's `or`
 * syntax (commas, parentheses, quotes) or act as a LIKE wildcard (% and _).
 * Names and INQ-/APP- references only need what's kept. */
export function searchPattern(raw: string): string | null {
  const cleaned = raw
    .slice(0, SEARCH_MAX_LENGTH)
    .replace(/[^\p{L}\p{N}\s'.-]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned === "" ? null : `"%${cleaned}%"`;
}

/** The `or` filter for a pattern from searchPattern(). */
export function searchFilter(pattern: string): string {
  return ["student_full_name", "inquiry_reference", "application_reference"]
    .map((column) => `${column}.ilike.${pattern}`)
    .join(",");
}

/** academic_year values are free text; the list's "not on the list" option
 * is `not in (...)` over the curated labels, each quoted. Labels are checked
 * YYYY/YYYY by the table, so no quoting can break. */
export function notInListFilter(labels: string[]): string {
  return `(${labels.map((l) => `"${l}"`).join(",")})`;
}
