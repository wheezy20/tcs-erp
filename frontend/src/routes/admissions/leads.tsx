import { createFileRoute } from "@tanstack/react-router";

import { AdmissionsLeadsPage } from "@/modules/admissions/components/leads-page";
import { parseLeadParam } from "@/modules/admissions/leads";

export const Route = createFileRoute("/admissions/leads")({
  validateSearch: (search: Record<string, unknown>): { lead?: string } => ({
    lead: parseLeadParam(search.lead),
  }),
  component: LeadsRoute,
});

function LeadsRoute() {
  const { lead } = Route.useSearch();
  return <AdmissionsLeadsPage leadId={lead} />;
}
