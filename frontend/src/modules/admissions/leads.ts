// What the staff lead list says (slice 13). Pure functions only (no
// Supabase, no React) so they can be unit tested. The database decides
// who sees which lead and which fields come back masked; this file only
// words it.

export const LEADS_PAGE_SIZE = 100;

export const LEAD_SOURCE_LABELS: Record<string, string> = {
  pdf_gate_admissions_overview: "Admissions Overview download",
};

export function leadSourceLabel(source: string): string {
  return LEAD_SOURCE_LABELS[source] ?? source;
}

/** The marketing consent column. An unsubscribed lead is deleted by the
 * next daily cleanup, so it shows only until then. */
export function consentLabel(consent: boolean, unsubscribedAt: string | null): string {
  if (unsubscribedAt) return "Unsubscribed";
  return consent ? "Agreed to marketing emails" : "No marketing emails";
}

/** "facebook / social / spring-open-day", leaving out the blank parts;
 * empty when there is no campaign information. */
export function utmSummary(row: {
  utmSource: string | null;
  utmMedium: string | null;
  utmCampaign: string | null;
}): string {
  return [row.utmSource, row.utmMedium, row.utmCampaign].filter((v) => v && v !== "").join(" / ");
}

/** "Showing 101 to 200 of 340". */
export function pageRangeLabel(offset: number, shown: number, total: number): string {
  if (total === 0 || shown === 0) return "No leads";
  return `Showing ${offset + 1} to ${offset + shown} of ${total}`;
}

/** The ?lead= value of the staff alert's link, only when it is a lead id. */
export function parseLeadParam(value: unknown): string | undefined {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)
    ? value
    : undefined;
}
