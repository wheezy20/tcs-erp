import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-react";

import { cn } from "@/lib/utils";
import type { SortDirection } from "@/lib/use-sort";

/** A `<th>` whose label toggles a `useSort()` column when clicked, with an
 * icon indicating the active sort column and direction (a neutral
 * up/down icon on inactive columns). */
export function SortableTh<K extends string>({
  label,
  sortKeyValue,
  activeKey,
  direction,
  onSort,
  align = "left",
}: {
  label: string;
  sortKeyValue: K;
  activeKey: K | null;
  direction: SortDirection;
  onSort: (key: K) => void;
  align?: "left" | "right";
}) {
  const active = activeKey === sortKeyValue;
  return (
    <th
      className={cn("px-5 py-3 font-medium", align === "right" && "text-right")}
      aria-sort={active ? (direction === "asc" ? "ascending" : "descending") : "none"}
    >
      <button
        type="button"
        onClick={() => onSort(sortKeyValue)}
        className={cn(
          "inline-flex items-center gap-1 hover:text-foreground",
          align === "right" && "flex-row-reverse",
          active && "text-foreground",
        )}
      >
        {label}
        {active ? (
          direction === "asc" ? (
            <ArrowUp className="size-3.5" />
          ) : (
            <ArrowDown className="size-3.5" />
          )
        ) : (
          <ArrowUpDown className="size-3.5 opacity-40" />
        )}
      </button>
    </th>
  );
}
