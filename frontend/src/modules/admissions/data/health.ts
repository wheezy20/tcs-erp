import { supabase } from "@/lib/supabase";

// Health answers (application_health_info, slice 4). Never in the list, the
// search or any export; only the detail page's health panel calls these, and
// it reads answers only after hasHealthCapability() returned true.

/** The live capability check (has_admissions_capability('health')), so a
 * capability revoked mid-session can't leave the panel claiming "no health
 * information on file". */
export async function hasHealthCapability(): Promise<boolean> {
  const { data, error } = await supabase.rpc("has_admissions_capability", {
    p_capability: "health",
  });
  if (error) throw error;
  return data === true;
}

export type HealthInfo = {
  hasLearningOrPhysicalNeeds: boolean;
  learningOrPhysicalNeedsDetails: string;
  hasMedicalConditions: boolean;
  medicalConditionsDetails: string;
  hasAllergiesOrDietaryRequirements: boolean;
  allergiesDietaryDetails: string;
};

export async function getHealthInfo(applicationId: string): Promise<HealthInfo | null> {
  const { data, error } = await supabase
    .from("application_health_info")
    .select(
      "has_learning_or_physical_needs, learning_or_physical_needs_details, has_medical_conditions, medical_conditions_details, has_allergies_or_dietary_requirements, allergies_dietary_details",
    )
    .eq("application_id", applicationId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    hasLearningOrPhysicalNeeds: data.has_learning_or_physical_needs,
    learningOrPhysicalNeedsDetails: data.learning_or_physical_needs_details,
    hasMedicalConditions: data.has_medical_conditions,
    medicalConditionsDetails: data.medical_conditions_details,
    hasAllergiesOrDietaryRequirements: data.has_allergies_or_dietary_requirements,
    allergiesDietaryDetails: data.allergies_dietary_details,
  };
}
