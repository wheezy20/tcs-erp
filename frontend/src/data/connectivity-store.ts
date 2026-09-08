import { useSyncExternalStore } from "react";

function subscribe(listener: () => void) {
  window.addEventListener("online", listener);
  window.addEventListener("offline", listener);
  return () => {
    window.removeEventListener("online", listener);
    window.removeEventListener("offline", listener);
  };
}

function getSnapshot() {
  return navigator.onLine;
}

/** Always "online" during SSR — the same fixed-value-for-hydration pattern
 * every other `*-store.ts` in this codebase already uses for a value the
 * server can't actually know (see `useCurrentBranch()`'s own note on why a
 * live `getSnapshot` used as both arguments causes a hydration mismatch):
 * `navigator` doesn't exist server-side, and the real state is only known
 * once client JS runs, so the server render and the client's first
 * hydration pass need to agree on one fixed value rather than guess. */
function getServerSnapshot() {
  return true;
}

/** Backed by the browser's own `online`/`offline` events — reliable for
 * exactly the case this app's connection-resilience work targets (a hard
 * disconnect, including DevTools' "Offline" network throttling, which sets
 * `navigator.onLine = false` and fires both events for real). It does NOT
 * catch a merely slow/flaky-but-technically-connected network — that's
 * what `isNetworkError()` (lib/network-error.ts) is for, applied at the
 * point an actual request fails, not as a standing connectivity poll. */
export function useOnlineStatus(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
