import { useRouter } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";

import { PublicNotice, PublicPage } from "@/modules/admissions/components/public-page-parts";
import { answerOffer, readOffer } from "@/modules/admissions/data/public-offer";
import {
  offerDate,
  readOfferFragment,
  type OfferDetails,
  type OfferResponse,
} from "@/modules/admissions/offer-page";
import { OFFER_COPY as COPY, PRIVACY_POLICY } from "@/modules/admissions/public-copy";

// /offer: the public offer page (admissions slice 11). The parent arrives
// from the offer email's private link, /offer#token=<64 hex>. The page reads
// the fragment once, removes it from the address bar through the router's
// history (so Back doesn't bring it back), and keeps the token only in this
// component's memory. It shows the offer (D-11a: first name, grade,
// academic year, campus, respond by date) and lets the parent accept or
// decline once, with a confirm step (D-11l). Nothing else is on the page.
// No sign-in and no AppShell (__root.tsx lists it as auth-free); every rule
// is enforced by the admissions-public Edge Function and respond_to_offer.

type View =
  | { kind: "missing" }
  | { kind: "loading" }
  | {
      kind: "open";
      details: OfferDetails;
      confirming: OfferResponse | null;
      sending: boolean;
      message: string | null;
    }
  | { kind: "done"; response: OfferResponse }
  | { kind: "answered"; response: OfferResponse }
  | { kind: "invalid" }
  | { kind: "loadFailed"; message: string };

