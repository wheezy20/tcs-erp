import { createFileRoute, Link, Outlet, useRouterState } from "@tanstack/react-router";

import { PageHeader } from "@/components/page-header";
import { useCurrentBranch } from "@/data/branch-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/end-of-day")({
  head: () => ({
    meta: [
      { title: "End of Day — TCS" },
      {
        name: "description",
        content:
          "Daily cash reconciliation: opening float, sales by payment method, cash variance, and Manager sign-off.",
      },
    ],
  }),
  component: EndOfDayLayout,
});

const TABS = [
  { to: "/end-of-day", label: "Today", exact: true },
  { to: "/end-of-day/history", label: "History", exact: false },
  { to: "/end-of-day/deposits", label: "Deposits", exact: false },
] as const;

function EndOfDayLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { name: branchName } = useCurrentBranch();

  return (
    <div>
      <PageHeader
        title="End of Day"
        description={`Cash reconciliation for the ${branchName ?? "…"}.`}
        actions={
          <div className="flex rounded-xl border border-border bg-card p-1">
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
        }
      />
      <Outlet />
    </div>
  );
}
