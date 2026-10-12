import { createFileRoute } from "@tanstack/react-router";

import { AdmissionsSettingsPage } from "@/modules/admissions/components/settings-page";

export const Route = createFileRoute("/admissions/settings")({
  component: AdmissionsSettingsPage,
});
