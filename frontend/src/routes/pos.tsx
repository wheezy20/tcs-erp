import { createFileRoute, Link, Outlet, useRouterState } from "@tanstack/react-router";
import { ShoppingCart } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { useAuth } from "@/data/auth-store";
import { useCurrentBranch } from "@/data/branch-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/pos")({
  head: () => ({
    meta: [
      { title: "POS — TCS" },
      {
        name: "description",
        content:
          "Counter checkout for walk-in customers: product grid, split payments, receipts, returns and exchanges.",
      },
      { property: "og:title", content: "POS — TCS" },
      {
        property: "og:description",
        content: "Fast till screen with cart, discounts, VAT, split payments and receipt preview.",
      },
    ],
  }),
  component: PosLayout,
});

const TABS = [
  { to: "/pos", label: "Checkout", exact: true },
  { to: "/pos/returns", label: "Returns & exchange", exact: false },
  { to: "/pos/history", label: "Sales history", exact: false },
] as const;

function PosLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { name: branchName } = useCurrentBranch();
  const { staff: currentStaff } = useAuth();

  // Accountant/Auditor is read-only everywhere (role-permissions-rewrite
  // migration). Checkout and Returns are pure write screens — every action
  // either makes is already rejected server-side, so there's no legitimate
  // reason to be there at all (same access-denied pattern as
  // routes/reports.tsx's Attendant guard). Sales history is different: it's
  // a read-only view over the same `sales` table Accountant/Auditor can
  // already read everywhere else, so it's deliberately NOT blocked here —
  // only /pos and /pos/returns are, by pathname, not the whole section.
  const isWriteScreen = pathname === "/pos" || pathname.startsWith("/pos/returns");
  const blocked = currentStaff?.role === "Accountant/Auditor" && isWriteScreen;

  return (
    <div>
      <PageHeader
        title="Point of Sale"
        description={`${branchName ?? "…"} · ${currentStaff?.name ?? "…"}`}
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
      {blocked ? (
        <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
          <ShoppingCart className="size-8 text-muted-foreground" />
          <h2 className="text-lg font-semibold">POS isn't available for this role</h2>
          <p className="max-w-sm text-sm text-muted-foreground">
            Accountant/Auditor is read-only everywhere — every checkout, return and exchange here is
            already rejected server-side, so there's nothing this screen can do for that role. Ask a
            Manager or Attendant if a sale or return needs to be made, or open Sales history above
            to read past receipts.
          </p>
        </div>
      ) : (
        <Outlet />
      )}
    </div>
  );
}
