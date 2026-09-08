import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { HandCoins, Search } from "lucide-react";

import { RecordDepositDialog } from "@/components/deposits/record-deposit-dialog";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useCurrentBranch } from "@/data/branch-store";
import { useCustomerDeposits, type CustomerDepositStatus } from "@/data/customer-deposits-store";
import { currency } from "@/data/dashboard";

export const Route = createFileRoute("/customer-deposits/")({
  head: () => ({
    meta: [
      { title: "Customer Deposits — TCS" },
      {
        name: "description",
        content:
          "Money taken up front to reserve goods for a customer, with the balance collected at hand-over.",
      },
    ],
  }),
  component: CustomerDepositsListPage,
});

export function statusBadge(status: CustomerDepositStatus) {
  if (status === "Fulfilled") return <Badge variant="secondary">Fulfilled</Badge>;
  if (status === "Cancelled")
    return (
      <Badge variant="outline" className="border-amber-500/40 text-amber-600 dark:text-amber-400">
        Cancelled
      </Badge>
    );
  return <Badge className="bg-primary/15 text-primary hover:bg-primary/15">Open</Badge>;
}

function CustomerDepositsListPage() {
  const { deposits } = useCustomerDeposits();
  const { name: branchName } = useCurrentBranch();
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("all");

  const rows = useMemo(
    () => [...deposits].sort((a, b) => (a.takenAt < b.takenAt ? 1 : -1)),
    [deposits],
  );

  const filtered = rows.filter((d) => {
    const q = query.trim().toLowerCase();
    const matchesQuery =
      !q ||
      d.id.toLowerCase().includes(q) ||
      d.customerName.toLowerCase().includes(q) ||
      d.description.toLowerCase().includes(q);
    const matchesStatus = status === "all" || d.status === status;
    return matchesQuery && matchesStatus;
  });

  const openRows = rows.filter((d) => d.status === "Open");
  const openValue = openRows.reduce((s, d) => s + d.amount, 0);
  const fulfilledCount = rows.filter((d) => d.status === "Fulfilled").length;

  return (
    <>
      <PageHeader
        title="Customer Deposits"
        description={`Up-front payments reserving goods for the ${branchName ?? "…"} — real money, real liability, balance due at hand-over.`}
        actions={<RecordDepositDialog />}
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard
          label="Open deposits"
          value={String(openRows.length)}
          hint="Awaiting fulfilment or cancellation"
        />
        <SummaryCard
          label="Held for customers"
          value={currency(openValue)}
          hint="Outstanding liability (account 2450)"
        />
        <SummaryCard
          label="Fulfilled"
          value={String(fulfilledCount)}
          hint="Applied to a sale or invoice"
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-56 flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search deposit, customer or description"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
          <Select value={status} onValueChange={setStatus}>
            <SelectTrigger className="h-10 w-40 rounded-xl">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All statuses</SelectItem>
              <SelectItem value="Open">Open</SelectItem>
              <SelectItem value="Fulfilled">Fulfilled</SelectItem>
              <SelectItem value="Cancelled">Cancelled</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <HandCoins className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No deposits match your filters</p>
            <p className="text-sm text-muted-foreground">
              Record one with the button above, or try another status/search.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Deposit</th>
                  <th className="px-5 py-3 font-medium">Customer</th>
                  <th className="px-5 py-3 font-medium">Reserved</th>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((d) => (
                  <tr key={d.id} className="group hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/customer-deposits/$depositId"
                        params={{ depositId: d.id }}
                        className="font-medium group-hover:text-primary"
                      >
                        {d.id}
                      </Link>
                      <p className="text-xs text-muted-foreground">{d.method}</p>
                    </td>
                    <td className="px-5 py-3">{d.customerName}</td>
                    <td className="px-5 py-3 max-w-xs truncate text-muted-foreground">
                      {d.description || "—"}
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{d.takenAt.slice(0, 10)}</td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(d.amount)}
                    </td>
                    <td className="px-5 py-3">{statusBadge(d.status)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function SummaryCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tabular-nums">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
