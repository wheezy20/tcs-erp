// Parent-facing text for the public admissions forms (admissions slice 9b),
// ported from TCS OS backend/templates/public/inquiry.html and apply.html.
// One place for the wording, so it can be checked against TCS OS and tested
// for the house rule: no em or en dashes anywhere (public-copy.test.ts).
// Labels that are tied to a field stay next to the field in the page.

/** The thank-you pages' email sentence (slice 12, decided 2026-10-16). */
export const CONFIRMATION_EMAIL_NOTE =
  "You should receive a confirmation email shortly. If you do not see it within a few minutes, please check your spam folder or contact the school.";

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
  /** Slice 12 sends a confirmation email (wording decided 2026-10-16). */
  keepReference: (many: boolean) =>
    `${CONFIRMATION_EMAIL_NOTE} Please still keep ${many ? "these reference numbers" : "this reference number"}.`,
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
  /** Slice 12 sends a confirmation email (wording decided 2026-10-16). */
  keepReference: `${CONFIRMATION_EMAIL_NOTE} Please still keep this reference number.`,
} as const;

/** "Ama", "Ama and Kofi", "Ama, Kofi and Esi": the children's names as the
 * parent typed them, for the thank-you sentence. Blank names are skipped. */
export function joinNames(names: string[]): string {
  const list = names.map((n) => n.trim()).filter((n) => n !== "");
  if (list.length <= 1) return list[0] ?? "";
  return `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`;
}

// ---------------------------------------------------------------- application fee

/** The application fee and where it is paid (decision Q7: a constants
 * file, not the database, so nobody can change the account from the app).
 * Reported accurate by Eyram on 2026-10-15, as TCS OS shows them. */
export const APPLICATION_FEE = {
  amount: "GHS 200.00",
  bank: "Consolidated Bank Ghana",
  accountNumber: "0383011100001",
  accountName: "Treasures Christian School",
} as const;

/** The fee box, TCS OS's wording with the house rule applied: a colon in
 * the heading, "then" between the steps instead of arrows, and, until
 * slice 12 sends email, "the school will contact you" instead of "you
 * will be notified via e-mail" (decision Q8). */
export const FEE_BOX = {
  heading: `Application fee: ${APPLICATION_FEE.amount}`,
  intro:
    "Once your application form is received and reviewed, the school will contact you regarding an admission decision after due process. Submission of an application form and payment of the application fee does NOT mean admission has been granted.",
  accountHeading: "ACCOUNT DETAILS:",
  accountLines: [
    APPLICATION_FEE.bank,
    `Account No: ${APPLICATION_FEE.accountNumber}`,
    `Name: ${APPLICATION_FEE.accountName}`,
  ],
  processHeading: "PAYMENT PROCESS:",
  process: `Walk in to the bank, OR dial *170#, then Option 1 (Transfer money), then Option 6 (Bank account), then Option 1 (Wallet to bank account), then # for next, then Option 16 (CBG), then Enter account number ${APPLICATION_FEE.accountNumber}, then Enter amount ${APPLICATION_FEE.amount}, then Enter Reference: name of the learner`,
} as const;

// ---------------------------------------------------------------- documents and scholarship

export const DOCUMENTS_COPY = {
  labels: {
    proof_of_vaccination: "Proof of vaccination",
    financial_clearance: "Proof of financial clearance from previous school",
    previous_report: "Report card / transcript from previous school",
    application_fee_proof:
      "Proof of application fee payment (bank deposit slip, GIP confirmation or mobile money receipt)",
  } as Record<string, string>,
  vaccinationHint: "Required when applying for a preschool grade.",
  uploading: "Uploading…",
  uploaded: (name: string) => `Uploaded: ${name}. Choose another file to replace it.`,
  failed: "Upload failed.",
  /** A failed replacement: the earlier file stays and is still sent. */
  earlierKept: (name: string) => `Your earlier file (${name}) is still attached.`,
  /** The 8 files per session cap (D-9g) reached in this visit. */
  limitReached:
    "You have used all the uploads for this form. Please reload the page and choose your files again.",
} as const;

