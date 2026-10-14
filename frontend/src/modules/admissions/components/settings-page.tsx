import { useState, type FormEvent } from "react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { getErrorMessage } from "@/lib/utils";
import { RoleBlockedPanel } from "@/modules/admissions/components/role-blocked-panel";
import {
  addAcademicYear,
  createCapacity,
  deleteCapacity,
  setAcademicYearActive,
  setOfferTtlDays,
  setPublicIntakeOpen,
  updateCapacity,
} from "@/modules/admissions/data/mutations";
import {
  listAcademicYears,
  listCampuses,
  type AcademicYear,
  type Campus,
} from "@/modules/admissions/data/reference";
import {
  getOfferTtlDays,
  getPublicIntakeOpen,
  listAllGrades,
  listCampusGradeRules,
  listCapacity,
  type CapacityRow,
  type SettingsGrade,
} from "@/modules/admissions/data/settings";
import { useAdmissionsAccess } from "@/modules/admissions/hooks/use-admissions-access";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  canEditAdmissionsSettings,
  canViewAdmissionsSettings,
} from "@/modules/admissions/permissions";
import {
  campusGradeSummary,
  capacityYearOptions,
  parseWholeNumber,
  yearStatus,
} from "@/modules/admissions/settings-rules";

const ALL_CAMPUSES = "__all__";
const NOT_A_NUMBER = "Enter a whole number.";

/** /admissions/settings. Manager writes; Auditor reads. Every other role
 * gets the blocked panel and the content (with its queries) never mounts. */
export function AdmissionsSettingsPage() {
  const { role } = useAdmissionsAccess();
  if (!canViewAdmissionsSettings(role)) {
    return (
      <RoleBlockedPanel
        title="Admissions settings"
        description="Public intake, academic years, capacity, offer expiry and campus grade rules."
        what="Admissions settings"
        openTo="Managers and Auditors"
      />
    );
  }
  return <SettingsContent canEdit={canEditAdmissionsSettings(role)} />;
}

function SettingsContent({ canEdit }: { canEdit: boolean }) {
  const years = useLoad(listAcademicYears, [], "Could not load academic years.");
  const campuses = useLoad(listCampuses, [], "Could not load campuses.");
  const grades = useLoad(listAllGrades, [], "Could not load grades.");

  return (
    <>
      <PageHeader
        title="Admissions settings"
        description="Public intake, academic years, capacity, offer expiry and campus grade rules."
        actions={canEdit ? undefined : <Badge variant="outline">Read-only</Badge>}
      />
      <div className="grid gap-6 lg:grid-cols-2">
        <div className="lg:col-span-2">
          <PublicIntakeSection canEdit={canEdit} />
        </div>
        <AcademicYearsSection canEdit={canEdit} years={years} />
        <OfferExpirySection canEdit={canEdit} />
        <div className="lg:col-span-2">
          <CapacitySection
            canEdit={canEdit}
            years={years.data ?? []}
            campuses={campuses.data ?? []}
            grades={grades.data ?? []}
            referenceError={years.error ?? campuses.error ?? grades.error}
          />
        </div>
        <div className="lg:col-span-2">
          <CampusRulesSection campuses={campuses.data ?? []} grades={grades.data ?? []} />
        </div>
      </div>
    </>
  );
}

function SectionMessage({ children, error }: { children: React.ReactNode; error?: boolean }) {
  return (
    <p
      className={
        error
          ? "px-6 py-8 text-center text-sm text-destructive"
          : "px-6 py-8 text-center text-sm text-muted-foreground"
      }
    >
      {children}
    </p>
  );
}

/* ---------------------------------------------------------------- public intake */

