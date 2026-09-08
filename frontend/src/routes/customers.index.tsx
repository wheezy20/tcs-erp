import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Search, Users } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Input } from "@/components/ui/input";
import { AddCustomerDialog } from "@/components/customers/add-customer-dialog";
import { ImportCustomersDialog } from "@/components/customers/import-customers-dialog";
import { ExportMenu } from "@/components/export-menu";
import { SortableTh } from "@/components/sortable-th";
import { useCurrentBranch } from "@/data/branch-store";
import { useCustomers } from "@/data/customer-store";
import type { Customer } from "@/data/customers";
import { currency } from "@/data/dashboard";
import { cn } from "@/lib/utils";
import { useSort } from "@/lib/use-sort";

type CustomerSortKey = "name" | "balance";

const customerSortAccessors: Record<CustomerSortKey, (c: Customer) => string | number> = {
  name: (c) => c.name,
  balance: (c) => c.balance,
};

export const Route = createFileRoute("/customers/")({
  head: () => ({
    meta: [
      { title: "Customers — TCS" },
      {
        name: "description",
        content: "Search customers, view outstanding balances and lifetime purchases in GHS.",
      },
      { property: "og:title", content: "Customers — TCS" },
      {
        property: "og:description",
        content: "Search customers, view outstanding balances and lifetime purchases in GHS.",
      },
    ],
  }),
  component: CustomersPage,
});

function CustomersPage() {
  const { customers: list } = useCustomers();
  const { name: branchName } = useCurrentBranch();
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (c) =>
        c.name.toLowerCase().includes(q) ||
        c.phone.replace(/\s/g, "").includes(q.replace(/\s/g, "")) ||
        c.email.toLowerCase().includes(q),
    );
  }, [list, query]);

  const { sortKey, sortDirection, toggleSort, sorted } = useSort<Customer, CustomerSortKey>(
    filtered,
    customerSortAccessors,
  );

  const owing = list.filter((c) => c.balance > 0);
  const totalOutstanding = owing.reduce((sum, c) => sum + c.balance, 0);

  return (
    <>
      <PageHeader
        title="Customers"
        description={`Contacts, balances and purchase history across the ${branchName ?? "…"}.`}
        actions={
          <>
            <ExportMenu
              baseName="customers"
              filters={[query]}
              summary={`${filtered.length} of ${list.length} customers, as filtered`}
              disabled={filtered.length === 0}
              getSheets={() => [
                {
                  name: "Customers",
                  columns: [
                    { header: "Name", value: (c: Customer) => c.name },
                    { header: "Customer type", value: (c: Customer) => c.type },
                    { header: "Customer since", value: (c: Customer) => c.since },
                    { header: "Phone", value: (c: Customer) => c.phone },
                    { header: "Email", value: (c: Customer) => c.email },
                    { header: "Address", value: (c: Customer) => c.address },
                    { header: "Outstanding balance (GHS)", value: (c: Customer) => c.balance },
                    { header: "Lifetime purchases (GHS)", value: (c: Customer) => c.lifetime },
                  ],
                  rows: filtered,
                },
              ]}
            />
            <ImportCustomersDialog />
            <AddCustomerDialog />
          </>
        }
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard
          label="Total customers"
          value={String(list.length)}
          hint="Retail, contractor & wholesale"
        />
        <SummaryCard
          label="Customers owing"
          value={String(owing.length)}
          hint="With an open balance"
        />
        <SummaryCard
          label="Total outstanding"
          value={currency(totalOutstanding)}
          hint="Across unpaid & part-paid invoices"
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="border-b p-4">
          <div className="relative max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by name, phone or email"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <Users className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No customers match “{query}”</p>
            <p className="text-sm text-muted-foreground">Try a different name or phone number.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <SortableTh<CustomerSortKey>
                    label="Name"
                    sortKeyValue="name"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                  />
                  <th className="px-5 py-3 font-medium">Phone</th>
                  <SortableTh<CustomerSortKey>
                    label="Outstanding balance"
                    sortKeyValue="balance"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                    align="right"
                  />
                  <th className="px-5 py-3 text-right font-medium">Lifetime purchases</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {sorted.map((c) => (
                  <tr key={c.id} className="group hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/customers/$customerId"
                        params={{ customerId: c.id }}
                        className="font-medium group-hover:text-primary"
                      >
                        {c.name}
                      </Link>
                      <p className="text-xs text-muted-foreground">
                        {c.type} · since {c.since}
                      </p>
                    </td>
                    <td className="px-5 py-3 tabular-nums text-muted-foreground">{c.phone}</td>
                    <td className="px-5 py-3 text-right">
                      <span
                        className={cn(
                          "inline-flex rounded-lg px-2 py-0.5 text-xs font-medium tabular-nums",
                          c.balance > 0
                            ? "bg-destructive/10 text-destructive"
                            : "bg-accent text-accent-foreground",
                        )}
                      >
                        {c.balance > 0 ? currency(c.balance) : "Settled"}
                      </span>
                    </td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(c.lifetime)}
                    </td>
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
      <p className="mt-2 text-2xl font-semibold tracking-tight">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
