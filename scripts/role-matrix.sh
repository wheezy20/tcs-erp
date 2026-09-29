#!/usr/bin/env bash
#
# Runs a file of SQL probes once per role (anon, Attendant, Manager,
# Accountant, Auditor, Admissions Officer) against the LOCAL database and prints a grid of
# which role each probe succeeded or failed for. Used by the test-runner
# subagent for every new/changed RPC or RLS policy — see CLAUDE.md's
# slice loop and .claude/agents/test-runner.md.
#
# Usage:
#   scripts/role-matrix.sh path/to/probes.sql
#
# Probe file format — blocks separated by header lines:
#
#   -- probe: create_admission_note as staff
#   -- expect: Manager,Attendant
#   select public.create_admission_note(...);
#
# `-- expect:` lists the roles that must SUCCEED; every other role must
# FAIL (raise an error). `anon`, `Attendant`, `Manager`, `Accountant`,
# `Auditor`, `Admissions Officer` are the valid names, comma-separated
# (spaces around commas are ignored; the space inside a name is kept);
# `none` means every role must fail. A
# mismatch prints MISMATCH and the script exits 1.
#
# Each probe runs in its own transaction that is always rolled back, so
# probes can freely insert/update/delete without leaving anything behind.
#
# Optional setup: inside a probe, lines above a `-- as role:` line run as
# `postgres` (bypassing RLS) before the role switch, in the same
# rolled-back transaction — use it to seed the rows a probe needs.
#
# RLS on SELECT filters rows silently rather than raising, so "0 rows" is
# a success here, not a denial. To assert a read is denied, seed a row in
# setup and write the probe so it raises when nothing is visible, e.g.:
#
#   -- probe: read applications
#   -- expect: Manager
#   insert into public.applications (...) values (...);
#   -- as role:
#   do $$ begin
#     if not exists (select 1 from public.applications) then
#       raise exception 'no rows visible';
#     end if;
#   end $$;
#
# Staff roles are impersonated as `authenticated` with a JWT `sub` claim
# set to one active staff row per role — the same identity auth.uid()
# resolves in a real request. Needs one active staff member per role; the
# dev accounts from scripts/seed-local-dev-staff.sh provide that (seed.sql
# has no Auditor), so run that script after every `supabase db reset`.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROBES="${1:-}"
if [[ -z "$PROBES" || ! -f "$PROBES" ]]; then
  echo "Usage: $0 path/to/probes.sql" >&2
  exit 2
fi

PROJECT_ID=$(grep -m1 '^project_id' supabase/config.toml | cut -d'"' -f2)
CONTAINER="supabase_db_${PROJECT_ID}"
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Local database container '$CONTAINER' isn't running (npx supabase start)." >&2
  exit 1
fi

psql_local() {
  docker exec -i "$CONTAINER" psql -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 "$@"
}

ROLES=(anon Attendant Manager Accountant Auditor "Admissions Officer")
declare -A SUB
for role in Attendant Manager Accountant Auditor "Admissions Officer"; do
  SUB[$role]=$(psql_local -c \
    "select id from public.staff where role = '$role' and active order by id limit 1;")
  if [[ -z "${SUB[$role]}" ]]; then
    echo "No active $role in public.staff — run ./scripts/seed-local-dev-staff.sh first." >&2
    exit 1
  fi
done

# Split the probe file into parallel arrays of name / expect / body.
NAMES=()
EXPECTS=()
SETUPS=()
BODIES=()
current_body=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^--[[:space:]]*probe:[[:space:]]*(.*)$ ]]; then
    if ((${#NAMES[@]} > 0)); then BODIES+=("$current_body"); fi
    NAMES+=("${BASH_REMATCH[1]}")
    SETUPS+=("")
    EXPECTS+=("")
    current_body=""
  elif [[ "$line" =~ ^--[[:space:]]*expect:[[:space:]]*(.*)$ ]] && ((${#NAMES[@]} > 0)); then
    # Trim around each comma-separated name, keeping inner spaces
    # ("Admissions Officer").
    expect_list=$(printf '%s' "${BASH_REMATCH[1]}" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g; s/^[[:space:]]+//; s/[[:space:]]+$//')
    EXPECTS[$((${#NAMES[@]} - 1))]="$expect_list"
  elif [[ "$line" =~ ^--[[:space:]]*as[[:space:]]+role:[[:space:]]*$ ]] && ((${#NAMES[@]} > 0)); then
    SETUPS[$((${#NAMES[@]} - 1))]="$current_body"
    current_body=""
  else
    current_body+="$line"$'\n'
  fi
done <"$PROBES"
if ((${#NAMES[@]} > 0)); then BODIES+=("$current_body"); fi

if ((${#NAMES[@]} == 0)); then
  echo "No '-- probe:' blocks found in $PROBES." >&2
  exit 2
fi

run_as() {
  local role="$1" setup="$2" body="$3" preamble
  if [[ "$role" == "anon" ]]; then
    preamble="set local role anon;
set local request.jwt.claims = '{\"role\":\"anon\"}';"
  else
    preamble="set local role authenticated;
set local request.jwt.claims = '{\"sub\":\"${SUB[$role]}\",\"role\":\"authenticated\"}';"
  fi
  printf 'begin;\n%s\n%s\n%s\nrollback;\n' "$setup" "$preamble" "$body" | psql_local 2>&1 >/dev/null
}

status=0
printf '%-44s' "probe"
for role in "${ROLES[@]}"; do printf '%-12s' "$role"; done
printf '\n'

for i in "${!NAMES[@]}"; do
  expect=",${EXPECTS[$i]},"
  printf '%-44s' "${NAMES[$i]:0:43}"
  # A broken setup would otherwise read as "denied" for every role and
  # silently pass a denial probe — so check it on its own first.
  if [[ -n "${SETUPS[$i]}" ]] &&
    ! err=$(printf 'begin;\n%s\nrollback;\n' "${SETUPS[$i]}" | psql_local 2>&1 >/dev/null); then
    printf 'SETUP FAILED\n    %s\n' "$(echo "$err" | grep -m1 'ERROR' || echo "$err" | head -1)"
    status=1
    continue
  fi
  errors=()
  for role in "${ROLES[@]}"; do
    # Exit status decides (ON_ERROR_STOP); stderr may also carry NOTICEs.
    if err=$(run_as "$role" "${SETUPS[$i]}" "${BODIES[$i]}"); then
      result="ok"
    else
      result="denied"
      errors+=("    $role: $(echo "$err" | grep -m1 'ERROR' || echo "$err" | head -1)")
    fi

    if [[ -n "${EXPECTS[$i]}" ]]; then
      if [[ "$expect" == *",$role,"* ]]; then want="ok"; else want="denied"; fi
      if [[ "$result" != "$want" ]]; then
        result="$result!"
        status=1
      fi
    fi
    printf '%-12s' "$result"
  done
  printf '\n'
  for e in "${errors[@]}"; do echo "$e"; done
done

if ((status != 0)); then
  echo
  echo "FAILED: a cell marked '!' doesn't match its '-- expect:' line, or a setup failed." >&2
fi
exit "$status"
