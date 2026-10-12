import { supabase } from "@/lib/supabase";

// Small reference lists the admissions screens need.

export type Campus = { id: string; name: string };

/** Campuses (branches), oldest first so Main leads. */
export async function listCampuses(): Promise<Campus[]> {
  const { data, error } = await supabase
    .from("branches")
    .select("id, name, created_at")
    .order("created_at")
    .order("id");
  if (error) throw error;
  return (data ?? []).map((b) => ({ id: b.id, name: b.name }));
}

export type AcademicYear = { label: string; isActive: boolean };

/** The curated academic year list (20261017110000). */
export async function listAcademicYears(): Promise<AcademicYear[]> {
  const { data, error } = await supabase
    .from("admissions_academic_years")
    .select("label, is_active, position")
    .order("position")
    .order("label");
  if (error) throw error;
  return (data ?? []).map((y) => ({ label: y.label, isActive: y.is_active }));
}

export type GradeListItem = { name: string; band: string | null };

/** The admissions grade list, in school order. */
export async function listGrades(): Promise<GradeListItem[]> {
  const { data, error } = await supabase
    .from("admissions_grades")
    .select("name, band, position, is_active")
    .order("position");
  if (error) throw error;
  return (data ?? []).filter((g) => g.is_active).map((g) => ({ name: g.name, band: g.band }));
}

/** id to name for every staff row (list_staff_names(), any active staff). */
export async function listStaffNames(): Promise<Map<string, string>> {
  const { data, error } = await supabase.rpc("list_staff_names");
  if (error) throw error;
  return new Map((data ?? []).map((s) => [s.id, s.name]));
}
