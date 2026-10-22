// What the staff email page and the application page say about the
// admissions email outbox (slice 12). Pure functions only (no Supabase, no
// React) so they can be unit tested. The database decides everything:
// who may see what, what is sent, retried, suppressed or expired. This
// file only words it.

export const EMAIL_STATUSES = [
  "pending",
  "sending",
  "sent",
  "failed",
  "suppressed",
  "expired",
] as const;
export type EmailStatus = (typeof EMAIL_STATUSES)[number];

export const EMAIL_STATUS_LABELS: Record<EmailStatus, string> = {
  pending: "Waiting",
  sending: "Sending",
  sent: "Sent",
  failed: "Failed",
  suppressed: "Not sent, address limit",
  expired: "Expired, never sent",
};

/** One line under the status, for the rows that need explaining. */
export const EMAIL_STATUS_NOTES: Partial<Record<EmailStatus, string>> = {
  suppressed:
    "This address already had 4 confirmation emails in 24 hours, so this one was held back.",
  expired:
    "It waited more than 48 hours without being sent, so it was dropped and will never be sent.",
  failed: "Every attempt failed, or the address was refused. A Manager can retry it.",
};

export const EMAIL_KIND_LABELS: Record<string, string> = {
  inquiry_parent: "Enquiry confirmation",
  inquiry_staff: "Enquiry staff alert",
  application_parent: "Application confirmation",
  application_staff: "Application staff alert",
  pdf_gate: "Admissions Overview PDF",
  lead_staff: "Lead staff alert",
  offer: "Offer link",
  offer_staff: "Offer response staff alert",
};

/** The note under a status, worded for the email's kind: the PDF has its
 * own limit of 2 a day per address (slice 13); an offer link email is
 * dropped when a newer link replaces it or the offer is no longer open, and
 * may wait up to 7 days (slice 11). */
export function statusNote(kind: string, status: string): string | undefined {
  if (status === "suppressed" && kind === "pdf_gate") {
    return "This address already had 2 Admissions Overview emails in 24 hours, so this one was held back.";
  }
  if (status === "expired" && kind === "offer") {
    return "Never sent: a newer link replaced it, the offer was answered, withdrawn or expired, or it waited more than 7 days.";
  }
  return EMAIL_STATUS_NOTES[status as EmailStatus];
}

export const EMAIL_ERROR_LABELS: Record<string, string> = {
  network: "Network error",
  timeout: "Timed out",
  rate_limited: "Provider busy (rate limit)",
  provider_error: "Provider error",
  invalid_recipient: "Address or email refused",
  config: "Mail settings problem or a required file missing",
  conflict: "Already being sent",
  other: "Other error",
};

/** The filter choices on the email page, in order. */
export const EMAIL_FILTERS: Array<{ value: EmailStatus | "all"; label: string }> = [
  { value: "all", label: "All" },
  { value: "failed", label: "Failed" },
  { value: "expired", label: "Expired" },
  { value: "pending", label: "Waiting" },
  { value: "suppressed", label: "Not sent, address limit" },
  { value: "sent", label: "Sent" },
];

export type Tone = "ok" | "waiting" | "problem" | "none";

export function statusTone(status: string): Tone {
  if (status === "sent") return "ok";
  if (status === "pending" || status === "sending") return "waiting";
  return "problem";
}

/** Who the email went to, as staff may see it. */
export function recipientLabel(kind: string, masked: string | null): string {
  if (kind.endsWith("_staff")) return "Staff alert address";
  return masked ?? "";
}

/** Only failed rows can be retried, and only by a Manager. */
export function canRetryEmail(role: string | null | undefined, status: string): boolean {
  return role === "Manager" && status === "failed";
}

