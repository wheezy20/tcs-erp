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