function PublicIntakeSection({ canEdit }: { canEdit: boolean }) {
  const intake = useLoad(getPublicIntakeOpen, [], "Could not load public intake.");
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const open = intake.data === true;

  async function change() {
    setBusy(true);
    try {
      await setPublicIntakeOpen(!open);
      toast.success(open ? "Public intake closed" : "Public intake opened");
      await intake.reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not change public intake."));
    } finally {
      setBusy(false);
      setConfirming(false);
    }
  }

  return (
    <section className="card-surface overflow-hidden">
      <div className="flex flex-wrap items-start justify-between gap-4 p-6">
        <div>
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-semibold">Public intake</h2>
            {intake.data === undefined && intake.loading ? null : intake.data === true ? (
              <Badge>Open</Badge>
            ) : intake.data === false ? (
              <Badge variant="outline">Closed</Badge>
            ) : (
              <Badge variant="outline">Not set</Badge>
            )}
          </div>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
            Whether parents can send the public Inquiry form at /inquiry. While closed, the form
            shows a closed page and every submission is refused. Keep it closed while the old
            admissions site is still taking inquiries.
          </p>
          {intake.error && <p className="mt-2 text-sm text-destructive">{intake.error}</p>}
        </div>
        {canEdit && typeof intake.data === "boolean" && (
          <Button
            variant={open ? "outline" : "default"}
            disabled={busy}
            onClick={() => setConfirming(true)}
          >
            {open ? "Close public intake" : "Open public intake"}
          </Button>
        )}
      </div>
      <AlertDialog open={confirming} onOpenChange={(o) => !busy && setConfirming(o)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {open ? "Close public intake?" : "Open public intake?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {open
                ? "The Inquiry form will show a closed page and refuse new submissions straight away."
                : "Anyone with the link will be able to send an inquiry. Make sure the old admissions site is no longer taking inquiries, so there is only one intake."}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={busy}
              onClick={(e) => {
                e.preventDefault();
                void change();
              }}
            >
              {open ? "Close intake" : "Open intake"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </section>
  );
}

/* ---------------------------------------------------------------- academic years */

function AcademicYearsSection({
  canEdit,
  years,
}: {
  canEdit: boolean;
  years: ReturnType<typeof useLoad<AcademicYear[]>>;
}) {
  const [label, setLabel] = useState("");
  const [busy, setBusy] = useState(false);

  async function add(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await addAcademicYear(label);
      toast.success(`${label.trim()} added`);
      setLabel("");
      await years.reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not add the academic year."));
    } finally {
      setBusy(false);
    }
  }

  async function toggle(year: AcademicYear) {
    setBusy(true);
    try {
      await setAcademicYearActive(year.label, !year.isActive);
      toast.success(`${year.label} ${year.isActive ? "retired" : "reactivated"}`);
      await years.reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not change the academic year."));
    } finally {
      setBusy(false);
    }
  }

  const rows = years.data ?? [];
  return (
    <section className="card-surface overflow-hidden">
      <div className="border-b p-6">
        <h2 className="text-sm font-semibold">Academic years</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          The years staff can pick. A retired year stays on the list for existing records but can't
          get a new capacity figure.
        </p>
      </div>
      {years.error && <SectionMessage error>{years.error}</SectionMessage>}
      {!years.data && years.loading ? (
        <SectionMessage>Loading…</SectionMessage>
      ) : rows.length === 0 ? (
        <SectionMessage>No academic years yet.</SectionMessage>
      ) : (
        <ul className="divide-y">
          {rows.map((y) => (
            <li key={y.label} className="flex items-center justify-between gap-3 px-6 py-3">
              <div className="flex items-center gap-3">
                <span className="text-sm font-medium tabular-nums">{y.label}</span>
                {y.isActive ? (
                  <Badge variant="secondary">Active</Badge>
                ) : (
                  <Badge variant="outline">Retired</Badge>
                )}
              </div>
              {canEdit && (
                <Button size="sm" variant="outline" disabled={busy} onClick={() => toggle(y)}>
                  {y.isActive ? "Retire" : "Reactivate"}
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
      {canEdit && (
        <form onSubmit={add} className="flex flex-wrap items-end gap-3 border-t p-6">
          <div className="grid gap-1.5">
            <Label htmlFor="new-academic-year">Add a year</Label>
            <Input
              id="new-academic-year"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="2028/2029"
              maxLength={20}
              className="w-40"
            />
          </div>
          <Button type="submit" disabled={busy || label.trim() === ""}>
            Add
          </Button>
        </form>
      )}
    </section>
  );
}

/* ---------------------------------------------------------------- offer expiry */

function OfferExpirySection({ canEdit }: { canEdit: boolean }) {
  const ttl = useLoad(getOfferTtlDays, [], "Could not load the offer expiry.");
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);

  async function save(e: FormEvent) {
    e.preventDefault();
    const days = parseWholeNumber(draft);
    if (days === null) {
      toast.error(NOT_A_NUMBER);
      return;
    }
    setBusy(true);
    try {
      await setOfferTtlDays(days);
      toast.success("Offer expiry saved");
      setDraft("");
      await ttl.reload();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not save the offer expiry."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card-surface overflow-hidden">
      <div className="border-b p-6">
        <h2 className="text-sm font-semibold">Offer expiry</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          How long a parent has to answer an offer. It applies to offers generated or reset from now
          on.
        </p>
      </div>
      <div className="p-6">
        {ttl.error && <p className="mb-3 text-sm text-destructive">{ttl.error}</p>}
        <p className="text-xs uppercase tracking-wide text-muted-foreground">Current</p>
        <p className="mt-1 text-2xl font-semibold tabular-nums">
          {ttl.data === undefined && ttl.loading
            ? "…"
            : ttl.data === null || ttl.data === undefined
              ? "Not set"
              : `${ttl.data} ${ttl.data === 1 ? "day" : "days"}`}
        </p>
      </div>
      {canEdit && (
        <form onSubmit={save} className="flex flex-wrap items-end gap-3 border-t p-6">
          <div className="grid gap-1.5">
            <Label htmlFor="offer-ttl-days">New expiry in days (1 to 90)</Label>
            <Input
              id="offer-ttl-days"
              inputMode="numeric"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              maxLength={3}
              className="w-28"
            />
          </div>
          <Button type="submit" disabled={busy || draft.trim() === ""}>
            Save
          </Button>
        </form>
      )}
    </section>
  );
}

/* ---------------------------------------------------------------- capacity */

function CapacitySection({
  canEdit,
  years,
  campuses,
  grades,
  referenceError,
}: {
  canEdit: boolean;
  years: AcademicYear[];
  campuses: Campus[];
  grades: SettingsGrade[];
  referenceError: string | null;
}) {
  const capacity = useLoad(listCapacity, [], "Could not load capacity.");
  const gradeName = new Map(grades.map((g) => [g.id, g.name]));
  const gradePosition = new Map(grades.map((g) => [g.id, g.position]));
  const campusName = new Map(campuses.map((c) => [c.id, c.name]));
  const rows = [...(capacity.data ?? [])].sort(
    (a, b) =>
      a.academicYear.localeCompare(b.academicYear) ||
      (gradePosition.get(a.gradeId) ?? 0) - (gradePosition.get(b.gradeId) ?? 0) ||
      (campusName.get(a.branchId ?? "") ?? "").localeCompare(
        campusName.get(b.branchId ?? "") ?? "",
      ),
  );

  return (
    <section className="card-surface overflow-hidden">
      <div className="flex flex-wrap items-start justify-between gap-3 border-b p-6">
        <div>
          <h2 className="text-sm font-semibold">Capacity</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Planned places per year, grade and campus. Accepting past it shows a warning; it never
            blocks a decision.
          </p>
        </div>
        {canEdit && (
          <CreateCapacityDialog
            years={years}
            campuses={campuses}
            grades={grades}
            onDone={capacity.reload}
          />
        )}
      </div>
      {(capacity.error || referenceError) && (
        <SectionMessage error>{capacity.error ?? referenceError}</SectionMessage>
      )}
      {!capacity.data && capacity.loading ? (
        <SectionMessage>Loading…</SectionMessage>
      ) : rows.length === 0 ? (
        <SectionMessage>No capacity figures yet.</SectionMessage>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-5 py-3 font-medium">Academic year</th>
                <th className="px-5 py-3 font-medium">Grade</th>
                <th className="px-5 py-3 font-medium">Campus</th>
                <th className="px-5 py-3 text-right font-medium">Capacity</th>
                {canEdit && <th className="px-5 py-3 font-medium" aria-label="Actions" />}
              </tr>
            </thead>
            <tbody className="divide-y">
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="px-5 py-3">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="tabular-nums">{r.academicYear}</span>
                      <YearFlag status={yearStatus(r.academicYear, years)} />
                    </div>
                  </td>
                  <td className="px-5 py-3">{gradeName.get(r.gradeId) ?? "Unknown grade"}</td>
                  <td className="px-5 py-3">
                    {r.branchId === null
                      ? "All campuses"
                      : (campusName.get(r.branchId) ?? "Unknown campus")}
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">{r.capacity}</td>
                  {canEdit && (
                    <td className="px-5 py-3">
                      <div className="flex justify-end gap-2">
                        <ChangeCapacityDialog row={r} onDone={capacity.reload} />
                        <DeleteCapacityDialog row={r} onDone={capacity.reload} />
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function YearFlag({ status }: { status: ReturnType<typeof yearStatus> }) {
  if (status === "active") return null;
  return (
    <Badge
      variant="outline"
      className="border-amber-400/60 text-amber-700 dark:text-amber-300"
      title={
        status === "retired"
          ? "This year is retired. The figure can still be changed or deleted."
          : "This year isn't on the academic year list. The figure can still be changed or deleted."
      }
    >
      {status === "retired" ? "Retired year" : "Not on the year list"}
    </Badge>
  );
}

function CreateCapacityDialog({
  years,
  campuses,
  grades,
  onDone,
}: {
  years: AcademicYear[];
  campuses: Campus[];
  grades: SettingsGrade[];
  onDone: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [year, setYear] = useState("");
  const [gradeId, setGradeId] = useState("");
  const [campus, setCampus] = useState(ALL_CAMPUSES);
  const [figure, setFigure] = useState("");
  const [busy, setBusy] = useState(false);
  const yearOptions = capacityYearOptions(years);
  const gradeOptions = grades.filter((g) => g.isActive);

  function reset() {
    setYear("");
    setGradeId("");
    setCampus(ALL_CAMPUSES);
    setFigure("");
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    const value = parseWholeNumber(figure);
    if (value === null) {
      toast.error(NOT_A_NUMBER);
      return;
    }
    setBusy(true);
    try {
      await createCapacity(year, gradeId, campus === ALL_CAMPUSES ? null : campus, value);
      toast.success("Capacity added");
      setOpen(false);
      reset();
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not add the capacity."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        Add capacity
      </Button>
      <Dialog
        open={open}
        onOpenChange={(o) => {
          setOpen(o);
          if (!o) reset();
        }}
      >
        <DialogContent>
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>Add capacity</DialogTitle>
              <DialogDescription>
                Only active academic years can get a new figure.
              </DialogDescription>
            </DialogHeader>
            <div className="mt-4 grid gap-4">
              <div className="grid gap-1.5">
                <Label>Academic year</Label>
                <Select value={year} onValueChange={setYear}>
                  <SelectTrigger aria-label="Academic year">
                    <SelectValue placeholder="Choose a year" />
                  </SelectTrigger>
                  <SelectContent>
                    {yearOptions.map((y) => (
                      <SelectItem key={y} value={y}>
                        {y}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {yearOptions.length === 0 && (
                  <p className="text-xs text-muted-foreground">
                    No active academic year. Add or reactivate one first.
                  </p>
                )}
              </div>
              <div className="grid gap-1.5">
                <Label>Grade</Label>
                <Select value={gradeId} onValueChange={setGradeId}>
                  <SelectTrigger aria-label="Grade">
                    <SelectValue placeholder="Choose a grade" />
                  </SelectTrigger>
                  <SelectContent>
                    {gradeOptions.map((g) => (
                      <SelectItem key={g.id} value={g.id}>
                        {g.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-1.5">
                <Label>Campus</Label>
                <Select value={campus} onValueChange={setCampus}>
                  <SelectTrigger aria-label="Campus">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={ALL_CAMPUSES}>All campuses</SelectItem>
                    {campuses.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-1.5">
                <Label htmlFor="new-capacity">Capacity (0 closes the grade)</Label>
                <Input
                  id="new-capacity"
                  inputMode="numeric"
                  value={figure}
                  onChange={(e) => setFigure(e.target.value)}
                  maxLength={6}
                  className="w-32"
                />
              </div>
            </div>
            <DialogFooter className="mt-6">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={busy || year === "" || gradeId === "" || figure.trim() === ""}
              >
                Add
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

function ChangeCapacityDialog({ row, onDone }: { row: CapacityRow; onDone: () => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [figure, setFigure] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const value = parseWholeNumber(figure);
    if (value === null) {
      toast.error(NOT_A_NUMBER);
      return;
    }
    setBusy(true);
    try {
      await updateCapacity(row.id, value);
      toast.success("Capacity changed");
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not change the capacity."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        onClick={() => {
          setFigure(String(row.capacity));
          setOpen(true);
        }}
      >
        Change
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>Change capacity</DialogTitle>
              <DialogDescription>
                {row.academicYear}. Only the figure changes; delete and add again to change the
                year, grade or campus.
              </DialogDescription>
            </DialogHeader>
            <div className="mt-4 grid gap-1.5">
              <Label htmlFor={`capacity-${row.id}`}>Capacity (0 closes the grade)</Label>
              <Input
                id={`capacity-${row.id}`}
                inputMode="numeric"
                value={figure}
                onChange={(e) => setFigure(e.target.value)}
                maxLength={6}
                className="w-32"
              />
            </div>
            <DialogFooter className="mt-6">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={busy || figure.trim() === ""}>
                Save
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

function DeleteCapacityDialog({ row, onDone }: { row: CapacityRow; onDone: () => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  async function confirm() {
    setBusy(true);
    try {
      await deleteCapacity(row.id);
      toast.success("Capacity deleted");
      setOpen(false);
      await onDone();
    } catch (err) {
      toast.error(getErrorMessage(err, "Could not delete the capacity."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        Delete
      </Button>
      <AlertDialog open={open} onOpenChange={setOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this capacity figure?</AlertDialogTitle>
            <AlertDialogDescription>
              {row.academicYear}, capacity {row.capacity}. Decisions for this grade will no longer
              show a capacity warning.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={busy}
              onClick={(e) => {
                e.preventDefault();
                confirm();
              }}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

/* ---------------------------------------------------------------- campus grade rules */

function CampusRulesSection({ campuses, grades }: { campuses: Campus[]; grades: SettingsGrade[] }) {
  const rules = useLoad(listCampusGradeRules, [], "Could not load the campus grade rules.");
  const summary = campusGradeSummary(campuses, rules.data ?? [], grades);

  return (
    <section className="card-surface overflow-hidden">
      <div className="border-b p-6">
        <h2 className="text-sm font-semibold">Campus grade rules</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Which grades each campus accepts. A campus without rules accepts every grade. Changed by a
          migration, not here.
        </p>
      </div>
      {rules.error ? (
        <SectionMessage error>{rules.error}</SectionMessage>
      ) : !rules.data && rules.loading ? (
        <SectionMessage>Loading…</SectionMessage>
      ) : summary.length === 0 ? (
        <SectionMessage>No campuses.</SectionMessage>
      ) : (
        <ul className="divide-y">
          {summary.map((c) => (
            <li key={c.campusId} className="grid gap-1 px-6 py-3 sm:grid-cols-[10rem_1fr]">
              <span className="text-sm font-medium">{c.campusName}</span>
              <span className="text-sm text-muted-foreground">
                {c.grades === null ? "Every grade" : c.grades.join(", ")}
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
