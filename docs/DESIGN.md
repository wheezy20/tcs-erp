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
  `payment_providers` (`20260909140000` as `banks`; renamed + given a
  `kind` column — `'Bank' | 'Mobile Money'` — in `20260909150000`) is the
  same shape: a school-editable list, seeded in the migration (it's
  entity-wide reference data, not branch-scoped), that drives the
  bank / mobile-money picker on the employee flow.
  `employee_pay_config.bank` stays plain `text` — the list constrains the
  picker, it isn't an FK. `positions` and `departments`
  (`20260909160000`) are two more lists of exactly the same shape —
  `name` (unique) / `position` / `is_active`, select for M/Acc/Aud, write
  for M/Acc, seeded in the migration, entity-wide — driving the position
  and department dropdowns on the employee flow. `employees.position` /
  `.department` likewise stay plain `text` (no FK); a stored value not in
  the active list still round-trips, flagged "(not in list)" in the
  picker (`RefListSelect` / `PaymentProviderSelect`). The rule: whenever a
  free-text field turns out to be a small set the school will curate,
  promote it to one of these lists rather than adding an FK'd lookup
  table or a hardcoded enum.
- **Payment destination reuses two columns for both methods.**
  `employee_pay_config.payment_method` (`'Bank' | 'Mobile Money'`,
  `20260909150000`) decides how to read `bank` / `account_no`: for a bank
  it's the bank name + account number; for mobile money it's the network
  name + wallet phone. No dedicated `momo_*` columns — they would always
  be half-null, and nothing downstream (the payroll journal entry least of
  all) cares *how* net pay is disbursed. Changing the method rides the
  same approve gate as changing the bank/account (it's the same columns
  and the same `propose_pay_config_change` → `approve_pay_config` path).
  Recording the destination is the whole scope; actually disbursing a run
  (bank file, MoMo bulk push) is not built.
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
  allowed only while it's a draft — `delete_payslip()`, `create_payslip()`
  and the exclusion RPCs all refuse once the run leaves `'Draft'`, and
  `payroll_runs_delete` RLS requires `status = 'Draft'`. `payroll_runs`
  has no UPDATE grant/policy at all, so the four status RPCs
  (`submit_payroll_run_for_review()` / `reject_payroll_run()` /
  `post_payroll_run()`, all SECURITY DEFINER) are the only things that
  ever flip it. Corrections after posting are new offsetting records,
  never edits (same rule as posted journal entries).
- **Payroll run review state machine (`20260909150000`).**
  `Draft → Ready for Review → Posted`, with reject as the one way back:
  `submit_payroll_run_for_review()` (any finance writer) moves a complete
  Draft to review; `post_payroll_run()` (Manager only now — approval and
  posting are the *same* step) approves it and posts the ledger entry;
  `reject_payroll_run(reason)` (Manager, reason required) sends it back to
  Draft with `rejection_reason` set (cleared on the next submit). Payslip
  edits are already blocked on any non-Draft run, so `'Ready for Review'`
  locks them for free. "Complete" (enforced by submit, mirrored in the
  UI) = every `Active` employee with a current approved `employee_pay_config`
  either has a payslip on the run **or** a `payroll_run_exclusions` row —
  `_payroll_run_unaccounted()` is the shared definition. Employees with no
  approved config still can't be paid and don't block; they're a
  non-blocking warning. `payroll_run_exclusions` (per-run, `on delete
  cascade`, optional reason, RPC-only writes like `payslips`) is the
  "deliberately not paid this cycle" marker; `exclude_employee_from_run()`
  refuses an employee who already has a payslip. Every status transition
  and every exclusion add/remove lands in `audit_log` via `AFTER`
  triggers (`audit_payroll_run()` / `audit_payroll_run_exclusion()`), new
  action values `payroll_run_submitted` / `_approved` / `_rejected` /
  `payroll_run_exclusion_added` / `_removed`. A Manager may approve a run
  they submitted themselves — no self-review block, consistent with the
  rest of this app.
