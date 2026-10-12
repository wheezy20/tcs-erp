import { useEffect, useMemo, useState } from "react";
import { Link } from "@tanstack/react-router";
import { ChevronLeft, ChevronRight, Search } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  ALL,
  OTHER_YEAR,
  PAGE_SIZE,
  UNBANDED_GRADE,
  listApplications,
  type ApplicationListFilters,
} from "@/modules/admissions/data/applications";
import { listAcademicYears, listCampuses, listGrades } from "@/modules/admissions/data/reference";
import { SEARCH_MAX_LENGTH } from "@/modules/admissions/data/search";
import { GradeCell, StageBadge } from "@/modules/admissions/components/stage-badge";
import { useAdmissionsAccess } from "@/modules/admissions/hooks/use-admissions-access";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import { STAGES, STAGE_LABELS } from "@/modules/admissions/labels";
import {
  canSeeUnbandedGrades,
  gradeFilterOptions,
  isAdmissionsReadOnly,
  emptyListMessage,
  officerHasNoScope,
} from "@/modules/admissions/permissions";

const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });

export function ApplicationListPage() {
  const { role, caps, capsLoading } = useAdmissionsAccess();
  const [searchInput, setSearchInput] = useState("");
  const [filters, setFilters] = useState<ApplicationListFilters>({
    search: "",
    stage: ALL,
    branchId: ALL,
    year: ALL,
    grade: ALL,
    page: 0,
  });

  // Debounce typing so each keystroke isn't a request.
  useEffect(() => {
    const t = setTimeout(() => {
      setFilters((f) => (f.search === searchInput ? f : { ...f, search: searchInput, page: 0 }));
    }, 300);
    return () => clearTimeout(t);
  }, [searchInput]);

  const campuses = useLoad(listCampuses, [], "Could not load campuses.");
  const years = useLoad(listAcademicYears, [], "Could not load academic years.");
  const grades = useLoad(listGrades, [], "Could not load grades.");
  const yearLabels = useMemo(() => (years.data ?? []).map((y) => y.label), [years.data]);

  // Wait for the academic year list first: the "Other (not on the list)"
  // filter needs it, and starting earlier would fetch the list twice.
  const yearsSettled = !years.loading;
  const list = useLoad(
    () => (yearsSettled ? listApplications(filters, yearLabels) : new Promise<never>(() => {})),
    [filters, yearLabels, yearsSettled],
    "Could not load applications.",
  );

  const gradeOptions = gradeFilterOptions(role, caps, grades.data ?? []);
  const showUnbanded = canSeeUnbandedGrades(role, caps);
  const noScope = !capsLoading && officerHasNoScope(role, caps);

  const set = (patch: Partial<ApplicationListFilters>) =>
    setFilters((f) => ({ ...f, ...patch, page: 0 }));

  const total = list.data?.total ?? 0;
  const rows = list.data?.rows ?? [];
  const firstShown = total === 0 ? 0 : filters.page * PAGE_SIZE + 1;
  const lastShown = Math.min(total, (filters.page + 1) * PAGE_SIZE);
  const isFiltered =
    filters.search !== "" ||
    filters.stage !== ALL ||
    filters.branchId !== ALL ||
    filters.year !== ALL ||
    filters.grade !== ALL;

  return (
    <>
      <PageHeader
        title="Applications"
        description="Inquiries and applications for every campus and grade you can see."
        actions={
          isAdmissionsReadOnly(role) ? <Badge variant="outline">Read-only</Badge> : undefined
        }
      />

      {noScope && (
        <div className="mb-6 rounded-lg border border-dashed px-4 py-3 text-sm text-muted-foreground">
          Your account has no grade bands yet, so no applications are shown. Ask a Manager to set
          your admissions access in Settings.
        </div>
      )}

      <div className="card-surface overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-56 max-w-sm flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Search student name or reference"
              className="h-10 rounded-xl pl-9"
              maxLength={SEARCH_MAX_LENGTH}
            />
          </div>
          <Select value={filters.stage} onValueChange={(v) => set({ stage: v })}>
            <SelectTrigger className="w-44" aria-label="Stage">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All stages</SelectItem>
              {STAGES.map((s) => (
                <SelectItem key={s} value={s}>
                  {STAGE_LABELS[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filters.branchId} onValueChange={(v) => set({ branchId: v })}>
            <SelectTrigger className="w-40" aria-label="Campus">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All campuses</SelectItem>
              {(campuses.data ?? []).map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filters.year} onValueChange={(v) => set({ year: v })}>
            <SelectTrigger className="w-44" aria-label="Academic year">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All academic years</SelectItem>
              {(years.data ?? []).map((y) => (
                <SelectItem key={y.label} value={y.label}>
                  {y.label}
                  {y.isActive ? "" : " (inactive)"}
                </SelectItem>
              ))}
              <SelectItem value={OTHER_YEAR}>Other (not on the list)</SelectItem>
            </SelectContent>
          </Select>
          <Select value={filters.grade} onValueChange={(v) => set({ grade: v })}>
            <SelectTrigger className="w-44" aria-label="Grade">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All grades</SelectItem>
              {gradeOptions.map((g) => (
                <SelectItem key={g.name} value={g.name}>
                  {g.name}
                </SelectItem>
              ))}
              {showUnbanded && (
                <SelectItem value={UNBANDED_GRADE}>Unbanded or other grade</SelectItem>
              )}
            </SelectContent>
          </Select>
        </div>

        {list.error ? (
          <p className="p-10 text-center text-sm text-destructive">{list.error}</p>
        ) : list.loading && !list.data ? (
          <p className="p-10 text-center text-sm text-muted-foreground">Loading…</p>
        ) : rows.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">
            {emptyListMessage(role, isFiltered)}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Student</th>
                  <th className="px-5 py-3 font-medium">Stage</th>
                  <th className="px-5 py-3 font-medium">Grade</th>
                  <th className="px-5 py-3 font-medium">Campus</th>
                  <th className="px-5 py-3 font-medium">Academic year</th>
                  <th className="px-5 py-3 font-medium">Updated</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((r) => (
                  <tr key={r.id} className="group hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/admissions/$applicationId"
                        params={{ applicationId: r.id }}
                        className="font-medium group-hover:text-primary"
                      >
                        {r.studentName}
                      </Link>
                      <p className="text-xs tabular-nums text-muted-foreground">
                        {[r.applicationReference, r.inquiryReference].filter(Boolean).join(" · ") ||
                          "No reference"}
                      </p>
                    </td>
                    <td className="px-5 py-3">
                      <StageBadge stage={r.stage} />
                    </td>
                    <td className="px-5 py-3">
                      <GradeCell gradeAsEntered={r.gradeAsEntered} gradeName={r.gradeName} />
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">
                      {r.branchName ?? "Not chosen"}
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">
                      {r.academicYear}
                      {r.monthOfEnrollment ? (
                        <p className="text-xs">From {r.monthOfEnrollment}</p>
                      ) : null}
                    </td>
                    <td className="px-5 py-3 tabular-nums text-muted-foreground">
                      {dateFormat.format(new Date(r.updatedAt))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {total > 0 && (
          <div className="flex items-center justify-between gap-4 border-t px-5 py-3 text-sm text-muted-foreground">
            <span className="tabular-nums">
              {firstShown} to {lastShown} of {total}
            </span>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={filters.page === 0 || list.loading}
                onClick={() => setFilters((f) => ({ ...f, page: f.page - 1 }))}
              >
                <ChevronLeft className="size-4" /> Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={lastShown >= total || list.loading}
                onClick={() => setFilters((f) => ({ ...f, page: f.page + 1 }))}
              >
                Next <ChevronRight className="size-4" />
              </Button>
            </div>
          </div>
        )}
      </div>
    </>
  );
}
