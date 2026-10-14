import { Fragment } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { ScrollText } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { useAuth } from "@/data/auth-store";
import { AuditLogPage } from "@/modules/audit/components/audit-log-page";
import { canViewAuditLog } from "@/modules/audit/permissions";

export const Route = createFileRoute("/audit-log/")({
  head: () => ({
    meta: [
      { title: "Audit Log | TCS" },
      { name: "description", content: "Recorded changes across TCS ERP." },
    ],
  }),
  component: AuditLogRoute,
});

// Manager, Accountant and Auditor only. audit_log_select is the real
// enforcement; this keeps other roles from mounting a page that would load
// nothing. The key remounts the page when a different user signs in.
function AuditLogRoute() {
  const { staff } = useAuth();
  if (!staff || !canViewAuditLog(staff.role)) {
    return (
      <div>
        <PageHeader title="Audit Log" description="Recorded changes across TCS ERP." />
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <ScrollText className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">The Audit Log isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            It's open to Managers, Accountants and Auditors.
          </p>
        </div>
      </div>
    );
  }
  return (
    <Fragment key={staff.id}>
      <AuditLogPage role={staff.role} />
    </Fragment>
  );
}
