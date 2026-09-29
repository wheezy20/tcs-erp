import { useEffect, type ReactNode } from "react";
import { useNavigate, useRouterState } from "@tanstack/react-router";
import { Loader2 } from "lucide-react";

import { isAdmissionsOfficer, useAuth } from "@/data/auth-store";
import { useSessionTimeoutMinutes } from "@/data/session-timeout-store";
import { useInactivityLogout } from "@/hooks/use-inactivity-logout";

const OFFICER_ROUTES = new Set(["/", "/settings"]);

function officerMayOpen(pathname: string) {
  return OFFICER_ROUTES.has(pathname.replace(/\/+$/, "") || "/");
}

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
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  // The location whose route components are actually rendered. Right after
  // the redirect below, `pathname` is already "/" while the router still
  // renders the old match until the new one resolves; without this the
  // blocked page mounts for a moment and starts its data loads.
  const renderedPathname = useRouterState({
    select: (s) => s.resolvedLocation?.pathname ?? s.location.pathname,
  });
  // The Admissions Officer's route allowlist. Every other role is unaffected
  // here; they have no route guard yet (open item, docs/admissions/PORT-PLAN.md).
  const isOfficer = isAdmissionsOfficer(staff?.role);
  const officerBlocked = isOfficer && !officerMayOpen(pathname);
  const officerHidden = isOfficer && (officerBlocked || !officerMayOpen(renderedPathname));

  useEffect(() => {
    if (!loading && !session) {
      navigate({ to: "/login" });
    }
  }, [loading, session, navigate]);

  useEffect(() => {
    if (officerBlocked) {
      navigate({ to: "/", replace: true });
    }
  }, [officerBlocked, navigate]);

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

  if (officerHidden) {
    // Redirecting to /, or waiting for / to replace the blocked page; don't
    // mount the page, so none of its data loads fire.
    return null;
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
