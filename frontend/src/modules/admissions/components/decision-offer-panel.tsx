import { useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Textarea } from "@/components/ui/textarea";
import type { StaffRole } from "@/data/auth-store";
import type { ApplicationSummary } from "@/modules/admissions/data/application-detail";
import {
  getDecision,
  getOfferEmailStatus,
  getOfferStatus,
  hasDecideCapability,
  type Decision,
  type OfferStatus,
} from "@/modules/admissions/data/decisions";
import {
  changeDecision,
  correctOfferResponse,
  generateOffer,
  previewOfferRecipients,
  recordDecision,
  recordOfferResponse,
  resendOfferLink,
  resetOffer,
  type SentOffer,
} from "@/modules/admissions/data/mutations";
import { listStaffNames } from "@/modules/admissions/data/reference";
import { getMatchDifferences } from "@/modules/admissions/data/submission-check";
import { guardiansNotOnRecord } from "@/modules/admissions/submission-check";
import { EnrolmentControls } from "@/modules/admissions/components/enrolment-controls";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  OFFER_EMAIL_STATUS_LABELS,
  OFFER_SEND_LIMIT_NOTE,
  SEND_TITLES,
  CORRECTION_REASON_MAX,
  correctionBody,
  notOnRecordLine,
  correctionReasonProblem,
  offerWaitingNote,
  responseSourceLabel,
  sendConfirmBody,
  sendDone,
  sendErrorMessage,
  type OfferSend,
} from "@/modules/admissions/offer-panel";
import {
  canGenerateOffer,
  canRecordDecision,
  canRecordOfferResponse,
  canResendOfferLink,
  canResetOffer,
  decisionChangeTargets,
  offerCorrectionTarget,
  type DecideCapability,
  type OfferState,
} from "@/modules/admissions/permissions";
import { getErrorMessage } from "@/lib/utils";

const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

const DECISION_LABELS: Record<string, string> = {
  accepted: "Accepted",
  waitlisted: "Waitlisted",
  rejected: "Rejected",
};

const OFFER_LABELS: Record<string, string> = {
  pending: "Waiting for the parent",
  accepted: "Accepted by the parent",
  declined: "Declined by the parent",
  expired: "Expired",
  withdrawn: "Withdrawn",
};

const OFFER_TONE: Record<string, "default" | "secondary" | "outline" | "destructive"> = {
  pending: "secondary",
  accepted: "default",
  declined: "destructive",
  expired: "outline",
  withdrawn: "outline",
};

/** Decision, offer and enrolment for one application. Mounted only after
 * the application itself was found, so the not-found page is unchanged.
 * Every control mirrors an RPC refusal for display only; the RPCs decide. */
export function DecisionOfferPanel({
  app,
  role,
  onChanged,
}: {
  app: ApplicationSummary;
  role: StaffRole | undefined;
  onChanged: () => Promise<void>;
}) {
  const capRes = useLoad(hasDecideCapability, [], "Couldn't check your permission.");
  const cap: DecideCapability = capRes.error
    ? "error"
    : capRes.data === undefined
      ? "checking"
      : capRes.data
        ? "granted"
        : "denied";

  // RLS gives an officer no decision or offer rows without the capability,
  // so an officer's panel reads them only once it's granted.
  const canRead = role === "Manager" || role === "Auditor" || cap === "granted";

  if (role === "Admissions Officer" && cap !== "granted") {
    return (
      <section className="card-surface p-6">
        <h2 className="text-sm font-semibold">Decision and offer</h2>
        <CapabilityMessage cap={cap} role={role} />
      </section>
    );
  }
  if (!canRead) return null;
  return <DecisionOfferBody app={app} role={role} cap={cap} onChanged={onChanged} />;
}

