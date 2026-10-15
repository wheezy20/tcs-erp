import { useState } from "react";

import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/page-header";
import {
  getApplicationDeclaration,
  getApplicationSummary,
  getStudentAndFamily,
  listEmergencyContacts,
  type ApplicationSummary,
} from "@/modules/admissions/data/application-detail";
import {
  ApplicationNotFound,
  BackToApplications,
} from "@/modules/admissions/components/application-not-found";
import { DecisionOfferPanel } from "@/modules/admissions/components/decision-offer-panel";
import { DocumentsPanel } from "@/modules/admissions/components/documents-panel";
import { HealthPanel } from "@/modules/admissions/components/health-panel";
import { NotesPanel } from "@/modules/admissions/components/notes-panel";
import { SubmissionCheckPanel } from "@/modules/admissions/components/submission-check-panel";
import { GradeCell, StageBadge } from "@/modules/admissions/components/stage-badge";
import { StageControls } from "@/modules/admissions/components/stage-controls";
import { useAdmissionsAccess } from "@/modules/admissions/hooks/use-admissions-access";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import { GENDER_LABELS, REFERRAL_LABELS, RELATIONSHIP_LABELS } from "@/modules/admissions/labels";
import { isAdmissionsReadOnly, isApplicationId } from "@/modules/admissions/permissions";

const dateOnly = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });
const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

export function ApplicationDetailPage({ applicationId }: { applicationId: string }) {
  // A malformed id never reaches the database, so it can't produce a
  // different page from an unknown or out-of-scope one.
  if (!isApplicationId(applicationId)) return <ApplicationNotFound />;
  return <ApplicationDetail key={applicationId} applicationId={applicationId} />;
}

function ApplicationDetail({ applicationId }: { applicationId: string }) {
  const { role, staffId } = useAdmissionsAccess();
  // Bumped after a decision, offer, enrolment or grade change, so the
  // Applicant card re-reads the student (a new student ID).
  const [version, setVersion] = useState(0);
  const summary = useLoad(
    () => getApplicationSummary(applicationId),
    [applicationId],
    "Could not load this application.",
  );

  if (summary.loading && !summary.data) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }
  if (summary.error && !summary.data) {
    return (
      <>
        <BackToApplications />
        <p className="py-16 text-center text-sm text-destructive">{summary.error}</p>
      </>
    );
  }
  // Nothing below mounts (and so nothing else is fetched) until the
  // application itself was found.
  if (!summary.data) return <ApplicationNotFound />;
  const app = summary.data;
  // A failed refresh after a stage change keeps the page and says so.
  const refreshError = summary.error;
  async function afterPipelineChange() {
    setVersion((v) => v + 1);
    await summary.reload();
  }

  return (
    <>
      <BackToApplications />
      <PageHeader
        title={app.studentName}
        description={
          [app.applicationReference, app.inquiryReference].filter(Boolean).join(" · ") ||
          "No reference yet"
        }
        actions={
          isAdmissionsReadOnly(role) ? (
            <Badge variant="outline">Read-only</Badge>
          ) : (
            <StageControls
              applicationId={app.id}
              stage={app.stage}
              role={role}
              onChanged={summary.reload}
            />
          )
        }
      />

      {refreshError && (
        <p className="mb-6 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
          {refreshError} The details below may be out of date; reload the page.
        </p>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <ApplicantAndFamily studentId={app.studentId} version={version} />
          <DecisionOfferPanel
            key={staffId ?? "none"}
            app={app}
            role={role}
            onChanged={afterPipelineChange}
          />
          <SubmissionCheckPanel applicationId={app.id} />
          <NotesPanel applicationId={app.id} role={role} staffId={staffId} />
          <DocumentsPanel applicationId={app.id} role={role} />
        </div>
        <div className="space-y-6">
          <ApplicationCard app={app} />
          <HealthPanel applicationId={app.id} />
          <EmergencyContacts applicationId={app.id} />
          <Declaration applicationId={app.id} />
        </div>
      </div>
    </>
  );
}

/* ---------------------------------------------------------------- panels */

function ApplicationCard({ app }: { app: ApplicationSummary }) {
  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Application</h2>
      <dl className="mt-4 grid grid-cols-2 gap-4">
        <div className="col-span-2">
          <dt className="text-xs uppercase tracking-wide text-muted-foreground">Stage</dt>
          <dd className="mt-1">
            <StageBadge stage={app.stage} />
          </dd>
        </div>
        <div>
          <dt className="text-xs uppercase tracking-wide text-muted-foreground">Grade</dt>
          <dd className="mt-1 text-sm font-medium">
            <GradeCell gradeAsEntered={app.gradeAsEntered} gradeName={app.gradeName} />
          </dd>
        </div>
        <Field label="Campus" value={app.branchName ?? "Not chosen"} />
        <Field label="Academic year" value={app.academicYear} />
        <Field label="Start month" value={app.monthOfEnrollment || "Not given"} />
        <Field label="Received" value={dateOnly.format(new Date(app.createdAt))} />
        <Field label="Last updated" value={dateOnly.format(new Date(app.updatedAt))} />
      </dl>
    </section>
  );
}

