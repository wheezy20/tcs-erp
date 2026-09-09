import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Search, Users } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useAuth } from "@/data/auth-store";
import { useStaff } from "@/data/staff-store";

export const Route = createFileRoute("/staff/")({
  component: StaffOverviewPage,
});

function StaffOverviewPage() {
  const { staff: currentStaff } = useAuth();
  const { staff: roster, pendingIds, loading } = useStaff();
  const [query, setQuery] = useState("");
  const [showInactive, setShowInactive] = useState(false);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return roster
      .filter((s) => (showInactive ? true : s.active))
      .filter((s) => {
        if (!q) return true;
        return (
          s.name.toLowerCase().includes(q) ||
          s.email.toLowerCase().includes(q) ||
          (s.position ?? "").toLowerCase().includes(q) ||
          (s.department ?? "").toLowerCase().includes(q) ||
          s.role.toLowerCase().includes(q)
        );
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [roster, query, showInactive]);

  const activeCount = roster.filter((s) => s.active).length;

  return (
    <>
      <PageHeader
        title="Staff"
        description="Everyone with a TCS login — role, position and how to reach them."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <SummaryCard label="Active staff" value={String(activeCount)} hint="Can sign in" />
        <SummaryCard
          label="All accounts"
          value={String(roster.length)}
          hint={`${roster.length - activeCount} inactive`}
        />
        <SummaryCard
          label="Pending invites"
          value={String(pendingIds.size)}
          hint={pendingIds.size ? "Not yet accepted" : "None outstanding"}
        />
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 border-b p-4">
          <div className="relative max-w-sm flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search name, email, position or department"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            <Switch checked={showInactive} onCheckedChange={setShowInactive} />
            Show inactive
          </label>
        </div>

        {loading ? (
          <p className="p-10 text-center text-sm text-muted-foreground">Loading…</p>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <Users className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No staff match this search</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Name</th>
                  <th className="px-5 py-3 font-medium">Role</th>
                  <th className="px-5 py-3 font-medium">Position</th>
                  <th className="px-5 py-3 font-medium">Department</th>
                  <th className="px-5 py-3 font-medium">Phone</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((s) => (
                  <tr key={s.id} className="group hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/staff/$staffId"
                        params={{ staffId: s.id }}
                        className="font-medium group-hover:text-primary"
                      >
                        {s.name}
                      </Link>
                      {s.id === currentStaff?.id && (
                        <Badge variant="secondary" className="ml-2">
                          You
                        </Badge>
                      )}
                      <p className="text-xs text-muted-foreground">{s.email}</p>
                    </td>
                    <td className="px-5 py-3">
                      <Badge variant="outline">{s.role}</Badge>
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{s.position ?? "—"}</td>
                    <td className="px-5 py-3 text-muted-foreground">{s.department ?? "—"}</td>
                    <td className="px-5 py-3 tabular-nums text-muted-foreground">
                      {s.phone ?? "—"}
                    </td>
                    <td className="px-5 py-3">
                      {pendingIds.has(s.id) ? (
                        <Badge variant="outline">Invite pending</Badge>
                      ) : (
                        <Badge variant={s.active ? "secondary" : "outline"}>
                          {s.active ? "Active" : "Inactive"}
                        </Badge>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <p className="mt-4 text-xs text-muted-foreground">
        Roles and active status are managed in{" "}
        <Link to="/settings" className="text-primary hover:underline">
          Settings → Staff
        </Link>
        . Bank details live on each person's Pay Config.
      </p>
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
