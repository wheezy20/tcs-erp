import { Link, useRouterState } from "@tanstack/react-router";
import {
  LayoutDashboard,
  Users,
  Package,
  ReceiptText,
  FileText,
  ShoppingCart,
  HandCoins,
  Wallet,
  Vault,
  BarChart3,
  BookOpen,
  Landmark,
  Truck,
  Settings,
  ChevronLeft,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/data/auth-store";

export const navItems = [
  { title: "Dashboard", url: "/", icon: LayoutDashboard },
  { title: "Customers", url: "/customers", icon: Users },
  { title: "Inventory", url: "/inventory", icon: Package },
  { title: "Sales & Invoicing", url: "/sales", icon: ReceiptText },
  { title: "Pro-forma Invoices", url: "/pro-forma", icon: FileText },
  { title: "Customer Deposits", url: "/customer-deposits", icon: HandCoins },
  { title: "POS", url: "/pos", icon: ShoppingCart },
  { title: "Expenses", url: "/expenses", icon: Wallet },
  { title: "End of Day", url: "/end-of-day", icon: Vault },
  { title: "Reports", url: "/reports", icon: BarChart3 },
  { title: "Accounting", url: "/accounting", icon: BookOpen },
  { title: "Banking", url: "/banking", icon: Landmark },
  { title: "Purchasing", url: "/purchasing", icon: Truck },
  { title: "Settings", url: "/settings", icon: Settings },
] as const;

export function AppSidebar({
  collapsed,
  onToggle,
  onNavigate,
}: {
  collapsed: boolean;
  onToggle?: () => void;
  onNavigate?: () => void;
}) {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { staff: currentStaff } = useAuth();
  // A nicety on top of the real enforcement in routes/reports.tsx (which
  // blocks the page's data even if this link were clicked directly) — an
  // Attendant shouldn't see a nav entry for a page they can't use at all.
  const canViewReports =
    currentStaff?.role === "Manager" || currentStaff?.role === "Accountant/Auditor";
  const isAuditor = currentStaff?.role === "Accountant/Auditor";
  // routes/pos.tsx blocks Accountant/Auditor from Checkout and Returns
  // (pure write screens) but not from Sales history (a read-only view they
  // have as much right to as any other table) — so the nav link itself
  // stays visible, just pointed straight at /pos/history for that role
  // instead of the Checkout screen they'd otherwise land on and immediately
  // bounce off.
  // Chart of Accounts shares the same Manager/Accountant-Auditor-only gate
  // as Reports (routes/accounting.tsx's own guard is the real enforcement).
  const visibleNavItems = navItems
    .filter((item) => item.url !== "/reports" || canViewReports)
    .filter((item) => item.url !== "/accounting" || canViewReports)
    .filter((item) => item.url !== "/banking" || canViewReports)
    .filter((item) => item.url !== "/purchasing" || canViewReports)
    .map((item) => (item.url === "/pos" && isAuditor ? { ...item, url: "/pos/history" } : item));

  const isActive = (url: string) =>
    url === "/" ? pathname === "/" : pathname === url || pathname.startsWith(`${url}/`);

  return (
    <aside
      className={cn(
        "glass-chrome flex h-full flex-col border-r transition-[width] duration-200",
        collapsed ? "w-[72px]" : "w-64",
      )}
    >
      <div className="flex h-16 items-center gap-3 px-4">
        {/* TODO: replace with the real TCS logo once a brand asset exists. */}
        <div
          className="flex size-9 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-bold text-primary-foreground"
          aria-hidden="true"
        >
          TCS
        </div>
        {!collapsed && (
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold leading-tight">TCS</p>
            <p className="truncate text-xs text-muted-foreground">School Suite</p>
          </div>
        )}
      </div>

      <nav className="flex-1 space-y-1 px-3 py-2">
        {visibleNavItems.map((item) => {
          const active = isActive(item.url);
          return (
            <Link
              key={item.url}
              to={item.url}
              onClick={onNavigate}
              title={collapsed ? item.title : undefined}
              className={cn(
                "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
                active
                  ? "bg-sidebar-accent text-sidebar-accent-foreground"
                  : "text-muted-foreground hover:bg-muted hover:text-foreground",
                collapsed && "justify-center px-0",
              )}
            >
              <item.icon className="size-[18px] shrink-0" />
              {!collapsed && <span className="truncate">{item.title}</span>}
            </Link>
          );
        })}
      </nav>

      {onToggle && (
        <div className="border-t border-sidebar-border p-3">
          <Button
            variant="ghost"
            size="sm"
            onClick={onToggle}
            className={cn(
              "w-full justify-start gap-2 text-muted-foreground",
              collapsed && "justify-center",
            )}
          >
            <ChevronLeft className={cn("size-4 transition-transform", collapsed && "rotate-180")} />
            {!collapsed && <span>Collapse</span>}
          </Button>
        </div>
      )}
    </aside>
  );
}
