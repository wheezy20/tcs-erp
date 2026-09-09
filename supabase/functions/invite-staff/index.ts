// Invite-only staff onboarding (Session 20) + Resend invite (same-day
// follow-up).
//
// The only server-side entry point that can ever create a new staff login
// besides scripts/bootstrap-production-manager.sh. Holds the service_role
// key (via Deno.env — Supabase injects SUPABASE_URL/SUPABASE_ANON_KEY/
// SUPABASE_SERVICE_ROLE_KEY into every Edge Function automatically, no
// `supabase secrets set` needed for these three), which is never sent to
// or reachable from the browser — the client only ever calls this function
// by name via supabase.functions.invoke(), which forwards the caller's own
// session token, not any secret.
//
// Two client instances, deliberately never crossed:
//   - `callerClient` is authenticated AS the calling browser session (anon
//     key + their JWT) — used ONLY to find out who they are and let RLS
//     answer "are they really an active Manager," the same real boundary
//     every other Manager-only action in this app relies on. This client
//     never touches the Admin API.
//   - `adminClient` is authenticated as service_role — used ONLY for the
//     actual privileged calls (admin.inviteUserByEmail(), admin.getUserById(),
//     admin.generateLink()), never to read or trust anything about the
//     caller.
// If the first check fails, the second client is never even constructed.
//
// Two actions, one function, because they share every bit of the
// verification/plumbing above and differ only in which Admin API call they
// make at the end:
//   - "invite" (default, original behaviour): admin.inviteUserByEmail() —
//     creates the auth.users row AND sends its own invite email via
//     GoTrue's configured mailer, in one call.
//   - "resend": for someone already invited but who's never signed in.
//     admin.inviteUserByEmail() fails with "already registered" for them
//     (confirmed directly) — GoTrue has no "resend an invite" admin call at
//     all. admin.generateLink({ type: "recovery" }) is the one that
//     actually works for an existing, unconfirmed user (also confirmed
//     directly — type: "invite" does not). Unlike inviteUserByEmail(),
//     generateLink() does NOT send anything — it only returns the link —
//     so this function has to deliver it itself, via sendMail() below,
//     never by handing the raw action_link back to the client: that link
//     signs straight into the account with no password, so it's a
//     credential-equivalent value the same way a password reset link is.
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6";