- **Posting a batch record to the ledger: one aggregated entry, its own
  poster, explicit not automatic.** `post_payroll_run(run_id)` follows the
  Session 14 auto-poster shape (`SECURITY DEFINER`, builds a `jsonb` line
  array, calls the private `_post_journal_entry_rows()` with
  `source_table`/`source_id` so the unique constraint blocks a
  double-post) — but, like `post_day_close_journal_entry()`, it sums the
  whole batch into **one** journal entry rather than one per payslip, and
  it's an explicit action — the Manager "approve" step of the review state
  machine above (Manager only since `20260909150000`; was
  `require_finance_writer()`), never fired from inside `create_payslip()`.
  Atomic: the entry and the `status → 'Posted'` flip commit together. Lines whose aggregate is zero
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
- **Uppercase normalization is a DB trigger, not client styling.**
  `employees.name` / `.position` / `.department` are forced to
  `upper(nullif(trim(x), ''))` by a `BEFORE INSERT OR UPDATE` trigger
  (`uppercase_employee_fields()`, `20260909160000`), so every write path —
  RPC, raw SQL, a future importer — stores them the same way and
  "Ama"/"AMA"/"ama" can't diverge. `positions` / `departments` get the
  same trigger (`uppercase_ref_list_name()`) and are seeded uppercase, so
  a stored `employees.department` always matches a list entry exactly.
  Phone is deliberately left exactly as entered. Extended `20260919` to
  every new HR-enrichment field that's a person's name or an ID-like
  value (`preferred_name`, `national_id`, `ssnit_number`, `tin_number`,
  `church_denomination`, `emergency_contact_name`) — same "Ama"/"AMA"/
  "ama" drift risk. `personal_email`/`school_email` go the *other*
  direction, lowercased by the same trigger — the real convention for
  email addresses, not left alone the way the original `phone`-only
  exception implied every contact field would be. `residential_address`/
  `qualifications` stay as-typed: genuine free text, no canonical casing.
  If another text column ever needs the same treatment, extend the
  existing trigger function rather than adding CSS `text-transform`
  (which only hides the inconsistency).
