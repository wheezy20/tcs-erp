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