export function OfferPage() {
  const router = useRouter();
  const [token, setToken] = useState<string | null>(null);
  const [view, setView] = useState<View>({ kind: "loading" });
  // Every state replaces the content (the clicked button goes away), so
  // focus moves to the new content and the region announces it.
  const bodyRef = useRef<HTMLDivElement>(null);
  const firstView = useRef(true);
  const viewKey = view.kind === "open" ? `open-${view.confirming ?? "none"}` : view.kind;
  useEffect(() => {
    if (firstView.current) {
      firstView.current = false;
      return;
    }
    bodyRef.current?.focus();
  }, [viewKey]);

  useEffect(() => {
    const t = readOfferFragment(window.location.hash);
    if (window.location.hash !== "") {
      router.history.replace(window.location.pathname);
    }
    setToken(t);
    if (!t) setView({ kind: "missing" });
    // Once, on arrival.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function load(t: string) {
    setView({ kind: "loading" });
    const r = await readOffer(t);
    if (r.kind === "open")
      setView({
        kind: "open",
        details: r.details,
        confirming: null,
        sending: false,
        message: null,
      });
    else if (r.kind === "answered") setView({ kind: "answered", response: r.response });
    else if (r.kind === "invalid") setView({ kind: "invalid" });
    else setView({ kind: "loadFailed", message: r.kind === "limit" ? COPY.limit : COPY.error });
  }

  useEffect(() => {
    if (token) void load(token);
  }, [token]);

  async function send(response: OfferResponse) {
    if (!token || view.kind !== "open") return;
    setView({ ...view, sending: true, message: null });
    const a = await answerOffer(token, response);
    if (a.kind === "recorded") setView({ kind: "done", response: a.response });
    else if (a.kind === "answered") setView({ kind: "answered", response: a.response });
    else if (a.kind === "invalid") setView({ kind: "invalid" });
    else
      setView({
        ...view,
        confirming: null,
        sending: false,
        message: a.kind === "limit" ? COPY.limit : COPY.error,
      });
  }

  let body;
  switch (view.kind) {
    case "loading":
      body = (
        <p className="tcs-subtitle" role="status">
          {COPY.loading}
        </p>
      );
      break;
    case "missing":
      body = (
        <PublicNotice title={COPY.missingTitle}>
          <p>{COPY.missingBody}</p>
        </PublicNotice>
      );
      break;
    case "invalid":
      body = (
        <PublicNotice title={COPY.invalidTitle}>
          <p>{COPY.invalidBody}</p>
        </PublicNotice>
      );
      break;
    case "loadFailed":
      body = (
        <PublicNotice title={COPY.pageTitle}>
          <p>{view.message}</p>
          <div className="tcs-step-nav">
            <button
              type="button"
              className="tcs-nav-btn tcs-primary"
              onClick={() => token && void load(token)}
            >
              {COPY.retry}
            </button>
          </div>
        </PublicNotice>
      );
      break;
    case "answered":
      body = (
        <PublicNotice title={COPY.answeredTitle}>
          <p>{COPY.answeredBody(view.response)}</p>
        </PublicNotice>
      );
      break;
    case "done":
      body =
        view.response === "accepted" ? (
          <PublicNotice title={COPY.acceptedTitle}>
            <p>{COPY.acceptedBody}</p>
          </PublicNotice>
        ) : (
          <PublicNotice title={COPY.declinedTitle}>
            <p>{COPY.declinedBody}</p>
          </PublicNotice>
        );
      break;
    case "open":
      body = (
        <OpenOffer
          view={view}
          onChoose={(c) => setView({ ...view, confirming: c, message: null })}
          onSend={send}
        />
      );
      break;
  }

  return (
    <PublicPage>
      <h1>{COPY.pageTitle}</h1>
      {view.kind === "open" && <p className="tcs-subtitle">{COPY.subtitle}</p>}
      <div ref={bodyRef} tabIndex={-1} aria-live="polite" className="tcs-offer-body">
        {body}
      </div>
    </PublicPage>
  );
}

function OpenOffer({
  view,
  onChoose,
  onSend,
}: {
  view: Extract<View, { kind: "open" }>;
  onChoose: (c: OfferResponse | null) => void;
  onSend: (r: OfferResponse) => void;
}) {
  const d = view.details;
  const confirming = view.confirming;
  return (
    <div className="tcs-card tcs-notice">
      {view.message && (
        <div className="tcs-message tcs-error" role="alert">
          {view.message}
        </div>
      )}
      {confirming ? (
        <>
          <h2>{confirming === "accepted" ? COPY.confirmAcceptTitle : COPY.confirmDeclineTitle}</h2>
          <p>
            {confirming === "accepted"
              ? COPY.confirmAccept(d.firstName)
              : COPY.confirmDecline(d.firstName)}
          </p>
          <div className="tcs-step-nav">
            <button
              type="button"
              className="tcs-nav-btn tcs-secondary"
              onClick={() => onChoose(null)}
              disabled={view.sending}
            >
              {COPY.back}
            </button>
            <button
              type="button"
              className="tcs-nav-btn tcs-primary"
              onClick={() => onSend(confirming)}
              disabled={view.sending}
            >
              {view.sending
                ? COPY.sending
                : confirming === "accepted"
                  ? COPY.confirmAcceptButton
                  : COPY.confirmDeclineButton}
            </button>
          </div>
        </>
      ) : (
        <>
          <p>{COPY.intro(d.firstName)}</p>
          <dl className="tcs-offer-details">
            <dt>{COPY.gradeLabel}</dt>
            <dd>{d.grade}</dd>
            <dt>{COPY.yearLabel}</dt>
            <dd>{d.academicYear}</dd>
            {d.campus && (
              <>
                <dt>{COPY.campusLabel}</dt>
                <dd>{d.campus}</dd>
              </>
            )}
            <dt>{COPY.respondByLabel}</dt>
            <dd>{offerDate(d.respondBy)}</dd>
          </dl>
          <div className="tcs-step-nav">
            <button
              type="button"
              className="tcs-nav-btn tcs-primary"
              onClick={() => onChoose("accepted")}
            >
              {COPY.accept}
            </button>
            <button
              type="button"
              className="tcs-nav-btn tcs-secondary"
              onClick={() => onChoose("declined")}
            >
              {COPY.decline}
            </button>
          </div>
        </>
      )}
      <p className="tcs-offer-privacy">
        {COPY.privacyBefore}{" "}
        {PRIVACY_POLICY.url ? (
          <a href={PRIVACY_POLICY.url} target="_blank" rel="noopener noreferrer">
            {PRIVACY_POLICY.text}
          </a>
        ) : (
          PRIVACY_POLICY.text
        )}
        {COPY.privacyAfter}
      </p>
    </div>
  );
}
