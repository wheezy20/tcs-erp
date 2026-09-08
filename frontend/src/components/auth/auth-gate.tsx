import { useEffect, type ReactNode } from "react";
import { useNavigate } from "@tanstack/react-router";
import { Loader2 } from "lucide-react";

import { useAuth } from "@/data/auth-store";
import { useSessionTimeoutMinutes } from "@/data/session-timeout-store";
import { useInactivityLogout } from "@/hooks/use-inactivity-logout";

/** Wraps every route except /login. Redirects to /login once it's clear
 * there's no session — "clear" meaning after the first session check
 * resolves, not before: `loading` starts identically true on the server and
 * on the client's first paint (see auth-store.ts's SERVER_SNAPSHOT), so
 * nothing here ever redirects before hydration, avoiding the same class of
 * hydration mismatch useCurrentBranch() and the POS clock fix both guard
 * against elsewhere in this app. */
export function AuthGate({ children }: { children: ReactNode }) {
  const { session, staff, loading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && !session) {
      navigate({ to: "/login" });
    }
  }, [loading, session, navigate]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <Loader2 className="size-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!session) {
    // The effect above is navigating away; render nothing rather than
    // flashing the app shell for a frame first.
    return null;
  }

  if (!staff) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <div className="max-w-sm text-center">
          <h1 className="text-lg font-semibold text-foreground">Account not active</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            This login isn't linked to an active staff account. Ask a manager to check your status
            in Settings, or contact them to be added.
          </p>
        </div>
      </div>
    );
  }

  return (
    <>
      <InactivityWatcher />
      {children}
    </>
  );
}

/** Only ever mounted once there's a genuine authenticated, active-staff
 * session (see the `session && staff` branch above) — so
 * business_settings.session_timeout_minutes is never fetched, and the idle
 * timer never arms, for an unauthenticated visitor. */
function InactivityWatcher() {
  const { sessionTimeoutMinutes } = useSessionTimeoutMinutes();
  useInactivityLogout(sessionTimeoutMinutes);
  return null;
}
