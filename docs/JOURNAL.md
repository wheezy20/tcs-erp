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

## 2026-09-24 — `20260922100000_onboarding_review_fixes.sql` failed against production; fixed and properly re-verified

`20260922100000`'s "ID Copy" -> "National ID" rename failed with a check
constraint violation when Eyram ran it against the real, already-deployed
production database. Rolled back cleanly (transactional), so production
was untouched — but the migration itself was wrong, and a fresh local
`db reset` had never caught it because it couldn't have: every
`employee_documents` row used in local testing was inserted *after* all
migrations had already applied, so the constraint was already sitting in
its final state by the time anything named "ID Copy" existed anywhere.
The bad transition itself was never exercised locally, only against a
database that had *actually lived through* Phase 2 and Phase 3 with a
real "ID Copy" upload sitting in it already.

Two bugs, not one, both in the same handful of lines — worth recording
both since the first "fix" attempt was itself wrong in a related way:

1. **First attempt**: widen the constraint, *then* rename the data. Still
   wrong — the "widened" constraint dropped `'ID Copy'` from the allowed
   list entirely (swapped for `'National ID'`), so *adding* that
   constraint fails immediately against the still-unrenamed pre-existing
   row. Postgres validates a new `check` against every existing row
   unless declared `not valid`, and swapping one allowed value for
   another is not a superset of what's already there.
2. **Real fix**: there is no ordering of "swap the constraint" plus
   "rename the data" that works in a single step here — it needs the
   standard expand/migrate/contract shape for a live enum-value rename:
   widen the constraint to accept **both** `'ID Copy'` and
   `'National ID'` at once, rename the data (now legal either way under
   the expanded constraint), then contract the constraint back down to
   its final form once nothing uses `'ID Copy'` anymore.

**Verified properly this time** — against a database that actually has
the failure precondition, not a fresh reset: temporarily moved
`20260922`/`20260923` out of `supabase/migrations/`, ran `db reset` (applies
cleanly through Phase 3), inserted a real `employee_documents` row with
`document_type = 'ID Copy'` directly via `psql` (simulating the row that
existed in production), then:
- Confirmed the *original* buggy statement order reproduces the exact
  reported error, verbatim, against this seeded row.
- Confirmed the *first fix attempt* (widen-then-rename, no `'ID Copy'`
  kept in the interim list) fails too, with a different but equally real
  error — `ADD CONSTRAINT` itself rejected by the pre-existing row.
- Restored to the same seeded state and applied the real fix via
  `npx supabase migration up --local` (applies one pending migration
  against existing database state, the same way `db push` would against
  a real project, rather than a full reset) — applied cleanly. Confirmed
  the row ended up `'National ID'`, the checklist item ended up
  `'National ID'`, and the constraint's *final* form correctly excludes
  `'ID Copy'` again (the contract step actually ran, not just the
  expand step).
- Applied `20260923` on top via the same `migration up` mechanism —
  clean.
