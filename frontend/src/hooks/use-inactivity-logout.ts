import { useEffect, useRef } from "react";
import { toast } from "sonner";

import { signOut } from "@/data/auth-store";

const ACTIVITY_EVENTS = [
  "mousedown",
  "mousemove",
  "keydown",
  "wheel",
  "touchstart",
  "scroll",
] as const;

// Checking on an interval (rather than clearing/resetting a setTimeout on
// every single event) means a fast-firing event like mousemove never
// touches a timer — it only updates a ref — so this stays cheap regardless
// of how much genuine activity there is.
const CHECK_INTERVAL_MS = 5_000;

/** Signs the user out completely — a real supabase.auth.signOut(), the same
 * call the manual "Sign out" action uses, landing back on /login requiring
 * their normal password (via AuthGate's existing session === null redirect)
 * — after `timeoutMinutes` with no genuine mouse/keyboard/touch/scroll
 * activity anywhere in the window. `timeoutMinutes` is only ever non-null
 * once the caller is both signed in and business_settings.
 * session_timeout_minutes has actually loaded — a null value here means
 * "don't arm a timer yet", not "no timeout". */
export function useInactivityLogout(timeoutMinutes: number | null) {
  const lastActivityRef = useRef(Date.now());

  useEffect(() => {
    if (!timeoutMinutes || timeoutMinutes <= 0) return;

    lastActivityRef.current = Date.now();
    const markActive = () => {
      lastActivityRef.current = Date.now();
    };

    ACTIVITY_EVENTS.forEach((event) =>
      window.addEventListener(event, markActive, { passive: true }),
    );

    const timeoutMs = timeoutMinutes * 60_000;
    const interval = window.setInterval(() => {
      if (Date.now() - lastActivityRef.current >= timeoutMs) {
        window.clearInterval(interval);
        toast.info("Signed out after a period of inactivity.");
        // signOut() clears the local session and (via auth-store.ts's
        // onAuthStateChange listener) flips useAuth().session to null,
        // which is what actually sends AuthGate to /login — nothing else
        // to do here even if the network call itself fails, since there's
        // no meaningful retry for "the browser sat idle."
        void signOut();
      }
    }, CHECK_INTERVAL_MS);

    return () => {
      ACTIVITY_EVENTS.forEach((event) => window.removeEventListener(event, markActive));
      window.clearInterval(interval);
    };
  }, [timeoutMinutes]);
}
