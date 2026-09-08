import { createFileRoute, Link, Outlet, useRouterState } from "@tanstack/react-router";
import { BookOpen } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { useAuth } from "@/data/auth-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/accounting")({
  head: () => ({
    meta: [
      { title: "Accounting — TCS" },
      {
        name: "description",
        content:
          "Chart of accounts, journal entries, the general ledger, and the financial reports built on top of them.",
      },
    ],
  }),
  component: AccountingLayout,
});

const TABS = [
  { to: "/accounting", label: "Chart of Accounts", exact: true },
  { to: "/accounting/journal-entries", label: "Journal Entries", exact: false },
  { to: "/accounting/ledger", label: "General Ledger", exact: false },
  { to: "/accounting/trial-balance", label: "Trial Balance", exact: false },
  { to: "/accounting/balance-sheet", label: "Balance Sheet", exact: false },
  { to: "/accounting/profit-loss", label: "Profit & Loss", exact: false },
  { to: "/accounting/cash-flow", label: "Cash Flow", exact: false },
] as const;

function AccountingLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { staff: currentStaff } = useAuth();
  const canView = currentStaff?.role === "Manager" || currentStaff?.role === "Accountant/Auditor";

  return (
    <div>
      <PageHeader
        title="Accounting"
        description="The chart of accounts, journal entries, general ledger and financial reports behind the books."
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

      {/* Same shape as Reports' route guard (and Session 12's own, now
          moved up here since it applies uniformly to every tab, including
          Session 15's four new financial reports): Accounting isn't in
          Attendant's granted module list, so this shows nothing for that
          role rather than a restricted view. RLS's own select policies are
          the real enforcement on every table underneath; this is what
          makes the section itself say so before any sub-page even tries to
          load data. */}
      {canView ? (
        <Outlet />
      ) : (
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <BookOpen className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Accounting isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            Accounting is restricted to Managers and Accountants/Auditors. Ask a Manager or
            Accountant/Auditor if you need something from here.
          </p>
        </div>
      )}
    </div>
  );
}
