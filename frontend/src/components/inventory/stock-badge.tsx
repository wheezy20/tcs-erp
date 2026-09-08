import { cn } from "@/lib/utils";
import type { StockStatus } from "@/data/inventory-store";

export function StockBadge({ status, className }: { status: StockStatus; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-lg px-2 py-0.5 text-xs font-medium",
        status === "In stock" && "bg-accent text-accent-foreground",
        status === "Low stock" && "bg-amber-500/15 text-amber-700 dark:text-amber-400",
        status === "Out of stock" && "bg-destructive/10 text-destructive",
        className,
      )}
    >
      <span
        className={cn(
          "size-1.5 rounded-full",
          status === "In stock" && "bg-primary",
          status === "Low stock" && "bg-amber-500",
          status === "Out of stock" && "bg-destructive",
        )}
      />
      {status}
    </span>
  );
}
