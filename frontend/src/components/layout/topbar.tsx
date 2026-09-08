import { Fragment, useMemo, useState, type ReactNode } from "react";
import { Link } from "@tanstack/react-router";
import { Bell, Menu, Moon, Search, Sun, Store } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useTheme } from "@/components/theme-provider";
import { matchesProductQuery } from "@/components/product-search-select";
import { signOut, useAuth } from "@/data/auth-store";
import { useCurrentBranch } from "@/data/branch-store";
import { useCustomers } from "@/data/customer-store";
import { useExpenses } from "@/data/expenses-store";
import { useInventory } from "@/data/inventory-store";
import { useInvoices } from "@/data/invoice-store";
import {
  markAllNotificationsRead,
  markNotificationRead,
  useNotifications,
  type AppNotification,
} from "@/data/notifications-store";
import { useSuppliers } from "@/data/suppliers-store";
import { getErrorMessage, cn } from "@/lib/utils";

function initials(name: string) {
  const parts = name.trim().split(/\s+/);
  return ((parts[0]?.[0] ?? "") + (parts[1]?.[0] ?? "")).toUpperCase() || "?";
}

function timeAgo(iso: string) {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function NotificationItem({ notification }: { notification: AppNotification }) {
  const unread = !notification.readAt;

  function onOpen() {
    if (unread) {
      markNotificationRead(notification.id).catch((err) => {
        toast.error(getErrorMessage(err, "Could not mark notification as read."));
      });
    }
  }

  const content = (
    <div className="flex items-start gap-2">
      <span
        className={cn(
          "mt-1.5 size-1.5 shrink-0 rounded-full",
          unread ? "bg-primary" : "bg-transparent",
        )}
      />
      <div className="min-w-0 flex-1">
        <p className={cn("text-sm", unread ? "font-medium" : "font-normal text-muted-foreground")}>
          {notification.title}
        </p>
        <p className="text-xs text-muted-foreground">{notification.body}</p>
        <p className="mt-1 text-[11px] text-muted-foreground">{timeAgo(notification.createdAt)}</p>
      </div>
    </div>
  );

  if (notification.link) {
    return (
      <Link to={notification.link} onClick={onOpen} className="block px-4 py-3 hover:bg-muted/50">
        {content}
      </Link>
    );
  }

  return (
    <button
      type="button"
      onClick={onOpen}
      className="block w-full px-4 py-3 text-left hover:bg-muted/50"
    >
      {content}
    </button>
  );
}

export function Topbar({ onOpenMenu }: { onOpenMenu: () => void }) {
  const { theme, toggleTheme } = useTheme();
  const { name: branchName } = useCurrentBranch();
  const { staff } = useAuth();
  const { notifications } = useNotifications();
  const { customers } = useCustomers();
  const { products } = useInventory();
  const { invoices } = useInvoices();
  const { expenses } = useExpenses();
  const { suppliers } = useSuppliers();
  const [query, setQuery] = useState("");
  const unreadCount = notifications.filter((n) => !n.readAt).length;
  const search = query.trim().toLowerCase();

  // These mirror the matching rules already used on the individual list pages.
  // Product matching is deliberately delegated to the shared helper so the global
  // search finds the same name/SKU/category/size matches as inventory and POS.
  const results = useMemo(() => {
    if (!search) return null;
    const compactQuery = search.replace(/\s/g, "");
    return {
      customers: customers.filter(
        (customer) =>
          customer.name.toLowerCase().includes(search) ||
          customer.phone.replace(/\s/g, "").includes(compactQuery) ||
          customer.email.toLowerCase().includes(search),
      ),
      products: products.filter((product) => matchesProductQuery(product, search)),
      invoices: invoices.filter(
        (invoice) =>
          invoice.id.toLowerCase().includes(search) ||
          invoice.customerName.toLowerCase().includes(search),
      ),
      expenses: expenses.filter(
        (expense) =>
          expense.description.toLowerCase().includes(search) ||
          expense.category.toLowerCase().includes(search) ||
          expense.recordedBy.toLowerCase().includes(search) ||
          expense.id.toLowerCase().includes(search) ||
          (expense.reference ?? "").toLowerCase().includes(search),
      ),
      suppliers: suppliers.filter(
        (supplier) =>
          supplier.name.toLowerCase().includes(search) || supplier.phone.includes(search),
      ),
    };
  }, [customers, expenses, invoices, products, search, suppliers]);

  const hasResults = results && Object.values(results).some((group) => group.length > 0);
  const clearSearch = () => setQuery("");

  return (
    <header className="glass-chrome sticky top-0 z-20 flex h-16 items-center gap-3 border-b px-4 md:px-6">
      <Button
        variant="ghost"
        size="icon"
        className="lg:hidden"
        onClick={onOpenMenu}
        aria-label="Open menu"
      >
        <Menu className="size-5" />
      </Button>

      <div className="relative hidden max-w-md flex-1 sm:block">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search customers, products, invoices…"
          className="h-10 rounded-xl pl-9"
          aria-label="Search records"
          aria-expanded={Boolean(results)}
          aria-controls="global-search-results"
        />
        {results && (
          <div
            id="global-search-results"
            className="absolute left-0 top-12 z-30 max-h-[70vh] w-full overflow-y-auto rounded-xl border bg-popover p-2 text-popover-foreground shadow-lg"
          >
            {!hasResults ? (
              <p className="px-3 py-5 text-center text-sm text-muted-foreground">
                No records match “{query.trim()}”.
              </p>
            ) : (
              <>
                <SearchGroup label="Customers" items={results.customers}>
                  {(customer) => (
                    <SearchResultLink
                      to="/customers/$customerId"
                      params={{ customerId: customer.id }}
                      primary={customer.name}
                      secondary={customer.phone || customer.email}
                      onOpen={clearSearch}
                    />
                  )}
                </SearchGroup>
                <SearchGroup label="Products" items={results.products}>
                  {(product) => (
                    <SearchResultLink
                      to="/inventory/$productId"
                      params={{ productId: product.id }}
                      primary={product.name}
                      secondary={`${product.sku} · ${product.category}${product.size ? ` · ${product.size}` : ""}`}
                      onOpen={clearSearch}
                    />
                  )}
                </SearchGroup>
                <SearchGroup label="Invoices" items={results.invoices}>
                  {(invoice) => (
                    <SearchResultLink
                      to="/sales/$invoiceId"
                      params={{ invoiceId: invoice.id }}
                      primary={invoice.id}
                      secondary={invoice.customerName}
                      onOpen={clearSearch}
                    />
                  )}
                </SearchGroup>
                <SearchGroup label="Expenses" items={results.expenses}>
                  {(expense) => (
                    <SearchResultLink
                      to="/expenses/$expenseId"
                      params={{ expenseId: expense.id }}
                      primary={expense.description}
                      secondary={`${expense.category} · ${expense.reference ?? expense.id}`}
                      onOpen={clearSearch}
                    />
                  )}
                </SearchGroup>
                <SearchGroup label="Suppliers" items={results.suppliers}>
                  {(supplier) => (
                    <SearchResultLink
                      to="/purchasing/suppliers/$supplierId"
                      params={{ supplierId: supplier.id }}
                      primary={supplier.name}
                      secondary={supplier.phone || supplier.email}
                      onOpen={clearSearch}
                    />
                  )}
                </SearchGroup>
              </>
            )}
          </div>
        )}
      </div>

      <div className="ml-auto flex items-center gap-2">
        <div className="hidden items-center gap-2 rounded-xl border bg-card px-3 py-1.5 text-sm md:flex">
          <Store className="size-4 text-primary" />
          <span className="font-medium">{branchName ?? "…"}</span>
        </div>

        <Popover>
          <PopoverTrigger asChild>
            <Button variant="ghost" size="icon" className="relative" aria-label="Notifications">
              <Bell className="size-5" />
              {unreadCount > 0 && (
                <span className="absolute right-2 top-2 size-2 rounded-full bg-primary" />
              )}
            </Button>
          </PopoverTrigger>
          <PopoverContent align="end" className="w-80 rounded-2xl p-0">
            <div className="flex items-center justify-between border-b px-4 py-3">
              <p className="text-sm font-semibold">Notifications</p>
              <div className="flex items-center gap-2">
                {unreadCount > 0 && <Badge variant="secondary">{unreadCount} new</Badge>}
                {unreadCount > 0 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 text-xs font-normal text-muted-foreground hover:text-foreground"
                    onClick={() =>
                      markAllNotificationsRead().catch((err) => {
                        toast.error(getErrorMessage(err, "Could not mark notifications as read."));
                      })
                    }
                  >
                    Mark all read
                  </Button>
                )}
              </div>
            </div>
            {notifications.length === 0 ? (
              <p className="px-4 py-6 text-center text-sm text-muted-foreground">
                No notifications yet.
              </p>
            ) : (
              <ul className="max-h-96 divide-y overflow-y-auto">
                {notifications.map((n) => (
                  <li key={n.id}>
                    <NotificationItem notification={n} />
                  </li>
                ))}
              </ul>
            )}
          </PopoverContent>
        </Popover>

        <Button variant="ghost" size="icon" onClick={toggleTheme} aria-label="Toggle theme">
          {theme === "dark" ? <Sun className="size-5" /> : <Moon className="size-5" />}
        </Button>

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="flex items-center gap-2 rounded-xl p-1 transition-colors hover:bg-muted">
              <Avatar className="size-8">
                <AvatarFallback className="bg-primary text-xs font-semibold text-primary-foreground">
                  {staff ? initials(staff.name) : "?"}
                </AvatarFallback>
              </Avatar>
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel>
              <p className="text-sm font-medium">{staff?.name ?? "…"}</p>
              <p className="text-xs font-normal text-muted-foreground">{staff?.role ?? ""}</p>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem>Profile</DropdownMenuItem>
            <DropdownMenuItem>Preferences</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              onClick={() => {
                signOut().catch((err) => {
                  toast.error(err instanceof Error ? err.message : "Could not sign out.");
                });
              }}
            >
              Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}

function SearchGroup<T extends { id: string }>({
  label,
  items,
  children,
}: {
  label: string;
  items: T[];
  children: (item: T) => ReactNode;
}) {
  if (items.length === 0) return null;
  return (
    <section className="py-1">
      <p className="px-2 py-1 text-xs font-medium text-muted-foreground">{label}</p>
      {items.slice(0, 8).map((item) => (
        <Fragment key={item.id}>{children(item)}</Fragment>
      ))}
    </section>
  );
}

function SearchResultLink({
  to,
  params,
  primary,
  secondary,
  onOpen,
}: {
  to: string;
  params: Record<string, string>;
  primary: string;
  secondary: string;
  onOpen: () => void;
}) {
  return (
    <Link
      // The path/parameter pairs above are generated routes. This small wrapper
      // keeps the result presentation consistent across each record type.
      to={to as never}
      params={params as never}
      onClick={onOpen}
      className="block rounded-lg px-2 py-2 hover:bg-muted"
    >
      <p className="truncate text-sm font-medium">{primary}</p>
      <p className="truncate text-xs text-muted-foreground">{secondary}</p>
    </Link>
  );
}
