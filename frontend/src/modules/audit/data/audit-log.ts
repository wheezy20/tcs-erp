import { supabase } from "@/lib/supabase";

// The Audit Log list. Reads audit_log directly: it has no client write path
// and its select policy (audit_log_select, 20261019100000) decides which
// rows come back, so an Accountant simply gets no admissions rows. Explicit
// columns only.

export const PAGE_SIZE = 50;
export const ALL = "all";

const COLUMNS = "id, occurred_at, action, entity_table, entity_id, actor_id, before, after";

export type AuditLogRow = {
  id: string;
  occurredAt: string;
  action: string;
  entityTable: string;
  entityId: string;
  /** Null only for application_offer_responded: a parent, through the offer link. */
  actorId: string | null;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
};

export type AuditLogQuery = {
  action: string;
  /** occurred_at >= this, or no lower bound. */
  gte: string | null;
  /** occurred_at < this, or no upper bound. */
  lt: string | null;
  page: number;
};

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

export async function listAuditLog(
  q: AuditLogQuery,
): Promise<{ rows: AuditLogRow[]; total: number }> {
  const from = q.page * PAGE_SIZE;
  let query = supabase
    .from("audit_log")
    .select(COLUMNS, { count: "exact" })
    .order("occurred_at", { ascending: false })
    .order("id")
    .range(from, from + PAGE_SIZE - 1);
  if (q.action !== ALL) query = query.eq("action", q.action);
  if (q.gte) query = query.gte("occurred_at", q.gte);
  if (q.lt) query = query.lt("occurred_at", q.lt);

  const { data, error, count } = await query;
  if (error) throw error;
  return {
    total: count ?? 0,
    rows: (data ?? []).map((r) => ({
      id: r.id,
      occurredAt: r.occurred_at,
      action: r.action,
      entityTable: r.entity_table,
      entityId: r.entity_id,
      actorId: r.actor_id,
      before: asObject(r.before),
      after: asObject(r.after),
    })),
  };
}

/** Staff names by id, through list_staff_names() (any active staff member;
 * id and name only, former staff included). */
export async function listStaffNames(): Promise<Map<string, string>> {
  const { data, error } = await supabase.rpc("list_staff_names");
  if (error) throw error;
  return new Map((data ?? []).map((s) => [s.id, s.name]));
}
