import { supabase } from "@/lib/supabase";
import type { MatchOutcome } from "@/modules/admissions/submission-check";

export type MatchFlag = {
  outcome: MatchOutcome;
  familyMatched: boolean;
  studentMatched: boolean;
  /** The earlier application a possible duplicate matched. */
  matchedApplicationId: string | null;
  /** That application's reference, or null when RLS hides it from you. */
  matchedReference: string | null;
  matchedVisible: boolean;
  differences: unknown;
  gradeNames: Record<string, string>;
};

/** The match flag for one application, or null when there is none (a new
 * family, or an application not made through the public form). RLS
 * returns it only to Manager, Auditor and an Admissions Officer in scope. */
export async function getMatchFlag(applicationId: string): Promise<MatchFlag | null> {
  const { data, error } = await supabase
    .from("application_match_flags")
    .select("outcome, family_matched, student_matched, matched_application_id, differences")
    .eq("application_id", applicationId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  let matchedReference: string | null = null;
  let matchedVisible = false;
  if (data.matched_application_id) {
    const { data: m, error: mError } = await supabase
      .from("applications")
      .select("application_reference, inquiry_reference")
      .eq("id", data.matched_application_id)
      .maybeSingle();
    if (mError) throw mError;
    matchedVisible = m !== null;
    matchedReference = m ? (m.application_reference ?? m.inquiry_reference) : null;
  }
  const { data: grades, error: gError } = await supabase
    .from("admissions_grades")
    .select("id, name");
  if (gError) throw gError;
  return {
    outcome: data.outcome as MatchOutcome,
    familyMatched: data.family_matched,
    studentMatched: data.student_matched,
    matchedApplicationId: data.matched_application_id,
    matchedReference,
    matchedVisible,
    differences: data.differences,
    gradeNames: Object.fromEntries((grades ?? []).map((g) => [g.id, g.name])),
  };
}
