# TCS ERP — Journal

A running log, newest at the bottom. Not a full commit-by-commit record —
just the decisions and milestones worth remembering later, same spirit as
Wilelik's `docs/session-*.md` but rolling instead of one file per session.

---

## 2026-09-08 — Project kickoff, rebrand, repo setup

- Decided to build the TCS ERP by forking Wilelik ERP (Eyram's dad's
  business system) rather than starting from scratch, since the
  accounting/expenses engine already exists and is solid.
- Explored Royal Avenue's school management system (third-party demo
  access, via Claude in Chrome) to source feature ideas — module list,
  fee/finance structure, attendance/gradebook approach, parent portal.
  Notable takeaways: event-triggered communication templates, a
  category-based (A1/A2/A3) fee differentiation model, automatic arrears
  rollover, and a real gap in their product around timetabling.
- Scoped **Phase 1** to Accounting/Finance, Expenses (already built),
  and Payroll (SSNIT/PAYE/Tier 2/payslips/staff overview) — deferring
  Student Management, Attendance, Exams, Communication, Parent Portal,
  and Timetable to later phases.
- Confirmed the actual statutory split against Eyram's existing payroll
  practice: SSNIT 0.5% employee + 13% employer, Tier 2 5% employee.
  Confirmed some staff (National Service personnel) are exempt from all
  three.
- Designed and drafted the payroll schema migration
  (`20260908070000_payroll_schema.sql`): `allowance_types`,
  `staff_pay_config`, `staff_allowances`, `statutory_rates`,
  `paye_bands`, `payroll_runs`, `payslips`, `payslip_allowances`, plus a
  `create_payslip()` calculation function. Not yet applied to the repo.
- Local folder flattened (had ended up double-nested as
  `tcs-erp/tcs-erp/wilelik-erp-main/` from a zip-download extraction) and
  a leftover duplicate `wilelik-erp-main/` folder removed.
