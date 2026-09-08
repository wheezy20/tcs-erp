import { useEffect, useState } from "react";
import { Loader2, RefreshCcw } from "lucide-react";

import { cn } from "@/lib/utils";

function relativeSync(lastSyncedAt: number | null, now: number): string {
  if (lastSyncedAt === null) return "Not yet synced";
  const seconds = Math.max(0, Math.floor((now - lastSyncedAt) / 1000));
  if (seconds < 5) return "Synced just now";
  if (seconds < 60) return `Synced ${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `Synced ${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  return `Synced ${hours}h ago`;
}

/** An honest "how stale is this" label for a reference lookup — never for
 * anything that gates a real transaction. `useInventory()`'s `products`
 * (and every other `*-store.ts`) is already a client-side cache by
 * construction (loaded once, kept in memory, only refetched on an explicit
 * reload) — this doesn't change that, it just makes its age visible
 * wherever a figure is shown for someone to *look at* (Inventory list, a
 * product's detail page), specifically so a stale number is never mistaken
 * for a current one while the connection is flaky. Deliberately not used
 * anywhere a transaction is actually decided — POS checkout and invoice
 * creation both go through create_sale()/create_invoice(), which re-check
 * stock/price live, server-side, every time, regardless of what this label
 * (or the cache it describes) currently shows. */
export function SyncStatus({
  lastSyncedAt,
  onRefresh,
  className,
}: {
  lastSyncedAt: number | null;
  onRefresh: () => Promise<void>;
  className?: string;
}) {
  const [now, setNow] = useState(() => Date.now());
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 15_000);
    return () => clearInterval(id);
  }, []);

  async function refresh() {
    setRefreshing(true);
    try {
      await onRefresh();
    } finally {
      setNow(Date.now());
      setRefreshing(false);
    }
  }

  return (
    <button
      type="button"
      onClick={() => void refresh()}
      disabled={refreshing}
      title="Reload from the server"
      className={cn(
        "inline-flex items-center gap-1.5 text-xs text-muted-foreground transition-colors hover:text-foreground disabled:cursor-wait",
        className,
      )}
    >
      {refreshing ? (
        <Loader2 className="size-3.5 animate-spin" />
      ) : (
        <RefreshCcw className="size-3.5" />
      )}
      {refreshing ? "Syncing…" : relativeSync(lastSyncedAt, now)}
    </button>
  );
}
