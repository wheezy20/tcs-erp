# TCS ERP — Planning

## What this is

An internal ERP for Treasures Christian School (TCS), forked from the
Wilelik ERP (a QuickBooks-like system originally built for Eyram's dad's
retail business). The fork reuses Wilelik's financial engine — real
double-entry accounting, not a bolted-on ledger — and adds school-specific
modules on top.

**Long-term destination:** this ERP eventually folds into **TCS OS**, the
Django + Supabase + Cloud Run monorepo already covering Admissions,
Enrollment, and CRM at admissions.tcsch.edu.gh. TCS ERP is being built
standalone first (in its own stack, inherited from Wilelik) rather than
inside TCS OS directly, because the financial engine already exists here
and re-platforming it into Django from scratch isn't worth doing twice.
How and when the merge happens is an open question — see CONSTRAINTS.md.

## Phase 1 (current focus): Accounting & Finance

- **Accounting** — chart of accounts, journal entries, ledger, trial
  balance, P&L, balance sheet, cash flow, bank reconciliation. Inherited
  from Wilelik essentially as-is; it's already a proper double-entry
  system, not something a school ERP needs to reinvent.
- **Expenses**, including receipt/proof-of-expense photo upload. Also
  inherited as-is — already has a `receipts` storage bucket and upload
  flow built in.
- **Payroll** — net new. Staff pay configuration, SSNIT (Tier 1) and
  Tier 2 statutory deductions, PAYE, payslip generation, staff overview.
  Per-staff exemption flags for temporary staff (e.g. National Service
  personnel) who don't pay any of the three.

## Later phases (not started)

Roughly in the order they'd likely get built, based on what's genuinely
missing from Wilelik and what a Royal Avenue school-management-system
demo (explored for feature ideas, not code) suggested is worth having:

- **Student Management** — bio-data, guardians, class/campus assignment,
  a fee-category mechanism for scholarships/discounts (Royal Avenue's
  A1/A2/A3 pattern was a clean example of this).
- **Attendance** — student and staff, daily granularity.
- **Exams / Gradebook** — mark entry, report card generation, likely
  needing a separate narrative-report path for Preschool/early years.
- **Communication** — event-triggered SMS/email templates (admission,
  fee reminders, exam results) and a "who owes money → one-click
  campaign" tool tied directly into Billing. This was the single most
  compelling idea from the Royal Avenue exploration.
- **Parent Portal** — per-guardian account linking, view-only access to
  grades/attendance/bills/homework.
- **Timetable** — a real gap in Royal Avenue's system (they advertise a
  permission for it but never built the feature). If TCS builds this
  properly, it's a genuine differentiator, not just parity.
- **POS / Inventory / Purchasing** — already exist in the fork, dormant
  until there's an actual school store or uniform shop to run through
  it.

## Non-goals for now

- Multi-campus support isn't needed yet (TCS is single-campus), but the
  underlying `branch_id` scoping is kept on every table anyway — see
  CONSTRAINTS.md.
- No parent/student self-service login until the Parent Portal phase.
- No attempt to match Royal Avenue's exact feature set module-for-module
  — the goal is picking the ideas worth having, not parity with a
  product Eyram doesn't control.