function CapabilityMessage({ cap, role }: { cap: DecideCapability; role: StaffRole | undefined }) {
  if (cap === "checking") return <p className="mt-3 text-sm text-muted-foreground">Loading…</p>;
  if (cap === "error") {
    return (
      <p className="mt-3 text-sm text-destructive">
        Couldn't check your decide permission, so no actions are shown. Reload the page.
      </p>
    );
  }
  if (cap === "denied" && role === "Manager") {
    return (
      <p className="mt-3 rounded-md border border-amber-400/50 bg-amber-50 px-3 py-2 text-sm dark:bg-amber-950/30">
        You can't record or change decisions or work with offers until you have the decide
        permission. A Manager grants it in Settings, Staff, Admissions access, and may grant it to
        themselves.
      </p>
    );
  }
  if (cap === "denied" && role === "Admissions Officer") {
    return (
      <p className="mt-3 text-sm text-muted-foreground">
        You don't have the decide permission, so decisions and offers aren't shown to you. Ask a
        Manager if you need it.
      </p>
    );
  }
  return null;
}

function DecisionOfferBody({
  app,
  role,
  cap,
  onChanged,
}: {
  app: ApplicationSummary;
  role: StaffRole | undefined;
  cap: DecideCapability;
  onChanged: () => Promise<void>;
}) {
  const decisionRes = useLoad(() => getDecision(app.id), [app.id], "Could not load the decision.");
  const offerRes = useLoad(() => getOfferStatus(app.id), [app.id], "Could not load the offer.");
  const names = useLoad(listStaffNames, [], "Could not load staff names.");

  const decision: Decision | null | undefined = decisionRes.data;
  const offerStatus: OfferStatus | null | undefined = offerRes.data;
  const loadError = decisionRes.error || offerRes.error;
  if (decision === undefined || offerStatus === undefined) {
    return (
      <section className="card-surface p-6">
        <h2 className="text-sm font-semibold">Decision and offer</h2>
        <p className={`mt-3 text-sm ${loadError ? "text-destructive" : "text-muted-foreground"}`}>
          {loadError || "Loading…"}
        </p>
      </section>
    );
  }

  const decisionType = decision?.decisionType ?? null;
  const offer: OfferState = offerStatus
    ? {
        response: offerStatus.response,
        effectiveResponse: offerStatus.effectiveResponse,
        responseSource: offerStatus.responseSource,
      }
    : null;

  async function refresh() {
    await Promise.all([decisionRes.reload(), offerRes.reload(), onChanged()]);
  }

  const recordable = canRecordDecision(role, cap, app.stage, decisionType);
  const changeTargets = decisionChangeTargets(
    role,
    cap,
    app.stage,
    decisionType,
    offerStatus?.response ?? null,
  );

  return (
    <section className="card-surface p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-sm font-semibold">Decision and offer</h2>
        <div className="flex flex-wrap gap-2">
          {recordable && (
            <DecisionDialog
              mode="record"
              applicationId={app.id}
              targets={["accepted", "waitlisted", "rejected"]}
              current={null}
              onDone={refresh}
            />
          )}
          {changeTargets.length > 0 && (
            <DecisionDialog
              mode="change"
              applicationId={app.id}
              targets={changeTargets}
              current={decision}
              onDone={refresh}
            />
          )}
        </div>
      </div>

      {loadError && <p className="mt-3 text-sm text-destructive">{loadError}</p>}
      {role !== "Auditor" && <CapabilityMessage cap={cap} role={role} />}

      <div className="mt-4 space-y-1 text-sm">
        {decision ? (
          <>
            <p>
              <span className="font-medium">{DECISION_LABELS[decision.decisionType]}</span>
              <span className="text-muted-foreground">
                {" "}
                by {(decision.decidedBy && names.data?.get(decision.decidedBy)) ||
                  "unknown staff"}, {dateTime.format(new Date(decision.decidedAt))}
              </span>
            </p>
            {decision.notes && (
              <p className="whitespace-pre-wrap text-muted-foreground">{decision.notes}</p>
            )}
            {decisionType === "accepted" && offerStatus?.response === "accepted" && (
              <p className="text-xs text-muted-foreground">
                The parent has accepted the offer, so the decision can no longer leave Accepted.
              </p>
            )}
          </>
        ) : (
          <p className="text-muted-foreground">No decision yet.</p>
        )}
      </div>

      <OfferSection
        app={app}
        role={role}
        cap={cap}
        decisionType={decisionType}
        offer={offer}
        offerStatus={offerStatus}
        onDone={refresh}
      />

      <EnrolmentControls
        app={app}
        role={role}
        decisionType={decisionType}
        offer={offer}
        onDone={refresh}
      />
    </section>
  );
}

