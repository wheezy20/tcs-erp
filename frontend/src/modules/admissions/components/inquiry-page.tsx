import { Fragment, useState, type FormEvent, type ReactNode } from "react";

import {
  BlockHeading,
  NativeSelect,
  PField,
  PublicNotice,
  PublicPage,
  Row,
  Section,
} from "@/modules/admissions/components/public-page-parts";
import { TurnstileWidget } from "@/modules/admissions/components/turnstile-widget";
import { getPublicAdmissionsOptions, submitInquiry } from "@/modules/admissions/data/public-intake";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  MAX_GUARDIANS,
  MAX_STUDENTS,
  MONTH_OPTIONS,
  OFFICE_MESSAGE,
  OTHER,
  PHONE_EXAMPLE,
  PHONE_HINT,
  REFERRAL_OPTIONS,
  RELATIONSHIP_OPTIONS,
  RELIGION_OPTIONS,
  ageHint,
  buildInquiryPayload,
  currentGradeChoices,
  emptyDraft,
  emptyGuardian,
  gradesForCampus,
  inquiryView,
  maskDateInput,
  needsCurrentSchool,
  parseDmy,
  phoneTypingError,
  readPhoneInput,
  todayInAccra,
  validateInquiry,
  withCampus,
  withChildCount,
  type FieldErrors,
  type GuardianDraft,
  type InquiryDraft,
  type PublicOptions,
  type StudentDraft,
} from "@/modules/admissions/inquiry-form";
import { ENQUIRY_COPY as COPY, joinNames } from "@/modules/admissions/public-copy";

// /inquiry: the public enquiry form (admissions slices 8 and 8b), with the
// TCS OS look and wording from slice 9b (C1): Cinzel and DM Sans, the TCS
// palette, one card with four numbered sections, as in TCS OS
// backend/templates/public/inquiry.html. No sign-in and no AppShell
// (__root.tsx lists it as auth-free). The page offers only what
// get_public_admissions_options returns; every rule is enforced again by
// the Edge Function and submit_inquiry. Parents see "enquiry"; the route
// and INQ references keep "inquiry".
//
// Kept from the ERP on purpose (slice 8b rules, D-9d): the religion list,
// grade, year and month lists without a free-text "Other", the current
// school asked only for a child already in school (so it follows the
// current grade), the optional campus, and the forgiving phone box with
// its hint.

const NO_CAMPUS = "__none__";
const SITE_KEY = (import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined) ?? "";
let missingKeyReported = false;

