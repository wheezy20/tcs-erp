import { createFileRoute } from "@tanstack/react-router";

import { ApplicationListPage } from "@/modules/admissions/components/application-list-page";

export const Route = createFileRoute("/admissions/")({
  component: ApplicationListPage,
});
