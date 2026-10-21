import { Fragment, useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { useRouter } from "@tanstack/react-router";

import {
  BlockHeading,
  NativeSelect,
  PField,
  PublicNotice,
  PublicPage,
  Row,
} from "@/modules/admissions/components/public-page-parts";
import { TurnstileWidget } from "@/modules/admissions/components/turnstile-widget";
import {
  createDraft,
  deleteDraft,
  loadDraft,
  openUploadSession,
  saveDraft,
  submitApplication,
  uploadDocument,
} from "@/modules/admissions/data/public-apply";
import { getPublicAdmissionsOptions } from "@/modules/admissions/data/public-intake";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  APPLICATION_OFFICE_MESSAGE,
  FEE_PROOF,
  GENDER_OPTIONS,
  MAX_HEALTH_DETAILS,
  PUBLIC_DOCUMENT_LABELS,
  applicationView,
  buildApplicationPayload,
  DOCUMENT_SLOTS,
  canUploadMore,
  checkFile,
  childAddress,
  emptyApplicationDraft,
  requiredDocumentTypes,
  validateApplication,
  type ApplicationDraft,
  type UploadedFile,
  type YesNo,
} from "@/modules/admissions/application-form";
import {
  LAST_STEP,
  STEPS,
  completeSteps,
  incompleteSteps,
  routeServerError,
} from "@/modules/admissions/application-steps";
import {
  MAX_GUARDIANS,
  MONTH_OPTIONS,
  NOT_YET_IN_SCHOOL,
  PHONE_EXAMPLE,
  PHONE_HINT,
  RELATIONSHIP_OPTIONS,
  RELIGION_OPTIONS,
  ageHint,
  currentGradeChoices,
  emptyGuardian,
  gradesForCampus,
  maskDateInput,
  parseDmy,
  phoneTypingError,
  readPhoneInput,
  todayInAccra,
  type FieldErrors,
  type GuardianDraft,
  type PublicOptions,
} from "@/modules/admissions/inquiry-form";
import { NationalityCombobox } from "@/modules/admissions/components/nationality-combobox";
import {
  APPLICATION_COPY as COPY,
  DECLARATION_COPY,
  DECLARATION_SECTIONS,
  DOCUMENTS_COPY as DOCS,
  FEE_BOX,
  PRIVACY_POLICY,
  SAVE_COPY,
  SCHOLARSHIP_COPY,
  applicationThankYou,
} from "@/modules/admissions/public-copy";
import {
  defaultSaveEmail,
  fromSavedState,
  hasUnsavedChanges,
  keptUntil,
  readResumeFragment,
  savedKey,
  toSavedState,
  type DraftErrorCode,
} from "@/modules/admissions/saved-application";

// /apply: the public Application form (admissions slice 9a), in the TCS OS
// six step layout from slice 9b C2 (TCS OS backend/templates/public/
// apply.html): Guardian(s), Student, Emergency, Health, Documents,
// Declaration, with the sticky section nav on the right (a scrolling strip
// above the form at 860px and below), free navigation in any order, Back,
// Next and Submit on the last step. No sign-in and no AppShell (__root.tsx
// lists it as auth-free). Every rule is enforced again by the
// admissions-public Edge Function and submit_application.
//
// Two security checks, as in 9a: one opens the upload session (action
// "upload") at the first upload, in the Documents step; one sends the
// application (action "application"), inside the Declaration step and
// mounted only while that step is shown.
//
// Save and finish later (slice 10): a third check (action "draft") on the
// first save only. The link the parent is emailed opens /apply#resume=<token>;
// the page reads the fragment once, removes it from the address bar at
// once, and opens the saved answers. The token is kept in memory only. The
// health questions, files and the declaration are never saved, so a resumed
// form asks for them again.

const SITE_KEY = (import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined) ?? "";
let missingKeyReported = false;

/** What the resume link opened, once it has been read. */
type Resumed = {
  draft: ApplicationDraft;
  step: number;
  saved: SavedDraft;
};

type ResumeState =
  | { status: "none" }
  | { status: "loading"; token: string }
  | { status: "ready"; resumed: Resumed }
  /** retryToken is kept only for a failure worth retrying (the network or
   * a rate limit), so Retry works without the link. */
  | { status: "problem"; code: DraftErrorCode; message: string; retryToken: string | null };

