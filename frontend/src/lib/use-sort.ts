import { useMemo, useState } from "react";

export type SortDirection = "asc" | "desc";

/**
 * Shared column-sort state for the hand-rolled `<table>` list views
 * (Inventory, Customers, Sales & Invoicing, ...). Sorts on top of whatever
 * array is passed in — callers apply their own search/filter logic first
 * and hand the already-filtered rows here, so sorting and filtering compose
 * rather than one replacing the other.
 */
export function useSort<T, K extends string>(
  items: T[],
  accessors: Record<K, (item: T) => string | number>,
  initial?: { key: K; direction?: SortDirection },
) {
  const [sortKey, setSortKey] = useState<K | null>(initial?.key ?? null);
  const [sortDirection, setSortDirection] = useState<SortDirection>(initial?.direction ?? "asc");

  const toggleSort = (key: K) => {
    if (sortKey === key) {
      setSortDirection((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDirection("asc");
    }
  };

  const sorted = useMemo(() => {
    if (!sortKey) return items;
    const accessor = accessors[sortKey];
    const factor = sortDirection === "asc" ? 1 : -1;
    return [...items].sort((a, b) => {
      const av = accessor(a);
      const bv = accessor(b);
      if (typeof av === "number" && typeof bv === "number") {
        return (av - bv) * factor;
      }
      return (
        String(av).localeCompare(String(bv), undefined, { sensitivity: "base", numeric: true }) *
        factor
      );
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- accessors is a fresh object literal per render by design; only items/sortKey/direction should trigger a resort
  }, [items, sortKey, sortDirection]);

  return { sortKey, sortDirection, toggleSort, sorted };
}
