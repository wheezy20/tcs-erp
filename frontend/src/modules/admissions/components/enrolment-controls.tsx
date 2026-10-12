import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { StaffRole } from "@/data/auth-store";
import {
  listDocuments,
  type ApplicationDocument,
  type ApplicationSummary,
} from "@/modules/admissions/data/application-detail";
import {
  correctApplicationGrade,
  markEnrolled,
  type EnrolmentResult,
} from "@/modules/admissions/data/mutations";
import { listGrades } from "@/modules/admissions/data/reference";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  DOCUMENT_STATUS_LABELS,
  DOCUMENT_TYPE_LABELS,
  type DocumentStatus,
} from "@/modules/admissions/labels";
import {
  canCorrectGrade,
  documentsNotApproved,
  enrolState,
  type OfferState,
} from "@/modules/admissions/permissions";
import { getErrorMessage } from "@/lib/utils";

/** Mark enrolled and grade correction, both Manager only. */
export function EnrolmentControls({
  app,
  role,
  decisionType,
  offer,
  onDone,
}: {
  app: ApplicationSummary;
  role: StaffRole | undefined;
  decisionType: string | null;
  offer: OfferState;
  onDone: () => Promise<void>;
}) {
  const state = enrolState(role, app.stage, decisionType, offer, app.gradeBand);
  const correctable = canCorrectGrade(role, app.stage, app.gradeBand);
  if (state === "hidden" && !correctable) return null;

  return (
    <div className="mt-6 border-t pt-4">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        Enrolment
      </h3>
      {app.gradeBand === null && (
        <p className="mt-3 rounded-md border border-amber-400/50 bg-amber-50 px-3 py-2 text-sm dark:bg-amber-950/30">
          The grade applied for, "{app.gradeAsEntered}", isn't one the school issues student IDs for
          (for example Grade 10 to 12, an old grade, or free text). Enrolment will be refused until
          the grade is corrected.
        </p>
      )}
      <div className="mt-3 flex flex-wrap gap-2">
        {state !== "hidden" && (
          <EnrolDialog
            applicationId={app.id}
            disabled={state === "blocked_by_grade"}
            onDone={onDone}
          />
        )}
        {correctable && <GradeCorrectionDialog app={app} onDone={onDone} />}
      </div>
    </div>
  );
}

function EnrolDialog({
  applicationId,
  disabled,
  onDone,
}: {
  applicationId: string;
  disabled: boolean;
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [result, setResult] = useState<EnrolmentResult | null>(null);

  async function enrol() {
    setSaving(true);
    try {
      const res = await markEnrolled(applicationId);
      setResult(res);
      toast.success("Enrolled");
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not enrol this application."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) setResult(null);
      }}
    >
      <Button onClick={() => setOpen(true)} disabled={disabled}>
        Mark enrolled
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Mark enrolled</DialogTitle>
          <DialogDescription>
            Enrolment gives the applicant a permanent student ID if they don't already have one. It
            can't be undone.
          </DialogDescription>
        </DialogHeader>
        {result ? (
          <p className="rounded-md border px-3 py-2 text-sm">
            {result.studentIdAssigned ? "Student ID assigned: " : "Existing student ID kept: "}
            <span className="font-mono font-semibold">{result.studentId ?? "none"}</span>
          </p>
        ) : (
          open && <DocumentWarning applicationId={applicationId} />
        )}
        <DialogFooter>
          {result ? (
            <Button onClick={() => setOpen(false)}>Done</Button>
          ) : (
            <>
              <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
                Cancel
              </Button>
              <Button onClick={enrol} disabled={saving}>
                {saving ? "Enrolling…" : "Mark enrolled"}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Lists every document that isn't approved. A warning, not a block. */
function DocumentWarning({ applicationId }: { applicationId: string }) {
  const docs = useLoad(
    () => listDocuments(applicationId),
    [applicationId],
    "Could not check the documents.",
  );
  if (docs.error) return <p className="text-sm text-destructive">{docs.error}</p>;
  if (!docs.data) return <p className="text-sm text-muted-foreground">Checking documents…</p>;
  const pending: ApplicationDocument[] = documentsNotApproved(docs.data);
  if (pending.length === 0) return null;
  return (
    <div className="rounded-md border border-amber-400/50 bg-amber-50 px-3 py-2 text-sm dark:bg-amber-950/30">
      <p className="font-medium">Some documents aren't approved yet:</p>
      <ul className="mt-1 list-disc pl-5">
        {pending.map((d) => (
          <li key={d.id}>
            {DOCUMENT_TYPE_LABELS[d.documentType] ?? d.documentType}:{" "}
            {DOCUMENT_STATUS_LABELS[d.status as DocumentStatus] ?? d.status}
          </li>
        ))}
      </ul>
      <p className="mt-1 text-muted-foreground">You can still enrol.</p>
    </div>
  );
}

function GradeCorrectionDialog({
  app,
  onDone,
}: {
  app: ApplicationSummary;
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [gradeId, setGradeId] = useState("");
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!gradeId) return;
    setSaving(true);
    try {
      await correctApplicationGrade(app.id, gradeId);
      toast.success("Grade corrected");
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not correct the grade."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        setOpen(o);
        if (o) setGradeId("");
      }}
    >
      <Button variant="outline" onClick={() => setOpen(true)}>
        Correct grade
      </Button>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Correct grade</DialogTitle>
          <DialogDescription>
            Replaces "{app.gradeAsEntered}" with a grade from the school's list. The campus must
            accept the new grade. The change is recorded in the audit log.
          </DialogDescription>
        </DialogHeader>
        {open && <GradePicker value={gradeId} onChange={setGradeId} />}
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={saving || !gradeId}>
            {saving ? "Saving…" : "Correct grade"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function GradePicker({ value, onChange }: { value: string; onChange: (id: string) => void }) {
  const grades = useLoad(listGrades, [], "Could not load grades.");
  if (grades.error) return <p className="text-sm text-destructive">{grades.error}</p>;
  if (!grades.data) return <p className="text-sm text-muted-foreground">Loading grades…</p>;
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger aria-label="New grade">
        <SelectValue placeholder="Choose a grade" />
      </SelectTrigger>
      <SelectContent>
        {grades.data.map((g) => (
          <SelectItem key={g.id} value={g.id}>
            {g.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
