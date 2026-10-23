// The staff offer panel's wording (admissions slice 11; D-11c, D-11h,
// D-11j). Pure functions only, so they can be unit tested. The database
// decides who may send, how often and to whom; this file only words it.

export type OfferSend = "generate" | "reset" | "resend";

export function addresses(n: number): string {
  return n === 1 ? "1 address" : `${n} addresses`;
}

/** The limit, as staff read it (offer_links_day, D-11h). */
export const OFFER_SEND_LIMIT_NOTE =
  "An offer's link can be emailed at most 3 times in 24 hours. Generate offer, Reset offer and Send link again all count.";

/** What to do when the limit stops a reset that was meant to kill a link
 * someone else may have. */
export const OFFER_LIMIT_HINT =
  "To stop the current link at once, change the decision instead: that withdraws the offer, and every link stops working.";

/** The confirm step's text before a send (D-11c, changed by Eyram): how
 * many addresses are emailed right now. */
export function sendConfirmBody(kind: OfferSend, n: number): string {
  const emailed =
    n === 0
      ? "No guardian on this application has an email address, so no email is sent. Record the parent's answer with Record response when they reply."
      : `The offer link is emailed to ${addresses(n)} now.`;
  switch (kind) {
    case "generate":
      return `This moves the application to Offer. ${emailed}`;
    case "reset":
      return `Any earlier link stops working at once, and the offer starts again with a new respond by date. ${emailed}`;
    case "resend":
      return `Any earlier link stops working at once. The respond by date stays the same. ${emailed}`;
  }
}

/** The confirm step's extra line when the application form named guardian
 * addresses that are not on the family record (slice 11, decided by Eyram
 * 2026-10-23): the offer link is a credential, so it goes only to guardians
 * on record. Null when there are none. */
export function notOnRecordLine(n: number): string | null {
  if (n <= 0) return null;
  return n === 1
    ? "1 address from the application form is not on the family record and will not get the link."
    : `${n} addresses from the application form are not on the family record and will not get the link.`;
}

export const SEND_TITLES: Record<OfferSend, string> = {
  generate: "Generate offer",
  reset: "Reset offer",
  resend: "Send link again",
};

/** The toast after a send. */
export function sendDone(kind: OfferSend, emailsQueued: number): string {
  const what =
    kind === "generate" ? "Offer generated" : kind === "reset" ? "Offer reset" : "New link queued";
  return emailsQueued === 0
    ? `${what}. No email was sent: no guardian has an email address.`
    : `${what}. The link is being emailed to ${addresses(emailsQueued)}.`;
}

/** A send refused by the daily limit gets the hint as well; anything else
 * keeps the database's own message. */
export function sendErrorMessage(details: unknown, message: string): string {
  return details === "offer_link_limit" ? `${message} ${OFFER_LIMIT_HINT}` : message;
}

export const OFFER_EMAIL_STATUS_LABELS: Record<string, string> = {
  pending: "Waiting to be sent",
  sending: "Sending",
  sent: "Sent",
  failed: "Failed. A Manager can retry it on the Admissions Emails page.",
  expired: "Not sent, no longer needed",
};

/** After this long, a waiting link email is worth explaining. */
export const OFFER_WAITING_NOTE_AFTER_MS = 10 * 60 * 1000;

/** The plain note for a link email still waiting (Eyram: "mail is off or at
 * the ceiling, so the new link is waiting"). Null when nothing needs
 * explaining. */
export function offerWaitingNote(
  emails: Array<{ status: string; createdAt: string }>,
  now: number,
  /** True after a reset or a resend (link generation above 1): an earlier
   * link existed and has already stopped working. */
  earlierLinkStopped: boolean,
): string | null {
  const stuck = emails.some(
    (e) =>
      (e.status === "pending" || e.status === "sending") &&
      now - Date.parse(e.createdAt) > OFFER_WAITING_NOTE_AFTER_MS,
  );
  if (!stuck) return null;
  const note =
    "The new link has not gone out yet. Email sending may be switched off, or today's email limit may have been reached. It goes out on its own when sending resumes, as long as the offer is still open.";
  return earlierLinkStopped
    ? `${note} The earlier link has already stopped working, so you may want to phone the parent.`
    : note;
}

/** Who gave the response, after the status badge. */
export function responseSourceLabel(source: string | null): string | null {
  if (source === "offer_link") return "through the offer link";
  if (source === "staff") return "recorded by staff";
  return null;
}

/** The correction dialog's text (D-11j): what happens to the stage. */
export function correctionBody(target: "accepted" | "declined"): string {
  return target === "declined"
    ? "The parent accepted through the offer link. Recording a decline instead moves the application to Offer declined."
    : "The parent declined through the offer link. Recording an acceptance instead moves the application back to Offer. This is refused once the respond by date has passed; reset the offer then.";
}

export const CORRECTION_REASON_MAX = 300;

/** Null when the reason will be accepted; otherwise what is wrong. The
 * database checks the same rule. */
export function correctionReasonProblem(reason: string): string | null {
  const r = reason.trim();
  if (r === "") return "Give a short reason.";
  if (r.length > CORRECTION_REASON_MAX)
    return `Keep the reason to ${CORRECTION_REASON_MAX} characters.`;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(r)) return "Keep the reason on one line.";
  return null;
}