/** TCS OS's scholarship question (apply.html), with the arrow dropped
 * from the link text. The link opens the school's scholarship details
 * (reported accurate by Eyram, 2026-10-15). */
export const SCHOLARSHIP_COPY = {
  question: "Are you interested in scholarship information?",
  hint: "TCS offers several scholarship schemes through the Treasures Impact Foundation.",
  linkText: "View scholarship details",
  url: "https://drive.google.com/file/d/12dDFJDSY2yaKT-KdMBQ7Y4DGq7_Bhbgf/view?usp=sharing",
  detailsPlaceholder: "Tell us more",
} as const;

// ---------------------------------------------------------------- declaration

export type DeclarationParagraph = string | { verse: string };

/** The declaration, word for word from TCS OS apply.html (TCS OS commit
 * f7b57ae, 2026-08-26). The only change: the verse's attribution, which
 * TCS OS sets after a dash, is in brackets. "The school's privacy policy"
 * has no link yet: a published privacy policy is a go-live gate, and its
 * link goes here, in this one place, when it exists. */
export const DECLARATION_SECTIONS: readonly {
  heading: string;
  paragraphs: readonly DeclarationParagraph[];
}[] = [
  {
    heading: "Indemnity Clause",
    paragraphs: [
      "As the parent/guardian of the learner admitted to Treasures Christian School, I understand that the school strives to ensure safety but cannot eliminate all risks associated with school activities, both on and off campus. I release and hold harmless Treasures Christian School, its staff, and representatives from any claims or liabilities arising from my ward's participation in school activities, except in cases of proven gross negligence. I accept responsibility for disclosing any relevant medical conditions and understand the school may take emergency action if needed, with resulting costs being my responsibility.",
    ],
  },
  {
    heading: "Data Protection",
    paragraphs: [
      "By signing this form, I/We consent to Treasures Christian School collecting, processing, and storing personal data and information provided in this admission form for the purpose of enrollment, administration, communication, and the safety and welfare of the learner. I/We understand that this data will be handled in accordance with applicable data protection laws and the school's privacy policy.",
    ],
  },
  {
    heading: "Declaration and Policy",
    paragraphs: [
      "Choosing a school is an important decision. At TCS, we value strong partnerships with families who share our commitment to academic excellence, character development, and Christian values. TCS reserves the right to recommend an alternative placement or decline admission where the School is unable to adequately support the child's needs.",
      "Newly admitted pupils may be placed under observation during an initial adjustment period.",
      "TCS reserves the right to review or withdraw admission where significant concerns arise or where undisclosed needs emerge that the School cannot reasonably support.",
      {
        verse:
          '"Train up a child in the way he should go, and when he is old he will not depart from it." (Proverbs 22:6)',
      },
      "We look forward to welcoming your family into the TCS community.",
      "I declare that the information provided in this form is true and correct to the best of my knowledge. I understand that any false information given may result in the withdrawal of an offer of a place or the removal of a student from the school. By signing this form, I consent and agree to the terms and conditions of Treasures Christian School.",
    ],
  },
];

export const DECLARATION_COPY = {
  agreement:
    "I have read and agree to the above Indemnity Clause, Data Protection consent, and Declaration & Policy.",
  mediaHeading: "Media Consent (optional)",
  mediaText:
    "I/We grant permission for the learner's photographs, videos, school work, and/or achievements to be used in school communications, including but not limited to newsletters, brochures, social media platforms, school website, and other promotional or marketing materials. These may be shared with the public to highlight school activities and celebrate student successes. If I/We wish to withdraw this media consent at any time, I/We understand that a written notice must be submitted to the school administration.",
  mediaAgreement: "I/We grant media consent as described above.",
  signature: "Sign by entering your full name:",
} as const;

