import { useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Choice, Field, Notice, Shell } from "@/modules/admissions/components/public-form-parts";
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
  emptyStudent,
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
  type FieldErrors,
  type GuardianDraft,
  type InquiryDraft,
  type PublicOptions,
  type StudentDraft,
} from "@/modules/admissions/inquiry-form";

// /inquiry: the public enquiry form (admissions slices 8 and 8b). No
// sign-in and no AppShell (__root.tsx lists it as auth-free). The page
// offers only what get_public_admissions_options returns; every rule is
// enforced again by the Edge Function and submit_inquiry. Parents see
// "enquiry"; the route and INQ references keep "inquiry".

const NO_CAMPUS = "__none__";
const SITE_KEY = (import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined) ?? "";
let missingKeyReported = false;

export function InquiryPage() {
  const options = useLoad(getPublicAdmissionsOptions, [], "Could not load the form.");
  const [closedAfterSubmit, setClosedAfterSubmit] = useState(false);
  const [references, setReferences] = useState<string[] | null>(null);

  const view = inquiryView({
    loading: options.loading,
    error: options.error,
    options: options.data,
    created: references !== null,
    closedAfterSubmit,
    siteKey: SITE_KEY,
  });

  if (view === "loading") {
    return <Shell>Loading…</Shell>;
  }
  if (view === "loadError" || !options.data) {
    return (
      <Notice title="The enquiry form couldn't load">
        Please try again later, or call the school office to make an enquiry.
      </Notice>
    );
  }
  if (view === "created" && references) {
    return <ThankYou references={references} />;
  }
  if (view === "closed") {
    return (
      <Notice title="Online enquiries are closed">
        We're not taking enquiries online at the moment. Please call the school office to make an
        enquiry.
      </Notice>
    );
  }
  if (view === "unavailable") {
    // Not a secret: says only that the public site key wasn't built in, so
    // the cause shows up in the browser console instead of a silent page.
    if (!missingKeyReported && typeof window !== "undefined") {
      missingKeyReported = true;
      console.error(
        "Inquiry form unavailable: VITE_TURNSTILE_SITE_KEY was empty when this site was built.",
      );
    }
    return <Notice title="The enquiry form isn't available">{OFFICE_MESSAGE}</Notice>;
  }
  return (
    <InquiryForm
      options={options.data}
      onCreated={setReferences}
      onClosed={() => setClosedAfterSubmit(true)}
    />
  );
}

/** No confirmation email exists until slice 12, so this page is the
 * parent's only record of the reference. */
function ThankYou({ references }: { references: string[] }) {
  const many = references.length > 1;
  return (
    <div className="mx-auto max-w-xl px-4 py-16 text-center">
      <img src="/tcs-logomark.png" alt="" className="mx-auto mb-6 h-12 w-12" />
      <h1 className="text-lg font-semibold">Thank you, we've received your enquiry</h1>
      <p className="mt-2 text-sm text-muted-foreground">
        The school will contact you about the next steps.
      </p>
      <div className="mx-auto mt-6 max-w-sm rounded-lg border p-4">
        <p className="text-sm text-muted-foreground">
          {many ? "Your reference numbers" : "Your reference number"}
        </p>
        <ul className="mt-2 space-y-1">
          {references.map((r) => (
            <li key={r} className="font-mono text-lg font-semibold tabular-nums">
              {r}
            </li>
          ))}
        </ul>
      </div>
      <p className="mt-4 text-sm text-muted-foreground">
        Please keep {many ? "these numbers" : "this number"}. You won't receive a confirmation
        email, so write {many ? "them" : "it"} down or take a screenshot, and quote{" "}
        {many ? "them" : "it"} when you contact the school.
      </p>
    </div>
  );
}

