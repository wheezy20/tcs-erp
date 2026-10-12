import { useEffect, useState } from "react";
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
  getOfferStatus,
  hasDecideCapability,
  type Decision,
  type OfferStatus,
} from "@/modules/admissions/data/decisions";
import {
  changeDecision,
  generateOffer,
  recordDecision,
  recordOfferResponse,
  resetOffer,
  type IssuedOffer,
} from "@/modules/admissions/data/mutations";
import { listStaffNames } from "@/modules/admissions/data/reference";
import { EnrolmentControls } from "@/modules/admissions/components/enrolment-controls";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  canGenerateOffer,
  canRecordDecision,
  canRecordOfferResponse,
  canResetOffer,
  decisionChangeTargets,
  offerLink,
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
  // The raw offer token, held only here: never in a store, cache, URL, toast
  // or browser storage. Gone when this panel unmounts (leaving the page or
  // switching application or user) or when dismissed.
  const [issued, setIssued] = useState<IssuedOffer | null>(null);

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
    ? { response: offerStatus.response, effectiveResponse: offerStatus.effectiveResponse }
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
        issued={issued}
        onIssued={setIssued}
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

function OfferSection({
  app,
  role,
  cap,
  decisionType,
  offer,
  offerStatus,
  issued,
  onIssued,
  onDone,
}: {
  app: ApplicationSummary;
  role: StaffRole | undefined;
  cap: DecideCapability;
  decisionType: string | null;
  offer: OfferState;
  offerStatus: OfferStatus | null;
  issued: IssuedOffer | null;
  onIssued: (o: IssuedOffer | null) => void;
  onDone: () => Promise<void>;
}) {
  const generatable = canGenerateOffer(role, cap, app.stage, decisionType, offer);
  const resettable = canResetOffer(role, cap, app.stage, decisionType, offer);
  const respondable = canRecordOfferResponse(role, cap, app.stage, decisionType, offer);
  if (!offerStatus && !generatable && !issued) return null;

  return (
    <div className="mt-6 border-t pt-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          Offer
        </h3>
        <div className="flex flex-wrap gap-2">
          {generatable && (
            <ConfirmAction
              label="Generate offer"
              title="Generate offer"
              body="This moves the application to Offer and creates a link for the parent. The link is shown once."
              run={() => generateOffer(app.id)}
              onResult={onIssued}
              onDone={onDone}
              success="Offer generated"
            />
          )}
          {respondable && <OfferResponseDialog applicationId={app.id} onDone={onDone} />}
          {resettable && (
            <ConfirmAction
              label="Reset offer"
              variant="outline"
              title="Reset offer"
              body="The old link stops working, a new link is created, and a new expiry starts from today. The application moves back to Offer."
              run={() => resetOffer(app.id)}
              onResult={onIssued}
              onDone={onDone}
              success="Offer reset"
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
            </dd>
          </div>
          <div>
            <dt className="text-xs uppercase tracking-wide text-muted-foreground">Sent</dt>
            <dd className="mt-1 font-medium">
              {offerStatus.sentAt ? dateTime.format(new Date(offerStatus.sentAt)) : "Not given"}
            </dd>
          </div>
          <div>
            <dt className="text-xs uppercase tracking-wide text-muted-foreground">Expires</dt>
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

      {issued && <OneTimeLink issued={issued} onDismiss={() => onIssued(null)} />}
    </div>
  );
}

function ConfirmAction({
  label,
  variant = "default",
  title,
  body,
  run,
  onResult,
  onDone,
  success,
}: {
  label: string;
  variant?: "default" | "outline";
  title: string;
  body: string;
  run: () => Promise<IssuedOffer>;
  onResult: (o: IssuedOffer) => void;
  onDone: () => Promise<void>;
  success: string;
}) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);

  async function confirm() {
    setSaving(true);
    try {
      const issued = await run();
      onResult(issued);
      toast.success(success);
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not update the offer."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <Button variant={variant} onClick={() => setOpen(true)}>
        {label}
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{body}</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={confirm} disabled={saving}>
            {saving ? "Working…" : label}
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

/** The parent link, shown once. Plain text with a Copy button, never a
 * clickable link: the response page doesn't exist until slice 11. */
function OneTimeLink({ issued, onDismiss }: { issued: IssuedOffer; onDismiss: () => void }) {
  const [link, setLink] = useState("");
  useEffect(() => {
    setLink(offerLink(window.location.origin, issued.token));
  }, [issued.token]);

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      toast.success("Link copied");
    } catch {
      toast.error("Couldn't copy. Select the text and copy it by hand.");
    }
  }

  return (
    <div className="mt-4 rounded-md border border-amber-400/50 bg-amber-50 p-3 text-sm dark:bg-amber-950/30">
      <p className="font-medium">Not live yet, do not send this link.</p>
      <p className="mt-1 text-muted-foreground">
        The parent response page isn't built yet, so this link won't work for a parent. Until it is,
        record the parent's answer yourself with Record response. The link is shown only once; a
        reset later gives a new one.
      </p>
      <div className="mt-2 flex items-center gap-2">
        <code className="min-w-0 flex-1 select-all break-all rounded border bg-background px-2 py-1.5 font-mono text-xs">
          {link}
        </code>
        <Button size="sm" type="button" onClick={copy} disabled={!link}>
          Copy
        </Button>
      </div>
      {issued.expiresAt && (
        <p className="mt-2 text-xs text-muted-foreground">
          Expires {dateTime.format(new Date(issued.expiresAt))}.
        </p>
      )}
      <Button size="sm" variant="ghost" className="mt-2" onClick={onDismiss}>
        Hide link
      </Button>
    </div>
  );
}