const ALLOWED_ROLES = ["Attendant", "Manager", "Accountant", "Auditor"];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Deliberately not GoTrue's own mailer — that's only reachable from inside
// GoTrue itself, for GoTrue's own templated emails (confirmation, invite,
// recovery, ...). This is a plain, separate SMTP send for the one email
// this function itself composes. Locally, this talks to the same Inbucket/
// Mailpit relay GoTrue's own invite emails already go through
// (SMTP_HOST=supabase_inbucket_tcs-erp, SMTP_PORT=1025, no auth — see
// supabase/functions/.env, gitignored, loaded via
// `supabase functions serve --env-file supabase/functions/.env`).
// Production needs its own real SMTP_HOST/PORT/USER/PASS/FROM set via
// `supabase secrets set`, matching whatever provider GoTrue's own
// [auth.email.smtp] is configured against — never invented or hardcoded
// here.
async function sendMail(to: string, subject: string, text: string, html: string) {
  const host = Deno.env.get("SMTP_HOST");
  if (!host) {
    throw new Error("SMTP_HOST is not configured for this environment");
  }
  const port = Number(Deno.env.get("SMTP_PORT") ?? "587");
  const user = Deno.env.get("SMTP_USER");
  const pass = Deno.env.get("SMTP_PASS");
  const from = Deno.env.get("SMTP_FROM") ?? "TCS <no-reply@tcs.local>";

  const transport = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: user && pass ? { user, pass } : undefined,
  });

  await transport.sendMail({ from, to, subject, text, html });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Not signed in" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Not signed in" }, 401);
  }

  // Reads through RLS as the caller themselves (staff_select is
  // is_active_staff()-gated) — this is the real "are they allowed to see
  // their own row" check, not a client-supplied claim about their role.
  const { data: callerStaff, error: staffError } = await callerClient
    .from("staff")
    .select("role, active")
    .eq("id", userData.user.id)
    .maybeSingle();

  if (staffError || !callerStaff?.active || callerStaff.role !== "Manager") {
    return json({ error: "Only a Manager can invite or resend staff invites" }, 403);
  }

  let body: {
    action?: "invite" | "resend";
    email?: string;
    name?: string;
    role?: string;
    staffId?: string;
    redirectTo?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  if (body.action === "resend") {
    const staffId = body.staffId?.trim();
    if (!staffId) {
      return json({ error: "staffId is required" }, 400);
    }

    // Same RLS read as the caller check above, this time for the target —
    // any active staff member can be read this way, which is exactly the
    // set a Manager should be allowed to resend an invite to.
    const { data: target, error: targetError } = await callerClient
      .from("staff")
      .select("id, name, email")
      .eq("id", staffId)
      .maybeSingle();
    if (targetError || !target) {
      return json({ error: "Staff member not found" }, 404);
    }

    // Re-checked against the Auth Admin API's own ground truth, not trusted
    // from whatever the client's Staff tab happened to render — the same
    // "RPC check is a UX nicety, this is the real boundary" relationship
    // used everywhere else in this build. Resending to someone who has
    // already signed in isn't dangerous exactly, but it's meaningless (they
    // already have a password) and worth a clear rejection rather than a
    // silently-sent, confusing email.
    const { data: authUser, error: authUserError } =
      await adminClient.auth.admin.getUserById(staffId);
    if (authUserError || !authUser.user) {
      return json({ error: "Staff member not found" }, 404);
    }
    if (authUser.user.last_sign_in_at) {
      return json({ error: "This person has already signed in — nothing to resend" }, 400);
    }

    const { data: linkData, error: linkError } = await adminClient.auth.admin.generateLink({
      type: "recovery",
      email: target.email,
      options: { redirectTo: body.redirectTo },
    });
    if (linkError) {
      return json({ error: linkError.message }, 400);
    }

    const actionLink = linkData.properties.action_link;
    try {
      await sendMail(
        target.email,
        "Finish setting up your TCS account",
        `Hi ${target.name},\n\nA Manager has resent your invite to TCS. Use the link below to set your password and sign in:\n\n${actionLink}\n\nIf you weren't expecting this, you can ignore this email.`,
        `<p>Hi ${target.name},</p><p>A Manager has resent your invite to TCS. Use the link below to set your password and sign in:</p><p><a href="${actionLink}">Finish setting up your account</a></p><p>If you weren't expecting this, you can ignore this email.</p>`,
      );
    } catch (err) {
      return json(
        { error: err instanceof Error ? err.message : "Could not send the invite email" },
        502,
      );
    }

    return json({ email: target.email });
  }

  // action: "invite" (default) — original behaviour, unchanged.
  const email = body.email?.trim().toLowerCase();
  const name = body.name?.trim();
  const role = body.role;

  if (!email || !name || !role || !ALLOWED_ROLES.includes(role)) {
    return json({ error: "email, name, and a valid role are all required" }, 400);
  }

  // handle_new_staff_signup() (see the Session 20 migration) reads role/name
  // straight out of this metadata and creates the linked staff row the
  // moment this call succeeds — before the invited person has done anything
  // at all. That trigger is what actually creates the staff row; this
  // function never inserts into staff directly.
  //
  // redirectTo comes from the calling browser (window.location.origin +
  // "/accept-invite" — see staff-store.ts's inviteStaff()), not hardcoded
  // here, since Deno.env doesn't know the caller's own origin. Trusting a
  // client-supplied redirect isn't the open-redirect risk it looks like:
  // GoTrue itself only ever honors a redirect_to that matches config.toml's
  // (or the hosted project's dashboard) site_url/additional_redirect_urls
  // allow-list — anything else is silently ignored in favor of the
  // configured default, regardless of what this function passes through.
  const { data: invited, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
    email,
    {
      data: { name, role },
      redirectTo: body.redirectTo,
    },
  );

  if (inviteError) {
    return json({ error: inviteError.message }, 400);
  }

  return json({ id: invited.user.id, email: invited.user.email });
});
