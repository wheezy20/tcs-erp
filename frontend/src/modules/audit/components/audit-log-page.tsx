import { Fragment, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";

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
import type { StaffRole } from "@/data/auth-store";
import { ALL, PAGE_SIZE, listAuditLog, listStaffNames } from "@/modules/audit/data/audit-log";
import { dateRangeBounds, describeChanges } from "@/modules/audit/filters";
import { useLoad } from "@/modules/audit/hooks/use-load";
import { actionLabel } from "@/modules/audit/labels";
import { actionFilterOptions, canSeeAdmissionsAuditRows } from "@/modules/audit/permissions";

const whenFormat = new Intl.DateTimeFormat(undefined, {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Africa/Accra",
});

type Filters = { action: string; from: string; to: string; page: number };

/** Read-only for every role that can open it. */
export function AuditLogPage({ role }: { role: StaffRole }) {
  const [filters, setFilters] = useState<Filters>({ action: ALL, from: "", to: "", page: 0 });
  const bounds = useMemo(
    () => dateRangeBounds(filters.from, filters.to),
    [filters.from, filters.to],
  );

  const names = useLoad(listStaffNames, [], "Could not load staff names.");
  const list = useLoad(
    () =>
      bounds.error
        ? Promise.resolve({ rows: [], total: 0 })
        : listAuditLog({
            action: filters.action,
            gte: bounds.gte,
            lt: bounds.lt,
            page: filters.page,
          }),
    [filters.action, filters.page, bounds.gte, bounds.lt, bounds.error],
    "Could not load the audit log.",
  );

  const set = (patch: Partial<Filters>) => setFilters((f) => ({ ...f, ...patch, page: 0 }));
  const isFiltered = filters.action !== ALL || filters.from !== "" || filters.to !== "";

  const total = list.data?.total ?? 0;
  const rows = list.data?.rows ?? [];
  const firstShown = total === 0 ? 0 : filters.page * PAGE_SIZE + 1;
  const lastShown = Math.min(total, (filters.page + 1) * PAGE_SIZE);

  return (
    <>
      <PageHeader
        title="Audit Log"
        description="Approvals, voids, overrides and other recorded changes, newest first."
        actions={<Badge variant="outline">Read-only</Badge>}
      />

      {!canSeeAdmissionsAuditRows(role) && (
        <div className="mb-6 rounded-lg border border-dashed px-4 py-3 text-sm text-muted-foreground">
          Admissions entries aren't shown for your role.
        </div>
      )}

      <div className="card-surface overflow-hidden">
        <div className="flex flex-wrap items-end gap-3 border-b p-4">
          <Select value={filters.action} onValueChange={(v) => set({ action: v })}>
            <SelectTrigger className="w-64" aria-label="Action">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All actions</SelectItem>
              {actionFilterOptions(role).map((a) => (
                <SelectItem key={a} value={a}>
                  {actionLabel(a)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <label className="flex flex-col gap-1 text-xs text-muted-foreground">
            From
            <Input
              type="date"
              className="w-40"
              value={filters.from}
              onChange={(e) => set({ from: e.target.value })}
            />
          </label>
          <label className="flex flex-col gap-1 text-xs text-muted-foreground">
            To
            <Input
              type="date"
              className="w-40"
              value={filters.to}
              onChange={(e) => set({ to: e.target.value })}
            />
          </label>
          {isFiltered && (
            <Button variant="ghost" onClick={() => set({ action: ALL, from: "", to: "" })}>
              Clear filters
            </Button>
          )}
        </div>

        {bounds.error ? (
          <p className="p-10 text-center text-sm text-destructive">{bounds.error}</p>
        ) : list.error ? (
          <p className="p-10 text-center text-sm text-destructive">{list.error}</p>
        ) : list.loading && !list.data ? (
          <p className="p-10 text-center text-sm text-muted-foreground">Loading…</p>
        ) : rows.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">
            {isFiltered ? "No entries match these filters." : "No entries yet."}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">When</th>
                  <th className="px-5 py-3 font-medium">Action</th>
                  <th className="px-5 py-3 font-medium">By</th>
                  <th className="px-5 py-3 font-medium">Record</th>
                  <th className="px-5 py-3 font-medium">Changes</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((r) => {
                  const changes = describeChanges(r.before, r.after);
                  return (
                    <tr key={r.id} className="align-top">
                      <td className="whitespace-nowrap px-5 py-3 tabular-nums text-muted-foreground">
                        {whenFormat.format(new Date(r.occurredAt))}
                      </td>
                      <td className="px-5 py-3 font-medium">{actionLabel(r.action)}</td>
                      <td className="px-5 py-3">
                        {(r.actorId && names.data?.get(r.actorId)) ??
                          (names.loading ? "…" : "Unknown")}
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">
                        {r.entityTable}
                        <p className="break-all text-xs tabular-nums">{r.entityId}</p>
                      </td>
                      <td className="px-5 py-3">
                        {changes.length === 0 ? (
                          <span className="text-muted-foreground">No details</span>
                        ) : (
                          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                            {changes.map((c) => (
                              <Fragment key={c.key}>
                                <dt className="text-muted-foreground">{c.key}</dt>
                                <dd className="break-all">
                                  {c.before !== null && r.before ? (
                                    <>
                                      <span className="text-muted-foreground line-through">
                                        {c.before}
                                      </span>{" "}
                                      → {c.after ?? "empty"}
                                    </>
                                  ) : (
                                    (c.after ?? c.before ?? "empty")
                                  )}
                                </dd>
                              </Fragment>
                            ))}
                          </dl>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {total > 0 && !bounds.error && (
          <div className="flex items-center justify-between gap-4 border-t px-5 py-3 text-sm text-muted-foreground">
            <span className="tabular-nums">
              {firstShown} to {lastShown} of {total}
            </span>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={filters.page === 0 || list.loading}
                onClick={() => setFilters((f) => ({ ...f, page: f.page - 1 }))}
              >
                <ChevronLeft className="size-4" /> Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={lastShown >= total || list.loading}
                onClick={() => setFilters((f) => ({ ...f, page: f.page + 1 }))}
              >
                Next <ChevronRight className="size-4" />
              </Button>
            </div>
          </div>
        )}
      </div>
    </>
  );
}
