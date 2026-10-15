import { useRef, useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Choice, Field, Notice, Shell } from "@/modules/admissions/components/public-form-parts";
import { TurnstileWidget } from "@/modules/admissions/components/turnstile-widget";
import {
  openUploadSession,
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
  checkFile,
  emptyApplicationDraft,
  requiredDocumentTypes,
  validateApplication,
  type ApplicationDraft,
  type UploadedFile,
} from "@/modules/admissions/application-form";
import {
  MAX_GUARDIANS,
  MONTH_OPTIONS,
  PHONE_EXAMPLE,
  PHONE_HINT,
  RELATIONSHIP_OPTIONS,
  RELIGION_OPTIONS,
  ageHint,
  currentGradeChoices,
  emptyGuardian,
  gradesForCampus,
  maskDateInput,
  NOT_YET_IN_SCHOOL,
  parseDmy,
  phoneTypingError,
  readPhoneInput,
  todayInAccra,
  type FieldErrors,
  type GuardianDraft,
  type PublicOptions,
} from "@/modules/admissions/inquiry-form";

// /apply: the plain public Application form (admissions slice 9a,
// checkpoint 2). No sign-in and no AppShell (__root.tsx lists it as
// auth-free). One page; the six-section form is slice 9b. Two security
// checks: one opens the upload session (action "upload"), one sends the
// application (action "application"). Every rule is enforced again by the
// admissions-public Edge Function and submit_application, which also reads
// each file's first bytes before accepting it.

const SITE_KEY = (import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined) ?? "";
let missingKeyReported = false;

export function ApplicationPage() {
  const options = useLoad(getPublicAdmissionsOptions, [], "Could not load the form.");
  const [closedAfterSubmit, setClosedAfterSubmit] = useState(false);
  const [reference, setReference] = useState<string | null>(null);

  const view = applicationView({
    loading: options.loading,
    error: options.error,
    options: options.data,
    created: reference !== null,
    closedAfterSubmit,
    siteKey: SITE_KEY,
  });

  if (view === "loading") return <Shell>Loading…</Shell>;
  if (view === "loadError" || !options.data) {
    return (
      <Notice title="The application form couldn't load">
        Please try again later, or call the school office to apply.
      </Notice>
    );
  }
  if (view === "created" && reference) return <ThankYou reference={reference} />;
  if (view === "closed") {
    return (
      <Notice title="Online applications are closed">
        We're not taking applications online at the moment. Please call the school office to apply.
      </Notice>
    );
  }
  if (view === "unavailable") {
    if (!missingKeyReported && typeof window !== "undefined") {
      missingKeyReported = true;
      console.error(
        "Application form unavailable: VITE_TURNSTILE_SITE_KEY was empty when this site was built.",
      );
    }
    return (
      <Notice title="The application form isn't available">{APPLICATION_OFFICE_MESSAGE}</Notice>
    );
  }
  return (
    <ApplicationForm
      options={options.data}
      onCreated={setReference}
      onClosed={() => setClosedAfterSubmit(true)}
    />
  );
}

/** No confirmation email exists until slice 12, so this page is the
 * parent's only record of the reference. */
function ThankYou({ reference }: { reference: string }) {
  return (
    <div className="mx-auto max-w-xl px-4 py-16 text-center">
      <img src="/tcs-logomark.png" alt="" className="mx-auto mb-6 h-12 w-12" />
      <h1 className="text-lg font-semibold">Thank you, we've received your application</h1>
      <p className="mt-2 text-sm text-muted-foreground">
        The school will check your documents and contact you about the next steps.
      </p>
      <div className="mx-auto mt-6 max-w-sm rounded-lg border p-4">
        <p className="text-sm text-muted-foreground">Your application number</p>
        <p className="mt-2 font-mono text-lg font-semibold tabular-nums">{reference}</p>
      </div>
      <p className="mt-4 text-sm text-muted-foreground">
        Please keep this number. You won't receive a confirmation email, so write it down or take a
        screenshot, and quote it when you contact the school.
      </p>
    </div>
  );
}

