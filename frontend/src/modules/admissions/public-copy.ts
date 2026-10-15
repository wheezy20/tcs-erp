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

/** "Ama", "Ama and Kofi", "Ama, Kofi and Esi": the children's names as the
 * parent typed them, for the thank-you sentence. Blank names are skipped. */
export function joinNames(names: string[]): string {
  const list = names.map((n) => n.trim()).filter((n) => n !== "");
  if (list.length <= 1) return list[0] ?? "";
  return `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`;
}
