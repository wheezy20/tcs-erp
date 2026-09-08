import { cn } from "@/lib/utils";

/** Same pattern as CostMissingBadge — but unlike a missing cost, a missing
 * price isn't just a reporting gap: this product is structurally blocked
 * from being added to a POS sale or an invoice line until it's set (see
 * hasPrice() in inventory-store.ts). */
export function PriceMissingBadge({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-lg bg-amber-500/15 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400",
        className,
      )}
    >
      <span className="size-1.5 rounded-full bg-amber-500" />
      No selling price set
    </span>
  );
}