/** TCS OS's thank-you sentence with the child's name, grade and year as
 * the parent entered them. */
export function applicationThankYou(name: string, grade: string, year: string): string {
  return `Thank you! We've received the application for ${name} (${grade}, ${year}). Our admissions team will review your documents and be in touch soon.`;
}

// ---------------------------------------------------------------- privacy policy

/** The school's privacy policy: the one place its link is set. A published
 * policy is a go-live gate; until it exists the words are shown without a
 * link. The policy must describe saved applications (slice 10). */
export const PRIVACY_POLICY = {
  text: "the school's privacy policy",
  url: null as string | null,
} as const;

// ---------------------------------------------------------------- save and finish later (slice 10)

/** The generic refusal: also the server's wording for the live-draft
 * limit, which must never say that saved applications exist. */
export const DRAFT_REFUSED =
  "We could not save your application right now. Please contact the school office.";

export const SAVE_COPY = {
  button: "Save and finish later",
  panelTitle: "Save and finish later",
  panelIntro:
    "We will email you a private link so that you can come back and finish this application, on this device or another one.",
  emailLabel: "Email address for the link",
  /** The consent line (drafted for Eyram's review, 2026-10-21), in two parts
   * around the privacy policy, which is linked from PRIVACY_POLICY. */
  consentBefore:
    "I agree that Treasures Christian School may keep the answers I have entered on this form, which may include details about my child, and the email address above, so that I can finish my application later. They are kept for 30 days after my last save, and for no more than 60 days in all, and are then deleted. The health questions, uploaded files, the declaration, my signature and media consent are not saved. I can delete my saved application at any time from the emailed link. My saved answers are handled in line with",
  consentAfter: ".",
  consentRequired: "Please tick the box to agree before saving.",
  turnstilePrompt: "Complete this security check to save.",
  save: "Save and email me a link",
  saving: "Saving…",
  close: "Close",
  saved: (masked: string, until: string) =>
    `Saved. We have emailed a link to ${masked}. It may take a few minutes to arrive, so please also check your spam folder. Your answers will be kept until ${until} unless you save again.`,
  savedAgain: (until: string) =>
    `Saved. Your answers will be kept until ${until}. Use the link we emailed you to come back.`,
  savedAgainEmailed: (masked: string, until: string) =>
    `Saved. We have emailed a new link to ${masked}. Your answers will be kept until ${until}.`,
  saveChanges: "Save changes",
  emailAgain: "Also email me a new link",
  /** After a resume email limit: the save was undone, nothing typed is lost. */
  saveWithoutEmail: "Save without emailing a link",
  notLost: "Nothing you have typed has been lost.",
  resumeLoading: "Opening your saved application…",
  resumed:
    "Welcome back. Your saved answers are restored. The health questions, uploaded files, the declaration, your signature and media consent were not saved, so please complete them again before you submit.",
  discard: "Discard this saved application",
  discardConfirm:
    "Discard your saved application? This deletes it and clears this form, and cannot be undone.",
  discarded: "Your saved application has been deleted.",
  filesAgain: "Files are not saved with your application. Please attach your documents again.",
  linkProblemTitle: "This link can't be opened",
  expiredTitle: "This saved application has expired",
  startNew: "Start a new application",
  loadFailedTitle: "We could not open your saved application",
  loadFailed:
    "We could not open your saved application just now. Please try again in a few minutes, or contact the school office.",
  retry: "Try again",
  /** A save naming an older version: another window saved since, or an
   * earlier save's answer was lost. */
  versionConflict:
    "This application was saved again from another window or device. Save what is on this screen to replace that copy, or open your emailed link in a new tab to see it.",
  saveThisScreen: "Save what is on this screen",
  stateRefused:
    "This form could not be saved. Please check what you have typed and try again, or contact the school office.",
  submittedTitle: "This application has already been submitted",
  submittedBody:
    "The school has received it. You should have a confirmation email with your application number. Please contact the school office if you have any questions.",
} as const;
