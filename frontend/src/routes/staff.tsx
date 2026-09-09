import { createFileRoute, Outlet } from "@tanstack/react-router";
import { Contact } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { canViewFinancials, useAuth } from "@/data/auth-store";

export const Route = createFileRoute("/staff")({
  head: () => ({
    meta: [
      { title: "Staff — TCS" },
      {
        name: "description",
        content:
          "Staff directory: role, position, department and active status for everyone with a TCS login, with an editable contact profile per person.",
      },
    ],
  }),
  component: StaffLayout,
});

// Manager / Accountant / Auditor can view the directory (the same
// non-Attendant "back office" set every finance-adjacent section uses —
// canViewFinancials is that exact triple). Editing a profile is
// Manager-only and gated again inside routes/staff.$staffId.tsx and by the
// `staff_update` RLS policy (has_role(['Manager'])). Attendants have no
// directory screen — they still read `staff` names via RLS everywhere
// "Recorded by" appears, they just don't get this page.
function StaffLayout() {
  const { staff } = useAuth();
  const canView = canViewFinancials(staff?.role);

  if (!canView) {
    return (
      <div>
        <PageHeader title="Staff" description="Staff directory and profiles." />
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <Contact className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">
            The staff directory isn't available for this role
          </h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            It's open to Managers, Accountants and Auditors. Ask a Manager if you need a colleague's
            contact details.
          </p>
        </div>
      </div>
    );
  }

  return <Outlet />;
}
