import { createFileRoute, Outlet } from "@tanstack/react-router";
import { Contact } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { canViewFinancials, useAuth } from "@/data/auth-store";

export const Route = createFileRoute("/staff")({
  head: () => ({
    meta: [
      { title: "Login accounts — TCS" },
      {
        name: "description",
        content:
          "ERP login accounts: name, role, active status and the linked employee record, for everyone who can sign in to TCS ERP.",
      },
    ],
  }),
  component: LoginAccountsLayout,
});

// Manager / Accountant / Auditor can view (canViewFinancials — the
// non-Attendant back-office triple). Attendants still read `staff` names
// via RLS everywhere "Recorded by" appears; they just don't get this page.
function LoginAccountsLayout() {
  const { staff } = useAuth();
  const canView = canViewFinancials(staff?.role);

  if (!canView) {
    return (
      <div>
        <PageHeader title="Login accounts" description="ERP sign-in accounts." />
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <Contact className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Login accounts aren't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            It's open to Managers, Accountants and Auditors.
          </p>
        </div>
      </div>
    );
  }

  return <Outlet />;
}
