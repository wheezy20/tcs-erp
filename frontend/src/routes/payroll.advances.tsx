import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { HandCoins, Plus } from "lucide-react";

import { Button } from "@/components/ui/button";
import { AdvancesTable, ProposeAdvanceDialog } from "@/components/payroll/staff-advances";
import { ACCOUNT_1350_NOTE } from "@/data/staff-advances-format";
import { canWriteFinancials, useAuth } from "@/data/auth-store";
import { useStaff } from "@/data/staff-store";
import { useStaffAdvances } from "@/data/staff-advances-store";

export const Route = createFileRoute("/payroll/advances")({
  component: StaffAdvancesPage,
});

/** Every staff advance: approvals waiting, then open advances, then the
 * rest. Balances and statuses come from staff_advance_summary(). */
function StaffAdvancesPage() {
  const { staff: currentStaff } = useAuth();
  const canWrite = canWriteFinancials(currentStaff?.role);
  const isManager = currentStaff?.role === "Manager";
  const { advances, changeRequests, loading, error } = useStaffAdvances();
  const { staff: roster } = useStaff();
  const [proposing, setProposing] = useState(false);

  const staffName = (id: string | null) =>
    id ? (roster.find((s) => s.id === id)?.name ?? "Unknown") : "—";
  const pendingIds = new Set(
    changeRequests.filter((c) => c.status === "Pending Approval").map((c) => c.advanceId),
  );
  const awaiting = advances.filter((a) => a.status === "Proposed" || pendingIds.has(a.id));
  const open = advances.filter(
    (a) => !awaiting.includes(a) && (a.displayStatus === "Active" || a.displayStatus === "Paused"),
  );
  const closed = advances.filter((a) => !awaiting.includes(a) && !open.includes(a));

  const tableProps = {
    changeRequests,
    showEmployee: true,
    canWrite,
    isManager,
    currentStaffId: currentStaff?.id ?? null,
    staffName,
  };

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-2xl text-sm text-muted-foreground">
          A staff advance is recorded once and repaid automatically from each payslip, after tax, on
          the IOU line, until it is repaid or a Manager approves a pause or cancellation.
        </p>
        {canWrite && (
          <Button onClick={() => setProposing(true)}>
            <Plus className="mr-1.5 size-4" /> Propose an advance
          </Button>
        )}
      </div>
      <p className="text-xs text-muted-foreground">{ACCOUNT_1350_NOTE}</p>

      {error ? (
        <p className="text-sm font-medium text-destructive">{error}</p>
      ) : loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : advances.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <HandCoins className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No staff advances yet</p>
        </div>
      ) : (
        <>
          {awaiting.length > 0 && (
            <section className="card-surface overflow-hidden">
              <h2 className="px-5 pt-4 text-sm font-semibold">Waiting for approval</h2>
              <AdvancesTable advances={awaiting} {...tableProps} />
            </section>
          )}
          <section className="card-surface overflow-hidden">
            <h2 className="px-5 pt-4 text-sm font-semibold">Being repaid</h2>
            <AdvancesTable advances={open} {...tableProps} />
          </section>
          {closed.length > 0 && (
            <section className="card-surface overflow-hidden">
              <h2 className="px-5 pt-4 text-sm font-semibold">Settled, cancelled and rejected</h2>
              <AdvancesTable advances={closed} {...tableProps} />
            </section>
          )}
        </>
      )}

      {proposing && <ProposeAdvanceDialog onClose={() => setProposing(false)} />}
    </div>
  );
}
