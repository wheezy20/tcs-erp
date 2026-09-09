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
- **RLS is role-based**, checked via `has_role()` / `is_active_staff()`
  helper functions (never hand-rolled per-table logic). Four roles on
  `staff.role`, split from the original combined "Accountant/Auditor" by
  `20260909090000_split_accountant_auditor_roles.sql`:
  - **Manager** — full read/write/delete everywhere.
  - **Accountant** — Manager-equivalent write on the *finance modules*
    (Payroll, Accounting, Expenses); read-only elsewhere (everywhere the
    old combined role could read).
  - **Auditor** — read-only everywhere the old combined role could read;
    no write access anywhere.
  - **Attendant** — Sales / POS / returns / invoices; no finance access.
  Three predicate/guard functions carry this:
  - `can_write()` = active staff AND not (Accountant or Auditor) — the
    ordinary-table write predicate, i.e. "Manager + Attendant". Used in
    every ordinary table's insert/update RLS policy.
  - `require_writable_role()` — RPC guard that rejects **only Auditor**.
    Accountant passes it; whether it can actually write is then decided by
    the target table's RLS (ordinary tables keep Accountant out via
    `can_write()`) or by `require_finance_writer()` (finance RPCs).
  - `require_finance_writer()` — rejects anyone who isn't Manager or
    Accountant. The guard at the top of every finance RPC
    (`create_expense`, `create_account`, `post_journal_entry`,
    `reverse_journal_entry`, `create_payroll_run`, `create_payslip`, …).
  Finance-module tables: writes gated `has_role(['Manager','Accountant'])`,
  selects `has_role(['Manager','Accountant','Auditor'])`. Everywhere else
  the old combined role could read (Banking, Purchasing, Suppliers, the
  Audit Log): selects gain Auditor, writes stay Manager-only.
  - Payroll adds a fourth shade inside the Manager/Accountant write scope:
    creating an employee and changing basic salary / bank details are
    *proposed* by an Accountant and only take effect on *Manager* approval
    (`approve_*` RPCs check `has_role(['Manager'])`). See the approval
    state-machine convention below.
  - Documented tradeoff: a direct RPC call by an Accountant to an
    *ordinary* RPC (e.g. `create_invoice()`) fails on RLS deep inside the
    function rather than with an early friendly message. The security
    boundary holds; only the error text is worse. Not worth widening 20+
    RPC guards to fix.
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

- **Effective-dated config instead of mutable single rows.** Employee pay
  configuration (`employee_pay_config`), statutory rates
  (`statutory_rates`), and PAYE bands (`paye_bands`) are all
  effective-dated (`effective_from`/`effective_to`) rather than a row
  that gets updated in place. A payslip references the config row that
  was active at the time it was generated, so a later raise or rate
  correction never silently rewrites a historical payslip.
- **Flexible allowance system, not fixed columns.** `allowance_types`
  (a school-editable list — Extra Classes, Transport, etc., each flagged
  taxable or not) + `employee_allowances` (standing per-employee defaults) +
  `payslip_allowances` (the actual amount applied on one month's
  payslip). Mirrors the same instinct as Wilelik's `expense_categories`
  — a configurable list beats hardcoded columns whenever the set of
  values is something the school itself will want to edit.
- **Overtime is deliberately NOT part of the flexible allowance system.**
  It's structurally different (an hours × rate calculation, not a flat
  named amount), so it stays as its own `overtime_hours` /
  `overtime_rate` /computed `overtime_pay` fields directly on the
  payslip.
- **Per-employee statutory exemption flags.** `pays_ssnit`, `pays_tier2`,
  `pays_paye` on `employee_pay_config`, independently toggleable — covers
  National Service personnel and any other temporary/contract staff who
  don't participate in some or all of the standard deductions. These are a
  **direct** edit (`set_pay_config_exemptions()` RPC, Manager/Accountant,
  no approval) — only basic salary and bank details are approval-gated.
- **Financial records: select-only tables, writes only through their own
  `SECURITY DEFINER` function.** `payroll_runs` / `payslips` /
  `payslip_allowances` / `employees` / `employee_pay_config` (like
  `journal_entries` before them) have a `select` RLS policy and *no*
  `insert`/`update`/`delete` policy or grant for `authenticated` — every
  write goes through a `SECURITY DEFINER` RPC that re-checks the role:
  `create_payroll_run()` / `create_payslip()` / `delete_payslip()` /
  `post_payroll_run()` for the run side, and `propose_employee()` /
  `approve_employee()` / `propose_pay_config_change()` /
  `approve_pay_config()` / … for the employee side (`20260909130000`).
  This keeps computed figures un-forgeable *and* makes the approval trail
  un-bypassable — even a Manager cannot PATCH `employee_pay_config`
  directly. `employee_allowances` and the statutory rate/band tables stay
  on plain role-based RLS (a Manager or Accountant edits them directly);
  `allowance_types` likewise.
