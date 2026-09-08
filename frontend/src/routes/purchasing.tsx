import { createFileRoute, Link, Outlet, useRouterState } from "@tanstack/react-router";
import { Truck } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { useAuth } from "@/data/auth-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/purchasing")({
  head: () => ({
    meta: [
      { title: "Purchasing — TCS" },
      {
        name: "description",
        content: "Suppliers, purchase orders, and goods received.",
      },
    ],
  }),
  component: PurchasingLayout,
});

const TABS = [
  { to: "/purchasing", label: "Purchase Orders", exact: true },
  { to: "/purchasing/suppliers", label: "Suppliers", exact: false },
] as const;

function PurchasingLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { staff: currentStaff } = useAuth();
  const canView = currentStaff?.role === "Manager" || currentStaff?.role === "Accountant/Auditor";

  return (
    <div>
      <PageHeader
        title="Purchasing"
        description="Suppliers, purchase orders, and goods received — tied into Accounts Payable."
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

      {/* Same shape as Accounting/Banking/Reports' route guard: Suppliers &
          Purchasing isn't in Attendant's spec-granted module list, so this
          shows nothing for that role rather than a restricted view. RLS's
          own select policies are the real enforcement underneath. */}
      {canView ? (
        <Outlet />
      ) : (
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <Truck className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">Purchasing isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            Purchasing is restricted to Managers and Accountants/Auditors. Ask a Manager or
            Accountant/Auditor if you need something from here.
          </p>
        </div>
      )}
    </div>
  );
}
