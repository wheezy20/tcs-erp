#!/usr/bin/env bash
# Golden payslip suite: holds create_payslip(), post_payroll_run() and the
# run-exclusion flow to hand-derived figures (supabase/golden/). Runs both
# tiers through the role-matrix harness, each probe in a rolled-back
# transaction, against the local database.
#
#   ./scripts/golden-payslips.sh
#
# Needs the local stack running, a fresh `npx supabase db reset` and
# `./scripts/seed-local-dev-staff.sh`. Exit code: 0 when every case in both
# files passes, otherwise the worst code from scripts/role-matrix.sh
# (1 = a wrong figure, a setup failure, or the database/staff missing;
# 2 = usage error). Both files always run, even if the first fails.

set -uo pipefail

cd "$(dirname "$0")/.."

worst=0
for entry in \
  "supabase/golden/payslips.sql|statutory-derived, Eyram-given and TCS OS parity" \
  "supabase/golden/payslips-tcsos-hand.sql|TCS OS hand-computed, not ERP-confirmed" \
  "supabase/golden/staff-advances.sql|staff advances, statutory-derived"; do
  file="${entry%%|*}"
  tier="${entry#*|}"
  echo "=== $file ($tier)"
  ./scripts/role-matrix.sh "$file"
  rc=$?
  echo "=== $file: exit $rc"
  echo
  (( rc > worst )) && worst=$rc
done

if (( worst == 0 )); then
  echo "Golden payslip suite: all cases pass."
else
  echo "Golden payslip suite: FAILED (exit $worst). Never fix a case by editing its expected figure."
  echo "(SETUP FAILED on many cases usually means the database wasn't freshly reset: run"
  echo " npx supabase db reset && ./scripts/seed-local-dev-staff.sh, then try again.)"
fi
exit "$worst"
