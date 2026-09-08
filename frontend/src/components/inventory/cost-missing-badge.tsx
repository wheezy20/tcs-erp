import { cn } from "@/lib/utils";

/** Same visual language as StockBadge's "Low stock" tone — an amber pill
 * flagging a data gap, not a stock-level concern, but deliberately the same
 * severity color so it reads consistently at a glance. */
export function CostMissingBadge({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-lg bg-amber-500/15 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400",
        className,
      )}
    >
      <span className="size-1.5 rounded-full bg-amber-500" />
      Cost price missing
    </span>
  );
}
