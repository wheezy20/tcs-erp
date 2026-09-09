import { createFileRoute, Outlet } from "@tanstack/react-router";
import { IdCard } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { canViewFinancials, useAuth } from "@/data/auth-store";

export const Route = createFileRoute("/employees")({
  head: () => ({
    meta: [
      { title: "Employees — TCS" },
      {
        name: "description",
        content:
          "Everyone TCS pays — employment status, pay configuration and the propose / approve workflow for new records, salary changes and bank details.",
      },
    ],
  }),
  component: EmployeesLayout,
});

// Manager / Accountant / Auditor can view (canViewFinancials). Accountant
// proposes; Manager approves/rejects; Auditor is read-only. RLS on
// `employees` / `employee_pay_config` + the SECURITY DEFINER RPCs are the
// real enforcement — this guard just hides the section from an Attendant.
function EmployeesLayout() {
  const { staff } = useAuth();
  if (!canViewFinancials(staff?.role)) {
    return (
      <div>
        <PageHeader title="Employees" description="Paid personnel and pay configuration." />
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <IdCard className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Employees isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            It's open to Managers, Accountants and Auditors.
          </p>
        </div>
      </div>
    );
  }
  return <Outlet />;
}
