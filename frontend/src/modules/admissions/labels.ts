// Display labels for admissions values. Presentation only: the database's
// CHECK constraints are the authority on which values exist.

export const STAGES = [
  "inquiry",
  "application",
  "document_review",
  "offer",
  "enrolled",
  "waitlisted",
  "rejected",
  "offer_declined",
] as const;
export type Stage = (typeof STAGES)[number];

export const STAGE_LABELS: Record<Stage, string> = {
  inquiry: "Inquiry",
  application: "Application",
  document_review: "Document review",
  offer: "Offer",
  enrolled: "Enrolled",
  waitlisted: "Waitlisted",
  rejected: "Rejected",
  offer_declined: "Offer declined",
};

export function stageLabel(stage: string): string {
  return STAGE_LABELS[stage as Stage] ?? stage;
}

export const STAGE_TONE: Record<Stage, "default" | "secondary" | "outline" | "destructive"> = {
  inquiry: "outline",
  application: "outline",
  document_review: "secondary",
  offer: "default",
  enrolled: "default",
  waitlisted: "secondary",
  rejected: "destructive",
  offer_declined: "destructive",
};

export const DOCUMENT_TYPE_LABELS: Record<string, string> = {
  proof_of_vaccination: "Proof of vaccination",
  financial_clearance: "Financial clearance",
  previous_report: "Previous report",
  application_fee_proof: "Application fee proof",
  proof_of_funds: "Proof of funds",
  passport_photo: "Passport photo",
  birth_certificate: "Birth certificate",
  other: "Other",
};

export const DOCUMENT_STATUSES = ["required", "pending_review", "approved", "rejected"] as const;
export type DocumentStatus = (typeof DOCUMENT_STATUSES)[number];

export const DOCUMENT_STATUS_LABELS: Record<DocumentStatus, string> = {
  required: "Not uploaded",
  pending_review: "Pending review",
  approved: "Approved",
  rejected: "Rejected",
};

export const DOCUMENT_STATUS_TONE: Record<
  DocumentStatus,
  "default" | "secondary" | "outline" | "destructive"
> = {
  required: "outline",
  pending_review: "secondary",
  approved: "default",
  rejected: "destructive",
};

export const REFERRAL_LABELS: Record<string, string> = {
  "": "Not given",
  current_parent: "Current parent",
  former_parent: "Former parent",
  parent_referral: "Parent referral",
  staff_referral: "Staff referral",
  website: "Website",
  friend_colleague: "Friend or colleague",
  social_media: "Social media",
  other: "Other",
};

export const RELATIONSHIP_LABELS: Record<string, string> = {
  mother: "Mother",
  father: "Father",
  guardian: "Guardian",
  other: "Other",
};

export const GENDER_LABELS: Record<string, string> = {
  "": "Not given",
  male: "Male",
  female: "Female",
};
