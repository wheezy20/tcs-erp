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