- **Mutation window on lifecycle records.** Where a record has a
  draft→final lifecycle (`payroll_runs.status`), delete/regenerate is
  allowed only while it's a draft — `delete_payslip()` and
  `create_payslip()` both refuse once the run is Posted, and
  `payroll_runs_delete` RLS requires `status = 'Draft'`. `payroll_runs`
  has no UPDATE grant/policy at all, so `post_payroll_run()` (SECURITY
  DEFINER) is the only thing that ever flips the status. Corrections after
  that are new offsetting records, never edits (same rule as posted
  journal entries).
- **Posting a batch record to the ledger: one aggregated entry, its own
  poster, explicit not automatic.** `post_payroll_run(run_id)` follows the
  Session 14 auto-poster shape (`SECURITY DEFINER`, builds a `jsonb` line
  array, calls the private `_post_journal_entry_rows()` with
  `source_table`/`source_id` so the unique constraint blocks a
  double-post) — but, like `post_day_close_journal_entry()`, it sums the
  whole batch into **one** journal entry rather than one per payslip, and
  it's an explicit Manager/Accountant action (`require_finance_writer()`),
  never fired from inside `create_payslip()`. Atomic: the entry and the
  `status → 'Posted'` flip commit together. Lines whose aggregate is zero
  are omitted (a zero-amount `journal_lines` row violates
  `journal_lines_has_amount`). Payroll's mapping: Dr `5140` gross; Cr
  `2300` net (payable — accrued, not disbursed); Cr `2310`/`2320`/`2330`
  SSNIT / Tier 2 / PAYE withheld; Cr `1350` IOU (repayment reduces the
  advance asset — the counterpart to `post_expense_journal_entry()`
  debiting `1350` for a "Staff advances" expense); Cr `4910` fines. The
  employer's 13% SSNIT contribution (`payslips.ssnit_employer`,
  snapshotted by `create_payslip()` on the same `pays_ssnit` flag) posts
  as a self-balancing pair on top — Dr `5145` Employer SSNIT Contribution
  / Cr `2310` SSNIT Payable — so `2310` carries both the withheld employee
  portion and the employer portion, and total staffing cost reads as
  `5140 + 5145` (`20260909120000`).
- **Multi-row RPC input is `jsonb`, not a composite-type array.**
  `create_payslip(p_allowances jsonb)` follows `create_invoice()` /
  `create_sale()`'s `p_lines jsonb` convention — `jsonb_array_elements` in
  the function body, an array of plain objects from the client. Composite
  type arrays (`create type ... as (...)` + `foo[]`) work in raw SQL but
  are a PostgREST footgun; don't reach for them.
- **Paid person vs ERP login are two tables.** `employees` is everyone TCS
  pays (teachers, drivers, kitchen staff — most with no login for a long
  time); `staff` is an ERP sign-in account. `staff.employee_id` optionally
  links the two (an Accountant who is also paid). `employee_pay_config` /
  `employee_allowances` / `payslips` all key off `employees.id`.
  `name` / `phone` / `position` / `department` live on `employees` (they
  are current-state 1:1 facts — the effective-dated pattern is only for
  values reconstructed *as-of a past date*, which org placement isn't).
  (`20260909130000_employees_and_approval_workflow.sql`.)
- **Approval workflow = an in-row state machine, not a parallel proposals
  table.** Three actions need Manager sign-off, proposed by an Accountant:
  creating an employee, changing basic salary, changing bank/account
  number. A pending proposal is *a row in a pending state* —
  `employees.employment_status = 'Pending Approval'`, or an
  `employee_pay_config` row with `approval_status = 'Pending Approval'` —
  so it reuses the effective-dated snapshot pattern directly and never
  touches live data (`create_payslip()` and every "current config" query
  filter `approval_status = 'Active'` / `employment_status = 'Active'`).
  Approve promotes it (`approve_pay_config()` closes the current open row
  with `effective_to = proposal.effective_from - 1`, then flips the
  pending row to `Active`); reject/withdraw tombstones it
  (`approval_status = 'Rejected'`, `effective_to` stays null, filtered out
  everywhere). Partial unique indexes enforce *one current approved row*
  (`where effective_to is null and approval_status = 'Active'`) and *one
  outstanding proposal* (`where approval_status = 'Pending Approval'`) per
  employee. **No same-period corrections** — a proposal's effective date
  must be a future month with no posted payslip; fixing the current period
  isn't supported (add a dedicated correction RPC later if it's ever
  needed). Suspend/reactivate (`Active` ⇄ `Suspended`) is a *direct*
  Accountant/Manager action, no gate. Every propose/approve/reject/suspend
  lands in `audit_log` (new action values) via `AFTER` triggers on
  `employees` / `employee_pay_config` — audit_log stays trigger-written-
  only, actor `coalesce(auth.uid(), proposed_by)`, skipped when null
  (seed/migration).
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
