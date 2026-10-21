import { useState } from "react";
import { Link } from "@tanstack/react-router";
import { RefreshCw } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RoleBlockedPanel } from "@/modules/admissions/components/role-blocked-panel";
import { listLeads, type LeadRow } from "@/modules/admissions/data/leads";
import { useAdmissionsAccess } from "@/modules/admissions/hooks/use-admissions-access";
import { useLoad } from "@/modules/admissions/hooks/use-load";
import {
  LEADS_PAGE_SIZE,
  consentLabel,
  leadSourceLabel,
  pageRangeLabel,
  utmSummary,
} from "@/modules/admissions/leads";
import { canViewAdmissionsLeads, leadContactsMasked } from "@/modules/admissions/permissions";

const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

/** /admissions/leads (slice 13). People who asked for the Admissions
 * Overview and Fees PDF on the school website. Manager and Admissions
 * Officer see every field; the Auditor sees email and phone masked (the
 * database masks them). Every other role gets the blocked panel and the
 * content (with its query) never mounts. ?lead=<id> shows one lead, the
 * staff alert's link. */
export function AdmissionsLeadsPage({ leadId }: { leadId?: string }) {
  const { role } = useAdmissionsAccess();
  if (!canViewAdmissionsLeads(role)) {
    return (
      <RoleBlockedPanel
        title="Admissions leads"
        description="People who asked for the Admissions Overview on the school website."
        what="Admissions leads"
        openTo="Managers, Admissions Officers and Auditors"
      />
    );
  }
  return <LeadsContent masked={leadContactsMasked(role)} leadId={leadId} />;
}

function LeadsContent({ masked, leadId }: { masked: boolean; leadId?: string }) {
  const [offset, setOffset] = useState(0);
  const leads = useLoad(
    () => listLeads({ limit: LEADS_PAGE_SIZE, offset: leadId ? 0 : offset, leadId }),
    [offset, leadId],
    "Could not load the leads.",
  );
  const rows = leads.data?.rows ?? [];
  const total = leads.data?.total ?? 0;

  return (
    <>
      <PageHeader
        title="Admissions leads"
        description="People who asked for the Admissions Overview and Fees document on the school website."
        actions={
          <Button variant="outline" size="sm" onClick={leads.reload} disabled={leads.loading}>
            <RefreshCw className="size-4" /> Refresh
          </Button>
        }
      />
      <section className="card-surface overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 border-b p-6">
          <div>
            <h2 className="text-sm font-semibold">{leadId ? "One lead" : "Leads"}</h2>
            <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
              Newest first. A lead without marketing consent is deleted 12 months after it came in,
              one with consent after 24 months, and an unsubscribed lead at the next daily cleanup.
              {masked && " Email addresses and phone numbers are partly hidden for your role."}
            </p>
          </div>
          {leadId && (
            <Button asChild variant="outline" size="sm">
              <Link to="/admissions/leads" search={{}}>
                Show all leads
              </Link>
            </Button>
          )}
        </div>
        {leads.error && <p className="px-6 py-4 text-sm text-destructive">{leads.error}</p>}
        {leads.data && rows.length === 0 && (
          <p className="px-6 py-8 text-center text-sm text-muted-foreground">
            {leadId
              ? "This lead is no longer on record. It may have been deleted under the retention rules."
              : "No leads yet."}
          </p>
        )}
        {rows.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-4 py-2 font-medium">Received</th>
                  <th className="px-4 py-2 font-medium">Name</th>
                  <th className="px-4 py-2 font-medium">Email</th>
                  <th className="px-4 py-2 font-medium">Phone</th>
                  <th className="px-4 py-2 font-medium">Grade of interest</th>
                  <th className="px-4 py-2 font-medium">Marketing</th>
                  <th className="px-4 py-2 font-medium">Source</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((r) => (
                  <LeadTableRow key={r.id} row={r} highlighted={r.id === leadId} />
                ))}
              </tbody>
            </table>
          </div>
        )}
        {!leadId && leads.data && (rows.length > 0 || offset > 0) && (
          <div className="flex flex-wrap items-center justify-between gap-4 border-t px-6 py-3">
            <p className="text-xs text-muted-foreground">
              {pageRangeLabel(offset, rows.length, total)}
            </p>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={offset === 0 || leads.loading}
                onClick={() => setOffset(Math.max(0, offset - LEADS_PAGE_SIZE))}
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={offset + rows.length >= total || leads.loading}
                onClick={() => setOffset(offset + LEADS_PAGE_SIZE)}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </section>
    </>
  );
}

function LeadTableRow({ row, highlighted }: { row: LeadRow; highlighted: boolean }) {
  const utm = utmSummary(row);
  return (
    <tr className={highlighted ? "bg-muted/40" : undefined}>
      <td className="whitespace-nowrap px-4 py-3 align-top">
        {dateTime.format(new Date(row.createdAt))}
      </td>
      <td className="px-4 py-3 align-top">{row.name}</td>
      <td className="px-4 py-3 align-top font-mono text-xs">{row.email ?? ""}</td>
      <td className="whitespace-nowrap px-4 py-3 align-top font-mono text-xs">{row.phone ?? ""}</td>
      <td className="px-4 py-3 align-top">{row.gradeInterest ?? ""}</td>
      <td className="px-4 py-3 align-top">
        <Badge variant={row.consentToMarketing && !row.unsubscribedAt ? "secondary" : "outline"}>
          {consentLabel(row.consentToMarketing, row.unsubscribedAt)}
        </Badge>
      </td>
      <td className="px-4 py-3 align-top">
        {leadSourceLabel(row.source)}
        {utm && <p className="mt-1 text-xs text-muted-foreground">{utm}</p>}
      </td>
    </tr>
  );
}
