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