export function ApplicationPage() {
  const options = useLoad(getPublicAdmissionsOptions, [], "Could not load the form.");
  const [closedAfterSubmit, setClosedAfterSubmit] = useState(false);
  const [created, setCreated] = useState<{ reference: string; sentence: string } | null>(null);
  const [resume, setResume] = useState<ResumeState>({ status: "none" });
  const [locked, setLocked] = useState(false);
  const [formKey, setFormKey] = useState(0);
  const [pageNotice, setPageNotice] = useState<string | null>(null);
  const router = useRouter();

  // The resume link: read the fragment once, then take it out of the
  // address bar (and so out of history and any later copy of the URL)
  // before anything else happens. Through the router's own history, so the
  // router's idea of the location loses the fragment too and never writes
  // it back.
  useEffect(() => {
    const token = readResumeFragment(window.location.hash);
    if (window.location.hash !== "") {
      router.history.replace(window.location.pathname + window.location.search);
    }
    if (token) setResume({ status: "loading", token });
    // Once, on arrival.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const loaded = options.data;
  useEffect(() => {
    if (resume.status !== "loading" || !loaded) return;
    let cancelled = false;
    void loadDraft(resume.token).then((a) => {
      if (cancelled) return;
      if (a.ok) {
        setResume({
          status: "ready",
          resumed: {
            draft: fromSavedState(a.state, loaded),
            step: a.step,
            saved: {
              token: resume.token,
              version: a.version,
              emailMasked: a.emailMasked,
              expiresAt: a.expiresAt,
            },
          },
        });
      } else if (a.code === "closed") {
        setClosedAfterSubmit(true);
      } else if (a.code === "draft_submitted") {
        setLocked(true);
      } else {
        const retryable = a.code === "error" || a.code === "draft_limit";
        setResume({
          status: "problem",
          code: a.code,
          message: retryable ? SAVE_COPY.loadFailed : a.message,
          retryToken: retryable ? resume.token : null,
        });
      }
    });
    return () => {
      cancelled = true;
    };
  }, [resume, loaded]);

  const startNew = () => {
    setResume({ status: "none" });
    setPageNotice(null);
    setFormKey((k) => k + 1);
  };

  const view = applicationView({
    loading: options.loading,
    error: options.error,
    options: options.data,
    created: created !== null,
    closedAfterSubmit,
    siteKey: SITE_KEY,
  });

  let body: ReactNode;
  if (view === "loading") {
    body = <p className="tcs-subtitle">Loading…</p>;
  } else if (view === "loadError" || !options.data) {
    body = (
      <PublicNotice title={COPY.loadErrorTitle}>
        <p>{COPY.loadErrorBody}</p>
      </PublicNotice>
    );
  } else if (view === "created" && created) {
    body = <ThankYou reference={created.reference} sentence={created.sentence} />;
  } else if (view === "form" && locked) {
    body = (
      <PublicNotice title={SAVE_COPY.submittedTitle}>
        <p>{SAVE_COPY.submittedBody}</p>
      </PublicNotice>
    );
  } else if (view === "form" && resume.status === "loading") {
    body = <p className="tcs-subtitle">{SAVE_COPY.resumeLoading}</p>;
  } else if (view === "form" && resume.status === "problem") {
    body = (
      <PublicNotice
        title={
          resume.retryToken
            ? SAVE_COPY.loadFailedTitle
            : resume.code === "draft_expired"
              ? SAVE_COPY.expiredTitle
              : SAVE_COPY.linkProblemTitle
        }
      >
        <p>{resume.message}</p>
        <div className="tcs-save-actions">
          {resume.retryToken && (
            <button
              type="button"
              className="tcs-nav-btn tcs-primary"
              onClick={() => setResume({ status: "loading", token: resume.retryToken as string })}
            >
              {SAVE_COPY.retry}
            </button>
          )}
          <button
            type="button"
            className={`tcs-nav-btn ${resume.retryToken ? "tcs-secondary" : "tcs-primary"}`}
            onClick={startNew}
          >
            {SAVE_COPY.startNew}
          </button>
        </div>
      </PublicNotice>
    );
  } else if (view === "closed") {
    body = (
      <PublicNotice title={COPY.closedTitle}>
        <p>{COPY.closedBody}</p>
      </PublicNotice>
    );
  } else if (view === "unavailable") {
    if (!missingKeyReported && typeof window !== "undefined") {
      missingKeyReported = true;
      console.error(
        "Application form unavailable: VITE_TURNSTILE_SITE_KEY was empty when this site was built.",
      );
    }
    body = (
      <PublicNotice title={COPY.unavailableTitle}>
        <p>{APPLICATION_OFFICE_MESSAGE}</p>
      </PublicNotice>
    );
  } else {
    const resumed = resume.status === "ready" ? resume.resumed : null;
    body = (
      <>
        {pageNotice && (
          <div className="tcs-message tcs-success" role="status">
            <p>{pageNotice}</p>
          </div>
        )}
        <ApplicationForm
          // formKey alone is enough: a resume always passes through
          // "loading", which unmounts the form, so the resumed values are
          // read by fresh useState initialisers.
          key={formKey}
          options={options.data}
          resumed={resumed}
          onSaved={() => setPageNotice(null)}
          onCreated={(reference, sentence) => {
            setCreated({ reference, sentence });
            window.scrollTo({ top: 0 });
          }}
          onClosed={() => setClosedAfterSubmit(true)}
          onLocked={() => {
            setLocked(true);
            window.scrollTo({ top: 0 });
          }}
          onDiscarded={() => {
            setResume({ status: "none" });
            setFormKey((k) => k + 1);
            setPageNotice(SAVE_COPY.discarded);
            window.scrollTo({ top: 0 });
          }}
        />
      </>
    );
  }

  return (
    <PublicPage wide>
      <h1>{COPY.title}</h1>
      <p className="tcs-subtitle">
        {COPY.subtitle}
        {view === "form" && <span className="tcs-subtitle-note">{COPY.note}</span>}
      </p>
      {body}
    </PublicPage>
  );
}

/** The reference, and the note that a confirmation email follows (slice
 * 12). */
function ThankYou({ reference, sentence }: { reference: string; sentence: string }) {
  return (
    <PublicNotice title={COPY.thankYouTitle}>
      <p>{sentence}</p>
      <div className="tcs-reference-box">
        <p>{COPY.referenceLabel}</p>
        <p className="tcs-reference">{reference}</p>
      </div>
      <p>{COPY.keepReference}</p>
    </PublicNotice>
  );
}

type Message = { kind: "error"; text: string } | { kind: "incomplete"; steps: number[] };

/** The saved application this form is linked to. The token stays in memory. */
type SavedDraft = { token: string; version: number; emailMasked: string; expiresAt: string };

function ApplicationForm({
  options,
  resumed,
  onSaved,
  onCreated,
  onClosed,
  onLocked,
  onDiscarded,
}: {
  options: PublicOptions;
  resumed: Resumed | null;
  onSaved: () => void;
  onCreated: (reference: string, sentence: string) => void;
  onClosed: () => void;
  onLocked: () => void;
  onDiscarded: () => void;
}) {
  const [draft, setDraft] = useState<ApplicationDraft>(
    () => resumed?.draft ?? emptyApplicationDraft(),
  );
  const [errors, setErrors] = useState<FieldErrors>({});
  const [step, setStep] = useState(resumed?.step ?? 0);
  const [saved, setSaved] = useState<SavedDraft | null>(resumed?.saved ?? null);
  // What the last successful save kept, to tell what has changed since.
  const [lastSaved, setLastSaved] = useState<string | null>(() =>
    resumed ? savedKey(resumed.draft) : null,
  );
  const [panelOpen, setPanelOpen] = useState(false);
  const wasResumed = resumed !== null;
  const [uploads, setUploads] = useState<Record<string, UploadedFile | undefined>>({});
  const [uploading, setUploading] = useState<string | null>(null);
  // Per slot: a file going up now or the last attempt failed; uploaded
  // files are in `uploads`. filesStarted counts reservations asked for in
  // this visit, for the files per session cap.
  const [fileStatus, setFileStatus] = useState<Record<string, "uploading" | "failed">>({});
  const [filesStarted, setFilesStarted] = useState(0);
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [opening, setOpening] = useState(false);
  const [uploadResetKey, setUploadResetKey] = useState(0);
  const [token, setToken] = useState("");
  const [resetKey, setResetKey] = useState(0);
  const [busy, setBusy] = useState(false);
  const sending = useRef(false);
  const [message, setMessage] = useState<Message | null>(null);
  // The two security checks fail separately: the upload one (step 5) and
  // the application one (step 6).
  const [uploadVerifyUnavailable, setUploadVerifyUnavailable] = useState(false);
  const [verifyUnavailable, setVerifyUnavailable] = useState(false);
  const today = todayInAccra();

  // Leaving would lose something: changes since the last save, anything in
  // a part never saved (health, the declaration), or any attached file
  // (files are never saved). The browser shows its own wording.
  const dirty = hasUnsavedChanges(draft, lastSaved, uploads);
  useEffect(() => {
    if (!dirty) return;
    const warn = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  const complete = completeSteps(draft, options, today, uploads);

  // On a phone the section nav is a strip that scrolls sideways: keep the
  // current step in view.
  const navRef = useRef<HTMLElement>(null);
  // After a step change (not on first load), focus the new step's heading
  // so keyboard and screen reader users land at the top of it.
  const headingRef = useRef<HTMLLegendElement>(null);
  const firstRender = useRef(true);
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    headingRef.current?.focus({ preventScroll: true });
  }, [step]);
  useEffect(() => {
    navRef.current
      ?.querySelector(".tcs-active")
      ?.scrollIntoView({ block: "nearest", inline: "nearest" });
  }, [step]);

  const clearError = (key: string) =>
    setErrors((e) => {
      if (!(key in e)) return e;
      const next = { ...e };
      delete next[key];
      return next;
    });
  const setGuardian = (i: number, patch: Partial<GuardianDraft>) => {
    Object.keys(patch).forEach((f) => clearError(`guardians.${i}.${f}`));
    setDraft((d) => ({
      ...d,
      guardians: d.guardians.map((g, j) => (j === i ? { ...g, ...patch } : g)),
    }));
  };
  const setChild = (patch: Partial<ApplicationDraft["child"]>) => {
    Object.keys(patch).forEach((f) => clearError(`child.${f}`));
    setDraft((d) => ({ ...d, child: { ...d.child, ...patch } }));
  };
  const setEmergency = (patch: Partial<ApplicationDraft["emergency"]>) => {
    Object.keys(patch).forEach((f) => clearError(`emergency.${f}`));
    setDraft((d) => ({ ...d, emergency: { ...d.emergency, ...patch } }));
  };
  const setHealth = (patch: Partial<ApplicationDraft["health"]>) => {
    Object.keys(patch).forEach((f) => clearError(`health.${f}`));
    setDraft((d) => ({ ...d, health: { ...d.health, ...patch } }));
  };

  /** Free navigation: any step, any order, nothing blocks. Leaving the
   * Declaration step unmounts its security check, so its token is dropped
   * and a fresh one is needed on return. */
  function goToStep(n: number, keepMessage = false) {
    if (n < 0 || n > LAST_STEP) return;
    if (!keepMessage) setMessage(null);
    if (step === LAST_STEP && n !== LAST_STEP) setToken("");
    setStep(n);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function scrollToProblem() {
    requestAnimationFrame(() => {
      const target =
        document.querySelector(".tcs-step-panel [aria-invalid='true']") ??
        document.getElementById("application-message");
      target?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }

  async function startUploads(uploadToken: string) {
    if (uploadToken === "" || sessionToken || opening) return;
    setOpening(true);
    const result = await openUploadSession(uploadToken, APPLICATION_OFFICE_MESSAGE);
    setOpening(false);
    if (result.ok) {
      setSessionToken(result.sessionToken);
      clearError("documents");
    } else if (result.closed) {
      onClosed();
    } else {
      setErrors((e) => ({ ...e, documents: result.message }));
      setUploadResetKey((k) => k + 1);
    }
  }

  async function chooseFile(type: string, file: File | undefined) {
    if (!file || !sessionToken) return;
    clearError(`documents.${type}`);
    const checked = checkFile(file.name, file.size);
    if ("error" in checked) {
      setErrors((e) => ({ ...e, [`documents.${type}`]: checked.error }));
      return;
    }
    if (!canUploadMore(filesStarted)) {
      setErrors((e) => ({ ...e, [`documents.${type}`]: DOCS.limitReached }));
      return;
    }
    setUploading(type);
    setFilesStarted((n) => n + 1);
    setFileStatus((s) => ({ ...s, [type]: "uploading" }));
    try {
      const uploaded = await uploadDocument(
        sessionToken,
        type,
        file,
        checked.extension,
        checked.contentType,
        APPLICATION_OFFICE_MESSAGE,
      );
      setUploads((u) => ({ ...u, [type]: uploaded }));
      setFileStatus((s) => {
        const next = { ...s };
        delete next[type];
        return next;
      });
    } catch (err) {
      // A failed replacement leaves the earlier upload in place.
      setFileStatus((s) => ({ ...s, [type]: "failed" }));
      setErrors((e) => ({
        ...e,
        [`documents.${type}`]: err instanceof Error ? err.message : APPLICATION_OFFICE_MESSAGE,
      }));
    } finally {
      setUploading(null);
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    // Only the Declaration step's Submit sends. Next and Submit are
    // separate keyed buttons, so a click on Next can't turn into a submit;
    // this also stops Enter in a field on another step.
    if (step !== LAST_STEP || sending.current) return;
    setMessage(null);
    const found = validateApplication(draft, options, today, uploads);
    setErrors(found);
    const incomplete = incompleteSteps(found);
    if (incomplete.length > 0) {
      // TCS OS: name every incomplete section, each a link back to it.
      setMessage({ kind: "incomplete", steps: incomplete });
      scrollToProblem();
      return;
    }
    if (uploading !== null || !sessionToken) {
      setMessage({ kind: "error", text: COPY.waitForUploads });
      scrollToProblem();
      return;
    }
    if (token === "") {
      setMessage({ kind: "error", text: COPY.completeCheck });
      return;
    }
    sending.current = true;
    setBusy(true);
    try {
      const outcome = await submitApplication(
        token,
        sessionToken,
        buildApplicationPayload(draft, options, uploads),
        saved?.token ?? null,
      );
      if (outcome.kind === "created") {
        // TCS OS's sentence, with the name, grade and year as entered.
        onCreated(
          outcome.reference,
          applicationThankYou(
            draft.child.fullName.trim(),
            options.grades.find((g) => g.id === draft.child.gradeId)?.name ?? "",
            draft.child.academicYear,
          ),
        );
      } else if (outcome.kind === "closed") {
        onClosed();
      } else if (outcome.kind === "alreadySubmitted") {
        onLocked();
      } else {
        // A server check the form didn't catch: open its step and show it
        // on the field when it names one.
        const where = routeServerError(outcome.path, draft);
        if (where.field) setErrors({ [where.field]: outcome.message });
        setMessage({ kind: "error", text: outcome.message });
        if (where.step !== null && where.step !== step) goToStep(where.step, true);
        scrollToProblem();
      }
    } finally {
      // A token is single use: always start the next attempt with a new one.
      setResetKey((k) => k + 1);
      setToken("");
      setBusy(false);
      sending.current = false;
    }
  }

  const c = draft.child;
  const inSchool = c.currentGrade !== NOT_YET_IN_SCHOOL;
  const where = childAddress(draft);
  const grades = gradesForCampus(options, draft.campusId);
  const docTypes = requiredDocumentTypes(options, c.gradeId);
  const relationshipItems = RELATIONSHIP_OPTIONS.map((o) => ({ value: o.value, label: o.label }));
  const religionItems = RELIGION_OPTIONS.map((r) => ({ value: r, label: r }));
  const monthItems = MONTH_OPTIONS.map((m) => ({ value: m.value, label: m.label }));
  const genderItems = GENDER_OPTIONS.map((o) => ({ value: o.value, label: o.label }));
  const invalid = (key: string) => (errors[key] ? true : undefined);

  const phoneInput = (id: string, key: string, value: string, set: (v: string) => void) => (
    <input
      id={id}
      type="tel"
      inputMode="tel"
      placeholder={PHONE_EXAMPLE}
      maxLength={32}
      aria-invalid={invalid(key)}
      value={value}
      onChange={(e) => {
        // Keeps what they type; a symbol or extra digit shows its error at
        // once (not while 233... is still being typed).
        const raw = e.target.value;
        set(raw);
        const error = phoneTypingError(raw);
        if (error) setErrors((x) => ({ ...x, [key]: error }));
      }}
      onBlur={() => {
        const read = readPhoneInput(value);
        if (!read.error && read.display !== value) set(read.display);
      }}
    />
  );

  const yesNo = (
    flag: "hasNeeds" | "hasMedical" | "hasAllergies",
    text: "needs" | "medical" | "allergies",
  ) => {
    const value: YesNo = draft.health[flag];
    const flagKey = `health.${flag}`;
    const textKey = `health.${text}`;
    const name = `h-${flag}`;
    return (
      <div className="tcs-field" role="radiogroup" aria-labelledby={`${name}-q`}>
        <span id={`${name}-q`} className="tcs-question">
          {COPY.health[flag]}{" "}
          <span className="tcs-required" aria-hidden="true">
            *
          </span>
        </span>
        <div className="tcs-radio-group">
          {[
            { v: true, label: "Yes" },
            { v: false, label: "No" },
          ].map((o) => (
            <label key={o.label} className="tcs-radio-option">
              <input
                type="radio"
                name={name}
                checked={value === o.v}
                aria-invalid={invalid(flagKey)}
                aria-describedby={errors[flagKey] ? `${name}-error` : undefined}
                onChange={() => setHealth({ [flag]: o.v, ...(o.v ? {} : { [text]: "" }) })}
              />
              {o.label}
            </label>
          ))}
        </div>
        {value === true && (
          <textarea
            id={`h-${text}`}
            aria-label={`${COPY.health[flag]} ${COPY.health.details}`}
            placeholder={COPY.health.details}
            maxLength={MAX_HEALTH_DETAILS}
            aria-invalid={invalid(textKey)}
            aria-describedby={errors[textKey] ? `h-${text}-error` : undefined}
            value={draft.health[text]}
            onChange={(e) => setHealth({ [text]: e.target.value })}
          />
        )}
        {errors[flagKey] && (
          <div id={`${name}-error`} className="tcs-field-error">
            {errors[flagKey]}
          </div>
        )}
        {errors[textKey] && (
          <div id={`h-${text}-error`} className="tcs-field-error">
            {errors[textKey]}
          </div>
        )}
      </div>
    );
  };

  /** One document slot: label (star when this grade requires it), file
   * input, and its status (uploading, uploaded, failed). The inputs wait
   * for the upload session, and stop at the files per session cap. */
  const documentSlot = (type: string) => {
    const key = `documents.${type}`;
    const done = uploads[type];
    const state = fileStatus[type];
    const required = docTypes.includes(type);
    return (
      <div className="tcs-document-field">
        <PField
          id={`d-${type}`}
          label={PUBLIC_DOCUMENT_LABELS[type] ?? type}
          required={required}
          error={errors[key]}
          hint={type === "proof_of_vaccination" ? DOCS.vaccinationHint : null}
        >
          <input
            id={`d-${type}`}
            type="file"
            accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png"
            disabled={!sessionToken || uploading !== null || !canUploadMore(filesStarted)}
            aria-invalid={invalid(key)}
            onChange={(e) => {
              void chooseFile(type, e.target.files?.[0]);
              e.target.value = "";
            }}
          />
        </PField>
        {state === "uploading" ? (
          <p className="tcs-upload-status" role="status">
            {DOCS.uploading}
          </p>
        ) : state === "failed" ? (
          <p className="tcs-upload-status tcs-failed" role="status">
            {done ? `${DOCS.failed} ${DOCS.earlierKept(done.fileName)}` : DOCS.failed}
          </p>
        ) : done ? (
          <p className="tcs-upload-status tcs-done" role="status">
            {DOCS.uploaded(done.fileName)}
          </p>
        ) : null}
      </div>
    );
  };

  const current = STEPS[step];

  // Focus moves to the panel's heading when it opens and back to the
  // button that opened it when it closes.
  const saveLaterRef = useRef<HTMLButtonElement>(null);
  function openPanel() {
    setPanelOpen(true);
    requestAnimationFrame(() => {
      const heading = document.getElementById("save-panel-title");
      heading?.focus({ preventScroll: true });
      document.getElementById("save-panel")?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }
  function closePanel() {
    setPanelOpen(false);
    requestAnimationFrame(() => saveLaterRef.current?.focus());
  }

  return (
    <>
      {/* Only for the saved application this page opened: a lost one that
          was saved again is a new one. */}
      {wasResumed && saved && saved.token === resumed?.saved.token && (
        <div className="tcs-message tcs-success" role="status">
          <p>{SAVE_COPY.resumed}</p>
          <div className="tcs-save-actions">
            <DiscardButton token={saved.token} onDiscarded={onDiscarded} />
          </div>
        </div>
      )}
      {panelOpen && (
        <SavePanel
          draft={draft}
          step={step}
          saved={saved}
          onSaved={(next, key) => {
            setSaved(next);
            setLastSaved(key);
            onSaved();
          }}
          onLost={() => {
            // The saved copy is gone (expired or deleted): the next save
            // starts a new one.
            setSaved(null);
            setLastSaved(null);
          }}
          onClosed={onClosed}
          onLocked={onLocked}
          onClose={closePanel}
        />
      )}
      {message && (
        <div id="application-message" className="tcs-message tcs-error" role="alert">
          {message.kind === "error" ? (
            <p>{message.text}</p>
          ) : (
            <>
              <p>{COPY.incompleteIntro}</p>
              <ul>
                {message.steps.map((n) => (
                  <li key={n}>
                    <button
                      type="button"
                      className="tcs-link-btn"
                      onClick={() => goToStep(n, true)}
                    >
                      {STEPS[n].title}
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      )}
      <div className="tcs-layout">
        <form onSubmit={submit} className="tcs-card" noValidate>
          <fieldset className="tcs-step-panel-wrap">
            <legend ref={headingRef} tabIndex={-1}>
              <span className="tcs-section-number">{step + 1}.</span>
              {current.title}
            </legend>

            <div className="tcs-step-panel">
              {/* ------------------------------------------ 1. guardians */}
              {current.key === "guardians" &&
                draft.guardians.map((g, i) => {
                  const k = (f: string) => `guardians.${i}.${f}`;
                  const id = (f: string) => `g${i}-${f}`;
                  const sameAddress = i === 1 && draft.secondSameAddress;
                  const shown = sameAddress
                    ? { address: draft.guardians[0].address, townCity: draft.guardians[0].townCity }
                    : { address: g.address, townCity: g.townCity };
                  const text = (
                    field: "surname" | "firstName" | "email",
                    label: string,
                    extra: {
                      type?: string;
                      inputMode?: "email";
                      max?: number;
                      hint?: string;
                    } = {},
                  ) => (
                    <PField
                      id={id(field)}
                      label={label}
                      required
                      error={errors[k(field)]}
                      hint={extra.hint}
                    >
                      <input
                        id={id(field)}
                        type={extra.type ?? "text"}
                        inputMode={extra.inputMode}
                        maxLength={extra.max ?? 255}
                        aria-invalid={invalid(k(field))}
                        value={g[field]}
                        onChange={(e) => setGuardian(i, { [field]: e.target.value })}
                      />
                    </PField>
                  );
                  return (
                    <Fragment key={i}>
                      <div className="tcs-block">
                        <BlockHeading
                          action={
                            i > 0 ? (
                              <button
                                type="button"
                                className="tcs-link-btn tcs-subtle"
                                onClick={() => {
                                  setErrors((e) =>
                                    Object.fromEntries(
                                      Object.entries(e).filter(
                                        ([key]) => !key.startsWith(`guardians.${i}.`),
                                      ),
                                    ),
                                  );
                                  setDraft((d) => ({
                                    ...d,
                                    secondSameAddress: false,
                                    guardians: d.guardians.filter((_, j) => j !== i),
                                  }));
                                }}
                              >
                                Remove
                              </button>
                            ) : undefined
                          }
                        >
                          Parent / Guardian {i + 1}
                        </BlockHeading>
                        <Row>
                          {text("surname", "Surname / Family name")}
                          {text("firstName", "First name(s)")}
                        </Row>
                        <PField
                          id={id("relationship")}
                          label="Relationship to child"
                          required
                          error={errors[k("relationship")]}
                        >
                          <NativeSelect
                            id={id("relationship")}
                            value={g.relationship}
                            onChange={(v) => setGuardian(i, { relationship: v })}
                            placeholder="Select one"
                            items={relationshipItems}
                            invalid={!!errors[k("relationship")]}
                          />
                        </PField>
                        <PField
                          id={id("religion")}
                          label="Religion"
                          required
                          error={errors[k("religion")]}
                        >
                          <NativeSelect
                            id={id("religion")}
                            value={g.religion}
                            onChange={(v) => setGuardian(i, { religion: v })}
                            placeholder="Select one"
                            items={religionItems}
                            invalid={!!errors[k("religion")]}
                          />
                        </PField>
                        <PField
                          id={id("address")}
                          label="Address"
                          required
                          error={errors[k("address")]}
                        >
                          <input
                            id={id("address")}
                            type="text"
                            maxLength={255}
                            disabled={sameAddress}
                            aria-invalid={invalid(k("address"))}
                            value={shown.address}
                            onChange={(e) => setGuardian(i, { address: e.target.value })}
                          />
                          {i === 1 && (
                            <div className="tcs-checkbox-field">
                              <label>
                                <input
                                  type="checkbox"
                                  checked={draft.secondSameAddress}
                                  onChange={(e) => {
                                    clearError(k("address"));
                                    clearError(k("townCity"));
                                    const checked = e.target.checked;
                                    setDraft((d) => ({ ...d, secondSameAddress: checked }));
                                  }}
                                />
                                Same address as above
                              </label>
                            </div>
                          )}
                        </PField>
                        <Row>
                          <PField
                            id={id("townCity")}
                            label="Town / City"
                            required
                            error={errors[k("townCity")]}
                          >
                            <input
                              id={id("townCity")}
                              type="text"
                              maxLength={255}
                              disabled={sameAddress}
                              aria-invalid={invalid(k("townCity"))}
                              value={shown.townCity}
                              onChange={(e) => setGuardian(i, { townCity: e.target.value })}
                            />
                          </PField>
                          <PField
                            id={id("phone")}
                            label="Contact number"
                            required
                            error={errors[k("phone")]}
                            hint={errors[k("phone")] ? null : PHONE_HINT}
                          >
                            {phoneInput(id("phone"), k("phone"), g.phone, (v) =>
                              setGuardian(i, { phone: v }),
                            )}
                          </PField>
                        </Row>
                        {text("email", "Active email address", {
                          type: "email",
                          inputMode: "email",
                          max: 254,
                          hint: i === 0 ? COPY.emailHint : undefined,
                        })}
                      </div>
                      {i === 0 && draft.guardians.length < MAX_GUARDIANS && (
                        <button
                          type="button"
                          className="tcs-link-btn"
                          onClick={() =>
                            setDraft((d) => ({
                              ...d,
                              guardians: [...d.guardians, emptyGuardian()],
                            }))
                          }
                        >
                          + Add a second parent / guardian
                        </button>
                      )}
                    </Fragment>
                  );
                })}

              {/* ------------------------------------------ 2. student */}
              {current.key === "student" && (
                <>
                  <PField id="c-name" label="Full name" required error={errors["child.fullName"]}>
                    <input
                      id="c-name"
                      type="text"
                      maxLength={255}
                      aria-invalid={invalid("child.fullName")}
                      value={c.fullName}
                      onChange={(e) => setChild({ fullName: e.target.value })}
                    />
                  </PField>
                  <Row>
                    <PField
                      id="c-dob"
                      label="Date of birth"
                      required
                      error={errors["child.dateOfBirth"]}
                      hint={ageHint(parseDmy(c.dateOfBirth), today)}
                    >
                      <input
                        id="c-dob"
                        type="text"
                        inputMode="numeric"
                        placeholder="dd/mm/yyyy"
                        maxLength={10}
                        autoComplete="off"
                        aria-invalid={invalid("child.dateOfBirth")}
                        value={c.dateOfBirth}
                        onChange={(e) => setChild({ dateOfBirth: maskDateInput(e.target.value) })}
                      />
                    </PField>
                    <PField id="c-gender" label="Gender" required error={errors["child.gender"]}>
                      <NativeSelect
                        id="c-gender"
                        value={c.gender}
                        onChange={(v) => setChild({ gender: v })}
                        placeholder="Select one"
                        items={genderItems}
                        invalid={!!errors["child.gender"]}
                      />
                    </PField>
                  </Row>
                  <PField
                    id="c-nat"
                    label="Nationality"
                    required
                    error={errors["child.nationality"]}
                    hint="Not listed? Please contact the school."
                  >
                    <NationalityCombobox
                      id="c-nat"
                      value={c.nationality}
                      onChange={(v) => setChild({ nationality: v })}
                      invalid={!!errors["child.nationality"]}
                    />
                  </PField>
                  <PField
                    id="c-address"
                    label="Learner's home address"
                    required
                    error={errors["child.address"]}
                  >
                    <input
                      id="c-address"
                      type="text"
                      maxLength={255}
                      disabled={c.sameAddress}
                      aria-invalid={invalid("child.address")}
                      value={where.address}
                      onChange={(e) => setChild({ address: e.target.value })}
                    />
                    <div className="tcs-checkbox-field">
                      <label>
                        <input
                          type="checkbox"
                          checked={c.sameAddress}
                          onChange={(e) => {
                            const checked = e.target.checked;
                            clearError("child.address");
                            clearError("child.townCity");
                            // Unticking starts from guardian 1's address, to edit.
                            setDraft((d) => {
                              const from = childAddress(d);
                              return {
                                ...d,
                                child: {
                                  ...d.child,
                                  sameAddress: checked,
                                  ...(checked ? {} : from),
                                },
                              };
                            });
                          }}
                        />
                        Same address as Parent/Guardian 1
                      </label>
                    </div>
                  </PField>
                  <Row>
                    <PField
                      id="c-town"
                      label="Town / City"
                      required
                      error={errors["child.townCity"]}
                    >
                      <input
                        id="c-town"
                        type="text"
                        maxLength={255}
                        disabled={c.sameAddress}
                        aria-invalid={invalid("child.townCity")}
                        value={where.townCity}
                        onChange={(e) => setChild({ townCity: e.target.value })}
                      />
                    </PField>
                    <PField id="c-postal" label="Postal code" error={errors["child.postalCode"]}>
                      <input
                        id="c-postal"
                        type="text"
                        maxLength={20}
                        aria-invalid={invalid("child.postalCode")}
                        value={c.postalCode}
                        onChange={(e) => setChild({ postalCode: e.target.value })}
                      />
                    </PField>
                  </Row>
                  <PField id="c-country" label="Country" error={errors["child.country"]}>
                    <input
                      id="c-country"
                      type="text"
                      maxLength={100}
                      aria-invalid={invalid("child.country")}
                      value={c.country}
                      onChange={(e) => setChild({ country: e.target.value })}
                    />
                  </PField>
                  <Row>
                    <PField
                      id="c-current"
                      label="Current grade / class"
                      required
                      error={errors["child.currentGrade"]}
                    >
                      <NativeSelect
                        id="c-current"
                        value={c.currentGrade}
                        onChange={(v) => {
                          clearError("child.currentSchool");
                          clearError("child.previousSchoolLocation");
                          setChild({ currentGrade: v });
                        }}
                        placeholder="Select one"
                        items={currentGradeChoices(options)}
                        invalid={!!errors["child.currentGrade"]}
                      />
                    </PField>
                    {inSchool && (
                      <PField
                        id="c-school"
                        label="Learner's current school"
                        required
                        error={errors["child.currentSchool"]}
                      >
                        <input
                          id="c-school"
                          type="text"
                          maxLength={255}
                          placeholder="N/A if not yet in school"
                          aria-invalid={invalid("child.currentSchool")}
                          value={c.currentSchool}
                          onChange={(e) => setChild({ currentSchool: e.target.value })}
                        />
                      </PField>
                    )}
                  </Row>
                  {inSchool && (
                    <PField
                      id="c-school-location"
                      label="Location/address of that school"
                      error={errors["child.previousSchoolLocation"]}
                    >
                      <input
                        id="c-school-location"
                        type="text"
                        maxLength={255}
                        placeholder="State N/A if not applicable"
                        aria-invalid={invalid("child.previousSchoolLocation")}
                        value={c.previousSchoolLocation}
                        onChange={(e) => setChild({ previousSchoolLocation: e.target.value })}
                      />
                    </PField>
                  )}
                  <PField id="c-campus" label="Campus applying to" required error={errors.campusId}>
                    <NativeSelect
                      id="c-campus"
                      value={draft.campusId}
                      onChange={(v) => {
                        clearError("campusId");
                        setDraft((d) => {
                          const keep = gradesForCampus(options, v).some(
                            (g) => g.id === d.child.gradeId,
                          );
                          return {
                            ...d,
                            campusId: v,
                            child: { ...d.child, gradeId: keep ? d.child.gradeId : "" },
                          };
                        });
                      }}
                      placeholder="Select one"
                      items={options.campuses.map((x) => ({ value: x.id, label: x.name }))}
                      invalid={!!errors.campusId}
                    />
                  </PField>
                  <PField
                    id="c-grade"
                    label="Grade applying for"
                    required
                    error={errors["child.gradeId"]}
                    hint="Grade not listed? Please contact the school."
                  >
                    <NativeSelect
                      id="c-grade"
                      value={c.gradeId}
                      onChange={(v) => setChild({ gradeId: v })}
                      placeholder={draft.campusId === "" ? "Choose a campus first" : "Select one"}
                      items={grades.map((g) => ({ value: g.id, label: g.name }))}
                      invalid={!!errors["child.gradeId"]}
                    />
                  </PField>
                  <Row>
                    <PField
                      id="c-year"
                      label="Academic year applying for"
                      required
                      error={errors["child.academicYear"]}
                    >
                      <NativeSelect
                        id="c-year"
                        value={c.academicYear}
                        onChange={(v) => setChild({ academicYear: v })}
                        placeholder="Select one"
                        items={options.academicYears.map((y) => ({ value: y, label: y }))}
                        invalid={!!errors["child.academicYear"]}
                      />
                    </PField>
                    <PField
                      id="c-month"
                      label="Month of enrolment"
                      required
                      error={errors["child.month"]}
                    >
                      <NativeSelect
                        id="c-month"
                        value={c.month}
                        onChange={(v) => setChild({ month: v })}
                        placeholder="Select one"
                        items={monthItems}
                        invalid={!!errors["child.month"]}
                      />
                    </PField>
                  </Row>
                </>
              )}

              {/* ------------------------------------------ 3. emergency */}
              {current.key === "emergency" && (
                <>
                  <p className="tcs-hint tcs-section-hint">{COPY.emergencyHint}</p>
                  <PField id="e-name" label="Full name" required error={errors["emergency.name"]}>
                    <input
                      id="e-name"
                      type="text"
                      maxLength={255}
                      aria-invalid={invalid("emergency.name")}
                      value={draft.emergency.name}
                      onChange={(e) => setEmergency({ name: e.target.value })}
                    />
                  </PField>
                  <Row>
                    <PField
                      id="e-rel"
                      label="Relationship to learner"
                      required
                      error={errors["emergency.relationship"]}
                    >
                      <input
                        id="e-rel"
                        type="text"
                        maxLength={100}
                        placeholder="e.g. Aunt, Family friend"
                        aria-invalid={invalid("emergency.relationship")}
                        value={draft.emergency.relationship}
                        onChange={(e) => setEmergency({ relationship: e.target.value })}
                      />
                    </PField>
                    <PField
                      id="e-phone"
                      label="Contact number"
                      required
                      error={errors["emergency.phone"]}
                      hint={errors["emergency.phone"] ? null : PHONE_HINT}
                    >
                      {phoneInput("e-phone", "emergency.phone", draft.emergency.phone, (v) =>
                        setEmergency({ phone: v }),
                      )}
                    </PField>
                  </Row>
                </>
              )}

              {/* ------------------------------------------ 4. health */}
              {current.key === "health" && (
                <>
                  <p className="tcs-hint tcs-section-hint">{COPY.healthPrivacy}</p>
                  {yesNo("hasNeeds", "needs")}
                  {yesNo("hasMedical", "medical")}
                  {yesNo("hasAllergies", "allergies")}
                </>
              )}

              {/* ------------------------------------------ 5. documents and payment */}
              {current.key === "documents" && (
                <>
                  <p className="tcs-hint tcs-section-hint">{COPY.documentsHint}</p>
                  {wasResumed && !Object.values(uploads).some(Boolean) && (
                    <p className="tcs-field-error" role="status">
                      {SAVE_COPY.filesAgain}
                    </p>
                  )}
                  {errors.documents && (
                    <div className="tcs-field-error" role="alert">
                      {errors.documents}
                    </div>
                  )}
                  {!sessionToken && (
                    <div className="tcs-document-field">
                      <p className="tcs-question">{COPY.uploadCheck}</p>
                      {uploadVerifyUnavailable ? (
                        <p className="tcs-field-error">
                          The security check couldn't load. {APPLICATION_OFFICE_MESSAGE}
                        </p>
                      ) : (
                        <TurnstileWidget
                          siteKey={SITE_KEY}
                          action="upload"
                          resetKey={uploadResetKey}
                          onToken={(t) => void startUploads(t)}
                          onUnavailable={() => setUploadVerifyUnavailable(true)}
                        />
                      )}
                      {opening && <p className="tcs-upload-status">{COPY.preparingUploads}</p>}
                    </div>
                  )}
                  {!canUploadMore(filesStarted) && (
                    <p className="tcs-field-error" role="status">
                      {DOCS.limitReached}
                    </p>
                  )}
                  {DOCUMENT_SLOTS.map((type) => {
                    const slot = documentSlot(type);
                    return type === FEE_PROOF ? (
                      <Fragment key={type}>
                        <p className="tcs-block-heading" style={{ marginTop: "1.5rem" }}>
                          {FEE_BOX.heading}
                        </p>
                        <div className="tcs-payment-box">
                          <p>{FEE_BOX.intro}</p>
                          <p>
                            {FEE_BOX.accountHeading}
                            {FEE_BOX.accountLines.map((line) => (
                              <Fragment key={line}>
                                <br />
                                {line}
                              </Fragment>
                            ))}
                          </p>
                          <p>
                            {FEE_BOX.processHeading}
                            <br />
                            {FEE_BOX.process}
                          </p>
                        </div>
                        {slot}
                      </Fragment>
                    ) : (
                      <Fragment key={type}>{slot}</Fragment>
                    );
                  })}

                  <div className="tcs-field" style={{ marginTop: "1.5rem" }}>
                    <div role="radiogroup" aria-labelledby="scholarship-q">
                      <span id="scholarship-q" className="tcs-question">
                        {SCHOLARSHIP_COPY.question}{" "}
                        <span className="tcs-required" aria-hidden="true">
                          *
                        </span>
                      </span>
                      <div className="tcs-hint" style={{ marginTop: 0, marginBottom: "0.5rem" }}>
                        {SCHOLARSHIP_COPY.hint}{" "}
                        <a href={SCHOLARSHIP_COPY.url} target="_blank" rel="noopener noreferrer">
                          {SCHOLARSHIP_COPY.linkText}
                        </a>
                      </div>
                      <div className="tcs-radio-group">
                        {[
                          { v: true, label: "Yes" },
                          { v: false, label: "No" },
                        ].map((o) => (
                          <label key={o.label} className="tcs-radio-option">
                            <input
                              type="radio"
                              name="wants-scholarship"
                              checked={draft.wantsScholarship === o.v}
                              onChange={() => {
                                clearError("scholarshipDetails");
                                setDraft((d) => ({ ...d, wantsScholarship: o.v }));
                              }}
                            />
                            {o.label}
                          </label>
                        ))}
                      </div>
                    </div>
                    {draft.wantsScholarship && (
                      <textarea
                        id="scholarship-details"
                        aria-label={`${SCHOLARSHIP_COPY.question} ${SCHOLARSHIP_COPY.detailsPlaceholder}`}
                        placeholder={SCHOLARSHIP_COPY.detailsPlaceholder}
                        maxLength={10000}
                        aria-invalid={invalid("scholarshipDetails")}
                        value={draft.scholarshipDetails}
                        onChange={(e) => {
                          clearError("scholarshipDetails");
                          const text = e.target.value;
                          setDraft((d) => ({ ...d, scholarshipDetails: text }));
                        }}
                      />
                    )}
                    {errors.scholarshipDetails && (
                      <div className="tcs-field-error">{errors.scholarshipDetails}</div>
                    )}
                  </div>
                </>
              )}

              {/* ------------------------------------------ 6. declaration */}
              {current.key === "declaration" && (
                <>
                  <div className="tcs-declaration-text" tabIndex={0} aria-label="Declaration">
                    {DECLARATION_SECTIONS.map((s) => (
                      <Fragment key={s.heading}>
                        <h4>{s.heading}</h4>
                        {s.paragraphs.map((para, n) =>
                          typeof para === "string" ? (
                            <p key={n}>{para}</p>
                          ) : (
                            <p key={n} className="tcs-verse">
                              {para.verse}
                            </p>
                          ),
                        )}
                      </Fragment>
                    ))}
                  </div>
                  <div className="tcs-field">
                    <div className="tcs-checkbox-field tcs-standalone">
                      <label>
                        <input
                          type="checkbox"
                          checked={draft.agreed}
                          aria-invalid={invalid("agreed")}
                          aria-describedby={errors.agreed ? "agreed-error" : undefined}
                          onChange={(e) => {
                            clearError("agreed");
                            const checked = e.target.checked;
                            setDraft((d) => ({ ...d, agreed: checked }));
                          }}
                        />
                        <span>
                          {DECLARATION_COPY.agreement}{" "}
                          <span className="tcs-required" aria-hidden="true">
                            *
                          </span>
                        </span>
                      </label>
                    </div>
                    {errors.agreed && (
                      <div id="agreed-error" className="tcs-field-error">
                        {errors.agreed}
                      </div>
                    )}
                  </div>

                  <p className="tcs-block-heading" style={{ marginTop: "1.5rem" }}>
                    {DECLARATION_COPY.mediaHeading}
                  </p>
                  <div className="tcs-declaration-text">
                    <p>{DECLARATION_COPY.mediaText}</p>
                  </div>
                  <div className="tcs-field">
                    <div className="tcs-checkbox-field tcs-standalone">
                      <label>
                        <input
                          type="checkbox"
                          checked={draft.mediaConsent}
                          onChange={(e) => {
                            const checked = e.target.checked;
                            setDraft((d) => ({ ...d, mediaConsent: checked }));
                          }}
                        />
                        <span>{DECLARATION_COPY.mediaAgreement}</span>
                      </label>
                    </div>
                  </div>

                  <div style={{ marginTop: "1.5rem" }}>
                    <PField
                      id="signature"
                      label={DECLARATION_COPY.signature}
                      required
                      error={errors.signature}
                    >
                      <input
                        id="signature"
                        type="text"
                        maxLength={255}
                        aria-invalid={invalid("signature")}
                        value={draft.signature}
                        onChange={(e) => {
                          clearError("signature");
                          setDraft((d) => ({ ...d, signature: e.target.value }));
                        }}
                      />
                    </PField>
                  </div>
                  <div className="tcs-turnstile" style={{ marginTop: "1.5rem" }}>
                    {verifyUnavailable ? (
                      <p className="tcs-field-error">
                        The security check couldn't load. {APPLICATION_OFFICE_MESSAGE}
                      </p>
                    ) : (
                      <TurnstileWidget
                        siteKey={SITE_KEY}
                        action="application"
                        resetKey={resetKey}
                        onToken={setToken}
                        onUnavailable={() => setVerifyUnavailable(true)}
                      />
                    )}
                  </div>
                </>
              )}
            </div>
          </fieldset>

          <div className="tcs-step-nav">
            {step > 0 && (
              <button
                key="back"
                type="button"
                className="tcs-nav-btn tcs-secondary"
                onClick={() => goToStep(step - 1)}
              >
                {COPY.back}
              </button>
            )}
            {step < LAST_STEP ? (
              <button
                key="next"
                type="button"
                className="tcs-nav-btn tcs-primary"
                onClick={() => goToStep(step + 1)}
              >
                {COPY.next}
              </button>
            ) : (
              <button
                key="submit"
                type="submit"
                className="tcs-nav-btn tcs-primary"
                disabled={busy || uploading !== null || verifyUnavailable}
              >
                {busy ? COPY.submitting : COPY.submit}
              </button>
            )}
          </div>
          <div className="tcs-save-later">
            <button ref={saveLaterRef} type="button" className="tcs-link-btn" onClick={openPanel}>
              {SAVE_COPY.button}
            </button>
          </div>
        </form>

        <nav ref={navRef} className="tcs-section-nav" aria-label="Application sections">
          {STEPS.map((s, n) => (
            <button
              key={s.key}
              type="button"
              className={[
                "tcs-section-nav-item",
                n === step ? "tcs-active" : "",
                complete[n] ? "tcs-complete" : "",
              ]
                .filter(Boolean)
                .join(" ")}
              aria-current={n === step ? "step" : undefined}
              onClick={() => goToStep(n)}
            >
              <span className="tcs-section-nav-dot" aria-hidden="true" />
              {s.nav}
              {complete[n] && <span className="sr-only"> (complete)</span>}
            </button>
          ))}
        </nav>
      </div>
    </>
  );
}

/** Deletes the saved application after a confirm: the parent's own
 * erasure. A link that no longer opens anything counts as deleted. */
function DiscardButton({ token, onDiscarded }: { token: string; onDiscarded: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <>
      <button
        type="button"
        className="tcs-link-btn"
        disabled={busy}
        onClick={async () => {
          if (!window.confirm(SAVE_COPY.discardConfirm)) return;
          setBusy(true);
          setError(null);
          const a = await deleteDraft(token);
          setBusy(false);
          if (a.ok || a.code === "draft_invalid") onDiscarded();
          else setError(a.message);
        }}
      >
        {SAVE_COPY.discard}
      </button>
      {error && <p className="tcs-field-error">{error}</p>}
    </>
  );
}

type PanelNote = {
  kind: "success" | "error";
  text: string;
  /** After a resume email limit on a later save. */
  offerWithoutEmail?: boolean;
  /** After a version conflict: the latest version, to save over. */
  overwriteVersion?: number;
};

/** Save and finish later. The first save asks for the email (prefilled
 * from guardian 1), the consent tick and a security check, and emails the
 * link. Later saves need none of these, and can email a new link. A
 * resume email limit undoes the save; nothing typed is lost, and a later
 * save can go again without the email. Outside the form element, so Enter
 * in its email field can never submit the application. */
function SavePanel({
  draft,
  step,
  saved,
  onSaved,
  onLost,
  onClosed,
  onLocked,
  onClose,
}: {
  draft: ApplicationDraft;
  step: number;
  saved: SavedDraft | null;
  onSaved: (saved: SavedDraft, key: string) => void;
  onLost: () => void;
  onClosed: () => void;
  onLocked: () => void;
  onClose: () => void;
}) {
  const [email, setEmail] = useState(() => defaultSaveEmail(draft));
  const [consent, setConsent] = useState(false);
  const [turnstile, setTurnstile] = useState("");
  const [resetKey, setResetKey] = useState(0);
  const [unavailable, setUnavailable] = useState(false);
  const [emailAgain, setEmailAgain] = useState(false);
  const [busy, setBusy] = useState(false);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; consent?: string }>({});
  const [note, setNote] = useState<PanelNote | null>(null);
  // A ref, not state: a second click in the same tick can't start a second
  // save (a second first save would make a second draft and email).
  const sending = useRef(false);

  async function refused(code: DraftErrorCode, text: string, later: boolean) {
    if (code === "closed") return onClosed();
    if (code === "draft_submitted") return onLocked();
    if (code === "email") return setFieldErrors({ email: text });
    if (code === "consent") return setFieldErrors({ consent: text });
    if (code === "draft_expired" || code === "draft_invalid") onLost();
    if (code === "draft_version" && saved) {
      // Saved from another window, or an earlier save whose answer was
      // lost. Reloading would lose the link, so read the latest version
      // and offer to save what is on this screen over it.
      // Held across the re-read, so a click meanwhile can't save the
      // stale version again.
      sending.current = true;
      setBusy(true);
      const latest = await loadDraft(saved.token);
      sending.current = false;
      setBusy(false);
      if (latest.ok) {
        return setNote({
          kind: "error",
          text: SAVE_COPY.versionConflict,
          overwriteVersion: latest.version,
        });
      }
      if (latest.code === "draft_expired" || latest.code === "draft_invalid") onLost();
      return setNote({ kind: "error", text: latest.message });
    }
    setNote({
      kind: "error",
      text:
        code === "draft_email_limit"
          ? `${text} ${SAVE_COPY.notLost}`
          : code === "draft_state"
            ? SAVE_COPY.stateRefused
            : text,
      offerWithoutEmail: later && code === "draft_email_limit",
    });
  }

  async function save(sendEmail: boolean, overVersion?: number) {
    if (sending.current) return;
    setNote(null);
    setFieldErrors({});
    const state = toSavedState(draft);
    // The snapshot this save keeps: typing during the request still counts
    // as unsaved afterwards.
    const key = JSON.stringify(state);
    if (!saved) {
      if (!consent) return setFieldErrors({ consent: SAVE_COPY.consentRequired });
      if (turnstile === "") return setNote({ kind: "error", text: COPY.completeCheck });
      sending.current = true;
      setBusy(true);
      const a = await createDraft(turnstile, email.trim(), state, step, true);
      sending.current = false;
      setBusy(false);
      // A token is single use: the next attempt needs a new one.
      setResetKey((k) => k + 1);
      setTurnstile("");
      if (!a.ok) return refused(a.code, a.message, false);
      onSaved(
        { token: a.token, version: a.version, emailMasked: a.emailMasked, expiresAt: a.expiresAt },
        key,
      );
      setNote({ kind: "success", text: SAVE_COPY.saved(a.emailMasked, keptUntil(a.expiresAt)) });
      return;
    }
    sending.current = true;
    setBusy(true);
    const a = await saveDraft(saved.token, state, step, overVersion ?? saved.version, sendEmail);
    sending.current = false;
    setBusy(false);
    if (!a.ok) return refused(a.code, a.message, true);
    onSaved(
      { ...saved, version: a.version, emailMasked: a.emailMasked, expiresAt: a.expiresAt },
      key,
    );
    setEmailAgain(false);
    setNote({
      kind: "success",
      text: a.emailQueued
        ? SAVE_COPY.savedAgainEmailed(a.emailMasked, keptUntil(a.expiresAt))
        : SAVE_COPY.savedAgain(keptUntil(a.expiresAt)),
    });
  }

  return (
    <div
      id="save-panel"
      className="tcs-card tcs-save-panel"
      role="region"
      aria-labelledby="save-panel-title"
    >
      <h2 id="save-panel-title" tabIndex={-1}>
        {SAVE_COPY.panelTitle}
      </h2>
      {!saved ? (
        <>
          <p>{SAVE_COPY.panelIntro}</p>
          <PField id="save-email" label={SAVE_COPY.emailLabel} required error={fieldErrors.email}>
            <input
              id="save-email"
              type="email"
              inputMode="email"
              maxLength={254}
              aria-invalid={fieldErrors.email ? true : undefined}
              value={email}
              onChange={(e) => {
                setEmail(e.target.value);
                setFieldErrors((f) => ({ ...f, email: undefined }));
              }}
            />
          </PField>
          <div className="tcs-field">
            <div className="tcs-checkbox-field tcs-standalone">
              <label>
                <input
                  type="checkbox"
                  checked={consent}
                  aria-invalid={fieldErrors.consent ? true : undefined}
                  aria-describedby={fieldErrors.consent ? "save-consent-error" : undefined}
                  onChange={(e) => {
                    setConsent(e.target.checked);
                    setFieldErrors((f) => ({ ...f, consent: undefined }));
                  }}
                />
                <span>
                  {SAVE_COPY.consentBefore}{" "}
                  {PRIVACY_POLICY.url ? (
                    <a href={PRIVACY_POLICY.url} target="_blank" rel="noopener noreferrer">
                      {PRIVACY_POLICY.text}
                    </a>
                  ) : (
                    PRIVACY_POLICY.text
                  )}
                  {SAVE_COPY.consentAfter}{" "}
                  <span className="tcs-required" aria-hidden="true">
                    *
                  </span>
                </span>
              </label>
            </div>
            {fieldErrors.consent && (
              <div id="save-consent-error" className="tcs-field-error">
                {fieldErrors.consent}
              </div>
            )}
          </div>
          <div className="tcs-turnstile">
            <p className="tcs-question">{SAVE_COPY.turnstilePrompt}</p>
            {unavailable ? (
              <p className="tcs-field-error">
                The security check couldn't load. {APPLICATION_OFFICE_MESSAGE}
              </p>
            ) : (
              <TurnstileWidget
                siteKey={SITE_KEY}
                action="draft"
                resetKey={resetKey}
                onToken={setTurnstile}
                onUnavailable={() => setUnavailable(true)}
              />
            )}
          </div>
        </>
      ) : (
        <div className="tcs-checkbox-field tcs-standalone">
          <label>
            <input
              type="checkbox"
              checked={emailAgain}
              onChange={(e) => setEmailAgain(e.target.checked)}
            />
            <span>{SAVE_COPY.emailAgain}</span>
          </label>
        </div>
      )}
      {/* Both live regions stay mounted, so what is put in them is
          announced. */}
      <div role="status" aria-live="polite">
        {note?.kind === "success" && (
          <div className="tcs-message tcs-success" style={{ marginTop: "1rem", marginBottom: 0 }}>
            <p>{note.text}</p>
          </div>
        )}
      </div>
      <div role="alert">
        {note?.kind === "error" && (
          <div className="tcs-message tcs-error" style={{ marginTop: "1rem", marginBottom: 0 }}>
            <p>{note.text}</p>
            {(note.offerWithoutEmail || note.overwriteVersion !== undefined) && (
              <div className="tcs-save-actions">
                <button
                  type="button"
                  className="tcs-nav-btn tcs-secondary"
                  disabled={busy}
                  onClick={() =>
                    note.overwriteVersion !== undefined
                      ? void save(emailAgain, note.overwriteVersion)
                      : void save(false)
                  }
                >
                  {note.overwriteVersion !== undefined
                    ? SAVE_COPY.saveThisScreen
                    : SAVE_COPY.saveWithoutEmail}
                </button>
              </div>
            )}
          </div>
        )}
      </div>
      <div className="tcs-save-actions">
        <button
          type="button"
          className="tcs-nav-btn tcs-primary"
          disabled={busy || (!saved && unavailable)}
          onClick={() => void save(saved ? emailAgain : true)}
        >
          {busy ? SAVE_COPY.saving : saved ? SAVE_COPY.saveChanges : SAVE_COPY.save}
        </button>
        <button type="button" className="tcs-nav-btn tcs-secondary" onClick={onClose}>
          {SAVE_COPY.close}
        </button>
      </div>
    </div>
  );
}