function ApplicationForm({
  options,
  onCreated,
  onClosed,
}: {
  options: PublicOptions;
  onCreated: (reference: string) => void;
  onClosed: () => void;
}) {
  const [draft, setDraft] = useState<ApplicationDraft>(emptyApplicationDraft);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [uploads, setUploads] = useState<Record<string, UploadedFile | undefined>>({});
  const [uploading, setUploading] = useState<string | null>(null);
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [opening, setOpening] = useState(false);
  const [uploadResetKey, setUploadResetKey] = useState(0);
  const [token, setToken] = useState("");
  const [resetKey, setResetKey] = useState(0);
  const [busy, setBusy] = useState(false);
  const sending = useRef(false);
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

  function scrollToFirstError() {
    requestAnimationFrame(() => {
      document
        .querySelector("[aria-invalid='true']")
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
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
    setUploading(type);
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
    } catch (err) {
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
    if (sending.current) return;
    setFormError(null);
    const found = validateApplication(draft, options, today, uploads);
    setErrors(found);
    if (Object.keys(found).length > 0 || !sessionToken) {
      setFormError("Please check the fields marked in red.");
      scrollToFirstError();
      return;
    }
    if (token === "") {
      setFormError("Please complete the security check below.");
      return;
    }
    sending.current = true;
    setBusy(true);
    try {
      const outcome = await submitApplication(
        token,
        sessionToken,
        buildApplicationPayload(draft, options, uploads),
      );
      if (outcome.kind === "created") onCreated(outcome.reference);
      else if (outcome.kind === "closed") onClosed();
      else if (outcome.field) {
        setErrors({ [outcome.field]: outcome.message });
        setFormError(outcome.message);
        scrollToFirstError();
      } else setFormError(outcome.message);
    } finally {
      // A token is single use: always start the next attempt with a new one.
      setResetKey((k) => k + 1);
      setToken("");
      setBusy(false);
      sending.current = false;
    }
  }

  const c = draft.child;
  const grades = gradesForCampus(options, draft.campusId);
  const docTypes = requiredDocumentTypes(options, c.gradeId);
  const religionItems = RELIGION_OPTIONS.map((r) => ({ value: r, label: r }));
  const monthItems = MONTH_OPTIONS.map((m) => ({ value: m.value, label: m.label }));
  const invalid = (key: string) => (errors[key] ? true : undefined);

  const phoneInput = (id: string, key: string, value: string, set: (v: string) => void) => (
    <Input
      id={id}
      type="tel"
      inputMode="tel"
      placeholder={PHONE_EXAMPLE}
      maxLength={32}
      aria-invalid={invalid(key)}
      value={value}
      onChange={(e) => {
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

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <img src="/tcs-logomark.png" alt="" className="mb-4 h-12 w-12" />
      <h1 className="text-xl font-semibold">Application for admission</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        One application per child. Fields marked <span className="text-destructive">*</span> are
        required.
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
              field: "surname" | "firstName" | "email",
              label: string,
              extra: { type?: string; inputMode?: "email"; max?: number } = {},
            ) => (
              <Field id={id(field)} label={label} required error={errors[k(field)]}>
                <Input
                  id={id(field)}
                  type={extra.type ?? "text"}
                  inputMode={extra.inputMode}
                  maxLength={extra.max ?? 255}
                  aria-invalid={invalid(k(field))}
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
                        onCheckedChange={(v) => {
                          clearError(k("address"));
                          clearError(k("townCity"));
                          setDraft((d) => ({ ...d, secondSameAddress: v === true }));
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
                      aria-invalid={invalid(k("address"))}
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
                      aria-invalid={invalid(k("townCity"))}
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
                    {phoneInput(id("phone"), k("phone"), g.phone, (v) =>
                      setGuardian(i, { phone: v }),
                    )}
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

        {/* ------------------------------------------------ child */}
        <section className="space-y-4">
          <h2 className="text-base font-semibold">The child</h2>
          <div className="grid gap-4 rounded-lg border p-4 sm:grid-cols-2">
            <Field id="c-name" label="Full name" required error={errors["child.fullName"]}>
              <Input
                id="c-name"
                maxLength={255}
                aria-invalid={invalid("child.fullName")}
                value={c.fullName}
                onChange={(e) => setChild({ fullName: e.target.value })}
              />
            </Field>
            <Field
              id="c-dob"
              label="Date of birth"
              required
              error={errors["child.dateOfBirth"]}
              hint={ageHint(parseDmy(c.dateOfBirth), today)}
            >
              <Input
                id="c-dob"
                inputMode="numeric"
                placeholder="dd/mm/yyyy"
                maxLength={10}
                autoComplete="off"
                aria-invalid={invalid("child.dateOfBirth")}
                value={c.dateOfBirth}
                onChange={(e) => setChild({ dateOfBirth: maskDateInput(e.target.value) })}
              />
            </Field>
            <Field id="c-gender" label="Gender" required error={errors["child.gender"]}>
              <Choice
                id="c-gender"
                value={c.gender}
                onChange={(v) => setChild({ gender: v })}
                placeholder="Select one"
                items={[...GENDER_OPTIONS]}
                invalid={!!errors["child.gender"]}
              />
            </Field>
            <Field id="c-nat" label="Nationality" required error={errors["child.nationality"]}>
              <Input
                id="c-nat"
                maxLength={100}
                aria-invalid={invalid("child.nationality")}
                value={c.nationality}
                onChange={(e) => setChild({ nationality: e.target.value })}
              />
            </Field>
            <Field id="c-address" label="Child's address" required error={errors["child.address"]}>
              <Input
                id="c-address"
                maxLength={255}
                aria-invalid={invalid("child.address")}
                value={c.address}
                onChange={(e) => setChild({ address: e.target.value })}
              />
            </Field>
            <Field id="c-town" label="Town / City" required error={errors["child.townCity"]}>
              <Input
                id="c-town"
                maxLength={255}
                aria-invalid={invalid("child.townCity")}
                value={c.townCity}
                onChange={(e) => setChild({ townCity: e.target.value })}
              />
            </Field>
            <Field
              id="c-current"
              label="Current grade / class"
              required
              error={errors["child.currentGrade"]}
            >
              <Choice
                id="c-current"
                value={c.currentGrade}
                onChange={(v) => {
                  clearError("child.currentSchool");
                  setChild({ currentGrade: v });
                }}
                placeholder="Select one"
                items={currentGradeChoices(options)}
                invalid={!!errors["child.currentGrade"]}
              />
            </Field>
            {c.currentGrade !== NOT_YET_IN_SCHOOL && (
              <Field
                id="c-school"
                label="Current school"
                required
                error={errors["child.currentSchool"]}
              >
                <Input
                  id="c-school"
                  maxLength={255}
                  aria-invalid={invalid("child.currentSchool")}
                  value={c.currentSchool}
                  onChange={(e) => setChild({ currentSchool: e.target.value })}
                />
              </Field>
            )}
            <Field id="c-campus" label="Campus" required error={errors.campusId}>
              <Choice
                id="c-campus"
                value={draft.campusId}
                onChange={(v) => {
                  clearError("campusId");
                  setDraft((d) => {
                    const keep = gradesForCampus(options, v).some((g) => g.id === d.child.gradeId);
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
            </Field>
            <Field
              id="c-grade"
              label="Grade seeking admission into"
              required
              error={errors["child.gradeId"]}
              hint="Grade not listed? Please contact the school."
            >
              <Choice
                id="c-grade"
                value={c.gradeId}
                onChange={(v) => setChild({ gradeId: v })}
                placeholder={draft.campusId === "" ? "Choose a campus first" : "Select one"}
                items={grades.map((g) => ({ value: g.id, label: g.name }))}
                invalid={!!errors["child.gradeId"]}
              />
            </Field>
            <Field id="c-year" label="Academic year" required error={errors["child.academicYear"]}>
              <Choice
                id="c-year"
                value={c.academicYear}
                onChange={(v) => setChild({ academicYear: v })}
                placeholder="Select one"
                items={options.academicYears.map((y) => ({ value: y, label: y }))}
                invalid={!!errors["child.academicYear"]}
              />
            </Field>
            <Field id="c-month" label="Month of enrolment" required error={errors["child.month"]}>
              <Choice
                id="c-month"
                value={c.month}
                onChange={(v) => setChild({ month: v })}
                placeholder="Select one"
                items={monthItems}
                invalid={!!errors["child.month"]}
              />
            </Field>
          </div>
        </section>

        {/* ------------------------------------------------ health */}
        <section className="space-y-4">
          <h2 className="text-base font-semibold">Health</h2>
          <p className="text-sm text-muted-foreground">
            Only staff who need it can see these answers.
          </p>
          <div className="space-y-4 rounded-lg border p-4">
            {(
              [
                ["hasNeeds", "needs", "Does your child have any learning or physical needs?"],
                ["hasMedical", "medical", "Does your child have any medical conditions?"],
                [
                  "hasAllergies",
                  "allergies",
                  "Does your child have any allergies or dietary requirements?",
                ],
              ] as const
            ).map(([flag, text, label]) => (
              <div key={flag} className="space-y-2">
                <div className="flex items-center gap-2">
                  <Checkbox
                    id={`h-${flag}`}
                    checked={draft.health[flag]}
                    onCheckedChange={(v) => setHealth({ [flag]: v === true, [text]: "" })}
                  />
                  <Label htmlFor={`h-${flag}`} className="font-normal">
                    {label} Tick for yes.
                  </Label>
                </div>
                {draft.health[flag] && (
                  <Field
                    id={`h-${text}`}
                    label="Please give details"
                    required
                    error={errors[`health.${text}`]}
                  >
                    <Textarea
                      id={`h-${text}`}
                      rows={3}
                      maxLength={MAX_HEALTH_DETAILS}
                      aria-invalid={invalid(`health.${text}`)}
                      value={draft.health[text]}
                      onChange={(e) => setHealth({ [text]: e.target.value })}
                    />
                  </Field>
                )}
              </div>
            ))}
          </div>
        </section>

        {/* ------------------------------------------------ emergency contact */}
        <section className="space-y-4">
          <h2 className="text-base font-semibold">Emergency contact</h2>
          <div className="grid gap-4 rounded-lg border p-4 sm:grid-cols-2">
            <Field id="e-name" label="Name" required error={errors["emergency.name"]}>
              <Input
                id="e-name"
                maxLength={255}
                aria-invalid={invalid("emergency.name")}
                value={draft.emergency.name}
                onChange={(e) => setEmergency({ name: e.target.value })}
              />
            </Field>
            <Field
              id="e-rel"
              label="Relationship to child"
              required
              error={errors["emergency.relationship"]}
            >
              <Input
                id="e-rel"
                maxLength={100}
                aria-invalid={invalid("emergency.relationship")}
                value={draft.emergency.relationship}
                onChange={(e) => setEmergency({ relationship: e.target.value })}
              />
            </Field>
            <Field
              id="e-phone"
              label="Contact number"
              required
              error={errors["emergency.phone"]}
              hint={PHONE_HINT}
            >
              {phoneInput("e-phone", "emergency.phone", draft.emergency.phone, (v) =>
                setEmergency({ phone: v }),
              )}
            </Field>
          </div>
        </section>

        {/* ------------------------------------------------ documents */}
        <section className="space-y-4">
          <h2 className="text-base font-semibold">Documents</h2>
          <p className="text-sm text-muted-foreground">
            PDF, JPG or PNG, 10 MB or less each. The proof of payment of the application fee is
            required for every application
            {docTypes.length > 1 ? ", and this grade also needs the documents below" : ""}.
          </p>
          {errors.documents && (
            <p role="alert" className="text-sm text-destructive">
              {errors.documents}
            </p>
          )}
          {!sessionToken ? (
            <div className="space-y-2 rounded-lg border p-4">
              <p className="text-sm">Complete this security check to upload your documents.</p>
              {verifyUnavailable ? (
                <p className="text-sm text-destructive">
                  The security check couldn't load. {APPLICATION_OFFICE_MESSAGE}
                </p>
              ) : (
                <TurnstileWidget
                  siteKey={SITE_KEY}
                  action="upload"
                  resetKey={uploadResetKey}
                  onToken={(t) => void startUploads(t)}
                  onUnavailable={() => setVerifyUnavailable(true)}
                />
              )}
              {opening && <p className="text-sm text-muted-foreground">Preparing uploads…</p>}
            </div>
          ) : (
            <div className="space-y-3 rounded-lg border p-4">
              {docTypes.map((type) => {
                const key = `documents.${type}`;
                const done = uploads[type];
                return (
                  <Field
                    key={type}
                    id={`d-${type}`}
                    label={PUBLIC_DOCUMENT_LABELS[type] ?? type}
                    required
                    error={errors[key]}
                    hint={
                      uploading === type
                        ? "Uploading…"
                        : done
                          ? `Uploaded: ${done.fileName}. Choose another file to replace it.`
                          : type === FEE_PROOF
                            ? "A photo or scan of the slip, confirmation or receipt."
                            : null
                    }
                  >
                    <Input
                      id={`d-${type}`}
                      type="file"
                      accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png"
                      disabled={uploading !== null}
                      aria-invalid={invalid(key)}
                      onChange={(e) => {
                        void chooseFile(type, e.target.files?.[0]);
                        e.target.value = "";
                      }}
                    />
                  </Field>
                );
              })}
            </div>
          )}
        </section>

        {/* ------------------------------------------------ declaration */}
        <section className="space-y-4">
          <h2 className="text-base font-semibold">Declaration</h2>
          <div className="space-y-4 rounded-lg border p-4">
            <div className="flex items-start gap-2">
              <Checkbox
                id="agreed"
                checked={draft.agreed}
                aria-invalid={invalid("agreed")}
                onCheckedChange={(v) => {
                  clearError("agreed");
                  setDraft((d) => ({ ...d, agreed: v === true }));
                }}
              />
              <Label htmlFor="agreed" className="font-normal leading-snug">
                I confirm that the information in this application is true and complete.
              </Label>
            </div>
            {errors.agreed && <p className="text-xs text-destructive">{errors.agreed}</p>}
            <Field
              id="signature"
              label="Your full name, as your signature"
              required
              error={errors.signature}
            >
              <Input
                id="signature"
                maxLength={255}
                aria-invalid={invalid("signature")}
                value={draft.signature}
                onChange={(e) => {
                  clearError("signature");
                  setDraft((d) => ({ ...d, signature: e.target.value }));
                }}
              />
            </Field>
          </div>
        </section>

        {/* ------------------------------------------------ submit */}
        <section className="space-y-4">
          {sessionToken && !verifyUnavailable && (
            <TurnstileWidget
              siteKey={SITE_KEY}
              action="application"
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
          <Button type="submit" disabled={busy || uploading !== null || verifyUnavailable}>
            {busy ? "Sending…" : "Submit application"}
          </Button>
        </section>
      </form>
    </div>
  );
}