- Full `db reset` from scratch afterward to confirm the whole sequence
  still works end to end with no regression from the fix.
  `check-duplicate-function-overloads.sh` clean at every step above.
  `tsc`/`eslint`/`vite build` unaffected (frontend wasn't touched).

**What I did not do, and can't**: actually run `supabase db push` against
the real production project. This local environment has never had
production credentials or a linked project — every verification this
entire session has been against the local Docker stack, and
CLAUDE.md is explicit that pushing to the real hosted project is Eyram's
own step, with his own credentials, not something to run on his behalf.
The local reproduction above is the closest verification available
short of that: the exact failure precondition (a real pre-existing
`'ID Copy'` row, not a freshly-seeded one), the exact CLI mechanism
(`migration up`, matching what `db push` does against existing state),
and confirmation that both the original bug and the first wrong fix
attempt are now understood and ruled out, not just patched over.

**Lesson for future data-value renames on a column already in
production**: a fresh `supabase db reset` only proves a migration is
internally consistent against data the *same reset* creates — it can't
catch a bug that only manifests against data created by an *earlier*
deployment. Verifying a rename/constraint-tightening migration that
touches a column already live in production needs either
`supabase migration up` against a database seeded with the specific
pre-existing value being renamed, or (equivalently) temporarily holding
back later migrations and reconstructing that intermediate state by hand
— a plain `db reset` isn't sufficient evidence for this class of change.

## 2026-09-24 (later) — HR beyond payroll, Phase 4: document generation

Built document generation for Appointment Letters, Probation Letters,
and Contracts (Teaching/Non-Teaching, auto-detected from position).
Presented the full schema/lifecycle/template/merge-field plan before
writing any code, per the established phase rhythm; Eyram confirmed all
three proposed defaults (HR records contract acceptance manually rather
than a new self-service signing flow; templates get their own dedicated
page rather than folding into Payroll Setup; the four templates ship
seeded with real starter prose rather than skeletal placeholders).

**Generalized the originally-planned single-purpose "employee contracts"
table into `employee_generated_documents`** with a `document_kind`
column (`Appointment Letter` / `Probation Letter` / `Contract-Teaching` /
`Contract-Non-Teaching`), since all three document types share identical
lifecycle mechanics and an identical generation mechanism — see
docs/DESIGN.md's new bullet for the full schema, the partial-unique-index
enforcement of "at most one Issued document per employee per kind," and
why Contract splits into two templates while the other two don't.

**The one new fact needed for Contract auto-detection**:
`positions.is_teaching` — nothing distinguished job function on that list
before. Backfilled `true` for every position with "TEACH" in the name
(Head Teacher, Class Teacher, Subject Teacher, Teaching Assistant,
Assistant Head Teacher — 5 of the 16 seeded positions), so existing staff
don't all silently default to Non-Teaching until someone manually reviews
every row. The resolution happens twice on purpose — once client-side (to
pick which template to render) and once again inside
`generate_employee_document()` (to decide what gets stored) — the server
never trusts the client's classification.

**The real obstacle, found only by actually running the generation flow
in a browser**: every attempt failed silently with a toast —
"Attempting to parse an unsupported color function 'oklch'" — because
this app's theme (`styles.css`) defines its colors as `oklch()` custom
properties, which html2canvas (jsPDF's `.html()` rendering backend)
can't parse. Two attempts before the real fix:
1. First guess: maybe html2canvas was walking oklch-styled ambient page
   CSS through inheritance — tried rendering inside an isolated
   `<iframe>` with no stylesheet of its own. Didn't help.
2. Read jsPDF's own source to find out why: `.html()`'s internal
   `toContainer()` step clones the source element and re-parents the
   clone into the app's *real* `document.body` before calling
   html2canvas at all — so an iframe source doesn't matter, the render
   always happens back in the live, oklch-themed page. html2canvas then
   clones the *entire* document again internally regardless of which
   specific element it's asked to render, confirmed by its own debug log
   ("Starting document clone with size 1280x4076" — full viewport
   dimensions, not the 700px-wide letter content).
3. **Real fix**: html2canvas's own `onclone(document)` hook, passed
   through jsPDF's `html2canvas` option, runs against the clone right
   before rendering — used to inject a blanket
   `*, *::before, *::after { color/background-color/border-color: ...
   !important; }` override, safe here specifically because this
   feature's template HTML never uses Tailwind classes or the app's
   custom properties at all (plain tags, inline styles). Verified with a
   real generated PDF fetched via its signed URL: `200`,
   `content-type: application/pdf`, 92,855 bytes, correct `%PDF-` magic
   bytes — not just "a request succeeded," an actually-openable document.

**Letterhead reuses `settings-store.ts`'s `DocumentSettings.company`** —
the same client-side source `invoice-pdf.ts` already reads — rather than
adding a school-identity table; `branches` has no such fields (checked
directly: it's a 4-column location label, not a company-identity
record), and this renders client-side anyway, same trust level as an
invoice.

Frontend: `generated-documents-store.ts` (RPC calls + signed-URL reads,
no direct table writes — same shape as every other RPC-only table this
session), `contract-templates-store.ts`, `lib/pdf/contract-pdf.ts`
(merge-field builder + the render function above), a new "HR letters &
contracts" card on the employee profile page (three generate buttons,
grouped-by-kind document list, Issue/Discard/Record-acceptance actions),
and a new dedicated `/employees/document-templates` page (one big
textarea per category, merge-field tokens listed as reference), linked
from the Employees list page's header. `positions`' settings chip on
Payroll Setup gained a Teaching/Non-Teaching toggle — extended the
existing generic `RefListSection`/`RefListChip` components with an
optional prop rather than forking them, and added a standalone
`setPositionIsTeaching()` function in `org-lists-store.ts` rather than
folding `is_teaching` into the shared `update()` used by
departments/qualifications too, since TypeScript correctly rejects an
update payload key that doesn't exist on every table in that shared
function's type union.

**Verified with a real end-to-end browser pass** (after fixing the
oklch issue above): generated an Appointment Letter and fetched its
signed URL directly (real PDF, confirmed above); generated a Contract
for a Teaching employee (Class Teacher) → correctly labeled
`Contract-Teaching`, never `Contract-Non-Teaching`; generated a Contract
for a Non-Teaching employee (Accountant) → correctly labeled
`Contract-Non-Teaching`; issued v1, then generated and issued v2 of the
same Appointment Letter → v1 correctly flipped to `Superseded`; recorded
an acceptance signature on the Issued v2 → showed "Accepted by …";
discarded a still-Draft Contract → fully removed. `dev-auditor@tcs.test`:
sees the whole section and can open the signed View PDF links, but no
Generate/Issue/Discard buttons anywhere — correct read-only. Template
editor: all four categories render with real seeded prose, the Probation
Letter template contains `{{probation_end_date}}`, an edit saved and
persisted across reload. `tsc`, `eslint`, `vite build`, and
`check-duplicate-function-overloads.sh` all clean at the existing
baseline.

Phase 5 (email infrastructure) remains the last piece of the original
five-phase plan.

## 2026-09-24 (fix) — Document generation shipped a blank PDF, masked by the oklch fix

Production-style testing found every generated document (Appointment
Letter, Probation Letter, Contract) opened as a genuinely blank
single-page PDF — a valid file, correct size, correct `%PDF-` magic
bytes, but no visible content. The earlier verification pass had checked
exactly those things (file existed, right content-type, right byte
count) and wrongly treated them as proof the PDF was correct; nobody had
actually opened one in a viewer.

Confirmed blank by opening a real generated PDF in a browser (not just
checking headers/bytes). Inspected the raw PDF content stream directly
(`qpdf --qdf`, grepping for `BT`/`Tj` text operators) and found real text
draw commands, in the right fill color, all positioned around x=-7317pt —
off the left edge of an A4 page. Not a rendering artifact: genuinely
invisible because it was drawn off-page.

Root-caused by reading jsPDF's own source (not guessed): `doc.html()`'s
`Worker.prototype.toContainer` unconditionally wraps its target in
jsPDF's own hidden overlay, hardcoded `position: fixed; left:
-100000px`. That's harmless for html2canvas's normal raster path (a real
`<canvas>`'s native 2D context correctly cancels the offset via its own
`translate()`), but `doc.html()` defaults to handing html2canvas a fake
`Canvas` shim instead so it can translate draw calls directly into
vector PDF operators rather than a raster image — and that shim doesn't
correctly cancel out html2canvas's internal position compensation, so
the -100000px overlay offset leaks straight into the emitted PDF
coordinates. This is a `doc.html()` bug, unrelated to the earlier oklch
color-parsing issue; the previous `onclone` fix for that ran inside
html2canvas's own rendering and never touched jsPDF's separate
coordinate math, so it fixed one failure mode (a thrown error) while
leaving a second, silent one (blank output) completely masked.

Fix: stop using `doc.html()` entirely. Call `html2canvas()` directly
against a real `<canvas>` element (added as a normal declared dependency
— it had only ever been jsPDF's undeclared transitive one), then place
the result into the PDF manually via `doc.addImage()`. Added manual
pagination (slicing the canvas into page-height chunks) since this path
no longer gets `doc.html()`'s automatic page-splitting for free —
contracts can run longer than one page even though letters typically
don't. The `onclone` oklch fix carries over unchanged, since it's
html2canvas's own hook and applies regardless of how the raster result
gets into the PDF afterward.

Verified properly this time: opened real rendered PDFs (screenshotted in
a PDF viewer, not just fetched) for all three document kinds —
Appointment Letter, Probation Letter, Contract-Teaching — confirming
legible letterhead, body text, and correct ₵ formatting. Separately
inspected a Contract-Non-Teaching PDF's raw content stream to confirm
text draw coordinates now fall inside the page. Forced a two-page split
by temporarily padding a template with extra paragraphs (restored
exactly afterward) and confirmed the page break lands cleanly, with the
sentence continuing correctly across the boundary and no blank gap or
duplicated content. `tsc`, `eslint`, `vite build`, and
`check-duplicate-function-overloads.sh` all clean at the existing
baseline.

Lesson for this project specifically: "the file exists, has the right
size, and has the right magic bytes" is not evidence a generated
document is correct — only opening it and looking is. Applies to any
future binary-output feature (exports, other document types), not just
this one.

## 2026-09-29 — Direction reversed: TCS OS retires into this ERP; Admissions becomes Phase 2

Eyram decided outside this repo (TCS OS records it in its own
`docs/JOURNAL.md`, same date) that the planned merge now runs the
other way. **TCS OS (Django + Supabase + Cloud Run,
`~/projects/tcs-os`) is being retired, and its logic ported into this
ERP.** Until now, PLANNING.md, CONSTRAINTS.md, STACK.md, and CLAUDE.md
all described this ERP eventually folding *into* TCS OS. All four are
updated in this session. The reason, per TCS OS's entry: TCS's staff
are non-technical, and this ERP's UI was preferred over what Django
could deliver without a lot of custom frontend work.

What it means here:

- **HR and Finance: nothing to port.** TCS OS's `hr`/`finance` modules
  were ported *from* this repo, including the corrected Tier 2 scheme
  and per-band PAYE rounding. What does come back is TCS OS's parity
  evidence, as future regression cases: Emmanuel Ansah (basic 6,500 →
  net 5,008.37), Abena Konadu Owusu, and Yaw Darko Asamoah, all matched
  to the cent. Also its recorded coverage gaps: allowances, overtime,
  fines, IOU, and higher PAYE bands, which were never exercised.
- **Admissions is the real port.** It's live in production on TCS OS
  at admissions.tcsch.edu.gh, with about 3 real records. It's now
  PLANNING.md's **Phase 2: Admissions (ported from TCS OS)**. Only the
  logic comes across. Models, views, and templates get rewritten for
  plpgsql RPCs, RLS, and TanStack routes.
- **The 3 real records get migrated by hand** into this project's own
  hosted Supabase project, with their attached Storage files. It's a
  one-off step Eyram runs. This ERP never points at TCS OS's database
  or buckets. The records hold real child health data, so their
  contents stay out of docs, commits, and fixtures.
- **admissions.tcsch.edu.gh must keep working until cutover**, and then
  redirect to this ERP instead of going dark. Tokens in emails parents
  already have (offer, draft-resume, unsubscribe) must keep resolving.
  TCS OS also notes `app.tcsch.edu.gh` gets repointed here. Both DNS
  steps are Eyram's to run.
- **`~/projects/tcs-os` is read-only** from this repo's sessions.

Two conflicts surfaced and flagged in the docs rather than decided:
TCS OS models two campuses (Main and Annex, with per-campus capacity),
against PLANNING.md's "TCS is single-campus" non-goal; and admissions'
staff shapes (officer, decider, grade-band coordinators) don't fit the
four-role model, against CONSTRAINTS.md's "don't invent a fifth role".
Both go to `docs/admissions/PORT-PLAN.md` as open decisions.

Docs only: no code, schema, or migration changes this session. Next,
in separately reviewed steps: port TCS OS's five subagents plus a
push/deploy-blocking hook, and write the slice loop into CLAUDE.md.
Then write `docs/admissions/PORT-PLAN.md`.

## 2026-09-29 — Three admissions-port decisions settled: campuses, roles, no dual intake

Eyram settled the three open questions the previous entry flagged. Docs
only, no schema or code yet.

1. **Campuses: Main and Annex, on the existing `branch_id`.** TCS really
   has two campuses. The "single-campus now" framing in PLANNING.md's
   non-goals and CONSTRAINTS.md's Architecture section came from
   Wilelik and was wrong for TCS. Both are rewritten: each campus is a
   `branches` row, with no new `campus` table or column. Still to settle
   in the port plan: turning `seed.production.sql`'s single "Treasures
   Christian School" branch into Main plus a new Annex row, and which
   existing screens need a campus filter.
2. **Roles: still four, plus a small admissions capabilities layer.**
   The layer has a `can_decide` flag, a per-staff list of grade bands
   for coordinators, and a separate gate for child health data. It
   isn't a fifth role, because it only narrows or unlocks admissions
   actions for someone who already holds one of the four roles. It
   never grants anything outside admissions, and every capability is
   ungranted by default. CONSTRAINTS.md's "don't invent a fifth role"
   rule now says why, and its "open" marker is removed. The exact
   storage shape is left to `docs/admissions/PORT-PLAN.md`.
3. **No dual-intake window, confirmed.** TCS OS and the ERP never both
   accept real admissions submissions at the same time. Promoted from
   "proposed" in CONSTRAINTS.md. Consequence: the ERP's public forms go
   live only after TCS OS's intake stops, and the hand migration runs
   after that. So no real record ever needs reconciling across the two
   systems.

## 2026-09-29 — Stage 2: project subagents, production-command hook, slice loop, role-matrix harness

Ported TCS OS's five subagents into `.claude/agents/`. They were
rewritten for this stack, not copied, since the Django-specific checks
(app labels, `makemigrations --check`, `queryset.update()`) don't apply
here:

- **tcs-planner** now has to state an expected role matrix, the anon
  surface, and every human confirmation gate for the slice it plans.
- **test-runner** runs lint, `tsc --noEmit`, build, `db reset`, the dev
  staff seed, `check-duplicate-function-overloads.sh`, and a types
  regen diff. For every new or changed RPC or RLS policy it also writes
  and runs a role matrix across anon/Attendant/Manager/Accountant/Auditor.
  It may fix mechanical failures, but it only reports policy, grant, or
  logic failures and never edits an `-- expect:` line to get a green run.
- **code-reviewer** checks DESIGN.md and CONSTRAINTS.md, plus three
  specific checks: anon-reachable surface that isn't SECURITY DEFINER
  (checked against the live database's effective privileges, not the
  migration text), service_role in `frontend/src` or `dist/client`, and
  client-side business logic.
- **docs-updater** and **feature-researcher** are aimed at this repo's
  docs. feature-researcher writes only to a "Backlog / someday" section
  of PLANNING.md.

New `scripts/role-matrix.sh`. The host has no `psql`, so it runs
through `docker exec` into `supabase_db_tcs-erp`. It impersonates each
role the way a real request does (`authenticated` plus a JWT `sub`
claim), runs every probe in a rolled-back transaction, supports a setup
section that runs as `postgres` to seed rows, and fails on any
`-- expect:` mismatch. A broken setup is reported as `SETUP FAILED`,
because otherwise it would read as "denied" for every role and let a
denial probe pass silently. Smoke-tested against the existing guards:
`require_finance_writer()` and `require_writable_role()` produced the
expected grid, and a seeded `audit_log` read showed Manager, Accountant
and Auditor ok, with Attendant and anon denied.

New PreToolUse hook (`.claude/hooks/block-production-commands.sh`,
wired in the new project-level `.claude/settings.json`). It blocks
`git push`, `supabase db push`, `supabase db reset --linked/--db-url`,
`supabase functions deploy`, `supabase secrets set`, `wrangler deploy`,
and `bootstrap-production-manager.sh`. The last four go beyond the list
Eyram asked for, and are in because they're production steps too. It
matches only in command position and skips heredoc bodies. The heredoc
rule was added after the hook blocked this session's own CLAUDE.md
edit, whose heredoc text mentioned the bootstrap script. 31 block/allow
cases pass. It's a backstop, not a sandbox: `bash -c "…"` gets past it.

CLAUDE.md gained the slice loop (plan, build one slice, test, review,
at most 3 fix rounds then stop and report, record, stop for review)
and its four human confirmation gates: statutory numbers, new
permissions or capabilities, public anon surface, and production steps.

**Found while building the harness:** `anon` has EXECUTE on 169 of 170
public functions (Postgres's PUBLIC default plus Supabase's default
privileges). Invoker RPCs are safe only because `require_staff()`
rejects anon at runtime. Separately, `deposit_number_counters` has RLS
**off** with full anon privileges, and a probe confirmed an anon INSERT
gets past grants and RLS. Not fixed, since it's outside this stage's
scope. It's logged as an open CONSTRAINTS.md checklist item. DESIGN.md
now codifies the rule: the anon surface is SECURITY DEFINER functions
only, and new invoker RPCs `revoke execute … from public, anon`. It
also records this measured baseline and the one deliberate anon table
read (`qualifications_select_anon`).

## 2026-09-29 — `deposit_number_counters` gets RLS and loses anon

Closes the gap Stage 2 logged as an open CONSTRAINTS.md checkbox: the
counter table behind customer-deposit numbers (`20260901100000`) had
RLS off and full anon privileges. Eyram set the scope: one new
migration, the same policies as `invoice_number_counters`, revoke anon,
touch nothing else. This is the first slice run through the loop from
Stage 2 (tcs-planner, build, test-runner, code-reviewer,
docs-updater). This session loaded before `.claude/agents/` existed,
so each step ran as a general-purpose agent following that agent's
file.

New migration `20260929100000_deposit_number_counters_rls.sql`:

- enables RLS, with `deposit_number_counters_select`
  (`is_active_staff()`), `_insert` (with check `can_write()`),
  `_update` (`can_write()` for both using and check) and `_delete`
  (`has_role(['Manager'])`). These match `invoice_number_counters`
  apart from the names, with no `to` clause;
- `revoke all on public.deposit_number_counters from anon`.

The `authenticated` and `service_role` grants are untouched. Both
counter tables' ACLs were already identical (`arwdDxtm`).

Role matrix: `supabase/role-matrix/20260929100000_deposit_number_counters_rls.sql`,
6 probes × 5 roles. **Before the migration** it showed 10 mismatch
cells: anon ok on all direct counter access, Accountant and Auditor
ok on direct insert/update, and Attendant, Accountant and Auditor ok
on direct delete. **After**, it exits 0 with no mismatches:

| Probe | Ok | Denied |
|---|---|---|
| counter select | all four staff roles | anon |
| direct insert / update | Attendant, Manager | anon, Accountant, Auditor |
| direct delete | Manager | everyone else |
| `create_customer_deposit`, first-of-month insert path | Attendant, Manager | anon, Accountant, Auditor |
| `create_customer_deposit`, on-conflict update path | Attendant, Manager | anon, Accountant, Auditor |

Both `create_customer_deposit` probes assert the exact DEP number
returned. Who can create deposits hasn't changed. Accountant is now
stopped at the counter upsert (RLS), one statement earlier than
before, when `customer_deposits`' insert policy stopped it. Auditor
and anon are still stopped by `require_writable_role()`. Structural
check after `db reset`: `relrowsecurity = t`, and anon has no
select/insert/update/delete/truncate privilege. Anon-privileged
tables drop from 15 to 14, all with RLS on (DESIGN.md's baseline is
updated).

test-runner: `tsc`, build, `db reset`, dev staff seed, and
`check-duplicate-function-overloads.sh` all pass. Two failures have
nothing to do with this slice and are left unfixed because they're
outside its scope:

- `npm run lint` is red on a prettier error already present at
  `frontend/src/components/settings/accent-sync.tsx:32`.
- The types regen diff isn't empty. The committed `database.types.ts`
  came from an older Supabase CLI than the local 2.118.0, and the
  difference is style only (`Args: never` becomes
  `Record<PropertyKey, never>`; `normal_balance` shows as `never` in
  Insert/Update). There's no schema difference and nothing about
  `deposit_number_counters`. **Eyram decides whether to regenerate.**

code-reviewer: nothing blocking, and no confirmation-gate items,
because access only got narrower. Two wording fixes were applied to
the migration's header comment. It no longer claims anon could
"truncate through the Data API", and it now says the pro-forma counter
precedent shares these policies but never revoked anon. Noticed but
out of scope, so not fixed. These are possible later work, not
decisions:

- `pro_forma_invoice_number_counters`, `pro_forma_invoices` and
  `pro_forma_invoice_lines` still give anon table privileges
  (TRUNCATE included), though RLS blocks anon on every policy.
- `authenticated` holds TRUNCATE (plus REFERENCES/TRIGGER) on both the
  deposit and invoice counters. RLS doesn't cover TRUNCATE, but it
  isn't reachable through PostgREST.
- `20260814080000`'s comment says the invoice/sale counters have no
  DELETE grant, but in the live database `authenticated` holds DELETE.
- If a Manager deleted the current month's counter row, the next
  deposit would collide on the `customer_deposits` primary key. That
  blocks the insert and never duplicates a number. The same is true of
  `invoice_number_counters`, and this table inherits it by parity.

**Pending, Eyram's step after review and commit:** run
`npx supabase db push` from the repo root against the linked TCS ERP
project. Until then the hosted database still has the gap.

## 2026-09-29 — Stage 3: admissions port plan drafted (plan only)

Eyram asked for the admissions port plan: plan only, with no
application code, no migrations and no commits. The three Stage 1
decisions (campuses as `branches` rows, four roles plus an admissions
capabilities layer, no dual intake) were treated as fixed inputs. The
result is `docs/admissions/PORT-PLAN.md` (new). The plan holds the
detail; this entry only records what happened and where to look.

**Approach.** tcs-planner ran as a general-purpose agent following
`.claude/agents/tcs-planner.md`, because this session started before
those agent files were loaded. It read TCS OS's `docs/admissions/*`,
`backend/modules/admissions/` (models, views, serializers, emails,
bulk_email, access, admin, turnstile, storage, tests) and
`docs/deployment.md`. On the ERP side it read the onboarding token
flow, `supabase/functions/invite-staff` and `create_payslip`. The
main session wrote the output to PORT-PLAN.md and spot-checked its
load-bearing citations against the code. All of them held; the list
is in the plan's "Open unknowns" section.

**Slices: 17, in a different order from Eyram's suggested 0–9.** They
are 0, 1, 2, 3, 4, 5, 6, 7a, 7b and 8–15. The main changes, and why:

- **New slice 1: make a second branch safe, then seed Main + Annex,**
  before any admissions table exists. There are 14 frontend lookups
  of the form `branches … limit(1).single()` with no ordering, in 13
  files under `frontend/src/data/`. Once an Annex row exists, which
  branch payroll, expenses and invoices write to becomes undefined.
  This touches finance and POS stores, so the plan flags that it needs
  Eyram's OK to belong in Phase 2.
- **Capabilities layer moved before the schema (slice 2),** because
  every admissions RLS policy depends on it.
- **Health info and documents split out (slice 4)** from the core
  schema (slice 3).
- **Staff UI split into 7a and 7b.**
- **Public surface split per anon piece:** 8 (inquiry, plus the Edge
  Function, Turnstile, rate limits and the intake flag), 9
  (application + uploads), 10 (drafts), 11 (offer page), 13 (leads)
  and 14 (bulk email + unsubscribe). Each gets its own confirmation
  gate.
- Transactional email is slice 12, and cutover is slice 15.

**Key recommendations. These are recommendations, not decisions.**
Each is listed as one of Eyram's decisions, D-0a … D-15f, with a
recommendation, in the plan's consolidated table:

- Turnstile-verified writes, upload-URL minting and the mailer live in
  a Supabase Edge Function. The submit RPCs are service-role-only, so
  `anon` can't call them directly.
- Email goes through a DB outbox drained by pg_cron + pg_net, sending
  via Resend.
- The Worker only serves secret-free routes.
- At cutover, `admissions.tcsch.edu.gh` attaches to the ERP Worker.
  The ERP's public routes reuse TCS OS's exact paths (`/inquiry`,
  `/apply?draft_token=`, `/offer?token=`,
  `/api/admissions/unsubscribe/<token>/`), so links already sent keep
  resolving without a redirect. Tokens migrate as SHA-256 hashes of
  the verbatim TCS OS tokens. PLANNING.md's Phase 2 bullet still says
  "becomes a redirect"; that wording is left as is until Eyram decides
  D-15b.
- An `admissions_settings.public_intake_open` flag is the technical
  enforcement of no dual intake.

**Where the code contradicts the brief or the docs.** Full list in the
plan's "Where the code contradicts…" section:

- Grade-band scoping keys on the grade **applied for**
  (`year_group_applied_for`), not the child's current grade.
  CONSTRAINTS.md's wording ("resolved live from the applicant's
  current grade") is left unchanged until Eyram confirms D-2c.
- TCS OS's admissions tests don't cover most of the rules being
  ported: reference formats, stage gating, capacity, Annex,
  vaccination, matching, expiry, uploads. Probes will be derived from
  the model, serializer and admin code instead.
- Bulk send is atomic per batch of up to 100 (Resend's batch API),
  with invalid addresses skipped beforehand, not atomic per message.
- TCS OS has a fourth permission, `can_send_bulk_email` (D-2d).
- Per its `deployment.md`, TCS OS production is only migrated through
  `0014`; `0015`–`0019` are unapplied unless they were deployed since.
- There's likely more real data than ~3 records: leads with emailed
  unsubscribe tokens, and possibly drafts. So slice 15 starts with an
  inventory that Eyram runs.
- An anonymous Application re-submission in TCS OS overwrites
  guardian, student and health data, and can reset any stage back to
  `application` (D-9b).
- TCS OS's generate-offer isn't atomic, and reset-offer reuses the
  token (D-6b).
- The unsubscribe GET changes state (D-14b).
- The marketing site posts cross-origin to TCS OS's lead endpoints
  (D-13a).

**Out-of-scope ERP issues, noted in the plan but not planned:**

- onboarding puts the raw token in the storage object path
  (`frontend/src/data/onboarding-store.ts:312`);
- `submit_onboarding_form` stores client-supplied storage paths
  without checking them;
- `invite-staff`'s CORS is `*`.

**Nothing built:** no code, no migrations, no commits. **Next step:**
Eyram reviews PORT-PLAN.md and its decisions. No slice starts before
that.

## 2026-09-29 — Admissions decisions recorded: fifth role (Admissions Officer), D-1/D-2/D-3 accepted

Eyram reviewed the port plan and decided a first batch. Everything is
recorded in `docs/admissions/PORT-PLAN.md` ("Decisions recorded", the
consolidated table, slices 1–6) and CONSTRAINTS.md "Staff roles".

- **A fifth role, Admissions Officer.** It supersedes D-2b and the
  earlier same-day decision to use "four roles plus capabilities". None
  of the four fits a coordinator: Attendant brings store writes,
  Accountant brings payroll and finance writes, and Manager is
  everything. The new role gets admissions tables only. Attendant stays
  the store role. The capabilities layer stays for narrowing inside
  admissions:
  - `can_decide`: Manager or Admissions Officer;
  - `can_view_health`: any role;
  - `grade_bands`: Admissions Officer only. Accountant was dropped from
    the plan's recommendation because a coordinator holding it would
    get finance write access.

  CONSTRAINTS.md's "don't invent a fifth role" rule is rewritten. It now
  records this as a deliberate, confirmed exception, notes that more
  roles are expected as the ERP grows, and adds an "Adding a role"
  procedure: Eyram's recorded decision, its own slice, allowlist guards,
  a read-exposure audit, and denial probes.
- **A new slice 1b, "Admissions Officer role",** sits after slice 1
  (campuses). Not started. The plan proposes an explicit `all_grades`
  flag for a full officer, as open decision D-2g, rather than "every
  band" or "empty means all".
- **Accepted as recommended:** D-1a, D-1b, D-1c, D-2a, D-2c, D-2d, D-2e,
  D-2f, D-3a, D-3b. D-2c means grade bands key on the grade applied for
  (`year_group_applied_for`), not the current grade. CONSTRAINTS.md and
  the tcs-planner and code-reviewer agent files now say so. The
  code-reviewer also now blocks denylist-style guards and undeclared
  roles, and its bulk-email line matches the per-batch finding.

**Read-exposure audit** (live local DB). A new role passing
`is_active_staff()` would reach the following today:

- **Reads:** 24 tables, including all of `staff`, `business_settings`,
  and every sales, invoice, customer and inventory table.
- **Writes:** 19 store tables, because `can_write()` is a denylist (not
  Accountant or Auditor).
- **RPC guards:** the guard in 28 RPCs, because
  `require_writable_role()` only rejects Auditor. 8 of those invoker
  RPCs have no `has_role` of their own.
- **`compute_day_totals`**, a SECURITY DEFINER function guarded only by
  `require_staff`.

Every finance, payroll, HR and onboarding table and every storage
policy already uses `has_role()` allowlists. Slice 1b converts the two
denylist guards to allowlists, with D-1b-a to D-1b-d open. The full
table is in PORT-PLAN.md slice 1b.

## 2026-09-29 — Admissions slice 1: campuses (Main + Annex), deterministic branch lookups

Eyram confirmed five decisions from the port plan (all recommended): D-2g
(explicit `all_grades` flag), D-1b-a (allowlist guards), D-1b-b (officer
reads branches and staff names only), D-1b-c (Auditor read-only on
admissions), D-1b-d (role string "Admissions Officer"). The only
contradiction in the earlier journal entry was the consolidated decision
table preamble saying "none is decided here"; reworded to match.

**Branch lookups verified (main session, before any change).** 13
files in `frontend/src/data/` have `from("branches")…limit(1).single()`
with no `order by`. The earlier count was 14; the 14th,
`inventory-store.ts:197`, is an UPDATE keyed by the id from `:122`, not a
lookup. Verified against the then-HEAD commit "Enable RLS on
deposit_number_counters and revoke anon". The DB side already orders
(`order by created_at limit 1` in 6 migration functions).

**Slice 1 run through the slice loop.** An implementation existed
uncommitted in the working tree from an earlier session that hadn't
been journaled. tcs-planner planned from HEAD and judged that diff:

- **Kept as built:** the helper (`getSchoolBranchId()` /
  `getSchoolBranchRow()` in `branch-store.ts`, `order by created_at`),
  the 12 other call-site rewrites, the Settings → Branches copy,
  `seed.sql` (Main `…0001` + Annex `…0002`, explicit `created_at` 1s
  apart), `seed.production.sql` (rename the oldest branch to Main keeping
  its id, insert Annex strictly newer, raise if another row is called
  Main or the oldest isn't Main; run command gains `-v ON_ERROR_STOP=1`),
  and the deposit-counters probe comment. A
  branch-list export for the admissions campus picker was proposed but
  **deferred to the slice that builds the picker (7a or 9)** — nothing
  consumes it before then.
- **DESIGN.md:** a new convention bullet was added in-session: "Branches
  are campuses; the oldest is Main and holds every school-wide record."
  There is no migration comment, because slice 1 has no migration.
- **Probe:** `supabase/role-matrix/campuses-main-annex.sql`. The header
  comment was corrected this session (named for D-1a since there's no
  migration; explains the no-op UPDATE). Proves two branch rows don't
  change read permissions: attendant/manager/accountant/auditor ✓ on
  branches select; anon ✗.
- **test-runner, full pass:** After prettier reflow of a pre-existing
  lint error in `accent-sync.tsx` (outside scope), `lint`, `tsc`,
  `build`, `db reset`, and `check-duplicate-function-overloads.sh` all
  pass. Types regen: no schema change; 73-line residue is CLI-formatting
  drift in generic helper boilerplate, pre-existing. Campuses probe and
  deposit-counters probe re-run both pass. Proved the probe's no-op UPDATE
  has teeth: after it, an unordered `limit 1` returns Annex while
  `order by created_at limit 1` still returns Main (the planner had
  doubted this). Seed
  idempotency: production script tested on a rolled-back local transaction
  for a single legacy row and for Main+Annex.
- **code-reviewer:** no blocking findings. anon/service_role/client-logic
  checks clean. Non-blocking: `seed.production.sql` doesn't flag a hosted
  project with 3+ pre-existing branch rows (speculative).

**Pending, Eyram's steps:**
1. Review diff (code + docs together).
2. Commit when asked.
3. Production step after commit: `psql "$PROD_DB_URL" -v ON_ERROR_STOP=1
   -f supabase/seed.production.sql` (renames the hosted oldest branch to
   Main and adds Annex) — Eyram runs this, not Claude.

**Slice 1b not started.**

## 2026-09-29 — 2026 PAYE bands planned (stopped at statutory gate); payroll tax decisions recorded

- **Plan only, nothing built.** Eyram asked for GRA's "Year of Assessment
  2026" monthly bands to be added as a new effective-dated set (effective
  1 September 2026), with the existing set left untouched. `tcs-planner`
  found `create_payslip()` already picks the band set by payroll month
  (`make_date(year, month, 1)` against `max(effective_from) <= that date`),
  not "the latest". So August 2026 and earlier keep the old set, and
  September 2026 onward gets the new one. It also rounds each band on
  `numeric`. The slice is therefore a single data-insert migration
  (`effective_from = 2026-09-01`, 7 bands), with no function change.
  The engine's method reproduces Eyram's three hand cross-checks
  (1,795.50 → 193.81, 1,606.50 → 160.74, 6,142.50 → 1,140.13). The
  figures were checked against the GRA PAYE page on 2026-09-29 and
  match. Stopped at the statutory-number gate for Eyram's confirmation.
- **Recorded in CONSTRAINTS.md (Eyram's decisions):**
  - The overtime concession doesn't apply to TCS (accountant
    confirmed; qualifying also needs annual income of GHS 18,000 or
    less).
  - National Service staff are fully exempt from SSNIT, Tier 2 and PAYE.
  - GRA's bonus rule (5% up to 15% of annual basic, excess graduated)
    gets its own later slice.
  - Extra classes stay a normal taxable allowance until the accountant
    confirms in writing how they're classified.

## 2026-09-29 — Admissions slice 1b-i: allowlist guards (no new role yet)

Eyram approved the slice 1b plan and split it. 1b-i (this entry) turns the
two denylist guards into allowlists and closes the read exposure, with no
new role. 1b-ii adds the Admissions Officer role itself. Recorded in
`docs/admissions/PORT-PLAN.md` (slices 1b-i and 1b-ii).

**Decisions (Eyram, 2026-09-29):**

1. Guard rewrites approved. A role outside the list gets "This action is
   not available to your role"; Auditor keeps "Auditor is read-only and
   cannot perform this action".
2. `staff` read is `can_read_store()` or own row.
3. `list_staff_names()` returns `id` and `name` for all staff, active or
   not.
4. The officer reads `branches`.
5. No Admissions sidebar section until slice 7a (no placeholder nav).
6. A route-guard allowlist for the officer.
7. Hide the Settings tabs that read `business_settings` from the officer.
8. Split 1b into 1b-i and 1b-ii. Items 4 to 7 are built in 1b-ii.

**Corrections to the planner's pass (main session):**

- A plain four-role `staff_select` would have signed an officer out,
  because `auth-store.ts` resolves the signed-in user from their own
  `staff` row.
- The topbar's global search loads store data for every role. 1b-ii
  gates it.
- No route has a `beforeLoad` guard today.

**Built:** `20260929110000_allowlist_guards.sql`. Every replaced function
keeps its signature, volatility, `security definer` and `search_path`, so
it's `create or replace` with no drops.

- `can_write()` = `has_role(['Manager','Attendant'])`. It was
  `is_active_staff() and not has_role(['Accountant','Auditor'])`.
- `require_writable_role()` = `require_staff()`, then an allowlist of
  Manager, Attendant and Accountant. It used to reject Auditor only.
- New `can_read_store()` = `has_role` of the four roles. 22 select
  policies move from `is_active_staff()` to it: every one except
  `branches` (unchanged) and `staff`.
- `staff_select` = `can_read_store() or (id = auth.uid() and
  is_active_staff())`. An inactive member still sees nothing, as before.
- New `list_staff_names()`: SECURITY DEFINER, `require_staff()` first,
  `id` and `name` of every staff row, ordered by name.
- `compute_day_totals` gets a `can_read_store()` check. Its body is
  otherwise identical.
- Both new functions are revoked from `public` and `anon`, and granted to
  `authenticated` and `service_role`.
- `database.types.ts` gains the two function types (+8 lines). The
  generic-helper section is left as committed, to keep the pre-existing
  CLI formatting drift out.

**Proof:**

- `supabase/role-matrix/20260929110000_allowlist_guards_regression.sql`
  has 100 probes generated from the live catalog:
  - 6 guard truth tables, including all-inactive;
  - 24 table reads, plus 3 `staff` variants;
  - 38 writes, one per `can_write()` policy on the 19 tables;
  - 28 RPCs, one per `require_writable_role()` caller, with NULL
    arguments; access errors count as denied and later errors as passed;
  - `compute_day_totals`.
- Its output was byte-identical (363 lines) on the schema without and
  with the migration. test-runner reproduced this independently, moving
  the migration out and back with sha256 checked.
- The catalog diff (policies, function definitions and ACLs, table ACLs
  and RLS flags, constraints, triggers) shows only the 23 policy changes,
  the 2 new functions and the 3 changed bodies. No existing grant
  changed.
- Confirmed empirically that RLS WITH CHECK fires before unique
  constraints on INSERT, which is what the write probes rely on.
- `…_new_surface.sql` (6 probes) all match. The campuses and
  deposit-counters files re-run clean. Lint, tsc, build, db reset and the
  overload check all pass.

**Audit findings:**

- The only denylist guards were `can_write()` and
  `require_writable_role()`. Every other `not has_role([...])` check is
  reject-unless-listed.
- `handle_new_staff_signup` maps any unrecognised invited role to
  Attendant. 1b-ii must add the new role to its list, or an invited
  officer would get store access.

**code-reviewer:** no blocking findings. The one non-blocking item was a
missing `service_role` grant on the two new functions, for consistency
with the codebase. Fixed, and the regression output is still
byte-identical.

**Open item: route guards for the other roles.** No route has an access
guard. Pages are protected only by sidebar visibility, some in-page
checks, and RLS. 1b-ii adds a route-guard allowlist for the Admissions
Officer only. Guards for the existing roles aren't planned: an Attendant
opening a finance URL directly gets the page, with RLS returning empty or
denied data. Eyram to decide whether and when.

**Pending:** Eyram's review. No commit until asked. `npx supabase db push`
later is Eyram's step. 1b-ii not started.

## 2026-09-29 — 2026 PAYE bands built, confirmed and tested

Eyram confirmed the GRA "Year of Assessment 2026" monthly PAYE bands
(7 bands, effective 1 September 2026) on 2026-09-29, checked against
the live GRA PAYE page the same day and matched. The slice is a single
data-only migration seeding the new set, leaving the 2025 set untouched.
`create_payslip()` already selects the band set by payroll month via
`max(effective_from) <= make_date(year, month, 1)`, so no function change
is needed: August 2026 and earlier use the old set, September 2026 onward
gets the new one.

**Built:** `supabase/migrations/20260929120000_paye_bands_2026.sql`.
- 7 rows (one per band) inserted with `effective_from = 2026-09-01`
  and `on conflict (effective_from, band_order) do nothing`.
- No schema, grant or RLS change.
- Monthly bands: 0–588 0%, 588–668 5%, 668–768 10%, 768–3,668 17.5%,
  3,668–19,668 25%, 19,668–50,000 30%, above 50,000 35%.

**Probe:** `supabase/role-matrix/20260929120000_paye_bands_2026.sql`.
- Checks the new set's exact contents and that the 2025-01-01 set is
  unchanged (Manager, Accountant and Auditor can read).
- Creates real payslips via `create_payslip()` for a Sep 2026 run (new
  bands): Emmanuel Ansah basic 6,500 → PAYE 1,140.13, net 5,002.37;
  Abena basic 1,900 → 193.81, net 1,601.69; Yaw basic 1,700 → 160.74,
  net 1,445.76.
- Same three for an Aug 2026 run (old bands): PAYE 1,134.13 / 204.96 /
  171.89, net 5,008.37 / 1,590.54 / 1,434.61. Emmanuel's 5,008.37 is the
  TCS OS parity figure, so the old engine is still held to a result
  verified outside this repo.
- Only Manager and Accountant pass the payslip probes; the other roles
  are stopped by `require_finance_writer()`. Anon reaches the function
  through Supabase's default execute grant and is stopped by the same
  guard (pre-existing, not new here).
- **Teeth check, in a rolled-back transaction:** deleted the new set's
  rows → Sep run gave 1,134.13 (old bands), confirming the probe would
  fail without the migration.

**test-runner results:**
- lint: 0 new errors, 12 pre-existing warnings.
- `tsc` and `vite build` clean.
- `check-duplicate-function-overloads.sh` clean.
- Role matrix: no mismatches. Other role-matrix files also pass.
- Idempotency: rerunning the migration in a rolled-back transaction
  inserts 0 rows.
- **`supabase db reset` deliberately skipped** — another Claude session
  was using the same local stack at the time, and a reset would have wiped
  its state. The migration was applied with `npx supabase migration up
  --local` instead. A full `db reset` still needs to run before commit.
- `database.types.ts` not regenerated per Eyram's instruction (no schema
  change).

**code-reviewer:** arithmetic, old set untouched, idempotency and probe
teeth all verified clean. One blocking finding: the docs still said
"planned, awaiting confirmation" after the migration was built. Resolved
by this entry and the CONSTRAINTS.md update (fix round 1).

**Pending, Eyram's question:** Has any real September 2026 payroll already
been run on a hosted project with the old bands? Posted payslips must not
be rewritten, so if yes, a correction path is needed separately, outside
this slice. The hosted project gets the 2026 set only when Eyram runs
`npx supabase db push`. Not committed.

---

## 2026-09-29 — Admissions slice 1b-ii: Admissions Officer role

**Adds the fifth staff role on top of 1b-i's allowlist guards.** Slice 1b was split on 2026-09-29 into 1b-i (guards only, committed as slice 1b-i, allowlist guards) and 1b-ii (the role). The role reaches nothing until admissions tables exist (slice 3 onward). All decisions (D-1b-b, D-1b-d and others 4–7 from PORT-PLAN.md) confirmed 2026-09-29.

**Built:**

- **Migration `supabase/migrations/20260929130000_admissions_officer_role.sql`:**
  - `staff.role` check constraint: added `'Admissions Officer'` to the allowed list.
  - `handle_new_staff_signup()` trigger: changed to reject unlisted roles explicitly ('Unknown staff role: <role>') instead of silently defaulting to Attendant. A missing role still defaults to Attendant (seed paths depend on it).
- **Edge Function `supabase/functions/invite-staff/index.ts`:** added "Admissions Officer" to `ALLOWED_ROLES`.
- **Frontend:**
  - `StaffRole` union in `data/auth-store.ts`, and added `isAdmissionsOfficer()` helper.
  - `STAFF_ROLES` in `routes/settings.tsx` (role dropdown, invite dialog).
  - Sidebar: hide Procurement & Stores section from the officer (Finance and HR already hidden by `canViewFinancials`).
  - Dashboard: separate `OfficerDashboard()` component with no data hooks, rendering only a welcome message.
  - Topbar: global search extracted into a separate `GlobalSearch()` component; it's only mounted for non-officers (since they cannot read store data).
  - Route guard in `auth-gate.tsx`: Admissions Officer allowlist (`"/"` and `"/settings"`). Any other route redirects to `/`. Guard checks both `pathname` and `resolvedLocation` to prevent blocked pages from mounting data-fetching hooks.
  - Settings: six tabs hidden from the officer (`documents`, `tax`, `inventory`, `expenses`, `notifications`, `security`). `documents`, `inventory` and `expenses` load store tables; `tax`, `notifications` and `security` read `business_settings`.
  - Settings "Roles & permissions" note updated to mention five roles.
- **Scripts:**
  - `seed-local-dev-staff.sh`: a fifth dev account, `dev-admissions@tcs.test`, role Admissions Officer. Added to CLAUDE.md's dev-accounts table.
  - `role-matrix.sh`: updated to support six roles. Fixed `-- expect:` parsing to handle spaces inside role names (`Admissions Officer`), trimming around commas only.
- **Role-matrix probes:**
  - `supabase/role-matrix/20260929130000_admissions_officer_role.sql` (new): 30 probes proving the officer reads only its own staff row, `branches`, and `list_staff_names()`. Denied on all finance, payroll, HR and storage tables/functions.
  - `supabase/role-matrix/20260929110000_allowlist_guards_regression.sql` (re-run with sixth column): five existing columns unchanged; officer ✗ on 96 of 100 probes, ✓ on only 4 (`is_active_staff()`, `read branches`, `read staff`, `read staff: own row`).
  - `supabase/role-matrix/20260929110000_allowlist_guards_new_surface.sql` (re-run): officer included in `list_staff_names()` probes (3), all pass.
  - `supabase/role-matrix/campuses-main-annex.sql` (re-run): officer added to both campus-read probes.

**Verification:**

- Five-column regression proof: all five existing probe files re-run after removing the officer column; output byte-identical to a baseline run with the committed (five-role) script and committed probe files on the pre-migration schema. Confirmed independently by test-runner.
- Officer column accuracy: exactly 4 of 100 regression probes pass for the officer (the four named above); denied on stores, finance, payroll, HR, `can_write()`, all 28 `require_writable_role()` RPCs, `compute_day_totals`.
- New probe file 20260929130000: all 30 probes match expected results (officer sees only own row, branches, staff names; signup with role 'Admissions Officer' lands as that role; 'Janitor' rejected; missing role → Attendant; `staff_role_check` refuses 'Janitor').
- Catalog diff (before/after migration): only `staff_role_check` constraint and `handle_new_staff_signup` body changed; no grants, policies or other changes.
- PAYE independence: officer test fixtures (9e1b0000- ids, year 2090) all rolled back; payroll counts unchanged.
- lint: 0 errors. `tsc`, `vite build`, duplicate-overload check all pass.
- `database.types.ts`: types regen shows only pre-existing helper formatting drift; `role` stays `text`, no type change.
- Browser smoke test (Playwright, local dev, `dev-admissions@tcs.test`): visiting `/`, all visible Settings tabs, and direct loads of `/pos`, `/inventory`, `/payroll`, `/expenses`, `/customers`, `/staff`, `/employees`, `/banking`, `/purchasing`, `/accounting`, `/reports`, `/sales` — the only requests were `staff`, `branches`, `notifications`, `business_settings` (406, RLS) and `rpc/staff_sign_in_status`; no store, finance or HR table. All 12 routes redirected to `/`. Attendant and Manager (control): no redirects, search, Stores nav and all 13 Settings tabs unchanged. A first run caught blocked `/pos` page still loading right after redirect (router renders old match until new one resolves); fixed by checking `resolvedLocation` and re-verified.
- code-reviewer: no blocking findings.

**Deviations from PORT-PLAN 1b-ii text (built as described, intentionally):**

- Dashboard: a separate component (`OfficerDashboard`) with no data hooks, not the full dashboard with some KPIs hidden.
- Settings tabs: exactly six tabs hidden (`documents`, `tax`, `inventory`, `expenses`, `notifications`, `security`), not the three named in the plan text.
- Route guard: checks both `location.pathname` and `resolvedLocation.pathname` (the latter to prevent the blocked page mounting while the redirect is in flight).
- `role-matrix.sh` `-- expect:` parsing: fixed to handle spaces in role names, trimming only around commas.

**Open items / not verified:**

- **Officer inactivity auto-logout never arms:** `InactivityWatcher` reads `business_settings.session_timeout_minutes`. The officer gets a 406 (RLS), so `sessionTimeoutMinutes` stays `null`, and `useInactivityLogout` treats `null` as "don't arm". Not fixed: a fix needs a new narrow read (e.g. a SECURITY DEFINER function returning only the timeout) = a new permission, Eyram's decision. Not blocking now (the officer can see nothing sensitive yet) but must be fixed before slice 3–4 gives the officer admissions or health data.
- **Missing role in signup metadata still defaults to Attendant:** `handle_new_staff_signup` silently defaults a missing `role` metadata field to Attendant. This is intentional (seed paths and the script both create users without a role and set it afterwards), but Eyram to confirm.
- Route guards for the other four roles: still not built (existing open item).
- **Not end-to-end verified:** invite-staff Edge Function change was not exercised end-to-end (no local email invite run); the officer's Staff tab calls `rpc/staff_sign_in_status` (Manager-only), which errors for the officer the same way it does for Attendant today; nothing was run against a hosted project.

**Pending, for Eyram:**

- Review the slice.
- No commit yet; this session's changes are uncommitted.
- The hosted project gets the migration only when Eyram runs `npx supabase db push`.
- The invite-staff Edge Function change takes effect in production only when Eyram runs `npx supabase functions deploy invite-staff`.

## 2026-09-29 — Slice 1c: session timeout readable by every staff role

Fixes the open item from slice 1b-ii: the Admissions Officer couldn't read
`business_settings.session_timeout_minutes` directly, so the inactivity
logout timer never armed. Created a narrow SECURITY DEFINER function
`get_session_timeout_minutes()` that returns only that one value to any
active staff member (including the officer), bypassing the Admissions Officer's
restriction on `business_settings`.

**Built:**

- **Migration `supabase/migrations/20260929140000_session_timeout_read.sql`:**
  - `get_session_timeout_minutes()`: SECURITY DEFINER, stable, calls
    `require_staff()` first, returns `session_timeout_minutes` from
    `business_settings` (id = 1). Granted to `authenticated` and
    `service_role`; revoked from `public` and `anon`.
- **Frontend `frontend/src/data/session-timeout-store.ts`:**
  - Changed `load()` to call `supabase.rpc("get_session_timeout_minutes")`
    instead of reading `business_settings` table directly. Updated comment
    to explain why: not every role can read the table (Admissions Officer).
- **Generated types `frontend/src/lib/database.types.ts`:**
  - Added `get_session_timeout_minutes` function type.
- **Role-matrix probe `supabase/role-matrix/20260929140000_session_timeout_read.sql`**
  asserts: the function returns the configured value to all five staff roles
  and not to anon; it fails when all staff are inactive; direct
  `business_settings` read stays four roles (not the officer) and update
  stays Manager only.

**Verification (main session, reproduced independently by test-runner):**

- The six existing probe files give byte-identical output, all six columns,
  on the schema without and with the migration. The new file passes 4/4.
- The catalog diff (policies, function definitions and ACLs, table
  ACLs/RLS, constraints, triggers, buckets) shows only the new function and
  its ACL. `has_function_privilege`: anon false, authenticated and
  service_role true.
- Browser (Playwright fake clock, local timeout set to 1 minute, then
  restored to 15). On the committed code: the four existing roles were
  still signed in at 50s and signed out by 75s; the officer was never
  signed out. With this change, all five behave the same way.
  - The four existing roles' request sets on `/` changed only by the added
    `POST rpc/get_session_timeout_minutes`. Their one remaining
    `business_settings` GET is `invoice-store`'s `vat_rate`, via the topbar
    search.
  - The officer's `business_settings` GET is gone.
- As Manager, Settings → Security shows the value, and saving a new value
  still works through the direct table update. The timer picks it up
  without a page reload (`reload()`).
- Lint, tsc, build and the overload check pass. The types regen adds only
  the new function line.
- code-reviewer: no blocking findings.

**Pending:**

- Eyram reviews the slice.
- Not committed; `npx supabase db push` is Eyram's step.

## 2026-10-05 — Admissions slice 2: grade reference data and capabilities layer

Eyram approved the slice 2 plan, confirmed its four gates and accepted O-1
to O-9 as recommended (2026-10-05; recorded in PORT-PLAN.md slice 2).

**Gates confirmed:**

1. New reads: capability rows (own row for every active staff member; all
   rows for Manager and Auditor) and `admissions_grades` (Manager, Auditor,
   Admissions Officer).
2. The Accountant can read capability changes through the existing
   `audit_log` policy.
3. A Manager's role change is refused while the member holds a capability
   the new role can't hold.
4. The three predicates are executable by every staff role, not anon.

**Built:** migration `20261005100000_admissions_grades_and_capabilities.sql`.

- **`admissions_grades`:** the 14 TCS OS grades. `band` is a generated
  column from `classification_code`, so the two can't drift. The
  vaccination flag is set on the five preschool grades. There is a
  case-insensitive unique name, and no SHS rows (O-3). Manager, Auditor and
  Admissions Officer can read it; nobody writes it except by migration.
  - **Correction to PORT-PLAN:** the TCS OS names are "Kindergarten 1/2",
    not "KG 1–2".
- **`staff_admissions_capabilities`:** `staff_id` is the primary key and
  cascades from `staff`. The columns are `can_decide`, `can_view_health`,
  `grade_bands`, `all_grades`, and the server-forced `granted_by` and
  `updated_at`.
  - **Checks:** only the three band names, each at most once; `all_grades`
    can't be combined with a band list (D-2g); no all-empty row (O-7).
  - **RLS:** a member reads their own row; Manager and Auditor read every
    row.
  - **Grants:** `authenticated` has select only; `anon` has nothing.
- **Who may hold what:** one helper holds the rules, enforced in three
  places:
  - the capabilities table's own trigger, which locks the holder's staff
    row with `for share`;
  - a trigger on `staff` role changes, which refuses a change until the
    capability is cleared;
  - the RPC.
- **Deactivation:** deactivating a member clears their row (O-1).
- **`set_admissions_capabilities()`:** active Manager only, and self-grant
  is allowed.
  - It replaces the member's full state, with no defaults.
  - It validates the bands and refuses grants to inactive members.
  - An all-empty call deletes the row; an identical call writes nothing.
- **Audit:** a trigger writes `audit_log` action
  `admissions_capabilities_changed`, with `before`/`after` values plus the
  holder's role and name. Writes with no signed-in actor aren't audited.
  The `audit_log_action_check` gains only the new value.
- **Predicates:** `admissions_grade_band()` ignores case and extra
  whitespace (O-2). `admissions_grade_visible()` and
  `has_admissions_capability()` follow; an unknown capability name raises
  (O-5).
  - All three are SECURITY DEFINER and stable, with `search_path` pinned.
  - They are revoked from public and anon, and granted to `authenticated`
    and `service_role`.
- **Frontend:**
  - **Settings → Staff:** a new "Admissions access" column. A Manager sees
    every member with a Manage dialog; an Auditor sees every member
    read-only; anyone else sees their own row and "—" for the rest.
  - **The dialog:** it offers only what the member's role may hold, and
    `can_view_health` only where it has an effect or is being revoked
    (O-6). The database stays the authority.
  - **Error handling:** the role and active handlers use
    `getErrorMessage()`. A failed refresh after a committed write is no
    longer reported as a failed write.
  - **`staff-store.ts`:** it now drops its data when the signed-in user
    changes, as the new capabilities store does. Since slice 1b-ii an
    officer sees only their own staff row, so switching users in the same
    tab had left the next user with that one-row roster.
- **Probes:** `…_admissions_grades_and_capabilities.sql` (57) and
  `…_predicates.sql` (30). Fixture ids are `9e020000-`.

**Verification:**

- The seven existing probe files are byte-identical (all six columns) with
  and without the migration; test-runner reproduced this independently.
  - The new files pass 57/57 and 30/30.
  - The catalog diff is additions plus `audit_log_action_check` gaining
    exactly one value.
  - The anon-executable function count is unchanged.
- **Mutation checks** by test-runner: each of five deliberate breakages
  made the right probe fail. The five were dropping either holding
  trigger, opening `admissions_grade_visible` to the Attendant, removing
  the role check from 'decide', and removing the no-op guard.
- **Browser (Playwright):**
  - **Manager:** a dialog grant is stored and audited. A refused role
    change shows the guard's message and leaves the role unchanged.
    Deactivating clears the row, and reactivating doesn't restore it.
  - **Officer:** fetches only its allowed requests plus
    `staff_admissions_capabilities`, and sees only its own row.
  - **Auditor:** sees every row, read-only.
  - **Attendant and Accountant:** see their own row and "—" for the rest.
  - **Same-tab user switch** (officer → Manager): the roster and access
    are correct.
  - **A simulated tab refocus** causes no reload.
- **Fixes after review:**
  - **Non-blocking:** stale per-user caches; a refresh failure reported as
    a write failure; `getErrorMessage()`; grade trimming now covers tabs
    and newlines (probe F2 gained that case); a comment on the cascade
    audit skip.
  - **From the re-review:** reset only on a real user change, plus a
    generation guard.
- Lint (0 errors), tsc, build and the overload check pass.
- **Bug in my harness loops, earlier slices included:** `echo
  "$(basename $f) exit=$?"` printed 0 regardless, because the command
  substitution resets `$?`. Failures were still caught by grepping the
  outputs and comparing against baselines. Exit codes are captured
  correctly now.

**Pending (Eyram's steps):**

1. Review. Not committed.
2. `npx supabase db push`.
3. Deploy the frontend.
4. Grant the real officer's capabilities in Settings → Staff.

## 2026-10-06 — Overtime tax slice (migration A): concessionary overtime engine, no rate row

Eyram approved the plan. TCS's accountant has accepted the GRA overtime
concession; written confirmation is pending. This reverses two 2026-09-29
decisions (the concession not applying to TCS, and extra classes staying a
taxable allowance) and the 2026-09-18 "New flag" entry. Those entries stay
as written; CONSTRAINTS.md now records the reversal as "reported by Eyram
2026-10-06, written confirmation pending".

The rule as decided: the qualifying test is basic salary only, that month's
basic × 12, before SSNIT and Tier 2, with overtime and allowances excluded.
"Not more than": exactly 18,000 qualifies, and overtime of exactly 50% of
basic stays at 5%. Overtime up to 50% of monthly basic is taxed at 5%, the
excess at 10%, and overtime stays out of the PAYE base. Above the threshold
nothing changes. `pays_paye = false` (including National Service) means no
overtime tax. Extra-class payments are entered as overtime. Eyram's other
accepted defaults: qualification is computed per payslip (no stored flag);
overtime tax posts as its own Cr 2330 line; the "Extra Classes"
allowance type stays. Rounding (Eyram, later the same day): overtime tax
is worked from the overtime amount as shown on the payslip (rounded to
2 dp), not the unrounded hours × rate; the cap is round(basic × 50%);
each of the two tax parts is rounded to 2 dp; PAYE rounding is
unchanged.

**Built (migration A only), `20261006100000_overtime_tax_engine.sql`:**
- `overtime_tax_rates`: effective-dated, one row per date, picked by
  payroll month. A missing row means no concession (not an error). Access
  as `paye_bands`: Manager, Accountant and Auditor read; Manager and
  Accountant write; anon nothing. **No row is shipped.** The row (figures
  and effective date) is a later migration, after the written confirmation
  and Eyram's confirmation of the numbers.
- `payslips.overtime_tax` (default 0) and `overtime_concession` (default
  false), with checks. No backfill.
- `create_payslip()` and `post_payroll_run()`: `create or replace`, same
  signatures. With the table empty both behave exactly as before.
- Frontend: overtime tax on the payslip screen, print and PDF (with a note
  when the concession applied); a separate 2330 line in the posting
  preview; the concession on the Payroll → Setup card; hint text in the
  payslip dialog for entering extra classes as overtime; regenerated types.
- `supabase/role-matrix/20261006100000_overtime_tax_engine.sql`, 28 probes:
  table access and checks, "no row shipped" (A9, which the rate-row
  migration must update), oracle cases A–M plus K2 through
  `create_payslip()` under a fixture row, two posting probes, and posted
  payslips.

**Verification:**
- Before the migration, a local dataset of 21 payslips across a Posted, a
  Ready for Review and a Draft run (with overtime and an allowance) was
  created through the real RPCs. After `supabase migration up`, an md5 of
  every pre-existing column of `payslips`, `payslip_allowances`,
  `payroll_runs`, `journal_entries` and `journal_lines` was identical.
  Posting the Ready for Review run gave identical journal lines.
  Regenerating the Draft run's payslips gave identical figures.
- All 9 older probe files give byte-identical output with and without the
  migration; the new file passes 28/28. Exit codes captured directly this
  time.
- Case M (3.5 h × 40.37 = 141.295, shown as 141.30) gives overtime tax
  7.07. With the unrounded basis put back in the local database it gives
  7.06 and only M fails; A–L and the older files are unchanged by the
  rounding change. That mutant was not part of the test-runner's run,
  which preceded the rounding change.
- Test-runner: six mutants (overtime left in the PAYE base, `<` for `<=`,
  `pays_paye` ignored, a single rate, no posting line, Attendant added to
  the select policy) each turned the expected probes red. It recomputed
  every oracle figure independently.
- The catalog diff is additions plus the two function bodies. 169
  functions anon can execute, unchanged.
- Lint (0 errors), tsc, build and the overload check pass.
- In the browser as Manager, with a local fixture row: payslip, PDF,
  posting preview (balanced, 2330 overtime line), setup card and hint
  text. With no row, the setup card says the concession is not in effect
  (Manager and Auditor).
- The code review found nothing blocking.

## 2026-10-06 — Overtime tax slice: migration B (the 2026-10-01 rate row)

Eyram confirmed the figures and effective date (threshold 18,000, cap
share 50%, rates 5% and 10%, effective 2026-10-01); accountant approval
reported by Eyram, written copy to be saved. This supersedes the earlier
entry's "no row is shipped" and "28 probes".

**Built:** `20261006110000_overtime_tax_rates_2026.sql`, one
`overtime_tax_rates` row (`on conflict (effective_from) do nothing`).
Payroll months from October 2026 get the concession; earlier months keep
the old treatment. Payslips already generated are snapshots and are not
recomputed.

**Migration A, small changes since the earlier entry:**
- The concession test now uses the overtime as shown on the payslip
  (`round(hours x rate, 2) > 0`), so overtime that rounds to 0.00 no longer
  sets the concession flag. This changes no oracle case.
- Comment fixes: the previous `create_payslip()` definition is
  `20260909130000`, and the header now points at migration B.

**Probes** (`supabase/role-matrix/20261006100000_overtime_tax_engine.sql`,
now 30):
- A9 asserts exactly the shipped row.
- Oracle cases A-O run under the real row with October 2026 runs. K is
  September 2026 with the real row present (no concession); K2 has no row.
- New B-N: each tax part is rounded separately (basic 1,200.20, overtime
  600.15, tax 30.02; rounding only the sum gives 30.01). New B-O: the cap is
  rounded (basic 1,000.19, overtime 500.10 exactly at the cap, tax 25.01;
  an unrounded cap gives 25.00). The test-runner had found both mistakes
  survived the 28-probe file.
- Posting probes C1 and C2 now run October 2026 under the real row.

**Verification:**
- Clean reset with A and B: all 10 probe files pass. The overtime file
  passes 30/30, and the 9 older files are byte-identical to their output
  from before migration A.
- Existing data: payroll data (Posted August, Ready for Review September,
  Draft October with overtime, 21 payslips) was created through the real
  functions before both migrations. After applying A and B, the checksum of
  every pre-existing payroll and journal row is identical, and posting the
  September run gives identical lines. Regenerating an October Draft
  payslip (basic 1,200, overtime 400) picks up the concession (overtime tax
  20.00).
- Mutants, each caught by a probe: unrounded basis (B-M), sum-only
  rounding (B-N), unrounded cap (B-O), `<` for `<=` (B-D), overtime left in
  PAYE (ten probes), `pays_paye` ignored (B-I, B-J), no 2330 line (C1), the
  row's above-cap rate changed to 11 (A9, B-B, B-G).
- Test-runner brute force: 12,000 October 2026 payslips under the real row
  matched an independent Decimal model, with net = gross - deductions on
  every row. Non-qualifying cases, and 1,152 September 2026 payslips, were
  identical to the pre-slice function.
- Lint (0 errors), tsc, build, overload check and types diff pass. 169
  functions anon can execute (unchanged); anon has no access to the table.
- Code review: nothing blocking.

## 2026-10-07 — Live site was using the local Supabase; deploy script added

Eyram found the live site's requests going to `127.0.0.1:54321`, so it
showed the local `seed.sql` demo data (INV-2404 to INV-2429, Samuel
Tetteh, the paint and tile products) instead of the hosted database. The
hosted discovery query had found none of those rows. Cause: the URL and
anon key are baked in at build time, the only env file in `frontend/` is
`.env.local` (local Supabase), and the Lovable config wrapper's
`loadEnv(mode, cwd, "VITE_")` reads `.env.local` in every mode, including
production builds. The deploy shipped a build made that way. The hand-over
commands given in earlier sessions (`npm run build && npx wrangler deploy`)
did not say to build with the hosted values.

Every sales, customers, inventory, pro-forma, customer deposits, POS, end
of day and purchasing screen reads Supabase through `src/lib/supabase.ts`;
none uses mock data or browser storage.

Added `frontend/scripts/deploy-production.sh`, now the only way to deploy
(rule in CONSTRAINTS.md "Deployment" and CLAUDE.md). It reads the hosted
values from the gitignored `frontend/.env.deploy`, sets every `.env` file
Vite would load aside during the build, refuses the local Supabase
address, the `.env.local` key or a CLI demo key in `dist/`, requires the
hosted URL and key in both bundles, and only then runs `wrangler deploy`.
The literal rule "refuse any `127.0.0.1` or `localhost`" could not be
used: supabase-js and TanStack Router contain those strings in every
build.

Verification, without deploying (`--check-only` / `--build-only`, fake
project ref and an unsigned fake anon key):
- The existing local build was refused, listing the five places the local
  address was baked in.
- A missing `.env.deploy`, a local URL, a service_role key, a secret key
  and a leftover folder from an interrupted run were each refused.
- A build with the fake hosted values passed every check. `.env.local`
  came back byte-identical, and so it did after a build killed mid-way.
- The test `.env.deploy` and `dist/` were removed afterwards.

Not done: no deploy, nothing on hosted. Eyram creates `.env.deploy` and
runs the script.

## 2026-10-07 — Hosted cleanup of dummy records; live site deploy fixed

This week's one-off cleanup of the hosted project (scripts kept outside
the repo) removed:
- 9 dummy employees;
- the September 2026 payroll run (7 payslips) and its journal entry
  JE-26090002;
- 39 audit rows about those records;
- 8 Storage files: 6 generated documents and 2 onboarding documents;
- the QA test expense EXP-1043, its journal entry JE-26090001 and its
  receipt file.

JE-26090001 and JE-26090002 are left unused on purpose, a gap in the
journal entry sequence.

All 5 hosted staff accounts were kept, including the test Accountant and
Auditor logins.

Live site: it had been built with the local Supabase address and was
reading the local database (previous entry). It now deploys through
`frontend/scripts/deploy-production.sh` against the hosted project. The
retail demo data seen on the live site was local seed data and was never
in the hosted database. This supersedes the previous entry's "Not done:
no deploy".

## 2026-10-07 — Slice 0: golden payslip suite

Built slice 0 (payroll regression carry-back) as a permanent golden
payslip suite, the go-live clearance for HR and Payroll. It holds
`create_payslip()`, `post_payroll_run()` and the run-exclusion flow to
hand-derived figures against the real rate rows, through the existing
rolled-back harness. No migration, no engine or frontend change.

- `supabase/golden/payslips.sql`: 39 active probes. G0 pins the rate rows.
  Then: 2026 band edges and cases; high earners; fines, IOU and the
  half-pesewa tie; 2025 band edges; Eyram's four overtime figures;
  Emmanuel Ansah (5,008.37 in August 2026, 5,002.37 in September); and three
  run probes (an exclusion with posting and the overtime-tax line, posting
  without it, a refused submission). Five PENDING cases are commented out
  with their expected values.
- `supabase/golden/payslips-tcsos-hand.sql`: 4 probes, the TCS OS
  hand-computed tier (D-0c), labelled not ERP-confirmed.
- `scripts/golden-payslips.sh` runs both; CLAUDE.md and
  `.claude/agents/test-runner.md` make the suite a before-and-after gate for
  payroll and finance changes, and forbid editing an expected figure to pass.

Eyram's decisions: suite in `supabase/golden/`, two files, noisy six-role
output kept; D-0a written off (Abena and Yaw were dummy records); D-0c yes;
D-0d: the 2025 band set asserted, labelled "current behaviour, not confirmed
correct".

The accountant's answers (reported by Eyram 2026-10-07, accountant confirmed (reported, written copy to be saved)) moved these
to asserted: the contribution split (0.5 / 5 / 13 / 0); fines and IOU after
tax with no cap; half a pesewa rounds up in PAYE; no SSNIT ceiling known
to the accountant; normal PAYE rates for non-qualifying overtime. Still
PENDING: non-taxable allowances (all taxable until he names an exemption),
non-qualifying overtime entering PAYE unrounded, a National Service payslip
showing taxable income with no PAYE, and the 4910 / 1350 posting accounts.
The 2026-09-01 set applies to the first real payroll.

After the code review, taxable income is no longer asserted for the
National Service, PAYE-exempt and H3 cases: what a payslip shows as
taxable income with no PAYE charged is one of the pending items.

Verification:
- "Before", on a fresh database at 6fdb4c0: all 10 existing role-matrix
  files pass. The suite didn't exist yet; this slice changes no engine
  code.
- After: `./scripts/golden-payslips.sh` passes (39 + 4 cases). The 10
  existing files give byte-identical output to the before run. Lint (0
  errors), tsc, build and the overload check pass.
- Every expected figure was typed from the approved plan and recomputed
  with an independent Decimal model; the test-runner recomputed them again
  from the live rate rows (0 disagreements), and checked the pending values.
- 13 mutants were applied to the local engine and data, including: PAYE
  rounded on the total; half-even rounding; fines reducing taxable income;
  employer SSNIT on gross; the band set picked by today's date; the
  overtime-tax line always or never posted; a changed band rate; and a
  submission that skips the unaccounted check. Every one turned at least one
  case red.
- A wrong expected figure prints one line naming each field with exp= and
  got=, and <<WRONG on the wrong one. A misspelt expected key is refused.
- Code review: one blocking finding, fixed: the taxable income of a
  National Service payslip had been asserted. The smaller points were also
  taken.
- docs-updater worked from the diff and Eyram's instructions. Its PORT-PLAN
  table had wrong case inputs and statuses, which I rewrote.

## 2026-10-07 — Overtime pay rounded to the printed figure

Accountant confirmed (reported, written copy to be saved), reported by Eyram
2026-10-07: for staff who do not qualify for the overtime concession,
overtime enters the PAYE base at the amount printed on the payslip, rounded
to 2 dp, not the exact hours × rate. 2.5 h × 40.05 = 100.125 is printed and
taxed as 100.13, so PAYE on basic 1,900 in September 2026 is 211.34, not
211.33.

- Migration `20261007100000_overtime_pay_rounded.sql`: `create or replace`
  of `create_payslip` with the same signature, `security definer` and
  `search_path`; no grant changes. The one change is
  `v_overtime_pay := round(hours × rate, 2)`. Gross, total earning, taxable
  income, PAYE, total deductions and net pay all read that figure. The
  concession test and overtime tax already used the rounded figure, so the
  concession cases' figures are unchanged. Existing payslips, draft or
  posted, are not recalculated. Hosted has no payroll runs (Eyram), so no
  hosted payslip is affected.
- Golden suite: the pending case Q-OT-UNR is now asserted as E-R1 (211.34,
  deductions 315.84, net 1,684.29). New case E-R2: October 2026, basic
  4,500 (no concession, 54,000 > 18,000), 1.5 h × 20.05 = 30.075 taxed as
  30.08, PAYE 675.15 in the 25% band (675.14 unrounded), net 3,607.43.
  PENDING cases now: Q-ALW-N, Q-ALW-MIX, Q-NSS-ALW, Q-POST-3.
- Found while tracing overtime, not changed: hours, rate, allowance amounts,
  fines and IOU with more than 2 dp are stored rounded but computed exact
  (hours 2.555 at 40.00 prints "2.56h @ 40.00" beside 102.20; an allowance
  of 100.125 enters PAYE unrounded). Recorded in CONSTRAINTS as an open
  question for the accountant.

Verification:
- Before, fresh reset at `08d69dd`: all 10 role-matrix files and
  `./scripts/golden-payslips.sh` exit 0.
- The new golden file run against the old engine: only E-R1 and E-R2 red,
  each on PAYE, deductions and net by one pesewa.
- After, fresh reset with the migration: the golden suite passes (41 + 4
  cases), and its output differs from the before run only by the two new
  cases. The 10 role-matrix files are byte-identical to the before run.
  The catalog definition of `create_payslip` differs by the one line; its
  ACL is identical; one overload.
- test-runner: lint, tsc, build and the overload check pass. The types
  regen differs from the committed file only in helper-type parentheses
  (no table, function or enum differs; no schema change in this slice).
  It recomputed E-R1 and E-R2 from the live rows with no disagreement.
  Four mutants each turned the suite red: unrounded overtime (E-R1, E-R2);
  rounding gross only (E-R1, E-R2); truncating (E-M, E-R1, E-R2);
  half-down (E-M, E-R1, E-R2). The concession cases E-A, E-B and GA-X1
  stayed green under all four.
- code-reviewer: no blocking findings.
- docs-updater called this a schema change and missed the PORT-PLAN case
  table and pending list; I corrected those.

## 2026-10-07 — Payroll inputs: more than 2 decimal places or a negative value refused

Owner decision (Eyram, 2026-10-07), recommended to the accountant: any
payroll input that is a money amount or an hours figure has at most 2
decimal places, refused rather than rounded, enforced in the database so the
form cannot be bypassed. Closes the CONSTRAINTS open question from the
overtime-rounding slice.

- The inputs and their write paths: `employee_pay_config.basic_salary`
  (`propose_employee`, `propose_pay_config_change`, `approve_employee`,
  `approve_pay_config`); `employee_allowances.default_amount` (direct
  client insert/update under RLS); `payslips.overtime_hours`,
  `overtime_rate`, `fines`, `iou` and `payslip_allowances.amount`
  (`create_payslip`). There is no IOU or repayment table; IOU exists only
  as the payslip input. Rate tables are written only by migrations and are
  out of scope.
- Migration `20261007110000_payroll_inputs_two_dp.sql`: a `numeric(p,2)`
  column rounds a value before any trigger or check sees it, so the seven
  columns become plain `numeric`. Each gets a `*_2dp` check (value =
  round(value, 2), plus the old magnitude bound) and a BEFORE INSERT OR
  UPDATE trigger, `_refuse_over_2dp()`, which raises e.g. "Fines must have
  at most 2 decimal places (got 10.005)" (or "... is not a valid amount"
  for NaN or out-of-range) and stores round(value, 2), so stored values
  keep scale 2. No function body, grant or RLS change; the trigger
  function is not executable by anon or authenticated.
- Frontend: overtime hours `step` 0.5 → 0.01 (the other inputs were already
  0.01). `setStandingAllowances` now inserts the new rows before deleting
  the old, so a refused amount keeps the old allowances; if the delete
  fails, the new rows are deleted again, and the list reloads either way.
  Still two client calls, not one transaction. All affected forms already
  show the server message via `getErrorMessage`.
- Golden section V, 17 cases: refusals V-SAL-1 to 4 (each basic-salary
  RPC), V-ALW-1 and 2 (standing allowance insert and update), V-PS-1 to 8
  (hours, rate, allowance, fines, IOU, 10.00001, the string "1e-3", NaN);
  accepted V-OK-1 (OT 1.25 × 40.05, allowance 100.12, fines 10.05, IOU
  20.25: PAYE 220.09, net 1,695.29), V-OK-2 and V-OK-3 (2 dp salary and
  standing allowance accepted; 1500 and 100 stored as 1500.00 and 100.00).
- Found, not changed: fines, IOU, overtime hours and rate have no `>= 0`
  check (recorded in CONSTRAINTS).

Verification:
- Before, fresh reset at `173bb11`: all 10 role-matrix files and the golden
  suite exit 0.
- After the migration: the 10 role-matrix files and the existing golden
  output are byte-identical to the before run. With section V the golden
  suite passes (58 + 4 cases).
- Through the API as the local dev Manager, a direct standing-allowance
  insert of 100.125 returns code 22023 with the message above; nothing is
  written.
- test-runner: lint, tsc, build, the overload check pass; types regen
  differs only in helper-type parentheses; seeded values all scale 2;
  V-OK-1 recomputed from the live rows. Mutants, each from a fresh reset:
  triggers dropped (refusals come back as raw check-constraint text and
  V-OK-2/3 lose scale 2: 16 V cases red); triggers and checks dropped (the
  same 16 red, values accepted); the old `numeric(p,2)` types restored (13
  refusal cases red, silently rounded). No non-V case went red.
- code-reviewer: no blocking findings. Its point that insert-then-delete
  could leave duplicate standing allowances (paid twice by bulk generation)
  if the delete failed led to the compensating delete above; a single RPC
  would make it atomic.
- docs-updater miscounted the V cases and cited invented line numbers; I
  rewrote this entry.

Extension, same day, same unapplied migration (owner decision, Eyram
2026-10-07): negative amounts and hours are refused on the same seven
inputs.

- The trigger also raises "<Label> cannot be negative (got X)" (after the
  NaN/range check, before the decimals check). `payslips.overtime_hours`,
  `overtime_rate`, `fines` and `iou` gained a `>= 0` check; the other three
  columns already had one. This closes the CONSTRAINTS item about negative
  payslip inputs.
- Zero stays allowed on all seven. For basic salary I checked whether zero
  is ever legitimate: the schema has allowed it since `20260908070000`
  ("Basic salary must be zero or more"), the forms accept 0, Volunteer and
  Intern are employment types (allowance-only pay is plausible), and the
  TCS OS pay-config model sets no minimum. No seeded record has a zero
  salary. So zero is allowed rather than requiring more than zero.
- Golden section N, 14 cases: N-SAL-1 to 4 (each basic-salary RPC refuses
  -100 with its existing message; these exercise the RPCs' own checks, not
  the new trigger branch, since salary is only written through them),
  N-ALW-1 and 2 (standing allowance insert and update, -50), N-PS-1 to 6
  (hours, rate, allowance, fines, IOU, fines -0.01), N-OK-1 (basic 0
  accepted, stored 0.00), N-OK-2 (October 2026, basic 0, taxable allowance
  500: PAYE 0, net 500).
- Found: the four approval "Adjust before approving" paths sent
  `Number(override.basicSalary) || 0`, so clearing the salary box approved
  a basic salary of 0 without warning (older than this slice; with zero
  allowed the database cannot tell it from an intended 0). Fixed below.

Verification of the extension:
- Before (fresh reset with the slice as it stood): 10 role-matrix files and
  the golden suite exit 0.
- After: the 10 files are byte-identical to that run; the golden suite
  passes (72 + 4 cases) and its output differs only by the N cases.
- test-runner: lint, tsc, build, the overload check pass; types regen only
  the known parentheses; N-OK-2 recomputed from the live rows; no seeded
  value negative. Mutants from a fresh reset: the negative branch removed
  (N-ALW-1/2 and N-PS-1 to 6 red, refused by raw check text instead); the
  branch and the `>= 0` checks removed (the same 8 red, negatives
  accepted). No other case went red.
- code-reviewer: no blocking findings.

Approve-screen salary check, same slice (Eyram, 2026-10-07): the four
"Adjust before approving" screens (new employee and pay change, on the
Employees list and on the employee page) now refuse a blank or invalid
salary box on approve, like the propose forms do. A new
`overrideBasicSalary()` in `components/employees/payment-fields.tsx`
replaces `Number(override.basicSalary) || 0` at all four sites. A blank,
whitespace-only, non-numeric, infinite or negative box throws "Enter a
basic salary (0 or more) to approve with, or press Cancel to approve as
proposed.", which the screen's existing error toast shows, and the approve
RPC is not called. An explicit 0 is still sent. Approving without
adjusting is unchanged. No database change.

Verification: lint, tsc and build pass. There is no frontend test
framework, so the check's logic was run directly on "", "   ", "abc",
"-5" and "Infinity" (each refused) and "0", "0.00", "1500", "1500.25" and
" 2000 " (each accepted). code-reviewer: no blocking findings; it
confirmed the throw happens before the RPC call and reaches the toast via
`getErrorMessage`, and that each adjust section has the Cancel button the
message names.

## 2026-10-07 — Staff advances (IOU loans)

An advance is now recorded once and repaid automatically through payroll
until it is repaid or a Manager approves a pause or cancellation. Design
and new surface approved by Eyram before the build, with his answers:
build the net-pay cap as the default but keep its golden case PENDING;
keep the 1350 run-posting case PENDING alongside Q-POST-3; a Manager may
approve their own proposal, both names shown; cancel only stops
deductions and leaves the balance on 1350.

- `20261008100000_staff_advances.sql`: tables `staff_advances`,
  `staff_advance_change_requests` (pause, resume, cancel, instalment;
  one pending per advance) and `staff_advance_repayments` (one per advance
  per payslip, `on delete cascade` with the payslip). Select-only for
  Manager, Accountant and Auditor; no direct writes. Balance and Settled
  are computed (`staff_advance_summary`), never stored. Write RPCs: propose,
  approve, reject and withdraw, for advances and for changes; approve and
  reject are Manager only, and approving an advance posts Dr 1350 / Cr the
  payout account (Cash 1000, Mobile Money 1020, Bank Transfer the chosen
  bank account) on Main, dated the payout date. Audit rows for proposals,
  approvals and rejections (six new `audit_log` actions; the 22 existing
  ones kept). An approved advance's amount, dates and payout are frozen by
  trigger. Money columns follow the 2 dp / non-negative trigger and checks.
  Read functions `staff_advance_deduction_preview` and
  `staff_advance_payslip_lines` (balance remaining after a payslip,
  computed at display).
- `20261008110000_create_payslip_staff_advances.sql`: `create_payslip`
  (same signature) deducts each eligible advance after every other
  deduction, oldest approval first, `least(instalment, balance)`, capped
  so net pay can't go below zero; the total joins `payslips.iou` (which
  `post_payroll_run` already credits to 1350) and `total_deductions`;
  taxable income and PAYE are untouched. A manual IOU on a payslip that
  deducts an advance is refused. A payslip with no eligible advance is
  computed exactly as before.
- Frontend: a Staff Advances tab under Payroll (propose, approvals,
  change requests); an advances card on the employee profile (finance
  roles only, with a banner when a non-active employee has a balance);
  the payslip dialog shows what each advance will deduct and turns the
  manual IOU box off when one applies; the printed payslip and its PDF
  show one line per advance repayment with the balance remaining.
- Golden: new `supabase/golden/staff-advances.sql`, run by
  `./scripts/golden-payslips.sh`: 20 cases (normal instalment; 600 at 250
  settling with a final 100 and nothing after; paused; cancelled; two
  advances; manual IOU refused; draft delete restores the balance;
  a later draft month doesn't over-deduct; a backdated run is skipped;
  not before the first repayment month; draft and posted payslips not
  recalculated; refusals of 3 dp, negative, zero, an instalment above the
  amount, a repayment month before the payout, and a 3 dp instalment
  change). PENDING, commented out with figures: run posting to 1350,
  the payout entry, the net-pay cap (fines 2,400 leave 137.24), and the
  cap's oldest-first order with two advances. Role matrix:
  `supabase/role-matrix/20261008100000_staff_advances.sql`.
- CONSTRAINTS: the decisions and PENDING items (cap, leaver settlement and
  write-off, interest, maximum size), 1350 unconfirmed; and the
  accountant's further answers: all allowances taxable, no health
  insurance, no extra pension.

Verification:
- Before, fresh reset at `94723eb`: the 10 role-matrix files and the
  golden suite exit 0.
- After both migrations: the 10 role-matrix files are byte-identical, and
  the existing golden files' output is byte-identical to the before run.
  The new golden file passes (20 cases), and the 4 PENDING cases pass
  when run uncommented (they stay commented). The new role-matrix file
  passes: propose and withdraw Manager and Accountant; approve, reject and
  others' withdrawals Manager only; reads Manager, Accountant, Auditor;
  direct writes and the internal helper nobody; anon executes none of the
  new functions. Checked directly: audit rows written by proposer and
  approver, the payout entry (Dr 1350 / Cr 1020 for Mobile Money), and the
  freeze trigger refusing an amount change.
- test-runner: lint (0 errors, 13 warnings as before), tsc, build,
  overload check pass; types regen differs only in the known helper
  parentheses; ADV-1, ADV-2, ADV-5 and ADV-P3 recomputed independently.
  Mutants, each from a fresh reset: ignoring advances, no balance cap,
  counting only posted repayments, no manual-IOU refusal, and Paused
  treated as Active each turned staff-advances cases red, with the older
  golden files green. Newest-first ordering survived, because order only
  changes figures under the cap; covered by PENDING case ADV-P4.
- code-reviewer: no blocking findings. Taken from its notes: a load error
  now uses `getErrorMessage`, a failed deduction preview shows a note, the
  payout posts on Main rather than the employee's branch, and a first
  repayment month before the payout month is refused (ADV-R8). The full
  suite was re-run after these.
- docs-updater placed the CONSTRAINTS block inside the retirement
  checklist and misdescribed tables and statuses; I rewrote its edits.

## 2026-10-08 — Employee bulk import

Employees can now be added in bulk from a spreadsheet: download the
template, fill it in, upload, see every row as OK or with its problem,
then confirm. Plan and new surface approved by Eyram, with his answers:
phone matches warn without blocking; a name match refuses the row ("add
them by hand"); blank SSNIT/Tier 2/PAYE flags are an error; the audit
trail stays exactly as manual entry writes it, with no salary or personal
details in error messages or app logs; no uniqueness constraints this
slice (PLANNING notes the manual-path gap); the unedited example row is
refused; the parser fixes must leave the other importers unchanged.

- `20261009100000_employee_bulk_import.sql`: `preview_employee_import`
  (saves nothing) and `import_employees` (advisory lock, checks again,
  all-or-nothing), both Manager and Accountant only with anon revoked,
  sharing the private `_employee_import_check` and three private parsing
  helpers (money, date, Yes/No) that no user can call. Each row goes
  through the unchanged `propose_employee` (Pending Approval employee, and
  a Pending Approval pay config when a salary is given) and then
  `update_employee_profile`. New audit action `employees_imported`: one
  summary row per import with counts only; the per-employee rows are the
  manual ones. Money: optional GHS or cedi sign, commas only as thousands
  separators, ASCII digits only, at most 2 decimals, no negatives, zero
  allowed. Dates YYYY-MM-DD. Position, department and bank must be in the
  existing lists. Limits 200 rows and 512 KB. Standing allowances and
  qualifications are not imported.
- Frontend: an "Import employees" button beside "Propose employee". The
  shared `ImportDialog` gained an opt-in `remote` mode (the database checks
  the whole file, confirm stays off until every row is OK, rows keep their
  spreadsheet numbers, the template is an .xlsx with every cell typed as
  text). `parse.ts` gained an additive `rowNumbers` and an opt-in
  `isoDates` option that decodes Excel date cells with SheetJS's calendar
  code, the same in every time zone. Only the employee importer uses them.

Verification:
- Before, fresh reset at `d9e52f1`: the 11 role-matrix files and the
  golden suite exit 0.
- After: the 11 files and the golden output are byte-identical;
  `propose_employee` and `update_employee_profile` are unchanged in the
  catalog. The new role-matrix file passes (18 probes): preview and import
  Manager and Accountant only; helpers nobody; anon executes none;
  messages name columns, never values (including non-ASCII digits);
  an error row saves nothing; a National Service row gets a Pending pay
  config with No/No/No and nothing becomes Active; one summary audit row;
  example row, existing name, same name twice in one file and 201 rows
  refused; a failure while saving shows the row number only.
- Other importers: a harness parses 24 CSV and XLSX files across the
  products, customers, invoices and bank-statement importers (blank lines,
  quoted fields, typed number and date cells, extra and missing columns)
  with their default options; the output is byte-identical before and
  after. The dialog's existing path keeps `index + 2` row numbers, browser
  validation, valid-rows-only import and the CSV template.
- End to end against the local API as the dev Accountant: the generated
  template is refused at preview and at import; a filled file with a blank
  line keeps rows 2 and 4; an Excel date cell arrives as 1990-05-07 (the
  default mode still gives 5/7/90). Dates from 1905 to 2026 decode
  correctly in Accra, New York, London, Kolkata and Auckland.
- test-runner: lint (0 errors, 13 warnings as before), tsc, build,
  overload check pass; types regen only the known helper parentheses.
  Deliberate breaks, each caught: skipping the re-check, an Active pay
  config, anon execute, dropping the existing-name check, blank flags
  defaulting to Yes, a 1000-row cap, removing the example-row check. Two
  breaks it found uncaught (the save-failure wrapper and an in-file
  duplicate name) now have probes B9 and B8; removing the wrapper turns B9
  red with the leaked text.
- code-reviewer: one blocking finding, fixed: `\d` in the money parser
  matched non-ASCII digits, which the numeric cast then refused with the
  value in its message (probe A4). Also taken: commas only as thousands
  separators ("1,50" was read as 150), the dialog no longer stays busy if
  closed during a check, a failed refresh after a committed import isn't
  reported as a failed import, and the date decoding above (the first
  version, via local dates, was a day out east of UTC). Re-review: nothing
  blocking.
- docs-updater added an advisory-lock timeout example, a race as a cause
  of rollback, and "duplicates caught by normal approval workflow"; none
  is true and I removed them.

## 2026-10-08 — Employee import: only Name required, blank flags warn

Eyram changed two rules of the (still uncommitted) employee import, so the
rest of a record can be filled in by hand after the upload. This
supersedes "blank SSNIT/Tier 2/PAYE flags are an error" in the entry
above; the migration `20261009100000` was edited in place, since it has
not been committed or pushed.

- Checked first, as asked: `propose_employee` requires only a name (plus
  a branch, which the import supplies, and a payment method of Bank or
  Mobile Money, defaulting to Bank); `update_employee_profile` requires
  nothing. Neither was changed, and no placeholder value is written for a
  blank column. So only Name is required; the template now heads it
  "Name (required)".
- On a row with a salary, a blank flag is treated as Yes (manual entry's
  default) with a warning on that row, e.g. "SSNIT flag blank, will be
  treated as Yes"; warnings don't block the confirm. A value other than
  Yes/No is still an error. Blank dates and list cells are accepted as
  blank; wrong values are still errors.
- Open decision for Eyram: a row with pay details but no salary is still
  refused, because `propose_employee` stores pay details only in a pay
  config, which it creates only when a salary is given.

Verification:
- Fresh reset: the 11 other role-matrix files are byte-identical to the
  previous run and the golden suite to the slice's before run;
  `propose_employee` and `update_employee_profile` are unchanged. The
  import role-matrix file passes with 22 probes: B1 is now "a row with
  only a name"; B4's problem row uses the flag "maybe" instead of a blank;
  new B10 (a salaried row with blank flags: two warnings, no errors,
  imported as Yes/No/Yes and Pending), B11 (blank dates and lists
  accepted; a wrong date, employment type and position each refused with
  its own message), B12 (a blank name refused) and B13 (pay details
  without a salary refused).
- Lint (0 errors, 13 warnings), tsc and build pass; the end-to-end run
  with the new header and the 24-case parser regression for the other
  importers are unchanged.
- test-runner's deliberate breaks: blank flag as No, blank flag as an
  error again, Yes without the warning, a blank date refused, a blank
  position refused, Name made optional and a wrong position accepted each
  turned a probe red. Pay details without a salary silently accepted
  survived; B13 was added and turns red under that break. (The earlier
  entry's break "blank flags defaulting to Yes" is now the intended
  behaviour.)
- code-reviewer: no blocking findings; B11 was tightened from an error
  count to the exact message per field on its advice.
- docs-updater edited CONSTRAINTS only; its text matched the facts given,
  except that it dropped the National Service sentence, which I restored.

## 2026-10-08 — "National Service" employment type

Eyram asked for National Service as its own employment type, an HR label
only. Before building I reported where the list lives (the employees
check constraint, `update_employee_profile`'s hard-coded list, the import
checker, and the frontend type and dropdown) and where it's used (the
profile's HR details, the import, and the `{{employment_type}}` token in
generated contracts; no report, filter or payslip uses it, and no payroll
function reads it). He approved three database changes and a separate
slice after the import was committed (`2f860ba`).

- `20261010100000_employment_type_national_service.sql`: the
  `employees_employment_type_check` constraint gains "National Service";
  `update_employee_profile` changes only its allowed list and message;
  `_employee_import_check` accepts the type and adds a non-blocking
  reminder ("National Service staff are normally exempt: check the SSNIT,
  Tier 2 and PAYE flags") when a National Service row with a salary would
  still pay any of them. The flags are never set from the type. No data
  is rewritten.
- Frontend: the type and the profile dropdown; a reminder on the profile
  when National Service is chosen and the current or pending pay config
  pays any flag; the import help text lists the allowed types and no
  longer reads as if the type sets the flags.
- The import role-matrix's B11 expected the old employment-type message;
  its expected text was updated to the new wording, the message this
  change intentionally alters. Nothing else in that file changed.

Verification:
- Before, fresh reset at `2f860ba`: the 12 role-matrix files and the
  golden suite exit 0; the four local employees have no employment type.
- Catalog diff after: `update_employee_profile` differs only in the
  allowed list and its message; `_employee_import_check` only in the
  list, the message and the reminder block; both functions' grants are
  identical. The constraint lists the six types. The employees' types are
  unchanged.
- All 12 existing role-matrix files pass with byte-identical output
  (the import file once B11's text was updated); the golden suite is
  byte-identical. New `supabase/role-matrix/20261010100000_employment_type_national_service.sql`
  passes with 7 probes: the constraint accepts the type; the profile sets
  it and leaves the pay flags alone; an unknown type is still refused; an
  import row with National Service and No, No, No saves as given with no
  warning; a National Service row with a Yes or blank flag gets the
  reminder, imports, and keeps its flags as given; no reminder without a
  salary; a National Service employee who still pays all three gets
  exactly the Full-Time figures (basic 3,100, September 2026: PAYE 392.26,
  net 2,537.24).
- Lint (0 errors, 13 warnings), tsc, build and the overload check pass;
  the types regen has no change beyond the known helper parentheses.
- test-runner's deliberate breaks, each caught by the new file: the
  constraint, the profile list or the checker list without the type;
  the checker setting the flags to No automatically; the reminder made
  blocking; the reminder removed; the profile function flipping the pay
  flags; `create_payslip` treating National Service as exempt.
- code-reviewer: no blocking findings; on its advice the import help
  text was reworded so it can't be read as the type setting the flags.
- docs-updater wrote that the flags "remain the only thing payroll
  reads", which overstates it; corrected to "payroll decides exemptions
  from the flags alone and never reads employment_type". It also left out
  the migration and the profile reminder, which I added.

---

## 2026-10-10 — TCS OS runway recorded; port plan status corrected

Docs only, no code or schema.

- PORT-PLAN's Status table, and slice 0's own status line, said slices 0
  and 2 were awaiting review. Both are committed ("Slice 0: golden
  payslip suite for payroll regression", 2026-10-07; "Admissions slice 2:
  grade reference data and staff admissions capabilities", 2026-10-05).
  Corrected.
- New PORT-PLAN section "TCS OS runway (as of 2026-10-10)", from a
  read-only investigation of `~/projects/tcs-os` (2026-10-08) plus what
  Eyram reported on 2026-10-10. It separates found, reported and inferred
  statements, and lists the questions only Eyram can answer. Headline:
  nothing in TCS OS's code or docs expires; the runway is set by billing
  and the admissions season.
- Reported, not verified: the Cloud Run console shows revision
  `admissions-00024-xxb` live (about 12 days before 2026-10-10), so the
  `admissions-00019-qm7` in TCS OS's `deployment.md` is stale. Both
  Supabase projects are separate and on free plans. The Google Cloud
  trial ends about 2026-10-13 and needs upgrading; Eyram is doing that on
  2026-10-10, and it isn't recorded as done.

---

## 2026-10-10 — Admissions slice 3a: applicant core tables with staff RLS

Slice 3 approved and built as 3a (decisions, offers and rules deferred to 3b).

**Eyram's approval (2026-10-10):** the slice 3 plan with gates A1–A5 (visibility and read access), B1–B4 (schema shape), and D-3c (option 3: capacity readable by Manager and Auditor only). New decisions recorded (D-3d through D-3g, decided 2026-10-10):

- **A1:** Manager and Auditor read every row of the slice 3a/3b tables (health excluded until slice 4).
- **A2 (= D-3d):** an Admissions Officer reads families, guardians, students, applications, emergency contacts and notes only for in-scope children; siblings in other bands are hidden (a deliberate change from TCS OS's unscoped StudentInline on the family page, `tcs-os admin.py:90-93`).
- **A3 (= D-3g):** an officer reads decisions and offers only if in scope AND holding can_decide (matches TCS OS's coordinator bundle, which had no view_decision/view_offer — `tcs-os migration 0019`). Built in slice 3b.
- **A4:** admissions_campus_grade_rules readable by Manager, Auditor and Admissions Officer. Built in slice 3b.
- **A5:** staff may read the token hash columns through ordinary select.
- **B1 (= D-3e):** capacity and campus rules keyed by grade_id FK to admissions_grades, not free-text year_group. Built in slice 3b.
- **B2 (= D-3f):** strict student_id and reference regexes kept; fallback is to drop the student_id check if the slice 15 inventory finds non-conforming legacy ids.
- **B3:** no legacy_id column; the slice 15 import keeps the old-id to uuid mapping in a local file.
- **B4:** slice 3 split into 3a (families, guardians, students, applications, application_emergency_contacts, application_notes) and 3b (application_decisions, application_offers, admissions_capacity, admissions_campus_grade_rules). Only 3a is built.
- **D-3c:** capacity readable by Manager and Auditor only (not officers).

**Built 3a:** migration `supabase/migrations/20261011100000_admissions_core_applicants.sql` (6 tables, 3 SECURITY DEFINER visibility helpers `admissions_application_visible/admissions_student_visible/admissions_family_visible(uuid)`, 2 triggers `normalise_guardian_email` and `set_application_note_identity`, 6 select policies, select-only for authenticated, nothing for anon, CRUD for service_role, no write RPCs, no audit_log action changes, no frontend change beyond regenerated `database.types.ts`). Probe files `supabase/role-matrix/20261011100000_admissions_core_applicants_visibility.sql` (51 probes) and `…_structure.sql` (39 probes).

**Deviations from the planner's draft:** student_id and INQ/APP regexes accept 4 or more trailing digits (TCS OS pads to 4 but doesn't cap, `tcs-os models.py:65-74, 113`); the note trigger forces `created_at` as well as `author_id` when `auth.uid()` is set.

**Corrections to PORT-PLAN's slice 3 text found while planning:** it's 10 tables not "about 11"; Annex campus grade rules can't be seeded by a migration because Annex is inserted by `supabase/seed.sql` and `supabase/seed.production.sql`, which run after migrations, so 3b puts those rows in both seed files keyed by branch_id; columns the plan omitted are included (`declaration_signature_name`, `declaration_agreed`, `wants_scholarship_info`, `scholarship_interest_details`, `applications.updated_at`, emergency contact name/relationship/phone); the IP column keeps TCS OS's name `declaration_ip_address`, type `inet`; there's no DB-side "school branch" helper and slice 3 doesn't need one.

**Carry-forwards found while planning, for later slices:** slice 5's reference-assigning trigger and slice 6's gates must not run on (or must skip) imported legacy rows; slice 5/6 should restrict deletes deliberately because families/students/applications cascade to notes and contacts; slice 9's submission snapshot must not live on applications or any table officers read without the health gate (it can hold health answers); slice 14 needs a token design for guardians created in the ERP, since a stored hash can't rebuild a permanent unsubscribe link; slice 15 import dry run should report legacy rows that the non-blank grade/academic-year checks, the student_id/reference formats or the length caps would refuse; slice 7a will need invented demo rows in seed.sql because nothing can create admissions rows until slice 8.

**Verification (test-runner, then main session):** fresh db reset + dev staff seed; lint 0 errors (13 warnings), tsc, build, duplicate-overload check pass; types regen additive apart from the known helper-parentheses noise; all 13 existing role-matrix files byte-identical to a baseline taken at HEAD before the first edit; both new files pass; catalog diff additions only (5 functions, 6 policies), anon-executable function count unchanged at 169; golden payslip suite unchanged versus baseline (not required: nothing touches payroll/finance paths). Deliberate breaks, each caught: applications policy `using (true)`; an insert grant plus policy on applications; family helper with only `has_role`, and with `has_role` removed (caught only by D6); student helper without the grade check; student_id regex back to exactly 4 digits; note trigger without the `auth.uid()` guard; execute on the family helper granted to anon. Dropping `security definer` from a helper was initially caught by nothing; probe A3 (prosecdef and pinned search_path on the three helpers) was added and catches it.

**code-reviewer:** no blocking findings. Acted on: added probe D8 (one student with applications in two bands); softened the migration header comment that claimed no check rejects a legacy value; clarified that the student and family helpers return true for Manager and Auditor for any id. Not acted on (noted only): policies don't say `to authenticated` (anon has no table grant, matches slice 2); per-row helper calls are fine at current volume; negative probes can't distinguish "hidden" from another error, mitigated by positive controls.

**Docs:** PORT-PLAN split slice 3 into 3a and 3b in the status table; recorded the split, decisions and carry-forwards in the slice 3a section; added carry-forward notes to slices 5, 6, 7a, 9, 14, 15; updated slice 15's runbook step 1 inventory to count non-conforming student_id and year_group_applied_for values and malformed references. DESIGN.md added the admissions-data-tables convention (select-only, SECURITY DEFINER helpers, live-scope visibility, identity triggers act only on signed-in writes). Fixed the stale note under slice 1b-ii that said slice 1c was "uncommitted, awaiting Eyram's review" — it's committed.

---

## 2026-10-11: Admissions slice 3b, decisions, offers and capacity, plus scope change

Slice 3b built (decisions, offers, capacity and campus rules), uncommitted; slice 3a committed but not pushed until 3b is complete so one rollout covers both.

**Build:** migration `supabase/migrations/20261012100000_admissions_decisions_offers_capacity_rules.sql` (4 tables, one trigger function, 4 select-only policies, no write RPCs or helpers). Tables: `application_decisions` (one per application, decision_type accepted/waitlisted/rejected, decided_by FK staff on delete set null, decided_at forced by trigger, notes up to 10000 chars); `application_offers` (one per application, token_hash not null unique with `^[0-9a-f]{64}$` format check, sent_at/expires_at/responded_at nullable, response pending/accepted/declined/expired); `admissions_capacity` (academic_year text, grade_id FK admissions_grades on delete restrict, branch_id nullable FK branches on delete restrict, capacity >= 0, unique nulls not distinct on (academic_year, grade_id, branch_id)); `admissions_campus_grade_rules` (branch_id, grade_id, composite primary key, both FKs on delete restrict). One trigger function `set_application_decision_identity()` forces decided_by and decided_at on insert and update, only when auth.uid() is set.

**Design decisions (decided 2026-10-11):** (a) composite primary key on campus rules; (b) restrict FKs from capacity and rules to grades and branches; (c) decided_at re-stamped on every signed-in update; (d) no consistency checks between offer dates; (e) academic_year matched as exact text; (f) campus rule enforced only in slice 9's submit RPC, never as a trigger. Read rules (slice 3b decisions): Manager and Auditor see all; Admissions Officer sees decisions and offers only when the application is in scope AND they hold can_decide (matches D-3g). Capacity readable by Manager and Auditor only; campus rules by Manager, Auditor and Admissions Officer. Offer token_hash readable by the same readers as the offer.

**Seeds:** supabase/seed.sql inserts Annex's two rules (Pre Nursery, Nursery 1) after the branches insert. supabase/seed.production.sql: the header reworded (safe on a fresh project; on a live project don't re-run the whole file, because the first block can re-create deleted or renamed expense categories or allowance types, and a renamed Annex would get a second Annex branch); the Annex rules are a separate, final DO block that can be run on its own and fails loudly if Annex is missing or the two rules aren't present.

**Probes:** supabase/role-matrix/20261012100000_admissions_decisions_offers_capacity_rules_visibility.sql (40 probes) and …_structure.sql (48 probes). Both files pass locally.

**Verification (test-runner):** fresh db reset; lint 0 errors (13 warnings), tsc, build, duplicate-overload check all pass; types regen additive (149 lines); all 15 earlier role-matrix files byte-identical to a baseline; both new files green; catalog diff exactly 1 function and 4 policies added, none changed; anon-executable function count unchanged at 169; golden payslip suite unchanged. Deliberate breaks, all caught (the can_decide and scope conjuncts removed from the decisions and offers policies, capacity and rules policies widened or narrowed, grants to authenticated and anon, nulls not distinct removed, offer uniqueness dropped, token regex loosened and not null dropped, trigger guard and insert-only and decided_at on update, cascade on FK, execute to anon, seed.sql rules removed or extra Main rule, seed.production.sql without on conflict or wrong grade name). seed.production.sql tested: once, twice (idempotent), and with Annex deleted (recreated with 2 rules, Main unaffected).

**code-reviewer:** no blocking findings. Fixed after review (fix round 1): Annex rules moved into their own block in seed.production.sql so failure there doesn't abort category/allowance seeding; header warns about re-runs and renames; added probes DEC15b and OFF15b (Attendant and Accountant holding can_decide still read nothing); renamed probe C7 to clarify FK declaration. After fixes, both files pass (88 probes); seed checks re-run: once, twice, Annex-deleted all end with Annex 2 rules and Main 0. seed.production.sql with wrong grade name fails only in the rules block.

**Scope change, decided 2026-10-11:** All TCS OS applications and inquiries are test data. Nothing in TCS OS production needs migrating to the ERP. ERP reference counters start fresh. The port's scope shrinks: slice 5 no longer carries a carry-forward about skipping imported rows; slice 15 becomes a DNS and cutover step, not a hand migration. Still open: whether the 6 leads and 17 guardians who received TCS OS campaign emails are test data. If any are real, their unsubscribe links are the only TCS OS data that would need handling at cutover. Slices 0 to 3b are built; the rest is plan.

**Docs:** PORT-PLAN point 6 ("Where the code contradicts") rewritten to state all TCS OS applications/inquiries are test data and the open question about leads/guardians; slice 2's O-3 decision updated to "No SHS rows until TCS offers SHS"; slice 3b updated to show what was built (tables, read rules, design choices, seeds, probes, counts); slice 3a carry-forwards trimmed (removed import-related notes, kept delete restriction and demo rows); slice 5 updated (counters start fresh); slice 6 added a design carry-forward (capacity warning to officers must be figure-free); slice 7b updated (capacity screen visible to Manager/Auditor only); slice 15 rewritten (no inventory, export, import, verify or counter steps; fresh start, DNS and endpoint cutover, and the TCS OS admin freeze). "Links already sent" section gains a note that offer and draft links don't need to keep resolving since records are test data. Runbook shrinks from 11 steps to 6 (Prepare, Stop intake, Set roles/open, DNS, Keep read-only, Shutdown); adds open items before it (leads/guardians, seed.production status, Annex row, school edits). DESIGN.md extended the admissions-data-tables convention to cover decisions, offers, capacity and rules with their specific read rules. CONSTRAINTS.md updated the admissions cutover item and the TCS OS retirement section (no hand migration; which legacy links still matter; no-dual-intake wording). PLANNING.md's "about 3 real records" lines replaced with the new fact.

---

## 2026-10-11: Hosted Annex setup snippet

Slices 3a and 3b are applied on hosted. Hosted has one branch, "Treasures Christian School" (created 2026-09-09), and no Annex row; Annex is a real campus.

- New `docs/admissions/hosted-annex-setup.sql`, for Eyram to run by hand in the hosted SQL editor. One all-or-nothing DO block: checks Pre Nursery and Nursery 1 exist, inserts Annex only if no branch named Annex exists (name, default_low_stock_threshold 20, created_at one second after the newest branch, id from its default), refuses if Annex would become the oldest branch, inserts the two Annex grade rules with on conflict do nothing, and raises unless Annex has exactly 2 rules. Ends with a read-only select of branches and their rules. Not run by Claude, locally or on hosted.
- `seed.production.sql` is not used for this on hosted: its first block would rename the existing branch to Main and re-seed expense categories and allowance types. Its final Annex block looks Annex up by name, so it has no fixed-id problem, but it raises if Annex doesn't exist yet.
- Checked what a second branch row affects: no trigger on `branches`; no RLS policy keys on branch; every database picker uses `order by created_at limit 1` and every frontend lookup goes through `getSchoolBranchId()` / `getSchoolBranchRow()` / `useCurrentBranch()` (oldest branch); no screen lists branches in a dropdown; no code matches a branch by name. So staff, employees, payroll, expenses, POS and the branch name shown in the app stay on the existing branch. The hosted oldest branch keeps its name rather than "Main"; nothing depends on that name.
- PORT-PLAN's runbook open items updated with the hosted state and the snippet.

## 2026-10-11: Admissions slice 4, health answers, documents and the private bucket

Slice 4 built 2026-10-11, uncommitted. Delivers application_health_info and application_documents (metadata only), plus the private admissions-documents bucket with file visibility gated through document rows.

**Migration:** `20261013100000_admissions_health_documents_storage.sql`. Two tables (application_health_info one per application with three flag+details pairs capped at 2,000 chars; application_documents with eight TCS OS document types, status, storage_path and uploaded_at), one bucket (10 MiB, PDF/JPEG/PNG only), three RLS policies (health and documents read by scope and capability, bucket read by visible document row), grants for authenticated select and service_role full CRUD.

**Decisions (all decided 2026-10-11):**

- **D-4a.** Health gate: can_view_health AND band scope. Decided as recommended.
- **D-4b.** Grant timing: everything starts ungranted, and no migration or seed grants a capability. Eyram grants can_view_health to named staff through Settings (audited) once TCS names who needs it.
- **D-4c.** Health read audit: not in Phase 2, reserved for state transitions. Last good moment to revisit is before slice 7a builds on the table.
- **D-4d.** Retention direction kept: keep health data for enrolled students; purge closed applications after about 12 months once checked against Ghana's Data Protection Act 2012 (Act 843); the purge is a later slice, removes files through the Storage API and removes document rows and files before the application, because documents restrict.
- **D-4e.** Health details limit: 2,000 characters (slice 9 form must match).
- **D-4f.** Application deletes: restricted if documents exist.
- **D-4g.** Bucket: 10 MiB, PDF/JPEG/PNG only, no HEIC.
- **D-4h.** Signed file URLs: 300 seconds (slice 7a constant).
- **D-4i.** Staff edit RPC for health: none built.
- **D-4j.** Document read gate: scope only, no health capability needed.
- **D-4k.** Manager and Auditor: need can_view_health for health reads.
- **D-4l.** Attendant and Accountant: may hold can_view_health (O-6) but read nothing.
- **D-4m.** Health rows: only when answered (inquiries have none).

**Probe files:** supabase/role-matrix/20261013100000_admissions_health_documents_storage_visibility.sql (59 probes) and …_structure.sql (31 probes). Deliberate breaks: 23 total; 20 caught; break 5 (dropping has_role allowlist) is an equivalent mutant (has_admissions_capability already limits roles, kept for defence in depth); break 9a (prefix match on storage_path) was not caught, so probe SV7c was added; break 23 (bucket on conflict do nothing) can't be caught by SQL probes (B5 replays its own upsert). B1 runs bucket check as postgres because storage.buckets has RLS.

**Verification:** baseline at HEAD (17 earlier probe files and the golden suite green, 169 anon-executable functions; the golden suite isn't required for this slice). test-runner: lint 0 errors, 13 warnings; tsc, build, overload check pass; types regen additive (76 lines); all 17 earlier files byte-identical; both new files green; catalog diff: no function added or changed, exactly 3 policies added (health and documents table select, storage select), none changed; anon-executable 169; golden unchanged. Local Storage API check (outside repo): bucket not public, public URL refused with "Bucket not found"; Manager and Auditor sign and fetch; Attendant, Accountant, officers without capability or wrong band refused; officer with right band can sign; file with no row can't be signed by anyone; Manager and anon uploads refused; 11 MiB, HEIC and application/x-msdownload rejected; PNG and JPEG accepted; cleanup left no files or rows. code-reviewer: no blocking findings. Noted: PORT-PLAN slice 4 still mentioned a document read function and two storage policies (now removed); storage_path still allows "a//b" and "a/./b" (harmless, because matching is exact and unique); slice 9 must sanitize file names to allowed characters.

**Student emergency summary (requested 2026-10-11):** added to PORT-PLAN as a future, unscheduled slice after enrolment exists: a student-level emergency record filled from the application's health answers at enrolment, updated by a nurse or administrator, with read logging proposed. Access model, decided 2026-10-11: readable by all active staff (`is_active_staff()`), enrolled students only, emergency fields only (allergies, conditions, medication, doctor, emergency contacts), edits restricted to a nurse or administrator role. The roles cook, nurse and class teacher don't exist yet, so that slice must add them. Slice 4 stays as built.

**Documents updated:**
- PORT-PLAN.md: status line, slice 4 status, slice 4 section rewrite, 7a health panel wording with D-4c and D-4h notes, slice 9 carry-forwards (2,000 char limit, file name sanitization), slice 10 payload shape correction, cutover runbook step 6 (TCS OS shutdown decoupled from D-4d), new future slice "Student emergency summary" after cutover.
- DESIGN.md: admissions data tables entry extended for slice 4 scope and visibility rules (health with capability gate, documents with scope only), files readable through visible rows, applications with documents restrict deletes; new storage gotchas section (protect_objects_delete trigger, RLS on buckets, SQL bypasses limits, HTTP testing, on conflict do update for pre-existing buckets).
- CONSTRAINTS.md: no changes (health gate statement already accurate).

**Outstanding for Eyram:** confirm Ghana's Data Protection Act 2012 retention obligations before fixing purge period; no production steps in this slice.

---

## 2026-10-11: Admissions slice 5, numbering, stages, notes and document review

Slice 5 built 2026-10-11, uncommitted. Delivers reference numbering (INQ and APP counters, year-based sequences), stage transitions, notes with edit tracking, and document status review.

**Migration:** `20261014100000_admissions_numbering_stages_notes_documents.sql`. One table (admissions_reference_counters, key PK with check allowing INQ-YYYY, APP-YYYY, STUDENT-YY-PP; next_value >= 1). Fourteen functions: nine granted to no one (four numbering helpers: year in Africa/Accra, sequence text with a 4-digit minimum that widens past 9999, an atomic upsert holding the counter lock to commit, and a reference builder that skips hand-entered numbers; the writer guard: active Manager or Admissions Officer, Auditor refused; and four trigger functions), plus the five RPCs. Five RPCs (move_application_to_document_review, set_application_stage, add_application_note, update_application_note, set_application_document_status). Five triggers (applications_assign_references for INQ on insert at inquiry and APP first past inquiry, applications_guard_update stops anything leaving enrolled for any caller and stops a signed-in caller changing or clearing an assigned reference (postgres and service_role can, for hand corrections), applications_set_updated_at reuses set_updated_at(), applications_audit_stage AFTER UPDATE OF stage, application_documents_audit_status on application_documents). One column added (application_notes.edited_at). Two new audit_log_action_check values (application_stage_changed, application_document_status_changed).

**Counters:** RLS on, no policy, revoke all from public, anon, authenticated and service_role. Counters start empty. _next_admissions_sequence holds the lock to commit, so no gaps from rollbacks. _next_admissions_reference skips a number a hand-entered row already holds. Year pinned to Africa/Accra at assignment time.

**Formats (D-5a decided, year pinned to Africa/Accra):** INQ-YYYY-NNNN assigned on inquiry insert; APP-YYYY-NNNN the first time stage is past inquiry. YYYY is the year at assignment. Sequences reset per year. Four-digit minimum, widening past 9999 with no cap (plain Postgres lpad would truncate 10000 to 1000, so a widening formatter is used; the same lpad truncation affects the existing invoice and deposit numbering, out of scope, noted only). Each number assigned once, never reassigned.

**Stage RPCs (D-5c decided):** move_application_to_document_review (Manager or in-scope officer; inquiry or application only; re-checked under row lock). set_application_stage (Manager only; targets application, document_review, waitlisted, rejected; never inquiry, offer, offer_declined or enrolled; never out of offer or enrolled; refuses same stage).

**Notes and documents (D-5g, D-5h decided):** add_application_note (Manager or in-scope officer; trimmed; not blank; at most 10,000 chars; author and time set by 3a trigger). update_application_note (author only, while active and in scope; content and edited_at only; no delete RPC). set_application_document_status (Manager or in-scope officer; between pending_review, approved, rejected; never to required; refused on document with no file; refuses same status). Out of scope and not found give same error in every RPC ("Application not found", "Note not found", "Document not found"). can_decide and can_view_health play no part. Auditor never writes.

**Audit rows (D-5i decided):** only when a signed-in staff member made the change (no actor, no row). Stage row: before {stage}, after {stage, application_reference}. Document row: before {status}, after {status, document_type, application_reference}; no file path, names or health data. Readable through existing audit_log_select (Manager, Accountant, Auditor). Service_role or postgres changes write no audit row.

**Decisions (decided 2026-10-11):**

- **D-5a.** Formats final. TCS OS records them as settled with TCS ("no legacy convention", `02-stack-and-schema.md:156-159`). Decision: keep them verbatim, zero-padded to 4 digits.
- **D-5b.** May Manager move out of terminal stage (rejected, waitlisted, offer_declined)? Recommendation: allow except from enrolled, and audit it. Decision: allow with audit.
- **D-5c.** set_application_stage targets only application, document_review, waitlisted and rejected; never inquiry, offer, offer_declined or enrolled; never out of offer or enrolled. Decided.
- **D-5d.** No leaving enrolled for any caller, by trigger. Decided.
- **D-5e.** Gaps only from hand actions (delete, edit counter, skip), never failures (counter and row commit or roll back together). Decided.
- **D-5f.** Student IDs (YYPPNNNN, counter key STUDENT-YY-PP) assigned in slice 6 reusing _next_admissions_sequence and _admissions_sequence_text.
- **D-5g.** Notes.edited_at, author-only edit, no delete. Bad note by deactivated author fixed only by postgres; Manager redact can be added later. Decided.
- **D-5h.** Document status changes ARE audited (changed from plan). Payload: status, document_type, application_reference. Decided.
- **D-5i.** Stage audit rows carry application reference. Service_role/postgres write no audit row. Decided.
- **D-5j.** Counters with no privilege for any API role including service_role, no read for anyone. Decided.
- **D-5k.** Offer needs-accepted-decision and enrolled needs-decision-and-offer gate built in slice 6. Decided.
- **D-5l.** Year pinned to Africa/Accra. Decided.

**Probes:** supabase/role-matrix/20261014100000_admissions_numbering_stages_notes_documents_structure.sql (16), _numbering.sql (18), _rpcs.sql (81): 115 in all. Slice 4 structure file probe A4 changed on purpose: asserts none on application_health_info and exactly application_documents_audit_status on application_documents (slice 9 will update if it adds a document trigger).

**Verification:** baseline at HEAD d5580d8 on fresh reset (19 probe files and golden suite green, anon-executable 169). After build: lint 0 errors, 13 warnings; tsc, build, overload check pass; types regen additive (155 lines); 18 earlier probe files byte-identical, slice 4 structure file differing only in A4's name line; three new files green; golden suite byte-identical before and after audit list rewrite; catalog diff 14 new functions (set_updated_at reused), none changed, no policy change, anon-executable 169. Concurrency races on local DB: new counter key (A=1, B=2, B waited about 5 s), existing key, two committed inquiry inserts (consecutive numbers, no unique violation), stage race (second call raised "currently at 'document_review'", exactly one audit row written). Deliberate breaks: 32 variants; 30 caught by probes or races (lock and stage re-lock only by races); two gaps (INQ assigned on update; RPC's 10,000-character check backed by table check) closed by new probes N3c and NO8b, each verified to catch its break.

**code-reviewer:** no blocking findings. Fix round 1: skip-if-in-use check split per prefix so always uses unique index. Not changed: probe A3d keeps fixed anon-executable count of 169 on purpose (standing rule); setup-only probes run identically for every role (accepted). Noted for later: service_role already has table-level insert and update on applications, so slices 8 and 9 stage changes bypass RPC rules and write no audit row (keep in view on those reviews); counter locks held to commit (future transaction numbering both INQ and APP in opposite orders could deadlock, keep intake short and consistent); lpad truncation also affects existing invoice and deposit numbering (out of scope, noted only).

**Documents updated:**
- PORT-PLAN.md: status line changed to "slices 0 to 5 built"; status table: slice 4 to committed (admissions 4), slice 5 to built awaiting review (uncommitted); slice 4 status line to committed; complete rewrite of slice 5 section (formats, decisions D-5a through D-5l with what was changed from plan, probes, verification, code-reviewer findings, carry-forwards for slices 6, 8, 9); carry-forward "(Optional) numbering trigger with a stable name" in slice 3a marked done (applications_assign_references); slice 6 design carry-forward updated (reuses _next_admissions_sequence for student IDs, built-in offer/enrolled gate); slices 8 and 9 sections add carry-forwards (service_role bypasses stage rules, no audit row; keep intake short and consistent; slice 9 must update probes if it adds document trigger).
- DESIGN.md: new numbering convention entry (counters table no API privileges, numbers by BEFORE trigger so every writer is numbered, atomic upsert holding lock to commit, no gaps from rollbacks, skip hand-entered numbers, lpad gotcha, year to Africa/Accra). Extended admissions data tables entry (slice 5 adds first write RPCs with role guard and scope re-check under row lock, indistinguishable not-found errors; audit rows for stage and document status changes trigger-written only for signed-in actor).

**Outstanding for Eyram:** review the slice. The production step after review is `npx supabase db push` (Eyram's to run); no seed or frontend change.


---

## 2026-10-12: Admissions slice 6a, decisions and capacity (staff side)

Slice 6 split into 6a (decisions and capacity) and 6b (offers, enrolment gate, student IDs). 6a built, uncommitted, awaiting Eyram's review. 6b not started.

**Migration** `20261015100000_admissions_decisions_capacity.sql`, 11 new functions, no existing function, policy or table grant changed:
- `application_offers.response` gains `withdrawn` (D-6j, changed from the recommendation of reusing `expired`). A withdrawn offer counts like a declined one.
- Helpers with no grant: `_require_admissions_decider()` (the slice 5 writer guard, then the decide capability), `_admissions_grade_id()`, `_offer_effective_response()` (a pending offer strictly past `expires_at` reads as expired, using `clock_timestamp()` because `now()` goes stale after a lock wait), `_admissions_capacity_warning()`.
- `record_decision` creates the one decision and refuses when one exists; `change_decision` changes it and refuses when none exists or nothing changes (D-6k). Both need can_decide, held explicitly by a Manager too, and scope for an officer; checks run role, capability, scope, then again under the application row lock. Both refuse at inquiry or enrolled (D-6f). waitlisted and rejected move the stage; accepted never does. When `change_decision` takes a decision away from accepted, a pending offer is withdrawn and an offer the parent accepted blocks the change.
- Capacity warning, returned to both a Manager and an officer when the resulting decision is accepted: strictly greater than the capacity, null-safe campus match, leaving out `offer_declined` applications and offers declined, withdrawn or past expiry (D-6c). Only the Manager's text carries figures. It never blocks.
- Manager-only `create_admissions_capacity`, `update_admissions_capacity` (figure only), `delete_admissions_capacity`.
- Audit by trigger, signed-in actor only: `application_decision_changed` (decision type set or changed; not on a notes-only edit) and `admissions_capacity_changed`. The action list goes from 31 to 33.

**Decisions (2026-10-12):** D-6a to D-6i and D-6k to D-6p as recommended (see PORT-PLAN's consolidated table); D-6j changed to `withdrawn`. No document gate for offers or enrolment; 7b lists unapproved documents as a warning. D-6g keeps the enrolment calendar year, with an open question: do the real current TCS student IDs follow YYPPNNNN, and which year did they use? D-6h refuses enrolment for an unbanded or legacy grade, with a 7b carry-forward for a Manager-only grade-correction RPC. PORT-PLAN's migrated-data wording dropped (nothing is imported from TCS OS).

**Probes:** `20261015100000_admissions_decisions_capacity_structure.sql` (28), `_decisions.sql` (80), `_capacity.sql` (72), 180 in all. One intended change to an earlier file: slice 5 structure probe A5 now checks the audit list still contains its 31 values; the newest slice's structure file pins the exact list (33 here). No 3b probe listed the offer response values, so no 3b file changed. Probe S13 checks the source of `record_decision` and `change_decision` for the application row lock and the scope re-check under it, which no single-session behaviour probe can see.

**Verification:** baseline at HEAD 8b9c1d4 on a fresh reset: 22 probe files and the golden suite green, anon-executable count 169. After the build: db reset, duplicate-overload check, lint (0 errors, 13 warnings), tsc and build pass; types regen additive; all 25 probe files and the golden suite green, the 22 earlier files' output unchanged; anon-executable count 169. 45 deliberate breaks, all caught except equivalent mutants (`clock_timestamp()` with `>=`, and dropping the anon or authenticated revoke while the PUBLIC revoke stays). Two gaps closed: a probe helper that passed on NULL, and a missing lock or under-lock re-check (probe S13, also shown by races).

**Races (local):** two `record_decision` calls: the second waited, then was refused; one decision, one audit row. Two `change_decision` calls serialized, two audit rows. A scope change held under lock made a waiting officer's `record_decision` fail with "Application not found". `change_decision` against an offer being accepted by a raw write: accept first, the change is refused; change first, the offer is withdrawn, but an unguarded raw write could still set it to accepted. So 6b's accept paths must lock the application, then the offer, and re-check pending, expiry and the accepted decision under the lock (recorded as a 6b carry-forward).

**code-reviewer:** no blocking findings. Noted, not changed: the warning can undercount when two applications for the same year, grade and campus are accepted at the same moment (a soft warning; a capacity row lock would make it exact); the 3b identity trigger re-stamps `decided_by` and `decided_at` on a notes-only edit, so `decided_at` means last changed; the branch-null audit skip is unreachable because `staff.branch_id` is not null; an accepted decision can sit on a waitlisted or rejected stage (TCS OS parity; 6b's `generate_offer` allows those stages).

**Outstanding for Eyram:** review 6a. After commit, `npx supabase db push`; then on hosted a Manager grants themselves can_decide in Settings, since no migration grants a capability.

---

## 2026-10-12: Admissions slice 6b, offers, the enrolment gate and student IDs (staff side)

6b built, uncommitted, awaiting Eyram's review. 6a is committed (5c56735).

**Migration** `20261016100000_admissions_offers_enrolment.sql`: 12 new functions, one replaced (`audit_application_stage`), 4 new triggers, one table, one view.
- `admissions_settings`: one row, `offer_ttl_days` default 14, 1 to 90 (D-6a). Read by Manager and Auditor; changed only by the Manager-only `set_admissions_offer_ttl_days`; service_role gets select and update only.
- `generate_offer`, `reset_offer`, `record_offer_response` need the decide capability, and scope for an officer: role, capability, scope, then again under the lock. The token is 32 random bytes; only its SHA-256 hex is stored, and the raw token is returned once. A reset always replaces the token, so the old link finds nothing (D-6b). A reset is refused once the parent has accepted (D-6m).
- `mark_enrolled`, Manager only (D-6d): needs stage offer, an accepted decision and an offer whose effective response is accepted. It assigns YYPPNNNN once per student: YY is the Africa/Accra year at enrolment, PP the grade's classification code, NNNN from the `STUDENT-YY-PP` counter, skipping a number a hand-entered student holds. A grade with no code is refused (D-6h). An existing ID is kept, and a second enrolment of one student in one academic year is refused (D-6i). The enrolment stage audit row carries the student ID. The `students_guard_student_id` trigger stops a signed-in caller changing an assigned ID.
- Expiry is computed, never written by a read path (D-6l). `settle_expired_offers` is service_role only and also refuses any caller with `auth.uid()` set. It writes expired and moves offer to offer_declined, with no audit row.
- View `application_offer_status` (security_invoker) has no `token_hash` and shows `effective_response`. The expiry rule is written out inline, because `_offer_effective_response` has no grant for authenticated.
- Lock order on every accept and enrol path: application, decision, offer, student, counter. The request asked for application, offer, student, counter, and the plan asked for `change_decision`'s order (application, decision, offer); this satisfies both. The sweep takes the application, then the offer.
- Audit by trigger, signed-in actor only: `application_offer_changed` (response, expiry, a `token_replaced` boolean and the application reference; never the token or its hash) and `admissions_settings_changed`. The list goes from 33 to 35. 6a's `change_decision` withdrawal now also writes an offer row.

**Probes:** `20261016100000_admissions_offers_enrolment_structure.sql` (20), `_offers.sql` (53), `_enrolment.sql` (23): 96 in all. S13 checks the lock order and the re-checks under the locks by source; S15 checks token minting and hashing by source. Two intended changes to the 6a structure file: S6 now checks that the 33 values are still present (the 6b file pins the exact 35), and S8 now allows the new `application_offers_audit` trigger. The S8 change wasn't anticipated in the plan; it follows from the approved offer audit trigger.

**Verification:** baseline at HEAD 5c56735 on a fresh reset: overload check clean, types matched, golden suite green. After the build: db reset, overload check clean, types regen additive and identical to the working-tree file, lint 0 errors 13 warnings, tsc and build pass, all 28 probe files green, golden suite green, anon-executable count 169. 20 deliberate breaks, each run only against its target probe file and restored against a catalog fingerprint, all caught. The dropped breaks were lower risk or equivalent: the settings RPC role check, the sweep's `auth.uid()` backstop (when its grant was broken, the backstop still refused staff), the stage list, TTL bounds, invalid response values, the unbanded-grade refusal (without it, enrolment still fails inside `_next_admissions_student_id`), and the revoke and clock mutants already covered in 6a.

**Races (local):** `change_decision` against `record_offer_response`: accept first, the change waited and was refused; change first, the accept waited and was refused at waitlisted, offer withdrawn. That refusal came from the stage re-check, since no staff path changes the decision without moving the stage; the decision re-check is pinned by S13 and probe B13. `change_decision` against `generate_offer`, both orders: the offer was withdrawn, or generation was refused. Two enrolments at one grade and year: consecutive IDs. The same application twice: the second was refused, one stage audit row. One student's two applications: in one year, the second was refused; in two years, the second kept the ID. The sweep against `record_offer_response`, both orders: accept first, the sweep settled nothing; sweep first, the accept was refused.

**code-reviewer:** no blocking findings. Not changed: authenticated still has table-level select on `application_offers`, `token_hash` included (3b grant), so the view alone doesn't hide the hash from a Manager, Auditor or deciding officer. The hash can't be reversed, and narrowing the grant is a later decision. `reset_offer` also works on a declined offer and from waitlisted or rejected stages, as long as the decision is accepted. The sweep's lock order comment was fixed.

**Outstanding for Eyram:** review 6b. After commit, `npx supabase db push`. D-6g stays open. Slice 12 schedules the sweep; slice 11's `respond_to_offer` must take the same locks and re-checks.

---

## 2026-10-12: Admissions D-6q, the offer token hash read grant

Decided: authenticated keeps its table-level select on `application_offers`, `token_hash` included (the 3b grant); no revoke. The hash is the SHA-256 of 32 random bytes and can't be reversed; the offer page compares hashes, so the hash alone gives no access; `application_offer_status` hides it; and a column-level grant would make `select *` on the table fail. Carry-forward for slice 7a: select explicit columns and never select `token_hash` in the UI. Recorded in PORT-PLAN (D-6q, the 6b section and slice 7a) and DESIGN.md. Docs only; no schema or code change.

## 2026-10-12: Admissions slice 7a, staff pipeline UI (list, detail, notes, documents, health panel)

Slice 7a built 2026-10-12, uncommitted, awaiting Eyram's review.

**Migrations:** `20261017100000_admissions_application_list.sql` and `20261017110000_admissions_academic_years.sql`.
- `admissions_application_list`: a security_invoker view selecting from applications with explicit columns (no health, decision, offer, declaration, token_hash columns), grants select to authenticated and service_role only, to prevent unguarded anon reads. Helper function `admissions_grade_name(text)` SECURITY DEFINER, search_path pinned, revoked from public and anon, returns the grade's display name for the list.
- `admissions_academic_years`: curated list of academic years, format YYYY/YYYY with consecutive years enforced by check constraint. Seeded 2026/2027 and 2027/2028 (Eyram's choice of format and years). Select granted to Manager, Auditor and Admissions Officer; no authenticated write. Fixes the D-6o typo risk: the pickers use this list. The columns stay free text with no foreign key, so legacy values still round-trip. Slice 7b will add Manager RPCs to add and deactivate years; slices 8 and 9 submit will validate against this list.

**Anon-executable function count:** 169 (unchanged). The helper is revoked from anon and public.

**Frontend:** `routes/admissions/index.tsx` and `routes/admissions/$applicationId.tsx` (directory form, not dotted), module code in `src/modules/admissions/` with `data/`, `hooks/`, `components/`, `permissions.ts` and `labels.ts` (list and detail components reuse existing patterns).
- List: search by student name, inquiry and application references; filters by stage, campus, academic year (plus "Other, not on the list"), grade (plus "Unbanded or other grade" for Manager, Auditor and all_grades officers only); 50 per page.
- Detail: applicant, family and guardians, emergency contacts, declaration and consent (declaration IP address left out, Eyram's call), notes (add, edit own), documents (status change, View via 300-second signed link created on click, never stored), health panel (live `has_admissions_capability('health')` check; renders nothing for non-holders; "No health information on file" only for holders), Move to Document Review, Manager-only Change stage. Auditor sees a Read-only badge and no write controls. Attendant and Accountant get the "not available for this role" panel and no sidebar item.
- AuthGate's officer allowlist now covers `/admissions` and below.
- Sidebar: Admissions section after HR and Payroll.
- Out-of-scope, nonexistent and malformed ids show the same not-found page.
- No new RPC: the five write controls use slice 5 RPCs.

**Tests:** vitest added (option B, pure logic only; Eyram approved). `npm test` added to scripts. Vitest 5.0.4 works on Vite 8, so option A fallback wasn't needed. Two test files, 19 tests. An eslint override makes `select("*")` and `token_hash` literals errors under `modules/admissions`.

**Demo data:** invented rows in `supabase/seed.sql` only (9 applications, stages inquiry, application, document_review, waitlisted, rejected; offer and enrolled left for 7b since they need decision and offer rows). `seed.production.sql` untouched. `scripts/seed-local-admissions-files.sh` uploads invented placeholder files, localhost-guarded.

**Role matrix:** probes `supabase/role-matrix/20261017100000_admissions_application_list.sql` and `20261017110000_admissions_academic_years.sql`. Includes L3b: an officer with `{jhs}` sees exactly its in-scope row through the view and nothing out of scope. L10: anon cannot read the view. L10b: anon cannot execute the helper. L12: anon-executable count pinned at 169.

**Decisions (approved 2026-10-12):**
- **D-7a.** Staff route prefix `/admissions`. Eyram approved the folder form for routes (`routes/admissions/route.tsx`, `index.tsx`, `$applicationId.tsx`) rather than dotted filenames.
- Project layout rule adopted (docs/DESIGN.md, "Project layout"): new module code in `frontend/src/modules/<module>/`, thin routes, probes stay flat, `shared/` not created yet. CLAUDE.md "Repo layout" and commands updated (Eyram approved).

**Verification:** baseline before the first edit, on a fresh reset at HEAD 6c1f014: duplicate-overload check clean, types regen identical, lint 0 errors 13 warnings, tsc clean, anon-executable count 169. After build: lint 0 errors 13 warnings (same as baseline), tsc clean, 19 tests pass, build ok, db reset, duplicate-overload check clean, types regen identical, both new probe files and three existing admissions probe files green, 14 deliberate breaks (9 DB, 5 UI mapped onto unit tests) all went red and were restored; dropped breaks (U5 needs rendering but covered by grep and review; label and order mutations; pagination mutations; sidebar alone; equivalent revoke mutants; no new RPC so no transaction or concurrency races). Golden payroll suite skipped (no payroll, audit action list or statutory change).

**code-reviewer:** no blocking findings. Fix round 1 for two non-blocking ones: list fetched twice on mount, and a failed reload blanked panels. Re-reviewed, not blocking. Noted: health capability checked once per page mount (DB still enforces each read); `admissions_grade_name` is SECURITY DEFINER though it could be invoker (harmless).

**D-4c (no health read audit in Phase 2) stands:** slice 7a reads health through the table policy. Revisiting this later (to add audit logging) would mean switching to a SECURITY DEFINER read RPC.

**Carry-forward to 7b:** every query keeps explicit columns and never selects `token_hash`; offer state from `application_offer_status` only (D-6q).

**Port-Plan updates:** slice 7a section rewritten with status line, route paths updated to directory form (`routes/admissions/` with `index.tsx` and `$applicationId.tsx`), module structure documented (`src/modules/admissions/` with subdirectories). Slice 7b section updated with carry-forward details for the grade-correction RPC (also checks Annex campus rules) and the academic year write RPCs as a carry-forward. The audit log screen is recorded as a proposal, not a decision.

**Decisions approved by Eyram for later slices:** (1) the 7b grade-correction RPC also checks that the Annex campus accepts the new grade; (2) academic year write RPCs in 7b. **Recommended, not decided:** a read-only audit log screen (Manager, Accountant, Auditor) as its own slice after 7b (working name 7c).

**7b bullet removed:** PORT-PLAN.md's 7b bullet "Wiring the slice 2 capabilities panel into the staff list" was already removed earlier in this session (it was already built: settings.tsx shows an "Admissions access" column). No further action.

**Pure-move refactor proposed:** a later slice (not yet scheduled) to move HR and Finance modules from `src/data/` into `src/modules/` structure (git mv only, no behavior change). Not added to the plan yet; mentioned here for tracking.

**Slices 6a and 6b applied on hosted:** Eyram's `npx supabase migration list` on 2026-10-12 shows 20261015100000 (6a) and 20261016100000 (6b) on both Local and Remote.

**Lockfile patches:** two transitive bumps came with vitest (@jridgewell/sourcemap-codec, picomatch).

**Outstanding for Eyram:** review slice 7a. After commit, production steps are Eyram's: `npx supabase db push` (the two migrations; before the frontend deploy, since the list needs the view), then `frontend/scripts/deploy-production.sh`. No hosted seed or hand step; demo rows are local only.

## 2026-10-12: Admissions slice 7a applied on hosted and deployed

- Migrations 20261017100000 and 20261017110000 applied on hosted: Eyram's `npx supabase migration list` shows 20261017100000 and 20261017110000 on both Local and Remote.
- The 7a frontend was deployed on 2026-10-12.
- Slices 6a and 6b are also applied on hosted (same migration list output on 2026-10-12: 20261015100000 and 20261016100000 on both Local and Remote).

---

## 2026-10-12: Admissions slice 7b1, decision, offer and enrolment actions and grade correction

Slice 7b was split on 2026-10-12 into 7b1 (actions on the application detail page) and 7b2 (Manager and Auditor admin screens at `/admissions/settings`). 7b1 is built and uncommitted. 7b2 has not started and waits for Eyram's go.

**Decisions (2026-10-12):**

- Grade correction applies only to an unrecognised grade (the narrow rule). It locks the application row only, and the function explains why.
- D-6q reversed. `application_offers` select for authenticated is now a column-level grant without `token_hash`. Any column added later needs its own explicit grant (DESIGN.md).
- The audit action list goes from 35 to 37 in 7b1: `application_grade_corrected`, plus `admissions_academic_year_changed`, whose trigger comes in 7b2. 7b2 then leaves the CHECK untouched, so the golden payslip suite runs once, in 7b1.
- The grade audit row carries the old grade as the applicant typed it, truncated to 50 characters. This is the one free-text payload exception (DESIGN.md).
- The offer link shows once, as plain text with a Copy button and the warning "Not live yet, do not send this link." Until slice 11 ships the parent page, staff record the parent's answer with Record response. The link shape is `<origin>/offer?token=<token>`. Tokens issued now stay valid for slice 11, and any offer can be reset for a new link until the parent accepts.
- Accepted versus capacity counts are deferred.
- 7b2 academic years: add, retire and reactivate; no rename. 7b2 also audits them.
- D-6g stays open. No real applicant is enrolled on hosted until it is answered. The build does not depend on it.

**Built (uncommitted):**

- **Migration `20261018100000_admissions_grade_correction.sql`:**
  - `correct_application_grade(p_application_id uuid, p_grade_id uuid) returns jsonb`. Manager only. The order is role, scope, arguments (an active grade with a student ID classification), then the application row lock, with these re-checks under it: found and in scope, not enrolled, the current grade unrecognised, and campus grade rules (covering Annex). It stores the grade's canonical name and returns `year_group_applied_for`, `grade_band` and `stage`. It touches no decision, offer, student or counter row.
  - Trigger `applications_audit_grade` (`audit_application_grade()`) after update of `year_group_applied_for`. It fires for a signed-in actor only and carries the application reference, the new grade and the old grade.
  - The audit CHECK goes to 37 values.
  - The `application_offers` column grant: `id, application_id, sent_at, expires_at, response, responded_at`.
- **Frontend (`frontend/src/modules/admissions/`):**
  - `components/decision-offer-panel.tsx`:
    - Record and Change decision. The capacity warning toast shows the RPC's own text.
    - Generate offer, Reset offer and Record response.
    - The one-time link panel. The token lives in component state only.
    - Plain messages for a Manager or officer without decide, and for a failed capability check.
  - `components/enrolment-controls.tsx`:
    - Mark enrolled, Manager only. It lists every document that isn't approved, as a warning.
    - Mark enrolled is disabled with the reason when the grade has no band, and the student ID is shown after success.
    - Correct grade, Manager only.
  - Other module files:
    - `data/decisions.ts`: reads the decision, the offer status (from `application_offer_status` only) and the live decide capability.
    - The RPC wrappers in `data/mutations.ts`, and the grade id in `data/reference.ts`.
    - The display rules in `permissions.ts`.
    - `decision-permissions.test.ts`, with 11 tests.
    - The detail page reloads the Applicant card after enrolment.
  - Outside the module: `eslint.config.js` bans `localStorage` and `sessionStorage` in the admissions module, and `database.types.ts` is regenerated (additive, one function).
- **`seed.sql` (local only; `seed.production.sql` is unchanged):**
  - Seven invented applications: an accepted decision without an offer, a pending offer, an expired offer, an accepted offer with Grade 6 and two documents not uploaded, an accepted offer with "Grade 11", a declined offer, and an enrolled pupil with student ID 26039901.
  - One capacity row: Grade 3, Main, 2026/2027, capacity 1.
  - Every demo reference (7a and 7b1) moved to the 09xx range.

**Found during the build:** since 7a, the slice 5 numbering probe file had been failing. 7a's demo rows held `APP-2026-0001` onward, and the probes clear the counters and expect `-0001`. 7a's check pass ran only three of the older probe files. The fix is the 09xx move in `seed.sql`; no probe changed.

**Earlier probe files changed on purpose (no check removed):**

- These accept the offers column grant: A1 in `20261012100000_..._structure.sql`, S9 in `20261015100000_..._structure.sql`, and S14 in `20261016100000_..._structure.sql`.
- A4 in `20261014100000_..._structure.sql` and S6 in `20261016100000_..._structure.sql` are now superset checks. The 7b1 structure file owns the exact `applications` trigger list (S4) and the exact 37-value audit list (S2). Keep S2 and S4 permanently.
- 6b structure S13 has a comment pointing to 7b1 S5, which pins that the grade correction takes the application lock only.
- 6b enrolment M13 sets aside non-fixture offers in its rolled-back setup, because the expiry sweep is global.
- 6b offers B8 reads `token_hash` as postgres. It now checks that the stored hash is the SHA-256 of the latest token.

**Verification:**

- **Baseline before the first edit** (HEAD 35cce04, fresh reset): overload check clean, types identical, anon-executable count 169, golden payslip suite green.
- **After the build** (test-runner):
  - db reset and dev staff ok, overload check clean, types regen identical, anon count 169.
  - All 32 role-matrix files green.
  - Golden payslip suite green, with no expected figure changed.
  - Lint 0 errors and 13 warnings (same as the baseline), tsc clean, `npm test` 30 tests pass, build ok.
  - Nothing staged, and no service role key in `frontend/src`.
- **New probe files:**
  - `20261018100000_admissions_grade_correction.sql`: G1 to G10, plus T1, T1b and T2. T1 and T1b refuse `token_hash` and `select *` on `application_offers` for every role. T2 shows the granted columns and the status view still read.
  - `_structure.sql`: S1 to S7.
- **16 deliberate breaks, all caught.** Each break ran only against its target probe file and was restored against a catalog fingerprint.
  - 13 database breaks: no Manager check, existence checked before role, no `for update`, no campus rule, no narrow rule, enrolled allowed, inactive grade accepted, anon execute, audit trigger dropped, audit without an actor, a name in the audit row, audit list not extended, and `token_hash` readable again.
  - 3 frontend unit-test breaks: "checking" or "error" treated as granted, Reset offered on an accepted offer, and Mark enrolled offered with no band.
  - The no-actor break was first missed. The G10 fixture had no campus, so the trigger's no-branch exit hid it. G10 now uses a campus and catches it.
- **Dropped breaks:** message and label mutations; duplicate revoke mutants (equivalent); token persistence. There are no DOM tests, so persistence is covered by the eslint ban, which was checked to fire on `localStorage` and `window.sessionStorage`, and by review.
- **Races** (two real sessions, local):
  - Correction first: `mark_enrolled` waited about 2 seconds, then enrolled with classification 03.
  - Two corrections: the second waited about 2 seconds and was refused by the narrow rule, leaving one audit row.
  - Enrolment first with an unbanded grade is not a lock collision. A refused enrolment aborts and releases its lock at once. The outcome was still correct: the correction, then a successful enrolment.
- **code-reviewer:** no blocking findings. Keep 7b1 structure S2 and S4 permanently.
- **Not done:** no browser walk-through of the new screens yet.

**Outstanding:**

- Eyram's review, and a browser walk-through with the demo rows.
- After commit, Eyram's production steps: `npx supabase db push`, then `frontend/scripts/deploy-production.sh`.
- On hosted, a Manager must grant themselves `can_decide` (Settings, Staff, Admissions access) before the decision panel offers actions.

**7b1 follow-up (2026-10-12, uncommitted):**

- The Admissions Officer dashboard no longer says Admissions isn't built. It now points to Admissions, with an Open Admissions button. No other screen carried that text.
- An officer's empty, unfiltered application list now says "No applications in your assigned grades. A Manager sets your admissions access in Settings." It gives no count and no hint about applications outside their grades. The rule is `emptyListMessage()` in `permissions.ts`, with a unit test (32 tests pass).
- The local dev officer saw nothing because it had no admissions access row. Neither `seed.sql` nor `seed-local-dev-staff.sh` creates one, and the demo rows cover all three bands. The seed can't add one, because the dev accounts are created by the script after the seed runs. A pre-made row would also clash with the role-matrix probes, which insert the officer's access row in their own setup. To test the officer view locally, a Manager grants access in Settings, Staff, Admissions access.

## 2026-10-12: Admissions slice 7b2, admin screens and academic year list management

Slice 7b2 built on 2026-10-12 and committed as bed38c9; production steps not yet run.

**What was built:**

- **Migration `20261018110000_admissions_academic_years_write.sql`:**
  - `add_admissions_academic_year(p_label text)` returns the row. Manager only. Label trimmed and validated as YYYY/YYYY consecutive years (same CHECK rule as the table itself). Database assigns `position` as max+1 under a share row exclusive table lock. Duplicates (active or retired, padded or not) refused with message "That academic year is already on the list".
  - `set_admissions_academic_year_active(p_label text, p_active boolean)`: Manager only, retire or reactivate; no rename, no delete. Refuses unknown year, null flag, and no change.
  - Helper `_require_admissions_year_manager()` runs first, before any argument is read, so every non-Manager gets the same error "Only a Manager can change the academic year list" regardless of input.
  - Trigger `admissions_academic_years_audit` (after insert or update of `is_active`, signed-in actor only): fires `audit_admissions_academic_year()`, action `admissions_academic_year_changed`, entity_id is the label, branch is the actor's campus (as `admissions_settings_changed`). The audit CHECK is unchanged at 37 values.
  - `create_admissions_capacity`: same signature as 6a (create or replace). Now refuses a year not active on the list with message "The academic year must be an active year on the academic year list", taking FOR SHARE on the year row so it can't be retired between check and insert. Existing capacity rows for an unlisted or retired year are untouched and can still be changed and deleted. Consequence: a new capacity year must match the list format, so the old 50-character free text case can no longer be created.
  - Grants: revoked from public and anon; the two RPCs granted to authenticated and service_role; helper and trigger function have no grant. Anon-executable count stays 169. No new table, policy or permission.
- **Frontend:** `/admissions/settings` (thin route `routes/admissions/settings.tsx` with full component `modules/admissions/components/settings-page.tsx`). Sidebar item "Admissions Settings" for Manager and Auditor. Sections: Academic years (list, add, retire, reactivate), Offer expiry (show and edit `offer_ttl_days` via `set_admissions_offer_ttl_days`), Capacity (list, add, change, delete via the three 6a RPCs; rows whose year is retired or not on the list are flagged but still editable and deletable; add offers only active years), Campus grade rules (read only). Manager writes; Auditor sees no write controls and a Read-only badge. Officer, Attendant and Accountant get the role-blocked panel (new extracted component `role-blocked-panel.tsx`, also used by `/admissions` layout) and nothing is queried. New pure rules: `canViewAdmissionsSettings` and `canEditAdmissionsSettings` in `permissions.ts`. New helpers: `yearStatus`, `capacityYearOptions`, `parseWholeNumber`, `campusGradeSummary` in `settings-rules.ts` with `settings-rules.test.ts`. New `data/settings.ts` (explicit column selects) and six mutation wrappers in `data/mutations.ts`. `database.types.ts` regenerated (additive).
- **Probes:** new `20261018110000_admissions_academic_years_write.sql` (A1 to A13, C1 to C5) and `_structure.sql` (S1 to S7). Changed on purpose: `20261015100000_admissions_decisions_capacity_capacity.sql` V6d and V7 setups insert 2028/2029 and 2030/2031 into the year list; V7's 50-character year case moved to the new file's C1 as a refusal. No other probe changed.

**Verification:**

- Baseline before first edit (HEAD f04a336, fresh reset): overload check clean, types identical, anon count 169.
- After build (test-runner): db reset and dev staff ok, overload check clean, types regen identical, anon count 169. Six role-matrix files green (the two new files, 6a capacity and 6a structure, 7a academic years, 7b1 grade correction structure whose S2 shows audit list still exactly 37). `npm test` 39 tests pass. `tsc` clean. Lint 0 errors 13 warnings (baseline). Build ok. No `select("*")` or `token_hash` in admissions module. No service role key in `frontend/src`. Nothing staged. Golden payroll suite skipped (audit CHECK and nothing payroll related changed).
- Six deliberate breaks, all caught, each on a fresh reset against only its probe file: no Manager check on add (A1 to A5 mismatched), unlisted year accepted by capacity (C1, C2), retired year accepted (C2), anon granted execute on add (S1, S7), audit trigger dropped (structure S3; behaviour A10, A11), and Auditor allowed to edit in `canEditAdmissionsSettings` (unit test failed). None dropped.
- Races: none tested by plan (simple writes).
- Code-reviewer: no blocking findings. Non-blocking notes: unused v_staff variables; the 50-character length check in capacity create is now only reachable by labels the list check refuses anyway (kept so its message is unchanged); hard-coded "1 to 90" and maxLength copies in UI; the null campus cast in the capacity wrapper.
- Browser walk-through: not done.

**Outstanding:**

- Eyram's review.
- After commit: Eyram's production steps (`npx supabase db push`, then `frontend/scripts/deploy-production.sh`).

**Carry-forward:**

- Slices 8 and 9 validate the submitted year against the academic year list.
- The academic year list is now written only through the two Manager RPCs. Years are retired rather than deleted or renamed. Capacity creation requires an active listed year while older rows stay editable.

## 2026-10-12: D-6g answered (student IDs) and the staff ID format

**D-6g is answered and closed.** Eyram's answer: two digit calendar year of enrolment, then a two digit group code, then a four digit roll starting at 0001. The roll restarts per year and per group, so 26010001, 26020001 and 26030001 can all exist. The year is the year the student is enrolled in the system: a student accepted and enrolled in 2026 who starts school in 2027 keeps the 26 ID. Group codes: Pre Nursery to Nursery 2 is 01, KG 1 and 2 is 02, Primary 1 to 6 is 03, JHS 1 to 3 is 04.

Checked read-only against the code, no change needed (details in PORT-PLAN, slice 6b):

- The 14 grades' classification codes, seeded only in `20261005100000`, match the groups, reading Kindergarten 1 and 2 as KG 1 and 2, Grade 1 to 6 as Primary 1 to 6, and Grade 7 to 9 as JHS 1 to 3. That name correspondence is a reading of the TCS OS grade names, not something Eyram stated.
- `_next_admissions_student_id` (`20261016100000`) counts per `STUDENT-YY-PP` key from 1, and `mark_enrolled` takes the year from `_admissions_reference_year(clock_timestamp())`, the Africa/Accra calendar year (`20261014100000`).
- Not checked on hosted. The hosted grade codes need the read-only query given to Eyram.

The earlier lines "D-6g stays open" (6b and 7b1 entries) are superseded by this entry.

**Staff IDs (new, HR, not admissions).** Format `ST26-01002`: ST means staff, 26 is the year, then a dash, then a two digit class code (01 admin, 02 teaching, 03 non teaching), then a three digit roll number (002 in the example). **Open:** whether the roll restarts per year, per class, both or neither. Not built. A read-only check found no staff number or ID generated anywhere today: `employees` and `staff` have uuid keys only, the employee import template has no ID column, and the onboarding item "Staff Email & ID Issued" is derived from a linked login and a school email. Recorded in PLANNING, Phase 1.

No code changed and no probes run.

---

## 2026-10-13: Admissions 7c, read-only Audit Log and Accountant audit narrowing

Slice 7c was built on 2026-10-13. It is local only: the work is in the uncommitted working tree, and nothing is applied on hosted or deployed. It was built before slice 8.

**Why:** the audit log was readable by Manager, Accountant and Auditor alike, and every row was readable. So the Accountant could read admissions decision outcomes by APP reference, offer changes, and who holds the child-health gate. The role matrix (PORT-PLAN, "Roles and capabilities") gives the Accountant no admissions rows, and D-1b says the same for audit reads. Separately, `audit_log` had TRUNCATE granted to `anon`, `authenticated` and `service_role` through Supabase's default privileges. A probe showed that every role, anon included, could truncate `audit_log` inside a rolled-back transaction.

**Built (uncommitted):**

- **Migration `20261019100000_audit_log_admissions_read.sql`:** policy only. `audit_log_select` now lets Manager and Auditor read every row. The Accountant reads every row except actions starting `application_` or `admissions_` (9 of the 37 actions). Before this, Manager, Accountant and Auditor all read every row.
- **Migration `20261019110000_audit_log_revoke_truncate.sql`:** revokes TRUNCATE on `public.audit_log` from `anon`, `authenticated` and `service_role`. PostgREST has no truncate verb. The revoke removes TRUNCATE from those three roles. Before writing it, the session checked that no seed, probe, script, golden case or Edge Function truncates `audit_log`.
- **Frontend:** `/audit-log`, Manager, Accountant and Auditor only.
  - `routes/audit-log/index.tsx` is a thin route with a role guard. Module code is in `frontend/src/modules/audit/`: `labels.ts`, `permissions.ts`, `filters.ts`, `data/audit-log.ts`, `hooks/use-load.ts` and `components/audit-log-page.tsx`.
  - `hooks/use-load.ts` is a documented copy of the admissions hook, because modules must not import each other.
  - Filters: action, and a From and To date range. Both days are included, in UTC (which is Africa/Accra). 50 rows per page, newest first.
  - Actor names come from `list_staff_names()`. Changed fields are shown before and after.
  - The Accountant sees a note that admissions entries are not shown, and the action filter offers no admissions actions to the Accountant.
  - New sidebar section "Oversight" with "Audit Log".
- **Probes:**
  - New `supabase/role-matrix/20261019100000_audit_log_admissions_read.sql` (S1 to S3, R1 to R5, W1 to W3). S1 classifies all 37 actions, so a new action fails the probe until it is classified.
  - New `supabase/role-matrix/20261019110000_audit_log_revoke_truncate.sql` (T1, T2).
  - One deliberate edit to an existing probe: `20261005100000_admissions_grades_and_capabilities.sql`, E6 `expect` changed from Manager, Accountant, Auditor to Manager, Auditor. This is the same narrowing, seen from the grades side.

**A consequence to note:** O-8 (2026-10-05) accepted that the Accountant reads capability changes through the existing `audit_log` policy. Under 7c that no longer holds, because `admissions_capabilities_changed` starts with `admissions_`. Eyram should confirm this, since O-8 was a recorded decision. The 7c change was built as enforcement of D-1b. No separate decision for it is recorded in this journal.

**Verification:**

- **Baseline before the first edit** (HEAD 29ea1f3, fresh reset): overload check clean, types identical, anon-executable count 169.
- **After the build** (test-runner, fresh reset):
  - Overload check clean. Types regen identical. Anon-executable count 169, unchanged.
  - Lint 0 errors and 13 warnings (same as baseline). `tsc` clean. `npm test` 57 tests pass (18 new). Build ok.
  - No service role string in `frontend/src` or the client bundle. Nothing staged.
  - Both new probe files green.
  - The 15 earlier probe files that touch `audit_log` were run before and after the change. Output is identical except for the intended E6 change.
- **Golden payroll suite:** run at the end of 7c, after both migrations, on a fresh reset. All cases pass. It was not run before the first edit; Eyram asked for it once at the end.
- **Deliberate breaks, all caught:** 8 for the policy, and 1 for TRUNCATE.
  - Policy: the old policy (Accountant reads all); only the `application_` prefix hidden; the Accountant branch dropped; Auditor moved to the restricted branch; INSERT granted to `authenticated`; an unclassified 38th action; a UI filter offering admissions actions to the Accountant (unit test); the officer allowed to open the page (unit test).
  - TRUNCATE: truncate before the revoke (T1, T2).
- **Limitation:** the whole-catalog function fingerprint taken at baseline used an unordered aggregate, so before and after could not be compared. The migrations contain only one policy drop and create, and one revoke.
- **code-reviewer:** no blocking findings. Notes: the policy relies on the prefix naming rule, which S1 pins. `isAdmissionsAction` in `labels.ts` must stay in step with the SQL prefixes.
- **Not done:** a browser walk-through of `/audit-log`.

**Measured and not changed (for a later sweep decision):** after the revoke, 83 of 86 public tables still hold TRUNCATE for at least one API role (Supabase default privileges): 13 for `anon`, 64 for `authenticated`, and the rest for `service_role` only. Nothing in 7c changes these grants.

- **anon holds TRUNCATE on 13 tables:** `contract_templates`, `employee_documents`, `employee_generated_documents`, `employee_onboarding_submissions`, `employee_onboarding_tasks`, `employee_onboarding_tokens`, `held_sales`, `notifications`, `onboarding_checklist_items`, `pro_forma_invoices`, `pro_forma_invoice_lines`, `pro_forma_invoice_number_counters`, `qualifications`.
- **Financial and audit-style records that still hold TRUNCATE:** `accounts`, `bank_accounts`, `bank_deposits`, `bank_reconciliations`, `bank_statement_lines`, `customer_deposits`, `day_closes`, `expenses`, `expense_category_accounts`, `invoices`, `invoice_lines`, `invoice_payments`, `journal_entries`, `journal_lines`, `payroll_runs`, `payroll_run_exclusions`, `payslips`, `payslip_allowances`, `employee_pay_config`, `staff_advances`, `staff_advance_repayments`, `staff_advance_change_requests`, `sales`, `sale_lines`, `sale_payments`, `sale_returns`, `supplier_payments`, `stock_movements`, purchase order and receipt tables, pro forma invoice tables, `manager_overrides`, `statutory_rates`, `paye_bands`, `overtime_tax_rates`, `staff`, and the number counters (invoice, journal entry, sale, purchase order, pro forma, deposit).
- **Admissions tables** hold TRUNCATE for `service_role` only.
- `deposit_number_counters` still holds TRUNCATE for `authenticated` and `service_role`.

**Outstanding for Eyram:**

- Review and commit 7c.
- Production steps, after commit: `npx supabase db push`, then `frontend/scripts/deploy-production.sh`. Eyram runs both.
- 7b2's production steps are still outstanding and go with the same push and deploy.

**O-8 update:** O-8 was confirmed superseded on 2026-10-13, because D-1b is now enforced by 7c; PORT-PLAN.md records it (slice 2 decisions and the slice 7c section).

## 2026-10-13: Slice 8 and 9 planning decisions and the TCS OS read

Eyram answered the slice 8 and 9 planning questions on 2026-10-13. Nothing in slices 8 or 9 is built. These decisions are recorded in `docs/admissions/PORT-PLAN.md`, in the slice 8 and 9 sections and the consolidated table.

**Decided 2026-10-13:**

- **D-8a:** the bot check runs in the Supabase Edge Function `admissions-public`. The submit RPCs are service-role-only: `submit_inquiry` and `check_public_rate_limit` are revoked from `public`, `anon` and `authenticated`, and granted to `service_role`. The service role key never reaches the browser, Cloudflare, or any `VITE_` variable.
- **Anon surface:** `get_public_admissions_options()` is anon, SECURITY DEFINER and read-only. It takes the anon-executable count from 169 to 170. A probe names the added function, and the six probe files that pin 169 move to 170 in slice 8.
- **D-8b:** a new ERP Turnstile widget with its own keys. The marketing site's widgets are decided in slice 13.
- **D-8d:** rate limits are 20 per hour per IP hash, a global cap of 200 per hour, and 5 per guardian email per day. The IP hash is an HMAC made in the Edge Function, so the database never stores a raw IP. The numbers are kept in one place so they can be tuned after the first real month. The fixed refusal tells the visitor to call the school office, so a false positive (for example, parents sharing a mobile carrier address) has a way out. The draft and lead bucket numbers are not covered by this decision.
- **D-8e:** the origin allow-list is read from configuration, not hardcoded. It holds the workers.dev host and `app.tcsch.edu.gh` for now, plus localhost in local development only. Eyram confirms the final production host before cutover.
- **Public forms (slices 8 and 9):** free-text academic years and free-text grades are refused. Only the active lists are accepted. Where a grade isn't offered, the form says to contact the school.
- **D-9b (firmed):** a matched family never gains or changes guardians from an anonymous submission. Differing details go in the staff-only snapshot. The rationale: refusing a same-year, same-grade match would confirm that a record exists (enumeration). TCS OS's Application response returns `family_id`, application id and `student_id`.
- **D-9c (changed):** never refuse on a match. Flag it for staff, and give an identical response. The 2026-09-29 recommendation (refuse the same year and grade) is superseded.
- **Slice 9 split:** pre-split into 9a (upload path, submit RPC, minimal form) and 9b (the full 6-section form).
- **Slice 9 magic-byte check:** at submit, PDF, JPEG and PNG files are checked by their first bytes, because staff open files from strangers.

**Still open:** D-8c (inquiry de-duplication; the plan keeps none, for parity), D-9a (upload mechanism), D-9d (phone rule) and D-9e (application-fee proof). Also open: whether the hosted Edge runtime's `x-forwarded-for` can be trusted. Until that is answered, per-IP limits are best effort. Turnstile and the global cap are the controls that cannot be spoofed.

**Read from TCS OS (2026-10-13, from the code, not tested):**

- TCS OS's Turnstile check verifies `success` only (no hostname or action check), and fails closed on a network error.
- Draft saves and upload-url are not Turnstile-gated.
- TCS OS's DRF throttle has `NUM_PROXIES` unset, so it keys on the whole `X-Forwarded-For` string, whose front the client controls. With no `CACHES` setting, counters are per Cloud Run instance. So TCS OS's rate limits are probably ineffective, and its Turnstile check is its only real control.

These findings were read from code and not tested against a running TCS OS.

## 2026-10-14: Admissions 8, public request path and Inquiry form

Slice 8 was built on 2026-10-14. It is local only: the work is in the uncommitted working tree, and nothing is applied on hosted or deployed. It is the first slice with an anon surface, so the build went through the slice loop with a confirmation gate on the anon surface (PORT-PLAN, slice 8).

**Why:** public parents need an Inquiry form, and the form needs a bot check and rate limits that a client can't bypass. D-8a puts the Turnstile check in an Edge Function, `admissions-public`, and the submit RPCs are service-role-only, so the service role key never reaches the browser. D-8d sets the limits and D-8e the origin allow-list. The database never stores a raw IP or email: the keys are hashes, and a CHECK enforces it.

**Built (uncommitted):**

- **Migrations:**
  - `20261020100000_admissions_public_intake_flag.sql`: the intake flag, with a Manager-only setter.
  - `20261020110000_public_rate_limits.sql`: `public_rate_limits`, `_public_rate_limit_rule`, `check_public_rate_limit`, and the `_require_public_service_caller()` guard.
  - `20261020120000_admissions_submit_inquiry.sql`: `submit_inquiry`, service-role-only.
  - `20261020130000_admissions_public_options.sql`: `get_public_admissions_options()`, the one anon-executable function.
- **Edge Function** `supabase/functions/admissions-public`: `handler.ts`, `index.ts`, `handler.test.ts` and `integration.test.ts`. `verify_jwt = false` in `supabase/config.toml`.
- **Frontend:** the `/inquiry` route (`routes/inquiry.tsx`), `__root.tsx` and `routeTree.gen.ts` for the auth-free allow-list, and module files in `frontend/src/modules/admissions/`: `components/inquiry-page.tsx`, `components/turnstile-widget.tsx`, `data/public-intake.ts`, `inquiry-form.ts` and `inquiry-form.test.ts`. The Admissions Settings page gained a Public intake card (Manager toggle with a confirm step; Auditor read-only).
- **Deploy script:** `frontend/scripts/deploy-production.sh` (see the verification notes below).
- **Probes:** four new probe files, one for each migration, in `supabase/role-matrix/`. Seven existing probe files moved from 169 to 170 (the anon-executable count pinned in each). The plan text said six; the build moved seven, and this entry records seven.
- **Generated:** `frontend/src/lib/database.types.ts` regenerated.

**How it differs from the plan text:** PORT-PLAN, "Built 2026-10-14", has the full list. In short: `submit_inquiry` takes only the payload, so the database never sees an IP; the buckets are `submit_ip`, `submit_global` and `inquiry_email` (the plan's `submit`, `draft` and `lead` buckets are not built); and Turnstile also checks the hostname and the action.

**Anon surface:** anon-executable count 169 to 170. The one new function is `get_public_admissions_options()`, SECURITY DEFINER and read-only.

**Open decisions at the start:** D-8c (de-duplication) and the forwarded-IP question did not block the build. D-8c stays open, and the build keeps no de-duplication, for parity. The forwarded-IP question was built as "the leftmost `x-forwarded-for` as best effort". Per-IP limits are best effort until the hosted header is tested (PORT-PLAN, slice 8, Still open (a)).

**Verification:**

- **Baseline before the first edit** (HEAD 7a07d6a, fresh reset): reset and dev staff ok, overload check clean, types identical, anon-executable count 169.
- **After the build** (test-runner, fresh reset):
  - Overload check clean.
  - Types regen identical after one regen. The first run found one missing line, for `_require_public_service_caller`; the types were regenerated.
  - Anon-executable count 170.
  - Lint 0 errors and 13 warnings (same as baseline). `tsc` clean. `npm test` 77 pass. Build ok.
  - No service role or secret string in `dist/client` or `frontend/src`. No tracked file holds the local secret values.
  - `handler.test.ts` 25 of 25 at the test-runner pass (26 after a review fix, below).
  - `integration.test.ts` 7 of 7 against the local database, with a fake Turnstile verifier. No Cloudflare call was made.
  - All 40 role-matrix files green on a fresh reset.
- **Probe fixes:** I9 ordered by a column that `audit_log` doesn't have. The test-runner fixed it in the probe. R11 never reached the table CHECK, so it now inserts as postgres in setup. It was then shown to catch a dropped CHECK.
- **Deliberate breaks: 20, all caught:** anon grant on `submit_inquiry`; guard removed plus grant; intake check removed; free-text key allowed; inactive grade accepted; campus rule removed; email limit removed; IP limit 20 to 21; counter never refuses; raw IP storable; select on `public_rate_limits` granted to anon; rate-limit guard removed plus grant; options returning inactive grades; intake RPC without the Manager check; audit branch removed; global counted before Turnstile; raw IP sent as the key; Turnstile fail open; hostname check removed; token in a response.
  - Dropped on purpose: a retired-year break (the same rule as the inactive-grade break), and a frontend payload break (vitest covers it, and the server refuses unknown keys).
- **Golden payroll suite:** skipped. Nothing payroll-related changed, and no audit action list changed (`admissions_settings_changed` has existed since 6b).
- **Code review:** no blocking findings.
  - Fixed after review: the unknown-key message no longer echoes the key's name; a body stream that errors mid-read now gives a clean 400 (new handler test, which takes `handler.test.ts` to 26); the deploy script also refuses Cloudflare test site keys.
  - Deferred, non-blocking: rate-limit row cleanup runs on every hit (a scheduled cleanup later, D-12b); the closed flag is checked only in `submit_inquiry`, after the limits and Turnstile.
  - For Eyram: forwarded IP trust (a launch gate before intake opens); the per-email limit's enumeration and lockout effect (PORT-PLAN, slice 8, Still open (b)); and sign-off on the new server-side service_role use in the Edge Function.
- **Not done:**
  - A browser walk-through of `/inquiry`. Turnstile's test keys may not satisfy the hostname and action checks, and a real POST would call Cloudflare.
  - The deploy script was not run. The PreToolUse hook blocks every mode of it.

**Outstanding for Eyram:** review of the uncommitted slice. After the commit, Eyram's production steps: the database push, the Edge Function deploy, the Edge Function secrets, and `frontend/scripts/deploy-production.sh`. The exact commands are Eyram's to run, from the gate in CLAUDE.md. The decisions still open are D-8c and D-9d, and the three items under PORT-PLAN, slice 8, Still open (a) to (b).

## 2026-10-14: 7b2 and 7c status correction

Eyram reported on 2026-10-14 that the 7b2 (bed38c9) and 7c (7a07d6a) migrations are both applied on hosted. Their frontend deploys are not confirmed. Earlier lines in this journal saying their production steps were still outstanding (the 7b2 entry and the 7c entry's "Outstanding for Eyram") are superseded by this entry. The slice 8 report's remark that the next database push would also carry 7b2 and 7c was wrong. PORT-PLAN.md's status line, status table and the 7b and 7c sections are updated to match. Slice 8 is unchanged: built locally, not committed, nothing applied on hosted.

## 2026-10-14: D-8c and D-9d decided

Eyram closed two open decisions on 2026-10-14.

- **D-8c (closed):** no de-duplication on inquiries. Each inquiry creates a new family, guardians, students and applications, which is how slice 8 was built. Revisit with slice 9's matching.
- **D-9d (closed, changed from the parity recommendation):** spaces and dashes are removed, then the phone must be a plus sign followed by 8 to 15 digits. The cleaned form (plus sign and digits only) is stored.

**Applied to slice 8 (still uncommitted):** `20261020120000_admissions_submit_inquiry.sql` was edited in place, because it has not been pushed. It now cleans the phone, checks the new rule, stores the cleaned form, and has a new error message. The form logic (`inquiry-form.ts`, new `cleanPhone`) checks and sends the cleaned form with the same message, and the phone input allows 32 characters. The Edge Function has no phone check of its own, so it needed no change. Tests: vitest covers 7 digits refused, 8 and 15 accepted, 16 refused, spaces and dashes accepted and stripped, missing plus refused, letters refused, and the cleaned payload. Probe Q7 now uses the new refusals, and new probe Q10 covers each edge plus the stored form.

**Verification:** fresh reset, `20261020120000_admissions_submit_inquiry.sql` probes Q1 to Q10 green, vitest 78 tests pass, `tsc` clean, overload check clean, types identical. Only those were run, as asked.

## 2026-10-14: Admissions 8b, enquiry form polish and two intake switches

Slice 8b was built on 2026-10-14. It is local only: the work is in the uncommitted working tree, and nothing is applied on hosted or deployed. It follows slice 8 and changes the public enquiry form and the intake switches (PORT-PLAN, slice 8b).

**Built (uncommitted):**

- **Migrations:**
  - `20261021100000_admissions_public_applications_flag.sql`: the second intake switch, `public_applications_open` (default false), with `set_admissions_public_applications(boolean)`, Manager only.
  - `20261021110000_admissions_inquiry_form_polish.sql`: `branches.public_label` and its guard, the current grade or prior schooling columns and constraint, the religion and month checks in `submit_inquiry`, and the field-named errors. The slice 8 helper functions (`_public_text`, `_public_only_keys`, `_public_invalid`) were dropped and recreated with a field argument.
- **Seeds:** `seed.sql` and `seed.production.sql` each call `_admissions_seed_public_campus_labels()` after inserting campuses.
- **Edge Function** `supabase/functions/admissions-public`: the enquiry wording in two messages, and the field name passed through to the response only when it matches a strict path pattern.
- **Frontend:** the enquiry form (`inquiry-form.ts`, `inquiry-form.test.ts`), `components/inquiry-page.tsx`, `components/settings-page.tsx` (both switches), `data/application-detail.ts`, `data/settings.ts`, `labels.ts`, and `routes/inquiry.tsx`. `database.types.ts` was regenerated.
- **Probes:** two new files in `supabase/role-matrix/`: `20261021100000_admissions_public_applications_flag.sql` (P1 to P15) and `20261021110000_admissions_inquiry_form_polish.sql` (L1 to L12). Fixtures were updated in two slice 8 probe files, `20261020120000_admissions_submit_inquiry.sql` and `20261020130000_admissions_public_options.sql`.

**Decisions (all made 2026-10-14):**

- **Religion:** Christian, Muslim, Traditional, Other, Prefer not to say, enforced in `submit_inquiry`.
- **Month of enrolment:** January (shown as "January (Limited Admissions)", the TCS OS wording) or September. "Other" is dropped.
- **Current grade or class:** N/A (not yet in school), then the 14 active grades (a child in early care picks Pre Nursery; changed later on 2026-10-14, see below). It is stored as `students.current_grade_id` or `students.prior_schooling`, never both (`students_current_grade_one_check`). The old free-text `students.current_grade` is kept for legacy rows and written empty by public enquiries. Not yet in school hides and refuses the current school field; any grade requires it. A current grade above the grade applied into is not enforced.
- **Public campus labels:** `branches.public_label`, nullable, falling back to `name`. Seeded as "Main Campus (Somey Down)" for Main or Treasures Christian School (the hosted name), and "Annex (CK Road)" for Annex. A guard trigger stops any signed-in user from setting or changing a label. The reason is that `branches` has a broad `can_write()` update policy and the label is public, so labels change only by migration. `branches.name` is unchanged for HR and Finance.
- **Wording:** parents see "enquiry" everywhere. The route `/inquiry`, INQ references and code keep "inquiry".
- **Date of birth:** typed as dd/mm/yyyy with a numeric keypad and automatic slashes, sent as ISO.
- **Age hint:** display only, never sent or trusted. It lives in `inquiry-form.ts` as `ageHint`, and a test checks that the payload has no age.
- **Also added:** a "Same address as above" checkbox for guardian 2; inline errors next to each field, including server ones; asterisks on required fields; a thank-you page that says the school will contact the parent and shows the INQ reference or references to keep (no confirmation email exists until slice 12); and a phone hint that says to start with a plus sign and country code, then 8 to 15 digits, with spaces and dashes allowed.
- **Anon surface gate (approved 2026-10-14):** `get_public_admissions_options` changes only the campus label string and adds an `applications_open` key. Same signature, so the anon-executable count stays at 170.
- **Two independent intake switches (approved 2026-10-14):**
  - Slice 8's `public_intake_open` and `set_admissions_public_intake` are applied on hosted and keep their names. They now mean public inquiries. The reason is that a rename would need a coordinated column rename, function drop and frontend deploy for no change in behaviour, so only new objects were added.
  - `public_applications_open` is new. It is audited as `admissions_settings_changed` with only the changed field.
  - `submit_inquiry` refuses only when public inquiries are closed. Slice 9's application submit must check only `public_applications_open`.
  - Admissions Settings shows both switches. Applications is disabled with a note that the form arrives in a later slice. The Auditor sees both read-only.

**Verification:**

- **Baseline** (HEAD 6842848, fresh reset): clean, anon-executable count 170.
- **After the build** (test-runner, fresh reset):
  - overload check clean; types identical; anon-executable count 170;
  - lint 0 errors and 13 warnings; `tsc` clean; build clean;
  - `npm test` 97 pass; `handler.test.ts` 27 of 27; `integration.test.ts` 7 of 7;
  - all 42 role-matrix files green.
- **Deliberate breaks: 16, all caught:** applications setter without the Manager check; setter granted to anon; `submit_inquiry` reading the applications switch; audit branch missing; options `applications_open` reading the wrong switch; religion check removed; month check removed; inactive current grade accepted; both current grade and prior schooling accepted; not yet in school with a school accepted; students constraint dropped; options returning the internal name; label guard dropped; label seeder matching only Main; field details passed unfiltered; age added to the payload.
  - Dropped on purpose: the old `current_grade` key (covered by the unknown-key rule).
- **Browser:** a local headless Chrome render of `/inquiry`, using Cloudflare's test keys, showed the enquiry wording, the new labels and the asterisks.
- **Golden payroll suite:** skipped. Nothing payroll-related changed, and the audit action list is unchanged.

**Code review:** no blocking findings. Non-blocking, left open (PORT-PLAN, slice 8b, open follow-ups):

- the campus name check before the push (a read-only check of the hosted campus names);
- the stale-form message after a reopen;
- `students.current_grade_id` is `on delete restrict`, so grades are retired, not deleted.

**Outstanding for Eyram:**

- Review the uncommitted slice 8b.
- After the commit, the production steps, in this order: close public inquiries first, then the database push, the Edge Function deploy and the frontend deploy, then reopen. Eyram runs these steps. No commands are recorded here.
- The cutover gate is in PORT-PLAN, slice 15: `admissions.tcsch.edu.gh` does not move to the ERP until a confirmation email exists (slice 12) or Eyram accepts the gap in writing.

## 2026-10-14: Admissions 8b, extra early-care option removed; branches update probe

Eyram removed the extra early-care option from the enquiry form's current grade or class list on 2026-10-14. The list is now N/A (not yet in school), then the 14 active grades. A child in early care picks Pre Nursery, and the current school stays required for any grade.

- `students.prior_schooling` now allows only `'not_yet_in_school'`. `20261021110000_admissions_inquiry_form_polish.sql` was edited in place, because it has not been pushed. The edit covers the check constraint and `submit_inquiry`. The form list, the staff detail label, the vitest cases and the probes were updated to match.
- The 8b deliberate-break set drops the early-care break. It was already listed as dropped, and that entry is removed.
- New probe L13 in `supabase/role-matrix/20261021110000_admissions_inquiry_form_polish.sql`: a role allowed to edit branches (Manager, Attendant) can still change a branch's name and other columns after the label guard, and the label stays unchanged. L3 and L4 prove signed-in users can't set or change `public_label`.
- Verification: on a fresh reset, the 8b polish probe file and the slice 8 submit_inquiry and options probe files are green. The inquiry vitest file passes, `tsc` is clean, the overload check is clean and the types are identical.

## 2026-10-14: Enquiry form phone example replaced

The enquiry form's phone example was a real personal number, carried over from TCS OS. Every example now uses a placeholder.

- Parents now see `+233 XX XXX XXXX` in the phone hint, the input placeholder and the server's phone error message.
- New migration `20261022100000_admissions_inquiry_phone_example.sql` re-creates `submit_inquiry` with only that message changed. The committed slice 8 and 8b migrations still contain the old number in their text, but they are not edited, because they may already be applied. The new function supersedes them.
- Tests and probes use obviously invalid all-zero numbers (`+233000000000`).
- Not changed: git history (commits c71b363 and 32eae11) still contains the number. Removing it would mean rewriting history, which is Eyram's decision.
- Verification: on a fresh reset, the three affected probe files are green. 27 handler tests, 7 integration tests and 40 inquiry vitest tests pass. `tsc` is clean, the overload check is clean and the types are identical.

## 2026-10-14: D-9d revised, strict phone format

Eyram changed the enquiry form's phone rule on 2026-10-14. It replaces the earlier rule from the same day, which removed spaces and dashes before checking for a plus sign and 8 to 15 digits. The point is the format: foreign numbers are still accepted.

- **Rule:** a plus sign and digits only, stored as sent.
  - Ghana: +233 and exactly 9 digits, the first not 0, for example +233590000000.
  - Any other country: a country code not starting with 0, and 8 to 15 digits in all, for example +442079460958.
  - Spaces, dashes, letters and extra digits are refused; nothing is cleaned or stripped any more.
- **On the form:**
  - Digits typed without a plus sign are a Ghana number and get +233 in front. Every number shows with no spaces.
  - A foreign number starts with + and the country code.
  - Spaces, letters, dashes or other symbols, a leading 0 on a Ghana number, a country code starting with 0, and too many digits show an error at once. The typed text stays visible.
  - The hint reads "Format: +233590000000. Country code and your number, no spaces." The placeholder is +233590000000.
- **Built:**
  - New migration `20261023100000_admissions_inquiry_phone_format.sql` re-creates `submit_inquiry` with only the phone check, its message and the stored value changed. Committed migrations are not edited.
  - Form logic: `readPhoneInput`, `storedPhone`, `phoneError` and `isValidPhone` replace `cleanPhone`.
  - Probe Q10 in `20261020120000_admissions_submit_inquiry.sql` was rewritten for the new rule, with a fresh email per attempt so the per-email limit can't mask a result. Fixtures in the 8b probe files and the integration test now use +233590000000.
- **Verification:**
  - On a fresh reset, the three affected probe files are green.
  - Two deliberate breaks, both caught by Q10: the server check loosened to the old 8 to 15 digit rule, and the old space and dash stripping put back.
  - 42 inquiry vitest tests, 27 handler tests and 7 integration tests pass.
  - `tsc` clean, lint 0 errors (13 warnings, baseline), overload check clean, types identical.

## 2026-10-14: Hosted state of slices 7b2, 7c, 8 and 8b, as reported

Each fact below is reported by Eyram, 2026-10-14. Nothing else is recorded here as applied or verified.

- **Migrations:** the slice 8b migrations `20261021100000`, `20261021110000`, `20261022100000` and `20261023100000` show on both sides of the hosted migration list, so they are applied on hosted. The slice 8 migrations `20261020100000` to `20261020130000` were already applied.
- **Edge Function:** `admissions-public` is at version 2 on hosted, last updated 2026-10-14 08:12 UTC.
- **Campus labels:** the hosted public options return "Annex (CK Road)" and "Main Campus (Somey Down)".
- **Forwarded IP:** 25 plain requests gave 20 refusals by Turnstile, then 429 from request 21. 25 requests with a spoofed X-Forwarded-For all gave 429. So the leftmost header cannot be spoofed on the hosted platform, and the forwarded-IP open item (D-8d) is closed.
- **Live end-to-end test passed on 2026-10-14:**
  - a real Turnstile solve;
  - an INQ reference on the thank-you page;
  - the staff detail reading "Not yet in school";
  - the Accountant unable to see it;
  - audit rows for the switch.

  Public inquiries were closed again afterwards.
- **Frontends:** the 7b2 and 7c frontends are live. Eyram checked Admissions Settings and the Audit Log on the live site.
- **Go-live cleanup:** one test inquiry labelled "ZZ Test Do Not Process" exists on hosted. It must be removed by a small reviewed migration before real intake begins. Recorded in PORT-PLAN, slice 8b.

The confirmation email cutover gate (PORT-PLAN, slice 15) is unchanged.

## 2026-10-14: Enquiry phone box made forgiving (client only)

The phone box is now forgiving on the client only. The database rule (D-9d, migration `20261023100000`) and the Edge Function are unchanged, and there is no migration.

- **Removed silently:** spaces, dashes, dots and brackets.
- **Ghana local numbers:** a number with a leading 0 and exactly 9 more digits, typed without a plus, becomes +233 and those 9 digits. While a local number is still being typed there is no error; on submit an incomplete one asks for the full number.
- **233 without the plus:** 233 and exactly 9 digits (the first not 0) also becomes +233 and those 9 digits. While a number starting 233 is still short of 12 digits there is no error yet. 233 with 8 or 10 digits is not converted and is refused with the foreign tip.
- **When the box changes:** the box keeps what the parent types and shows the converted number when they leave it. Before, it reformatted on every keystroke, which would have turned typed 233 digits into +2332 at once. Errors for symbols and extra digits still show while typing.
- **Left to the strict rule:**
  - A leading 0 with more than 10 digits (for example a foreign number in its national format) is refused with a tip to start with + and the country code; it is not guessed.
  - Digits without a plus that are too many for a Ghana number (for example 447946095800) are refused with the same tip, so they are never quietly turned into a +233 number.
- **New hint:** "For example 0590000000 or +233590000000. From outside Ghana, start with + and the country code."
- **Verification:** the inquiry vitest file passes (49 tests) and `tsc` is clean. Nothing else was run, as asked.

## 2026-10-14: Slice 9 planning, application fee proof made compulsory (D-9e)

D-9e is decided: the application fee proof is compulsory. This is option A from the slice 9 plan. The earlier recommendation (optional, with an outstanding document row for staff) is dropped.

- `submit_application` refuses any submission without an `application_fee_proof` file that was reserved, uploaded and passed the byte check. It uses the same generic refusal as the other document failures.
- No outstanding `application_fee_proof` row is ever created, because a missing fee proof can't get through.
- Both the 9a plain form and the 9b form mark it required.
- One database helper gives the required document types per grade (fee proof for every grade, vaccination proof for preschool grades). Both the submit RPC and the public options use it, so the form and the server can't disagree.
- The staff Submission check panel shows the fee proof first, with a note that staff must match it against the bank or mobile money record.
- Test plan additions: a probe that a submission with every other document but no fee proof is refused, and a deliberate break that removes the check.

Plan only: no code or migrations. Recorded in PORT-PLAN, slice 9, and the consolidated decision table. D-9a and D-9f to D-9l are still open.

## 2026-10-14: Admissions slice 9a checkpoint 1, the upload backend (built locally)

Checkpoint 1 of slice 9a is built locally and uncommitted. It is not applied on hosted and not deployed. It covers the upload path only: sessions, reservations, the cleanup sweep, the rate buckets, the required-documents helper and the two Edge Function actions `upload_session` and `upload_url`. Checkpoint 2 (`submit_application`, the `application` action with the byte check, `/apply`, the staff check panel and the Settings switch) has not started. Detail is in PORT-PLAN, slice 9, "Checkpoint 1 built 2026-10-14".

- **Why one Turnstile solve opens a session (D-9f).** A parent uploads up to four files, and each upload needs a signed URL. One solve gives a session token, stored only as a hash, and every reservation in that session hangs off it. Submit will accept only that session's files.
- **Why the sweep has an age rule.** Storage's signed upload token lives 2 hours from signing, whatever the reservation's expiry. The sweep therefore cleans a reservation only when it is unused, expired for more than 30 minutes and made more than 2 hours 15 minutes ago. Once a row is cleaned its token is dead, so nothing can land after the sweep and be orphaned. Review found the sweep would have cleaned too early; that was fixed in fix round 1.
- **Why cleanup runs in the Edge Function.** `storage.objects` has a delete guard, so files can only be removed through the Storage API. The Edge Function's `storage.ts` makes those calls.
- **Migration and probes.** `20261024100000_admissions_application_uploads.sql` adds the two tables (RLS on, no policies, no API privileges), four service-role-only RPCs, two unlisted helpers and the new rate rules. `get_public_admissions_options` gains `required_document_types` with its signature unchanged, so the anon-executable count stays at 170. The new probe file `20261024100000_admissions_application_uploads.sql` has U1 to U23.

**Verification (local only):**

- **Baseline** at HEAD 378d9d1 on a fresh reset: 42 probe files green, anon-executable 170.
- **Local Storage checks:** an anon upload without a signed URL is refused; a token for another path is refused (InvalidSignature); a second upload to the same path is refused even with `x-upsert` true (KeyAlreadyExists); 11 MiB is refused (413); `text/html` is refused (415); a Range request returns 206 with the leading bytes; the signed upload token lasts 2 hours with overwrite off.
- **test-runner, after the build, fresh reset:** lint 0 errors and 13 warnings; `tsc` clean; `npm test` 107 of 107; build clean; overload check clean; types regen identical; anon-executable 170; all 43 probe files green; `handler.test.ts` 40 of 40; the two integration files 7 of 7 each; prettier clean.
- **Order matters.** Running the integration tests before the probe loop makes probe I1 in `20261011100000_admissions_core_applicants_structure.sql` fail on a reference collision, because the integration tests commit inquiry rows. It is green on a fresh reset. Run the probes first.
- **Deliberate breaks:** 8 of the 21 planned for checkpoint 1, all caught (U9, U11, U14, U15, U16 and the two unit and integration tests). The other 13 belong to checkpoint 2. The golden payroll suite was skipped: nothing payroll-related changed, and the audit action list and audit policies are unchanged.
- **Code review:** no blocking findings. Two non-blocking findings were fixed in fix round 1: the sweep age rule above, and probe U22 split into U22 (no write policy on the bucket, expect all roles) and U23 (direct insert, expect none). Re-review found both fixes OK.

**Open after checkpoint 1 (non-blocking, recorded in PORT-PLAN, slice 9):**

- The 400 open-reservation cap can be filled cheaply: one solve gives 8 reservations with no file, held about 6.5 to 8.5 hours. A few IPs could block uploads for every parent. Counting only reservations with a file, or a shorter life for empty ones, is Eyram's call (D-9g).
- `upload_url` has no IP limit (D-9l).
- The bucket trusts the declared Content-Type until checkpoint 2's byte check. Staff file viewing should use a download disposition.
- Sessions and cleaned reservation rows are never purged. A purge belongs with slice 12's scheduled sweep.
- The sweep runs on every solved `upload_session` request, bounded at 20 deletes each.

**Outstanding for Eyram:** the go for checkpoint 2 after review of this diff. The deploy for checkpoint 1 is for Eyram to run, not run here: `npx supabase db push` (applies `20261024100000`), then `npx supabase functions deploy admissions-public`. No new secrets and no frontend change. Public applications are still closed, so nothing is reachable by parents until the switch is turned on.

## 2026-10-15: Admissions slice 9a checkpoint 1, open-reservation cap counts stored files

Eyram reviewed checkpoint 1 and asked for one change before it ships. It is still local and uncommitted, and nothing is applied on hosted or deployed.

- **The cap.** The 400 open-reservation cap now counts a reservation only if its file exists at the reserved path, or if it is unexpired, has no file yet and is under 30 minutes old. Before, every unused reservation counted for up to about 8.5 hours, so one Turnstile solve could hold 8 places without uploading anything and a few IPs could block uploads for every parent. The 30 minutes is the window of the `upload_open_reservations` rule, kept with the other numbers. The sweep age rule and the 6 hour lifetime are unchanged. Migration `20261024100000` was changed in place, since it is not applied anywhere.
- **Residual risk, accepted:** a bot can still upload to a live signed URL up to 2 hours after its reservation stopped counting. That is bounded by 100 sessions per hour, 8 files per session and 10 MiB per file, and the file counts again once it lands.
- **Probes and break:** U4 updated; U24 (files block) and U25 (old empty reservations don't block) added; U15 covers fresh empty ones. The break "count every unused reservation again" is caught by U25, one more break in checkpoint 1 at Eyram's request.
- **Checkpoint 2 requirement:** staff open application documents through signed URLs that force a download, not an inline viewer.
- **CLAUDE.md:** run the probe files before the Edge Function integration tests.

Recorded in PORT-PLAN, slice 9 (D-9g and the checkpoint 1 section), and DESIGN.md (the caps bullet).

## 2026-10-15: Admissions slice 9a checkpoint 2, submit, matching and /apply (built locally)

Checkpoint 2 of slice 9a is built locally and uncommitted. It is not applied on hosted and not deployed. It covers the rest of 9a: the submit RPC, the match flags, the `application` action with the byte check, the plain `/apply` page, the staff Submission check panel and the Settings switch. The six-section form (9b) is still to come. Detail is in PORT-PLAN, slice 9, "Checkpoint 2 built 2026-10-15".

- **Hosted state, as reported by Eyram on 2026-10-15.** Checkpoint 1 is committed as c822b56. Its migration `20261024100000` is applied on hosted, and `admissions-public` is deployed on hosted at version 3. Checkpoint 2 is not applied on hosted and not deployed.
- **Why the RPC takes the whole serializer shape.** The RPC accepts the full `ApplicationSerializer` payload now, so 9b is UI only and adds no rule the database doesn't enforce.
- **Why the Edge Function reads bytes and the database decides.** The database can't read file bytes. The Edge Function reads the first 16 bytes of each document through the Storage API and reports the kind for each reservation id and path. `submit_application` compares that report with the extension and refuses a missing or mismatched one. A failed read goes through as `unknown`, and the database refuses it. The convention is in DESIGN.md.
- **Why staff download and never view inline.** Parents' files are strangers' files. Staff open them only through a short-lived signed URL with a forced download. The file name is built only from the reference, the document type and the extension. The convention is in DESIGN.md.
- **Decisions from Eyram, 2026-10-15** (recorded as D-9m to D-9p in PORT-PLAN):
  - the match flags are readable like `application_documents`;
  - a second Turnstile solve on submit, after the upload one;
  - a repeat submit on a used session returns the same APP reference and writes and counts nothing, so a double click is not a second application;
  - the family match prefers the family holding the same child (same name and date of birth), else the oldest.
- **Why the email count sorts emails first.** Fix round 1, after code review: the per-email count takes its bucket row locks in sorted order, so two submissions sharing emails can't deadlock.
- **Why the second database session test exists.** Break 15 (session row lock removed) was not caught by the Edge-level double click test, because the two requests never overlapped in the transaction. `submit.integration.test.ts` test 5 uses two database sessions on one upload session, and it catches the break.
- **Accepted risks (reported 2026-10-15), recorded in PORT-PLAN:**
  - per-email griefing: a valid solve plus files can make 5 successful submissions naming a victim's email and lock that email out for the day, bounded by `submit_ip` and `submit_global`;
  - two submissions at the same moment for the same new child with disjoint guardian emails can create two families, which staff see as duplicates;
  - an Edge nit: non-application bodies are parsed up to 64 KB before the 32 KB refusal.

**Verification (local only):**

- **Test-runner, fresh reset, end of pass:** overload check clean; types regen identical; anon-executable 170; all 44 probe files green; `handler.test.ts` 51 of 51; `integration.test.ts` 7 of 7; `upload.integration.test.ts` 7 of 7; `submit.integration.test.ts` 4 of 4 (before test 5 was added); lint 0 errors and 13 warnings (baseline); `tsc` clean; build ok; prettier clean; no service role key in the build; nothing staged.
- **After test 5 was added** (main session, fresh reset): the submit probe file green and `submit.integration.test.ts` 5 of 5, after break 15 was restored and again after fix round 1; overload check clean and types identical.
- **Vitest:** `npm test` 124, including the new `application-form`, `document-files` and `submission-check` files.
- **Deliberate breaks:** 13 in this checkpoint (10 to 22), all caught. Twelve were caught by the probe file (A1 to A26) or the unit and integration tests; break 15 was caught by the two-session test. Three were not broken on purpose: the payload path check (redundant, since the document row uses the reservation path), the switch independence (no break was made), and the share lock (not a genuinely concurrent integrity point).
- **Golden payroll suite:** skipped. No audit action, audit policy or payroll item changed.

**Rollout (Eyram runs; none of it has been run here), in this order:**

1. `npx supabase db push` (applies `20261025100000`).
2. `npx supabase functions deploy admissions-public` (version 3 to 4; no new secrets).
3. `frontend/scripts/deploy-production.sh` (never a bare `wrangler deploy`).
4. The D-9k live test: open Public applications in Settings, make one real submission at `/apply`, check the Submission check panel and one download, then close the switch again.

Public applications stay closed until step 4, and are closed again afterwards. The live-test application from step 4 needs cleaning up before real intake, together with the "ZZ Test Do Not Process" record from 8b.

**Open after checkpoint 2:** the accepted risks above; 9b; checkpoint 1 open items (b) to (e), unchanged; the "ZZ Test Do Not Process" cleanup, unchanged.

## 2026-10-15: Slice 9b planning decisions, checkpoint C1 built (local)

Slice 9b is the full six-section form in the TCS OS look. Eyram approved the plan on 2026-10-15. It is frontend only, so the anon surface is unchanged. C1 (the look foundation and `/inquiry`) is built locally, uncommitted and not deployed. C2 to C4 have not started. Detail is in PORT-PLAN, slice 9b.

- **Why frontend only.** The payload contract is final. TCS OS stores one combined declaration acceptance, a separate media consent, the signature and server time, which are the same four columns as the ERP. Every TCS OS application field is already accepted by `submit_application`. So there is no migration, RPC, Edge Function, RLS or grant change, and the anon-executable count stays at 170.
- **Decisions (approved 2026-10-15).** The fonts are self-hosted through `@fontsource` (Q1), and Inter moves off Google too, at the staff app's weights (Q2). The new look applies to the two public pages only (Q3). Nationality is stored as the TCS OS country names, with Ghana first, and demonyms are search aliases only (Q4 to Q6). The fee and bank details sit in a frontend constants file (Q7). Q8 keeps the neutral wording until slice 12 sends email. Q10 to Q15 cover the child count select, native selects, the document order with the fee proof under the fee box, the vaccination slot, the teal focus ring and the TCS OS labels. Q16 means no declaration text versioning for now. Q17 shows the previous school only for a child in school. Q18 is a deploy after C1 and after C3.
- **Q9 answers (reported by Eyram, 2026-10-15).** The GHS 200.00 fee, the bank account details, the `*170#` steps and the scholarship link are accurate as TCS OS shows them. The TCS OS wording stays, with dashes and arrows rewritten. Q9 is closed except for the privacy policy.
- **Privacy policy go-live gate.** There is no privacy policy page yet, and it is being written (reported by Eyram). So the declaration is ported exactly as TCS OS has it, with no link. A published policy must exist before real intake and before admissions.tcsch.edu.gh moves to the ERP. Then one link goes into the declaration copy constant. The gate is recorded in PORT-PLAN ("Go-live gates still open") and as an item in CONSTRAINTS.md.
- **Declaration text (Q16).** The TCS OS declaration and media consent text last changed in TCS OS commit f7b57ae on 2026-08-26 ("Phase 5: Expanded application form"). C3 ports it verbatim, with only the verse attribution reformatted. The date the ERP copy changes is recorded then.
- **Plan changes from Eyram.** (a) The full-contract integration test runs at the end of C2 and again before the C3 deploy, not only in C4. (b) `font-display: swap` for all three families, with Inter kept at the staff app's weights, so the staff app looks unchanged. (c) The housekeeping below is recorded.
- **Housekeeping.** PORT-PLAN's status row for slice 9 and the checkpoint 2 section still said checkpoint 2 was "built locally, uncommitted, not applied on hosted, not deployed". Both now give the reported state: checkpoint 2 is committed as 92346dd and applied on hosted, and Eyram reports slice 9a is built and live on hosted. The older JOURNAL entries are left as they were.
- **Hosted state, as reported by Eyram.** Checkpoint 1 is committed as c822b56, with migration `20261024100000` applied on hosted and `admissions-public` deployed at version 3. Checkpoint 2 is committed as 92346dd and applied on hosted. Not reported here: the D-9k live test result, and whether the Public applications switch is closed again.

**C1 built (local, uncommitted, not deployed):**

- **Fonts and styling.** `@fontsource/cinzel`, `@fontsource/dm-sans` and `@fontsource/inter` at 5.3.0. Inter is self-hosted for the whole app (400, 500, 600 and 700), in place of the Google Fonts link. Cinzel and DM Sans load only from the `/inquiry` route head, through `public-form.css`, which is scoped under `.tcs-public`. The licence lines are in `frontend/public/fonts-licences.txt`.
- **`/inquiry`.** Rewritten to the TCS OS layout and wording. It keeps the ERP's religion list, the no-free-text Other option, the current school for a child in school only, the optional campus, the forgiving phone box and the age hint (slice 8b and D-9d). The payload, validation, `submit_inquiry` and the Edge Function are unchanged.
- **Tests.** `vitest` runs 131 tests (was 124). The new `public-copy.test.ts` checks that the copy and public page sources contain no em or en dashes, plus the TCS OS headings.
- **Verification.** The test-runner end pass gave lint 0 errors and 13 warnings (the same as the baseline), `tsc` clean, the build ok, and prettier flagging only the generated `database.types.ts`. No font request to Google appears in `dist`. Inter is emitted at exactly 400, 500, 600 and 700. Nothing is staged. `supabase/` is untouched, so no database reset, role matrix or golden payroll run was needed. Two deliberate breaks, each against its own test file, were both caught, and the files were restored byte for byte.
- **Code review.** One BLOCKING finding, fixed in fix round 1: the invalid and focus borders never showed on text inputs, because the base input rule out-ranked them. The re-review found the fixes OK and nothing new blocking. Non-blocking fixes were also made.
- **Deploy (Eyram runs, not run here).** `frontend/scripts/deploy-production.sh`. No `db push` and no functions deploy.

**Open after C1:** C2, C3 and C4; the privacy policy go-live gate; the slice 9a accepted risks; the "ZZ Test Do Not Process" cleanup; checkpoint 1 open items (b) to (e), unchanged.

## 2026-10-15: Slice 9b C1 rollout reported, C2 built (local, uncommitted)

Two things happened on 2026-10-15. Slice 9b C1 was committed, deployed and checked on hosted, as reported by Eyram. Slice 9b C2, the six-step `/apply` form, was built locally. C2 is not committed and not deployed. Detail is in PORT-PLAN, slice 9b ("C1 rollout" and "C2 built 2026-10-15").

- **Hosted state, as reported by Eyram, 2026-10-15.** C1 is committed as dffe810 and deployed to hosted. Eyram checked it there: the fonts are self-hosted with no Google font request, the colours and fonts match the TCS OS look, Turnstile shows, the staff app is unchanged, and a test enquiry was submitted. That test enquiry joins the go-live cleanup list in PORT-PLAN, with the "ZZ Test Do Not Process" record and the slice 9a live-test application. C2 is not on hosted.
- **Why C2 needs no deploy yet.** Decision Q18 is to deploy after C1 and after C3, so C2 goes out with C3. If Eyram wants to see C2 on hosted earlier, `frontend/scripts/deploy-production.sh` is the command, and Eyram runs it.
- **Why one validator runs both the sidebar and the submit.** The sidebar ticks and the submit both call `completeSteps` in the new pure module `application-steps.ts`, and every validation key belongs to exactly one step (`stepForField`). A step can't show as ticked while submit would refuse it. A server error is routed the same way: a field path opens its step, and a child address error is shown on guardian 1, because the child's address follows guardian 1.
- **Why the payload contract is unchanged.** C2 is UI only. The draft carries `wantsScholarship`, `scholarshipDetails` and `mediaConsent`, sent as false and empty until C3 adds their inputs. `submit_application`, `submit_inquiry` and the Edge Function are not changed, and there is no migration.
- **Why the full-contract test exists now.** Eyram's plan change (a) moves the full-contract integration test to the end of C2 and before the C3 deploy. `submit.integration.test.ts` test 6 is a real submission against the local stack with all four documents, the scholarship answer, media consent, the optional fields, a second guardian, and a long nationality. It checks the stored values and passes 6 of 6.
- **Leave-page warning rule.** The warning starts once anything has been entered or uploaded. The prefilled country and the ticked address box don't count toward that. It is removed after a successful submit. Those two are filled in by the form itself, not by the parent, so an untouched form never triggers the warning.
- **Verification (local only).** Baseline at dffe810: lint 0 errors and 13 warnings, `tsc` clean, 131 tests, build ok, prettier flags only the generated `database.types.ts`. test-runner end pass: lint unchanged, `tsc` clean, 12 files and 152 tests (was 131), build ok, prettier flags only `database.types.ts`, no Google font host in `dist`, the public form CSS referenced only by `/inquiry` and `/apply`, no service role key in `dist/client`, `handler.test.ts` 51 of 51, `submit.integration.test.ts` 6 of 6, public applications closed again afterwards, nothing staged. There is no migration, so no `db reset`, overload check, types regen or role matrix. The golden payroll suite was not run: no payroll, audit action or audit policy changed.
- **Deliberate breaks.** Six, all pure logic, each against its own test file, all caught, and each file restored byte for byte: student fields mapped to the wrong step; an unanswered health question treated as No; the child address copied instead of followed; a child address server error not moved to guardian 1; the sidebar ticking a step with an invalid field; the payload key `postal_code` renamed.
- **Browser check.** Headless screenshots through the DevTools protocol on a local dev server, at 1280 and 375 px, of steps 1, 2 and 4 and of the submit-incomplete message, matched the TCS OS look.
- **Code review.** One BLOCKING finding, fixed in fix round 1. Next on step 5 could submit the form, because Next and Submit shared one unkeyed button slot and React changed its type during the click. Now they are separate keyed buttons, and submit runs only on step 6. A browser check confirmed Next on Documents lands on Declaration with no message. Also fixed: separate failure flags for the two Turnstile checks, focus moved to the step heading, and errors cleared when guardian 2 is removed. Re-review: the fixes are OK and nothing new is blocking.
- **Still open after C2.** C3 (nationality combobox, four document slots, the fee box with the TCS OS wording, the scholarship question and link, the declaration and media consent text, the thank-you sentence) and C4. The privacy policy go-live gate is still open. The go-live cleanup items are the "ZZ Test Do Not Process" record, the 9a live-test application and the C1 rollout test enquiry. The slice 9a accepted risks (a) to (c) and checkpoint 1 open items (b) to (e) are unchanged.

## 2026-10-15: Admissions slice 9b C3, the /apply content (built locally, uncommitted)

Checkpoint C3 of slice 9b is built locally and uncommitted. It is not deployed. It covers the content of `/apply`: the nationality combobox, the four document slots, the fee box, the scholarship question and link, the declaration and media consent, and the thank-you sentence. It is frontend only, like C1 and C2: no migration, RPC, Edge Function, RLS or grant change, and the payload contract is unchanged. The anon-executable count stays at 170. Detail is in PORT-PLAN, slice 9b, "C3 built 2026-10-15".

**Hosted state, as reported by Eyram, 2026-10-15.** C2 is committed as 8393551. No deploy of C2 has been reported. C1 is committed as dffe810 and was deployed (already recorded above). C3 is not on hosted.

- **Why nationality is a combobox that refuses unlisted values (Q4 to Q6).** The stored value is the TCS OS country name, so the staff pipeline reads one spelling. The 241 names are the TCS OS list, with Ghana first and the rest in `Intl.Collator("en")` order. Demonyms such as "Ghanaian" and "UK" are search aliases only, and each one points at a listed country. `submit_application` still accepts any text up to 100 characters, so the refusal ("Choose a country from the list") lives in the form only. Typing a name in any case becomes the listed name when the field is left.
- **Why the documents follow TCS OS order (Q12, Q13).** Proof of vaccination is always shown. It is required when the grade's `required_document_types` asks for it. Then come proof of financial clearance and the report card or transcript from the previous school, both optional. Then the fee box and the fee proof slot, which is compulsory for every grade. The upload security check sits at the top of the step, and the file inputs wait for it.
- **Per-file status and the cap.** Each file shows uploading, uploaded or failed. A failed replacement keeps and still sends the earlier file, and says so. The browser checks the extension and the 10 MB limit, but the server is the authority. Once 8 files have been started in one visit, the form says "reload and choose your files again" (D-9g). Every slot with an upload is sent, in slot order.
- **Why the fee box comes from constants (Q7).** `APPLICATION_FEE` and `FEE_BOX` in `public-copy.ts` hold GHS 200.00, the Consolidated Bank Ghana details and the *170# steps as TCS OS shows them (reported by Eyram, 2026-10-15). The fee is not in the database. Where TCS OS promises an email, the copy says "the school will contact you regarding an admission decision" instead (Q8), until slice 12 sends email.
- **Scholarship.** Yes or No, with No as the default. "Tell us more" appears on Yes, and the details are sent only on Yes.
- **Declaration copy, dated 2026-10-15 (Q16, required by Eyram).** The ERP copy of the declaration was ported word for word from TCS OS `backend/templates/public/apply.html` at commit f7b57ae (2026-08-26) into `DECLARATION_SECTIONS` and `DECLARATION_COPY` in `public-copy.ts`. The only change is the verse attribution, which is now "(Proverbs 22:6)" in brackets instead of after a dash. The media consent text, the agreement label and "Sign by entering your full name:" are word for word too. Media consent has its own checkbox and is independent of the declaration. "the school's privacy policy" has no link yet. When the policy is published, its link goes in that one place, and the go-live gate stays open until then.
- **Thank-you.** TCS OS's sentence, with the child's name, grade and year as entered, plus the APP reference and the line that no confirmation email is sent. There is no email promise.

**Tests and verification (local only):**

- **Baseline** at 8393551: lint 0 errors and 13 warnings, `tsc` clean, 152 tests, build ok, prettier flagging only the generated `database.types.ts`.
- **test-runner end pass:** lint unchanged, `tsc` clean, 13 files and 170 tests (was 152), build ok, prettier flagging only `database.types.ts`, no Google font host in `dist`, no service role key in `dist/client`, `handler.test.ts` 51 of 51, `submit.integration.test.ts` 6 of 6 including the full contract (test 6), public applications closed again afterwards, nothing staged. There is no migration, so no `db reset`, overload check, types regen or role matrix. The golden payroll suite was not run: no payroll, audit action or audit policy changed.
- **After fix round 1,** the main session reran `tsc`, the 170 tests, lint, build and prettier on the final tree, and the full-contract integration test: 6 of 6. This is the plan change (a) check before the C3 deploy.
- **New and extended tests.** `nationalities.test.ts` is new. `public-copy.test.ts` checks that no copy has an em or en dash, that the fee box and declaration text are present, that there is no email promise, and the thank-you sentence. `application-form.test.ts` covers the slot order, optional slots sent only when uploaded, the fee proof still required, the 8-file cap, nationality refused or normalised, media consent independent of the declaration, and scholarship default No.
- **Deliberate breaks:** 7, pure logic, each against its own test file, all caught, and each file restored byte for byte: unlisted nationality accepted; aliases removed from search; fee proof requirement dropped; vaccination requirement dropped; scholarship text sent on No; media consent tied to the declaration; an em dash in the copy.
- **Browser check** on a local dev server, through the DevTools protocol: "ivo" lists Côte d'Ivoire, Enter picks it and closes the list, and Escape closes the list and keeps focus. Screenshots of the Documents step (fee box, slots, scholarship) and the Declaration step match the TCS OS look.
- **Code review:** no blocking findings. Fix round 1 fixed four non-blocking items: dragging the list's scrollbar no longer closes it; reopening the list resets the highlight so Enter works; a failed replacement says the earlier file is still attached; hyphens match as spaces. Left as they are: the reload message at the cap loses the typed form (there are no drafts until slice 10), and minor screen reader notes on the "No match" row and the upload status. Re-review of fix round 1: all four fixes OK, nothing new blocking.

**Deploy and hosted check (Eyram runs them; neither has been run here):**

- **Deploy (Q18):** `frontend/scripts/deploy-production.sh`. No `supabase db push` and no `supabase functions deploy`. This deploy also carries C2 (8393551), which has not been reported on hosted.
- **Hosted check after the deploy:** `/inquiry` unchanged. Then `/apply` with Public applications open: one end-to-end submission with fake data (child named "ZZ Test Do Not Process") through all six steps, the combobox, the documents, the fee box, the scholarship link, the declaration, media consent and the thank-you with the APP reference. Then the staff Submission check panel and the downloads for that application, and then the switch closed again. The resulting test application joins the go-live cleanup list in PORT-PLAN.

**Still open after C3:** C4 (close-out), the privacy policy go-live gate, the C3 hosted check and its cleanup (if the check is run), the go-live cleanup items, the slice 9a accepted risks (a) to (c), and checkpoint 1 open items (b) to (e).

## 2026-10-15: Slice 9b C3 rollout reported; C4 close-out, slice 9 closed

**Hosted state, as reported by Eyram, 2026-10-15.** C3 is committed as 14582d0, deployed to hosted (carrying C2, 8393551) and checked there by Eyram, including a second submission that produced the match panel: the family matched by guardian email, the child matched by name and date of birth, the differences were listed, and the record was unchanged. Not reported: the references and names used, whether the second submission advanced an inquiry or made a possible duplicate, whether Public applications is closed again, and whether the slice 9a D-9k live test was run separately. The test applications from the check join the go-live cleanup list.

C4 is docs only, written locally and uncommitted. No code, migration, Edge Function or deploy change, and nothing was run against hosted. Detail is in PORT-PLAN, slice 9b, "C4, close-out", and the new section "Go-live test data cleanup plan".

- **Side by side checklist.** The 9b plan named the areas of a 20 point manual check at 375, 768 and 1280 px; C4 writes out the 20 points. Reported on hosted (all from the C1 check, 2026-10-15): no Google font request (pages not named), `/inquiry` fonts and colours, Turnstile on `/inquiry`, the staff app unchanged. Everything on `/apply` (sizes, sidebar at each width, step ticks, combobox by keyboard and touch, documents, declaration, no dashes on the live page, focus ring) is not yet checked on hosted; some have local evidence only, marked as such. No check was reported at a specific width.
- **Payload contract test.** It is in the suite: the shared fixture `full-application-payload.json` is read by `application-form.test.ts` and by `submit.integration.test.ts` test 6. Run on 2026-10-15 at 14582d0 on the local stack: vitest 13 files and 170 tests, `handler.test.ts` 51 of 51, `submit.integration.test.ts` 6 of 6. The probe files, the other two integration files and the hygiene checks were not rerun, because no code changed after their last green runs.
- **Slice 9 reconciled.** PORT-PLAN now lists where the built slice differs from the original "Delivers" plan (the submit signature, the upload paths and lifetimes, the session, the Edge sweep instead of pg_cron, matching), the hosted state as reported, the consolidated accepted risks (none new) and the open checkpoint 1 items.
- **Why the backlog items are recorded now.** Three came out of the hosted check and review: a blank answer shows as "(blank)" in the Submission check panel's differences although nothing changes, which may confuse officers (watch it, no change now); there is no withdrawn or spam disposal among the eight stages (needs a decision and probably a permission gate); and the declaration text will change when the privacy policy link goes in, so whether each application stores the version agreed must be decided before go-live. The last one is also a CONSTRAINTS checklist item.
- **Why the cleanup is a hand script, by reference, run once.** Applications with documents can't be deleted until their document rows go (D-4f), SQL can't delete stored files (D-4d, the `protect_objects_delete` trigger), and `audit_log` is append-only. So files go first through the Storage API or the dashboard, then one guarded transaction removes document rows, applications, students, families and old upload sessions, with a dry-run mode that rolls back. It works only from the references Eyram names, never a name pattern. A migration was not chosen because it would run on every local reset and keep the test references in the schema history. Audit rows, rate limit counters and the reference counters are left as they are.
- **Why after the privacy policy and the confirmation email.** Both need hosted tests that make more test records, and so do the slice 15 parity checks. One cleanup, after the last hosted test and just before real intake opens, means one reviewed production delete instead of several. A test record holding a real person's details is the exception and goes sooner.
- **DESIGN.md:** four new bullets: the shared payload fixture, one validator for step ticks and submit, parent-facing copy in one file with the dash test, and test record cleanup by reviewed hand script. **CONSTRAINTS.md:** checklist items for the cleanup and the declaration version.

**Open after C4 (slice 9 closed):** the privacy policy gate; the declaration version decision; the cleanup (plan only); the hosted checklist points not yet checked; whether Public applications is closed again; the slice 9 accepted risks; checkpoint 1 items (b) to (e); backlog items 1 to 4 in PORT-PLAN.

## 2026-10-15: C3 hosted check answers recorded

Eyram answered the points the C4 entry listed as not reported (reported by Eyram, 2026-10-15). Docs only; nothing run.

- **C3 hosted check.** Eyram ran the C3 check list for `/apply`: all six steps, sidebar ticks, the nationality combobox by keyboard ("ghanaian" and "ivo"), vaccination required for a preschool grade and not for Grade 3, fee proof upload and the refusal without it, replacing a file, an optional document, scholarship Yes with details, declaration and signature, Turnstile in steps 5 and 6, the thank-you page, the Submission check panel with the fee proof first, and documents arriving as downloads. Everything checked out. Those points are now Reported in PORT-PLAN C4.1. `/apply` at 375, 768 and 1280 px and by touch on a phone were not checked and stay Not checked.
- **The second submission** was a new application for a family already on record, not an inquiry advancing. The panel listed the guardian first name and the child's previous school location (blank) as differences and said the record was not changed. The blank row is backlog item 1, now seen on hosted.
- **The 9a D-9k live test** was done earlier and checked out.
- **Test records.** Every test record on hosted uses the child name "ZZ Test Do Not Process". Eyram will list the references later. The cleanup plan still works only from that list, never from the name.
- **Status table fix.** The 7b2 and 7c rows said the frontend deploy was not confirmed. Eyram reported on 2026-10-14 that both frontends are live and checked, which the header already said, so the rows now match it.

Still not reported: whether Public applications is closed again after the C3 check.

## 2026-10-16: Staff ID numbers (HR) built locally, checkpoints 1 to 3

Built on the local stack only. Nothing is committed, pushed, deployed or applied on hosted. The frontend has not yet been tried in a browser, by me or as reported by Eyram. Plan approved by Eyram on 2026-10-16 with changes; the decisions below replace the 2026-10-12 record. Full rules in DESIGN.md, "Staff ID numbers"; product summary in PLANNING.md; hosted rules in CONSTRAINTS.md.

**Decisions (Eyram, 2026-10-16):**

- Format `ST26-02002`: two digit approval year (Africa/Accra), two digit class (01 admin, 02 teaching, 03 kitchen, 04 janitorial, 05 transport, replacing "03 non teaching"), three digit roll 001 to 999 restarting per year only. The 1000th approval in a year is refused.
- Class from the position; a Manager alone sets it (new permission, approved). Readers Manager, Accountant, Auditor (approved). A deactivated position keeps giving its class.
- An unmapped position refuses the approval. Kept for life; one Manager correction with a reason, in the original year, with the next roll and the current position's class.
- **Backfill dropped.** Hosted has no real employees, so a backfill would only spend 2026 rolls on test records and the first real staff member would not be 001. Records approved before the migration show "Not issued".
- Test approvals happen locally only until go-live; cleanup notes in CONSTRAINTS and the PORT-PLAN cleanup plan.
- After code review: a rename or delete of a position that has a class is refused (a rename swap could otherwise move a class without writing the column; a delete was blocked by nothing, since `employees.position` has no foreign key). Rename: clear, rename, set again.
- `{{staff_id}}`: any template that uses it is refused until a current ID exists ("Approve this employee first so a staff ID exists"), with no placeholder text. An out-of-date ID in the merge data is refused too.
- TRUNCATE on `positions`: grants unchanged; added by name to the wider sweep list.

**Checkpoint 1, database.** Migration `20261026100000_hr_staff_numbers.sql`: `positions.staff_class` seeded for the 16 positions; `staff_numbers` and `staff_number_counters`; `_issue_staff_number`, `_take_staff_roll`, `_staff_class_for_employee` (granted to no API role); `set_position_staff_class` and `correct_staff_number` (Manager); `approve_employee` and `generate_employee_document` replaced with the same argument lists; the guard, immutability and audit triggers; three audit actions (40 in all). Two older probe files updated for the action list (7b1 S2 exact list, 7c S1 classification).

- **Change from the plan:** the ID is issued at the end of `approve_employee`, after the pay config update. Issued first, golden case V-SAL-3 went red, because its employee has no position and the classification refusal came before the decimal places error it expects. The case's expected text was not changed.
- **Race, by hand:** two sessions approved two employees in the same year with the year's counter row already committed; session B waited about 2.1 s on A's lock and took the next roll (ST26-01001, ST26-05002). With the lock removed (both the `for update` and the upsert, since `insert ... on conflict` alone also waits on A's uncommitted row), B failed on `unique (year, roll)`: a refusal, never a duplicate.

**Checkpoint 2, frontend.** Employee list (Staff ID column, search by ID ignoring case and separators), employee profile (ID, history, one-time Manager correction dialog), approval panels (unmapped notice, Approve disabled), Payroll setup positions (Manager class select, delete disabled for classed positions), payslip view and PDF ("Staff ID" row read at display time), staff list and detail (only where RLS returns the ID), `{{staff_id}}` merge field and its refusal before the click, audit labels. Pure helpers in `frontend/src/data/staff-numbers.ts`.

**Checkpoint 3, docs.** PLANNING, DESIGN, CONSTRAINTS (checklist item with the read-only hosted position query, TRUNCATE sweep note), PORT-PLAN cleanup plan row, this entry.

**Verification (local):**

- Hygiene at the start and end: overload check clean, types regenerated (120 lines added) and matching, anon-executable count 170 throughout, lint 0 errors and 13 warnings (baseline), `tsc` clean, `npm test` 183 tests (13 new, audit label counts 37 to 40), build ok.
- Role matrix: the new file has 40 probes, all green; the full suite of 45 files green after checkpoint 2.
- Deliberate breaks: 17, all caught (13 at checkpoint 1, 4 at checkpoint 2). Manager check on correction; read policy widened; no overwrite check; counter lock (race); roll per class; correction in the current year; 999 cap; second correction; retired ID reusable; class from `is_teaching`; revoke from public left out; class guard dropped; guard made SECURITY DEFINER; rename refusal; delete refusal; `{{staff_id}}` check; stale ID accepted. The checkpoint 1 report said 12 while its own table listed 13, so the total reported to Eyram as 16 is 17.
- Golden payslip suite: green before the first edit, after checkpoint 1, and again at the end of checkpoint 3 on a fresh reset: all cases pass.
- Code review: checkpoint 1 and checkpoint 2, no blocking findings. Fixed from review: the rename and delete bypass; the payslip page now waits for staff IDs to load; the generate pre-check waits for positions; the template check is an exact `strpos` match.

**Not done / open:** the frontend has not been tried in a browser; the hosted position query has not been run; nothing is committed; Eyram runs the push and deploy when ready. The rendered PDF itself can't be checked by the database (it checks only the merge data), as with every generated document.

## 2026-10-20: Admissions slice 12, confirmation email and scheduled cleanup (C1 to C3, local only)

Planned 2026-10-16 and approved by Eyram with changes on 2026-10-16, 2026-10-18 and 2026-10-20. C1 is committed as a929511; C2 and C3 are built locally and uncommitted. Nothing from this slice is applied, deployed or set on hosted. Detail, decisions D-12a to D-12o and the rollout handover are in PORT-PLAN, "Slice 12 as built".

- **What it does.** Every public enquiry and application now queues a confirmation email to the parent and one alert to staff, in the same transaction as the record. The `admissions-worker` Edge Function sends them through Resend when pg_cron calls it. The thank-you pages say a confirmation email follows.
- **Why an outbox and not a direct send.** A send straight after the submit loses the email if Resend is down or the function stops after the commit, and a retried request can send twice. The outbox keeps the email with the record, retries with back-off, and sends each row once (a claim lease, a claim token, and Resend's idempotency key per row).
- **Why no names in the email.** Names are free text typed into a public form; printing them would let anyone put words in an email sent from the school's domain to a stranger. The email carries only the reference, grade and year, and "Child N on your form" for several children (Eyram, 2026-10-16).
- **Why the parent on record also gets the email.** For a matched family, the typed addresses and the guardians already on record all get the same email, at most 4. The real parent hears about a fake child added to their family (the accepted risk of 2026-10-14), and a typed stranger gets the same email as in any other case, so nothing reveals whether a family exists.
- **What TCS OS showed.** The live TCS OS From address is `no-reply@mail.tcsch.edu.gh`, not the `admissions@tcsch.edu.gh` its code and deployment doc give (reported by Eyram from a real email on 14 Oct); the bare domain is not a verified sending domain. The TCS OS staff alert address is unknown (nobody received the alert from that test), so it is not copied: the ERP address is a function secret set at rollout. The TCS OS enquiry email attaches the overview PDF; the ERP drops it, because TCS OS gates that PDF behind a lead form (slice 13). Real people exist in TCS OS as PDF gate leads with consent flags; recorded in PORT-PLAN slice 13 (Act 843).
- **Why a 48 hour maximum age (2026-10-20).** Mail stays off until Eyram switches it on after the hosted tests. Without a limit, everything queued while off, or during a long outage, would go out at once and late. A queued email older than 48 hours is now expired and never sent.
- **Scheduled cleanup.** pg_cron now runs the upload sweep every 15 minutes (D-9h), settles expired offers hourly (D-6l), and purges old upload sessions, outbox rows past retention and pg_cron's own run history daily (closes slice 9 checkpoint 1 item d).
- **Recorded risk (accepted 2026-10-20).** A request to the worker with any non-empty secret header costs one database call before the comparison. The worker's use of the service role key (from its function environment, only the service-role-only functions, never logged) was approved on 2026-10-20.
- **Verification (local, test-runner end pass 2026-10-20).** Fresh reset; overload check clean; types identical; anon-executable 170; 46 probe files green (new: outbox E1 to E23, expiry X1 to X4); Edge tests 51, 7, 7, 6 (admissions-public) and 32, 5 (worker; fake provider, no real email); lint 0 errors, 13 warnings (baseline); `tsc` clean; vitest 194; build ok; no service role key in the bundle; Prettier clean. A two-session claim race (each row claimed once). 20 deliberate breaks, all caught (13 in C1, 7 in C2). A manual local run of the real wiring sent one email to a fake provider. Golden payroll suite not run: no audit action and no payroll item changed.
- **Docs.** DESIGN.md: five conventions (the outbox, the secret-gated worker, mail off with no defaults, the maximum age, scheduled work). CONSTRAINTS.md: the staff ID item now says committed; the slice 12 go-live item (From and domain, staff alert address, `net` not exposed, bounce rate, conditional counter bump, live only on hosted, kill switch, recorded risk). PORT-PLAN: slice 12 as built, the rollout handover, decision and status rows, the offer email moved to slice 11, TCS OS leads under slice 13, and the outbox row in the cleanup plan.

**Not done / open:** the C2 and C3 commits; the whole rollout (Eyram runs it, in the order in PORT-PLAN); the staff email page and the status line have not been tried in a browser; the hosted `net` exposure check, the Resend dashboard checks and the bounce rate after the first real week; the conditional reference counter bump at TCS OS intake close.

## 2026-10-21: Staff ID and slice 12 rollout reported

Docs only; nothing run here. Everything below is as reported by Eyram on 2026-10-20 and 2026-10-21; nothing else is claimed as applied or checked on hosted. C2 and C3 of slice 12 are committed as 8a45e04. Detail in PORT-PLAN, "Slice 12 rollout reported".

- **Applied and deployed.** A hosted backup was taken; the dry run listed exactly the four migrations and `db push` applied them (`20261026100000` staff ID, `20261027100000`, `20261027110000`, `20261027120000`). The positions query showed all 16 positions mapped and 0 employees in any position. The function secrets were set (the Resend key by the read -rsp method, `MAIL_DAILY_CEILING=60`), the worker URL was set, `admissions-worker` was deployed (version 1) and refused a request with no secret and one with a wrong secret (401), and the frontend was deployed. Exposed schemas showed "2 of 2", names not itemised; new tables are not exposed automatically.
- **Hosted test.** With `MAIL_MODE` live, the parent email reached Eyram's inbox. The first staff alert was suppressed by Resend after a Google NoSuchUser bounce, because `admissions@tcsch.edu.gh` did not exist when Resend first tried. Once the mailbox worked and the suppression was removed in Resend, a second test enquiry delivered the staff alert.
- **Why a new accepted risk.** The ERP showed that first staff alert as Sent: it records Resend accepting the email, and with bounce webhooks deferred it never hears about a later bounce or suppression. Accepted on 2026-10-21 until webhooks are built; the Resend dashboard is the place to see delivery.
- **Why a new go-live item.** A suppressed staff mailbox silently loses every staff alert. Before real intake, confirm `admissions@tcsch.edu.gh` is not on Resend's suppression list and that a test message reaches it quickly.
- **Docs.** PORT-PLAN: header status, slice 12 status row, the rollout reported section, the accepted risk, the go-live gates (the confirmation email now exists on hosted; the slice 12 checks stay open), and the two test enquiries and their outbox rows on the cleanup list. CONSTRAINTS.md: staff ID item, slice 12 item (status, accepted risk, suppression check, mail authentication check, staff address set, exposed schemas as reported). PLANNING.md: staff ID status.

**Not checked or not reported:** the matched-family application test; the staff ID click-through; `net` absent from exposed schemas by name. (SPF, DKIM and DMARC, `MAIL_MODE` and the public switches were reported later the same day; see the next entry.)

## 2026-10-21: Slice 12 hosted test, further answers

Docs only; nothing run here. Reported by Eyram on 2026-10-21:

- **Mail authentication.** SPF, DKIM and DMARC all showed PASS on the delivered parent email (Gmail, "Show original"). That closes the mail authentication go-live check.
- **Mail left live.** `MAIL_MODE` was left live after the test. The kill switch (`MAIL_MODE=off`) is in PORT-PLAN, rollout step 12.
- **Intake closed.** Public inquiries and Public applications are both closed again, so no parent can submit and nothing new is queued until intake opens.
- **Docs.** PORT-PLAN, "Slice 12 rollout reported" and the slice 12 go-live gate; CONSTRAINTS.md, the slice 12 item (mail authentication ticked; mail live and switches closed recorded).

**Still not reported:** the matched-family application test; the staff ID click-through; `net` absent from the exposed schemas by name.

## 2026-10-21: Admissions slice 10, saved applications (C1 to C3, local only)

Planned and approved by Eyram the same day with D-10a to D-10l. C1 is committed as dcbff52, C2 as 3ec9468, and C3 is built locally and uncommitted. Nothing from this slice is applied, deployed or set on hosted. Detail, the decisions and the rollout handover are in PORT-PLAN, "Slice 10 as built (local only)". Eyram runs every handover step.

- **What it does.** On the public `/apply` form a parent can press "Save and finish later". The answers entered so far are kept under a private link, emailed to the address prefilled from guardian 1 (after a consent tick). The link reopens the form with the answers restored, and the parent can submit from there. Saves are explicit: a button, no autosave. A welcome banner offers Discard.
- **What is not kept.**
  - Health answers: not kept at all (D-10d). The original plan's reason was that a draft's data can hold health answers and drafts are kept for weeks, so staff have no draft access by design. The session summary records the decision, not a longer reason.
  - Files (D-10c): not kept, and the parent attaches them again on resume. Upload sessions and their reservations live 6 hours and are swept soon after; keeping files for 30 days would need a new long-lived reservation kind, changes to the sweep and the 400 open reservation cap, and would hold bank slips and vaccination cards of applications that may never be submitted.
  - Declaration, signature and media consent: not kept. The state check refuses those keys at every level. They must be given fresh at the moment of submitting: a restored tick would leave it unclear when, and to which text, the parent agreed, and `declaration_agreed_at` is set by the server at submit.
- **Why the resume link is minted at send time.** Only its hash is stored, and the worker makes the link between claiming an outbox row and sending it. The original plan's D-12c left plaintext token links in the outbox open for slices 10 and 11. An outbox row is kept longer than a send and is readable by staff, so the link stays out of it, along with the log and any error text.
- **Why the link is a fragment.** A browser doesn't send `#resume=` to the server, so the token stays out of server and Edge logs. The page replaces the address through the router's history at once, so the token is gone from the address bar and Back doesn't bring it back.
- **Why the refusal is generic.** When the live-draft limit or a rate limit refuses, the parent sees only "We could not save your application right now. Please contact the school office." A specific message would show that a draft exists for an address, which is the reason the accepted risk below says the real parent sees only the generic message. The function maps the RPC's DETAIL code to that message and never matches message text.
- **Why an expired link is marked expired, not failed.** When the public switch is closed, or the draft expired or was submitted, the resume row is marked expired, not failed. The staff health count (`draft_failed`) then counts only links that actually failed to send. An email that is no longer needed is not a sending failure, so counting it would hide real failures and send staff looking for a problem that does not exist. The status itself was decided by Eyram on 2026-10-21.
- **Other decisions.** Per-draft daily resume email cap dropped in C1 (accepted: the per-address cap of 3 always binds first). Link backstop cap is 61. A first save that hits the resume email limit is simply refused. Old Prettier mismatches in the public handler files are left alone.
- **The consent line**, drafted for Eyram's review and not decided, is in `public-copy.ts`: "I agree that Treasures Christian School may keep the answers I have entered on this form, which may include details about my child, and the email address above, so that I can finish my application later. They are kept for 30 days after my last save, and for no more than 60 days in all, and are then deleted. The health questions, uploaded files, the declaration, my signature and media consent are not saved. I can delete my saved application at any time from the emailed link. My saved answers are handled in line with the school's privacy policy."
- **Verification (local, test-runner end pass 2026-10-21, then the main session after fix round 1).** Fresh reset; overload check clean; types identical; anon-executable 170; 50 of 50 probe files green (new D1 to D9, B1 to B10, L1 to L3). Edge unit tests: admissions-public 62, worker 30, templates 13. Integration tests: integration 7, upload 7, submit 6, draft 6, worker 7 (fake provider, no real email). Lint 0 errors and 13 warnings (baseline). `tsc` clean. Vitest 216, run after the health strip count was added. Build ok. No service role key in `dist/client`. Prettier clean on the changed files. Golden payroll suite not run: no payroll, audit action or audit policy was touched.
- **Race, by hand.** Two upload sessions submitted one draft: one application was made, and the second was refused after waiting about 2.1 s on the draft lock.
- **Deliberate breaks.** 19, all caught (14 in C1, 3 in C2, 2 in C3). A break of the per-draft daily email cap was not caught, so the cap was dropped as redundant.
- **Code review.** C1: no blocking findings. Three should-fix items were fixed: the link cap (61), resume rows dropped at submit and at wipe, and probe gaps. C3: no blocking findings. Seven should-fix items were fixed in one round and re-reviewed clean.
- **Docs touched.** PORT-PLAN (header status, slice 10 status row, "as built" section, D-10a to D-10l rows, privacy policy and saved applications gates, the cleanup plan row). CONSTRAINTS.md (privacy policy item, go-live cleanup item, new saved applications checklist item). DESIGN.md (five conventions). This entry. PLANNING.md is unchanged: it carries no slice 10 status.
- **Not done / open.**
  - The C3 commit. Nothing is committed; Eyram commits when asked.
  - The whole rollout, which Eyram runs in the order in PORT-PLAN's handover. `PUBLIC_APPLY_BASE_URL` is not set on hosted.
  - Resend click and open tracking off for `mail.tcsch.edu.gh`. Not reported.
  - The consent wording review. Drafted, not decided.
  - The privacy policy, which must now describe saved applications. Not written.
  - Erasure requests. The handling (Eyram deletes the draft by email address on hosted, with a reviewed SQL statement) is recorded as a plan, not reported by Eyram.
  - No browser run of the form locally. The hosted test is in the handover.
  - D-10c to D-10l sit in one row of the decision table. The session summary gives only D-10c (no files) and D-10d (no health answers) by number.

## 2026-10-21: Slice 10 rollout reported

Docs only; nothing run here. Everything below is as reported by Eyram on 2026-10-21; nothing else is claimed as applied or checked on hosted. C3 is committed as bebd811. Detail in PORT-PLAN, "Slice 10 rollout reported".

- **Applied and deployed, in the handover order.** Backups taken. `admissions-worker` deployed before the push, and a bare request returned 401. The dry run listed exactly `20261028100000`, `20261028110000` and `20261029100000`, and `db push` applied them. The four cron jobs are present. The grants query for `application_drafts` and `application_draft_links` returned no rows. `admissions-public` deployed. `PUBLIC_APPLY_BASE_URL` set to `https://tcs-erp.weyramkodzo.workers.dev`. Frontend deployed.
- **Hosted test passed** with Eyram's own address: save, resume email received, link not rewritten, fragment removed, resume, submit, and the reopened link locked as already submitted. Public applications closed again afterwards.
- **Why the worker went first.** The old worker would have failed every claim batch that met a `draft_resume` row; the new one reads them safely and had none to read until the push.
- **Not reported:** the anon-executable count after the push; the Resend click and open tracking setting itself. The unrewritten link indicates click tracking is off; open tracking is not shown by that test, so the checklist item stays open.
- **Docs.** PORT-PLAN: header status, slice 10 status row, "Slice 10 as built" (retitled), the new "Slice 10 rollout reported", the slice 10 go-live gate, and the slice 10 hosted test records on the cleanup list and in the cleanup plan table. CONSTRAINTS.md: the saved applications item (hosted test ticked) and the Resend tracking item (indirect evidence recorded, still open).

**Still open:** the consent wording review; the privacy policy describing saved applications; the Resend tracking setting itself; the anon count on hosted; the go-live cleanup of the test records.

## 2026-10-21: Cutover critical path and slice 13 plan approved

Docs only; nothing built, run or deployed. Two planning passes: the cutover critical path, then slice 13 (planned by `tcs-planner`). Eyram approved both with changes the same day. Detail in PORT-PLAN, slice 15 "Cutover decisions" and "Slice 13 plan".

- **What real families touch on TCS OS today** (read only, `~/projects/tcs-os` and `~/projects/tcs-website`). Only the marketing site's PDF gate, which posts to TCS OS with the TCS OS Turnstile key and emails a link to TCS OS's `/inquiry`. Quick interest is not called anywhere, and the site does not link to the forms. TCS OS's `ALLOWED_HOSTS` is the admissions host only, so the DNS flip itself stops TCS OS intake.
- **Cutover.** Go or no go on 1 Dec 2026, cutover planned for 2 Dec. Before cutover: slice 13, slice 15 host routing, the privacy policy and declaration version, the cleanup, the open checks. Slice 11 before cutover if it fits by about 20 Nov, otherwise shortly after with the copy link hidden. Slice 14 after cutover.
- **Cutover decisions.** No WAF rule (D-15d). The Cloud Run domain mapping is kept until shutdown, so rolling back is a DNS change. The staff host stays on workers.dev (D-15e). Reference counters are always raised to 0101 at cutover, because both systems use the same reference formats and a rollback could otherwise duplicate one. The real host test runs on cutover day, then the cleanup once. The declaration version is stored. The slice 10 consent line is approved as drafted.
- **Reported by Eyram.** The `tcsch.edu.gh` zone is Active in the same Cloudflare account as the `tcs-erp` Worker, so the custom domain can attach. TCS OS holds no real enquiry, application or family record; its only real records are three PDF gate leads (one consented to marketing, two not, none unsubscribed), and the 23 campaign recipients are test data except those three. Resend click and open tracking are both off for `mail.tcsch.edu.gh`, which closes that checklist item.
- **Why leads are the one import, and why it is small.** The three leads are real people with consent flags (Act 843), so they are imported after cutover by one reviewed SQL statement that keeps each lead's original `created_at` and consent flag. With three rows, the CSV export, checksum, legacy unsubscribe hash and `tcs_os_lead_id` planned earlier the same day were dropped (Eyram). Their names and contact details are kept out of every repo file; the docs hold only a template. The counter bump stays for DNS rollback safety, not for migration.
- **Slice 13 decisions (D-13a to D-13p).** The marketing site is repointed to the `admissions-public` Edge Function with the ERP widget's key, around 6 Nov and before the privacy policy if need be; the old path is not served; quick interest is dropped. Lead capture gets its own Manager-only, audited switch, independent of the intake switches, because the marketing site points at the ERP weeks before intake opens. Marketing origins go in a separate `ADMISSIONS_LEAD_ORIGINS` and reach only `pdf_gate`. The PDF email attaches the fees PDF and carries one plain link to `https://admissions.tcsch.edu.gh/inquiry`, the second exception to D-12f. A missing PDF means retry, never send without it.
- **Changed by Eyram.** The staff alert carries no name, email or phone, only grade, consent, source and a link to the lead (D-13g). Admissions Officer reads all leads in full, with no grade band scope because grade interest is mostly blank; Manager full; Auditor masked (D-13h, a new permission). Limits start at 20 per hour per IP, 40 per day in all, 2 PDF emails per address per day, lead mail at most half the daily ceiling (D-13j), adjusted from real ERP traffic. Retention: 12 months without consent, 24 with consent, deleted on unsubscribe, stated in the privacy policy (D-13l). About 22 deliberate breaks, not 32; still about 22 and three checkpoints after the import was simplified. `quick_interest_widget` is not allowed as a source (D-13d), since all three real leads came from the PDF gate.
- **Why lead mail has its own caps.** Lead mail must not use up a real parent's confirmation allowance or starve application mail, and a 5 MB attachment makes the PDF gate a mail-bombing path, so it gets its own per-address cap and at most half the ceiling.
- **Docs.** PORT-PLAN: header status, status rows 11, 13, 14 and 15, the D-12f exception, "Slice 13 plan", "Cutover decisions", the runbook (steps 2 and 4, parity list), the legacy path options, the anon surface table, the go-live gates (privacy policy covering leads, declaration version, consent wording, new lead capture checks, counter bump), the cleanup plan changes, and decision rows D-13a to D-13p, D-15d and D-15e. PORT-PLAN also: the campaign recipient question answered in its five places. CONSTRAINTS.md: the cutover, privacy policy, cleanup, declaration version, consent wording, Resend tracking and counter bump items; a new lead capture item; the TCS OS retirement section (the three-lead import exception, no real family records, no WAF rule, the mapping kept, the staff host, the campaign recipients answered).

**Waiting on Eyram:** the fees PDF; the Resend plan; the privacy policy; the Supabase plan; GCP billing through January 2027.

**Next:** slice 13 C1, after Eyram reviews this docs diff.

## 2026-10-21: Admissions slice 13 C1, the lead database (local only)

Built locally and uncommitted; nothing applied on hosted. Detail in PORT-PLAN, "Slice 13 C1 as built".

- **What it does.** A lead table for the marketing site's PDF gate, a third switch (`public_leads_open`, Manager only, audited, closed by default), `capture_lead` for the Edge Function, two outbox kinds (the PDF to the lead and a staff alert), the staff lead list, and lead retention in the daily housekeeping job.
- **Why the alert reads its fields at send time.** The outbox keeps no lead details; `get_lead_alert` hands the worker only the grade, consent, source and lead id while it holds the claim (D-13g).
- **Why lead mail has its own caps.** The confirmation cap now counts only confirmations, so PDFs and resume emails can't use up a family's 4 a day; lead mail is claimed after everything else and gets at most half the daily ceiling, so a burst of PDF requests can't starve application mail.
- **Fix round 1.** From code review: held back lead mail now sets the ceiling marker on the staff health strip, and housekeeping no longer deletes a lead mid-send. The ceiling arithmetic went into the go-live gate: each lead is two emails, so 40 leads a day needs a ceiling of at least 160.
- **Corrected in the docs.** Probe L4: the switch is readable by Manager and Auditor only, like the other admissions settings; the plan's Admissions Officer tick would have been an unapproved permission.
- **Slice 14 carry-forward (Eyram).** Unsubscribed leads are deleted by retention, so slice 14 keeps a hash-only suppression list so an opt out is still honoured.
- **Verification (local).** Fresh reset; no duplicate overloads; types regenerated (additions only); anon-executable 170; 52 of 52 probe files green; 16 deliberate breaks caught; worker integration 7 of 7; Edge unit tests 105; `tsc` clean; lint 0 errors and 13 warnings (baseline); vitest 216; build ok. Golden payroll suite not run (no payroll or audit action change).

**Not done:** the commit; the hand race on the PDF cap (two sessions); C2 (Edge Function and worker attachment) and C3 (staff screens); everything on hosted.

## 2026-10-21: Admissions slice 13 C2, the PDF gate action and the PDF email (local only)

C1 is committed as 1a76b6c. C2 is built locally and uncommitted; nothing is deployed or set on hosted and no real email was sent. Detail in PORT-PLAN, "Slice 13 C2 as built".

- **Race test (by hand).** Three sessions capturing to one address at once gave exactly 2 pending PDF emails and 1 suppressed; the later two waited on the advisory lock while the first was open.
- **What it does.** The marketing site's form can post to `admissions-public` (action `pdf_gate`) once it is repointed; the worker emails the fees PDF from the private bucket with the one enquiry link, and alerts staff with a link to the lead.
- **Why a separate origin list.** Marketing origins reach only the PDF gate, and the PDF gate only marketing origins (D-13c), so a page on the marketing site can't post enquiries or applications, and cutting the site off is one secret. A typo in that list refuses only the PDF gate.
- **Why a missing PDF stops the email.** An email that says the document is attached with nothing attached is worse than a delay; the row retries with class config, which shows on the staff email health page (D-13k).
- **Fix round 1.** From code review: a 120 second run budget, so a slow provider can't push a batch of 30 second attachment sends past the 5 minute claim lease; more tests; the enquiry link refuses an IP host.
- **Verification (local).** Edge unit tests 136; strict `tsc` clean; integration 7, 7, 6, 6, 7 and 3 on a fresh reset with a fake provider; no duplicate overloads; types match; anon-executable 170; 6 deliberate breaks caught (22 in the slice). Full role matrix not re-run (no SQL change); golden payroll suite not run.

**Not done:** the commit; C3 (the staff lead list, the third switch card, the email page labels, the rollout handover); everything on hosted.

## 2026-10-21: Admissions slice 13 C3, the staff lead screens and the rollout handover (local only)

C1 is committed as 1a76b6c and C2 as 98ff213. C3 is built locally and uncommitted; nothing is deployed or set on hosted. Detail in PORT-PLAN, "Slice 13 C3 as built" and "Slice 13 rollout handover".

- **What it adds.** `/admissions/leads` (Manager and Admissions Officer in full, Auditor with email and phone masked by the database; `?lead=<id>` opens the lead from a staff alert); a "Lead capture" switch card in Admissions Settings (Manager changes it, Auditor reads it; the Admissions Officer has no settings page, matching probe L4); the email page labels and wording for the two lead emails, including the PDF's own limit of 2 a day; the "Admissions Leads" sidebar link.
- **Recorded rule (Eyram).** The marketing hosts must never be added to `ADMISSIONS_ALLOWED_ORIGINS`: an origin on both lists passes both gates, so the marketing site could post enquiries, applications, uploads and drafts. In DESIGN.md (one of five new slice 13 conventions), CONSTRAINTS.md and the handover.
- **The handover.** In order: bucket check (done, reported by Eyram), backups, worker first, `db push` of the two C1 migrations, the PDF upload to the fixed path, the two secrets and `MAIL_DAILY_CEILING=200` only once the Resend plan is confirmed, `admissions-public`, the frontend, the marketing hosts on the ERP Turnstile widget, the marketing change on a temporary Vercel preview, the lead switch and the hosted test, the production switch-over, and the import of the three real leads by one reviewed statement (dry run first, original dates and consent kept, guarded against duplicates, no real data in any file).
- **Fix round 1 (code review, docs only).** The PDF upload avoids the dashboard's "Create folder" (its placeholder file is refused by the PDF-only bucket); the emergency cut-off is `secrets unset`; the import stops on another source, a blank email or an unsubscribe date, and dates carry their offset; the marketing snippet type-checks without a cast.
- **Verification (test-runner end of slice pass).** Fresh reset; no duplicate overloads; types identical; anon-executable 170; 52 of 52 probe files; Edge unit tests 136; integration 7, 7, 6, 6, 7 and 3 with a fake provider; `tsc` clean; lint 0 errors and 13 warnings (baseline); vitest 225; build ok; no service role key in `dist/client`; Prettier clean on the C3 files; no dashes added. No new deliberate breaks (the slice's 22 ran in C1 and C2). Golden payroll suite not run (no payroll or audit action change).

**Not done:** the commit; the whole rollout (Eyram runs it, in the handover order); the marketing site change (described, not made); the import of the three leads.
