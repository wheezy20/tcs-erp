import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { Package, Plus } from "lucide-react";

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
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { usePurchaseOrders, type PurchaseOrderStatus } from "@/data/purchasing-store";

export const Route = createFileRoute("/purchasing/")({
  component: PurchaseOrdersPage,
});

const STATUS_LABELS: Record<PurchaseOrderStatus, string> = {
  draft: "Draft",
  ordered: "Ordered",
  partially_received: "Partially received",
  received: "Received",
  cancelled: "Cancelled",
};

const STATUS_TONE: Record<PurchaseOrderStatus, string> = {
  draft: "",
  ordered: "border-blue-500/40 text-blue-600 dark:text-blue-400",
  partially_received: "border-amber-500/40 text-amber-600 dark:text-amber-400",
  received: "border-emerald-500/40 text-emerald-600 dark:text-emerald-400",
  cancelled: "border-destructive/40 text-destructive",
};

function PurchaseOrdersPage() {
  const { purchaseOrders, loading } = usePurchaseOrders();
  const { staff: currentStaff } = useAuth();
  const isManager = currentStaff?.role === "Manager";

  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<"all" | PurchaseOrderStatus>("all");

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return purchaseOrders.filter((po) => {
      if (status !== "all" && po.status !== status) return false;
      if (!term) return true;
      return po.id.toLowerCase().includes(term) || po.supplierName.toLowerCase().includes(term);
    });
  }, [purchaseOrders, search, status]);

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  return (
    <div className="mt-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by PO number or supplier…"
            className="h-9 w-64 rounded-xl"
          />
          <Select value={status} onValueChange={(v) => setStatus(v as typeof status)}>
            <SelectTrigger className="h-9 w-48 rounded-xl">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All statuses</SelectItem>
              {(Object.keys(STATUS_LABELS) as PurchaseOrderStatus[]).map((s) => (
                <SelectItem key={s} value={s}>
                  {STATUS_LABELS[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        {isManager && (
          <Button asChild className="gap-2">
            <Link to="/purchasing/new">
              <Plus className="size-4" /> New purchase order
            </Link>
          </Button>
        )}
      </div>

      {filtered.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed px-6 py-16 text-center">
          <Package className="size-8 text-muted-foreground" />
          <p className="text-sm font-medium">No purchase orders match</p>
        </div>
      ) : (
        <div className="card-surface overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">PO number</th>
                  <th className="px-5 py-3 font-medium">Supplier</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 font-medium">Order date</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                  <th className="px-5 py-3 text-right font-medium">Received</th>
                  <th className="px-5 py-3 text-right font-medium">Balance</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {filtered.map((po) => (
                  <tr key={po.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3">
                      <Link
                        to="/purchasing/$purchaseOrderId"
                        params={{ purchaseOrderId: po.id }}
                        className="font-medium text-primary hover:underline"
                      >
                        {po.id}
                      </Link>
                    </td>
                    <td className="px-5 py-3">{po.supplierName}</td>
                    <td className="px-5 py-3">
                      <Badge variant="outline" className={STATUS_TONE[po.status]}>
                        {STATUS_LABELS[po.status]}
                      </Badge>
                    </td>
                    <td className="px-5 py-3 text-muted-foreground">{po.orderDate}</td>
                    <td className="px-5 py-3 text-right tabular-nums">{currency(po.total)}</td>
                    <td className="px-5 py-3 text-right tabular-nums">
                      {currency(po.receivedValue)}
                    </td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currency(po.balance)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
