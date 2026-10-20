import { supabase } from "@/lib/supabase";
import type { ApplicationEmailRow, EmailHealth } from "@/modules/admissions/emails";

// The admissions email outbox (slice 12). No role reads the outbox table
// itself; these four functions decide who sees what. Recipients come back
// masked, and a staff alert never shows its address.

export type EmailRow = {
  id: string;
  kind: string;
  recipientMasked: string | null;
  references: string[];
  applicationIds: string[];
  status: string;
  attempts: number;
  lastErrorClass: string | null;
  lastHttpStatus: number | null;
  createdAt: string;
  nextAttemptAt: string;
  sentAt: string | null;
  requeuedAt: string | null;
};

/** Manager and Auditor. Newest first, at most 200. */
export async function listEmails(status: string | null): Promise<EmailRow[]> {
  const { data, error } = await supabase.rpc("list_admissions_emails", {
    p_status: status ?? undefined,
    p_limit: 200,
  });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    id: r.id,
    kind: r.kind,
    recipientMasked: r.recipient_masked,
    references: r.references ?? [],
    applicationIds: r.application_ids ?? [],
    status: r.status,
    attempts: r.attempts,
    lastErrorClass: r.last_error_class,
    lastHttpStatus: r.last_http_status,
    createdAt: r.created_at,
    nextAttemptAt: r.next_attempt_at,
    sentAt: r.sent_at,
    requeuedAt: r.requeued_at,
  }));
}

/** Manager and Auditor. */
export async function getEmailHealth(): Promise<EmailHealth> {
  const { data, error } = await supabase.rpc("get_admissions_email_health");
  if (error) throw error;
  const h = data?.[0];
  return {
    waiting: h?.waiting ?? 0,
    failed: h?.failed ?? 0,
    suppressed: h?.suppressed ?? 0,
    expired: h?.expired ?? 0,
    lastRunAt: h?.last_run_at ?? null,
    lastSuccessAt: h?.last_success_at ?? null,
    ceilingReachedAt: h?.ceiling_reached_at ?? null,
    configError: h?.config_error ?? false,
  };
}

/** Anyone who can see the application. Parent confirmations only, with no
 * address. */
export async function getApplicationEmailStatus(
  applicationId: string,
): Promise<ApplicationEmailRow[]> {
  const { data, error } = await supabase.rpc("get_application_email_status", {
    p_application_id: applicationId,
  });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    status: r.status,
    emails: r.emails,
    lastSentAt: r.last_sent_at,
  }));
}

/** Manager only. Returns how many failed emails were put back in the queue. */
export async function retryEmails(ids: string[]): Promise<number> {
  const { data, error } = await supabase.rpc("requeue_admissions_emails", { p_ids: ids });
  if (error) throw error;
  return data ?? 0;
}
