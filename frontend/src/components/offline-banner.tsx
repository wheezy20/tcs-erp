import { useEffect, useRef, useState } from "react";
import { Wifi, WifiOff } from "lucide-react";

import { useOnlineStatus } from "@/data/connectivity-store";

/** App-wide, unmissable connection indicator — mounted once in __root.tsx,
 * outside AppShell/AuthGate so it shows on every screen including /login.
 * Deliberately a persistent top bar, not a toast: a toast auto-dismisses on
 * its own timer regardless of whether the connection has actually come
 * back, which is exactly the "silent hang" this exists to prevent — the
 * bar stays up for the entire outage and only clears once the browser
 * itself reports being back online. */
export function OfflineBanner() {
  const online = useOnlineStatus();
  const wasOffline = useRef(false);
  const [showReconnected, setShowReconnected] = useState(false);

  useEffect(() => {
    if (!online) {
      wasOffline.current = true;
      setShowReconnected(false);
      return;
    }
    if (!wasOffline.current) return;
    wasOffline.current = false;
    setShowReconnected(true);
    const timer = setTimeout(() => setShowReconnected(false), 4000);
    return () => clearTimeout(timer);
  }, [online]);

  if (!online) {
    return (
      <div
        role="status"
        className="flex items-center justify-center gap-2 bg-destructive px-4 py-2 text-sm font-medium text-destructive-foreground"
      >
        <WifiOff className="size-4 shrink-0" />
        You&apos;re offline — nothing will save until your connection returns.
      </div>
    );
  }

  if (showReconnected) {
    return (
      <div
        role="status"
        className="flex items-center justify-center gap-2 bg-emerald-600 px-4 py-2 text-sm font-medium text-white"
      >
        <Wifi className="size-4 shrink-0" />
        Back online
      </div>
    );
  }

  return null;
}
