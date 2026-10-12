import { createFileRoute } from "@tanstack/react-router";

import { ApplicationDetailPage } from "@/modules/admissions/components/application-detail-page";

export const Route = createFileRoute("/admissions/$applicationId")({
  component: AdmissionsDetailRoute,
});

function AdmissionsDetailRoute() {
  const { applicationId } = Route.useParams();
  return <ApplicationDetailPage applicationId={applicationId} />;
}