function InquiryForm({
  options,
  onCreated,
  onClosed,
}: {
  options: PublicOptions;
  onCreated: (refs: string[]) => void;
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

  function scrollToFirstError() {
    requestAnimationFrame(() => {
      document.querySelector("[aria-invalid='true']")?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    });
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setFormError(null);
    const found = validateInquiry(draft, options, today);
    setErrors(found);
    if (Object.keys(found).length > 0) {
      setFormError("Please check the fields marked in red.");
      scrollToFirstError();
      return;
    }
    if (token === "") {
      setFormError("Please complete the security check below.");
      return;
    }
    setBusy(true);
    try {
      const outcome = await submitInquiry(token, buildInquiryPayload(draft));
      if (outcome.kind === "created") onCreated(outcome.references);
      else if (outcome.kind === "closed") onClosed();
      else if (outcome.field) {
        // A server check the form didn't catch: show it next to its field.
        setErrors({ [outcome.field]: outcome.message });
        setFormError("Please check the fields marked in red.");
        scrollToFirstError();
      } else setFormError(outcome.message);
    } finally {
      // A token is single use: always start the next attempt with a new one.
      setResetKey((k) => k + 1);
      setToken("");
      setBusy(false);
    }
  }

  const campusItems = [
    { value: NO_CAMPUS, label: "No preference" },
    ...options.campuses.map((c) => ({ value: c.id, label: c.name })),
  ];
  const currentItems = currentGradeChoices(options);
  const religionItems = RELIGION_OPTIONS.map((r) => ({ value: r, label: r }));
  const monthItems = MONTH_OPTIONS.map((m) => ({ value: m.value, label: m.label }));

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <img src="/tcs-logomark.png" alt="" className="mb-4 h-12 w-12" />
      <h1 className="text-xl font-semibold">Admissions enquiry</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Tell us about your family and we'll be in touch about next steps. Fields marked{" "}
        <span className="text-destructive">*</span> are required.
      </p>

      <form onSubmit={submit} className="mt-8 space-y-10" noValidate>
        {/* ------------------------------------------------ guardians */}
        <section className="space-y-6">
          <h2 className="text-base font-semibold">Parents or guardians</h2>
          {draft.guardians.map((g, i) => {
            const k = (f: string) => `guardians.${i}.${f}`;
            const id = (f: string) => `g${i}-${f}`;
            const sameAddress = i === 1 && draft.secondSameAddress;
            const shown = sameAddress
              ? { address: draft.guardians[0].address, townCity: draft.guardians[0].townCity }
              : { address: g.address, townCity: g.townCity };
            const text = (
              field: keyof GuardianDraft,
              label: string,
              extra: { type?: string; inputMode?: "tel" | "email"; max?: number } = {},
            ) => (
              <Field id={id(field)} label={label} required error={errors[k(field)]}>
                <Input
                  id={id(field)}
                  type={extra.type ?? "text"}
                  inputMode={extra.inputMode}
                  maxLength={extra.max ?? 255}
                  aria-invalid={errors[k(field)] ? true : undefined}
                  value={g[field]}
                  onChange={(e) => setGuardian(i, { [field]: e.target.value })}
                />
              </Field>
            );
            return (
              <div key={i} className="space-y-4 rounded-lg border p-4">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-medium">Parent or guardian {i + 1}</h3>
                  {i > 0 && (
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={() =>
                        setDraft((d) => ({
                          ...d,
                          secondSameAddress: false,
                          guardians: d.guardians.filter((_, j) => j !== i),
                        }))
                      }
                    >
                      Remove
                    </Button>
                  )}
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  {text("surname", "Surname / Family name")}
                  {text("firstName", "First name(s)")}
                  <Field
                    id={id("relationship")}
                    label="Relationship to child"
                    required
                    error={errors[k("relationship")]}
                  >
                    <Choice
                      id={id("relationship")}
                      value={g.relationship}
                      onChange={(v) => setGuardian(i, { relationship: v })}
                      placeholder="Select one"
                      items={[...RELATIONSHIP_OPTIONS]}
                      invalid={!!errors[k("relationship")]}
                    />
                  </Field>
                  <Field
                    id={id("religion")}
                    label="Religion"
                    required
                    error={errors[k("religion")]}
                  >
                    <Choice
                      id={id("religion")}
                      value={g.religion}
                      onChange={(v) => setGuardian(i, { religion: v })}
                      placeholder="Select one"
                      items={religionItems}
                      invalid={!!errors[k("religion")]}
                    />
                  </Field>
                  {i === 1 && (
                    <div className="flex items-center gap-2 sm:col-span-2">
                      <Checkbox
                        id="g1-same-address"
                        checked={draft.secondSameAddress}
                        onCheckedChange={(c) => {
                          clearError(k("address"));
                          clearError(k("townCity"));
                          setDraft((d) => ({ ...d, secondSameAddress: c === true }));
                        }}
                      />
                      <Label htmlFor="g1-same-address" className="font-normal">
                        Same address as above
                      </Label>
                    </div>
                  )}
                  <Field id={id("address")} label="Address" required error={errors[k("address")]}>
                    <Input
                      id={id("address")}
                      maxLength={255}
                      disabled={sameAddress}
                      aria-invalid={errors[k("address")] ? true : undefined}
                      value={shown.address}
                      onChange={(e) => setGuardian(i, { address: e.target.value })}
                    />
                  </Field>
                  <Field
                    id={id("townCity")}
                    label="Town / City"
                    required
                    error={errors[k("townCity")]}
                  >
                    <Input
                      id={id("townCity")}
                      maxLength={255}
                      disabled={sameAddress}
                      aria-invalid={errors[k("townCity")] ? true : undefined}
                      value={shown.townCity}
                      onChange={(e) => setGuardian(i, { townCity: e.target.value })}
                    />
                  </Field>
                  <Field
                    id={id("phone")}
                    label="Contact number"
                    required
                    error={errors[k("phone")]}
                    hint={PHONE_HINT}
                  >
                    <Input
                      id={id("phone")}
                      type="tel"
                      inputMode="tel"
                      placeholder={PHONE_EXAMPLE}
                      maxLength={32}
                      aria-invalid={errors[k("phone")] ? true : undefined}
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
                  </Field>
                  {text("email", "Active email address", {
                    type: "email",
                    inputMode: "email",
                    max: 254,
                  })}
                </div>
              </div>
            );
          })}
          {draft.guardians.length < MAX_GUARDIANS && (
            <Button
              type="button"
              variant="outline"
              onClick={() =>
                setDraft((d) => ({ ...d, guardians: [...d.guardians, emptyGuardian()] }))
              }
            >
              Add a second parent or guardian
            </Button>
          )}
        </section>

        {/* ------------------------------------------------ children */}
        <section className="space-y-6">
          <h2 className="text-base font-semibold">Children</h2>
          {draft.students.map((s, i) => {
            const k = (f: string) => `students.${i}.${f}`;
            const id = (f: string) => `s${i}-${f}`;
            const grades = gradesForCampus(options, s.campusId);
            const campusName = options.campuses.find((c) => c.id === s.campusId)?.name;
            const hint = ageHint(parseDmy(s.dateOfBirth), today);
            return (
              <div key={i} className="space-y-4 rounded-lg border p-4">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-medium">Child {i + 1}</h3>
                  {i > 0 && (
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={() =>
                        setDraft((d) => ({ ...d, students: d.students.filter((_, j) => j !== i) }))
                      }
                    >
                      Remove
                    </Button>
                  )}
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field id={id("name")} label="Full name" required error={errors[k("fullName")]}>
                    <Input
                      id={id("name")}
                      maxLength={255}
                      aria-invalid={errors[k("fullName")] ? true : undefined}
                      value={s.fullName}
                      onChange={(e) =>
                        setStudent(i, "fullName", (x) => ({ ...x, fullName: e.target.value }))
                      }
                    />
                  </Field>
                  <Field
                    id={id("dob")}
                    label="Date of birth"
                    required
                    error={errors[k("dateOfBirth")]}
                    hint={hint}
                  >
                    <Input
                      id={id("dob")}
                      inputMode="numeric"
                      placeholder="dd/mm/yyyy"
                      maxLength={10}
                      autoComplete="off"
                      aria-invalid={errors[k("dateOfBirth")] ? true : undefined}
                      value={s.dateOfBirth}
                      onChange={(e) =>
                        setStudent(i, "dateOfBirth", (x) => ({
                          ...x,
                          dateOfBirth: maskDateInput(e.target.value),
                        }))
                      }
                    />
                  </Field>
                  <Field
                    id={id("current")}
                    label="Current grade / class"
                    required
                    error={errors[k("currentGrade")]}
                  >
                    <Choice
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
                  </Field>
                  {needsCurrentSchool(s) && (
                    <Field
                      id={id("school")}
                      label="Learner's current school"
                      required
                      error={errors[k("currentSchool")]}
                    >
                      <Input
                        id={id("school")}
                        maxLength={255}
                        placeholder="N/A if not yet in school"
                        aria-invalid={errors[k("currentSchool")] ? true : undefined}
                        value={s.currentSchool}
                        onChange={(e) =>
                          setStudent(i, "currentSchool", (x) => ({
                            ...x,
                            currentSchool: e.target.value,
                          }))
                        }
                      />
                    </Field>
                  )}
                  <Field id={id("campus")} label="Preferred campus" error={errors[k("campusId")]}>
                    <Choice
                      id={id("campus")}
                      value={s.campusId === "" ? NO_CAMPUS : s.campusId}
                      onChange={(v) =>
                        setStudent(i, "campusId", (x) =>
                          withCampus(x, v === NO_CAMPUS ? "" : v, options),
                        )
                      }
                      placeholder="No preference"
                      items={campusItems}
                      invalid={!!errors[k("campusId")]}
                    />
                  </Field>
                  <Field
                    id={id("grade")}
                    label="Grade seeking admission into"
                    required
                    error={errors[k("gradeId")]}
                    hint={`${campusName ? `Showing the grades ${campusName} takes. ` : ""}Grade not listed? Please contact the school.`}
                  >
                    <Choice
                      id={id("grade")}
                      value={s.gradeId}
                      onChange={(v) => setStudent(i, "gradeId", (x) => ({ ...x, gradeId: v }))}
                      placeholder="Select one"
                      items={grades.map((g) => ({ value: g.id, label: g.name }))}
                      invalid={!!errors[k("gradeId")]}
                    />
                  </Field>
                  <Field
                    id={id("year")}
                    label="Academic year enquiring for"
                    required
                    error={errors[k("academicYear")]}
                  >
                    <Choice
                      id={id("year")}
                      value={s.academicYear}
                      onChange={(v) =>
                        setStudent(i, "academicYear", (x) => ({ ...x, academicYear: v }))
                      }
                      placeholder="Select one"
                      items={options.academicYears.map((y) => ({ value: y, label: y }))}
                      invalid={!!errors[k("academicYear")]}
                    />
                  </Field>
                  <Field
                    id={id("month")}
                    label="Month of enrolment"
                    required
                    error={errors[k("month")]}
                  >
                    <Choice
                      id={id("month")}
                      value={s.month}
                      onChange={(v) => setStudent(i, "month", (x) => ({ ...x, month: v }))}
                      placeholder="Select one"
                      items={monthItems}
                      invalid={!!errors[k("month")]}
                    />
                  </Field>
                </div>
              </div>
            );
          })}
          {draft.students.length < MAX_STUDENTS && (
            <Button
              type="button"
              variant="outline"
              onClick={() => setDraft((d) => ({ ...d, students: [...d.students, emptyStudent()] }))}
            >
              Add another child
            </Button>
          )}
        </section>

        {/* ------------------------------------------------ referral and comments */}
        <section className="space-y-4">
          <h2 className="text-base font-semibold">About your enquiry</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field
              id="referral"
              label="How did you hear about us?"
              required
              error={errors.referralSource}
            >
              <Choice
                id="referral"
                value={draft.referralSource}
                onChange={(v) => {
                  clearError("referralSource");
                  setDraft((d) => ({ ...d, referralSource: v }));
                }}
                placeholder="Select one"
                items={[...REFERRAL_OPTIONS]}
                invalid={!!errors.referralSource}
              />
            </Field>
            {draft.referralSource === OTHER && (
              <Field
                id="referral-other"
                label="Please specify"
                required
                error={errors.referralSourceOther}
              >
                <Input
                  id="referral-other"
                  maxLength={255}
                  aria-invalid={errors.referralSourceOther ? true : undefined}
                  value={draft.referralSourceOther}
                  onChange={(e) => {
                    clearError("referralSourceOther");
                    setDraft((d) => ({ ...d, referralSourceOther: e.target.value }));
                  }}
                />
              </Field>
            )}
          </div>
          <Field id="comments" label="Comments, suggestions or questions" error={errors.comments}>
            <Textarea
              id="comments"
              rows={4}
              maxLength={10000}
              placeholder="Anything else we should know?"
              aria-invalid={errors.comments ? true : undefined}
              value={draft.comments}
              onChange={(e) => setDraft((d) => ({ ...d, comments: e.target.value }))}
            />
          </Field>
        </section>

        {/* ------------------------------------------------ submit */}
        <section className="space-y-4">
          {verifyUnavailable ? (
            <p className="text-sm text-destructive">
              The security check couldn't load. {OFFICE_MESSAGE}
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
          {formError && (
            <p role="alert" className="text-sm text-destructive">
              {formError}
            </p>
          )}
          <Button type="submit" disabled={busy || verifyUnavailable}>
            {busy ? "Sending…" : "Submit enquiry"}
          </Button>
        </section>
      </form>
    </div>
  );
}