export type ApplicationEmailRow = { status: string; emails: number; lastSentAt: string | null };

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** The confirmation line on an application page. */
export function applicationEmailLine(rows: ApplicationEmailRow[]): { tone: Tone; text: string } {
  const count = (s: string) => rows.filter((r) => r.status === s).reduce((n, r) => n + r.emails, 0);
  const sent = count("sent");
  const waiting = count("pending") + count("sending");
  const failed = count("failed");
  const expired = count("expired");
  const held = count("suppressed");
  if (sent + waiting + failed + expired + held === 0) {
    return { tone: "none", text: "No confirmation email for this application." };
  }
  const parts: string[] = [];
  if (sent) parts.push(`sent to ${plural(sent, "address", "addresses")}`);
  if (waiting) parts.push(`${plural(waiting, "email", "emails")} waiting`);
  if (failed) parts.push(`${failed} failed`);
  if (expired) parts.push(`${expired} expired and never sent`);
  if (held) parts.push(`${held} held back by the address limit`);
  const text = `Confirmation email: ${parts.join(", ")}.`;
  const tone: Tone = failed || expired || held ? "problem" : waiting ? "waiting" : "ok";
  return { tone, text };
}

export type EmailHealth = {
  waiting: number;
  failed: number;
  suppressed: number;
  expired: number;
  /** Resume emails for saved applications that failed (slice 10). A count
   * only: staff never see those emails or who saved. */
  draftFailed: number;
  lastRunAt: string | null;
  lastSuccessAt: string | null;
  ceilingReachedAt: string | null;
  configError: boolean;
};

const STALL_MINUTES = 10;

function minutesSince(iso: string | null, now: Date): number | null {
  if (!iso) return null;
  return Math.floor((now.getTime() - new Date(iso).getTime()) / 60000);
}

/** The health strip's messages, most urgent first. */
export function healthMessages(h: EmailHealth, now: Date): Array<{ tone: Tone; text: string }> {
  const out: Array<{ tone: Tone; text: string }> = [];
  if (h.configError) {
    out.push({
      tone: "problem",
      text: "A mail setting is missing or was refused (the key, the sending domain or the enquiry link setting), or the Admissions Overview PDF is missing. The emails affected are waiting until this is fixed.",
    });
  }
  const sinceRun = minutesSince(h.lastRunAt, now);
  if (h.waiting > 0 && (sinceRun === null || sinceRun > STALL_MINUTES)) {
    out.push({
      tone: "problem",
      text:
        sinceRun === null
          ? `${plural(h.waiting, "email is", "emails are")} waiting and sending has never run. Sending may be switched off.`
          : `${plural(h.waiting, "email is", "emails are")} waiting and sending last ran ${sinceRun} minutes ago. Sending may be switched off or stopped.`,
    });
    out.push({
      tone: "waiting",
      text: "Any email that has waited more than 48 hours will be marked expired, and never sent, the next time sending runs.",
    });
  }
  const sinceCeiling = minutesSince(h.ceilingReachedAt, now);
  if (sinceCeiling !== null && sinceCeiling <= STALL_MINUTES) {
    out.push({
      tone: "waiting",
      text: "The daily sending limit, or the half of it kept for Admissions Overview emails, was reached. Waiting emails go out as the limit allows.",
    });
  }
  if (h.failed > 0) {
    out.push({
      tone: "problem",
      text: `${plural(h.failed, "email", "emails")} failed. A Manager can retry them.`,
    });
  }
  if (h.expired > 0) {
    out.push({
      tone: "problem",
      text: `${plural(h.expired, "email", "emails")} expired: each waited more than 48 hours and was never sent.`,
    });
  }
  if (h.draftFailed > 0) {
    out.push({
      tone: "problem",
      text: `${plural(h.draftFailed, "saved application link email", "saved application link emails")} failed. These are not listed and can't be retried here; a parent who saves again gets a new link.`,
    });
  }
  if (h.suppressed > 0) {
    out.push({
      tone: "waiting",
      text: `${plural(h.suppressed, "email was", "emails were")} held back because an address reached its daily limit.`,
    });
  }
  if (out.length === 0) {
    const sinceSent = minutesSince(h.lastSuccessAt, now);
    out.push({
      tone: "ok",
      text:
        h.waiting > 0
          ? `Sending. ${plural(h.waiting, "email is", "emails are")} waiting.`
          : sinceSent === null
            ? "Nothing waiting. No email has been sent yet."
            : "Nothing waiting. Sending is working.",
    });
  }
  return out;
}
