# TCS ERP — Planning

## What this is

An internal ERP for Treasures Christian School (TCS), forked from the
Wilelik ERP (a QuickBooks-like system originally built for Eyram's dad's
retail business). The fork reuses Wilelik's financial engine — real
double-entry accounting, not a bolted-on ledger — and adds school-specific
modules on top.

**Long-term destination: this ERP is the one TCS system.** Until
2026-09-29 the plan was the reverse: fold this ERP into **TCS OS** (the
Django + Supabase + Cloud Run project at `~/projects/tcs-os`, serving
Admissions at admissions.tcsch.edu.gh). That direction has been
reversed (see docs/JOURNAL.md, 2026-09-29). **TCS OS is being retired
and its logic ported into this ERP.** The main reason is that
TCS's staff are non-technical, and this ERP's UI was preferred over what
Django could offer without a lot of custom frontend work.

- **HR and Finance need no port.** TCS OS's `hr`/`finance` modules
  were themselves ported *from* this repo. Their payroll parity work
  (payslips matched to the cent) is useful as regression evidence, not
  as code to bring back. See CONSTRAINTS.md.
- **Admissions is the real port.** It's live in production on TCS OS
  with about 3 real records. It becomes Phase 2 below.
- TCS OS stays live, untouched, until this ERP reaches parity. Its
  folder is **read-only reference**, and its `docs/` are the source of
  truth for the business logic being ported.

## Phase 1: Accounting, Finance & HR

**Status:** built and in use for test runs; no real payroll month run yet.
The HR items deferred in CONSTRAINTS.md stay deferred.

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
- **HR beyond payroll** — staff records, onboarding checklist and the
  tokenized public onboarding form, document storage, generated
  letters/contracts. See CONSTRAINTS.md's "HR expansion beyond payroll"
  and docs/JOURNAL.md (2026-09-19 onward).

## Phase 2: Admissions (ported from TCS OS)

**Status:** next, not started. No admissions code gets written until
`docs/admissions/PORT-PLAN.md` exists and has been reviewed.

Porting TCS OS's live admissions module: inquiries, applications,
documents, decisions/offers/enrolment gating, reference numbering,
transactional and bulk email, lead capture, and grade-band coordinator
access. **Only the business logic and rules come across.** The Django
models, views and templates are rewritten for this stack (plpgsql RPCs,
RLS, TanStack routes), not translated line for line. The TCS OS
reference docs are `~/projects/tcs-os/docs/admissions/`
(`02-stack-and-schema.md` for rules and past incidents,
`03-build-order.md` for what shipped and why).

- The slice-by-slice plan (each slice ships on its own, ending in
  cutover) is `docs/admissions/PORT-PLAN.md`. It's written as its own
  step and reviewed before any admissions code is built.
- **Real data:** TCS OS's ~3 real admissions records, plus any files
  attached to them in TCS OS's Storage, get **migrated by hand into
  this project's own hosted Supabase project**. This ERP never
  connects to TCS OS's database or buckets. See CONSTRAINTS.md.
- **The public URL must not break.** admissions.tcsch.edu.gh keeps
  serving from TCS OS until cutover. At cutover it becomes a redirect
  to this ERP's public admissions routes. It is not simply switched
  off, because parents hold links to it in sent emails.
- **Two campuses, Main and Annex**, each a `branches` row using the
  existing `branch_id` (decided 2026-09-29, see CONSTRAINTS.md). Seat
  capacity is per campus, and Annex only takes the grades TCS OS
  restricts it to.
- **Roles stay four.** Admissions adds a small capabilities layer on
  top: a `can_decide` flag, per-staff grade bands for coordinators, and
  a separate gate for child health data. See CONSTRAINTS.md.
- **No dual intake:** TCS OS and this ERP never both accept real
  submissions at once. See CONSTRAINTS.md.

## Later phases (not started)

Roughly in the order they'd likely get built, based on what's genuinely
missing from Wilelik and what a Royal Avenue school-management-system
demo (explored for feature ideas, not code) suggested is worth having:

- **Student Management** — bio-data, guardians, class/campus assignment,
  a fee-category mechanism for scholarships/discounts (Royal Avenue's
  A1/A2/A3 pattern was a clean example of this). Admissions (Phase 2)
  brings in `Family`/`Guardian`/`Student` records first, so this phase
  should build on them rather than create a second student model.
- **Attendance** — student and staff, daily granularity.
- **Exams / Gradebook** — mark entry, report card generation, likely
  needing a separate narrative-report path for Preschool/early years.
- **Communication** — event-triggered SMS/email templates (admission,
  fee reminders, exam results) and a "who owes money → one-click
  campaign" tool tied directly into Billing. This was the single most
  compelling idea from the Royal Avenue exploration. Admissions (Phase
  2) brings in the first email infrastructure: transactional email, and
  bulk email with RFC 8058 unsubscribe. This phase should extend it,
  not replace it.
- **Parent Portal** — per-guardian account linking, view-only access to
  grades/attendance/bills/homework.
- **Timetable** — a real gap in Royal Avenue's system (they advertise a
  permission for it but never built the feature). If TCS builds this
  properly, it's a genuine differentiator, not just parity.
- **POS / Inventory / Purchasing** — already exist in the fork, dormant
  until there's an actual school store or uniform shop to run through
  it.

## Non-goals for now

- No campus-management features beyond what TCS's two campuses (Main
  and Annex) need. They're two `branches` rows on the existing
  `branch_id`, not a general multi-campus system. A third campus, or
  per-campus settings/branding, isn't planned. See CONSTRAINTS.md.
- No parent/student self-service login until the Parent Portal phase.
  The admissions public forms don't break this rule. Inquiry and
  application submission is anonymous (bot-checked), and the
  resume/offer/unsubscribe links use unguessable single-record tokens
  (like the onboarding form), not logins.
- No attempt to match Royal Avenue's exact feature set module-for-module
  — the goal is picking the ideas worth having, not parity with a
  product Eyram doesn't control.
