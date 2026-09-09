import { useEffect, useState, type FormEvent } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { requestPasswordReset, signIn, useAuth } from "@/data/auth-store";

export const Route = createFileRoute("/login")({
  head: () => ({
    meta: [{ title: "Sign in — TCS" }],
  }),
  component: LoginPage,
});

function LoginPage() {
  const { session, staff, loading } = useAuth();
  const navigate = useNavigate();

  // Already signed in with an active staff account — /login has nothing left
  // to do here, send them to the app proper.
  useEffect(() => {
    if (!loading && session && staff) {
      navigate({ to: "/" });
    }
  }, [loading, session, staff, navigate]);

  // A valid sign-in succeeded (a real session exists) but it isn't linked
  // to an active staff row — the same state AuthGate blocks everywhere
  // else in the app, just reached here directly instead of via a navigate,
  // since the effect above only ever fires when staff is truthy too. Left
  // unhandled, this used to mean the sign-in form just sat there after a
  // "successful" submit with no explanation at all — same block either
  // way, but the recovery-link path (which does reach AuthGate, landing on
  // / after /accept-invite) already explained it and this one didn't.
  const accountNotActive = !loading && !!session && !staff;

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="flex flex-col items-center gap-3 text-center">
          <img
            src="/tcs-logomark.png"
            alt="Treasures Christian School"
            className="h-20 w-20 rounded-2xl bg-white object-contain p-2 shadow-sm"
          />
          <h1 className="text-xl font-semibold tracking-tight">Treasures Christian School</h1>
          <p className="text-sm text-muted-foreground">Sign in to your staff account</p>
        </div>

        {accountNotActive ? (
          <Card>
            <CardContent className="pt-6 text-center">
              <h2 className="text-lg font-semibold text-foreground">Account not active</h2>
              <p className="mt-2 text-sm text-muted-foreground">
                This login isn't linked to an active staff account. Ask a manager to check your
                status in Settings, or contact them to be added.
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardContent className="pt-6">
              <SignInForm />
              <ForgotPassword />
            </CardContent>
          </Card>
        )}

        <p className="text-center text-xs text-muted-foreground">
          TCS is invite-only — ask a Manager to invite you from Settings if you don't have an
          account yet.
        </p>
      </div>
    </div>
  );
}

function SignInForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await signIn(email, password);
      // useAuth() picks up the new session reactively; the effect in
      // LoginPage handles navigating away once it does.
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not sign in.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="signin-email">Email</Label>
        <Input
          id="signin-email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="signin-password">Password</Label>
        <Input
          id="signin-password"
          type="password"
          autoComplete="current-password"
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
      </div>
      {error && <p className="text-sm text-destructive">{error}</p>}
      <Button type="submit" className="w-full" disabled={submitting}>
        {submitting ? <Loader2 className="size-4 animate-spin" /> : "Sign in"}
      </Button>
    </form>
  );
}

/** Below the sign-in form. A public, unauthenticated action — the request
 * itself never reveals whether the email is actually registered
 * (requestPasswordReset() resolves the same way either way, by GoTrue's
 * own design), so the success copy stays deliberately generic rather than
 * branching on some "does this account exist" check that would leak the
 * answer. Reuses /accept-invite for the actual "set a new password" step —
 * no separate page, the recovery link lands there exactly like an invite/
 * resend link does. */
function ForgotPassword() {
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (submitted) {
    return (
      <p className="mt-4 border-t pt-4 text-sm text-muted-foreground">
        If that email has an account, a reset link is on its way.
      </p>
    );
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="mt-3 text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
      >
        Forgot password?
      </button>
    );
  }

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await requestPasswordReset(email);
      setSubmitted(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not send the reset link.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={onSubmit} className="mt-4 space-y-3 border-t pt-4">
      <div className="space-y-2">
        <Label htmlFor="forgot-email">Email</Label>
        <Input
          id="forgot-email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </div>
      {error && <p className="text-sm text-destructive">{error}</p>}
      <div className="flex gap-2">
        <Button type="submit" className="flex-1" disabled={submitting}>
          {submitting ? <Loader2 className="size-4 animate-spin" /> : "Send reset link"}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() => setOpen(false)}
          disabled={submitting}
        >
          Cancel
        </Button>
      </div>
    </form>
  );
}
