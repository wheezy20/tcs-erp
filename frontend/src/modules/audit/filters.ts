// Pure helpers for the Audit Log filters and the before/after column.

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function parseDay(value: string): Date | null {
  if (!DATE_RE.test(value)) return null;
  const d = new Date(`${value}T00:00:00Z`);
  // Rejects dates like 2026-02-30, which Date rolls over to March.
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value ? null : d;
}

export type DateBounds = { gte: string | null; lt: string | null; error: string | null };

/** Turns the From and To date inputs (YYYY-MM-DD, either may be empty)
 * into occurred_at bounds: from the start of From to the end of To, both
 * days included. Days are UTC, which is Africa/Accra's time. */
export function dateRangeBounds(from: string, to: string): DateBounds {
  const fromDay = from ? parseDay(from) : null;
  const toDay = to ? parseDay(to) : null;
  if ((from && !fromDay) || (to && !toDay)) {
    return { gte: null, lt: null, error: "Enter dates as day, month and year." };
  }
  if (fromDay && toDay && fromDay > toDay) {
    return { gte: null, lt: null, error: "The From date is after the To date." };
  }
  const end = toDay ? new Date(toDay.getTime() + 24 * 60 * 60 * 1000) : null;
  return {
    gte: fromDay ? fromDay.toISOString() : null,
    lt: end ? end.toISOString() : null,
    error: null,
  };
}

export type ChangeRow = { key: string; before: string | null; after: string | null };

function show(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value) && value.every((v) => typeof v !== "object" || v === null)) {
    return value.map((v) => String(v)).join(", ");
  }
  return JSON.stringify(value);
}

/** The fields an audit row records. With both sides present, only the
 * fields that differ; with one side missing (a creation or a removal),
 * every field on the other side. Sorted by field name. */
export function describeChanges(
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null,
): ChangeRow[] {
  const keys = new Set([...Object.keys(before ?? {}), ...Object.keys(after ?? {})]);
  const rows: ChangeRow[] = [];
  for (const key of [...keys].sort()) {
    const b = before ? show(before[key]) : null;
    const a = after ? show(after[key]) : null;
    if (before && after && b === a) continue;
    rows.push({ key, before: b, after: a });
  }
  return rows;
}
