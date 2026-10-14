import { useState, type FormEvent, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { TurnstileWidget } from "@/modules/admissions/components/turnstile-widget";
import { getPublicAdmissionsOptions, submitInquiry } from "@/modules/admissions/data/public-intake";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  MAX_GUARDIANS,
  MAX_STUDENTS,
  MONTH_OPTIONS,
  OFFICE_MESSAGE,
  OTHER,
  REFERRAL_OPTIONS,
  RELATIONSHIP_OPTIONS,
  buildInquiryPayload,
  emptyDraft,
  emptyGuardian,
  emptyStudent,
  formAvailable,
  gradesForCampus,
  todayInAccra,
  validateInquiry,
  withCampus,
  type FieldErrors,
  type GuardianDraft,
  type InquiryDraft,
  type PublicOptions,
  type StudentDraft,
} from "@/modules/admissions/inquiry-form";

// /inquiry: the public Inquiry form (admissions slice 8). No sign-in and no
// AppShell (__root.tsx lists it as auth-free). The page offers only what
// get_public_admissions_options returns; every rule is enforced again by
// the Edge Function and submit_inquiry.

const NO_CAMPUS = "__none__";
const SITE_KEY = (import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined) ?? "";

export function InquiryPage() {
  const options = useLoad(getPublicAdmissionsOptions, [], "Could not load the form.");
  const [closedAfterSubmit, setClosedAfterSubmit] = useState(false);
  const [references, setReferences] = useState<string[] | null>(null);

  if (options.loading && !options.data) {
    return <Shell>Loading…</Shell>;
  }
  if (options.error || !options.data) {
    return (
      <Notice title="The inquiry form couldn't load">
        Please try again later, or call the school office to make an inquiry.
      </Notice>
    );
  }
  if (references) {
    return (
      <Notice title="Thank you, we've received your inquiry">
        <span className="block">
          Your reference{references.length > 1 ? "s" : ""}:{" "}
          <span className="font-medium text-foreground">{references.join(", ")}</span>
        </span>
        <span className="mt-2 block">Our admissions team will be in touch.</span>
      </Notice>
    );
  }
  if (closedAfterSubmit || !formAvailable(options.data)) {
    return (
      <Notice title="Online inquiries are closed">
        We're not taking inquiries online at the moment. Please call the school office to make an
        inquiry.
      </Notice>
    );
  }
  if (SITE_KEY === "") {
    return <Notice title="The inquiry form isn't available">{OFFICE_MESSAGE}</Notice>;
  }
  return (
    <InquiryForm
      options={options.data}
      onCreated={setReferences}
      onClosed={() => setClosedAfterSubmit(true)}
    />
  );
}

function Shell({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto max-w-xl px-4 py-16 text-center text-sm text-muted-foreground">
      {children}
    </div>
  );
}

function Notice({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="mx-auto max-w-xl px-4 py-16 text-center">
      <img src="/tcs-logomark.png" alt="" className="mx-auto mb-6 h-12 w-12" />
      <h1 className="text-lg font-semibold">{title}</h1>
      <p className="mt-2 text-sm text-muted-foreground">{children}</p>
    </div>
  );
}

