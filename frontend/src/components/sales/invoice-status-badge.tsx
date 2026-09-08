import type { InvoiceStatus } from "@/data/invoices";
import { cn } from "@/lib/utils";

const styles: Record<InvoiceStatus, string> = {
  Paid: "border-primary/30 bg-primary/10 text-primary",
  "Partly paid": "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-400",
  Unpaid: "border-destructive/30 bg-destructive/10 text-destructive",
};

export function InvoiceStatusBadge({
  status,
  className,
}: {
  status: InvoiceStatus;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium",
        styles[status],
        className,
      )}
    >
      <span className="size-1.5 rounded-full bg-current" />
      {status}
    </span>
  );
}