export function InquiryPage() {
  const options = useLoad(getPublicAdmissionsOptions, [], "Could not load the form.");
  const [closedAfterSubmit, setClosedAfterSubmit] = useState(false);
  const [created, setCreated] = useState<{ references: string[]; names: string } | null>(null);

  const view = inquiryView({
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
    body = <ThankYou references={created.references} names={created.names} />;
  } else if (view === "closed") {
    body = (
      <PublicNotice title={COPY.closedTitle}>
        <p>{COPY.closedBody}</p>
      </PublicNotice>
    );
  } else if (view === "unavailable") {
    // Not a secret: says only that the public site key wasn't built in, so
    // the cause shows up in the browser console instead of a silent page.
    if (!missingKeyReported && typeof window !== "undefined") {
      missingKeyReported = true;
      console.error(
        "Inquiry form unavailable: VITE_TURNSTILE_SITE_KEY was empty when this site was built.",
      );
    }
    body = (
      <PublicNotice title={COPY.unavailableTitle}>
        <p>{OFFICE_MESSAGE}</p>
      </PublicNotice>
    );
  } else {
    body = (
      <InquiryForm
        options={options.data}
        onCreated={(references, names) => setCreated({ references, names })}
        onClosed={() => setClosedAfterSubmit(true)}
      />
    );
  }

  return (
    <PublicPage>
      <h1>{COPY.title}</h1>
      <p className="tcs-subtitle">
        {COPY.subtitle}
        {view === "form" && <span className="tcs-subtitle-note">{COPY.requiredNote}</span>}
      </p>
      {body}
    </PublicPage>
  );
}

/** The reference, and the note that a confirmation email follows (slice
 * 12). The names are the ones the parent typed, not anything the server
 * sent back. */
function ThankYou({ references, names }: { references: string[]; names: string }) {
  const many = references.length > 1;
  return (
    <>
      <div className="tcs-message tcs-success" role="status">
        {COPY.thankYouFor(names)}
      </div>
      <PublicNotice title={COPY.thankYouTitle}>
        <div className="tcs-reference-box">
          <p>{many ? COPY.referenceMany : COPY.referenceOne}</p>
          {references.map((r) => (
            <p key={r} className="tcs-reference">
              {r}
            </p>
          ))}
        </div>
        <p>{COPY.keepReference(many)}</p>
      </PublicNotice>
    </>
  );
}

function InquiryForm({
  options,
  onCreated,
  onClosed,
}: {
  options: PublicOptions;
  onCreated: (refs: string[], names: string) => void;
  onClosed: () => void;
}) {
  const [draft, setDraft] = useState<InquiryDraft>(emptyDraft);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [token, setToken] = useState("");
  const [resetKey, setResetKey] = useState(0);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [verifyUnavailable, setVerifyUnavailable] = useState(false);
  const today = todayInAccra();

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
  const setStudent = (i: number, field: string, next: (s: StudentDraft) => StudentDraft) => {
    clearError(`students.${i}.${field}`);
    setDraft((d) => ({ ...d, students: d.students.map((s, j) => (j === i ? next(s) : s)) }));
  };

  // The first field in red, else the message box at the top (TCS OS shows
  // its messages above the form).
  function scrollToProblem() {
    requestAnimationFrame(() => {
      const target =
        document.querySelector("[aria-invalid='true']") ??
        document.getElementById("inquiry-message");
      target?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setFormError(null);
    const found = validateInquiry(draft, options, today);
    setErrors(found);
    if (Object.keys(found).length > 0) {
      setFormError(COPY.checkFields);
      scrollToProblem();
      return;
    }
    if (token === "") {
      setFormError(COPY.completeCheck);
      scrollToProblem();
      return;
    }
    setBusy(true);
    try {
      const outcome = await submitInquiry(token, buildInquiryPayload(draft));
      if (outcome.kind === "created") {
        onCreated(outcome.references, joinNames(draft.students.map((s) => s.fullName)));
        window.scrollTo({ top: 0 });
      } else if (outcome.kind === "closed") {
        onClosed();
      } else if (outcome.field) {
        // A server check the form didn't catch: show it next to its field.
        setErrors({ [outcome.field]: outcome.message });
        setFormError(COPY.checkFields);
        scrollToProblem();
      } else {
        setFormError(outcome.message);
        scrollToProblem();
      }
    } finally {
      // A token is single use: always start the next attempt with a new one.
      setResetKey((k) => k + 1);
      setToken("");
      setBusy(false);
    }
  }

  const invalid = (key: string) => (errors[key] ? true : undefined);
  const referralItems = REFERRAL_OPTIONS.map((o) => ({ value: o.value, label: o.label }));
  const relationshipItems = RELATIONSHIP_OPTIONS.map((o) => ({ value: o.value, label: o.label }));
  const religionItems = RELIGION_OPTIONS.map((r) => ({ value: r, label: r }));
  const monthItems = MONTH_OPTIONS.map((m) => ({ value: m.value, label: m.label }));
  const campusItems = [
    { value: NO_CAMPUS, label: "No preference" },
    ...options.campuses.map((c) => ({ value: c.id, label: c.name })),
  ];
  const currentItems = currentGradeChoices(options);
  const countItems = Array.from({ length: MAX_STUDENTS }, (_, i) => ({
    value: String(i + 1),
    label: String(i + 1),
  }));

  return (
    <>
      {formError && (
        <div id="inquiry-message" className="tcs-message tcs-error" role="alert">
          {formError}
        </div>
      )}
      <form onSubmit={submit} className="tcs-card" noValidate>
        {/* ------------------------------------------------ 1. referral */}
        <Section number={1} title={COPY.sections.referral}>
          <PField
            id="referral"
            label="Referral source"
            required
            error={errors.referralSource ?? errors.referralSourceOther}
          >
            <NativeSelect
              id="referral"
              value={draft.referralSource}
              onChange={(v) => {
                clearError("referralSource");
                setDraft((d) => ({ ...d, referralSource: v }));
              }}
              placeholder="Select one"
              items={referralItems}
              invalid={!!errors.referralSource}
            />
            {draft.referralSource === OTHER && (
              <input
                id="referral-other"
                type="text"
                className="tcs-other-input"
                placeholder="Please specify"
                aria-label="Please specify how you heard about us"
                maxLength={255}
                aria-invalid={invalid("referralSourceOther")}
                aria-describedby={errors.referralSourceOther ? "referral-error" : undefined}
                value={draft.referralSourceOther}
                onChange={(e) => {
                  clearError("referralSourceOther");
                  setDraft((d) => ({ ...d, referralSourceOther: e.target.value }));
                }}
              />
            )}
          </PField>
        </Section>

        {/* ------------------------------------------------ 2. guardians */}
        <Section number={2} title={COPY.sections.guardians}>
          {draft.guardians.map((g, i) => {
            const k = (f: string) => `guardians.${i}.${f}`;
            const id = (f: string) => `g${i}-${f}`;
            const sameAddress = i === 1 && draft.secondSameAddress;
            const shown = sameAddress
              ? { address: draft.guardians[0].address, townCity: draft.guardians[0].townCity }
              : { address: g.address, townCity: g.townCity };
            const text = (
              field: "surname" | "firstName" | "email",
              label: string,
              extra: { type?: string; inputMode?: "email"; max?: number } = {},
            ) => (
              <PField id={id(field)} label={label} required error={errors[k(field)]}>
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
            // Blocks are siblings (no wrapper), so the dashed rule between
            // them and none after the last works as in TCS OS.
            return (
              <Fragment key={i}>
                <div className="tcs-block">
                  <BlockHeading
                    action={
                      i > 0 ? (
                        <button
                          type="button"
                          className="tcs-link-btn tcs-subtle"
                          onClick={() =>
                            setDraft((d) => ({
                              ...d,
                              secondSameAddress: false,
                              guardians: d.guardians.filter((_, j) => j !== i),
                            }))
                          }
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
                  <PField id={id("address")} label="Address" required error={errors[k("address")]}>
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
                      <input
                        id={id("phone")}
                        type="tel"
                        inputMode="tel"
                        placeholder={PHONE_EXAMPLE}
                        maxLength={32}
                        aria-invalid={invalid(k("phone"))}
                        value={g.phone}
                        onChange={(e) => {
                          // Keeps what they type; a symbol or extra digit shows its
                          // error at once (not while 233... is still being typed).
                          const raw = e.target.value;
                          setGuardian(i, { phone: raw });
                          const error = phoneTypingError(raw);
                          if (error) setErrors((x) => ({ ...x, [k("phone")]: error }));
                        }}
                        onBlur={() => {
                          // On leaving the box, show the number in its fixed form:
                          // separators gone, 0... or 233... turned into +233...
                          const read = readPhoneInput(g.phone);
                          if (!read.error && read.display !== g.phone) {
                            setGuardian(i, { phone: read.display });
                          }
                        }}
                      />
                    </PField>
                  </Row>
                  {text("email", "Active email address", {
                    type: "email",
                    inputMode: "email",
                    max: 254,
                  })}
                </div>
                {i === 0 && draft.guardians.length < MAX_GUARDIANS && (
                  <button
                    type="button"
                    className="tcs-link-btn"
                    onClick={() =>
                      setDraft((d) => ({ ...d, guardians: [...d.guardians, emptyGuardian()] }))
                    }
                  >
                    {COPY.addGuardian}
                  </button>
                )}
              </Fragment>
            );
          })}
        </Section>

        {/* ------------------------------------------------ 3. the enquiry */}
        <Section number={3} title={COPY.sections.enquiry}>
          <PField id="child-count" label={COPY.childCount} required>
            <NativeSelect
              id="child-count"
              value={String(draft.students.length)}
              onChange={(v) => {
                const n = Number(v);
                // Errors of the children dropped from the end go with them.
                setErrors((e) =>
                  Object.fromEntries(
                    Object.entries(e).filter(([key]) => {
                      const m = /^students\.([0-9]+)\./.exec(key);
                      return !m || Number(m[1]) < n;
                    }),
                  ),
                );
                setDraft((d) => withChildCount(d, n));
              }}
              items={countItems}
            />
          </PField>
          {draft.students.map((s, i) => {
            const k = (f: string) => `students.${i}.${f}`;
            const id = (f: string) => `s${i}-${f}`;
            const grades = gradesForCampus(options, s.campusId);
            const campusName = options.campuses.find((c) => c.id === s.campusId)?.name;
            const hint = ageHint(parseDmy(s.dateOfBirth), today);
            return (
              <div key={i} className="tcs-block">
                <BlockHeading>Child {i + 1}</BlockHeading>
                <PField id={id("name")} label="Full name" required error={errors[k("fullName")]}>
                  <input
                    id={id("name")}
                    type="text"
                    maxLength={255}
                    aria-invalid={invalid(k("fullName"))}
                    value={s.fullName}
                    onChange={(e) =>
                      setStudent(i, "fullName", (x) => ({ ...x, fullName: e.target.value }))
                    }
                  />
                </PField>
                <PField
                  id={id("dob")}
                  label="Date of birth"
                  required
                  error={errors[k("dateOfBirth")]}
                  hint={hint}
                >
                  <input
                    id={id("dob")}
                    type="text"
                    inputMode="numeric"
                    placeholder="dd/mm/yyyy"
                    maxLength={10}
                    autoComplete="off"
                    aria-invalid={invalid(k("dateOfBirth"))}
                    value={s.dateOfBirth}
                    onChange={(e) =>
                      setStudent(i, "dateOfBirth", (x) => ({
                        ...x,
                        dateOfBirth: maskDateInput(e.target.value),
                      }))
                    }
                  />
                </PField>
                <Row>
                  <PField
                    id={id("current")}
                    label="Current grade / class"
                    required
                    error={errors[k("currentGrade")]}
                  >
                    <NativeSelect
                      id={id("current")}
                      value={s.currentGrade}
                      onChange={(v) => {
                        clearError(k("currentSchool"));
                        setStudent(i, "currentGrade", (x) => ({ ...x, currentGrade: v }));
                      }}
                      placeholder="Select one"
                      items={currentItems}
                      invalid={!!errors[k("currentGrade")]}
                    />
                  </PField>
                  {needsCurrentSchool(s) && (
                    <PField
                      id={id("school")}
                      label="Learner's current school"
                      required
                      error={errors[k("currentSchool")]}
                    >
                      <input
                        id={id("school")}
                        type="text"
                        maxLength={255}
                        placeholder="N/A if not yet in school"
                        aria-invalid={invalid(k("currentSchool"))}
                        value={s.currentSchool}
                        onChange={(e) =>
                          setStudent(i, "currentSchool", (x) => ({
                            ...x,
                            currentSchool: e.target.value,
                          }))
                        }
                      />
                    </PField>
                  )}
                </Row>
                <Row>
                  <PField id={id("campus")} label="Preferred campus" error={errors[k("campusId")]}>
                    <NativeSelect
                      id={id("campus")}
                      value={s.campusId === "" ? NO_CAMPUS : s.campusId}
                      onChange={(v) =>
                        setStudent(i, "campusId", (x) =>
                          withCampus(x, v === NO_CAMPUS ? "" : v, options),
                        )
                      }
                      items={campusItems}
                      invalid={!!errors[k("campusId")]}
                    />
                  </PField>
                  <PField
                    id={id("grade")}
                    label="Grade seeking admission into"
                    required
                    error={errors[k("gradeId")]}
                    hint={`${campusName ? `Showing the grades ${campusName} takes. ` : ""}Grade not listed? Please contact the school.`}
                  >
                    <NativeSelect
                      id={id("grade")}
                      value={s.gradeId}
                      onChange={(v) => setStudent(i, "gradeId", (x) => ({ ...x, gradeId: v }))}
                      placeholder="Select one"
                      items={grades.map((g) => ({ value: g.id, label: g.name }))}
                      invalid={!!errors[k("gradeId")]}
                    />
                  </PField>
                </Row>
                <Row>
                  <PField
                    id={id("year")}
                    label="Academic year enquiring for"
                    required
                    error={errors[k("academicYear")]}
                  >
                    <NativeSelect
                      id={id("year")}
                      value={s.academicYear}
                      onChange={(v) =>
                        setStudent(i, "academicYear", (x) => ({ ...x, academicYear: v }))
                      }
                      placeholder="Select one"
                      items={options.academicYears.map((y) => ({ value: y, label: y }))}
                      invalid={!!errors[k("academicYear")]}
                    />
                  </PField>
                  <PField
                    id={id("month")}
                    label="Month of enrolment"
                    required
                    error={errors[k("month")]}
                  >
                    <NativeSelect
                      id={id("month")}
                      value={s.month}
                      onChange={(v) => setStudent(i, "month", (x) => ({ ...x, month: v }))}
                      placeholder="Select one"
                      items={monthItems}
                      invalid={!!errors[k("month")]}
                    />
                  </PField>
                </Row>
              </div>
            );
          })}
        </Section>

        {/* ------------------------------------------------ 4. other information */}
        <Section number={4} title={COPY.sections.other}>
          <PField id="comments" label="Comments, suggestions or questions" error={errors.comments}>
            <textarea
              id="comments"
              maxLength={10000}
              placeholder="Anything else we should know?"
              aria-invalid={invalid("comments")}
              value={draft.comments}
              onChange={(e) => setDraft((d) => ({ ...d, comments: e.target.value }))}
            />
          </PField>
        </Section>

        {/* ------------------------------------------------ submit */}
        <div className="tcs-turnstile">
          {verifyUnavailable ? (
            <p className="tcs-field-error">
              {COPY.verifyUnavailable} {OFFICE_MESSAGE}
            </p>
          ) : (
            <TurnstileWidget
              siteKey={SITE_KEY}
              action="inquiry"
              resetKey={resetKey}
              onToken={setToken}
              onUnavailable={() => setVerifyUnavailable(true)}
            />
          )}
        </div>
        <button type="submit" className="tcs-submit" disabled={busy || verifyUnavailable}>
          {busy ? COPY.submitting : COPY.submit}
        </button>
      </form>
    </>
  );
}
