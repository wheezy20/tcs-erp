# TCS ERP — Constraints

Things that shape how this gets built, not just what gets built.

## Checklist — must be done before real go-live

- [ ] Verify PAYE bands against the official GRA published schedule
      (currently placeholder values, see docs/JOURNAL.md)
- [ ] Confirm the SSNIT / Tier 2 split (0.5% / 13% / 5%) against an
      official SSNIT source — currently only confirmed verbally against
      the school's current practice (see "Statutory accuracy" below).
      Note the employer's 13% is now computed, snapshotted
      (`payslips.ssnit_employer`) and posted (Dr 5145 / Cr 2310) as of
      `20260909120000` — only the *rate* still needs the official check.
- [ ] Replace `supabase/seed.sql` (still Wilelik's dummy retail data) with
      real TCS seed data, or none
- [ ] Create a dedicated hosted Supabase project for TCS and run
      `scripts/bootstrap-production-manager.sh` for the first real Manager
- [ ] Real TCS logo / favicon assets (sidebar + login currently render a
      text "TCS" placeholder)

## Data safety

- **This project must never connect to Wilelik's real Supabase project.**
  Wilelik (the original, at `~/projects/wilelik-erp`) holds Eyram's dad's
  actual business data. TCS ERP needs its own, separate Supabase project
  before any real staff/student/financial data goes into it. As of the
  rebrand, no live connection exists either way — `supabase/config.toml`
  only sets a local Docker container name — but this needs to stay true
  as deployment gets set up.
- `supabase/seed.sql` currently contains **Wilelik's dummy retail data**
  (building-materials products, Ghanaian customer/supplier names, a
  retailer's chart of accounts). Do not run `supabase db reset` expecting
  TCS-appropriate seed data until this file is replaced.

## Solo development

- Eyram is the only developer, building primarily via **Claude Code with
  conversational prompts**, not upfront specs. Keep changes scoped and
  reviewable — one module or feature at a time, not sweeping multi-module
  changes in a single session.
- Eyram is early in his data science / programming learning curve
  (started an MSc in Data Science with limited prior Python/programming
  background). This doesn't change the standards the code is held to,
  but explanations of *why* a decision was made are worth keeping
  (hence this docs/ folder and the conventions logged in DESIGN.md)
  rather than assuming context carries only in one person's head.

## Statutory accuracy (payroll)

- The SSNIT/Tier 2 split confirmed for this build: **SSNIT = 0.5%
  employee + 13% employer; Tier 2 = 5% employee** (employer-side Tier 2
  is 0 in this setup). This was confirmed directly by Eyram against his
  school's actual payroll practice, so it's more reliable than the
  secondhand tax-guide figures found via web search.
- **PAYE band thresholds are NOT yet verified against an official GRA
  source.** The `paye_bands` table structure is built (graduated bands,
  editable, effective-dated), but real numbers must come from GRA's
  actual published schedule before this is used for real payroll, not
  from blog/calculator sites.
- Rates and bands are stored as **editable database rows, never
  hardcoded constants** — a correction or an annual update should be a
  data change, not a code deploy.
- Some staff (e.g. National Service personnel, other temporary/contract
  staff) are **exempt from some or all of SSNIT/PAYE/Tier 2**. This is
  handled per-staff via boolean flags on `staff_pay_config`
  (`pays_ssnit`, `pays_tier2`, `pays_paye`), independently toggleable.

## Staff roles (as of 20260909090000)

Four roles on `staff.role`: **Manager** (full write everywhere),
**Accountant** (Manager-equivalent write on Payroll / Accounting /
Expenses; read-only elsewhere), **Auditor** (read-only everywhere the
old combined role could read), **Attendant** (Sales / POS / invoices; no
finance access). Enforced by RLS + the `can_write()` /
`require_writable_role()` / `require_finance_writer()` predicates — see
DESIGN.md. When adding a new table, decide which of these four it's for
and gate it with the matching predicate; don't invent a fifth role or a
per-table role check.

## Architecture

- Design for **single-campus** operation now (TCS has one campus), but
  keep `branch_id` on every relevant table anyway — same discipline
  Wilelik already used for its own single-branch-first rollout. This
  avoids a restructuring project if TCS ever opens a second campus.
- The eventual **merge into TCS OS** (Django + Supabase + Cloud Run) is
  a known future event, not a hypothetical. Avoid one-off hacks or
  undocumented schema decisions here that would make that merge harder
  than it needs to be — the DESIGN.md conventions exist partly for this
  reason.

## Ghana-specific context worth keeping in mind

- Currency: GH₵ throughout.
- Academic year: three-term structure (First/Second/Third Term), not
  semesters — relevant once Academic Settings/Exams get built.
- SMS: Mnotify is the common Ghana-specific aggregator (seen in Royal
  Avenue's system) — worth considering over Twilio-only when
  Communication gets built.
