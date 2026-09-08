import { useState, type FormEvent } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Loader2, Store } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { setPassword, useAuth } from "@/data/auth-store";

export const Route = createFileRoute("/accept-invite")({
  head: () => ({
    meta: [{ title: "Set your password — TCS" }],
  }),
  component: AcceptInvitePage,
});

// Reached only from the link in a real invite email (see
// supabase/functions/invite-staff/'s redirectTo). supabase-js auto-
// establishes a session from that link's own URL fragment on load — the
// same SIGNED_IN event a normal sign-in produces, auth-js doesn't expose a
// distinct one for invites (only PASSWORD_RECOVERY is special-cased) — so
// this route doesn't try to detect "is this really an invite," it just
// always asks for a new password. Anyone who lands here with no session at
// all (a stale or already-used link) gets a clear dead-end back to /login
// instead. The staff row already exists (handle_new_staff_signup() ran the
// moment the invite was sent, not when it's accepted), so setting a
// password is genuinely the only step left — no separate activation.
function AcceptInvitePage() {
  const { session, staff, loading } = useAuth();
  const navigate = useNavigate();
  const [password, setPasswordInput] = useState("");
  const [confirm, setConfirm] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (password.length < 6) {
      setError("Password must be at least 6 characters.");
      return;
    }
    if (password !== confirm) {
      setError("Passwords don't match.");
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await setPassword(password);
      navigate({ to: "/" });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not set your password.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="flex flex-col items-center gap-2 text-center">
          <div className="flex size-12 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
            <Store className="size-6" />
          </div>
          <h1 className="text-xl font-semibold tracking-tight">TCS</h1>
          <p className="text-sm text-muted-foreground">
            {staff
              ? `Welcome, ${staff.name} — set a password to finish setting up your account.`
              : "Finish setting up your account"}
          </p>
        </div>

        <Card>
          <CardContent className="pt-6">
            {loading ? (
              <div className="flex justify-center py-4">
                <Loader2 className="size-5 animate-spin text-muted-foreground" />
              </div>
            ) : !session ? (
              <div className="space-y-3 text-center text-sm text-muted-foreground">
                <p>This invite link is invalid or has already been used.</p>
                <Button asChild variant="outline" className="w-full">
                  <Link to="/login">Back to sign in</Link>
                </Button>
              </div>
            ) : (
              <form onSubmit={onSubmit} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="invite-password">New password</Label>
                  <Input
                    id="invite-password"
                    type="password"
                    autoComplete="new-password"
                    required
                    minLength={6}
                    value={password}
                    onChange={(e) => setPasswordInput(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="invite-password-confirm">Confirm password</Label>
                  <Input
                    id="invite-password-confirm"
                    type="password"
                    autoComplete="new-password"
                    required
                    minLength={6}
                    value={confirm}
                    onChange={(e) => setConfirm(e.target.value)}
                  />
                </div>
                {error && <p className="text-sm text-destructive">{error}</p>}
                <Button type="submit" className="w-full" disabled={submitting}>
                  {submitting ? (
                    <Loader2 className="size-4 animate-spin" />
                  ) : (
                    "Set password & continue"
                  )}
                </Button>
              </form>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
