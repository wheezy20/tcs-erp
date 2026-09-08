#!/usr/bin/env bash
#
# Checks the LOCAL database for duplicate function overloads (same name,
# different argument signature) and fails hard if any exist. Run this
# alongside tsc/lint/db reset before every commit that touches
# supabase/migrations/ — the same habitual place those already run.
#
# Three real incidents now — create_sale_return(), create_invoice(), and
# _post_journal_entry_rows() — were CREATE OR REPLACE FUNCTION with a
# changed argument list. Postgres treats a changed signature as defining a
# NEW, separate overload rather than replacing the original, silently
# leaving the old one behind; a later caller can then hit an ambiguous-call
# error, or worse, silently resolve to the wrong version. See CLAUDE.md's
# migration-writing guidance for the rule this check exists to catch
# violations of.
#
# Queries pg_proc directly rather than parsing migration SQL text — the
# database itself is the actual authority on whether a migration replaced
# a function or minted a second one, and no text parser can reliably beat
# that (dollar-quoting, comments containing apostrophes, and semicolons
# inside string literals all make a static scan genuinely fragile — hit
# more than once while auditing this schema's own seed data). Every RPC in
# this schema is called with exactly one fixed argument list; this project
# has no legitimate function overloading anywhere, so any duplicate name
# found here is real.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RESULT=$(npx supabase db query --local "
  select proname, count(*) as overload_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
  group by proname
  having count(*) > 1
  order by proname;
")

DUPES=$(echo "$RESULT" | jq -c '.rows')

if [[ "$DUPES" == "[]" ]]; then
  echo "No duplicate function overloads found."
  exit 0
fi

echo "Duplicate function overload(s) found in the public schema:" >&2
echo "$DUPES" | jq -r '.[] | "  \(.proname): \(.overload_count) versions"' >&2
echo >&2
echo "A migration likely changed an existing function's argument list via" >&2
echo "CREATE OR REPLACE FUNCTION without first DROP FUNCTION IF EXISTS-ing" >&2
echo "the old signature, so Postgres kept both. Find every signature with:" >&2
echo "  select oid::regprocedure from pg_proc where proname = '<name>';" >&2
echo "then drop the stale one explicitly in a new migration." >&2
exit 1
