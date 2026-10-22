import { supabase } from "@/lib/supabase";

// Reads for the decision and offer panel (slices 6a and 6b). RLS decides
// who sees which row: Manager and Auditor see every decision and offer; an
// Admissions Officer sees them only while holding the decide capability and
// with the application in scope. Offers are read from application_offer_status
// only, never from the offers table, and never the token hash.

/** The live has_admissions_capability('decide') result: false for an
 * Auditor, and for a Manager or officer without the can_decide row. */
export async function hasDecideCapability(): Promise<boolean> {
  const { data, error } = await supabase.rpc("has_admissions_capability", {
    p_capability: "decide",
  });
  if (error) throw error;
  return data === true;
}

export type Decision = {
  decisionType: string;
  decidedBy: string | null;
  decidedAt: string;
  notes: string;
};

export async function getDecision(applicationId: string): Promise<Decision | null> {
  const { data, error } = await supabase
    .from("application_decisions")
    .select("decision_type, decided_by, decided_at, notes")
    .eq("application_id", applicationId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    decisionType: data.decision_type,
    decidedBy: data.decided_by,
    decidedAt: data.decided_at,
    notes: data.notes,
  };
}

export type OfferStatus = {
  sentAt: string | null;
  expiresAt: string | null;
  /** The stored response. */
  response: string;
  respondedAt: string | null;
  /** The response as it stands now: a pending offer past its expiry is
   * "expired" here (computed by the view) before anything writes it. */
  effectiveResponse: string;
  /** Who gave the response (slice 11): the parent through the link, or
   * staff (a reply by phone, or a correction). Null while none is held. */
  responseSource: "offer_link" | "staff" | null;
  /** Moves up with every send; 0 means no link was ever sent. */
  linkGeneration: number;
};

export async function getOfferStatus(applicationId: string): Promise<OfferStatus | null> {
  const { data, error } = await supabase
    .from("application_offer_status")
    .select(
      "sent_at, expires_at, response, responded_at, effective_response, response_source, link_generation",
    )
    .eq("application_id", applicationId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    sentAt: data.sent_at,
    expiresAt: data.expires_at,
    response: data.response ?? "",
    respondedAt: data.responded_at,
    effectiveResponse: data.effective_response ?? "",
    responseSource:
      data.response_source === "offer_link" || data.response_source === "staff"
        ? data.response_source
        : null,
    linkGeneration: data.link_generation ?? 0,
  };
}

/** One email of the current link (slice 11), address masked by the
 * database. */
export type OfferEmail = {
  recipientMasked: string;
  status: string;
  attempts: number;
  createdAt: string;
  sentAt: string | null;
};

export async function getOfferEmailStatus(applicationId: string): Promise<OfferEmail[]> {
  const { data, error } = await supabase.rpc("get_offer_email_status", {
    p_application_id: applicationId,
  });
  if (error) throw error;
  return (data ?? []).map((r) => ({
    recipientMasked: r.recipient_masked,
    status: r.status,
    attempts: r.attempts,
    createdAt: r.created_at,
    sentAt: r.sent_at,
  }));
}
