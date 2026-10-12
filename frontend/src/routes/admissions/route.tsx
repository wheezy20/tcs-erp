import { Fragment } from "react";
import { createFileRoute, Outlet } from "@tanstack/react-router";
import { GraduationCap } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { useAuth } from "@/data/auth-store";
import { canViewAdmissions } from "@/modules/admissions/permissions";

export const Route = createFileRoute("/admissions")({
  head: () => ({
    meta: [
      { title: "Admissions | TCS" },
      { name: "description", content: "Inquiries and applications for TCS." },
    ],
  }),
  component: AdmissionsLayout,
});

// Manager, Auditor and Admissions Officer only. RLS on every admissions
// table is the real enforcement; this keeps Attendant and Accountant from
// mounting pages that would only ever load nothing. The key remounts every
// admissions page when a different user signs in, so no page state carries
// over between users.
function AdmissionsLayout() {
  const { staff } = useAuth();
  if (!staff || !canViewAdmissions(staff.role)) {
    return (
      <div>
        <PageHeader title="Admissions" description="Inquiries and applications." />
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <GraduationCap className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Admissions isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            It's open to Managers, Auditors and Admissions Officers.
          </p>
        </div>
      </div>
    );
  }
  return (
    <Fragment key={staff.id}>
      <Outlet />
    </Fragment>
  );
}
