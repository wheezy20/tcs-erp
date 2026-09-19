import { useState } from "react";
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
  Coins,
  Contact,
  IdCard,
  Settings,
  ChevronLeft,
  ChevronDown,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { canViewFinancials, useAuth } from "@/data/auth-store";

type NavItem = { title: string; url: string; icon: LucideIcon };

const DASHBOARD_ITEM: NavItem = { title: "Dashboard", url: "/", icon: LayoutDashboard };
const SETTINGS_ITEM: NavItem = { title: "Settings", url: "/settings", icon: Settings };

// TCS runs Finance/HR day to day; Procurement & Stores exists for a future
// retail/canteen operation that isn't running yet (see the dormant section
// below) — this grouping is what actually distinguishes "what TCS uses"
// from "what the fork inherited," which a flat alphabetical-ish list never
// could. The next real module (Transport, Kitchen, Asset Management,
// Analytics & BI, ...) gets its own section here the same way, once it's an
// actual route — see docs/DESIGN.md.
export const navSections: { key: string; label: string; dormant?: boolean; items: NavItem[] }[] = [
  {
    key: "finance",
    label: "Finance & Accounting",
    items: [
      { title: "Accounting", url: "/accounting", icon: BookOpen },
      { title: "Expenses", url: "/expenses", icon: Wallet },
      { title: "Banking", url: "/banking", icon: Landmark },
      { title: "Reports", url: "/reports", icon: BarChart3 },
    ],
  },
  {
    key: "hr",
    label: "HR & Payroll",
    items: [
      { title: "Employees", url: "/employees", icon: IdCard },
      { title: "Payroll", url: "/payroll", icon: Coins },
      { title: "Login Accounts", url: "/staff", icon: Contact },
    ],
  },
  {
    key: "stores",
    label: "Procurement & Stores · not yet in use",
    dormant: true,
    items: [
      { title: "Customers", url: "/customers", icon: Users },
      { title: "Inventory", url: "/inventory", icon: Package },
      { title: "Sales & Invoicing", url: "/sales", icon: ReceiptText },
      { title: "Pro-forma Invoices", url: "/pro-forma", icon: FileText },
      { title: "Customer Deposits", url: "/customer-deposits", icon: HandCoins },
      { title: "POS", url: "/pos", icon: ShoppingCart },
      { title: "End of Day", url: "/end-of-day", icon: Vault },
      { title: "Purchasing", url: "/purchasing", icon: Truck },
    ],
  },
];

// Every route gated behind the same Manager/Accountant/Auditor view as
// Reports — each route's own guard + RLS on its tables is the real
// enforcement, this only hides the link. Expenses joined this list
// `20260919` — expenses_select's RLS is the same Manager/Accountant/
// Auditor gate as everything else here, but the nav link stayed visible
// to Attendant regardless, leaving a permanently empty page instead of
// the link just not being there (see docs/JOURNAL.md).
const FINANCE_GATED_URLS = new Set([
  "/reports",
  "/accounting",
  "/expenses",
  "/payroll",
  "/banking",
  "/purchasing",
  "/employees",
  "/staff",
]);

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
  const canViewGated = canViewFinancials(currentStaff?.role);
  // Read-only roles for the operational POS screens: routes/pos.tsx blocks
  // both from Checkout/Returns, so the nav link points them at Sales
  // history instead of the Checkout screen they'd land on and bounce off.
  const posReadOnly = currentStaff?.role === "Auditor" || currentStaff?.role === "Accountant";
  const [storesOpen, setStoresOpen] = useState(false);

  const isActive = (url: string) =>
    url === "/" ? pathname === "/" : pathname === url || pathname.startsWith(`${url}/`);

  const visibleItems = (items: NavItem[]) =>
    items
      .filter((item) => !FINANCE_GATED_URLS.has(item.url) || canViewGated)
      .map((item) =>
        item.url === "/pos" && posReadOnly ? { ...item, url: "/pos/history" } : item,
      );

  const sections = navSections
    .map((section) => ({ ...section, items: visibleItems(section.items) }))
    .filter((section) => section.items.length > 0);

  // The active route can be inside the dormant section (a direct link, a
  // bookmark, or a deep link from elsewhere in the app) while it's
  // collapsed — force it open rather than hiding the one thing that
  // explains where the user currently is.
  const storesSection = sections.find((s) => s.key === "stores");
  const storesHasActive = storesSection?.items.some((item) => isActive(item.url)) ?? false;
  const showStoresItems = storesOpen || storesHasActive;

  function renderLink(item: NavItem, muted?: boolean) {
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
            : muted
              ? "text-muted-foreground/70 hover:bg-muted hover:text-foreground"
              : "text-muted-foreground hover:bg-muted hover:text-foreground",
          collapsed && "justify-center px-0",
        )}
      >
        <item.icon className="size-[18px] shrink-0" />
        {!collapsed && <span className="truncate">{item.title}</span>}
      </Link>
    );
  }

  return (
    <aside
      className={cn(
        "glass-chrome flex h-full flex-col border-r transition-[width] duration-200",
        collapsed ? "w-[72px]" : "w-64",
      )}
    >
      <div className="flex h-16 items-center gap-3 px-4">
        <img
          src="/tcs-logomark.png"
          alt="TCS"
          className="size-9 shrink-0 rounded-md bg-white object-contain p-1"
        />
        {!collapsed && (
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold leading-tight">TCS</p>
            <p className="truncate text-xs text-muted-foreground">School Suite</p>
          </div>
        )}
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-2">
        {renderLink(DASHBOARD_ITEM)}

        {collapsed
          ? // No room for section labels/collapsing in the icon rail — every
            // item stays one click away, flat, exactly like before this
            // reorg. The dormant section's de-emphasis is a full-width-
            // sidebar affordance only.
            sections.map((section) => section.items.map((item) => renderLink(item)))
          : sections.map((section) =>
              section.dormant ? (
                <div key={section.key} className="pt-2">
                  <button
                    type="button"
                    onClick={() => setStoresOpen((o) => !o)}
                    className="flex w-full items-center justify-between rounded-lg px-3 py-1.5 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/70 hover:text-muted-foreground"
                  >
                    <span className="truncate">{section.label}</span>
                    <ChevronDown
                      className={cn(
                        "size-3.5 shrink-0 transition-transform",
                        showStoresItems && "rotate-180",
                      )}
                    />
                  </button>
                  {showStoresItems && (
                    <div className="mt-1 space-y-1">
                      {section.items.map((item) => renderLink(item, true))}
                    </div>
                  )}
                </div>
              ) : (
                <div key={section.key} className="pt-2">
                  <p className="px-3 pb-1 pt-1 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/70">
                    {section.label}
                  </p>
                  <div className="space-y-1">{section.items.map((item) => renderLink(item))}</div>
                </div>
              ),
            )}
      </nav>

      <div className="border-t border-sidebar-border px-3 py-2">{renderLink(SETTINGS_ITEM)}</div>

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
