#!/usr/bin/env bash
#
# Creates four LOCAL-ONLY test staff accounts — one per role (Attendant,
# Manager, Accountant, Auditor) — so there's always a known-good login for
# every role when testing through /login. Deliberately NOT a migration or
# supabase/seed.sql: those run automatically (via `supabase db reset`, and
# migrations can be pushed to a real project via `supabase db push`), and
# credentials have no business living in a file that could ever go out that
# way by accident. This script is manual-only — nobody and nothing runs it
# for you.
#
# Uses the Admin API + the service_role key throughout (bypasses RLS
# entirely, and per the service_role_grants migration has normal full table
# access), so it refuses to run against anything but a local API_URL as a
# safety check.
#
# Safe to re-run after a `supabase db reset` — recreates the three accounts.
# Credentials are documented in CLAUDE.md under "Local dev-only test accounts".

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

STATUS=$(npx supabase status -o env 2>/dev/null || true)
API_URL=$(echo "$STATUS" | grep '^API_URL=' | cut -d'"' -f2)
SERVICE_ROLE_KEY=$(echo "$STATUS" | grep '^SERVICE_ROLE_KEY=' | cut -d'"' -f2)

if [[ -z "$API_URL" || -z "$SERVICE_ROLE_KEY" ]]; then
  echo "Could not read API_URL/SERVICE_ROLE_KEY from 'supabase status' — is the local stack running? (npx supabase start)" >&2
  exit 1
fi

if [[ "$API_URL" != *"127.0.0.1"* && "$API_URL" != *"localhost"* ]]; then
  echo "Refusing to run: API_URL ('$API_URL') is not a local address." >&2
  echo "This script uses the service_role key, which bypasses RLS entirely — it must never run against a real project." >&2
  exit 1
fi

PASSWORD="local-dev-2026"

create_or_get_user_id() {
  local email="$1" name="$2"
  local resp id

  resp=$(curl -s -X POST "$API_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg email "$email" --arg password "$PASSWORD" --arg name "$name" \
      '{email: $email, password: $password, email_confirm: true, user_metadata: {name: $name}}')")

  id=$(echo "$resp" | jq -r '.id // empty')
  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi

  # Already exists from a previous run — look it up instead of failing.
  local page=1
  while :; do
    local list count
    list=$(curl -s "$API_URL/auth/v1/admin/users?page=$page&per_page=200" \
      -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")
    id=$(echo "$list" | jq -r --arg email "$email" '.users[]? | select(.email == $email) | .id' | head -1)
    [[ -n "$id" ]] && break
    count=$(echo "$list" | jq -r '.users | length')
    [[ "$count" -eq 0 ]] && break
    page=$((page + 1))
  done

  if [[ -z "$id" ]]; then
    echo "Failed to create or find user $email:" >&2
    echo "$resp" >&2
    exit 1
  fi
  echo "$id"
}

set_role() {
  local id="$1" role="$2"
  curl -s -X PATCH "$API_URL/rest/v1/staff?id=eq.$id" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" -H "Prefer: return=minimal" \
    -d "$(jq -n --arg role "$role" '{role: $role, active: true}')" >/dev/null
}

echo "== dev-attendant@tcs.test (Attendant) =="
ATT_ID=$(create_or_get_user_id "dev-attendant@tcs.test" "Dev Attendant")
set_role "$ATT_ID" "Attendant"
echo "  id: $ATT_ID"

echo "== dev-manager@tcs.test (Manager) =="
MGR_ID=$(create_or_get_user_id "dev-manager@tcs.test" "Dev Manager")
set_role "$MGR_ID" "Manager"
echo "  id: $MGR_ID"

echo "== dev-accountant@tcs.test (Accountant) =="
ACC_ID=$(create_or_get_user_id "dev-accountant@tcs.test" "Dev Accountant")
set_role "$ACC_ID" "Accountant"
echo "  id: $ACC_ID"

echo "== dev-auditor@tcs.test (Auditor) =="
AUD_ID=$(create_or_get_user_id "dev-auditor@tcs.test" "Dev Auditor")
set_role "$AUD_ID" "Auditor"
echo "  id: $AUD_ID"

echo ""
echo "Done. Sign in at /login with any of the four accounts — credentials are in CLAUDE.md under 'Local dev-only test accounts'."