- Ran a full rebrand pass via Claude Code: deleted `business-app-spec.md`
  and a Wilelik-specific one-off SQL data-fix script; renamed "Wilelik" →
  "TCS" across ~40 files (routes, components, data stores, config,
  exported filenames, localStorage keys, seed emails,
  `supabase/config.toml`'s `project_id`). Left `supabase/migrations/`
  untouched, as intended.
- `CLAUDE.md` rewrite **deferred** — flagged as needing a real pass to
  separate reusable engineering conventions (now captured in
  `DESIGN.md`) from Wilelik-specific product narrative, rather than
  editing it live during the rebrand.
- Repo initialized fresh (no Wilelik git history carried over — this was
  the first commit) and pushed to `github.com/wheezy20/tcs-erp`
  (private).

### Still outstanding as of this entry
- Payroll migration not yet applied locally.
- `CLAUDE.md` rewrite not yet done.
- `supabase/seed.sql` still contains Wilelik's dummy retail data — needs
  replacing before a meaningful local `supabase db reset`.
- `staff.role` check constraint still limited to
  `Attendant`/`Manager`/`Accountant/Auditor` — fine for Phase 1, will
  need extending later.
- Real TCS logo/icon assets not yet available — sidebar/login use a text
  placeholder.
- PAYE band thresholds not yet verified against an official GRA source.
- No separate Supabase project created yet for TCS (still pointing at
  local dev only, per `CONSTRAINTS.md`).

---

## 2026-09-08 — CLAUDE.md rewrite, docs ownership model

- Rewrote `CLAUDE.md` (~300KB → ~180 lines). Kept the still-accurate
  engineering content (repo layout, commands, TanStack Start routing,
  shadcn/ui conventions, SSR error handling, lint/format, the local-dev
  and production-Manager bootstrap scripts). Deleted all Wilelik business
  narrative — the session-by-session build ledger, "Phase 1.5" language,
  building-materials domain rules, `business-app-spec.md` references (that
  file is deleted).
- Backend conventions that used to be inline in CLAUDE.md's "Data layer"
  section are now referenced from `docs/DESIGN.md` instead of duplicated.
- Added a "Project docs — read these first" section to CLAUDE.md pointing
  at all five `docs/` files, and made "keep the docs current" a standing
  instruction: scope/constraint/stack/design decisions get written to the
  relevant doc in the same session, JOURNAL always gets a dated entry, no
  need to be prompted.
- `docs/DESIGN.md`: updated its intro (CLAUDE.md now points here rather
  than being "due a rewrite"); added the accounting naming-discipline
  convention (never shorten "gross profit"/"operating margin" to
  "profit"/"net profit") that was previously only in CLAUDE.md's dropped
  Business Domain Rules section.
- No scope, stack, or constraint change this session — `PLANNING.md`,
  `STACK.md`, `CONSTRAINTS.md` untouched.

### bun-vs-npm resolved
- Confirmed **npm** is the package manager (`frontend/package-lock.json`
  current; `bun.lock` was stale pre-rebrand). Deleted `frontend/bun.lock`
  and `frontend/bunfig.toml`, dropped the `bun.lock` line from
  `frontend/.prettierignore`, and updated `STACK.md` and `CLAUDE.md`
  accordingly.

---

## 2026-09-08 — Payroll: schema review + applied, full UI built

**Migration review (`20260908070000_payroll_schema.sql`).** The draft was
structurally sound but had four deviations from `DESIGN.md` /
`supabase/migrations/` convention, all fixed in-place before applying
(the migration was still unapplied, so editing it was correct):
1. **No `service_role` grants** on any of the 8 tables — added (the exact
   gap `20260803130000` once existed to fix).
2. **Accountant/Auditor got INSERT + UPDATE** on every payroll table (the
   `do $$` loop applied `has_role(['Manager','Accountant/Auditor'])` to
   all of select/insert/update). Restructured to the real three-tier
   shape: select = Manager + Auditor; write = Manager only.
3. **No DELETE policy anywhere** → a mistaken payslip/draft run couldn't
   be removed and there's no update path, dead-ending the "generate →
   oops" loop. Added Manager delete on config tables; `payroll_runs`
   delete is Manager + `status='Draft'`; new `delete_payslip()` RPC
   (Draft-only).
4. **`payroll_runs.created_by` was client-suppliable** (nullable, no
   `default auth.uid()`, no trigger, created by raw insert). Replaced raw
   insert with a `create_payroll_run()` RPC (SECURITY DEFINER,
   Manager-only, forces `created_by = auth.uid()`, friendly
   unique-violation message).
   - Also: `create_payslip()` had no role guard at all and wasn't
     SECURITY DEFINER — added `require_writable_role()` + Manager check +
     a Draft-run check + `security definer set search_path = public`.
   - `create_payslip()`'s `p_allowances` changed from a composite-type
     array to `jsonb` (the `create_invoice()`/`create_sale()` `p_lines`
     convention — composite-array params are a PostgREST footgun).
- `payslips` / `payslip_allowances` / `payroll_runs` are now **select-only
  tables** — all writes go through the SECURITY DEFINER RPCs, same shape
  as `journal_entries`.
- Statutory rates (0.5% / 13% / 5%) and 7 placeholder monthly PAYE bands
  are seeded **in the migration** (`on conflict do nothing`) — entity-wide
  reference data belongs there, not `seed.sql` (the `seed_gap` lesson).
  Both carry a loud "verify against SSNIT/GRA before go-live" comment;
  the Pay Config screen shows the same warning. Demo `allowance_types` +
  `staff_pay_config` + `staff_allowances` for the 4 seeded staff (incl.
  Kojo Boadu set up as an all-exempt National Service case) went into
  `seed.sql`.

**Applied + verified.** Local Supabase stack was still running under the
old `wilelik-erp` project id (never restarted after the rebrand renamed
`project_id`) — stopped those containers (reversible), brought up
`tcs-erp` fresh. `supabase db reset` applied all 44 migrations + seed
clean; `database.types.ts` regenerated; `tsc`, `eslint` (payroll files
clean), `vite build`, and `check-duplicate-function-overloads.sh` all
pass. RPC-level test as the seeded Manager: `create_payroll_run` +
`create_payslip` compute correctly (hand-checked — e.g. Ama Owusu basic
2800 + 400 allowances → gross 3200, SSNIT 14 / Tier 2 140 / PAYE 423.80
→ net 2622.20). RLS negative paths confirmed: Attendant rejected from
`create_payroll_run` and sees 0 rows; Auditor rejected from
`create_payslip` with the read-only message but can still read rates.
Browser smoke test (headless, dev-manager account) drove the whole flow
— create run → generate payslip (standing allowances pre-fill
confirmed) → payslip view (correct real-payslip layout, Print +
Download PDF present) → Pay Config screen — with **zero console errors**.

**Frontend built (all new, follows existing conventions):**
- `data/payroll-store.ts` (one combined `usePayroll()` store, same
  `useSyncExternalStore` + Supabase pattern as `accounts-store.ts`),
  `data/payroll-format.ts` (shared `MONTHS`/`periodLabel`).
- Routes: `payroll.tsx` (tabbed layout + Manager/Auditor guard, mirrors
  `accounting.tsx`), `payroll.index.tsx` (runs list + Create Run),
  `payroll.$runId.tsx` (run detail: payslip list, generate-payslip
  dialog with editable pre-filled allowances / overtime / fines / IOU,
  delete payslip), `payroll.pay-config.tsx` (per-staff pay config + bank
  + exemption flags + standing allowances; allowance-type management),
  `payslips.$payslipId.tsx` (payslip view/print — top-level route, not
  under the payroll layout, so no tab chrome on the print page).
- `components/print/printable-payslip.tsx` + `lib/pdf/payslip-pdf.ts`
  (mirrors `printable-invoice.tsx` / `invoice-pdf.ts`, incl. the embedded
  Inter font for the ₵ sign).
- "Payroll" nav item added to `app-sidebar.tsx`, gated to
  Manager/Auditor like Accounting/Reports.
- **Deliberately deferred** (as instructed): posting a run to the
  Accounting ledger. `// TODO` markers left in `payroll.$runId.tsx` and
  the migration where a `post_payroll_run()` RPC + journal entry
  (salary expense / statutory liabilities / net pay payable) will hook
  in. `status` is currently just a lock against payslip edits.

**Pay-config edit model (v1).** Editing `staff_pay_config`: same
effective date = in-place `UPDATE` (a correction; safe because payslips
snapshot every amount); a later effective date = close the open row +
insert a new one. Good enough to exercise the flow; a dedicated "record
a pay change" flow can replace the heuristic later.

**Side effects worth noting:** wrote `frontend/.env.local` (gitignored)
with the local anon key so the app can reach the stack; ran
`scripts/seed-local-dev-staff.sh` so the three dev logins exist against
the fresh DB; fixed one stray prettier error in `routes/reports.tsx`
that my own 2026-09-08 rebrand sed introduced (shortening "Generated by
Wilelik" → "TCS" let the line collapse). One pre-existing, unrelated
prettier error remains in `components/settings/accent-sync.tsx` — left
alone (not this session's file).

`DESIGN.md` gained six new convention bullets (select-only financial
records + SECURITY DEFINER writes, Draft-only mutation window, jsonb RPC
input, the effective-dated edit model, reference-data-in-migration).
`PLANNING.md` / `STACK.md` / `CONSTRAINTS.md` unchanged — Payroll was
already Phase 1 scope and CONSTRAINTS already carries the
PAYE-not-yet-GRA-verified warning.

### Still outstanding
- `post_payroll_run()` accounting hook (its own follow-up).
- Real GRA PAYE bands + SSNIT split confirmation before any real payroll.
- The old `wilelik-erp` Docker containers are stopped, not removed — a
  `docker rm` once you're sure nothing there is needed.

---

## 2026-09-09 — Split the Accountant/Auditor role in two

`supabase/migrations/20260909090000_split_accountant_auditor_roles.sql`
(new migration, not an edit to `20260803120000` — it's a behavioural
change to the permission model). The old combined `Accountant/Auditor`
role becomes:

- **Accountant** — Manager-equivalent write on Payroll, Accounting and
  Expenses; read-only elsewhere.
- **Auditor** — read-only everywhere the combined role could read.
- **Manager** / **Attendant** — unchanged.

### Mechanism
- `staff.role` CHECK constraint → `('Attendant','Manager','Accountant','Auditor')`;
  any existing `'Accountant/Auditor'` row migrated to `'Accountant'`.
- `can_write()` → excludes both Accountant and Auditor (still "Manager +
  Attendant", the ordinary-table write predicate — unchanged meaning).
- `require_writable_role()` → now rejects **only Auditor**. Accountant
  passes; ordinary RPCs still keep Accountant out via `can_write()`-gated
  RLS on their target tables (documented tradeoff: the error surfaces deep
  inside the function, not as an early friendly message — security holds).
- `require_finance_writer()` — **new**. Manager or Accountant. The 8
  finance RPCs (`create_expense`, `void_expense`, `create_account`,
  `post_journal_entry`, `reverse_journal_entry`, `create_payroll_run`,
  `create_payslip`, `delete_payslip`) each had their
  `require_writable_role() + has_role(['Manager'])` guard swapped for a
  single `require_finance_writer()` call. Function bodies were pulled from
  the live DB with `pg_get_functiondef`, transformed with one perl
  substitution each, and re-emitted verbatim otherwise (build script kept
  in scratch, not committed).
- `handle_new_staff_signup()` accepts the two new role names;
  `supabase/functions/invite-staff/`'s `ALLOWED_ROLES` too.

### Blast radius (RLS) — 27 tables, all previously `Accountant/Auditor`
Every affected policy was a **SELECT** policy (the combined role was
read-only everywhere, so there were no positive write refs to split).

- **Finance-write tables** (15) — writes → `has_role(['Manager','Accountant'])`,
  selects → `+Auditor`:
  `expenses`, `expense_categories`, `expense_category_accounts`;
  `accounts`, `journal_entries`, `journal_lines`,
  `journal_entry_number_counters`;
  `allowance_types`, `staff_pay_config`, `staff_allowances`,
  `statutory_rates`, `paye_bands`, `payroll_runs`, `payslips`,
  `payslip_allowances`. (`payroll_runs_delete` keeps its
  `status = 'Draft'` clause — verified.)
- **Read-only-for-both tables** (12) — select → `+Auditor` only, writes
  untouched (still Manager-only; Banking/Purchasing aren't Accountant's
  modules): `audit_log`; `bank_accounts`, `bank_deposits`,
  `bank_reconciliations`, `bank_statement_lines`; `purchase_orders`,
  `purchase_order_lines`, `purchase_order_receipts`,
  `purchase_order_receipt_lines`, `purchase_order_number_counters`;
  `suppliers`, `supplier_payments`.
- No grant changes — every affected table already grants the relevant
  CRUD to `authenticated`; RLS is the differentiator.

### Frontend
- `data/auth-store.ts`: `StaffRole` gains `"Accountant" | "Auditor"`;
  new `canViewFinancials()` / `canWriteFinancials()` helpers.
- Route view-guards (`accounting`, `payroll`, `payslips`, `banking`,
  `purchasing`, `reports`, dashboard ledger KPI, sidebar nav visibility)
  → `canViewFinancials` (Manager + Accountant + Auditor).
- Write-gates in the finance UIs (`payroll.index` / `.$runId` /
  `.pay-config`, `accounting.index`, `accounting.journal-entries`,
  `expenses.index` "Record expense", `expenses.$expenseId` void) →
  `canWriteFinancials` (Manager + Accountant) — so an Accountant has the
  buttons, not just the DB access.
- POS (`pos.tsx`, sidebar `/pos` redirect): Checkout/Returns blocked for
  **both** Accountant and Auditor (read-only for operational modules);
  Sales history still open. Attendant paths untouched.
- `STAFF_ROLES` dropdown in Settings → 4 entries.
- `scripts/seed-local-dev-staff.sh` now creates **four** dev logins:
  `dev-accountant@tcs.test` + `dev-auditor@tcs.test` replace the single
  combined `dev-auditor`. `seed.sql` seeds Ebenezer Addo as `Accountant`.
  `CLAUDE.md`'s dev-account table updated.

### Verification
- `supabase db reset` clean (all migrations + seed); `gen types` clean;
  `tsc` / `eslint` / `vite build` / `check-duplicate-function-overloads.sh`
  all pass.
- **DB-layer RLS matrix, all 4 roles** (psql + JWT-claims impersonation):
  Accountant — `create_payroll_run` / `create_expense` / `create_account`
  / `post_journal_entry` succeed; direct PATCH on `accounts` /
  `staff_pay_config` / `paye_bands` matches rows; `create_invoice` /
  `adjust_product_stock` / PATCH `products` blocked; `create_bank_account`
  → "Only a Manager can add a bank account". Auditor — every write
  rejected ("Auditor is read-only…" for ordinary, "…limited to Manager
  and Accountant roles" for finance); reads work everywhere the combined
  role could. Attendant — unchanged (finance blocked, `products` PATCH
  still 12 rows). Manager — spot-checked writes succeed. Policy
  expressions inspected directly — all correct.
- **Browser** (headless, warmed dev server): Accountant sees "Create
  run" / "New entry" / "Record expense" and the pages load; Auditor sees
  the same pages (not access-blocked) with **no** write buttons; zero
  console errors. (Earlier headless runs flaked on a cold server —
  transient `branches` 401s that don't reproduce at the DB layer; the
  warmed re-run was clean.)

### Docs
- `DESIGN.md` role-model section rewritten for the 4-role model + the
  three predicates.
- `CONSTRAINTS.md` gains a "Checklist — must be done before real go-live"
  section (first item: verify PAYE bands against GRA) and a "Staff roles"
  section.

### Still outstanding
- `post_payroll_run()` accounting hook (unchanged from 2026-09-08).
- The pre-existing prettier error in `components/settings/accent-sync.tsx`
  is still there (not this session's file).

## 2026-09-09 — Staff Overview: directory + editable profiles

Built the "staff overview" piece outstanding from the original scope — a
directory/profile screen distinct from Payroll's Pay Config.

### What got built
- **`/staff`** (`routes/staff.tsx` layout + `staff.index.tsx`) — every
  staff member with role, position, department, phone and active/invite
  status; search; "show inactive" toggle; three summary cards. Row links
  to the profile. Same Manager/Accountant/Auditor view gate as the other
  back-office sections (`canViewFinancials`); Attendant gets an
  access-denied panel. New sidebar entry ("Staff", `Contact` icon), gated
  the same way.
- **`/staff/$staffId`** (`staff.$staffId.tsx`) — profile with an editable
  Contact & placement form (phone / position / department, Manager-only,
  dirty-tracked) plus read-only Account (sign-in email, role, status →
  link to Settings → Staff) and Pay & bank (bank / account no / basic
  salary → link to Pay Config) panels.
- `staff-store.ts`: `updateStaffProfile(id, {phone,position,department})`.
- `auth-store.ts` / `Staff` type gains `phone` / `position` /
  `department`.

### Schema — `20260909100000_staff_profile_fields.sql`
- `alter table public.staff add column phone / position / department`.
- `alter table public.staff_pay_config drop column position / department`
  — they were added there in the payroll migration (2026-09-08) but are
  org placement, not pay history: the payslip reads them live, never from
  a per-payslip snapshot, so moving the source of truth changes no
  payslip semantics and there was only seed data to migrate.
- **No new RLS or grants.** `staff` already has `staff_select` =
  `is_active_staff()` (every active staff member reads — needed for
  "Recorded by" names everywhere) and `staff_update` =
  `has_role(['Manager'])` (the policy that already gates role/active), plus
  `grant select, update on staff to authenticated`. The new columns ride
  both.

### Design decisions (flagged for review)
- **Columns on `staff`, not a `staff_profiles` side table.** `staff` is
  the identity table; phone/position/department are current-state 1:1
  facts of the same kind as `name`. Effective-dating is for values
  reconstructed as-of a past date — org placement isn't one. A directory
  field is no more sensitive than `staff.name`. New DESIGN.md convention:
  "Staff identity vs pay data".
- **`bank` / `account_no` stay on `staff_pay_config`** (pay data, pinned
  to each payslip by FK, effective-dated edit flow already owns them). The
  profile shows them read-only with a link to Pay Config. A single
  editable copy on `staff` would let the two diverge.
- **`email` is display-only** on the profile — it mirrors
  `auth.users.email`; changing it is a re-invite, not a field edit. No
  separate contact-email added (out of scope; note if ever wanted).
- **Edits are Manager-only, not Manager+Accountant.** Staff records are
  org-admin/HR data; the `20260909090000` split scoped Accountant to
  Payroll / Accounting / Expenses only. Reusing `staff_update` means zero
  RLS surface change. A dedicated HR permission can come later
  (CONSTRAINTS.md: "don't invent a fifth role" for now).

### Verification
- `supabase db reset` clean (incl. the new migration + seed); `gen types`
  clean; `tsc` / `eslint src` (0 errors — 2 pre-existing warnings) /
  `vite build` / `check-duplicate-function-overloads.sh` all pass.
- **DB RLS matrix** (psql + JWT-claims impersonation): `UPDATE
  public.staff SET phone/position/department` → Manager `UPDATE 1`;
  Attendant / Accountant / Auditor all `UPDATE 0`. All 4 roles can
  `SELECT` from `staff`.
- **Browser** (headless): Manager — `/staff` list (8 rows), profile
  opens, Save works (toast + value persists after reload), 0 console
  errors. Auditor & Accountant — list visible, profile read-only (no Save
  button, phone input disabled). Attendant — `/staff` shows the
  access-denied panel. Pay Config page still loads, "Position" column now
  sourced from `staff`, the pay-config dialog no longer has
  position/department fields and links out to the staff profile.

### Still outstanding
- `post_payroll_run()` accounting hook (unchanged from 2026-09-08).
- If a non-login "contact email" is ever wanted, add `staff.contact_email`
  (the current `email` stays the sign-in address).

## 2026-09-09 — Post payroll run to Accounting

Built the deferred "post to Accounting" step for payroll (the `// TODO` in
`payroll.$runId.tsx` and `20260908070000`).

### Schema — `20260909110000_post_payroll_run.sql`
- **4 new chart accounts** (`insert … on conflict (code) do nothing`, the
  in-migration pattern — `seed.sql` never runs on prod):
  `2310 SSNIT Payable`, `2320 Provident Fund (Tier 2) Payable`,
  `2330 PAYE Payable` (Liabilities), `4910 Staff Fines Recovered`
  (Revenue — deliberately its own line, not lumped into `4900 Other
  Income`, so fine recovery is visible on its own).
- **`post_payroll_run(p_run_id)`** — `SECURITY DEFINER`,
  `require_finance_writer()` (Manager + Accountant), Draft runs only.
  Aggregates every payslip in the run into **one** journal entry (like
  `post_day_close_journal_entry` rolls up a day), via
  `_post_journal_entry_rows()` with `source_table='payroll_runs'` /
  `source_id=run_id` (the unique constraint blocks a double-post). Atomic:
  the entry + `status → 'Posted'` + `posted_at` commit together.
  `entry_date` = last calendar day of the run's month.

  | Line | Dr | Cr |
  |---|---|---|
  | 5140 Salaries & Wages Expense | Σ gross | |
  | 2300 Salaries & Wages Payable | | Σ net (accrued, not disbursed) |
  | 2310 SSNIT Payable | | Σ ssnit |
  | 2320 Provident Fund (Tier 2) Payable | | Σ tier2 |
  | 2330 PAYE Payable | | Σ tax |
  | 1350 Advances to Staff | | Σ iou (repayment reduces the asset) |
  | 4910 Staff Fines Recovered | | Σ fines |

  Balanced by construction (credits sum to gross). Zero-aggregate lines
  (3–7) are omitted — a zero `journal_lines` row violates
  `journal_lines_has_amount`. Raises if total net ≤ 0.

### Immutability — already in place, verified not added
`create_payslip()` **already** refuses a non-Draft run (checked against
the live DB — the guard the task suspected was missing is there),
`delete_payslip()` already does, `payroll_runs_delete` RLS already
requires Draft, and `payroll_runs` has no UPDATE grant/policy. So a Posted
run is fully immutable through every path with no new code; the migration
just records that it was checked.

### Frontend
- `payroll-store.ts`: `postPayrollRun(id)` → RPC, then reloads both the
  payroll and journal stores.
- `journal-store.ts`: `reloadJournalEntries()` export; `payroll_runs →
  "Payroll"` source label.
- `payroll.$runId.tsx`: replaced the TODO with a Post-to-Accounting
  section. Draft + all-payslips-present → a **"Post to Accounting"** dialog
  showing the projected entry (debit/credit table), an employer-SSNIT
  caveat, and a warning listing any active staff with no pay config (they
  post excluded, not blocked). Not-yet-complete → a "generate the
  remaining N payslips first" note. Posted → an embedded card with the
  real entry (`JE-…`, date, line table) and an "Open in ledger" link.
  "Complete" = every active staff member **who has a pay config** has a
  payslip.

### Employer SSNIT (13%) gap — flagged in CONSTRAINTS.md, not just a comment
`create_payslip()` computes employee-side only, so this entry omits the
employer's 13% SSNIT contribution: the P&L understates staffing cost and
`2310 SSNIT Payable` is understated. Added to
`docs/CONSTRAINTS.md`'s go-live checklist with the fix (add an
employer-contribution figure to the payslip computation, then extend
`post_payroll_run()`).

### Verification
- `supabase db reset` / `gen types` clean; `tsc` / `eslint src` /
  `vite build` / `check-duplicate-function-overloads.sh` pass.
- **DB end-to-end** (psql, rolled-back txn): 4-payslip run → aggregates
  G 15200 / SSNIT 67.50 / Tier2 675 / PAYE 2128.68 / fines 50 / IOU 100 /
  net 12178.82 → posted `JE-26040001`, 7 lines, **15200 Dr = 15200 Cr**,
  run flipped to Posted. Second `post_payroll_run` rejected ("already
  posted"); `create_payslip` against the posted run rejected ("already
  posted and cannot take new payslips").
- **DB RLS matrix**: Manager posts OK, Accountant posts OK, Auditor
  blocked ("limited to Manager and Accountant roles"), Attendant blocked.
- **Browser** (headless): see below in this session's smoke run —
  Manager posts a run, the embedded entry appears, the generate/delete
  controls disappear, and a re-post attempt is not offered.

### Still outstanding
- Employer SSNIT (above).
- No "unpost"/reverse-from-the-run-page shortcut — a correction goes
  through the normal `reverse_journal_entry()` in Accounting. Fine for now.

## 2026-09-09 — Employer SSNIT contribution (closes the go-live gap)

Closed the employer-SSNIT gap flagged in `docs/CONSTRAINTS.md` the same
day it was opened.

### Schema — `20260909120000_payslip_employer_ssnit.sql`
- `payslips.ssnit_employer numeric(12,2) not null default 0` — a plain
  snapshot column (not a Postgres generated column: it reads
  `statutory_rates`), filled once by `create_payslip()`, never
  recomputed. Same discipline as `ssnit` / `tax` / `tier2`.
- New account **`5145 Employer SSNIT Contribution`** (Expenses / Operating
  Expense) — kept separate from `5140` so total staff cost reads as
  `5140 + 5145` rather than being hidden inside gross pay.
- `create_payslip()` (unchanged signature, plain `create or replace`):
  `v_ssnit_employer := round(basic × ssnit_employer_pct / 100, 2)` gated
  on the **same `pays_ssnit` flag** as the employee side — an exempt
  staff member generates neither side. Stored on the new column; **not**
  added to taxable income or net pay (it never touches the employee).
- `post_payroll_run()`: sums `ssnit_employer`, and when non-zero adds a
  self-balancing pair — `Dr 5145` / `Cr 2310` — on top of the existing
  employee-side `Cr 2310`. Both portions owe to the same payable. New
  balance: `Dr (gross + ssnit_employer) = Cr (net + ssnit_emp + ssnit_er
  + tier2 + paye + iou + fines)`.

Existing payslips keep `ssnit_employer = 0` (snapshot discipline — no
backfill); regenerate a Draft-run payslip to pick up the figure. Posted
runs are immutable and stay as posted.

### Frontend
- `payroll-store.ts`: `Payslip.ssnitEmployer` + `mapPayslip`.
- `payroll.$runId.tsx`: the post-preview dialog now shows `5145` and two
  `2310` lines (employee / employer); the posting note reflects that the
  employer contribution is included.
- **Payslip footnote** (screen + PDF) — my call, flagged in the proposal:
  shown on the payslip itself, in a separated block **below NET PAY**,
  labelled "Employer contributions (paid by <company>, not deducted from
  your pay)", with the SSNIT 13% amount and a "Total cost of employment
  this month" = `gross + ssnit_employer` line. Only rendered when
  `ssnitEmployer > 0`. Never enters the earnings/deductions/net math. The
  payslip is the per-staff-per-month artifact an auditor already reaches
  for; a separate cost report stays an easy follow-up (it can read the
  same snapshot column) but wasn't worth building for one number now.

### Verification
- `supabase db reset` / `gen types` clean; `tsc` / `eslint src` /
  `vite build` / `check-duplicate-function-overloads.sh` pass.
- **DB end-to-end** (rolled-back txn, 4 payslips incl. one `pays_ssnit =
  false`): employer SSNIT per payslip `845 / 546 / 364 / 0` (13% of
  basic, exempt staff = 0); employee SSNIT `32.50 / 21 / 14 / 0`.
  Posted entry has 9 lines including `Dr 5145 1755.00` and `Cr 2310
  1755.00` (employer) alongside `Cr 2310 67.50` (employee). **Balance:
  16955.00 Dr = 16955.00 Cr, diff 0.00** (was 15200 before the employer
  pair). `2310` total credited = `1822.50` across 2 lines; `5145` debited
  = `1755.00`.
- **DB RLS matrix** for the changed RPCs: unchanged — `post_payroll_run`
  / `create_payslip` still Manager+Accountant, Auditor/Attendant blocked.
- **Browser**: see this session's smoke run — Manager posts a run, the
  embedded entry shows the `5145` debit and both `2310` credits, the
  payslip view + PDF footnote renders for non-exempt staff and is absent
  for the exempt one.

### `docs/CONSTRAINTS.md`
Removed the "Employer SSNIT (13%) is not in the books" checklist item.
The SSNIT/Tier-2 item now notes only the *rate* still needs an official
source check — the mechanism is done.

## 2026-09-09 — Employees vs ERP logins + payroll approval workflow

Split "person TCS pays" from "person with an ERP login" and put a
propose → approve workflow in front of the fraud-sensitive payroll edits.
Migration `20260909130000_employees_and_approval_workflow.sql`.

### Schema
- **`employees`** — everyone TCS pays, independent of a login: `name`,
  `phone`, `position`, `department`, `employment_status` (`Pending
  Approval` / `Active` / `Suspended` / `Rejected`), `proposed_by` /
  `created_at` / `reviewed_by` / `reviewed_at` / `rejection_reason`.
  Select-only for `authenticated` (M/Acc/Aud); all writes via RPC.
- **`staff.employee_id`** — optional link (partial-unique). `staff` is now
  an ERP login only; `phone` / `position` / `department` **dropped** from
  it (moved to `employees`).
- **`staff_pay_config` → `employee_pay_config`**, **`staff_allowances` →
  `employee_allowances`**, `payslips.staff_id` → `employee_id`,
  `payslips.staff_pay_config_id` → `employee_pay_config_id`. All FKs now
  point at `employees`. `employee_pay_config` gains `approval_status`
  (default `'Active'` — raw inserts are live; only the propose RPC writes
  `'Pending Approval'`), `proposed_by` / `reviewed_by` / `reviewed_at` /
  `rejection_reason`. Partial unique indexes: `one_active` (`effective_to
  is null and approval_status = 'Active'`) and `one_pending`
  (`approval_status = 'Pending Approval'`).
- **`employee_pay_config` write policies dropped** — was Manager/Accountant
  CRUD, now RPC-only (even a Manager goes through the approval RPCs so the
  trail can't be bypassed). `employee_allowances` keeps plain M/Acc RLS
  (not approval-gated).
- **`audit_log`** — 9 new `action` values; `AFTER` triggers on `employees`
  / `employee_pay_config` write them on the relevant transitions. Actor
  `coalesce(auth.uid(), proposed_by)`, skipped when null (seed/migration).

### RPCs (all `SECURITY DEFINER`)
- `create_payslip()` — `p_staff_id` → `p_employee_id` (drop + recreate);
  adds "employee must be `Active`" and "config `approval_status =
  'Active'`" guards.
- **propose_*** (`require_finance_writer()`, M/Acc): `propose_employee()`
  (optionally bundles an initial pay config + a login link, per Open
  Question 3), `propose_pay_config_change()`.
- **approve_* / reject_*** (Manager only): `approve_employee()`,
  `reject_employee()`, `approve_pay_config()`, `reject_pay_config()`.
- **direct** (M/Acc, no gate): `set_employee_status()` (suspend ⇄
  reactivate), `update_employee_profile()`, `set_pay_config_exemptions()`,
  `withdraw_pay_config_proposal()`.
- Unchanged: `create_payroll_run()`, `delete_payslip()`,
  `post_payroll_run()` (they never referenced pay identity).

### Design decisions (from the confirmed plan)
1. `approval_status` default `'Active'`. 2. **No same-period corrections**
— a proposal's effective date must be a future month with no posted
payslip. 3. `propose_employee` bundles the initial pay config; approved /
rejected together. 4. Exemption flags stay a **direct** edit. 5.
Reactivation is direct, symmetric with suspend. 6. A login with no linked
employee has no phone/position/department — acceptable. 7. The `staff`
directory slims to "Login accounts" rather than being removed.

### Data migration (point 8) — verified by replay
A backfill `do` block (no-op on a fresh local reset; runs for real on a
DB with old-shape rows): for every `staff` row referenced by
`staff_pay_config` ∪ `staff_allowances` ∪ `payslips`, insert a linked
`Active` `employees` row (name/phone/position/department copied), set
`staff.employee_id`, repoint the three tables, then `NOT NULL` + swap FKs
+ drop `staff_id`. **Replay test**: applied the migration against a DB
pre-loaded with a 2-row effective-dated pay-config history for Ebenezer +
a generated payslip → 4 employees created & linked, all history preserved
(`4200 [Jan–May]` + `4600 [Jun→open]`), the payslip repointed with every
figure unchanged (gross 4690 / ssnit 23 / ssnit_er 598 / net 3729.25), no
orphans, `staff.phone/position/department` gone.

### Frontend
- **New `employees-store.ts`** (owns `employees` + `employee_pay_config`
  all-statuses + `employee_allowances` + the 10 RPC wrappers +
  `currentConfigFor` / `pendingConfigFor` / `configHistoryFor` /
  `standingAllowancesFor`).
- `payroll-store.ts` — dropped the pay-config/allowance bits;
  `Payslip.staff*` → `employee*`.
- **New routes** `/employees` (layout + guard), `/employees/` (list +
  `ProposeEmployeeDialog` + Manager `ApprovalsPanel`),
  `/employees/$employeeId` (profile: direct contact edit, current config +
  exemption switches, "Propose salary/bank change" + pending banner with
  withdraw/approve/reject, standing allowances, history table, status
  card).
- `payroll.$runId.tsx` — eligible list now = `Active` employees with an
  `Active` config. `payroll.pay-config.tsx` slimmed to statutory rates +
  allowance types ("Setup" tab). `payslips.$payslipId.tsx` sources
  position/department/bank from the employee.
- `staff.*` slimmed to **Login accounts** (name / role / linked employee /
  status; no phone/position/department). Sidebar: new "Employees" entry,
  "Staff" → "Login Accounts".
- `auth-store.ts` / `staff-store.ts` — `Staff` drops phone/position/
  department, gains `employeeId`; `updateStaffProfile()` removed.

### Verification
- `db reset` (migration + rewritten seed) clean; `gen types` current;
  `tsc` / `eslint src` (0 new errors) / `vite build` /
  `check-duplicate-function-overloads.sh` pass.
- **Backfill replay** — above.
- **DB state-machine matrix** (psql + JWT impersonation): create → pending
  → approve → Active (pending employee/config not payslip-eligible until
  approved); reject cascades to bundled config + unlinks the login;
  propose-change leaves the live config untouched, a mid-proposal payslip
  uses the old figure, approve closes the old row & the next month's
  payslip uses the new one; `one_pending` blocks a second proposal;
  same-period and already-paid-month effective dates rejected; suspend →
  not eligible → reactivate → eligible; exemptions toggle directly;
  no-approved-config → `create_payslip` refused.
- **RLS matrix**: `propose_*` — Attendant/Auditor blocked, Accountant/
  Manager OK; `approve_*` — Accountant/Auditor blocked ("Only a Manager"),
  Manager OK; `set_employee_status` — Attendant/Auditor blocked,
  Accountant OK; Auditor SELECTs `employees` + `employee_pay_config`
  including pending rows; Attendant SELECTs 0.
- **audit_log**: `employee_created` / `pay_config_proposed` attributed to
  the Accountant; `employee_approved` / `pay_config_approved` /
  `employee_suspended` to the Manager.
- **Browser** (headless, all 4 roles, zero console errors): Attendant →
  `/employees` blocked; Accountant proposes an employee (bundled pay),
  Manager sees the Approvals panel and approves, the employee becomes
  payslip-eligible, a payslip is generated; Accountant proposes a raise →
  pending banner, live config unchanged → Manager approves inline →
  history shows both salaries; suspend → the employee drops out of the
  next run's eligible list; Auditor sees the list but has no Propose /
  Suspend / Propose-change controls. DB check after the run confirmed the
  Jan payslip at 2000, the Feb-effective 2500 row current, and the full
  audit trail.

## 2026-09-09 — Approval-UI fix, banks reference list, real brand assets

Walkthrough follow-ups to the employees/approval work.

### 1. Bundled-proposal approval — rendering bug, data model was fine
`propose_employee()` with an initial pay config creates **one** employee
row + **one** `employee_pay_config` row (both `Pending Approval`, one
txn); `approve_employee()` flips both. Diagnosed **Caleb Gaba**
(`dee76086-…`): `employment_status = 'Active'`, exactly one pay config
(`81269c07-…`, basic 10000, Calbank, `Active`), audit trail
`employee_created` + `pay_config_proposed` (accountant, same instant) then
`employee_approved` + `pay_config_approved` (manager, same instant). **No
corruption, no duplicate records** — the data model did the right thing.

The bug was purely `ApprovalsPanel` (`employees.index.tsx`): it rendered
the pending employee and its bundled pending config as two independent
rows with two Approve/Reject pairs, and approving the employee row
cascaded (server-side) so the config row silently vanished.

**Fix** — `splitPendingConfigs()` (now in `employees-store.ts`): a pending
config on a still-`Pending Approval` employee is *bundled* (approved via
the record); one on an `Active` employee is a *standalone* change. The
panel now shows a bundled new hire as **one row** — identity + a pay
preview line — with **one Approve / one Reject** (`approveEmployee` /
`rejectEmployee`); the "Salary / bank changes" section lists standalone
changes only. Same split on the profile page: `PayConfigSection`'s pending
banner (with its own approve/reject) renders only for `emp.status ===
'Active'`; for a pending record the bundled pay shows as a read-only
preview and approval routes through the status card. Summary-card
"Pending approval" count no longer double-counts a bundled pair.

**Defensive server guard** (`20260909140000`): `approve_pay_config()` now
refuses a config whose employee isn't `Active` — "Approve the employee
record instead." The UI no longer offers that path anyway; this closes it
at the RPC.

### 2. Banks reference list (`20260909140000`)
New `banks` table — `name` (unique), `position`, `is_active`. Same
"school-editable list beats hardcoded" pattern as `allowance_types` /
`expense_categories` (the codebase's own precedent, quoted in
docs/DESIGN.md). **Not branch-scoped** — the licensed-bank list is
entity-wide, like the chart of accounts, so it's seeded **in the
migration** (`on conflict (name) do nothing`, ~23 BoG-licensed banks),
not `seed.sql`. RLS: select M/Acc/Aud, write M/Acc, not approval-gated.
`employee_pay_config.bank` stays plain `text` (the bank *name*) — no FK,
no data migration; the reference list only drives the picker.
- `banks-store.ts` + `BankSelect` component (a value not in the active
  list stays selectable, so a legacy free-text config round-trips).
- Bank `<Input>` → `<BankSelect>` in the propose-employee and
  propose-change dialogs; a Banks editor added to the payroll "Setup" tab
  beside Allowance types.

### 3. Brand assets
The user dropped `frontend/public/PNGS/` (logo library) and
`frontend/public/WEB/` (favicon set + manifest) and deleted the old
root-level icons.
- `WEB/*` favicons (`favicon.ico`, `-16/-32`, `apple-touch-icon`,
  `android-chrome-192/512`) → `public/` root. `site.webmanifest` rewritten
  (real name "Treasures Christian School", the five icon sizes,
  `theme_color`/`background_color` `#ffffff`).
- **`favicon-48x48.png` was not provided** — machine-downscaled from
  `android-chrome-192x192.png` (LANCZOS). Referenced from `__root.tsx`
  head + the manifest. Regenerate from a real 48px source if you have one.
- `public/tcs-logomark.png` ← the "logomark – white bg" glyph (deep-teal
  `#005e61` / green `#11b87a` / orange `#f15e00`). The placeholder "TCS"
  text badge in the sidebar and login page is now this image on a white
  chip (legible in light *and* dark themes). `__root.tsx` gains a
  `theme-color` meta + the 48px icon link.
- Logo library moved to `frontend/brand/` (out of the web-served dir);
  `public/PNGS` + `public/WEB` removed; `public/robots.txt` restored (its
  deletion was collateral of the folder swap).
- **Flag**: the artwork's brand palette is deep teal / green / orange, but
  the app's `--primary` is still indigo (`oklch(0.313 0.215 264.1)`) — the
  "Sign in" button, active nav, etc. stay indigo. Re-theming to the brand
  teal wasn't in scope; do it as a separate pass if wanted.
- **Missing / to provide if wanted**: a real 48×48 favicon; a dark-mode
  logomark variant (the "logomark – deap teal bg" light-glyph version is
  in `brand/logomark-light.png` if you want a theme-switched `<img>`
  later); a horizontal wordmark lockup for wide headers (in
  `brand/full-logo-horizontal-*.png`).

### Verification
- `db reset` (migration + seed) clean; `gen types` current; `tsc` /
  `eslint src` (0 new errors) / `vite build` /
  `check-duplicate-function-overloads.sh` pass.
- **DB**: banks table 23 rows; `approve_pay_config` on a bundled
  (Pending-employee) config → rejected with the guard message;
  `approve_employee` still cascades (emp + cfg → Active in one call);
  standalone change on an Active employee still approves; banks RLS —
  Attendant/Auditor insert blocked, Auditor sees all 23, Accountant insert
  OK.
- **Browser** (headless, zero console errors): login + sidebar render
  `/tcs-logomark.png` (old text badge gone); favicon/manifest served
  (200). Accountant proposes a bundled hire — bank field is a dropdown
  populated from the seeded list. Manager's Approvals panel shows it as
  **one** "New employee records" row with the pay preview and exactly
  **one** Approve button, **no** "Salary / bank changes" entry; one click
  → employee Active with the config attached, no pending banner on the
  profile. Setup tab shows the Banks editor with the seeded banks.

## 2026-09-09 — Payroll run review workflow, per-run exclusions, Mobile Money

Group A. One migration, `20260909150000_payroll_review_exclusions_momo.sql`,
plus the frontend to drive it. Nothing else changed shape.

### 1. Run review state machine

`payroll_runs.status` was `Draft → Posted`, any finance writer posting.
Now `Draft → Ready for Review → Posted`:

- `submit_payroll_run_for_review(run_id)` — any finance writer. Draft only.
  Enforces the completeness check (below); raises with the list of who's
  missing. Sets `submitted_by/at`, clears `rejection_reason`.
- `post_payroll_run(run_id)` — **Manager only now** (was
  `require_finance_writer()`). Requires `Ready for Review`. Approval and
  posting are one call — the journal-entry construction is byte-for-byte
  the 20260909120000 version, only the guard + a `reviewed_by/at` stamp
  changed.
- `reject_payroll_run(run_id, reason)` — Manager only, reason required.
  `Ready for Review → Draft`, stamps `rejection_reason` (shown in the
  Draft banner, cleared on the next submit).

New columns on `payroll_runs`: `submitted_by`, `submitted_at`,
`reviewed_by`, `reviewed_at`, `rejection_reason`. New `audit_log` actions
`payroll_run_submitted` / `_approved` / `_rejected`, written by a new
`audit_payroll_run()` AFTER-UPDATE trigger (the table had no audit trigger
before). Self-review is allowed — a Manager can approve a run they
submitted — consistent with the rest of the app; confirmed with the user.

`create_payslip()` / `delete_payslip()` already refuse any non-Draft run,
so `Ready for Review` locks payslip edits with no new code.

"Email payslips" (a Posted-run bulk action) is **deferred to its own
task** — no email provider is wired in this repo (`invite-staff` rides
Supabase Auth's built-in mail) and `employees` has no email column. The
run page shows a disabled "Email payslips" button with a `title`
explaining why.

### 2. "Exclude from this run"

New `payroll_run_exclusions` (`payroll_run_id` `on delete cascade`,
`employee_id` `on delete restrict`, optional `reason`, `excluded_by`,
unique on `(run, employee)`). Select for M/Acc/Aud; RPC-only writes like
`payslips`.

- `exclude_employee_from_run(run, employee, reason?)` / `include_employee_in_run(run, employee)`
  — finance writers, Draft only. Exclude refuses an employee who already
  has a payslip on the run.
- `_payroll_run_unaccounted(run_id)` — the shared "who's missing"
  definition: `Active` employees with a current approved
  `employee_pay_config` that have neither a payslip nor an exclusion on
  the run. `submit_payroll_run_for_review()` calls it; the run page
  computes the same set client-side for the "Ready to submit" gate.
  Employees with no approved config still don't block — non-blocking
  warning, as before.
- Audit: `payroll_run_exclusion_added` / `_removed` via
  `audit_payroll_run_exclusion()` (AFTER INSERT OR DELETE).

Run page: each not-yet-accounted employee gets **Generate payslip** and
**Exclude** (a dialog with an optional reason); an "Excluded this cycle"
section lists them with an **Include** undo (Draft only).

### 3. Mobile Money

`banks` → **`payment_providers`** (table, PK/unique/index/policies all
renamed) + a `kind` column (`'Bank' | 'Mobile Money'`, default `'Bank'`,
so the 23 existing rows are unchanged). Renamed rather than kept as
`banks` because the table is one session old, uncommitted, and would
otherwise be a table called `banks` that also holds MTN. Seeded three
networks — `MTN Mobile Money`, `Telecel Cash` (the post-2023 name for
Vodafone Cash), `AirtelTigo Money`.

`employee_pay_config.payment_method` (`'Bank' | 'Mobile Money'`, default
`'Bank'` — existing rows *are* banks, no data migration). The existing
`bank` / `account_no` columns double as the destination pair: for mobile
money they hold the network name + wallet phone. No `momo_*` columns —
they'd always be half-null and the journal entry never reads either
column. Considered and rejected in favour of the two-column reuse
(documented in DESIGN.md).

`propose_employee()` and `propose_pay_config_change()` gained a trailing
`p_payment_method text default 'Bank'` (drop + recreate per the
overload-check rule; grants re-issued). Same approval gate as a
bank/account change — it's the same columns, same path. The
`pay_config_proposed` / `pay_config_approved` audit payloads carry
`payment_method`; no new action. `create_payslip()` untouched — the
method changes where net pay goes, not how it's computed or posted.

Frontend: `banks-store.ts` → `payment-providers-store.ts`
(`usePaymentProviders`, `activeProviders(list, kind?)`);
`bank-select.tsx` → `payment-fields.tsx` (`PaymentProviderSelect` +
`PaymentDestinationFields`, a method toggle + kind-filtered provider
dropdown + a number field whose label switches). Wired into the
propose-employee and propose-change dialogs, the employee profile
display, the payslip PDF/print ("Bank" vs "Mobile money" line), and the
Setup tab (the "Banks" editor became "Payment providers" with Banks /
Mobile money groups and a kind toggle when adding).

### Verification

- `db reset` + seed clean; `gen types` current; `tsc` / `vite build` /
  `check-duplicate-function-overloads.sh` pass; `eslint src` — only the
  pre-existing `accent-sync.tsx:32` error, no new ones.
- **DB matrix**: submit with no payslips → blocked; submit with an
  unaccounted employee → blocked, name listed; exclude that employee →
  submit succeeds (`Ready for Review`, `submitted_by` set); exclude an
  employee who has a payslip → blocked; `create_payslip` / exclusion RPCs
  on a non-Draft run → blocked; `post_payroll_run` as Accountant →
  blocked ("Only a Manager"); `reject_payroll_run` as Accountant →
  blocked; reject as Manager with reason → `Draft` + `rejection_reason` +
  `reviewed_by`; re-submit → reason cleared; approve+post as Manager →
  `Posted`, journal entry **balanced (16755.00 = 16755.00)**,
  `reviewed_by` set. Audit trail: submitted → rejected(reason) →
  submitted → approved, plus `exclusion_added` / `_removed`.
- **MoMo**: `payment_providers` = 23 Bank + 3 Mobile Money; a MoMo
  `propose_employee` → bundled config `payment_method = 'Mobile Money'`,
  survives `approve_employee` cascade; `propose_pay_config_change` with a
  method carries it onto the pending row; audit payloads carry it.
- **RLS**: `payroll_run_exclusions` select — Auditor sees rows, Attendant
  sees none; `payment_providers` insert — Accountant OK, Auditor blocked
  (RLS), Attendant blocked; Auditor `submit_payroll_run_for_review` →
  blocked (`require_finance_writer`).
- **Browser** (headless, zero console errors): Manager creates a run →
  "Generate or exclude the remaining N" hint, no Submit button; generate
  one payslip + exclude the rest → "Ready to submit for review" +
  "Excluded this cycle"; Submit → "Ready for Review" badge + "Awaiting
  Manager review" panel with **Approve & post** + **Reject**; Reject with
  a reason → Draft + "Returned for revision" banner showing the reason;
  re-submit → Approve & post → "Posted to Accounting" card + a **disabled**
  "Email payslips" button. Setup tab shows "Payment providers" with Banks
  / Mobile money groups and MTN listed. Propose-employee dialog: switching
  the method to Mobile Money relabels to "Network" / "Mobile money
  number" and the provider dropdown offers exactly the 3 networks (24
  banks in Bank mode).

## 2026-09-09 — Group B: position/department lists, uppercase names, approvals redesign, bulk payslips

One migration, `20260909160000_position_department_lists_and_uppercase.sql`,
plus frontend. Five items.

### 1. `positions` / `departments` reference lists

Two more school-editable lists, identical shape and RLS to
`payment_providers` (`name` unique / `position` / `is_active`; select
M/Acc/Aud, write M/Acc; not approval-gated; entity-wide, so seeded in the
migration). They drive the Position and Department dropdowns on the
employee flow, replacing free-text inputs. `employees.position` /
`.department` stay plain `text` — no FK; a stored value not in the active
list still round-trips, flagged "(not in list)". Seeded a starter set
(16 positions, 10 departments) covering the demo employees' values plus a
sensible Ghanaian-school baseline. New generic `RefListSelect` component;
new `org-lists-store.ts` (a `makeRefListStore(table)` factory → `usePositions`
/ `useDepartments` + create/update/delete). Editors added to Payroll →
Setup as a generic `RefListSection` (beside Allowance types / Payment
providers).

### 2. Uppercase normalization (server-side)

`employees.name` / `.position` / `.department` → `upper(nullif(trim(x), ''))`
via a `BEFORE INSERT OR UPDATE` trigger (`uppercase_employee_fields()`),
so every write path stores them the same and case can't diverge.
`positions` / `departments` get the same trigger
(`uppercase_ref_list_name()`) and are seeded uppercase, so a stored
`employees.department` always resolves to a list entry. Email and phone
left exactly as entered. Existing rows normalized by a one-time `update`
in the migration (no-op on a fresh local reset — seed.sql runs after and
the trigger catches those).

### 3. Rejection reason UI

`reject_employee` / `reject_pay_config` already took `p_reason text`
(nullable — `nullif(trim(p_reason), '')`). The buttons were calling
`window.prompt("Reason for rejection?")`. Replaced every one with a
proper `RejectButton` component: a dialog with a `<Textarea>` (reason
optional, matching the RPC), used in the redesigned approvals panel and
on the employee profile page (status card + pending pay-change section).
No RPC change.

### 4. Approvals panel redesigned for scale

Was: full cards stacked inline for every pending item, in two sections.
Now: one compact table — Name · Change (badge) · Proposed by · Submitted
· Review — with a click-to-expand row per item. Expanding shows the
detail grid (identity + bundled pay for a new hire; salary / method /
provider / number / effective date for a pay change), an **Approve**
button, the `RejectButton` dialog, and an "Open record" link. Bundled
new-hire proposals stay one row / one Approve (via the existing
`splitPendingConfigs`). Rows sorted newest first.

### 5. Bulk-select + generate payslips

The run page's "Not yet on this run" list gains a checkbox per employee +
a select-all, and a **Generate N payslips** button that generates for
every selected employee at once — each at its standing config with the
employee's standing allowances and zero overtime / fines / IOU. The
per-employee dialog is still there as **Adjust** for month-specific
figures; **Exclude** unchanged. New `createPayslipsBulk(inputs[])` in
payroll-store loops `create_payslip` (continuing past a failure, tallying
ok/failed) and reloads once.

### Verification

- `db reset` + seed clean; `gen types` current; `tsc` / `vite build` /
  `check-duplicate-function-overloads.sh` pass; `eslint src` — only the
  pre-existing `accent-sync.tsx:32` error.
- **DB**: reference-list uppercase trigger ("night matron" → "NIGHT
  MATRON"); `propose_employee` / `update_employee_profile` uppercase
  name+position+department, leave phone ("MixedCase Phone Stays" kept);
  bundled config's `payment_method` carried, `bank` not uppercased; RLS on
  `positions`/`departments` — Accountant insert OK, Auditor insert blocked
  but sees all rows, Attendant sees none; `reject_employee` /
  `reject_pay_config` / `reject_payroll_run` all take `p_reason text`, a
  real reject stores the reason.
- **Browser** (headless, zero console errors): Setup tab shows Positions /
  Departments editors, adding "relief teacher" stores "RELIEF TEACHER";
  propose-employee dialog Position/Department are dropdowns (18 options,
  all uppercase, HEAD TEACHER present); proposed "kwesi arthur" lands as
  "KWESI ARTHUR" in the list with position "CLASS TEACHER"; approvals
  panel is a compact table (Review cells per row), expanding a row shows
  Approve + Open record, Reject opens a dialog with a textarea (not
  window.prompt); on a run, "Not yet on this run" has 5 checkboxes
  (select-all + 4), per-row Adjust/Exclude retained, select-all →
  "Generate 4 payslips" → 4 payslip rows created, section gone,
  "Ready to submit for review" shown.

## 2026-09-09 — Cloudflare Workers deploy target; production seed split

Moved the frontend's deploy target from Vercel (inherited from Wilelik) to
**Cloudflare Workers**, TanStack Start's current supported path.

### Vite / Worker config

- `frontend/vite.config.ts`: added `@cloudflare/vite-plugin`
  (`cloudflare({ viteEnvironment: { name: "ssr" } })`, injected via the
  Lovable wrapper's `plugins` option) and set `nitro: false` — the CF
  plugin builds TanStack Start's `ssr` Vite environment into a Worker, and
  Nitro would produce a competing server build. `tanstackStart.server.entry`
  stays `"server"` (`src/server.ts`, already a Workers-shaped
  `export default { fetch(request, env, ctx) }`).
- `frontend/wrangler.jsonc` (new): `name: "tcs-erp"`,
  `compatibility_date: "2026-09-01"`, `compatibility_flags: ["nodejs_compat"]`
  (supabase-js / jspdf / xlsx / SSR entry pull in Node built-ins),
  `main: "src/server.ts"`, `assets.directory: "dist/client"`,
  `observability.enabled: true`.
- `npm i -D @cloudflare/vite-plugin@^1.54.6 wrangler@^4.130.0`; removed the
  `nitro` devDependency. **wrangler 4 requires Node ≥ 22** — the build
  (`vite build`) still runs on Node 20, but `wrangler` (dev/deploy/dry-run)
  needs 22, so CI must use Node 22.
- Deleted `frontend/vercel.json`.

Build output: `vite build` → `dist/client/` (static assets) +
`dist/server/` (`index.js` Worker bundle + a generated `wrangler.json`
with resolved paths). `wrangler deploy` from `frontend/` auto-detects that
output — no `-c` flag needed.

### Seed split

- `supabase/seed.sql` — unchanged, still the full local-dev seed.
- `supabase/seed.production.sql` (new) — idempotent, run **once by hand**
  against a hosted DB after `supabase db push`
  (`psql "$PROD_DB_URL" -f supabase/seed.production.sql`). Contains only
  the branch-scoped reference rows the migrations can't seed on a fresh
  project: the `branches` row ("Treasures Christian School"), then
  `expense_categories` (9), `expense_category_accounts` (9), and
  `allowance_types` (4 starter types). **Zero** demo people, logins,
  employees, pay configs, payslips, payroll runs, products, customers,
  invoices, sales, expenses, suppliers, bank accounts.
- Everything the request listed as "reference data" that is *entity-wide*
  — chart of accounts, `statutory_rates`, `paye_bands`,
  `payment_providers`, `positions`, `departments` — is **already seeded by
  its own migration** (`on conflict do nothing`) and lands on any
  `supabase db push`. `seed.production.sql` deliberately does not duplicate
  it (that would be two sources of truth and drift). The one wrinkle:
  `20260819090000` seeds `expense_categories` / `_accounts` only *if a
  branch already exists* when it runs — which it doesn't on a brand-new
  project — so `seed.production.sql` re-does those for the branch it
  creates.
- **Which file runs when**: `config.toml` `[db.seed] sql_paths =
  ["./seed.sql"]` controls `supabase db reset` (local) *only*. Nothing
  seeds automatically on `db push`. `seed.production.sql` is never in
  `sql_paths` — it is a manual deploy step. Added a comment block in
  `config.toml` saying so.

### Build-time env vars

Documented in CONSTRAINTS.md + DESIGN.md: `VITE_SUPABASE_URL` /
`VITE_SUPABASE_ANON_KEY` are inlined by Vite at **build** time (the Lovable
wrapper's `envDefine` runs `loadEnv` and rewrites `import.meta.env.VITE_*`
to string literals). They must exist as env vars in the Cloudflare
**build** step; a Worker runtime secret set afterward is invisible to the
client bundle. The code reads `VITE_SUPABASE_ANON_KEY` (not
`VITE_SUPABASE_KEY` — the root `.env` currently has the wrong name). Anon
key is a public credential; never inline `service_role`.

### Verification

- `npm run build` (Node 20) → exit 0; `dist/client/` + `dist/server/`
  (`index.js` + `wrangler.json`) produced.
- `wrangler deploy --dry-run` in a `node:22` container (no CF credentials)
  → exit 0, 225 modules bundled, 175 assets read from `dist/client`,
  "No bindings found", "--dry-run: exiting now." Also passes without `-c`.
- `npm run dev` → CF plugin active ("The Cloudflare Vite plugin detected
  this dev session…"), SSR through workerd, `/` and `/login` render 200
  with the right `<title>`, no errors.
- `tsc` / dup-overload-check pass; `eslint src` only the pre-existing
  `accent-sync.tsx:32` error.
- `seed.production.sql` replayed against a fresh migrations-only DB (temp
  `sql_paths` swap + `db reset`): 1 branch, 47 accounts, 9
  expense_categories, 9 expense_category_accounts (correct GL mappings), 4
  allowance_types, 26 payment_providers, 16 positions, 10 departments, 1
  statutory_rates row, 7 paye_bands — and **0** staff / employees /
  payslips / products / auth.users. `config.toml` + local DB restored
  afterward.

## 2026-09-09 — bootstrap script: invite redirect_to

`scripts/bootstrap-production-manager.sh` was hitting `/auth/v1/invite`
with no `redirect_to`, so the first Manager's invite link landed on the
project's `site_url` root instead of `/accept-invite` (the
`invite-staff` Edge Function was already fixed for this — it forwards
`window.location.origin + "/accept-invite"` from the browser). The script
now requires an `APP_URL` env var, validates it's absolute http(s),
strips a trailing slash, and appends `?redirect_to=<jq @uri-encoded
$APP_URL/accept-invite>` to the invite call. Same allow-list caveat as the
Edge Function: GoTrue only honors a `redirect_to` on the project's
`site_url` / `additional_redirect_urls` list. CLAUDE.md's bootstrap
command updated with the new var.

## 2026-09-16 — Nav glitch fix, Accounting tab-wrap fix, brand teal re-theme

Three small polish items, investigated + fixed.

### Rare "previous page stays on screen" glitch on navigation

Reviewed every route-level component in the reported path (`payroll.tsx`,
`payroll.pay-config.tsx`, `accounting.tsx`) plus `AppShell` / `AuthGate` /
`router.tsx` for a missing `key` or leaked local state — found none; all
are pure functions of `pathname`/store data, no `useState` that could
survive a navigation. Reproduced the actual glitch with a scripted
headless run (20+ rapid Payroll↔Accounting navigations): one run threw
`SyntaxError: ... does not provide an export named 'useSelector'` from a
`.vite/deps` chunk, at the exact moment the dev server's log showed
`[optimizer] bundling dependencies...` — i.e. **Vite's dev-only dependency
pre-bundler re-optimizing mid-navigation**. It only discovers a route's
transitive dependencies the first time that route is visited in a
session; visiting a rarely-opened page (Payroll → Setup, which pulls in
stores no other page touches) can trigger a fresh re-bundle whose
in-flight module-graph swap leaves the client and server briefly
disagreeing about a chunk's exports — the navigation gets stuck showing
the old page until a hard reload re-fetches the now-consistent bundle
(exactly the reported symptom). Not present in the production Cloudflare
Worker build, which has no runtime dependency discovery at all.

Fix: `vite.config.ts` now sets `optimizeDeps.entries: ["src/routes/**/*.tsx",
"src/routes/**/*.ts"]`, so Vite crawls every route's full import graph at
dev-server start instead of discovering it piecemeal as pages get
visited. Verified: cleared `.vite` cache, cold-started, and the first-ever
visit to Setup then Accounting in a fresh session rendered correctly with
zero console errors (previously the failure mode was specifically a
first-visit-to-an-unvisited-route event). See CLAUDE.md's operational
specifics list.

### Accounting tab bar wrapping at ~1200px

`accounting.tsx`'s 7 tabs lived in `PageHeader`'s `actions` slot
(`flex flex-wrap`), competing with the title for width — at ~1200px it
lost, wrapping "Cash Flow" onto its own line inside the rounded pill.
Moved the tab bar out of `actions` into its own full-width row below the
header, `overflow-x-auto` + `flex-nowrap` + `shrink-0 whitespace-nowrap`
tabs: it either fits on one line or scrolls horizontally, never wraps.
Verified at 1200px viewport — all 7 tabs render on one row (Playwright
`boundingBox()` check: "Chart of Accounts" and "Cash Flow" at the same
y-coordinate) with a screenshot confirming no visual break.

### Re-themed `--primary` to the brand teal

Sampled actual pixel colors out of `frontend/brand/*.png` (Python/Pillow)
rather than reusing memory of the palette — confirmed: deep teal
`#005e61`, green `#11b87a`, orange `#f15e00`, gold-amber `#edbb0f`. Teal
is the wordmark/text color in the horizontal logo and the obvious
`--primary` — white-on-teal contrast is 7.6:1 (clears AAA). The gold-amber
`#edbb0f` the user flagged turns out to already closely match the
existing `--warning` token (`oklch(0.78 0.15 78)` vs. teal-gold's own
`oklch(0.814 0.164 88.9)`), so no separate change was needed there.

Two places actually needed changing, not one — `styles.css`'s `--primary`
is only the pre-hydration CSS fallback; `AccentSync` always overwrites it
at runtime from `settings-store.ts`'s `DEFAULT_ACCENT` (a
`localStorage`-backed, school-editable "accent colour" in Settings →
Appearance), which is what a real browser actually shows. Changed both,
to the same `oklch(0.438 0.074 198.6)` / `#005e61`, so there's no
flash-of-indigo before hydration and "Reset" in Settings restores the
real brand color. `--accent`/`--ring`/`--chart-1`/`--sidebar-primary`/
`--sidebar-accent`/the Liquid Glass tint all already derive from
`--primary` via `var()`/`color-mix()`, so the whole app re-themed from
these two edits with no other file touched.

Verified: computed `getComputedStyle(document.documentElement)
.getPropertyValue("--primary")` = `#005e61` in both light and dark mode;
screenshots confirm the sidebar active state, primary buttons, badges,
and the dashboard revenue chart line all render teal, consistently across
both themes.

### Verification (all three)

`tsc --noEmit` — clean except one **pre-existing, unrelated** error in
`__root.tsx`'s `ErrorComponent` typing (confirmed present on `HEAD` before
any of today's changes via `git stash`; not touched, out of scope).
`eslint src` — only the pre-existing `accent-sync.tsx:32` prettier error
and the usual `react-refresh` warnings. `vite build` — exit 0, unaffected
by `optimizeDeps` (a dev-only Vite option). No schema changes, so no
`db reset` / `gen types` / dup-overload check needed this round.

### Docs

`docs/DESIGN.md`'s Branding section updated: re-theme done, plus a new
"Two places define `--primary`" note explaining the `AccentSync` /
`DEFAULT_ACCENT` runtime-override relationship (a real gotcha — editing
only `styles.css` would have shipped no visible change at all).
`docs/CONSTRAINTS.md`'s go-live checklist: re-theme checked off; the
48×48 favicon and dark-mode logomark variant split into their own still-
open item. `CLAUDE.md`: brand-assets bullet updated, new operational-
specifics bullet for `optimizeDeps.entries`.

## 2026-09-18 — Amend a pending pay config before approving

A pending pay-config proposal (standalone salary/bank change, or the
bundled initial pay config on a new-hire proposal) could previously only
be Approved-as-submitted or Rejected — a mistyped account number meant a
full reject/resubmit cycle, even though Contact & Placement fields on the
same employee record are already directly editable with no approval gate
at all. Requested with an explicit ask to see the RPC-shape plan before
any code was written, since the audit-trail implication (not silently
crediting the Accountant's proposal with a number the Manager actually
changed) was the part that mattered most.

### The RPC shape

Went with the "extend the existing RPCs" option over a separate
`amend_and_approve_pay_config()`, per the plan presented and confirmed:
`approve_pay_config(p_config_id uuid, p_basic_salary numeric default
null, p_payment_method text default null, p_bank text default null,
p_account_no text default null)` and `approve_employee(p_employee_id
uuid, ...)` with the same four trailing params — `null` means "leave as
proposed." Both needed `drop function` + `create` (not `create or
replace`) for the new argument lists, per the repo's function-overload
convention (`scripts/check-duplicate-function-overloads.sh`).

The override is applied inside the *same* `update` that flips
`approval_status` to `'Active'`, in both functions — this is what makes
the audit diff free: `audit_employee_pay_config()`'s `OLD` row is always
exactly the Accountant's (or bundled-proposal's) original insert, and
`NEW` is whatever the Manager actually approved, so a plain `OLD` vs `NEW`
comparison on the four amendable columns is the whole detection
mechanism — no new column, no snapshot table.

### The new audit action

`audit_employee_pay_config()` now branches on a
`(old.basic_salary, old.payment_method, old.bank, old.account_no) is
distinct from (new.*)` check, but only on a Pending→Active transition. A
real difference emits `pay_config_amended_and_approved` (added to
`audit_log_action_check`) with `before` built from `old.*` — the original
proposed values, not just `{approval_status: 'Pending Approval'}` the way
`pay_config_approved` records it — so the diff is self-contained in one
audit row and doesn't depend on cross-referencing the earlier
`pay_config_proposed` row. No difference still produces exactly
`pay_config_approved`, byte-for-byte what it always emitted — verified by
running both paths locally and diffing the resulting `audit_log` rows
(see Verification). Reject is untouched; effective_from and the exemption
flags are out of scope (exemptions are already direct-edit with no gate,
and effective_from carries its own posted-payslip re-validation that
would meaningfully complicate a same-statement amendment).

### Frontend

A shared `AdjustPayFields` component
(`components/employees/payment-fields.tsx`, built on the existing
`PaymentDestinationFields`) went into all three Approve surfaces: the
standalone pending-config panel and the bundled-hire "Approve record"
button on the employee profile page (`employees.$employeeId.tsx`), and
both the new-employee and standalone-change rows of the list page's
Approvals panel (`employees.index.tsx`, `NewEmployeeDetail` /
`ConfigChangeDetail`). Each gets an "Adjust before approving" toggle,
closed by default (plain approve, unchanged). Opening it always submits
all four fields together, even ones left exactly as proposed — the
trigger's own diff decides whether anything counts as an amendment, so
the frontend never has to track per-field "touched" state or worry about
sending a partial override. `employees-store.ts`'s `approvePayConfig()` /
`approveEmployee()` both gained an optional `override` argument threaded
straight to the RPC's four new params.

### Verification

Local `supabase db reset` applied
`20260918100000_pay_config_amend_on_approve.sql` clean;
`check-duplicate-function-overloads.sh` reported no duplicates;
`database.types.ts` regenerated (diff limited to the two RPCs' `Args`
gaining the four optional params, as expected). `tsc --noEmit` clean
except the same pre-existing, unrelated `__root.tsx` error. Three
Playwright runs against the local stack (Accountant proposes, Manager
approves in a separate browser context so the two roles don't share a
session):

1. Standalone change, adjusted: proposed 3,500 → Manager adjusted to
   3,750 → `audit_log` shows `pay_config_amended_and_approved`,
   `before.basic_salary: 3500`, `after.basic_salary: 3750`.
2. Standalone change, plain approve (no adjustment opened): proposed
   2,900 → approved as-is → `audit_log` shows the unchanged
   `pay_config_approved` shape, confirming the no-amendment path is
   byte-for-byte what it was before this change.
3. Bundled new-hire: proposed with an initial 1,500 basic salary →
   Manager opened "Adjust before approving" on the bundled pay in the
   Approvals panel and changed it to 1,800 → `audit_log` shows
   `pay_config_amended_and_approved` with the same before/after shape,
   and the employee record itself flipped to `Active` in the same action.

Zero console/page errors across all three runs. No new `tsc`/`eslint`
issues introduced.

## 2026-09-18 — `eslint .` taking 25+ minutes

Reported: a full-repo `eslint .` run had to be killed after 25+ minutes,
while `eslint` scoped to individual changed files finished in seconds.
Suspected `database.types.ts` or `routeTree.gen.ts` (large generated
files) — `database.types.ts` was already in `eslint.config.js`'s
`ignores`, but `routeTree.gen.ts` (`src/routeTree.gen.ts`, generated by
the router plugin — see `CLAUDE.md`'s routing section) genuinely wasn't,
so that was a real gap worth closing regardless.

It wasn't the actual cause, though. `DEBUG=eslint:* npx eslint .` showed
the run stuck deep inside `eslint:code-path` analysis (the control-flow
graph `eslint-plugin-react-hooks` builds for its rules) against
`frontend/.vercel/output/functions/__server.func/_libs/*.mjs` — a stale,
gitignored build-cache directory left over from before this project's
deploy target moved to Cloudflare Workers (`docs/STACK.md`). 217 giant
single-line bundled vendor chunks (react-hook-form, floating-ui,
radix-ui, ~205K lines total) is exactly the kind of input that makes
code-path analysis pathological. ESLint's flat-config default file
matching includes `.mjs`, and nothing in `ignores` excluded `.vercel/`,
so it got linted every time.

Fixed by adding `.vercel`, `.wrangler`, `.tanstack` (other local
build/dev-state dirs, none of them source), and `src/routeTree.gen.ts`
to `eslint.config.js`'s `ignores`. Verified: full `eslint .` now
completes in ~20–40s, reporting only the same pre-existing baseline
issues (`accent-sync.tsx:32`'s prettier error, dated to the initial
commit, plus the usual `react-refresh/only-export-components` warnings)
— nothing new.

## 2026-09-18 — Audit history view on the employee profile page

There was no in-app way to see `audit_log` entries — checking them meant
querying the database directly. Added a "History" section to
`employees.$employeeId.tsx` showing an employee's full audit trail:
profile status changes plus every pay-config event (proposed / approved /
amended-and-approved / rejected / exemptions changed), newest first, with
a readable before/after summary instead of raw JSON.

### RLS — confirmed, not assumed

Per the request's explicit instruction to confirm rather than assume:
`audit_log_select` on `public.audit_log` is
`using (has_role(array['Manager','Accountant','Auditor']))` (rewritten by
`20260909090000_split_accountant_auditor_roles.sql`; unchanged since).
No insert/update/delete policy exists for any role — trigger-written-only
holds. `grant select` targets only `authenticated`; `anon` and
`service_role` get nothing on this table (a deliberate exception to the
usual "service_role gets full CRUD" convention). `employees` and
`employee_pay_config` carry the identical predicate, so in practice an
Attendant never reaches this page's data at all — verified directly by
requesting the same query as `dev-attendant@tcs.test`'s own session token
against the local PostgREST endpoint: HTTP 200, `[]`, no error, RLS
silently filtering everything rather than an explicit denial.

### The join

A pay-config audit row's `entity_id` is the *config row's* id, not the
employee's, so a full history needs `entity_table = 'employees' and
entity_id = <employee id>` OR `entity_table = 'employee_pay_config' and
entity_id in (<every config row id for this employee, any
approval_status>)`. Did the join client-side rather than adding an RPC:
`employees-store.ts`'s `configs` array already holds every
`employee_pay_config` row regardless of approval_status, so the page
already has the full id list without an extra query — it's passed to a
new `frontend/src/data/audit-history.ts` module, which builds a
PostgREST compound `.or()` filter
(`and(entity_table.eq.employees,entity_id.eq.…),and(entity_table.eq.employee_pay_config,entity_id.in.(…))`)
and queries `audit_log` directly. No RPC needed — `audit_log`'s own RLS
select policy is the entire access boundary, same as a plain `.from()`
read anywhere else in this codebase.

Fetching is a small `useState`/`useEffect` hook
(`useEmployeeAuditHistory`), not `@tanstack/react-query` — confirmed via
a codebase search that `useQuery` isn't used anywhere despite
`QueryClientProvider` being wired up at the root, and every existing
detail route derives its data from an eagerly-loaded global store rather
than an on-demand query. Introducing react-query as a second data-fetch
convention for one feature wasn't this task's call to make, so the
hook matches the plainer style the store files themselves already use
internally, scoped to just this one page rather than a new global store
(audit history is inherently per-employee and not needed anywhere else).

### Readable summaries, not raw JSON

`summarizeAuditEntry()` in `audit-history.ts` switches on `action` and
diffs only the fields relevant to that action, emitting nothing for a
field that didn't change (so an unamended `pay_config_approved` doesn't
print five redundant "X: same → same" lines, and a `pay_config_proposed`
with no bank/account yet doesn't print "Bank/network: null"). Currency
values reuse the existing `currency()` formatter from `data/dashboard.ts`
for the exact `GH₵4,000 → GH₵5,000` shape the request asked for.

### Verification

No browser pass this round — the dev machine's swap was fully exhausted
(other, unrelated desktop processes) partway through, and a prior
Playwright run had already been OOM-killed once; launching another
Chromium instance risked collateral damage to whatever else was running,
so this was verified a different way instead. Replicated the exact
PostgREST query `audit-history.ts` issues via `curl` against the local
REST endpoint, authenticated as real `dev-manager@tcs.test` /
`dev-accountant@tcs.test` / `dev-attendant@tcs.test` sessions (password
grant against local GoTrue, not a service-role bypass):

- Standalone amended config (`e0000000-…-001`): returned exactly the
  `pay_config_amended_and_approved` + `pay_config_proposed` rows from the
  earlier amend-before-approve testing, in the right order.
- Bundled new-hire (`AMENDMENT TEST HIRE`): returned all four events
  (`pay_config_proposed`, `employee_created`, `pay_config_amended_and_approved`,
  `employee_approved`) correctly joined across both `entity_table` values.
- An employee with zero pay-config rows ever: the `.or()` filter's
  single-clause form (no pay-config `and(...)` group) still returns `200
  []` rather than erroring — confirms the empty-`configIds` code path.
- `dev-attendant@tcs.test`'s own token against the same query: `200 []`
  — RLS denial confirmed, not assumed.

Hand-traced `summarizeAuditEntry()` against all six real rows above
(covering `employee_created`, `employee_approved`,
`pay_config_proposed`, `pay_config_amended_and_approved`) — every line
matched the intended human-readable shape with no null/undefined leaking
through. `tsc --noEmit` clean except the same pre-existing, unrelated
`__root.tsx` error. `eslint` (both scoped and full-repo, now ~20–40s per
the fix above) clean except the same pre-existing baseline issues.
`vite build` exit 0.

## 2026-09-18 — Receipts bucket made private; pending-employee list-view fix

Two findings from a walkthrough.

### Receipts publicly readable via unsigned URL

The `receipts` storage bucket has been `public = true` since it was
created (`20260802100000_expenses_schema.sql`), from before this app had
any auth/RLS at all. `20260803120000_auth_roles_schema.sql` tightened
storage *writes* to `authenticated` only but explicitly left `public`
alone — a real gap, not a deliberate tradeoff, since a `public = true`
Supabase Storage bucket serves downloads through an endpoint that
bypasses `storage.objects` RLS entirely. Every receipt has been readable
by anyone with the object path (a guessable `<uuid>.<ext>`, no session
required) since the day this table shipped.

Presented a plan before touching anything, since it affects every
existing receipt reference in the frontend: checked and confirmed there
is exactly one such place — `expenses-store.ts`'s `receiptUrl()` — with
`record-expense-dialog.tsx`, `expenses.index.tsx`, and
`expenses.$expenseId.tsx` all just consuming the already-resolved
`Expense.receiptUrl: string | null`, never touching Storage directly.

**Fix, confirmed before building:** private bucket + role-scoped RLS,
not an edge function. `20260918110000_receipts_bucket_private.sql` flips
`storage.buckets.public` to `false` for `receipts` and replaces the one
blanket `receipts_staff_access` (`for all to authenticated`) policy with
four command-scoped ones mirroring `expenses_select` /
`expenses_insert` / `expenses_update` / `expenses_delete` exactly (same
`has_role()` predicate, same role sets) — a receipt is exactly as
sensitive as the expense row it belongs to:
- `receipts_select`: `Manager`, `Accountant`, `Auditor`
- `receipts_insert` / `receipts_update` / `receipts_delete`: `Manager`,
  `Accountant`

No edge function: Supabase's `createSignedUrl(s)` is itself gated by the
`storage.objects` SELECT RLS policy at generation time, using the
caller's own session — the frontend's already-authenticated client can
call it directly and only ever receives a signed URL for a receipt it's
actually RLS-permitted to read, so there's no "trusting the client" gap
to close with a server component. This codebase's one existing edge
function (`invite-staff`) exists specifically because that operation
needs the `service_role` key; signing a URL for an object the caller
already has read access to does not, so adding one here would've been
inconsistent with how this repo already draws that line.

`expenses-store.ts`: `receiptUrl()` → `signReceiptUrls()`, one batched
`createSignedUrls(paths, 3600)` call per `loadExpenses()` (not one
request per row) instead of `getPublicUrl()`. Expiry: 1 hour, confirmed
with Eyram — regenerated fresh on every list/detail load, so a normal
viewing session never sees a stale URL; a leaked one (browser history, a
screenshare) goes stale same-day. `Expense.receiptUrl`'s shape is
unchanged (`string | null`), so the three consuming files needed zero
changes.

Verified end-to-end against the local stack via direct Storage REST
calls (not the JS SDK, to rule out any client-side masking of a real
gap) with real `dev-manager@tcs.test` / `dev-auditor@tcs.test` /
`dev-attendant@tcs.test` sessions (password grant, not a service-role
bypass): uploaded a real object as Manager; the old unsigned
`/object/public/receipts/...` path now returns 400 (no longer resolves
— confirms the bucket is actually private, not just RLS-narrowed);
`/object/sign/...` succeeds for Manager and Auditor and returns a token
whose signed URL serves the real file content; the same call for
Attendant is denied (`AccessDenied`); Attendant's own upload attempt is
denied with an explicit RLS-violation message. `check-duplicate-function-
overloads.sh` clean (no function signatures touched). `database.types.ts`
unaffected (storage schema isn't part of what it generates from).
Nothing to flag in `docs/CONSTRAINTS.md` — fully resolved, no open
decision left pending.

### Pending employee shows "Basic salary: Not set" / "Paid to: —" in the list view

Display bug only — the detail page (`employees.$employeeId.tsx`) already
read the bundled pay config correctly. Root cause:
`employees.index.tsx`'s list-view row only called `currentConfigFor()`,
which requires `approval_status = 'Active'` — a brand-new employee's
bundled pay is still `Pending Approval` until the *employee record*
itself is approved (`approve_employee()` cascades both in one step), so
it never matched and silently fell through to "Not set"/"—".

Fixed by falling back to `pendingConfigFor()` only when there's no
*active* config at all — an Active employee with a separate outstanding
salary/bank change still shows their current, approved figures here (not
the unapproved proposal), unchanged from before. When the fallback
applies, the cell renders in italic with a small "(pending)" suffix so
it doesn't read as if the figure were already approved. Verified via a
data-level trace (not a browser pass — the dev machine's swap was fully
exhausted mid-session from unrelated processes, and a prior Playwright
run had already been OOM-killed once, so a second Chromium launch was
skipped to avoid risking collateral damage to whatever else was running):
proposed a fresh `Pending Approval` employee with a bundled ₵2,750 config
via the real `propose_employee()` RPC, confirmed the row's exact shape in
the database, and hand-traced `currentConfigFor`/`pendingConfigFor`
against it — `activeCfg` correctly `undefined` (status is `Pending
Approval`, not `Active`), `pendingCfg` correctly picks up the ₵2,750/
Ecobank Ghana row. `tsc --noEmit` and `eslint` both clean (pre-existing
`__root.tsx` error and baseline warnings only). `vite build` exit 0.

## 2026-09-18 — SSNIT ledger clarity; real GRA PAYE bands; overtime/bonus tax flag

Three items from a walkthrough.

### 2310 SSNIT Payable's dual use was invisible once posted

`post_payroll_run()` has posted both the employee withholding and the
employer's 13% contribution to the same account (2310) since
`20260909120000_payslip_employer_ssnit.sql`, distinguished only by each
`journal_lines` row's own `description` text. Asked to show reasoning
before building, since the fix approach mattered.

Checked whether the two General Ledger-adjacent views already handled
this before assuming they didn't: `accounting.ledger.tsx` (General
Ledger) already renders `lineDescription` inline, unconditionally, right
under the entry description — not broken. `accounting.journal-entries.tsx`
(Journal Entries list) already has a dedicated "Line description" column
in its expand-a-row detail table — not broken either, just behind a
normal click-to-expand, same as any other drill-into-a-row list. The
actual gap was narrower than the initial report implied: only the payroll
run's own embedded "Posted to Accounting" card (`PostedEntryCard` in
`payroll.$runId.tsx`) was missing the description entirely —
`EntryLinesTable` (shared with the pre-post confirmation dialog) never
had a description column, and the pre-post dialog only read fine because
it fakes distinct account *names* ("SSNIT Payable (employee)" / "(employer)")
for its synthetic preview rows, a trick that doesn't exist once the real
entry is posted and both lines share the account's one real name.

**Considered and rejected: a second account (2311) for the employer
portion**, i.e. the sub-account-code approach floated in the request.
Doesn't fit this schema at all — `accounts.code` has `check (code ~
'^[0-9]{3,6}$')`, strictly numeric, no separator, so a "2310-1/2310-2"
scheme would need loosening a constraint that's never been loosened for
any other account. A distinct whole code (2311) would fit that
constraint, but splits one real liability to one creditor (SSNIT, settled
in one monthly remittance) into two account balances by *cost origin*
rather than by creditor — "what do we owe SSNIT this month" stops being
a single account balance, and nothing in this app currently sums
accounts back together for that purpose. Introducing this codebase's
first-ever split/sub-account, solely to fix a display gap, would be a
disproportionate schema change for what turned out to be a small
rendering gap in one view.

**Fix:** `EntryLinesTable`'s `lines` gained an optional `description`,
rendered as a muted sub-line under the account code/name — the exact
pattern `accounting.ledger.tsx` already uses for `lineDescription`, now
applied here too. `PostedEntryCard` threads the real posted line's
`description` through. `PostRunDialog`'s synthetic preview lines also
gained matching `description` text (mirroring `post_payroll_run()`'s
own strings exactly) for every line, not just the two SSNIT ones, so the
pre-post preview and the post-post card render identically in structure
— the preview keeps its extra "(employee)"/"(employer)" name suffixes as
a bonus immediate-read clarity, not a substitute for the description.

Also corrected account 2310's own `description` (`Chart of Accounts`
page) — it only mentioned the employee side, which was accurate until
`20260909120000` and stale ever since (`20260918120000_ssnit_payable_
description_fix.sql`).

Verified against a real posted run rather than a browser pass (the dev
machine's swap stayed fully exhausted throughout, same constraint as the
last two sessions): created a run, generated one payslip, excluded the
rest, submitted for review and posted it end-to-end via the real RPC
chain as real `dev-accountant@tcs.test`/`dev-manager@tcs.test` sessions
(→ `JE-30080001`), then queried the resulting `journal_lines` directly —
`SSNIT withheld — August 2030` / `Employer SSNIT contribution — August
2030`, distinct as expected. Traced the render chain by reading every
link (`journal_lines.description` → PostgREST's `journal_lines(*, ...)`
embed → `mapJournalEntry` → `PostedEntryCard`'s new mapping →
`EntryLinesTable`) rather than screenshotting it. `tsc --noEmit` and
`eslint` (scoped + full-repo, ~21s) both clean except the same
pre-existing baseline issues. `vite build` exit 0.

### PAYE bands sourced from GRA's real published table

The `20260908070000` seed rows labeled "PLACEHOLDERS" turned out to
already be GRA's real monthly figures for five of seven bands — only the
top two needed correcting: band 6's upper bound and band 7's lower bound,
both 50,416.67 → 50,000
(`20260918130000_paye_bands_gra_2024.sql`).

Confirmed `paye_bands` stores **monthly**, not annual, thresholds before
touching anything: `create_payslip()`'s `v_taxable_income` is built
straight from `employee_pay_config.basic_salary` (a monthly figure) plus
monthly overtime/allowances minus monthly SSNIT/Tier2, compared directly
against `lower_bound`/`upper_bound` with no annualization step anywhere
in the band loop. GRA's monthly figures were used as-is, no conversion
needed.

GRA's own table (gra.gov.gh, labeled "Year 2024") has a genuine internal
rounding inconsistency: its band widths sum arithmetically to 50,416.67
(exactly where the original placeholder's boundary came from — it wasn't
a guess, someone had already sourced this correctly once), but the
table's own top-band row is explicitly labeled "Exceeding 50,000.00".
Per explicit direction: 50,000 is authoritative, GRA's literal stated
threshold over the arithmetic sum. The 30% band now runs 19,896.67 →
50,000 and 35% starts exactly at 50,000 — every taxable cedi still
covered by exactly one band, just a GHS 416.67 narrower 30% band than
the old placeholder.

`docs/CONSTRAINTS.md`: checklist item flipped from `[ ]` placeholder to
`[x]` sourced-from-GRA, with a new `[ ]` line for the residual "Year
2024, not re-confirmed against a later revision" risk. "Statutory
accuracy" section rewritten to match, with the monthly-vs-annual and
rounding-inconsistency reasoning spelled out there too.

Verified against a real posted payslip (the same `JE-30080001` run
above, employee EMMANUEL ANSAH, taxable income GHS 6,142.50): computed
tax GHS 1,134.13 by hand against the corrected bands (0 + 5.50 + 13.00 +
554.08 + 561.46, each rounded per-band the way `create_payslip()` itself
does) and it matched the actual posted `payslips.tax` value, confirming
the corrected bands are live and computing correctly, not just seeded.

### New flag: overtime/bonus may need non-graduated tax treatment

Not built, per explicit decision — documentation only.
`docs/CONSTRAINTS.md` gained a new checklist item + a matching
"Statutory accuracy" bullet: GRA's monthly PAYE schedule's own completion
notes (items 23–24) suggest overtime pay for a *qualifying junior
employee* (income ≤ GHS 800/month or GHS 9,600/year) may need a separate
concessionary flat rate rather than the graduated bands
`create_payslip()` currently applies to every overtime cedi — meaning
current overtime taxation could be wrong specifically for TCS's
lower-paid staff. Lower priority and also unmodeled: bonus income
reportedly carries its own flat 5% final-tax treatment (up to 15% of
annual basic). Both need confirmation from TCS's accountant or GRA
directly before any code changes.

## 2026-09-19 — Payroll → Setup banner still said "placeholder" after the GRA fix

The statutory-rates banner on `payroll.pay-config.tsx` still read
"Placeholder figures — verify against SSNIT / GRA before running real
payroll," left over from before `20260918130000_paye_bands_gra_2024.sql`
corrected `paye_bands` against GRA's real published table — a stale
warning actively contradicting what was now true in the database.

Reworded exactly per the requested wording, deliberately not
overstating certainty: "SSNIT/Tier 2 rates confirmed against TCS's
actual payroll practice; PAYE bands sourced from GRA's published table
(gra.gov.gh) — see docs/CONSTRAINTS.md for the one noted ambiguity
(top-band threshold) and the still-open overtime/bonus tax treatment
question." This is "verified against the best available source, two
specific tracked caveats," not "fully verified, zero open questions" —
matches how `docs/CONSTRAINTS.md` itself now describes the same state
(previous entry).

Verified with a real browser pass this time — the dev machine's swap had
been expanded and had headroom again, unlike the last several rounds.
One snag worth remembering: the first Playwright attempt filled the
login form immediately after `page.goto(..., { waitUntil: "load" })`
and the fields showed empty in the resulting screenshot — a race between
Playwright's `fill()` and this SSR app's client-side hydration attaching
React's controlled-input state after the DOM nodes already existed.
Adding a short wait after `goto()` before filling fixed it. Logged in as
`dev-manager@tcs.test`, opened `/payroll/pay-config`, confirmed via the
rendered page text that the new wording is present, the old "Placeholder
figures" text is gone, and there were zero console/page errors.
`tsc --noEmit` clean except the same pre-existing, unrelated `__root.tsx`
error. `eslint` (scoped + full-repo, ~21s) clean except the same
pre-existing baseline issues. `vite build` exit 0.

## 2026-09-19 — Sidebar/Dashboard/Reports reorganized around Finance & HR, not retail

"The app still reads as a retail ERP rather than a school tool" — a
navigation-wide reorg, planned and confirmed before any code (four
files touched, all nav-adjacent). Full plan and the two open judgment
calls (add new HR/Payroll dashboard widgets? extend search to index
staff?) were put to Eyram before building; both landed on the
recommended option.

### Sidebar (`components/layout/app-sidebar.tsx`)

Flat 17-item list → `navSections`: **Finance & Accounting**
(Accounting, Expenses, Banking, Reports), **HR & Payroll** (Employees,
Payroll, Login Accounts), **Procurement & Stores · not yet in use**
(Customers, Inventory, Sales & Invoicing, Pro-forma Invoices, Customer
Deposits, POS, End of Day, Purchasing — collapsed by default, muted
text when expanded), with Dashboard standing alone at the top and
Settings pinned to the bottom behind its own divider. Verified the
proposed grouping against the code rather than assuming it was right:
Accounting/Payroll/Banking/Purchasing/Reports/Employees/Login Accounts
already share one `canViewFinancials` gate, which happens to line up
exactly with the Finance+HR split — a good sign the grouping matches
how the app already models itself, not just how it looks.

A collapsed dormant section auto-opens if the current route is inside
it (a bookmark or deep link into Inventory shouldn't hide the very nav
entry explaining where you are). Icon-rail (fully collapsed) mode skips
grouping entirely and renders every item flat, same as before this
change — no room for section labels there anyway. A section header now
hides itself when none of its items are visible for the current role
(previously each item just vanished one-by-one from a flat list) —
built as a general rule, not a special case, so e.g. an Attendant sees
no "HR & Payroll" header at all rather than an empty one.

Considered and rejected retrofitting the full shadcn `Sidebar`/
`SidebarGroup` primitive set already vendored in `components/ui/
sidebar.tsx` but never wired up (no `SidebarProvider`, no consumer) —
`AppSidebar` is hand-rolled and works today; pulling in an unused
context system for a cosmetic reorg risked the collapse/mobile-drawer
behavior that already works, for no real benefit over plain local
`useState`.

**Found, not fixed**: Expenses isn't in the sidebar's role-filter list,
so it stays visible to Attendant even though `expenses_select`'s RLS
(Manager/Accountant/Auditor only) already blocks Attendant from reading
it — a pre-existing nav/RLS mismatch this reorg surfaced (Finance &
Accounting shrinks to just "Expenses" for that role) but didn't
introduce or fix. Flagged for a separate look.

`docs/DESIGN.md` gained a bullet documenting `navSections` as the
established convention: the next real module (Transport, Kitchen,
Asset Management, Analytics & BI, ...) gets its own top-level section
the same way, once it's an actual route — never an empty nav entry
pointing nowhere just to reserve the shape.

### Dashboard (`routes/index.tsx`, `data/dashboard.ts`)

Of 5 KPIs, 3 were retail (Today's Sales, This Month's Sales, Inventory
Value) and the two widgets below (12-month revenue chart, "Recent
transactions") were 100% retail — and there was no Payroll/Accounting
widget at all, not "deprioritized," genuinely absent. Cash on Hand and
Expenses this Month now lead a 4-up primary row; the 3 retail KPIs plus
the revenue chart, Low stock products, and Recent transactions all moved
into one `border-dashed` "Store & Sales · not yet in use" block, always
visible but visually demoted (not collapsed — a dashboard is a
glance-once-per-visit read, unlike the sidebar, so hiding a chart behind
a click seemed like the wrong tradeoff here even though it was the right
one for nav).

Filled the resulting gap (confirmed with Eyram first) with two new
small widgets built from data that already existed elsewhere:
**Pending approvals** (`useEmployees()` + `splitPendingConfigs()`,
exactly the same count `employees.index.tsx`'s own summary card
computes) and **Latest payroll run** (`usePayroll()`'s `runs`, sorted by
year then month client-side since the query only orders by year
server-side — a real gap that would have silently returned the wrong
"latest" run within a year otherwise). Both gated behind the same
`canViewFinancials` check as Cash on Hand (`canSeeHrPayrollWidgets`),
showing "Visible to Manager, Accountant and Auditor" rather than a
misleading 0/blank for Attendant.

### Reports (`routes/reports.tsx`)

Of 11 reports, only Expenses Summary runs on data TCS has today —
everything else (Sales Summary, Profit & Margin, Operating Margin,
Product Performance, Inventory Valuation, Discounts Given, Payment
Methods, Returns & Exchanges) reads Sales/POS/Inventory. Debtors &
Receivables and VAT Summary are the interesting edge case: conceptually
relevant to a school (fees owed, tax) but built entirely on the
Sales/Invoicing domain today, so they'd render empty for TCS right now
for a data-model reason, not a conceptual one — grouped with the rest
rather than promoted, since promoting them today would just show an
empty report with no explanation why. Applied the identical collapsed-
by-default grouping to the report picker (same "flat list of buttons"
shape as the sidebar) via `DORMANT_REPORT_IDS`, same auto-open-if-
active behavior. Changed the default active report from Sales Summary
to Expenses Summary. Reworded the page header, the role-gate empty-state
header, and the `<head>` meta description — all three led with "Sales,
profit, ... inventory" and never mentioned Expenses despite it being the
one populated report.

### Global search (`components/layout/topbar.tsx`)

Placeholder was `"Search customers, products, invoices…"` — already
slightly wrong (the search also matches expenses and suppliers, neither
mentioned) on top of being retail-first. Changed to `"Search expenses,
customers, invoices…"`, accurate to what's actually searched, leading
with the finance-relevant one. Confirmed with Eyram: not extending
search to index Employees/Staff as part of this pass (a real feature
gap, flagged, bigger scope than a wording fix) — the new placeholder
doesn't claim staff are searchable, since they aren't.

### Verification

Real browser pass as both `dev-manager@tcs.test` and
`dev-attendant@tcs.test` (memory pressure had eased since the last
couple of rounds — full pass this time, not a data trace). Confirmed:
all three sections render with the right items and the right collapsed/
expanded default state; expanding "Procurement & Stores" reveals its
items in muted styling; the dormant report group and its auto-open-on-
active behavior both work; the new Pending Approvals/Latest Payroll Run
widgets show real data (a leftover test payroll run from an earlier
session's verification, "August 2030 · Posted," rendered correctly);
Attendant's dashboard correctly grays out all three HR/Finance-gated
widgets and the HR & Payroll section header is fully absent, not empty;
zero console/page errors across both sessions. `tsc --noEmit` clean
except the same pre-existing `__root.tsx` error. Full-repo `eslint`
clean except the same pre-existing baseline issues (8–10s). `vite build`
exit 0.

## 2026-09-19 — Closed the Expenses nav/RLS gap flagged above

Quick follow-up: added `/expenses` to `app-sidebar.tsx`'s
`FINANCE_GATED_URLS`, the same Manager/Accountant/Auditor filter list
already governing Accounting/Payroll/Banking/Purchasing/Employees/Login
Accounts — `expenses_select`'s RLS has always been that exact role set,
the nav link just never matched it. An Attendant no longer sees a link
to a page that would only ever render empty for them; Finance &
Accounting's header now correctly disappears for that role too (it was
Expenses's only remaining item there), via the "hide a section header
with nothing visible in it" rule from the reorg above — no special-
casing needed, that rule already covered this once the item itself was
gated.

Verified with a real browser pass as `dev-attendant@tcs.test`: sidebar
now shows only Dashboard, Procurement & Stores (collapsed), and
Settings — no Expenses link, no Finance & Accounting header, zero
console errors. Left untouched, deliberately out of scope for this
targeted fix: the Dashboard's own "Expenses this Month" KPI isn't
role-gated the way Cash on Hand/Pending Approvals/Latest Payroll Run
are — it still shows a real (if RLS-empty) figure to Attendant. That's
a separate widget-level gap, not the nav-link visibility this fix was
about. `tsc --noEmit` clean except the same pre-existing `__root.tsx`
error. Full-repo `eslint` clean except the same pre-existing baseline
issues. `vite build` exit 0.

## 2026-09-19 — Role-gated the Dashboard's Expenses this Month KPI

Second follow-up from the same reorg: the "Expenses this Month" card
wasn't gated the way Cash on Hand (and the two new HR/Payroll widgets)
were, so an Attendant saw a real-looking GH₵0 figure instead of the
"unavailable" treatment — indistinguishable from a genuinely-zero month,
when what was actually happening is `expenses_select`'s RLS (Manager/
Accountant/Auditor only) returning an empty array to that role.

`data/dashboard.ts`: added `unavailable: !canReadLedger` to the
Expenses this Month KPI, same flag Cash on Hand already uses (same role
set, `expenses_select` and the ledger tables share the identical RLS
gate), and its hint now reads "Visible to Manager, Accountant and
Auditor" when gated instead of "N expenses recorded" against an array
that's empty for the wrong reason. `KpiCard` in `routes/index.tsx`
already renders `unavailable` as "—" with no code changes needed there
— this was purely a missing flag on one KPI definition, not a rendering
gap. Updated the neighboring comment on Cash on Hand, which used to
claim "only this KPI can ever be role-gated" — no longer true now that
a second one is.

Verified with a real browser pass as both `dev-attendant@tcs.test`
(now shows "—" / "Visible to Manager, Accountant and Auditor", matching
Cash on Hand/Pending Approvals/Latest Payroll Run exactly) and
`dev-manager@tcs.test` (unchanged: real figure, "0 expenses recorded").
Zero console errors either session. `tsc --noEmit` clean except the
same pre-existing `__root.tsx` error. Full-repo `eslint` clean except
the same pre-existing baseline issues. `vite build` exit 0.

## 2026-09-19 — HR beyond payroll: the full plan, and Phase 1 (staff record enrichment)

New scope, informed directly by TCS's existing Google Apps Script HR
system (its User Manual, two setup guides, the live `TCS_HR_Master_
Database.xlsx`, and the Interview Assessment Form — read for field
names, workflow logic and email conventions; its security model, a
public Google Form with zero RLS, was explicitly not carried over).
Recruitment stays on that system for now (Careers form, Applicant
pipeline, Interview Tracker) — a separate, later migration.

### The plan, presented before any code (per explicit request)

Six areas: staff record enrichment, an onboarding checklist workflow, a
private document-storage bucket for onboarding uploads (applying the
receipts-bucket lesson from day one this time), contract generation and
lifecycle, real email infrastructure, and a call on Leave/KPI/Training/
Disciplinary/Exit & Offboarding.

Reading the actual live spreadsheet (not just the manual's prose) turned
up several things worth having gotten right before building:
- **The onboarding checklist has 18 items in the real system**, not the
  5 broadly summarized in the request — schema needed to be general
  enough to hold all 18 (a school-editable catalog + per-employee
  completion rows), not 5 hardcoded columns.
- **Bank details and salary already live on `employee_pay_config`**, not
  a flat staff row — the source spreadsheet flattens everything; this
  schema doesn't copy that.
- **"Handbook Issued?" appears in both the enrichment list and the
  onboarding checklist** in the request — resolved as one thing (an
  onboarding task with a timestamp), not duplicated.
- **`STAFF_STATUS` exists in the sheet but wasn't in the requested field
  list** — correctly left out: it would've collided with the existing
  `employment_status`, which already gates payroll eligibility.
- **Three more tabs exist beyond the two the request named as
  "for future use"** — `07 TRAINING`, `08 DISCIPLINARY`, `09 EXIT &
  OFFBOARDING`, fully fielded with their own dropdown enums, same as
  Leave/KPI. Flagged alongside them rather than assumed out of scope.
- **The payroll page's disabled "Email payslips" button** (tooltip:
  "needs an email provider and staff email addresses") is directly
  unblocked by two things in this same plan — the email infra (item 5)
  and the new `school_email` field (item 1). Confirmed the connection
  the request asked about.
- **This repo already has a working transactional-email mechanism** —
  `invite-staff`'s edge function has its own `sendMail()` via
  `nodemailer` + `SMTP_HOST/PORT/USER/PASS/FROM` secrets, currently used
  only for its "resend invite" path (and only working locally, against
  Inbucket). Changed the email recommendation from "new Resend REST
  integration" to "point this existing mechanism at Resend's SMTP relay"
  — smaller, and it's the exact same secrets already needed for
  `invite-staff`'s own production invite emails to start working at all.
- **jsPDF's `html()` render mode and its `html2canvas` peer are already
  installed** (confirmed in `node_modules` — an unused transitive
  dependency of `jspdf`), which settles the contract-document mechanism:
  HTML templates with `{{placeholder}}` merge tags, rendered via
  `doc.html()` rather than hand-positioned `doc.text()` calls the way
  `invoice-pdf.ts`/`payslip-pdf.ts` do — the right fit for prose of
  unpredictable length, vs. those two files' known-structure tabular
  documents.

Three genuine judgment calls were put to Eyram before building, all
confirmed on the recommended option: (1) a tokenized, unauthenticated
public onboarding-form path (mirroring the source system's own approach,
rather than inventing a fifth `staff` role) — this will be this app's
**first-ever anon write path**, called out explicitly rather than
introduced quietly; (2) Eyram runs `supabase secrets set` himself once
Resend credentials exist, rather than pasting them into the dashboard;
(3) defer Leave, KPI & Performance, Training, Disciplinary, and Exit &
Offboarding **uniformly** — none had working logic anywhere to preserve,
just column shapes to copy later if ever needed. `docs/CONSTRAINTS.md`
gained a new section recording all three decisions and the deferred-list
scope.

### Phase 1: staff record enrichment — built and verified

17 new columns on `employees` (`20260919100000_employee_hr_fields.sql`):
`preferred_name`, `date_of_birth`, `gender`, `national_id`,
`personal_email`, `school_email`, `employment_type` (check-constrained to
the live system's actual seeded dropdown — `Full-Time`/`Part-Time`/
`Contract`/`Volunteer`/`Intern`; its own user manual says "Fixed-Term,
etc." but that's not what's actually in the dropdown, confirmed directly
against the spreadsheet), `start_date`, `probation_end_date`,
`contract_end_date`, `emergency_contact_name`/`_phone`,
`residential_address`, `qualifications`, `ssnit_number`, `tin_number`,
`church_denomination`. Every one a plain current-state fact, direct-edit,
no approval gate — same treatment as the existing `phone`/`position`/
`department`.

`uppercase_employee_fields()` extended to the new name-like/ID-like
fields (`preferred_name`, `national_id`, `ssnit_number`, `tin_number`,
`church_denomination`, `emergency_contact_name`); `personal_email`/
`school_email` **lowercased** by the same trigger instead — the real
convention for email addresses, correcting what the old "email and phone
both left alone" comment implied. `residential_address`/`qualifications`
stay as-typed.

`update_employee_profile()` (drop + recreate, per the argument-list-
change rule): its three original params keep their exact existing
behavior unchanged (always sent, always set) — the 17 new ones are
trailing, default-`null` optional params using the same amend-in-place
idiom as `approve_pay_config()`'s override params (`20260918`): `null`
means "leave unchanged," an explicit empty string clears a text field.
This let the frontend ship a wholly separate "HR details" card with its
own independent Save button, without touching `ProfileForm`'s existing
phone/position/department behavior at all — it just re-sends the
employee's current values for those three every time the new card saves.

`employees-store.ts`: `Employee` gained the 17 fields (mapped from
snake_case), a new `EmploymentType` union, and `updateEmployeeProfile()`
gained an optional third `hrDetails` argument. `employees.$employeeId.tsx`
gained `HrDetailsSection`, mirroring `ProfileForm`'s exact card/dirty-
check/save pattern.

**Verified with a real browser pass**: local `db reset` applied the
migration clean; `check-duplicate-function-overloads.sh` reported none;
`database.types.ts` regenerated (one redo needed — piping `2>&1 | tail`
into the same redirect target as the file write mixed the CLI's own
stderr noise into the generated file; fixed by filtering the known noise
lines before writing). Logged in as `dev-manager@tcs.test`, opened an
employee record, filled every new HR-details field, saved, reloaded, and
confirmed via screenshot that all seven spot-checked fields persisted
correctly with the right casing (`TESTY`, `Female` left alone, `BAPTIST`
uppercased from a lowercase `baptist` typed in) — cross-checked directly
against the database with `psql`, which matched exactly. `tsc --noEmit`
clean except the same pre-existing `__root.tsx` error. Full-repo `eslint`
clean except the same pre-existing baseline issues (~17s). `vite build`
exit 0.

Phases 2–5 (document storage, onboarding + the tokenized public form,
contract generation, email infrastructure) are separate follow-up
sessions, each with their own plan-to-verification pass, per the phasing
laid out when the full plan was presented.

## 2026-09-20 — HR beyond payroll, Phase 2: document storage for onboarding uploads

Built the private storage bucket + metadata table for onboarding personal
documents (national ID, certificates, photo), applying the receipts-bucket
lesson (`20260918110000`) from the very first commit instead of retrofitting
it later — see docs/DESIGN.md's new "Document storage applies the
receipts-bucket lesson" bullet for the exact shape.

`20260920100000_employee_documents.sql`: `onboarding-documents` bucket
created with `public = false`; four `storage.objects` policies mirroring
`receipts_select`/`insert`/`update`/`delete` exactly (select Manager/
Accountant/Auditor, write Manager/Accountant). `employee_documents` table
(employee_id, document_type, storage_path, uploaded_by, uploaded_at,
notes) with the same RLS shape as `employee_allowances` — plain RLS
writes, not a SECURITY DEFINER RPC, not approval-gated, no audit_log
trigger. `document_type` is a checked enum (`National ID` / `Certificate`
/ `Photo` / `Other`) rather than free text, matching the small,
school-controlled scope of what onboarding actually asks for.

**Held back on purpose, not stubbed**: the plan called for an `anon`
INSERT policy scoped to a valid onboarding token embedded in the object
path, prepping this bucket for Phase 3's public form. Building that policy
now was impossible, not just premature — its `with check` needs to look up
the token in `onboarding_tokens`, a table that won't exist until Phase 3,
and Postgres fails a `create policy` referencing an undefined table
outright. So there is currently no `anon` access to this bucket at all;
that policy arrives together with `onboarding_tokens` in Phase 3's own
migration, never as a dormant no-op sitting in the schema in the meantime.

Frontend: new `employee-documents-store.ts` (`listEmployeeDocuments`,
`uploadEmployeeDocument`, `deleteEmployeeDocument`), all reads through
`createSignedUrls()`, never `getPublicUrl()`. New `DocumentsSection` on
the employee profile page (`employees.$employeeId.tsx`) — upload form
(type + file + notes) gated `canWrite`, a list of uploaded documents with
a signed "View" link, delete gated `canWrite`. Placed directly after the
new HR-details card.

**Verified with a real browser pass**, specifically targeting the two
things this phase was about — bucket privacy and the RLS matrix:
- Logged in as `dev-manager@tcs.test`, uploaded a test file, confirmed the
  row and its signed "View" link appeared, and confirmed the signed URL
  itself resolves (`200`).
- Fetched the *same object* through Storage's `/object/public/<path>`
  endpoint directly (no signed token) — got back `404 Bucket not found`.
  This is the same test used to verify the receipts fix, and the same
  signature: Storage doesn't even acknowledge a non-public bucket exists
  through that route, rather than a generic 403.
- `dev-auditor@tcs.test`: sees the Documents section and the View link,
  no Upload button — correct read-only.
- `dev-accountant@tcs.test`: sees and can use the Upload button, and
  successfully deleted the manager's test row (used to confirm delete
  permission and to clean up the test data in the same step).
- `dev-attendant@tcs.test`: hits the pre-existing "Employees isn't
  available for this role" guard before ever reaching the Documents
  section — confirms Attendant has no path to this data at all, not just
  an empty result.
- Cross-checked directly against the database afterwards: `storage.buckets`
  shows `onboarding-documents` / `public = f`, and `employee_documents` is
  empty (the test row was actually deleted through the UI, not just
  hidden client-side).
- `tsc --noEmit` clean except the same pre-existing `__root.tsx` error.
  `eslint` clean except the same pre-existing baseline (13 problems,
  full repo). `vite build` exit 0. `check-duplicate-function-overloads.sh`
  reported none.

Phases 3–5 (onboarding checklist + the tokenized public form, contract
generation, email infrastructure) remain separate follow-up sessions.

## 2026-09-21 — HR beyond payroll, Phase 3: onboarding checklist + the tokenized public form

Built the onboarding checklist (manual + derived items), the freeze-once
`onboarding_completed_at`, and the tokenized public onboarding form — the
first anon-writable path in this app. Full rationale is in docs/DESIGN.md's
new "Onboarding checklist: manual vs. derived items, and the first
anon-writable path" bullet; this entry covers what got built and how it
was verified.

**One deviation from the original plan**, based on the real
ACCEPTED_STAFF_ONBOARDING tracker rather than just the Apps Script source:
the 18 items split into manual (checkbox-toggled, `toggle_onboarding_task()`)
and derived (trigger-computed, never toggleable) kinds. Two collapses from
four named derived signals down to two catalog rows — "Bank Details Form"/
"Payroll Added" are the same predicate under two names, and "Staff Email
Created"/"Staff ID Issued" were both specified against the identical
compound condition — this schema can't distinguish either pair as separate
facts, so keeping four rows would double-count two signals with no added
information. 14 manual + 2 derived = 16 catalog rows.

`20260921100000_onboarding_checklist_and_public_form.sql`:
`onboarding_checklist_items` (school-editable catalog, same shape as
`positions`/`departments`), `employee_onboarding_tasks` (RPC-only writes,
same "no direct RLS write policy" pattern as `employees`), `employee_onboarding_tokens`
and `employee_onboarding_submissions` (the security-sensitive pair — see
below), plus `employees.onboarding_completed_at`. Also widened
`employee_documents.document_type` (20260920) from its 4-value placeholder
guess to the real 8 document-backed item names, now that this data exists —
those names double as `document_type` values written by
`approve_onboarding_submission()`, no separate mapping table needed.

**Derived-item mechanics**: `recompute_derived_onboarding_task()` is called
by triggers on `employee_pay_config` (insert/update) and on `staff`/
`employees.school_email` (insert/update), recomputing just the affected
derived item for that employee. `initialize_onboarding_tasks()` snapshots
every currently-active catalog item onto a newly-Active employee — fired
by a widened trigger that covers both the normal `approve_employee()`
transition (UPDATE) *and* a row inserted already Active (seed data, a
future importer), since the latter never fires an "UPDATE OF
employment_status" trigger at all. Caught this the hard way: the first
`db reset` after writing the migration showed every seeded demo employee
with only 2 of 16 tasks (the two derived ones, created by the pay-config/
staff triggers firing off seed.sql's own inserts) — the migration's
backfill loop had run before seed.sql existed (migrations apply before
seeding, always), and the transition trigger was UPDATE-only so it never
caught employees inserted directly as Active. Fixed by widening the
trigger to `after insert or update of employment_status`; the backfill
loop stays for its real purpose (a production deploy where Active
employees already exist in the table when this migration runs).

**The tokenized public form** — reviewed carefully since this is a new
security surface for the app, not just a new feature:
- `generate_onboarding_token()` (Manager/Accountant, Active employees
  only) mints 32 bytes via pgcrypto's `gen_random_bytes()`, returns the
  raw 64-hex-char token to the caller once, stores only its SHA-256 hash.
- Expiry (14 days default) checked on every use.
- Single-use closed with a row lock: `submit_onboarding_form()` does
  `select ... for update` before checking `used_at`, so a concurrent
  double-submit blocks on the lock rather than racing past the check.
- Document uploads happen before the RPC call (token still unused at
  upload time); the storage policy validates the token in the object path
  via `is_valid_onboarding_token()`, a boolean-only SECURITY DEFINER
  function — anon never gets a direct read policy on the tokens table
  itself, which a naive "let anon read tokens so the storage policy can
  check them" approach would have required.
- `approve_onboarding_submission()` copies personal-fact fields (DOB,
  national ID, emergency contact, address, qualifications) and uploaded
  documents onto the real tables, but deliberately leaves
  `employee_pay_config` alone — the submission's bank fields are for HR's
  reference only, so the existing Accountant-proposes/Manager-approves
  gate on bank/account changes isn't quietly bypassed by a single
  onboarding-review approval.

Frontend: new `onboarding-store.ts` (tasks, submissions, token
generation/review — all RPC calls, no direct writes) and a new
"Onboarding checklist" card on the employee profile page (Active
employees only, since tasks only exist post-Active): checkbox list with
"Auto"/"Document" badges, a one-time-reveal generated link with a copy
button, and a submissions review list with Approve/Reject (reusing the
existing `RejectButton` dialog). New public route
`/onboarding/$token` (`onboarding.$token.tsx`) — added to `__root.tsx`'s
auth-free allowlist alongside `/login`/`/accept-invite`, since a candidate
here has no ERP account at all and every real check happens server-side.

**Verified with a real end-to-end browser pass**, specifically targeting
the anon path:
- `dev-manager@tcs.test`: sees the checklist (1 of 16 complete —
  seed data's pay config satisfies the one derived item), generates a
  link, gets a one-time reveal with a working copy button.
- `dev-auditor@tcs.test`: sees the same checklist read-only, no "Generate
  onboarding link" button.
- No login at all: opened the generated link, saw the real employee's
  name/position/department, added a document, checked contract
  acceptance, typed a signature, submitted — success page shown.
- **Reused the identical link immediately after**: got "This link is
  invalid or has expired" — single-use confirmed in a real browser, not
  just at the SQL level.
- Fetched the uploaded object through Storage's unsigned
  `/object/public/...` endpoint directly: `400`/`Bucket not found`, same
  signature as the Phase 2 receipts-style check.
- `dev-manager@tcs.test` again: saw the Pending Review submission,
  approved it — badge flipped to Approved.
- Cross-checked the database afterwards: `employees.date_of_birth`/
  `.national_id` updated from the submission, a real `employee_documents`
  row created (`document_type = 'ID Copy'`, matching the checklist item
  name), the token's `used_at` set, and — importantly — the "ID Copy"
  checklist item itself is still unchecked: approving a submission gets
  the data and files into the system, it does not silently mark a manual
  item done. A human still has to look at the document and check the box.
- Also verified directly at the SQL level before the browser pass: the
  `toggle_onboarding_task()` guard rejects toggling a derived item
  ("This item is tracked automatically and can't be toggled by hand"),
  and `onboarding_completed_at` — once set by checking all 16 items —
  stayed set after manually unchecking one item again (never cleared).
- `tsc --noEmit` clean except the same pre-existing `__root.tsx` error.
  `eslint` clean except the same pre-existing baseline (13 problems, full
  repo). `vite build` exit 0. `check-duplicate-function-overloads.sh`
  reported none.

Known, accepted scope limits carried into Phase 4: no "revoke an
unexpired token" RPC, no cap on multiple open tokens per employee
(expiry is the only staleness mechanism), and no UI yet for editing the
checklist catalog itself (adding/renaming/deactivating items is possible
via direct SQL/a future Settings screen, not built here).

Phases 4–5 (contract generation and lifecycle, email infrastructure)
remain separate follow-up sessions.

## 2026-09-22 — Onboarding review fixes from production testing

Five fixes from a real walkthrough, one of them a priority correctness/
security bug in the review flow itself.

**Priority fix — the pending submission couldn't be reviewed before
Approve.** `SubmissionReview`'s previous version rendered only a handful
of fields (DOB, national ID, emergency contact, bank, signature) and a
bare document *count* — gender, personal email, residential address,
qualifications, and payment method were never rendered at all, and
uploaded documents had no viewable link anywhere before clicking Approve.
For the one path in this app anonymous strangers can write through, that
meant the human review step was reviewing nothing. Root cause was
frontend-only: the storage `onboarding_documents_select` RLS policy is
already bucket-wide for Manager/Accountant/Auditor (not scoped to a
specific object path), so an authenticated review session could always
sign these paths — `listOnboardingSubmissions()` just never called
`createSignedUrls()` on them. Fixed by signing every submission's
document paths at read time and rendering the full field set (every
`OnboardingSubmission` field, `?? "—"` for blanks) plus clickable signed
links, in a new `SubmissionReview` component, matching the same
"everything visible inline, right where the action is" shape the pending
pay-config proposal already uses. Verified in a real browser: opened the
submission review card *before* clicking Approve and confirmed gender,
personal email, residential address, and qualifications were all visible
in the card text, the uploaded document's link was present and signed
(`token=` in the URL), and directly fetching that pre-approval link
returned `200` — not just present in the DOM, actually resolving.

**Gender dropdown on the public form.** Replaced the free-text `Input`
with a `Select` (Male/Female) on `/onboarding/$token`, plus a server-side
check constraint on `employee_onboarding_submissions.gender` — this is
the anon-writable path, so the constraint isn't just a UI nicety.
`employees.gender` itself (edited by HR through `HrDetailsSection`) stays
free text; that field wasn't in scope for this fix and constraining it
would break existing direct-edit behavior there. Worth revisiting later
if that inconsistency becomes a real problem.

**"ID Copy" renamed to "National ID"**, matching `employees.national_id`'s
own naming — a data migration (`update ... set name = 'National ID'`),
not a schema change, plus updating the one existing `employee_documents`
row and the `document_type` check constraint to match, plus the frontend
`DocumentType` union. Deliberately a new migration, not an edit to the
Phase 3 migration that first seeded "ID Copy" — same "always fix forward"
convention this repo already follows for same-day corrections
(`ssnit_payable_description_fix`, etc.), even though nothing here had
been committed yet.

**National ID / SSNIT Card / TIN Copy now accept a document OR a typed
number**, with which one actually recorded. New
`onboarding_checklist_items.accepts_number_in_lieu` (true for these
three), and `employee_onboarding_tasks.provided_via` /
`.provided_number`. `toggle_onboarding_task()` (argument list changed,
dropped and recreated) now requires one of `'document'`/`'number'` for
these three when completing: `'document'` is checked against a real
`employee_documents` row for that employee (raises a clear error
otherwise — "upload one first, or record the number instead"),
`'number'` requires a non-blank value and **also writes it onto the
matching `employees` column** (`national_id`/`ssnit_number`/`tin_number`)
so HR doesn't have to type the same number twice. Unchecking an item
always clears `provided_via`/`provided_number` — if it's redone, that's a
fresh choice, not a stale leftover. Frontend: `ChecklistTaskRow` now
special-cases these three items with a small inline chooser (Select:
document/number, a text input that appears for the number path, Confirm/
Cancel) instead of a plain checkbox; a completed item shows a "Document"
or "Number: <value>" badge. Verified all three guard paths directly at
the SQL level (missing choice, document-without-a-file, and the
success path) before the browser pass, then end-to-end in the browser:
marked "National ID" done via document (one existed from the approved
submission above) and "SSNIT Card" done via a typed number, confirmed
both badges rendered, and confirmed `employees.ssnit_number` picked up
the typed value in the database.

All four verified together in one browser walkthrough (Manager generates
a link → anon fills the form with the new gender dropdown, uploads a
"National ID"-labeled document, submits → Manager reviews the full
detail and a working document link *before* approving → Manager marks
the two special checklist items via document/number). `tsc`, `eslint`,
`vite build`, and `check-duplicate-function-overloads.sh` all clean at
the existing baseline.

**Qualifications multi-select — proposed, not yet built.** Eyram asked
for qualifications to move from free text to a multi-select backed by a
school-editable reference list (same "promote free-text to a curated
list" pattern as `positions`/`departments`/`payment_providers`/
`allowance_types`), with new entries added the same way those lists
already are — a `positions`/`departments`-shaped table plus a
`RefListSection` entry on the Payroll Setup page, not an inline
add-while-picking affordance (checked: none of the existing single-select
pickers have that either — `RefListSelect` only lets an out-of-list value
round-trip with a "(not in list)" badge; adding a genuinely new option
already only happens on that settings page). Proposed a 15-entry starter
seed (WASSCE/SSSCE through Doctorate, NTC Teaching License, Early
Childhood/Montessori certificates, and common support-role certs — First
Aid, Food Handler's, Commercial Driving License, Professional Accounting,
Security) for Eyram to review before building — `employees.qualifications`
would become `text[]` (matching the `position`/`department` "list
constrains the picker, not an FK" convention) and needs a genuine
multi-select component, which nothing in this codebase has yet
(`command.tsx`/`popover.tsx` exist and are the right building blocks —
`product-search-select.tsx` is the closest existing single-select
combobox to adapt). Not started pending that review.

## 2026-09-23 — Qualifications: free text to a school-editable multi-select

Built the piece deferred from 2026-09-22, after showing the proposed
15-entry seed list for review.

`20260923100000_qualifications_reference_list.sql`: new `qualifications`
table, same shape/RLS as `positions`/`departments` (select M/Acc/Aud,
write M/Acc) — minus the uppercase trigger, since these read as proper
names/certifications rather than short codes. One addition beyond that
precedent: a second `select` policy scoped `to anon using (is_active)`,
since the public onboarding form needs the active list too. This isn't
narrowed behind a SECURITY DEFINER function the way the tokenized-form
security note insists on elsewhere — there's nothing sensitive in a
qualification's name, position, or `is_active` flag to protect, so a
direct RLS grant is the simpler, equally-safe choice; the earlier
narrowing was specifically about not leaking `employee_id`/`created_by`
alongside a boolean check, which doesn't apply here. Confirmed the two
`select` policies don't cross-contaminate: `to anon` policies are scoped
by Postgres role membership, so an authenticated Attendant session (which
still shouldn't see this table) never picks up the anon-scoped policy —
verified with `set role anon` in a rolled-back transaction.

`employees.qualifications` and `employee_onboarding_submissions.qualifications`
both changed `text` -> `text[]` (existing values wrapped in a
single-element array, not discarded). `update_employee_profile()` and
`submit_onboarding_form()` both had their `p_qualifications` parameter
retyped the same way — an argument type change, so both were dropped
before recreating, same as every other argument-list change this session.
The array itself follows the exact same amend-in-place idiom as every
other field on `update_employee_profile()`, just without the text-specific
`nullif(trim())` dance: `coalesce(p_qualifications, qualifications)` —
null leaves it unchanged, an explicit `'{}'` clears it.

New `RefListMultiSelect` (`components/employees/ref-list-multi-select.tsx`),
adapting `ProductSearchSelect`'s Command+Popover combobox shape to more
than one selection, with removable badges and the same "(not in list)"
round-trip treatment as `RefListSelect` for a stored value the active
list no longer has. Deliberately no inline "add a new option" affordance
in the picker itself — checked first, and none of the existing
single-select pickers have that either; a new entry is always added on
the Payroll Setup page's `RefListSection`, which now has a "Qualifications"
entry alongside Positions/Departments. `org-lists-store.ts`'s
`makeRefListStore()` factory (already parameterized by table name) just
needed its type union widened to include `"qualifications"` — no new
store plumbing required. Wired into both places `employees.qualifications`
is written: `HrDetailsSection` (HR's direct edit) and the public
onboarding form (candidate self-entry) — both read the same
`useQualifications()` list, which correctly returns only active entries
for an anon session and everything (for toggling inactive ones back on)
for an authenticated Manager/Accountant/Auditor session, via RLS alone,
no client-side branching needed.

**Verified with two real browser passes**: Payroll Setup's Qualifications
section renders the 15 seeded entries plus "NTC Teaching License", and
adding a new one ("Custom Test Cert") through the existing Add flow
worked immediately. On the employee profile, picking two qualifications
in `HrDetailsSection`, saving, and reloading showed both persisted. On
the public form, an anon session (no login at all) saw the same seeded
list, picked one, and submitted; the Manager's pre-approval review card
(from the priority fix two days ago) showed it correctly as joined text
before Approve was ever clicked. Cross-checked directly against the
database: both `employees.qualifications` and the submission's own
`qualifications` column stored as real Postgres arrays
(`{"Bachelor's Degree","Custom Test Cert"}`), not JSON strings or
comma-joined text. `tsc`, `eslint`, `vite build`, and
`check-duplicate-function-overloads.sh` all clean at the existing
baseline.
