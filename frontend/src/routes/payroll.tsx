import { createFileRoute, Link, Outlet, useRouterState } from "@tanstack/react-router";
import { Coins } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { useAuth } from "@/data/auth-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/payroll")({
  head: () => ({
    meta: [
      { title: "Payroll — TCS" },
      {
        name: "description",
        content:
          "Monthly payroll runs, payslip generation with SSNIT / Tier 2 / PAYE, and staff pay configuration.",
      },
    ],
  }),
  component: PayrollLayout,
});

const TABS = [
  { to: "/payroll", label: "Payroll Runs", exact: true },
  { to: "/payroll/pay-config", label: "Staff Pay Config", exact: false },
] as const;

/** Same Manager + Accountant/Auditor gate as Accounting / Reports —
 * payroll (individual salaries) is not in an Attendant's granted module
 * list. RLS on every payroll table is the real enforcement; this makes
 * the section itself say so before a sub-page tries to load. */
function PayrollLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { staff } = useAuth();
  const canView = staff?.role === "Manager" || staff?.role === "Accountant/Auditor";

  return (
    <div>
      <PageHeader
        title="Payroll"
        description="Monthly payroll runs, payslips, and each staff member's pay configuration."
        actions={
          canView ? (
            <div className="flex flex-wrap gap-1 rounded-xl border border-border bg-card p-1">
              {TABS.map((tab) => {
                const active = tab.exact ? pathname === tab.to : pathname.startsWith(tab.to);
                return (
                  <Link
                    key={tab.to}
                    to={tab.to}
                    className={cn(
                      "rounded-lg px-3.5 py-1.5 text-sm font-medium transition-colors",
                      active
                        ? "bg-primary text-primary-foreground"
                        : "text-muted-foreground hover:text-foreground",
                    )}
                  >
                    {tab.label}
                  </Link>
                );
              })}
            </div>
          ) : undefined
        }
      />

      {canView ? (
        <Outlet />
      ) : (
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <Coins className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Payroll isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            Payroll is restricted to Managers and Accountants/Auditors. Ask a Manager if you need
            something from here.
          </p>
        </div>
      )}
    </div>
  );
}
