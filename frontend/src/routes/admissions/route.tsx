import { Fragment } from "react";
import { createFileRoute, Outlet } from "@tanstack/react-router";

import { useAuth } from "@/data/auth-store";
import { RoleBlockedPanel } from "@/modules/admissions/components/role-blocked-panel";
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
      <RoleBlockedPanel
        title="Admissions"
        description="Inquiries and applications."
        what="Admissions"
        openTo="Managers, Auditors and Admissions Officers"
      />
    );
  }
  return (
    <Fragment key={staff.id}>
      <Outlet />
    </Fragment>
  );
}