function Field({
  id,
  label,
  error,
  children,
}: {
  id: string;
  label: string;
  error?: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{label}</Label>
      {children}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}

function Choice({
  id,
  value,
  onChange,
  placeholder,
  items,
}: {
  id: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  items: { value: string; label: string }[];
}) {
  return (
    <Select value={value === "" ? undefined : value} onValueChange={onChange}>
      <SelectTrigger id={id}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {items.map((i) => (
          <SelectItem key={i.value} value={i.value}>
            {i.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
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

  const setGuardian = (i: number, patch: Partial<GuardianDraft>) =>
    setDraft((d) => ({
      ...d,
      guardians: d.guardians.map((g, j) => (j === i ? { ...g, ...patch } : g)),
    }));
  const setStudent = (i: number, next: (s: StudentDraft) => StudentDraft) =>
    setDraft((d) => ({ ...d, students: d.students.map((s, j) => (j === i ? next(s) : s)) }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setFormError(null);
    const found = validateInquiry(draft, options, todayInAccra());
    setErrors(found);
    if (Object.keys(found).length > 0) {
      setFormError("Please check the highlighted fields.");
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
      else setFormError(outcome.message);
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

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <img src="/tcs-logomark.png" alt="" className="mb-4 h-12 w-12" />
      <h1 className="text-xl font-semibold">Admissions inquiry</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Tell us about your family and the children you're enquiring for. Fields are required unless
        marked optional.
      </p>

      <form onSubmit={submit} className="mt-8 space-y-10" noValidate>
        {/* ------------------------------------------------ guardians */}
        <section className="space-y-6">
          <h2 className="text-base font-semibold">Parents or guardians</h2>
          {draft.guardians.map((g, i) => {
            const k = (f: string) => `guardians.${i}.${f}`;
            const id = (f: string) => `g${i}-${f}`;
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
                          guardians: d.guardians.filter((_, j) => j !== i),
                        }))
                      }
                    >
                      Remove
                    </Button>
                  )}
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field id={id("surname")} label="Surname" error={errors[k("surname")]}>
                    <Input
                      id={id("surname")}
                      maxLength={255}
                      value={g.surname}
                      onChange={(e) => setGuardian(i, { surname: e.target.value })}
                    />
                  </Field>
                  <Field id={id("first")} label="First name(s)" error={errors[k("firstName")]}>
                    <Input
                      id={id("first")}
                      maxLength={255}
                      value={g.firstName}
                      onChange={(e) => setGuardian(i, { firstName: e.target.value })}
                    />
                  </Field>
                  <Field
                    id={id("relationship")}
                    label="Relationship to child"
                    error={errors[k("relationship")]}
                  >
                    <Choice
                      id={id("relationship")}
                      value={g.relationship}
                      onChange={(v) => setGuardian(i, { relationship: v })}
                      placeholder="Select one"
                      items={[...RELATIONSHIP_OPTIONS]}
                    />
                  </Field>
                  <Field id={id("religion")} label="Religion" error={errors[k("religion")]}>
                    <Input
                      id={id("religion")}
                      maxLength={255}
                      value={g.religion}
                      onChange={(e) => setGuardian(i, { religion: e.target.value })}
                    />
                  </Field>
                  <Field id={id("address")} label="Address" error={errors[k("address")]}>
                    <Input
                      id={id("address")}
                      maxLength={255}
                      value={g.address}
                      onChange={(e) => setGuardian(i, { address: e.target.value })}
                    />
                  </Field>
                  <Field id={id("town")} label="Town or city" error={errors[k("townCity")]}>
                    <Input
                      id={id("town")}
                      maxLength={255}
                      value={g.townCity}
                      onChange={(e) => setGuardian(i, { townCity: e.target.value })}
                    />
                  </Field>
                  <Field id={id("phone")} label="Contact number" error={errors[k("phone")]}>
                    <Input
                      id={id("phone")}
                      inputMode="tel"
                      placeholder="+233551794822"
                      maxLength={32}
                      value={g.phone}
                      onChange={(e) => setGuardian(i, { phone: e.target.value })}
                    />
                  </Field>
                  <Field id={id("email")} label="Email address" error={errors[k("email")]}>
                    <Input
                      id={id("email")}
                      type="email"
                      maxLength={254}
                      value={g.email}
                      onChange={(e) => setGuardian(i, { email: e.target.value })}
                    />
                  </Field>
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
                  <Field id={id("name")} label="Full name" error={errors[k("fullName")]}>
                    <Input
                      id={id("name")}
                      maxLength={255}
                      value={s.fullName}
                      onChange={(e) => setStudent(i, (x) => ({ ...x, fullName: e.target.value }))}
                    />
                  </Field>
                  <Field id={id("dob")} label="Date of birth" error={errors[k("dateOfBirth")]}>
                    <Input
                      id={id("dob")}
                      type="date"
                      max={todayInAccra()}
                      value={s.dateOfBirth}
                      onChange={(e) =>
                        setStudent(i, (x) => ({ ...x, dateOfBirth: e.target.value }))
                      }
                    />
                  </Field>
                  <Field
                    id={id("school")}
                    label="Current school"
                    error={errors[k("currentSchool")]}
                  >
                    <Input
                      id={id("school")}
                      maxLength={255}
                      placeholder="N/A if not yet in school"
                      value={s.currentSchool}
                      onChange={(e) =>
                        setStudent(i, (x) => ({ ...x, currentSchool: e.target.value }))
                      }
                    />
                  </Field>
                  <Field
                    id={id("current")}
                    label="Current grade or class"
                    error={errors[k("currentGrade")]}
                  >
                    <Input
                      id={id("current")}
                      maxLength={50}
                      value={s.currentGrade}
                      onChange={(e) =>
                        setStudent(i, (x) => ({ ...x, currentGrade: e.target.value }))
                      }
                    />
                  </Field>
                  <Field
                    id={id("campus")}
                    label="Preferred campus (optional)"
                    error={errors[k("campusId")]}
                  >
                    <Choice
                      id={id("campus")}
                      value={s.campusId === "" ? NO_CAMPUS : s.campusId}
                      onChange={(v) =>
                        setStudent(i, (x) => withCampus(x, v === NO_CAMPUS ? "" : v, options))
                      }
                      placeholder="No preference"
                      items={campusItems}
                    />
                  </Field>
                  <Field
                    id={id("grade")}
                    label="Grade seeking admission into"
                    error={errors[k("gradeId")]}
                  >
                    <Choice
                      id={id("grade")}
                      value={s.gradeId}
                      onChange={(v) => setStudent(i, (x) => ({ ...x, gradeId: v }))}
                      placeholder="Select one"
                      items={grades.map((g) => ({ value: g.id, label: g.name }))}
                    />
                    <p className="text-xs text-muted-foreground">
                      {campusName ? `Showing the grades ${campusName} takes. ` : ""}
                      Grade not listed? Please contact the school.
                    </p>
                  </Field>
                  <Field id={id("year")} label="Academic year" error={errors[k("academicYear")]}>
                    <Choice
                      id={id("year")}
                      value={s.academicYear}
                      onChange={(v) => setStudent(i, (x) => ({ ...x, academicYear: v }))}
                      placeholder="Select one"
                      items={options.academicYears.map((y) => ({ value: y, label: y }))}
                    />
                  </Field>
                  <Field
                    id={id("month")}
                    label="Month of enrolment"
                    error={errors[k("month")] ?? errors[k("monthOther")]}
                  >
                    <Choice
                      id={id("month")}
                      value={s.month}
                      onChange={(v) => setStudent(i, (x) => ({ ...x, month: v }))}
                      placeholder="Select one"
                      items={[
                        ...MONTH_OPTIONS.map((m) => ({ value: m, label: m })),
                        { value: OTHER, label: "Other" },
                      ]}
                    />
                    {s.month === OTHER && (
                      <Input
                        aria-label="Month of enrolment (other)"
                        placeholder="Please specify"
                        maxLength={50}
                        value={s.monthOther}
                        onChange={(e) =>
                          setStudent(i, (x) => ({ ...x, monthOther: e.target.value }))
                        }
                      />
                    )}
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
          <h2 className="text-base font-semibold">About your inquiry</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field id="referral" label="How did you hear about us?" error={errors.referralSource}>
              <Choice
                id="referral"
                value={draft.referralSource}
                onChange={(v) => setDraft((d) => ({ ...d, referralSource: v }))}
                placeholder="Select one"
                items={[...REFERRAL_OPTIONS]}
              />
            </Field>
            {draft.referralSource === OTHER && (
              <Field id="referral-other" label="Please specify" error={errors.referralSourceOther}>
                <Input
                  id="referral-other"
                  maxLength={255}
                  value={draft.referralSourceOther}
                  onChange={(e) => setDraft((d) => ({ ...d, referralSourceOther: e.target.value }))}
                />
              </Field>
            )}
          </div>
          <Field id="comments" label="Comments or questions (optional)" error={errors.comments}>
            <Textarea
              id="comments"
              rows={4}
              maxLength={10000}
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
            {busy ? "Sending…" : "Send inquiry"}
          </Button>
        </section>
      </form>
    </div>
  );
}
