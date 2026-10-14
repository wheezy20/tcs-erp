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
- **Admissions is the real port.** It's live in production on TCS OS;
  all its applications and inquiries are test data, so nothing is
  migrated (2026-10-11). It becomes Phase 2 below.
- TCS OS stays live, untouched, until this ERP reaches parity. Its
  folder is **read-only reference**, and its `docs/` are the source of
  truth for the business logic being ported.

## Phase 1: Accounting, Finance & HR

**Status:** built and in use for test runs; no real payroll month run yet.
The HR items deferred in CONSTRAINTS.md stay deferred.
Staff advances (IOU loans repaid through payroll) were built 2026-10-07 as
Phase 1 payroll work while Phase 2 Admissions is the active phase.
Employee bulk import (2026-10-08, migration `20261009100000`) is a new
capability for HR data entry: preview and all-or-nothing import from
spreadsheets. **Remaining gap:** The manual "Propose employee" path has no
duplicate check. A manual proposal saved at the same moment as a bulk
import may slip past the import's duplicate check and create a
double entry. No uniqueness constraints were added (Eyram, 2026-10-08);
how to close the manual-path gap is not yet decided.

**Staff IDs (format given by Eyram 2026-10-12, not built).** Format
`ST26-01002`: ST means staff, 26 is the year, then a dash, then a two
digit class code (01 admin, 02 teaching, 03 non teaching), then a three
digit roll number (002 in the example). **Open question:** does the roll
restart per year, per class, both, or neither? Not answered; nothing may
assume it. Today the ERP generates no staff number: `employees` and
`staff` are keyed by uuid only, the employee import template has no ID
column, and the onboarding item "Staff Email & ID Issued" is derived
from a linked login plus a school email, not from any ID value.

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

**Status:** slice 1 (campuses) committed and deployed. Slice 1b split:
1b-i (allowlist guards, can_read_store, list_staff_names, regression matrix)
committed and deployed; 1b-ii (Admissions Officer role) committed and deployed.
Slice 1c (session timeout readable by every staff role) committed and deployed.
Slice 2 (admissions grade reference data and capabilities layer) committed and applied on hosted.
Slice 3a (applicants, guardians, students, applications, contacts, notes) committed and applied on hosted.
Slice 3b (decisions, offers, capacity, campus rules) committed and applied on hosted.
Slice 4 (health answers, documents and private storage bucket) committed and applied on hosted.
Slice 5 (numbering, stage transitions, notes and document review) committed (8b9c1d4) and applied on hosted.
Slice 6a (decisions and capacity staff side) committed (5c56735) and applied on hosted.
Slice 6b (offers, enrolment gate, student IDs staff side) committed (6c1f014) and applied on hosted.
Slice 7a (staff pipeline UI: list, detail, notes, documents, health panel) committed (de1aff9) and applied on hosted; frontend deployed on 2026-10-12.
Slice 7b split into 7b1 (detail page actions: decision, offer, enrolment, grade correction) committed (f04a336) and 7b2 (admin screens: academic years, capacity, offer expiry, campus rules) committed as bed38c9.
Slice 7c (read-only Audit Log at `/audit-log`, Accountant audit narrowing) built 2026-10-13 and committed (7a07d6a). Slice 8 (public request path and Inquiry form) built locally on 2026-10-14, not committed. Slice 8 and 9 planning decisions recorded 2026-10-13.
Decision batches recorded 2026-09-29 (D-2g, D-1b-a/b/c/d confirmed), 2026-10-05 (O-1 to O-9 confirmed), 2026-10-12 (D-6a to D-6p decided, D-6j changed to a withdrawn offer response), 2026-10-12 (D-7a approved) and 2026-10-12 (7b split, D-6q reversed, grade correction narrow rule, audit extended to 37), 2026-10-13 (slice 7c, and slice 8 and 9 planning decisions).

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
  cutover) is `docs/admissions/PORT-PLAN.md`, drafted 2026-09-29. It's
  reviewed before any admissions code is built.
- **Data:** all TCS OS applications and inquiries are test data, so
  nothing is migrated and the ERP's reference counters start fresh
  (2026-10-11). Still open: whether the 6 leads and 17 guardians who
  received TCS OS campaign emails are test data. This ERP never
  connects to TCS OS's database or buckets. See CONSTRAINTS.md.
- **The public URL must not break.** admissions.tcsch.edu.gh keeps
  serving from TCS OS until cutover. At cutover it becomes a redirect
  to this ERP's public admissions routes. It is not simply switched
  off, because parents hold links to it in sent emails.
- **Two campuses, Main and Annex**, each a `branches` row using the
  existing `branch_id` (decided 2026-09-29, see CONSTRAINTS.md). Seat
  capacity is per campus, and Annex only takes the grades TCS OS
  restricts it to.
- **A fifth role, Admissions Officer** (decided 2026-09-29), gives
  access to admissions only. A capabilities layer (`can_decide`,
  grade bands, a separate child-health gate) narrows access inside
  admissions. More roles may be added as other modules are built. See
  CONSTRAINTS.md "Staff roles" for how.
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
