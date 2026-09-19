import { createFileRoute, Link } from "@tanstack/react-router";
import {
  ArrowUpRight,
  ArrowDownRight,
  TrendingUp,
  AlertTriangle,
  ClipboardCheck,
  Coins,
} from "lucide-react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { useCurrentBranch } from "@/data/branch-store";
import { currency, TODAY, useDashboard, type DashboardKpi } from "@/data/dashboard";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Dashboard — TCS" },
      {
        name: "description",
        content: "Daily sales, monthly revenue, inventory value and cash on hand at a glance.",
      },
      { property: "og:title", content: "Dashboard — TCS" },
      {
        property: "og:description",
        content: "Daily sales, monthly revenue, inventory value and cash on hand at a glance.",
      },
    ],
  }),
  component: Dashboard,
});

// These two are the only KPIs relevant to what TCS actually does day to
// day; everything else in `kpis` is Sales/POS/Inventory-flavored and gets
// demoted into the "Store & Sales" section below, matching the sidebar's
// Finance & Accounting / Procurement & Stores split (20260919).
const PRIMARY_KPI_LABELS = new Set(["Cash on Hand", "Expenses this Month"]);

function Dashboard() {
  const {
    kpis,
    lowStock,
    recentTransactions,
    revenueSeries,
    monthDelta,
    pendingApprovals,
    latestPayrollRun,
    canSeeHrPayrollWidgets,
  } = useDashboard();
  const { name: branchName } = useCurrentBranch();
  // Computed at render time, not module load — a top-level const here would
  // only be as fresh as whenever this module was first evaluated (once per
  // page load, or once per SSR server-process lifetime), not the real
  // current day on every visit.
  const todayLabel = new Date(`${TODAY()}T00:00:00Z`).toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });

  const primaryKpis = kpis.filter((k) => PRIMARY_KPI_LABELS.has(k.label));
  const storeKpis = kpis.filter((k) => !PRIMARY_KPI_LABELS.has(k.label));

  return (
    <>
      <PageHeader title="Dashboard" description={`${todayLabel} · ${branchName ?? "…"}`} />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {primaryKpis.map((kpi) => (
          <KpiCard key={kpi.label} kpi={kpi} />
        ))}

        <div className="card-surface p-5">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <ClipboardCheck className="size-4" /> Pending approvals
          </div>
          <p className="mt-2 text-2xl font-semibold tracking-tight">
            {canSeeHrPayrollWidgets ? pendingApprovals : "—"}
          </p>
          <p className="mt-3 text-xs text-muted-foreground">
            {canSeeHrPayrollWidgets ? (
              <Link to="/employees" className="hover:underline">
                New hires and pay changes awaiting a Manager
              </Link>
            ) : (
              "Visible to Manager, Accountant and Auditor"
            )}
          </p>
        </div>

        <div className="card-surface p-5">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Coins className="size-4" /> Latest payroll run
          </div>
          <p className="mt-2 text-2xl font-semibold tracking-tight">
            {!canSeeHrPayrollWidgets ? "—" : (latestPayrollRun?.label ?? "None yet")}
          </p>
          <p className="mt-3 text-xs text-muted-foreground">
            {!canSeeHrPayrollWidgets ? (
              "Visible to Manager, Accountant and Auditor"
            ) : latestPayrollRun ? (
              <Link
                to="/payroll/$runId"
                params={{ runId: latestPayrollRun.id }}
                className="hover:underline"
              >
                {latestPayrollRun.status}
              </Link>
            ) : (
              <Link to="/payroll" className="hover:underline">
                No payroll run created yet
              </Link>
            )}
          </p>
        </div>
      </div>

      {/* Sales/POS/Inventory — dormant until TCS runs a canteen/uniform-shop
          operation, same framing as the sidebar's "Procurement & Stores ·
          not yet in use". Kept fully visible (not collapsed) here, unlike
          the sidebar: a dashboard is a glance-once-per-visit read, and a
          Manager who does occasionally check these numbers shouldn't need
          an extra click to reveal a whole section every time. */}
      <section className="mt-8 rounded-2xl border border-dashed p-5">
        <p className="mb-4 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/70">
          Store & Sales · not yet in use
        </p>

        <div className="grid gap-4 sm:grid-cols-3">
          {storeKpis.map((kpi) => (
            <KpiCard key={kpi.label} kpi={kpi} muted />
          ))}
        </div>

        <div className="mt-4 grid gap-4 lg:grid-cols-3">
          <div className="card-surface p-5 opacity-80 lg:col-span-2">
            <div className="mb-4 flex items-center justify-between">
              <div>
                <h2 className="text-base font-semibold">Monthly revenue</h2>
                <p className="text-sm text-muted-foreground">Last 12 months, in GHS</p>
              </div>
              <Badge variant="secondary" className="gap-1">
                <TrendingUp className="size-3" /> {monthDelta >= 0 ? "+" : ""}
                {monthDelta}%
              </Badge>
            </div>
            <div className="h-[300px] w-full">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={revenueSeries} margin={{ left: 8, right: 8, top: 8 }}>
                  <defs>
                    <linearGradient id="rev" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="var(--color-chart-1)" stopOpacity={0.45} />
                      <stop offset="100%" stopColor="var(--color-chart-1)" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid
                    strokeDasharray="3 3"
                    stroke="var(--color-border)"
                    vertical={false}
                  />
                  <XAxis dataKey="month" tickLine={false} axisLine={false} fontSize={12} />
                  <YAxis
                    tickLine={false}
                    axisLine={false}
                    fontSize={12}
                    tickFormatter={(v: number) => `${Math.round(v / 1000)}k`}
                  />
                  <Tooltip
                    formatter={(v: number) => [currency(v), "Revenue"]}
                    contentStyle={{
                      borderRadius: 12,
                      border: "1px solid var(--color-border)",
                      background: "var(--color-card)",
                    }}
                  />
                  <Area
                    type="monotone"
                    dataKey="revenue"
                    stroke="var(--color-chart-1)"
                    strokeWidth={2.5}
                    fill="url(#rev)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="card-surface p-5 opacity-80">
            <div className="mb-4 flex items-center gap-2">
              <AlertTriangle className="size-4 text-[color:var(--warning)]" />
              <h2 className="text-base font-semibold">Low stock products</h2>
            </div>
            <ul className="space-y-4">
              {lowStock.map((item) => (
                <li key={item.id}>
                  <Link
                    to="/inventory/$productId"
                    params={{ productId: item.id }}
                    className="flex items-baseline justify-between gap-3 hover:underline"
                  >
                    <p className="truncate text-sm font-medium">{item.name}</p>
                    <p className="shrink-0 text-xs text-muted-foreground">
                      {item.stock}/{item.reorder} {item.unit}
                    </p>
                  </Link>
                  <Progress value={(item.stock / item.reorder) * 100} className="mt-2 h-1.5" />
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="card-surface mt-4 overflow-hidden opacity-80">
          <div className="flex items-center justify-between border-b px-5 py-4">
            <div>
              <h2 className="text-base font-semibold">Recent transactions</h2>
              <p className="text-sm text-muted-foreground">Latest sales and invoices</p>
            </div>
            {/* One "View all" link can't route correctly for a mixed list —
                this preview merges invoices and POS sales, and there's no
                single page in the app showing both together, so a link that
                always went to Sales & Invoicing made a POS sale here exactly
                as unreachable as this fix's other half (the Reference cell
                below) already was. Two explicitly-typed links, rather than
                guessing which module the click "really" meant. */}
            <div className="flex items-center gap-3 text-sm font-medium">
              <Link to="/sales" className="text-primary hover:underline">
                All invoices
              </Link>
              <Link to="/pos/history" className="text-primary hover:underline">
                All POS sales
              </Link>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Reference</th>
                  <th className="px-5 py-3 font-medium">Customer</th>
                  <th className="px-5 py-3 font-medium">Type</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {recentTransactions.map((t) => (
                  <tr key={t.ref} className="hover:bg-muted/40">
                    <td className="px-5 py-3 font-medium">
                      {t.type === "Invoice" ? (
                        <Link
                          to="/sales/$invoiceId"
                          params={{ invoiceId: t.ref }}
                          className="hover:underline"
                        >
                          {t.ref}
                        </Link>
                      ) : (
                        // No per-sale detail route for POS (unlike invoices'
                        // /sales/$invoiceId) — lands on Sales history with
                        // this receipt's number pre-filled into its own
                        // search box, matching href's own /pos/history?q=...
                        // shape above rather than an unfiltered list.
                        <Link to="/pos/history" search={{ q: t.ref }} className="hover:underline">
                          {t.ref}
                        </Link>
                      )}
                    </td>
                    <td className="px-5 py-3">{t.party}</td>
                    <td className="px-5 py-3 text-muted-foreground">{t.type}</td>
                    <td className="px-5 py-3">
                      <StatusBadge status={t.status} />
                    </td>
                    <td className="px-5 py-3 text-right font-medium">{currency(t.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </>
  );
}

function KpiCard({ kpi, muted }: { kpi: DashboardKpi; muted?: boolean }) {
  const up = kpi.delta >= 0;
  const good = kpi.invertDelta ? !up : up;
  return (
    <div className={cn("card-surface p-5", muted && "opacity-80")}>
      <p className="text-sm text-muted-foreground">{kpi.label}</p>
      <p className="mt-2 text-2xl font-semibold tracking-tight">
        {kpi.unavailable ? "—" : currency(kpi.value)}
      </p>
      <div className="mt-3 flex items-center gap-2 text-xs">
        {!kpi.unavailable && kpi.delta !== 0 && (
          <span
            className={cn(
              "inline-flex items-center gap-1 rounded-lg px-1.5 py-0.5 font-medium",
              good ? "bg-accent text-accent-foreground" : "bg-destructive/10 text-destructive",
            )}
          >
            {up ? <ArrowUpRight className="size-3" /> : <ArrowDownRight className="size-3" />}
            {Math.abs(kpi.delta)}%
          </span>
        )}
        <span className="text-muted-foreground">{kpi.hint}</span>
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles =
    status === "Paid"
      ? "bg-accent text-accent-foreground"
      : status === "Partly paid"
        ? "bg-[color:var(--warning)]/15 text-[color:var(--warning-foreground)] dark:text-[color:var(--warning)]"
        : "bg-destructive/10 text-destructive";
  return (
    <span className={cn("inline-flex rounded-lg px-2 py-0.5 text-xs font-medium", styles)}>
      {status}
    </span>
  );
}
