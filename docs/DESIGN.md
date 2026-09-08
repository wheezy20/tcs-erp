# TCS ERP — Design Conventions

This file is the source of truth for backend/architectural conventions.
`CLAUDE.md` points here rather than restating them. Anything load-bearing
gets documented here in plain terms, not just inferred from reading old
migrations.

## Conventions inherited from Wilelik (keep these)

These aren't stylistic preferences — the schema and RLS policies actively
depend on them holding true for every new table/function added.

- **Create-can't-overwrite RPC discipline.** A "create" function never
  accepts a client-supplied id and never upserts — it's a plain insert.
  If a record needs editing later, that's a separate, explicitly-named
  `update_x()` function, not a second call to the create function. This
  is why `create_payslip()` (payroll) follows the same shape as
  `create_expense()` and `create_invoice()`.
- **`drop function if exists` before changing an argument list.**
  Postgres allows function overloading, so changing a function's
  parameters without dropping the old signature first leaves both
  versions live — a real bug class this codebase has hit before (see
  `scripts/check-duplicate-function-overloads.sh`).
- **Explicit grants per table**, not blanket exposure. Every new table
  needs its `anon`/`authenticated`/`service_role` grants decided
  deliberately. `service_role` gets full CRUD by default (it bypasses
  RLS anyway); withholding a grant from it buys nothing except on tables
  where even service_role shouldn't have update/delete (e.g. append-only
  audit logs, posted journal entries).
- **RLS is role-based, three tiers**, checked via the `has_role()` and
  `is_active_staff()` helper functions (never hand-rolled per-table
  logic). Payroll extends this by restricting to `Manager` and
  `Accountant/Auditor` only — Attendant has no access to payroll data at
  all.
- **Identity columns are server-forced, never client-supplied.** Columns
  like `recorded_by`, `issued_by`, `performed_by` default to `auth.uid()`
  and a trigger overwrites whatever the client sends whenever
  `auth.uid()` is non-null. The client cannot claim to be someone else.
- **Computed, never stored**, for anything derivable from other tables —
  reports, reconciliation figures, running balances. Storing a derived
  number invites it silently going stale.
- **Nullable-override-with-global-default** pattern — e.g. a global
  low-stock threshold with an optional per-product override. Same shape
  is available for anything else that's "usually one value, sometimes
  needs an exception."
- **Once posted/closed, no update/delete.** Journal entries, once
  posted, get no update or delete policy or grant at all — not even for
  service_role. A correction is a new offsetting entry, never an edit to
  history.
- **`getErrorMessage()` duck-typing** — `supabase-js` errors aren't real
  `Error` instances, so error handling needs to check shape, not rely on
  `instanceof Error`.
- **Accounting naming discipline.** In the reports/accounting UI and code,
  "gross profit" (revenue − cost of goods sold) and "operating margin"
  (gross profit − recorded expenses) are never shortened to "profit" or
  "net profit" — neither figure accounts for payroll, and conflating them
  is a real reporting error, not a wording preference.

## New conventions introduced for TCS-specific work

- **Effective-dated config instead of mutable single rows.** Staff pay
  configuration (`staff_pay_config`), statutory rates
  (`statutory_rates`), and PAYE bands (`paye_bands`) are all
  effective-dated (`effective_from`/`effective_to`) rather than a row
  that gets updated in place. A payslip references the config row that
  was active at the time it was generated, so a later raise or rate
  correction never silently rewrites a historical payslip.
- **Flexible allowance system, not fixed columns.** `allowance_types`
  (a school-editable list — Extra Classes, Transport, etc., each flagged
  taxable or not) + `staff_allowances` (standing per-staff defaults) +
  `payslip_allowances` (the actual amount applied on one month's
  payslip). Mirrors the same instinct as Wilelik's `expense_categories`
  — a configurable list beats hardcoded columns whenever the set of
  values is something the school itself will want to edit.
- **Overtime is deliberately NOT part of the flexible allowance system.**
  It's structurally different (an hours × rate calculation, not a flat
  named amount), so it stays as its own `overtime_hours` /
  `overtime_rate` /computed `overtime_pay` fields directly on the
  payslip.
- **Per-staff statutory exemption flags.** `pays_ssnit`, `pays_tier2`,
  `pays_paye` on `staff_pay_config`, independently toggleable — covers
  National Service personnel and any other temporary/contract staff who
  don't participate in some or all of the standard deductions.
- **Financial records: select-only tables, writes only through their own
  `SECURITY DEFINER` function.** `payroll_runs` / `payslips` /
  `payslip_allowances` (like `journal_entries` before them) have a
  `select` RLS policy and *no* `insert`/`update`/`delete` policy or grant
  for `authenticated` — every write goes through `create_payroll_run()` /
  `create_payslip()` / `delete_payslip()`, which are `SECURITY DEFINER`
  and re-check the role themselves. This keeps the computed figures
  un-forgeable (a client can't hand-insert a payslip row) without needing
  a per-column CHECK. Ordinary *config* tables (`allowance_types`,
  `staff_pay_config`, statutory rate/band tables) stay on plain three-tier
  RLS — a Manager edits them directly, same as `accounts`.
- **Mutation window on lifecycle records.** Where a record has a
  draft→final lifecycle (`payroll_runs.status`), delete/regenerate is
  allowed only while it's a draft — `delete_payslip()` refuses once the
  run is Posted, and `payroll_runs_delete` RLS requires `status = 'Draft'`.
  Corrections after that are new offsetting records, never edits (same
  rule as posted journal entries).
- **Multi-row RPC input is `jsonb`, not a composite-type array.**
  `create_payslip(p_allowances jsonb)` follows `create_invoice()` /
  `create_sale()`'s `p_lines jsonb` convention — `jsonb_array_elements` in
  the function body, an array of plain objects from the client. Composite
  type arrays (`create type ... as (...)` + `foo[]`) work in raw SQL but
  are a PostgREST footgun; don't reach for them.
- **Effective-dated config edit model.** Editing an effective-dated config
  row (`staff_pay_config`): if the effective date is unchanged it's a
  *correction* → plain in-place `UPDATE` (safe, because every dependent
  record — a payslip — snapshots the actual amounts at generation, so
  history is unaffected either way). A *later* effective date is a real
  change → close the open row (`effective_to` = day before) and insert a
  new open-ended one. A dedicated "record a pay change" flow can replace
  the heuristic later.
- **Entity-wide reference data goes in the migration, not `seed.sql`.**
  Rows that must exist in *every* environment and have no branch/staff FK
  — the chart of accounts, statutory rates, PAYE bands — are inserted by
  the migration itself with `on conflict do nothing`. `seed.sql` never
  runs on a real deployment, so seed-only reference data silently ends up
  missing in production (the lesson of
  `20260819090000_seed_gap_accounts_expense_categories.sql`). Branch-
  scoped demo data (sample pay configs, allowance types) still goes in
  `seed.sql`.

## Branding

TCS naming has been applied throughout the fork (sidebar, login page,
document/report titles, exported filenames, localStorage keys, Supabase
`project_id`). Real TCS logo/icon assets are still pending — the sidebar
and login currently render a plain text "TCS" badge as a placeholder.
See JOURNAL.md for the specific rebrand pass and what's still
outstanding.
