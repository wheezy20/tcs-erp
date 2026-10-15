// Parent-facing text for the public admissions forms (admissions slice 9b),
// ported from TCS OS backend/templates/public/inquiry.html and apply.html.
// One place for the wording, so it can be checked against TCS OS and tested
// for the house rule: no em or en dashes anywhere (public-copy.test.ts).
// Labels that are tied to a field stay next to the field in the page.

export const ENQUIRY_COPY = {
  pageTitle: "Admissions enquiry · TCS",
  title: "Admissions Enquiry",
  subtitle: "Tell us about your family and we'll be in touch about next steps.",
  requiredNote: "Fields marked * are required.",
  sections: {
    referral: "How did you hear about us?",
    guardians: "Parent / Guardian information",
    enquiry: "The enquiry",
    other: "Other information",
  },
  addGuardian: "+ Add a second parent / guardian",
  childCount: "How many children are you seeking to enrol?",
  submit: "Submit enquiry",
  submitting: "Submitting…",
  checkFields: "Please check the fields marked in red.",
  completeCheck: "Please complete the security check above the button.",
  verifyUnavailable: "The security check couldn't load.",
  loadErrorTitle: "The enquiry form couldn't load",
  loadErrorBody: "Please try again later, or call the school office to make an enquiry.",
  closedTitle: "Online enquiries are closed",
  closedBody:
    "We're not taking enquiries online at the moment. Please call the school office to make an enquiry.",
  unavailableTitle: "The enquiry form isn't available",
  thankYouTitle: "Thank you, we've received your enquiry",
  /** TCS OS's sentence, with the names the parent typed. */
  thankYouFor: (names: string) =>
    `Thank you! We've received your enquiry for ${names}. Our admissions team will be in touch soon.`,
  referenceOne: "Your reference number",
  referenceMany: "Your reference numbers",
  /** No confirmation email until slice 12, so the page says so. */
  keepReference: (many: boolean) =>
    `Please keep ${many ? "these numbers" : "this number"}. You won't receive a confirmation email, so write ${
      many ? "them" : "it"
    } down or take a screenshot, and quote ${many ? "them" : "it"} when you contact the school.`,
} as const;

export const APPLICATION_COPY = {
  title: "Admissions Application",
  subtitle:
    "Formally apply and upload the required documents. You don't need to have submitted an enquiry first.",
  /** Shown under the subtitle: one application per child. */
  note: "One application per child. Fields marked * are required.",
  /** TCS OS: "...so we can match your family's records", reworded: nothing
   * in the family's record is changed by an application (D-9b). */
  emailHint:
    "If you already sent us an enquiry, please use the same email address so the school can link the two.",
  emergencyHint: "Someone we can reach if a parent/guardian is unavailable.",
  healthPrivacy: "Only staff who need it can see these answers.",
  health: {
    hasNeeds: "Does the learner have any learning or physical needs we should be aware of?",
    hasMedical: "Does the learner have any medical conditions we should be aware of?",
    hasAllergies: "Does the learner have any allergies or dietary requirements?",
    details: "Please provide details",
  },
  documentsHint: "Accepted file types: PDF, JPG, PNG. Maximum size: 10MB per file.",
  uploadCheck: "Complete this security check to upload your documents.",
  preparingUploads: "Preparing uploads…",
  back: "Back",
  next: "Next",
  submit: "Submit application",
  submitting: "Submitting…",
  incompleteIntro: "Please complete the following section(s) before submitting:",
  completeCheck: "Please complete the security check above the button before submitting.",
  waitForUploads: "Please wait for document uploads to finish before submitting.",
  checkFields: "Please check the fields marked in red.",
  loadErrorTitle: "The application form couldn't load",
  loadErrorBody: "Please try again later, or call the school office to apply.",
  closedTitle: "Online applications are closed",
  closedBody:
    "We're not taking applications online at the moment. Please call the school office to apply.",
  unavailableTitle: "The application form isn't available",
  thankYouTitle: "Thank you, we've received your application",
  thankYouBody: "The school will check your documents and contact you about the next steps.",
  referenceLabel: "Your application number",
  keepReference:
    "Please keep this number. You won't receive a confirmation email, so write it down or take a screenshot, and quote it when you contact the school.",
} as const;

/** "Ama", "Ama and Kofi", "Ama, Kofi and Esi": the children's names as the
 * parent typed them, for the thank-you sentence. Blank names are skipped. */
export function joinNames(names: string[]): string {
  const list = names.map((n) => n.trim()).filter((n) => n !== "");
  if (list.length <= 1) return list[0] ?? "";
  return `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`;
}
