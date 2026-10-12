import { supabase } from "@/lib/supabase";
import { notInListFilter, searchFilter, searchPattern } from "@/modules/admissions/data/search";

// The applications list (admissions_application_list, 20261017100000). The
// view is security_invoker, so the applications and students select
// policies decide which rows come back. Explicit columns only; the view has
// no health, decision, offer or token column in the first place.

export const PAGE_SIZE = 50;

/** Filter value meaning "grade not on the admissions grade list". */
export const UNBANDED_GRADE = "__unbanded__";
/** Filter value meaning "academic year not on the curated list". */
export const OTHER_YEAR = "__other__";
export const ALL = "all";

const LIST_COLUMNS =
  "id, student_full_name, branch_id, branch_name, academic_year, year_group_applied_for, grade_name, grade_band, month_of_enrollment, stage, inquiry_reference, application_reference, updated_at";

export type ApplicationListRow = {
  id: string;
  studentName: string;
  branchName: string | null;
  academicYear: string;
  gradeAsEntered: string;
  gradeName: string | null;
  gradeBand: string | null;
  monthOfEnrollment: string;
  stage: string;
  inquiryReference: string | null;
  applicationReference: string | null;
  updatedAt: string;
};

export type ApplicationListFilters = {
  search: string;
  stage: string;
  branchId: string;
  year: string;
  grade: string;
  page: number;
};

export async function listApplications(
  filters: ApplicationListFilters,
  academicYearLabels: string[],
): Promise<{ rows: ApplicationListRow[]; total: number }> {
  const from = filters.page * PAGE_SIZE;
  let query = supabase
    .from("admissions_application_list")
    .select(LIST_COLUMNS, { count: "exact" })
    .order("updated_at", { ascending: false })
    .order("id")
    .range(from, from + PAGE_SIZE - 1);

  const pattern = searchPattern(filters.search);
  if (pattern) query = query.or(searchFilter(pattern));
  if (filters.stage !== ALL) query = query.eq("stage", filters.stage);
  if (filters.branchId !== ALL) query = query.eq("branch_id", filters.branchId);
  if (filters.year === OTHER_YEAR) {
    if (academicYearLabels.length > 0) {
      query = query.not("academic_year", "in", notInListFilter(academicYearLabels));
    }
  } else if (filters.year !== ALL) {
    query = query.eq("academic_year", filters.year);
  }
  if (filters.grade === UNBANDED_GRADE) query = query.is("grade_name", null);
  else if (filters.grade !== ALL) query = query.eq("grade_name", filters.grade);

  const { data, error, count } = await query;
  if (error) throw error;
  return {
    total: count ?? 0,
    rows: (data ?? []).map((r) => ({
      id: r.id!,
      studentName: r.student_full_name ?? "",
      branchName: r.branch_name,
      academicYear: r.academic_year ?? "",
      gradeAsEntered: r.year_group_applied_for ?? "",
      gradeName: r.grade_name,
      gradeBand: r.grade_band,
      monthOfEnrollment: r.month_of_enrollment ?? "",
      stage: r.stage ?? "",
      inquiryReference: r.inquiry_reference,
      applicationReference: r.application_reference,
      updatedAt: r.updated_at ?? "",
    })),
  };
}
