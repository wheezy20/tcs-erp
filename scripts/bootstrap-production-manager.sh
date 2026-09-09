#!/usr/bin/env bash
#
# Creates exactly ONE real, protected Manager account on a real (hosted)
# Supabase project — the very first staff login, before anyone exists yet
# to invite anyone through the app's own Settings > Staff screen.
#
# Deliberately separate from scripts/seed-local-dev-staff.sh, and the
# inverse of its safety check: that script refuses to run against anything
# but a local API_URL; this one refuses to run against localhost/127.0.0.1
# (local dev has its own seed mechanism — this script has no reason to ever
# touch it, and running it there by mistake would just be noise).
#
# This is NOT invoked from the app, not from a migration, not from CI —
# it is meant to be run BY HAND, ONCE, by whoever holds the real project's
# service_role key, against the real hosted project. See CLAUDE.md's
# "Bootstrapping the first production Manager" section for the exact
# command and context.
#
# What it does, mirroring the invite flow every subsequent staff member
# goes through (see supabase/functions/invite-staff/), not a special,
# separate mechanism:
#   1. Calls the same Admin API invite endpoint
#      (supabase.auth.admin.inviteUserByEmail() calls under the hood) with
#      role: "Manager" in the invite's own metadata — handle_new_staff_signup()
#      (Session 20 migration) reads that and creates the linked staff row
#      immediately, exactly like any other invite. The invite carries a
#      redirect_to of "$APP_URL/accept-invite", matching what the
#      invite-staff Edge Function passes (window.location.origin +
#      "/accept-invite") so the invited Manager lands on the set-password
#      screen, not the bare app root. GoTrue only honors a redirect_to that
#      is on the hosted project's site_url / additional_redirect_urls
#      allow-list, so APP_URL must match one of those.
#   2. Flips protected = true on that one row directly — the one thing an
#      ordinary invite (via the Edge Function) can never do, and the only
#      reason this script exists instead of just using the Settings UI once
#      a Manager exists.
#
# Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY for the real, hosted
# project (from the Supabase dashboard — Project Settings > API), the
# deployed app's base URL APP_URL (e.g. https://erp.school.example — the
# invite link's redirect target, must be allow-listed in the project's
# auth URL config), and the new Manager's email/name. Never hardcode a
# hosted project's credentials into this file or pass them on a shared
# shell history; export them in your own terminal first.
#
# Usage:
#   SUPABASE_URL="https://<ref>.supabase.co" \
#   SUPABASE_SERVICE_ROLE_KEY="<service_role key>" \
#   APP_URL="https://erp.school.example" \
#   MANAGER_EMAIL="owner@realbusiness.com" \
#   MANAGER_NAME="Real Owner Name" \
#   ./scripts/bootstrap-production-manager.sh

set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (from the hosted project's dashboard) before running this." >&2
  exit 1
fi

if [[ "$SUPABASE_URL" == *"127.0.0.1"* || "$SUPABASE_URL" == *"localhost"* ]]; then
  echo "Refusing to run: SUPABASE_URL ('$SUPABASE_URL') looks like a local address." >&2
  echo "This script is for bootstrapping a real, hosted project's first Manager — local dev already has scripts/seed-local-dev-staff.sh for this." >&2
  exit 1
fi

if [[ -z "${MANAGER_EMAIL:-}" || -z "${MANAGER_NAME:-}" ]]; then
  echo "Set MANAGER_EMAIL and MANAGER_NAME for the real person this account belongs to." >&2
  exit 1
fi

if [[ -z "${APP_URL:-}" ]]; then
  echo "Set APP_URL to the deployed app's base URL (e.g. https://erp.school.example)." >&2
  echo "The invite link redirects there + '/accept-invite'; it must be on the project's auth redirect allow-list." >&2
  exit 1
fi
if [[ ! "$APP_URL" =~ ^https?:// ]]; then
  echo "APP_URL ('$APP_URL') must be an absolute http(s) URL." >&2
  exit 1
fi
APP_URL="${APP_URL%/}"
REDIRECT_TO="$APP_URL/accept-invite"

echo "About to send a REAL invite email to: $MANAGER_EMAIL"
echo "  Name:     $MANAGER_NAME"
echo "  Role:     Manager (protected — cannot be demoted, deactivated, or deleted by anyone afterward)"
echo "  Project:  $SUPABASE_URL"
echo "  Redirect: $REDIRECT_TO"
echo
read -r -p "Type BOOTSTRAP to confirm and proceed: " CONFIRM
if [[ "$CONFIRM" != "BOOTSTRAP" ]]; then
  echo "Aborted — no changes made." >&2
  exit 1
fi

echo
echo "== Sending invite =="
# redirect_to is a query param on /auth/v1/invite (this is what
# supabase.auth.admin.inviteUserByEmail(email, { redirectTo }) sends under
# the hood, and what supabase/functions/invite-staff/index.ts forwards from
# the browser). Without it the invite link lands on the project's site_url
# root instead of the set-password screen. URL-encoded via jq's @uri.
REDIRECT_TO_ENC=$(jq -rn --arg u "$REDIRECT_TO" '$u|@uri')
INVITE_RESP=$(curl -s -X POST "$SUPABASE_URL/auth/v1/invite?redirect_to=$REDIRECT_TO_ENC" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg email "$MANAGER_EMAIL" --arg name "$MANAGER_NAME" \
    '{email: $email, data: {name: $name, role: "Manager"}}')")

USER_ID=$(echo "$INVITE_RESP" | jq -r '.id // empty')
if [[ -z "$USER_ID" ]]; then
  echo "Invite failed:" >&2
  echo "$INVITE_RESP" >&2
  exit 1
fi
echo "  Invited. User id: $USER_ID"

echo "== Marking the linked staff row protected =="
PATCH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$SUPABASE_URL/rest/v1/staff?id=eq.$USER_ID" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"protected": true}')

if [[ "$PATCH_STATUS" != "204" ]]; then
  echo "Failed to set protected = true (HTTP $PATCH_STATUS)." >&2
  echo "The invite already went out and the staff row exists as Manager — check it directly (e.g. in Supabase Studio) and set protected manually if this step didn't take." >&2
  exit 1
fi

echo "  Done — protected = true."
echo
echo "$MANAGER_EMAIL will receive a real invite email. Once they click it and set a password,"
echo "they'll land in the app as a protected Manager — role, active status, and the protected"
echo "flag itself can never be changed or deleted by anyone from this point on, per the"
echo "staff_protect_row trigger (Session 20 migration), not just this script's own convention."
