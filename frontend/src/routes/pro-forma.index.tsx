import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { FileText, Plus, Search } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useCurrentBranch } from "@/data/branch-store";
import { currency } from "@/data/dashboard";
import { useProFormaInvoices, type ProFormaStatus } from "@/data/pro-forma-store";

export const Route = createFileRoute("/pro-forma/")({
  head: () => ({
    meta: [
      { title: "Pro-forma Invoices — TCS" },
      {
        name: "description",
        content: "Non-binding quotes that can be converted into a real invoice once accepted.",
      },
    ],
  }),
  component: ProFormaListPage,
});

function statusBadge(status: ProFormaStatus) {
  return status === "converted" ? (
    <Badge variant="secondary">Converted</Badge>
  ) : (
    <Badge className="bg-primary/15 text-primary hover:bg-primary/15">Open</Badge>
  );
}

function ProFormaListPage() {
  const { proFormaInvoices } = useProFormaInvoices();
  const { name: branchName } = useCurrentBranch();
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("all");

  const rows = useMemo(
    () => [...proFormaInvoices].sort((a, b) => (a.date < b.date ? 1 : -1)),
    [proFormaInvoices],
  );

  const filtered = rows.filter((pf) => {
    const q = query.trim().toLowerCase();
    const matchesQuery =
      !q || pf.id.toLowerCase().includes(q) || pf.customerName.toLowerCase().includes(q);
    const matchesStatus = status === "all" || pf.status === status;
    return matchesQuery && matchesStatus;
  });

  const openCount = rows.filter((pf) => pf.status === "open").length;
  const convertedCount = rows.filter((pf) => pf.status === "converted").length;
  const quotedValue = rows.filter((pf) => pf.status === "open").reduce((s, pf) => s + pf.total, 0);

  return (
    <>
      <PageHeader
        title="Pro-forma Invoices"
        description={`Non-binding quotes for the ${branchName ?? "…"} — no stock or ledger impact until converted.`}
        actions={
          <Button asChild className="gap-2">
            <Link to="/pro-forma/new">
              <Plus className="size-4" /> New pro-forma
            </Link>
          </Button>
        }
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard label="Open quotes" value={String(openCount)} hint="Awaiting a decision" />
        <SummaryCard label="Quoted value" value={currency(quotedValue)} hint="Sum of open quotes" />
        <SummaryCard label="Converted" value={String(convertedCount)} hint="Became real invoices" />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-56 flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search quote number or customer"
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
              <SelectItem value="open">Open</SelectItem>
              <SelectItem value="converted">Converted</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <FileText className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No pro-forma invoices match your filters</p>
            <p className="text-sm text-muted-foreground">Try another status or search term.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Quote</th>
                  <th className="px-5 py-3 font-medium">Customer</th>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 font-medium">Valid until</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((pf) => (
                  <tr key={pf.id} className="group hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/pro-forma/$proFormaId"
                        params={{ proFormaId: pf.id }}
                        className="font-medium group-hover:text-primary"
                      >
                        {pf.id}
                      </Link>
                      <p className="text-xs text-muted-foreground">{pf.lines.length} line items</p>
                    </td>
                    <td className="px-5 py-3">{pf.customerName}</td>
                    <td className="px-5 py-3 text-muted-foreground">{pf.date}</td>
                    <td className="px-5 py-3 text-muted-foreground">{pf.validUntil}</td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(pf.total)}
                    </td>
                    <td className="px-5 py-3">{statusBadge(pf.status)}</td>
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