function ApplicantAndFamily({ studentId, version }: { studentId: string; version: number }) {
  const res = useLoad(
    () => getStudentAndFamily(studentId),
    [studentId, version],
    "Could not load the applicant.",
  );
  if (res.error) return <ErrorCard title="Applicant" message={res.error} />;
  if (!res.data) return <LoadingCard title="Applicant" />;
  const { student: s, family } = res.data;

  return (
    <>
      <section className="card-surface p-6">
        <h2 className="text-sm font-semibold">Applicant</h2>
        <dl className="mt-4 grid gap-4 sm:grid-cols-2">
          <Field label="Full name" value={s.fullName} />
          <Field
            label="Date of birth"
            value={s.dateOfBirth ? dateOnly.format(new Date(`${s.dateOfBirth}T00:00:00`)) : ""}
          />
          <Field label="Gender" value={GENDER_LABELS[s.gender] ?? s.gender} />
          <Field label="Nationality" value={s.nationality} />
          <Field label="Current school" value={s.currentSchool} />
          <Field label="Current grade" value={s.currentGrade} />
          <Field label="Previous school location" value={s.previousSchoolLocation} />
          <Field label="Student ID" value={s.studentNumber ?? "Assigned at enrolment"} />
          <Field
            label="Address"
            value={[s.address, s.townCity, s.postalCode, s.country].filter(Boolean).join(", ")}
          />
        </dl>
      </section>

      <section className="card-surface p-6">
        <h2 className="text-sm font-semibold">Family</h2>
        {family ? (
          <>
            <dl className="mt-4 grid gap-4 sm:grid-cols-2">
              <Field
                label="Heard about us"
                value={
                  family.referralSource === "other" && family.referralSourceOther
                    ? `Other: ${family.referralSourceOther}`
                    : (REFERRAL_LABELS[family.referralSource] ?? family.referralSource)
                }
              />
              <Field label="Comments" value={family.comments} />
            </dl>
            <h3 className="mt-6 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              Parents and guardians
            </h3>
            {family.guardians.length === 0 ? (
              <p className="mt-2 text-sm text-muted-foreground">None recorded.</p>
            ) : (
              <div className="mt-2 divide-y rounded-md border">
                {family.guardians.map((g) => (
                  <div key={g.id} className="grid gap-1 px-3 py-2 text-sm sm:grid-cols-3">
                    <div>
                      <p className="font-medium">
                        {[g.firstName, g.surname].filter(Boolean).join(" ") || "No name"}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {RELATIONSHIP_LABELS[g.relationship] ?? g.relationship}
                        {g.religion ? ` · ${g.religion}` : ""}
                      </p>
                    </div>
                    <div className="text-muted-foreground">
                      <p className="truncate">{g.email}</p>
                      <p className="tabular-nums">{g.phone}</p>
                    </div>
                    <p className="text-muted-foreground">
                      {[g.address, g.townCity].filter(Boolean).join(", ") || "No address"}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </>
        ) : (
          <p className="mt-2 text-sm text-muted-foreground">No family record.</p>
        )}
      </section>
    </>
  );
}

function EmergencyContacts({ applicationId }: { applicationId: string }) {
  const res = useLoad(
    () => listEmergencyContacts(applicationId),
    [applicationId],
    "Could not load emergency contacts.",
  );
  if (res.error) return <ErrorCard title="Emergency contacts" message={res.error} />;
  if (!res.data) return <LoadingCard title="Emergency contacts" />;
  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Emergency contacts</h2>
      {res.data.length === 0 ? (
        <p className="mt-3 text-sm text-muted-foreground">None recorded.</p>
      ) : (
        <ul className="mt-3 space-y-2 text-sm">
          {res.data.map((c) => (
            <li key={c.id}>
              <p className="font-medium">{c.name}</p>
              <p className="text-xs text-muted-foreground">
                {c.relationship} · <span className="tabular-nums">{c.phone}</span>
              </p>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function Declaration({ applicationId }: { applicationId: string }) {
  const res = useLoad(
    () => getApplicationDeclaration(applicationId),
    [applicationId],
    "Could not load the declaration.",
  );
  if (res.error) return <ErrorCard title="Declaration and consent" message={res.error} />;
  if (!res.data) return <LoadingCard title="Declaration and consent" />;
  const d = res.data;
  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">Declaration and consent</h2>
      <dl className="mt-4 grid gap-4">
        <Field
          label="Declaration"
          value={
            d.declarationAgreed
              ? `Agreed${d.declarationSignatureName ? ` by ${d.declarationSignatureName}` : ""}${
                  d.declarationAgreedAt
                    ? `, ${dateTime.format(new Date(d.declarationAgreedAt))}`
                    : ""
                }`
              : "Not agreed"
          }
        />
        <Field label="Media consent" value={d.mediaConsentAgreed ? "Given" : "Not given"} />
        <Field
          label="Scholarship information"
          value={
            d.wantsScholarshipInfo ? d.scholarshipInterestDetails || "Requested" : "Not requested"
          }
        />
      </dl>
    </section>
  );
}

/* --------------------------------------------------------------- helpers */

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-1 whitespace-pre-wrap text-sm font-medium">{value || "Not given"}</dd>
    </div>
  );
}

function LoadingCard({ title }: { title: string }) {
  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">{title}</h2>
      <p className="mt-3 text-sm text-muted-foreground">Loading…</p>
    </section>
  );
}

function ErrorCard({ title, message }: { title: string; message: string }) {
  return (
    <section className="card-surface p-6">
      <h2 className="text-sm font-semibold">{title}</h2>
      <p className="mt-3 text-sm text-destructive">{message}</p>
    </section>
  );
}