/* ---------------------------------------------------------------- decision */

function DecisionDialog({
  mode,
  applicationId,
  targets,
  current,
  onDone,
}: {
  mode: "record" | "change";
  applicationId: string;
  targets: string[];
  current: Decision | null;
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [type, setType] = useState("");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    try {
      const res =
        mode === "record"
          ? await recordDecision(applicationId, type, notes)
          : await changeDecision(applicationId, type, notes);
      toast.success(
        res.offerWithdrawn
          ? `Decision saved as ${DECISION_LABELS[type]}. The pending offer was withdrawn.`
          : `Decision saved as ${DECISION_LABELS[type]}`,
      );
      if (res.capacityWarning) toast.warning(res.capacityWarning, { duration: 20000 });
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not save the decision."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) {
          setType(current?.decisionType ?? "");
          setNotes(current?.notes ?? "");
        }
      }}
    >
      <Button variant={mode === "record" ? "default" : "outline"} onClick={() => setOpen(true)}>
        {mode === "record" ? "Record decision" : "Change decision"}
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{mode === "record" ? "Record decision" : "Change decision"}</DialogTitle>
          <DialogDescription>
            Waitlisted and rejected also move the stage. Moving away from Accepted withdraws a
            pending offer. The change is recorded in the audit log.
          </DialogDescription>
        </DialogHeader>
        <RadioGroup value={type} onValueChange={setType} className="gap-3">
          {targets.map((t) => (
            <div key={t} className="flex items-center gap-2">
              <RadioGroupItem value={t} id={`decision-${t}`} />
              <Label htmlFor={`decision-${t}`}>{DECISION_LABELS[t]}</Label>
            </div>
          ))}
        </RadioGroup>
        <div className="space-y-2">
          <Label htmlFor="decision-notes">Notes</Label>
          <Textarea
            id="decision-notes"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={4}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={saving || !type}>
            {saving ? "Saving…" : "Save decision"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* ---------------------------------------------------------------- offer */

// Slice 11: the offer link is emailed to the guardians when an offer is
// generated, reset or sent again; it is made when each email is sent and
// exists only in the email, so this panel never sees it. Every send has a
// confirm step that says how many addresses are emailed now (D-11c).
function OfferSection({
  app,
  role,
  cap,
  decisionType,
  offer,
  offerStatus,
  onDone,
}: {
  app: ApplicationSummary;
  role: StaffRole | undefined;
  cap: DecideCapability;
  decisionType: string | null;
  offer: OfferState;
  offerStatus: OfferStatus | null;
  onDone: () => Promise<void>;
}) {
  const generatable = canGenerateOffer(role, cap, app.stage, decisionType, offer);
  const resettable = canResetOffer(role, cap, app.stage, decisionType, offer);
  const respondable = canRecordOfferResponse(role, cap, app.stage, decisionType, offer);
  const resendable = canResendOfferLink(role, cap, app.stage, decisionType, offer);
  const correction = offerCorrectionTarget(role, cap, app.stage, decisionType, offer);
  const generation = offerStatus?.linkGeneration ?? 0;
  const emails = useLoad(
    () => (offerStatus ? getOfferEmailStatus(app.id) : Promise.resolve([])),
    [app.id, generation, offerStatus?.response],
    "Could not load the offer emails.",
  );
  if (!offerStatus && !generatable) return null;

  async function done() {
    await Promise.all([onDone(), emails.reload()]);
  }
  const source = responseSourceLabel(offerStatus?.responseSource ?? null);
  const waiting = offerWaitingNote(emails.data ?? [], Date.now(), generation > 1);

  return (
    <div className="mt-6 border-t pt-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          Offer
        </h3>
        <div className="flex flex-wrap gap-2">
          {generatable && (
            <SendConfirm kind="generate" applicationId={app.id} run={generateOffer} onDone={done} />
          )}
          {resendable && (
            <SendConfirm
              kind="resend"
              variant="outline"
              applicationId={app.id}
              run={resendOfferLink}
              onDone={done}
            />
          )}
          {respondable && <OfferResponseDialog applicationId={app.id} onDone={done} />}
          {correction && (
            <CorrectionDialog applicationId={app.id} target={correction} onDone={done} />
          )}
          {resettable && (
            <SendConfirm
              kind="reset"
              variant="outline"
              applicationId={app.id}
              run={resetOffer}
              onDone={done}
            />
          )}
        </div>
      </div>

      {offerStatus && (
        <dl className="mt-3 grid gap-3 text-sm sm:grid-cols-3">
          <div>
            <dt className="text-xs uppercase tracking-wide text-muted-foreground">Status</dt>
            <dd className="mt-1">
              <Badge variant={OFFER_TONE[offerStatus.effectiveResponse] ?? "outline"}>
                {OFFER_LABELS[offerStatus.effectiveResponse] ?? offerStatus.effectiveResponse}
              </Badge>
              {source && <span className="ml-2 text-xs text-muted-foreground">{source}</span>}
            </dd>
          </div>
          <div>
            <dt className="text-xs uppercase tracking-wide text-muted-foreground">Sent</dt>
            <dd className="mt-1 font-medium">
              {offerStatus.sentAt ? dateTime.format(new Date(offerStatus.sentAt)) : "Not given"}
            </dd>
          </div>
          <div>
            <dt className="text-xs uppercase tracking-wide text-muted-foreground">Respond by</dt>
            <dd className="mt-1 font-medium">
              {offerStatus.expiresAt ? dateTime.format(new Date(offerStatus.expiresAt)) : "Never"}
            </dd>
          </div>
        </dl>
      )}
      {offerStatus?.effectiveResponse === "expired" && offerStatus.response === "pending" && (
        <p className="mt-2 text-xs text-muted-foreground">
          This offer has expired. The stage stays at Offer until the expiry job runs; reset the
          offer to send a new one.
        </p>
      )}

      {offerStatus && (
        <div className="mt-4 text-sm">
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Offer link emails</p>
          {emails.error ? (
            <p className="mt-1 text-destructive">{emails.error}</p>
          ) : emails.data === undefined ? (
            <p className="mt-1 text-muted-foreground">Loading…</p>
          ) : emails.data.length === 0 ? (
            <p className="mt-1 text-muted-foreground">
              {generation === 0
                ? "No link has been emailed for this offer."
                : "No email went with the latest link: no guardian had an email address. Record the parent's answer with Record response."}
            </p>
          ) : (
            <ul className="mt-1 space-y-1">
              {emails.data.map((e, i) => (
                <li key={`${e.recipientMasked}-${i}`} className="flex flex-wrap gap-x-2">
                  <span className="font-mono text-xs">{e.recipientMasked}</span>
                  <span className="text-muted-foreground">
                    {OFFER_EMAIL_STATUS_LABELS[e.status] ?? e.status}
                    {e.status === "sent" && e.sentAt
                      ? `, ${dateTime.format(new Date(e.sentAt))}`
                      : ""}
                  </span>
                </li>
              ))}
            </ul>
          )}
          {waiting && <p className="mt-2 text-xs text-amber-700 dark:text-amber-400">{waiting}</p>}
        </div>
      )}
    </div>
  );
}

/** Generate offer, Reset offer or Send link again, with the confirm step:
 * the address count is asked for when the dialog opens. */
function SendConfirm({
  kind,
  variant = "default",
  applicationId,
  run,
  onDone,
}: {
  kind: OfferSend;
  variant?: "default" | "outline";
  applicationId: string;
  run: (applicationId: string) => Promise<SentOffer>;
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [count, setCount] = useState<number | null>(null);
  const [countError, setCountError] = useState<string | null>(null);
  const [notOnRecord, setNotOnRecord] = useState(0);
  const [saving, setSaving] = useState(false);

  async function openDialog() {
    setOpen(true);
    setCount(null);
    setCountError(null);
    setNotOnRecord(0);
    // Advisory only: if the match flags can't be read, the line is left out
    // and the send is not blocked.
    void getMatchDifferences(applicationId)
      .then((d) => setNotOnRecord(guardiansNotOnRecord(d)))
      .catch(() => setNotOnRecord(0));
    try {
      setCount(await previewOfferRecipients(applicationId));
    } catch (err) {
      setCountError(getErrorMessage(err, "Could not count the guardian addresses."));
    }
  }
  const unrecorded = notOnRecordLine(notOnRecord);

  async function confirm() {
    setSaving(true);
    try {
      const sent = await run(applicationId);
      toast.success(sendDone(kind, sent.emailsQueued));
      setOpen(false);
      await onDone();
    } catch (err) {
      const details = (err as { details?: unknown } | null)?.details;
      toast.error(sendErrorMessage(details, getErrorMessage(err, "Could not update the offer.")));
    } finally {
      setSaving(false);
    }
  }

  const title = SEND_TITLES[kind];
  return (
    <Dialog open={open} onOpenChange={(o) => (o ? void openDialog() : setOpen(false))}>
      <Button variant={variant} onClick={() => void openDialog()}>
        {title}
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {countError
              ? countError
              : count === null
                ? "Counting the guardian addresses…"
                : sendConfirmBody(kind, count)}
          </DialogDescription>
        </DialogHeader>
        {unrecorded && count !== null && <p className="text-sm">{unrecorded}</p>}
        <p className="text-xs text-muted-foreground">{OFFER_SEND_LIMIT_NOTE}</p>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={confirm} disabled={saving || count === null}>
            {saving ? "Working…" : title}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Correct a response the parent gave through the link (D-11j), with a
 * short reason that goes into the audit log. */
function CorrectionDialog({
  applicationId,
  target,
  onDone,
}: {
  applicationId: string;
  target: "accepted" | "declined";
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [touched, setTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const problem = correctionReasonProblem(reason);

  async function save() {
    setTouched(true);
    if (problem) return;
    setSaving(true);
    try {
      await correctOfferResponse(applicationId, target, reason.trim());
      toast.success(target === "declined" ? "Recorded as declined" : "Recorded as accepted");
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not correct the response."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) {
          setReason("");
          setTouched(false);
        }
      }}
    >
      <Button variant="outline" onClick={() => setOpen(true)}>
        Correct response
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {target === "declined" ? "Record a decline instead" : "Record an acceptance instead"}
          </DialogTitle>
          <DialogDescription>{correctionBody(target)}</DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor="offer-correction-reason">Reason</Label>
          <Textarea
            id="offer-correction-reason"
            value={reason}
            maxLength={CORRECTION_REASON_MAX}
            onChange={(e) => setReason(e.target.value.replace(/[\r\n]+/g, " "))}
            onBlur={() => setTouched(true)}
            rows={2}
          />
          <p className="text-xs text-muted-foreground">
            Kept in the audit log. Say what happened, for example that the parent phoned to say they
            clicked the wrong button. Please don't include names or contact details.
          </p>
          {touched && problem && <p className="text-xs text-destructive">{problem}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save correction"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function OfferResponseDialog({
  applicationId,
  onDone,
}: {
  applicationId: string;
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [response, setResponse] = useState<"" | "accepted" | "declined">("");
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!response) return;
    setSaving(true);
    try {
      await recordOfferResponse(applicationId, response);
      toast.success(response === "accepted" ? "Offer accepted" : "Offer declined");
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not record the response."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) setResponse("");
      }}
    >
      <Button variant="outline" onClick={() => setOpen(true)}>
        Record response
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Record the parent's response</DialogTitle>
          <DialogDescription>
            Use this when the parent answered by phone, on paper or in person. Declined moves the
            application to Offer declined.
          </DialogDescription>
        </DialogHeader>
        <RadioGroup
          value={response}
          onValueChange={(v) => setResponse(v as "accepted" | "declined")}
          className="gap-3"
        >
          <div className="flex items-center gap-2">
            <RadioGroupItem value="accepted" id="offer-accepted" />
            <Label htmlFor="offer-accepted">The parent accepted</Label>
          </div>
          <div className="flex items-center gap-2">
            <RadioGroupItem value="declined" id="offer-declined" />
            <Label htmlFor="offer-declined">The parent declined</Label>
          </div>
        </RadioGroup>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={saving || !response}>
            {saving ? "Saving…" : "Record response"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
