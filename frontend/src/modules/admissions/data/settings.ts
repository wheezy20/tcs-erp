import { supabase } from "@/lib/supabase";

// Reads for the admissions settings screen (slice 7b2). Manager and Auditor
// only: admissions_capacity and admissions_settings are select-only for
// those two roles (RLS), so the page never calls these for anyone else.

export type CapacityRow = {
  id: string;
  academicYear: string;
  gradeId: string;
  branchId: string | null;
  capacity: number;
};

/** Every capacity row, including any for a year not on the list. */
export async function listCapacity(): Promise<CapacityRow[]> {
  const { data, error } = await supabase
    .from("admissions_capacity")
    .select("id, academic_year, grade_id, branch_id, capacity")
    .order("academic_year")
    .order("id");
  if (error) throw error;
  return (data ?? []).map((c) => ({
    id: c.id,
    academicYear: c.academic_year,
    gradeId: c.grade_id,
    branchId: c.branch_id,
    capacity: c.capacity,
  }));
}

export type SettingsGrade = { id: string; name: string; position: number; isActive: boolean };

/** Every admissions grade, inactive ones too, so an old capacity row or
 * campus rule still shows its grade's name. */
export async function listAllGrades(): Promise<SettingsGrade[]> {
  const { data, error } = await supabase
    .from("admissions_grades")
    .select("id, name, position, is_active")
    .order("position");
  if (error) throw error;
  return (data ?? []).map((g) => ({
    id: g.id,
    name: g.name,
    position: g.position,
    isActive: g.is_active,
  }));
}

/** The current offer expiry in days (the single admissions_settings row). */
export async function getOfferTtlDays(): Promise<number | null> {
  const { data, error } = await supabase
    .from("admissions_settings")
    .select("offer_ttl_days")
    .eq("id", 1)
    .maybeSingle();
  if (error) throw error;
  return data?.offer_ttl_days ?? null;
}

export type CampusGradeRule = { branchId: string; gradeId: string };

/** Campus grade rules: a campus with rows accepts only those grades; a
 * campus without rows accepts every grade. Read-only in the app. */
export async function listCampusGradeRules(): Promise<CampusGradeRule[]> {
  const { data, error } = await supabase
    .from("admissions_campus_grade_rules")
    .select("branch_id, grade_id");
  if (error) throw error;
  return (data ?? []).map((r) => ({ branchId: r.branch_id, gradeId: r.grade_id }));
}
