import { supabase } from "@/lib/supabase";

// The staff lead list (slice 13). No role reads admissions_leads itself;
// list_admissions_leads decides who sees what: the Manager and the
// Admissions Officer get every field, the Auditor gets email and phone
// masked, everyone else is refused.

export type LeadRow = {
  id: string;
  createdAt: string;
  name: string;
  email: string | null;
  phone: string | null;
  gradeInterest: string | null;
  source: string;
  consentToMarketing: boolean;
  unsubscribedAt: string | null;
  utmSource: string | null;
  utmMedium: string | null;
  utmCampaign: string | null;
};

/** Newest first. With leadId, only that lead (the staff alert's link). */
export async function listLeads(opts: {
  limit: number;
  offset: number;
  leadId?: string;
}): Promise<{ rows: LeadRow[]; total: number }> {
  const { data, error } = await supabase.rpc("list_admissions_leads", {
    p_limit: opts.limit,
    p_offset: opts.offset,
    p_lead_id: opts.leadId,
  });
  if (error) throw error;
  const rows = (data ?? []).map((r) => ({
    id: r.id,
    createdAt: r.created_at,
    name: r.name,
    email: r.email,
    phone: r.phone,
    gradeInterest: r.grade_interest,
    source: r.source,
    consentToMarketing: r.consent_to_marketing,
    unsubscribedAt: r.bulk_email_unsubscribed_at,
    utmSource: r.utm_source,
    utmMedium: r.utm_medium,
    utmCampaign: r.utm_campaign,
  }));
  return { rows, total: Number(data?.[0]?.total_count ?? 0) };
}
