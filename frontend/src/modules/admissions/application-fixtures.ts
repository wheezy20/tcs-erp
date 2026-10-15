// Test fixtures shared by application-form.test.ts and
// application-steps.test.ts (pure data; not imported by the app).
import {
  FEE_PROOF,
  emptyApplicationDraft,
  type ApplicationDraft,
  type UploadedFile,
} from "@/modules/admissions/application-form";
import { parsePublicOptions } from "@/modules/admissions/inquiry-form";

export const OPTIONS = parsePublicOptions({
  intake_open: false,
  applications_open: true,
  grades: [
    {
      id: "g-n1",
      name: "Nursery 1",
      position: 2,
      required_document_types: [FEE_PROOF, "proof_of_vaccination"],
    },
    { id: "g-3", name: "Grade 3", position: 8, required_document_types: [FEE_PROOF] },
    { id: "g-2", name: "Grade 2", position: 7 },
  ],
  campuses: [
    { id: "c-annex", name: "Annex", accepted_grade_ids: ["g-n1"] },
    { id: "c-main", name: "Main", accepted_grade_ids: ["g-n1", "g-3", "g-2"] },
  ],
  academic_years: ["2026/2027"],
});

export const TODAY = "2026-10-15";

export const FEE: UploadedFile = {
  reservationId: "r1",
  path: "uploads/r1/application_fee_proof.pdf",
  fileName: "slip.pdf",
};
export const VAC: UploadedFile = {
  reservationId: "r2",
  path: "uploads/r2/proof_of_vaccination.png",
  fileName: "card.png",
};

/** A complete, valid application for Grade 3 at Main. */
export function validDraft(): ApplicationDraft {
  const d = emptyApplicationDraft();
  d.guardians = [
    {
      surname: "Mensah",
      firstName: "Ama",
      relationship: "mother",
      religion: "Christian",
      address: "1 Ring Road",
      townCity: "Accra",
      phone: "0590000000",
      email: " Ama@Example.com ",
    },
  ];
  d.child = {
    ...d.child,
    fullName: " Kofi Mensah ",
    dateOfBirth: "03/02/2019",
    gender: "male",
    nationality: "Ghana",
    currentGrade: "g-2",
    currentSchool: "Little Stars",
    previousSchoolLocation: " Spintex Road ",
    gradeId: "g-3",
    academicYear: "2026/2027",
    month: "September",
  };
  d.campusId = "c-main";
  d.emergency = { name: "Kojo", relationship: "Uncle", phone: "+442079460958" };
  d.health = {
    hasNeeds: false,
    needs: "",
    hasMedical: false,
    medical: "",
    hasAllergies: false,
    allergies: "",
  };
  d.signature = "Ama Mensah";
  d.agreed = true;
  return d;
}