- **HR-enrichment fields (`20260919`) all stay current-state facts on
  `employees`, same as `phone`/`position`/`department` — none needed a
  new table.** Sourced from TCS's existing Google-Sheets HR system's
  staff-database columns, but not copied wholesale: bank name/account
  number and salary stay on `employee_pay_config` exactly as before
  (approval-gated, effective-dated) rather than being duplicated onto
  `employees` the way the flat spreadsheet has them — this repo already
  separates that correctly and the enrichment doesn't undo it. The source
  system's own `Staff Status` dropdown (Probationary/Confirmed/On Leave/
  Resigned/Terminated/Retired) is deliberately not ported as a second
  status column: "Probationary" vs "Confirmed" is derived from
  `probation_end_date` vs today (computed-never-stored, applied somewhere
  the source system didn't have it) rather than a status a person has to
  remember to flip in sync with the date; the departure-flavored values
  overlap with the explicitly-deferred Leave/Exit & Offboarding domains
  (see `docs/CONSTRAINTS.md`) and aren't solved by this table.
- **Document storage applies the receipts-bucket lesson from the first
  commit, not as a retrofit.** `onboarding-documents` (`20260920`) is
  `public = false` from its `insert into storage.buckets` — there is no
  "start public, fix later" phase the way `receipts` briefly had. Reads
  go through `supabase.storage.from(...).createSignedUrls()`
  (`employee-documents-store.ts`), never `getPublicUrl()`. Verified the
  same way the receipts fix was verified: fetching the bucket's
  `/object/public/<path>` endpoint directly returns `404 Bucket not
  found` (Storage refuses to serve a non-public bucket through that route
  at all, rather than a generic 403), while the signed URL for the same
  object resolves normally. `employee_documents` (metadata: employee_id,
  document_type, storage_path, uploaded_by, uploaded_at, notes) is a
  plain RLS-gated table shaped exactly like `employee_allowances` — select
  Manager/Accountant/Auditor, insert/update/delete Manager/Accountant, not
  approval-gated, no audit_log trigger (matches `employee_allowances`,
  not `employees`/`employee_pay_config` — audit_log is reserved for
  approval-state transitions, not every plain insert). Deliberately flat,
  no version history: that shape belongs to the *contract* lifecycle
  (Draft/Issued/Superseded, still to be built) which is a genuinely
  different problem and its own table, not a reuse of this one.
  A tokenized `anon` INSERT policy for this bucket — the public onboarding
  form's upload path — was scoped out on purpose rather than stubbed: it
  needs to look up its token in a table (`onboarding_tokens`) that doesn't
  exist until the onboarding-checklist phase, and referencing a
  nonexistent table in a policy fails the migration outright, so this
  isn't a dormant no-op sitting in the schema today. It arrives together
  with `onboarding_tokens` in that phase's own migration.
- **Onboarding checklist: manual vs. derived items, and the first
  anon-writable path in the app (`20260921`).** 18 real checklist items
  (from the live ACCEPTED_STAFF_ONBOARDING tracker, not just the Apps
  Script source) split into two kinds on `onboarding_checklist_items` —
  `is_derived = false` (a human does something; toggled through
  `toggle_onboarding_task()`, never a raw table write) and
  `is_derived = true` (the fact already lives elsewhere in this schema;
  a trigger recomputes it, never manually toggleable). Two collapses from
  the original four named derived signals to two catalog items: "Bank
  Details Form" and "Payroll Added" are the identical predicate (an
  Active `employee_pay_config` row exists) under two names, and "Staff
  Email Created"/"Staff ID Issued" were both specified against the same
  compound condition (a linked `staff` row exists AND
  `employees.school_email` is set) — this schema has no way to
  distinguish those as separate facts, so two catalog rows that always
  flip together would double-count one signal with zero added
  information. `employees.onboarding_completed_at` is set once, by
  trigger, when every *active* item is done, and is **never cleared** —
  a catalog item added or reactivated later, or a manual item someone
  unchecks afterward, doesn't retroactively "unfinish" someone already
  onboarded. Deactivating a catalog item can *newly* satisfy that
  condition for employees stuck only on it, so deactivation also
  triggers a completion recheck.
  Known, accepted scope limits (not oversights): task rows are snapshotted
  once, at the employee's Active transition (or a manual
  `initialize_onboarding_checklist()` re-run) — a catalog item added or
  reactivated afterward does not retroactively appear on someone already
  mid-checklist. There's also no "revoke an unexpired token" RPC and no
  uniqueness constraint limiting one open token per employee — expiry is
  the only staleness mechanism; resending just generates another token.
  Both are deliberate simplicity choices for a first version, not gaps
  that block shipping.
  `employee_documents.document_type` (20260920) was widened from a
  4-value placeholder guess to the real 8 document-backed item names once
  this tracker showed what's actually asked for — those names double as
  `document_type` values, so `approve_onboarding_submission()` writes
  straight from the checklist item name with no separate mapping table.
  The **tokenized public form** (`/onboarding/$token`, auth-free in
  `__root.tsx` same as `/login`) is the first place this app accepts an
  anon write. The security shape, end to end:
  - **Generation** (`generate_onboarding_token()`, Manager/Accountant,
    Active employees only) mints 32 bytes from pgcrypto's
    `gen_random_bytes()` (a CSPRNG), returns the 64-hex-char raw token to
    the caller **exactly once**, and stores only its SHA-256 hash
    (`employee_onboarding_tokens.token_hash`, unique). There is no way to
    recover a usable token from the database afterwards, including for a
    Manager reading the table directly.
  - **Expiry** (`expires_at`, default 14 days) is checked on every use by
    both `is_valid_onboarding_token()` and `submit_onboarding_form()`.
  - **Single-use** is enforced with a row lock, not a bare
    `used_at is null` check: `submit_onboarding_form()` does
    `select ... for update` on the token row before anything else, then
    re-checks `used_at is null` inside the same transaction before
    setting it. A concurrent second submission for the same token blocks
    on that lock until the first commits, then finds it already used —
    there's no window where two submissions can both pass validation for
    one token.
  - **Storage uploads happen before the RPC call**, while the token is
    still unused — the frontend uploads each file first, collects the
    resulting paths, then calls `submit_onboarding_form()` last (the
    step that actually consumes the token). The `onboarding_documents_anon_insert`
    storage policy checks the token embedded in the object path
    (`onboarding/{token}/...`) via `is_valid_onboarding_token()` — a
    SECURITY DEFINER function returning only a boolean. Anon is never
    granted a direct read policy on `employee_onboarding_tokens` itself;
    a raw `select` policy narrow enough for the storage check to work
    would also hand back `employee_id`/`created_by`/`created_at` for
    every unexpired token to anyone who could enumerate the bucket path
    space, which the boolean function never does.
  - **What anon can never do**: read `employee_onboarding_tokens` or
    `employee_onboarding_submissions` (no grant, no policy); write to
    `employees`/`employee_pay_config`/`employee_documents` directly (no
    grant — only `approve_onboarding_submission()` touches those, and
    only after a human review); or resubmit through a used/expired token.
    The only two anon-reachable surfaces in the schema are the one
    storage insert policy above and three SECURITY DEFINER functions
    (`is_valid_onboarding_token`, `get_onboarding_context`,
    `submit_onboarding_form`), each doing its own token check internally.
  **Approval deliberately does not touch `employee_pay_config`.** The
  submission's bank/account fields are stored for HR's reference only —
  `approve_onboarding_submission()` copies personal-fact fields (DOB,
  national ID, emergency contact, address, qualifications — the same set
  `update_employee_profile()` already owns) and the uploaded documents,
  but leaves bank/account changes behind the existing Accountant-proposes/
  Manager-approves gate (`20260909130000`). Auto-applying a
  candidate-submitted bank detail on a single approval would quietly
  weaken the one two-person control that field exists to protect; HR
  reads the reviewed submission and proposes the pay config the normal
  way through the existing UI.
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
  everywhere). `propose_employee()` can *bundle* an initial pay config —
  the pending config for a still-pending employee is approved/rejected
  **with the employee record** (`approve_employee()` cascades), not on its
  own: `approve_pay_config()` refuses a config whose employee isn't
  `Active`, and the approval UI shows a bundled new hire as one
  proposal with one Approve/Reject (`splitPendingConfigs()` in
  `employees-store.ts` draws the bundled-vs-standalone line). Partial unique indexes enforce *one current approved row*
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
- **Amend-then-approve, not reject-then-resubmit — and the audit trail must
  say which one happened (`20260918`).** A Manager can correct a pending
  pay config's basic salary / payment method / bank / account number in the
  same click as approving it, rather than being forced through a full
  reject/resubmit cycle for a typo. `approve_pay_config()` and
  `approve_employee()` each gained four optional trailing parameters
  (`p_basic_salary`, `p_payment_method`, `p_bank`, `p_account_no`, all
  `default null` — "leave as proposed") rather than a separate
  `amend_and_approve_*` RPC: the bundled-vs-standalone split already forces
  two entry points (`approve_pay_config()` refuses a not-yet-`Active`
  employee's bundled config; `approve_employee()` cascades it instead), so
  widening both is no new surface, and it keeps "adjust" and "approve" one
  atomic statement/audit event instead of two. The override, when given, is
  applied in the *same* `update` that flips `approval_status` to `Active`,
  so `audit_employee_pay_config()`'s `OLD` row is always the Accountant's
  original proposal and `NEW` is whatever the Manager actually approved — a
  direct diff, no extra bookkeeping column. The trigger compares
  `(old.basic_salary, old.payment_method, old.bank, old.account_no)` against
  `new.*` on every Pending→Active transition; a real difference gets its own
  action, `pay_config_amended_and_approved`, with `before` set to the
  *original proposed values* (not just `{approval_status: 'Pending
  Approval'}` the way `pay_config_approved` records it) so the diff survives
  independently of the earlier `pay_config_proposed` row — an unamended
  approval is still exactly `pay_config_approved`, byte-for-byte unchanged.
  Scope is deliberately narrow: `effective_from` and the exemption flags are
  not amendable this way (exemptions are already direct-edit with no gate;
  `effective_from` carries its own posted-payslip re-validation that would
  complicate a same-statement amendment). Reject is untouched — no
  amendment path there. On the frontend, every Approve surface (the
  standalone pending-config panel and the bundled-hire status card on the
  employee profile page, and both rows of the list page's Approvals panel)
  offers an "Adjust before approving" toggle
  (`AdjustPayFields`/`PaymentDestinationFields` in
  `components/employees/payment-fields.tsx`) that always sends all four
  fields together when opened, even ones left unedited — the trigger's own
  diff is what decides whether anything actually counts as an amendment, so
  the frontend doesn't need to track per-field "touched" state.
- **Entity-wide reference data goes in the migration, not `seed.sql`.**
  Rows that must exist in *every* environment and have no branch/staff FK
  — the chart of accounts, statutory rates, PAYE bands, `payment_providers`,
  `positions`, `departments` — are inserted by the migration itself with
  `on conflict do nothing`. `seed.sql` never runs on a real deployment, so
  seed-only reference data silently ends up missing in production (the
  lesson of `20260819090000_seed_gap_accounts_expense_categories.sql`).
- **Two seed files, split by trust, not by content.**
  `supabase/seed.sql` is **local-dev only** — it is the only file in
  `config.toml`'s `[db.seed] sql_paths`, and that list drives `supabase db
  reset` and nothing else (no seed runs on `db push`). It carries demo
  people, dev-adjacent records, and Wilelik's leftover retail data.
  `supabase/seed.production.sql` is run **once by hand** against a hosted
  DB after `db push`; it is idempotent and carries **only** the
  branch-scoped reference rows the migrations structurally cannot seed on
  a brand-new project — the `branches` row itself, and then
  `expense_categories` / `expense_category_accounts` / `allowance_types`,
  which `20260819090000` skips when no branch exists yet. Everything
  entity-wide is already in via the migrations; `seed.production.sql` does
  not duplicate it. Zero demo people / logins / transactions in that file,
  ever.
- **`VITE_*` env vars are build-time, inlined — not runtime config.**
  Vite (via the Lovable config wrapper's `envDefine`, which runs
  `loadEnv` at config time) statically replaces every `import.meta.env.VITE_*`
  reference with a string literal during `vite build`. So
  `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` (read in
  `lib/supabase.ts`) are frozen into the JS bundle at build time and there
  is **no** runtime lookup — a Cloudflare Worker secret set after the
  build is invisible to the client code. They must be in the environment
  of the *build* step. The anon key is a public client credential (RLS is
  the boundary); a `service_role` key must never be inlined. Anything that
  genuinely needs to vary per-deploy without a rebuild would have to be
  read from the Worker `env` in `src/server.ts` and passed down — nothing
  does today.
- **The sidebar is grouped by what TCS actually uses, not a flat list**
  (`20260919`, `components/layout/app-sidebar.tsx`'s `navSections`).
  Dashboard stands alone at the top; Finance & Accounting and HR & Payroll
  are always-expanded sections; Procurement & Stores — every route this
  fork inherited that TCS doesn't run yet (Customers, Inventory, Sales &
  Invoicing, Pro-forma Invoices, Customer Deposits, POS, End of Day,
  Purchasing) — is its own collapsed-by-default, muted-style section, so a
  dormant module stays fully reachable without competing for attention.
  Settings is pinned to the bottom, its own divider, matching the same
  pattern reused in the Reports report-picker (`routes/reports.tsx`,
  `DORMANT_REPORT_IDS`) and the Dashboard's "Store & Sales" block
  (`routes/index.tsx`). **The next real module** (Transport, Kitchen,
  Asset Management, Analytics & BI, or anything else TCS eventually
  needs) gets its own new top-level section here the same way, once it's
  an actual route — never an empty/placeholder nav entry pointing nowhere.

## Branding

TCS naming has been applied throughout the fork (sidebar, login page,
document/report titles, exported filenames, localStorage keys, Supabase
`project_id`). Real TCS brand assets are in place (`20260909140000`
walkthrough follow-up): the favicon set + `site.webmanifest` under
`frontend/public/`, and `public/tcs-logomark.png` in the sidebar + login.
The master logo library lives in `frontend/brand/` (out of the web dir).
`--primary` is re-themed to the brand deep teal `#005e61` (`20260916`),
sampled directly from the artwork in `frontend/brand/` rather than
guessed — see "Two places define `--primary`" below and JOURNAL.md. A
true 48×48 favicon and a dark-mode logomark variant are still outstanding.

- **Two places define `--primary` — the runtime one wins.**
  `styles.css`'s `:root`/`.dark` `--primary` is only the pre-hydration/
  no-JS fallback. `AccentSync` (`components/settings/accent-sync.tsx`)
  always runs on mount and overwrites `--primary`/`--accent`/`--ring`/
  `--sidebar-primary`/`--sidebar-accent`/`--chart-1` with an inline style
  from `appearance.accent` (`settings-store.ts`, `localStorage`-backed —
  a school could pick its own accent color from Settings). So changing
  the CSS token alone has **no visible effect**; `DEFAULT_ACCENT` must
  change too, and that's the value that actually matters for what a
  fresh browser profile sees. Both are kept in sync to the same brand hex
  so there's no flash-of-wrong-color between first paint and hydration.
