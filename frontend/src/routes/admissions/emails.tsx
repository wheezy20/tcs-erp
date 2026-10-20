import { createFileRoute } from "@tanstack/react-router";

import { AdmissionsEmailsPage } from "@/modules/admissions/components/emails-page";

export const Route = createFileRoute("/admissions/emails")({
  component: AdmissionsEmailsPage,
});
