# Admissions port plan (TCS OS → TCS ERP)

**Status:** slices 0 to 5, 6a and 6b built and committed; slice 7a built, awaiting Eyram's review (uncommitted); the rest is plan. Two batches of decisions are recorded below ("Decisions recorded"); the rest are open.
**Scope:** porting TCS OS's live admissions module (`~/projects/tcs-os/backend/modules/admissions/`) into this repo, one slice at a time. Each slice goes through one pass of the slice loop in `CLAUDE.md`.
**Settled inputs (not reopened here):** Main and Annex are two `branches` rows. There's a fifth role, **Admissions Officer** (decided 2026-09-29; it supersedes the earlier "four roles plus capabilities" decision), plus an admissions capabilities layer for narrowing inside admissions. There is no dual intake. See `docs/CONSTRAINTS.md` and `docs/PLANNING.md`, 2026-09-29, and "Decisions recorded" below.

---

## Summary

The port brings over TCS OS's admissions **rules**, not its Django shape. Every rule TCS OS enforces in `Model.save()`, a serializer or an admin action becomes a SECURITY DEFINER RPC, trigger, constraint or RLS policy here. That covers reference numbering, stage gates, negative-outcome propagation, the Annex grade rule, the preschool vaccination rule, capacity warnings, duplicate matching and token expiry.

The plan runs in three stretches:

1. **Foundations.** Payroll regression carry-back, campus safety, the capabilities layer, then the core schema with staff-only RLS.
2. **The staff pipeline.** Numbering, stages, decisions, offers, enrolment and the staff UI. Nothing in this stretch touches `anon`.
3. **The public surface, email, and cutover.** Each anon-reachable piece ships in its own slice so it gets its own confirmation gate.

Public writes that need a secret (the Turnstile check, rate limiting, signed upload URLs) go through one Supabase Edge Function. The database functions behind it are service-role-only, so `anon` can't call them directly. Email is an outbox table written in the same transaction as the record, drained asynchronously by an Edge Function that pg_cron and pg_net trigger.

At cutover, `admissions.tcsch.edu.gh` is attached to the ERP Worker. The ERP's public routes use TCS OS's exact paths (`/inquiry`, `/apply`, `/offer`, `/api/admissions/unsubscribe/<token>/`), so every link already in a parent's inbox keeps resolving, including RFC 8058 one-click POSTs, with no redirect needed. Nothing is imported from TCS OS: its applications, inquiries, offers and drafts are all test data, so no TCS OS token is carried across.

## Status

| # | Slice | Status | Depends on |
|---|---|---|---|
| 0 | Payroll regression carry-back (golden payslip suite, `supabase/golden/`) | committed (slice 0, golden payslip suite) | — |
| 1 | Campuses: make a second branch safe, seed Main + Annex | committed (slice 1, campuses) | — |
| 1b-i | Allowlist guards, can_read_store(), staff read, list_staff_names(), compute_day_totals, regression matrix | committed (slice 1b-i, allowlist guards) | 1 |
| 1b-ii | Admissions Officer role (check constraint, signup fix, invite-staff, frontend + route guard, dev account, sixth matrix column) | committed (slice 1b-ii, Admissions Officer role) | 1b-i |
| 1c | Session timeout readable by every staff role | committed (slice 1c, session timeout read) | 1b-ii |
| 2 | Admissions grade reference data + capabilities layer | committed (admissions slice 2, grade reference data and capabilities) | 1c |
| 3a | Core admissions schema (families, guardians, students, applications, contacts, notes) | committed (admissions 3a) | 2 |
| 3b | Decisions, offers, capacity, campus grade rules | committed (admissions 3b) | 3a |
| 4 | Health info, documents metadata, private bucket | committed (admissions 4) | 3b |
| 5 | Reference numbering + stage transitions + notes/document review RPCs | committed (admissions 5, 8b9c1d4) | 4 |
| 6a | Decisions and capacity (staff side) | committed (5c56735) and applied on hosted | 5 |
| 6b | Offers, enrolment gate, student IDs (staff side) | committed (6c1f014) and applied on hosted | 6a |
| 7a | Staff pipeline UI: list, detail, notes, documents, health panel | built, awaiting Eyram's review (uncommitted) | 6b |
| 7b | Staff pipeline UI: decision/offer/enrol actions, capacity, capability admin | not started | 7a |
| 8 | Public request path (Edge Function, Turnstile, rate limits, intake flag) + public Inquiry form | not started | 7b |
| 9 | Public Application form: direct submit, uploads, matching, rules | not started | 8 |
| 10 | Application drafts: save/resume tokens | not started | 9 |
| 11 | Public offer response page | not started | 8, 6b |
| 12 | Transactional email (outbox, mailer, templates, resend-failed) | not started | 8 (and 6, 9, 10 for the emails it sends) |
| 13 | Lead capture (marketing-site endpoints) | not started | 8, 12 |
| 14 | Bulk email + one-click unsubscribe | not started | 12, 13 |
| 15 | Cutover, domain, TCS OS shutdown (nothing is imported) | not started | all |

Slice 0 is independent of admissions and can run first or in parallel.

## Decisions recorded

All of these were decided by Eyram on **2026-09-29**. The rows in the consolidated decision table below are marked to match.

**Fifth role: Admissions Officer** (supersedes D-2b and the Stage 1 "four roles plus capabilities" decision):

- A new `staff.role` value, `Admissions Officer`, gives baseline access to **admissions tables only**, and nothing in finance, payroll, HR or the store.
- Attendant stays the store role (sales, POS, invoices).
- The capabilities layer stays, for narrowing inside admissions:
  - `can_decide`: Manager or Admissions Officer;
  - `can_view_health`: any role;
  - `grade_bands`: Admissions Officer only.
- Accountant is dropped from `grade_bands`, because a coordinator holding that role would get payroll and finance write access.
- It's built in the new slice 1b, before any admissions table.
- "All bands" for a full officer is an explicit `all_grades` flag, exclusive with `grade_bands` (**D-2g**).
- More roles may be added as other parts of the system are built. CONSTRAINTS.md records how.

**Accepted as recommended:**

- D-1a: rename the existing branch to Main and add Annex.
- D-1b: every existing module stays school-wide on Main.
- D-1c: no campus filter on existing screens in Phase 2.
- D-2a: capabilities in a side table.
- D-2c: bands key on the grade applied for (`year_group_applied_for`), live.
- D-2d: `can_send_bulk_email` isn't a capability; bulk send is Manager only.
- D-2e: only an active Manager grants; self-grant is allowed and audited.
- D-2f: a Manager needs `can_decide` explicitly.
- D-3a: `students` is the long-term Student record.
- D-3b: `academic_year` is text picked from a list.

**Second batch, also decided 2026-09-29, as recommended:**

- **D-2g:** an explicit `all_grades` flag, exclusive with `grade_bands`.
- **D-1b-a:** `can_write()` and `require_writable_role()` become allowlists.
- **D-1b-b:** an Admissions Officer reads `branches`, reads staff names only through a narrow function, and gets no `business_settings` and no store tables.
- **D-1b-c:** Auditor reads admissions read-only; health only if granted.
- **D-1b-d:** the role string is `Admissions Officer`.

**Superseded:** D-2b, replaced by the fifth-role decision above.

---

## Where the code contradicts the brief or the ERP docs (read this first)

These come from reading the code. Where a doc and the code disagree, the plan follows the code.

1. **Grade-band scoping keys on the grade applied for, not the child's current grade.** The filter is `year_group_applied_for__in` (`tcs-os/backend/modules/admissions/admin.py`, `band_lookup` on `ApplicationAdmin`, line 209). TCS OS's own design doc says it filters on "the *current* value of a live column (`year_group_applied_for`)" (`tcs-os/docs/DESIGN.md`, "Live queryset scoping"). `Student.current_grade` (`models.py:217`) is a different field, and nothing scopes on it. CONSTRAINTS.md's phrase "resolved live from the applicant's current grade" should be read as "the current value of the grade applied for". **D-2c decided 2026-09-29: bands key on the grade applied for.** CONSTRAINTS.md is updated to match.
2. **The TCS OS test suite doesn't cover most of the rules this port has to preserve.** `tcs-os/backend/modules/admissions/tests.py` (85 tests) covers:
   - leads and UTM fields;
   - bulk-email audience, placeholders and unsubscribe;
   - the async transactional-email worker;
   - `Administration` group permissions;
   - grade bands and coordinator scoping;
   - `move_to_document_review`;
   - `audit_staff_roles`.

   It has **no tests** for reference formats, stage gating, the capacity warning, the Annex restriction, the preschool vaccination rule, duplicate matching, offer or draft expiry, or upload validation. Those were checked by hand, according to `docs/admissions/02-stack-and-schema.md` and `04-build-log.md`. For them, the port's regression probes have to be written from the rule source (`models.py`, `serializers.py`, `admin.py`), not copied from tests.
3. **Bulk send is atomic per batch, not per message.** Resend's batch endpoint is all-or-nothing for each call of up to 100 emails (`02-stack-and-schema.md:672-674`). TCS OS keeps one bad address from sinking a batch by pre-validating and marking it `skipped_invalid` (`bulk_email.py:43-50`, `enqueue_campaign_send` at `:255`). Each recipient row still ends in exactly one terminal status. "Per-message atomicity" in the brief should read as "one terminal status per recipient row, with batches that fail as a unit and retry as a unit".
4. **TCS OS has a fourth ungranted permission, `admissions.can_send_bulk_email`** (`02-stack-and-schema.md:662`, `admin.py:613-617`). The settled capabilities layer names only three. **Decision D-2d.**
5. **Production TCS OS may be behind the repo.** `tcs-os/docs/deployment.md:12-30` (last reconciled 2026-09-03) says production runs revision `admissions-00019-qm7` with migrations through `0014`. Migrations `0015` (async TransactionalEmail), `0016` (UTM), `0017` (Administration group), `0018` (StaffProfile) and `0019` (coordinator groups) had not been applied. The TCS OS journal doesn't record a later deploy. If that still holds:
   - production sends Inquiry, Application and draft-resume emails **inline**;
   - no coordinators exist in production;
   - nobody but a superuser holds `can_decide`, `can_view_health_info` or `can_send_bulk_email`.

   With nothing to migrate (point 6), the live migration level no longer affects the port.
6. **All TCS OS applications and inquiries are test data; nothing to migrate** (decided 2026-10-11). Still open: whether the 6 leads and 17 guardians who received TCS OS campaign emails are also test data. If any of them are real, their unsubscribe links are the only TCS OS data that would need handling at cutover.
7. **The inquiry form doesn't de-duplicate.** Only the Application path matches existing records (`serializers.py:251-330`). `InquirySerializer.create()` always creates a new Family, Guardians and Students.
8. **An anonymous Application re-submission overwrites existing records.** A submission that matches on guardian email:
   - updates that guardian's fields (`serializers.py:264-272`);
   - updates the matched student's fields;
   - resets a matched application to `stage="application"` from **any** stage, including `enrolled` and `offer` (`serializers.py:300-321`);
   - overwrites `HealthInfo` (`:354`).

   So anyone who knows a parent's email can change that family's contact details and health answers. The port shouldn't copy this. See **D-9b**.
9. **Uploaded file paths are trusted from the client in both systems.**
   - TCS OS mints paths server-side (`storage.py`, `create_upload_target`) but accepts any `file_path` string at submit (`serializers.py` `ApplicationDocumentSerializer`), without checking that it was minted for this submission.
   - The ERP's onboarding flow has the same gap: `submit_onboarding_form(p_uploaded_documents jsonb)` stores client-supplied paths (`20260923100000_qualifications_reference_list.sql:199,239`).
   - Onboarding also puts the **raw token** in the object path (`frontend/src/data/onboarding-store.ts:312`, `onboarding/${token}/…`), so the raw token persists in `storage.objects.name`. That undercuts the "only the hash is stored" design.

   Admissions shouldn't copy either weakness.
10. **Two offer-handling issues in TCS OS:**
    - **Generate Offer isn't atomic.** `admin.py:390-405` saves the Offer, token included, *before* `application.save()` runs the gate. A failed gate leaves a pending offer row behind.
    - **Reset Offer reuses the same token** (`admin.py:417-433`), so a link from an earlier email becomes live again.

    The port wraps generation in one transaction and mints a new token on every re-offer (**D-6b**).
11. **The unsubscribe GET changes state** (`views.py:328-330`). Mail-security link scanners that prefetch GETs can unsubscribe people. See **D-14b**.
12. **The marketing site posts cross-origin to TCS OS.** `https://tcsch.edu.gh` and `*.vercel.app` preview hosts POST to `/api/admissions/quick-interest/` and `/api/admissions/pdf-gate/admissions-overview/` (`02-stack-and-schema.md:731-746`). A redirect can't carry a cross-origin POST with CORS reliably. At cutover those two paths need to be served, or the marketing site repointed.

**ERP-side findings that shape the plan:**

- **13 frontend call sites pick "the" branch with `.from("branches").select(...).limit(1).single()` and no `order by`.** They're in `frontend/src/data/` (`payroll-store.ts:329`, `employees-store.ts:297`, `expenses-store.ts:91`, `invoice-store.ts:130`, `pos-store.ts:167`, `customer-store.ts:60`, `inventory-store.ts:122`, `end-of-day-store.ts:149`, `purchasing-store.ts:176`, `suppliers-store.ts:65`, `pro-forma-store.ts:93`, `held-sales-store.ts:127`, `branch-store.ts:32`). The plan first counted 14. The 14th, `inventory-store.ts:197`, is `setDefaultThreshold`'s `branches` UPDATE keyed by the id from `:122`, not a lookup, so fixing `:122` fixes it. Re-verified on 2026-09-29 against the then-HEAD commit "Enable RLS on deposit_number_counters and revoke anon". Once a second branch row exists, which branch payroll, expenses and invoices write to is undefined. The unique key `payroll_runs (branch_id, month, year)` (`20260908070000_payroll_schema.sql:183`) could then split a month's run across campuses. The database side already picks deterministically: `handle_new_staff_signup` and `post_journal_entry` use `order by created_at limit 1`. **Slice 1 fixes this before any Annex row exists.**
- **No server functions and no Worker `env` access exist today.** There's no `createServerFn` or `*.server.ts` in `frontend/src`, and `frontend/src/server.ts` only wraps SSR errors. The only Edge Function is `supabase/functions/invite-staff` (CORS `*`, SMTP via nodemailer, `index.ts:42-83`). `supabase/config.toml` has no `[functions.*]` blocks. `pg_cron` and `pg_net` are available but not installed locally (`pg_available_extensions`).
- **Local and production branch names differ.** Locally the one branch is `Ho Main Branch` (id `…0001`, from `seed.sql`). `seed.production.sql` creates `Treasures Christian School`.

---

## Conventions for every slice

- **Rules live in the database.** Stage changes, reference numbers, gates, eligibility and capacity checks, token checks, the Annex and vaccination rules, and duplicate matching are all RPCs, triggers, constraints or RLS. React only displays what comes back.
- **Real record contents never appear** in docs, the journal, commits, fixtures, role-matrix probes or chat. Fixtures are invented; the seeded demo payroll people in `seed.sql` are fine because they're dummy data. Real applicant records in the ERP will hold child health data.
- **Tables have select-only RLS for staff and no write grant; writes go through their own SECURITY DEFINER RPC.** This follows the "Financial records" convention in DESIGN.md, applied to admissions because stage and decision history must be un-forgeable.
- Every new invoker RPC runs `revoke execute … from public, anon`, and every new table has explicit grants. `auto_expose_new_tables` is off.
- Every anon-reachable function is `security definer`, pins `search_path`, and validates its own token or size input. Anything that must trust a Turnstile result is **not** anon-executable at all (see "Bot check and email placement").
- Every slice adds a role-matrix probe file at `supabase/role-matrix/<migration>.sql`.
- **Six-column matrices from slice 1b on.** Slices 1b and 2 have all six columns. Slices 3 to 6 have an AO column and fold Attendant and Accountant (✗ throughout) into a note under each table. The tables in slices 7b to 14 predate the fifth role, so each of those slices' planner passes adds an Admissions Officer column. The officer is ✗ on every service-role-only function, gets the same result as anon on token-gated anon functions, and follows the roles and capabilities matrix for staff reads and writes. Attendant and Accountant are ✗ on all admissions data.
- **Capability variants are separate probes.** `scripts/role-matrix.sh` impersonates exactly one staff account per role, so each capability variant (with or without `can_decide`, in or out of band, with or without health) gets its own probe. The probe's postgres setup section grants or revokes the capability on that role's dev account.
- **Service-role-only functions** are asserted with `-- expect: none` (every JWT role denied). Their positive path is tested separately as `service_role`, in a rolled-back psql transaction.
- Every slice ends at the loop's step 7: stop for Eyram's review and don't start the next slice. Docs are updated in the same slice: DESIGN.md gets any new convention, and JOURNAL.md always gets an entry.
- Production steps (`db push`, `functions deploy`, `secrets set`, `wrangler deploy`, DNS, Cloudflare dashboard changes) are Eyram's. A slice hands over the exact command and never runs it.

## Recommended shapes the slices build on (each needs Eyram's confirmation)

**Admissions grade reference (slice 2).** One table, `admissions_grades`, replaces TCS OS's hand-kept `STUDENT_ID_CLASSIFICATION` and the `GRADE_BANDS` derived from it (`models.py:24-52`), so the two can't drift apart. Columns: `name`, `position`, `classification_code` (`01`–`04`, null for none), `band` (`preschool` | `primary` | `jhs` | null), `is_preschool_vaccination_required`, `is_active`.

It's seeded in the migration because it's entity-wide reference data. The seed is the 14 TCS OS grades: Pre Nursery, Nursery 1, Nursery 2, Kindergarten 1 and Kindergarten 2 are preschool (codes `01` and `02`); Grades 1–6 are primary (`03`); Grades 7–9 are JHS (`04`). **No SHS rows get a code**, following the `TODO(SHS)` at `models.py:16-23`. `applications.year_group_applied_for` stays `text`, so free-text "Other" grades still round-trip and resolve to no band. That's the same pattern as `employees.position`.

**Roles and capabilities (slices 1b and 2). Decided 2026-09-29.**

Admissions access comes from two layers:

1. **Role (slice 1b).** A fifth `staff.role` value, `Admissions Officer`, gives **baseline access to admissions tables only**, and nothing in finance, payroll, HR or the store. Attendant stays the store role (sales, POS, invoices) and gets **no** admissions access. Accountant gets none either, because Accountant holds payroll and finance write access, and an admissions coordinator shouldn't.
2. **Capabilities (slice 2)** narrow or unlock actions *inside* admissions. They never grant anything outside admissions, and they start ungranted.

A side table, `staff_admissions_capabilities`, keyed by `staff_id` (PK, FK to `staff`) (D-2a, decided):

| Column | Meaning | Who may hold it (decided) |
|---|---|---|
| `can_decide boolean not null default false` | May record decisions and generate or reset offers. | Manager or Admissions Officer |
| `can_view_health boolean not null default false` | The child-health gate. | Any role |
| `grade_bands text[] not null default '{}'` | Values from `admissions_grades.band`. | Admissions Officer only |
| `all_grades boolean not null default false` | The "all bands" marker for a full officer (D-2g, decided). | Admissions Officer only |
| `granted_by`, `updated_at` | Server-forced identity columns. | — |

No row means nothing is granted. Writes go only through `set_admissions_capabilities(p_staff_id, p_can_decide, p_can_view_health, p_grade_bands, p_all_grades)`. Only an active Manager may call it, and self-grant is allowed but audited (D-2e, decided). Every change lands in `audit_log` through an AFTER trigger, with a new action value, `admissions_capabilities_changed`. A check constraint (or trigger, since it needs `staff.role`) refuses a capability the holder's role may not hold.

It's a side table rather than columns on `staff` because `staff_update` is a whole-row Manager policy (`pg_policies`: `staff_update` = `has_role(['Manager'])`), so capability columns there could be PATCHed directly with no audit. A side table also keeps `staff`'s existing triggers (`staff_protect_row`, `staff_onboarding_recompute`) out of it.

**How a full officer sees everything (D-2g, decided 2026-09-29).** Band scoping resolves live from `applications.year_group_applied_for`, the grade applied for (D-2c). Some grades have no band: Grades 10–12 (SHS) and free-text "Other" grades. TCS OS showed those only to Administration.

A full officer is marked by an explicit **`all_grades boolean`**, meaning "every application, including unbanded grades". It's separate from `grade_bands`, so it can't be confused with "listed all three bands", which still excludes unbanded grades. A check refuses `all_grades = true` together with a non-empty `grade_bands`, so exactly one scoping mode applies.

Two alternatives were rejected:

- a sentinel `'all'` value inside `grade_bands`, because it overloads a list with a magic value;
- "empty means all", because it inverts TCS OS's safety default: a misconfigured coordinator saw nothing.

Predicates:

- `admissions_grade_visible(p_grade text)`.
  - **Manager and Auditor** see every admissions row, including unbanded grades.
  - **An Admissions Officer** sees a grade if `all_grades` is set, or if the grade's band is in their `grade_bands`. With neither, they see nothing (TCS OS's `scoped_grades_for` safety default).
  - **Attendant and Accountant:** always false.
- `has_admissions_capability('decide' | 'health')`.

Role and capability matrix (decided except where marked):

| | Manager | Admissions Officer | Attendant | Accountant | Auditor |
|---|---|---|---|---|---|
| Any access to finance, payroll, HR or store tables | as today | **none** | as today | as today | as today |
| See non-health admissions rows | all | `all_grades`, or in-band only | none | none | all (read-only) |
| Add or edit notes, set document status, move to Document Review | yes | in scope | no | no | no |
| Unrestricted stage moves, mark enrolled, capacity edits | yes | no | no | no | no |
| Record decision, generate or reset offer | only if `can_decide` | only if `can_decide`, and in scope | never | never | never |
| See health info | only if `can_view_health` | only if `can_view_health`, and in scope | only if `can_view_health`, but sees no admissions rows, so effectively never | same as Attendant | only if `can_view_health` |
| Grant capabilities | yes | no | no | no | no |

"In scope" means the application's grade is visible to that officer under `admissions_grade_visible`. The first two action rows follow TCS OS's coordinator permission bundle (`02-stack-and-schema.md:879-888`). The Auditor column follows the rule that the Auditor is read-only everywhere: the Auditor reads admissions, and health only if granted (D-1b-c).

**Stages (slices 3 and 5).** Keep TCS OS's eight values: `inquiry`, `application`, `document_review`, `offer`, `enrolled`, `waitlisted`, `rejected`, `offer_declined` (`models.py:230-239`). Stage has no UPDATE grant. Only the RPCs in slices 5 and 6 change it.

---

## Slice 0 — Payroll regression carry-back

**Status:** committed (slice 0, golden payslip suite).

**Delivers:** `supabase/golden/payslips.sql` (statutory-derived cases, Eyram's overtime figures, the Emmanuel Ansah parity case, run probes and the commented PENDING cases) and `supabase/golden/payslips-tcsos-hand.sql` (the TCS OS hand-computed tier only, D-0c), run together by `./scripts/golden-payslips.sh`. It replaces the originally planned `supabase/role-matrix/payroll-regression.sql`.

- Each payslip probe's setup (as postgres) inserts an invented employee, an `employee_pay_config` (basic salary and `pays_*` flags) and a `payroll_runs` row for August, September or October 2026. The body calls `create_payslip()` against the real rate rows and compares every field with the hand-derived figures through a rolled-back `pg_temp.golden_check()` helper, which raises one line naming each field as `exp=` / `got=`.
- G0 pins the rate rows themselves; the run probes (GA-X1 to GA-X3) cover an exclusion, posting with and without the overtime-tax line, and a refused submission.
- PENDING cases stay commented out, with their inputs and expected values written down, until the accountant confirms them.

**Not included:** no schema changes to payroll. Statutory numbers (`statutory_rates`, `paye_bands`, `overtime_tax_rates`) already live in the database.

**TCS OS files to read:** `docs/DESIGN.md:140-155`; `docs/JOURNAL.md:638-700, 878-919`; `docs/CONSTRAINTS.md:50-75`; `backend/modules/hr/tests.py:74-212`; `backend/modules/hr/payroll.py:70-80`; `backend/modules/hr/management/commands/run_parity_test_payroll.py:55-67`; `seed_parity_test_employees.py:40-50`.

**DESIGN.md conventions:** computed-never-stored (don't store expected values in tables); effective-dated config (the probe's run month must fall inside the pay config's and `statutory_rates`' effective range; live rates are effective 2025-01-01); flexible allowances (`allowance_types.taxable`); overtime kept out of allowances; per-employee exemption flags; mutation window (Draft only).

**Role matrix:** every `create_payslip` probe and GA-X3 expect Manager and Accountant (the four other roles are denied by `require_finance_writer()`); the posting probes GA-X1 and GA-X2 expect Manager only; G0 expects all six roles. Capability variants don't apply.

**Anon surface:** none.

**Decisions (made 2026-10-07):**

- **D-0a (written off).** Abena Konadu Owusu and Yaw Darko Asamoah were dummy records. They are removed from the plan, with no pending cases.
- **D-0b.** Moved from pending to asserted, accountant confirmed (reported, written copy to be saved), reported by Eyram 2026-10-07: fines and IOU repayments come off after tax and don't reduce taxable income, with no cap on total deductions; a PAYE amount of exactly half a pesewa rounds up; the contribution split (employee SSNIT 0.5%, employee Tier 2 5%, employer SSNIT 13%, employer Tier 2 0); no SSNIT contribution ceiling known to the accountant (high-earner cases); normal PAYE rates for non-qualifying overtime; non-qualifying overtime enters the PAYE base at the printed amount (hours × rate rounded to 2 dp), asserted as probes E-R1 and E-R2. Still PENDING (commented out): non-taxable allowances ("subject to GRA policy"; all allowances stay taxable until he names an exemption), a National Service payslip showing taxable income with no PAYE, and the posting accounts for fines (4910) and IOU (1350).
- **D-0c (decided yes).** The TCS OS hand-computed cases are in their own file, `payslips-tcsos-hand.sql`, labelled "TCS OS hand-computed, not ERP-confirmed".
- **D-0d (decided).** The 2025-01-01 band set is asserted but labelled "current behaviour, not confirmed correct"; the accountant said only that the new bands apply from now. The 2026-09-01 set is what applies to the first real payroll.

**Size:** two probe files and one wrapper script, no schema or frontend change.

## Slice 1 — Campuses: make a second branch safe, seed Main and Annex

**Delivers:**

- Replace the 13 non-deterministic `branches … limit(1).single()` lookups with one shared helper, `getSchoolBranchId()` in `data/branch-store.ts`. It resolves `order by created_at limit 1`, the same rule the DB functions use. Recommendation D-1b: payroll, expenses, accounting, POS and inventory stay **school-wide on the oldest branch (Main)**.
- ~~`branch-store.ts` exposes the list of branches (id, name) for the admissions campus picker only.~~ Deferred on 2026-09-29 to the slice that builds the picker (7a or 9). Nothing consumes it before then, and that slice decides its ordering and filtering.
- Seeds:
  - `seed.sql` (local): rename `Ho Main Branch` to `Main` and add an `Annex` row. The Annex `created_at` must be later than Main's.
  - `seed.production.sql`: after the existing branch reuse or creation, idempotently rename the oldest branch to `Main` (D-1a) and insert `Annex` if it's missing. The branch-scoped seeders keep targeting only Main.
- A DESIGN.md note: "branches = campuses. The oldest is Main and hosts school-wide records." There's no migration comment, because the slice has no migration.

**Not included:** no admissions tables, no campus filter on existing screens (D-1c), no per-campus settings.

**TCS OS files to read:** `backend/modules/admissions/migrations/0009_seed_campuses.py`; `models.py:180-193` (Campus); `docs/admissions/02-stack-and-schema.md:474-480`.

**Conventions:** two seed files split by trust; entity-wide reference data in migrations (this is branch data, so it goes in seeds); `branches` RLS is unchanged (`branches_select is_active_staff()`, insert with no qual, update `can_write()`, delete Manager).

**Role matrix:** no RPC or RLS change. Add one probe that proves two branch rows don't change who can read branches: all staff ✓, anon ✗.

**Anon surface:** none.

**Decisions for Eyram:**

- **D-1a (decided 2026-09-29, as recommended).** Rename the existing production branch to "Main" rather than adding two new rows. Recommendation: rename, so every existing `branch_id` FK stays on Main. The rename is visible where the branch name is displayed (`useCurrentBranch()` in `end-of-day.index.tsx`, `pro-forma.new.tsx`). Renaming the hosted row is a data change Eyram runs through `seed.production.sql`.
- **D-1b (decided 2026-09-29, as recommended).** Which existing modules stay school-wide. Recommendation: all of them for now (payroll, expenses, accounting, POS). Admissions is the only campus-aware module.
- **D-1c (decided 2026-09-29, as recommended).** Which screens get a campus filter. Recommendation: none in Phase 2. Revisit if payroll ever needs per-campus runs.

**Size:** one small frontend refactor (13 call sites to one helper), two seed edits and one probe. No migration.

## Slice 1b-i — Allowlist guards (no new role yet)

The original slice 1b was split on 2026-09-29 into two: 1b-i (this slice, guards only) and 1b-ii (add the role). This slice rewrites the two denylist guards as allowlists and closes the read exposure before any new role exists, with no behaviour change for the four existing roles. Slice 1b-ii adds the Admissions Officer.

### Split and decisions (2026-09-29)

Eyram's confirmed decisions: (1) guard rewrites approved: a role outside the list gets `'This action is not available to your role'`, and Auditor keeps its read-only message; (2) staff read = `can_read_store()` or own-row form `(id = auth.uid() and is_active_staff())`; (3) `list_staff_names()` returns id and name for **ALL** staff, active or not; (4) officer reads branches; (5) no Admissions sidebar section until slice 7a; (6) route-guard allowlist for the officer; (7) hide the Settings tabs that read `business_settings` from the officer; (8) split 1b into 1b-i and 1b-ii. Decisions 4–7 are built in 1b-ii.

**Delivers:**

- **Write guards become allowlists (D-1b-a, decided).** Today they're denylists, so a new role would inherit store write access automatically:
  - `can_write()` is currently `is_active_staff() and not has_role(['Accountant','Auditor'])`. It becomes `has_role(['Manager','Attendant'])`, the same meaning for the existing four roles. Without this change an Admissions Officer passes `can_write()` and gets INSERT/UPDATE on the 19 store tables listed below.
  - `require_writable_role()` currently rejects only Auditor. It becomes an allowlist of `Manager`, `Attendant` and `Accountant`, same meaning for the existing roles, plus an explicit rejection message for Admissions Officer. 28 RPCs call it (list below). The invoker ones then fall through to table RLS, which is now an allowlist too. The definer ones (`create_bank_account`, `void_invoice`, `void_sale`) already carry their own `has_role` allowlist.
  - Re-read every `has_role(...)` array in migrations and confirm none uses a negation. The live audit found none.
- **Read-exposure fixes (D-1b-b, decided)** (see the audit table below):
  - The `is_active_staff()` read policies on store tables and on `business_settings` switch to an allowlist predicate, `can_read_store()` = `has_role(['Manager','Attendant','Accountant','Auditor'])`.
  - `branches` keeps `is_active_staff()`, so the officer can read it for the campus picker.
  - The `staff` select policy switches to own-row form: `can_read_store() or (id = auth.uid() and is_active_staff())` — inactive staff still see no one.
  - A narrow SECURITY DEFINER function, `list_staff_names()`, returns only `id` and `name` of **ALL** staff (active or not), for note authors and the like. It's executable by `authenticated` and `service_role`, and revoked from `public` and `anon`.
  - `compute_day_totals` gets a `can_read_store()` check.
- **Probe file:** `supabase/role-matrix/<migration>_allowlist_guards_regression.sql` proves the four existing roles are unchanged (100 probes: 6 guard truth-table, 24 table-read, 38 write, 28 RPC, compute_day_totals). Output byte-identical on pre- and post-migration schema. Catalog diff: only the 23 select-policy changes, 2 new functions, 3 changed bodies; no existing grant changed.
- **New-surface file:** `supabase/role-matrix/<migration>_allowlist_guards_new_surface.sql` (6 probes: can_read_store truth incl. inactive, list_staff_names all roles incl. inactive, anon denial), all match.
- **DESIGN.md:** the guard predicates are documented as allowlists, `can_read_store()` is added, staff own-row form, `list_staff_names()`, and a one-line rule: guards are allowlists; never add a role by negation.

**Not included:** the Admissions Officer role itself, any admissions table or capability (slice 2 onward). Slice 1b-ii adds the role. The role has no admissions data to see until slice 3.

**Read exposure today: what a new role would reach through `is_active_staff()` and friends.** This is the live audit of the local DB (`pg_policies`, `pg_proc`), 2026-09-29.

| Mechanism | Tables or functions a new active role would reach today | After slice 1b (recommended) |
|---|---|---|
| `is_active_staff()` SELECT policies (24 tables) | `branches`, `business_settings`, `customer_deposits`, `customer_discounts`, `customers`, `day_closes`, `deposit_number_counters`, `held_sales`, `invoice_lines`, `invoice_number_counters`, `invoice_payments`, `invoices`, `manager_overrides`, `pro_forma_invoice_lines`, `pro_forma_invoice_number_counters`, `pro_forma_invoices`, `products`, `sale_lines`, `sale_number_counters`, `sale_payments`, `sale_returns`, `sales`, `staff`, `stock_movements` | Store tables and `business_settings` move to `can_read_store()`. `staff` moves to the same allowlist, and officers get names via `list_staff_names()`. `branches` stays `is_active_staff()` (D-1b-b). |
| `can_write()` INSERT/UPDATE/DELETE policies (19 tables) | `branches`, `customer_deposits`, `customers`, `deposit_number_counters`, `held_sales`, `invoice_lines`, `invoice_number_counters`, `invoice_payments`, `invoices`, `pro_forma_invoice_lines`, `pro_forma_invoice_number_counters`, `pro_forma_invoices`, `products`, `sale_lines`, `sale_number_counters`, `sale_payments`, `sale_returns`, `sales`, `stock_movements` | Denied (allowlist). |
| RPCs guarded by `require_writable_role()` (28) | `adjust_product_stock`, `cancel_bank_reconciliation`, `cancel_customer_deposit`, `cancel_purchase_order`, `clear_statement_line`, `complete_bank_reconciliation`, `convert_pro_forma_to_invoice`, `create_bank_account`, `create_customer_deposit`, `create_customer_discount`, `create_invoice`, `create_pro_forma_invoice`, `create_purchase_order`, `create_sale`, `create_sale_return`, `create_sale_return_batch`, `create_supplier`, `import_bank_statement_lines`, `match_statement_line`, `place_purchase_order`, `receive_purchase_order`, `record_invoice_payment`, `record_supplier_payment`, `start_bank_reconciliation`, `unmatch_statement_line`, `update_invoice`, `void_invoice`, `void_sale`. Of these, 8 have no `has_role` of their own (`adjust_product_stock`, `convert_pro_forma_to_invoice`, `create_customer_deposit`, `create_invoice`, `create_pro_forma_invoice`, `create_sale_return_batch`, `record_invoice_payment`, `update_invoice`), all invoker, so today only table RLS (`can_write()`) stops them. | Rejected at the guard. |
| Staff-only definer function | `compute_day_totals` (SECURITY DEFINER, guarded only by `require_staff`/`is_active_staff`, so it bypasses sales RLS) | Add a role allowlist. |
| Own-row policy | `notifications` (`recipient_id = auth.uid()`) | Unchanged; harmless. |
| `has_role([...])` allowlists | every finance, payroll, HR and onboarding table and every storage bucket policy | Already excluded. Nothing to change. |

**DESIGN.md conventions:** the RLS role model (this slice rewrites its predicates); explicit grants; `drop function` before changing an argument list (the predicates keep their signatures); identity columns unchanged; a new "Regression-proofing a guard change" note (generate a probe from catalog, run unchanged on old and new schema, require byte-identical output plus catalog diff; example files listed).

**Role matrix:** five columns (anon, Attendant, Manager, Accountant, Auditor only). Every guard probe keeps its current result for the four existing roles after the rewrite. anon is ✗ everywhere. No Admissions Officer column yet (slice 1b-ii).

**Anon surface:** none.

**Decisions (all decided 2026-09-29):**

- **D-1b-a.** Allowlist guards, not added deny arrays, which would repeat the same trap for every future role.
- **D-1b-b.** Built here: `can_read_store()`, the `staff` own-row read and `list_staff_names()`, so a role outside the four gets no store tables, no `business_settings` and no staff directory. The officer reading `branches` needs nothing new (`branches` keeps `is_active_staff()`).
- **D-1b-c.** Auditor reads admissions read-only; health only if granted. Nothing to build until admissions tables exist (slices 3 and 4).
- **D-1b-d.** The role string is `Admissions Officer`. Used in 1b-ii.

**Open item:** no route in the app has an access guard (no `beforeLoad`). Pages are protected only by sidebar visibility, some in-page checks, and RLS. 1b-ii adds a route-guard allowlist for the officer. Guards for the other roles aren't planned; see "Open unknowns".

**Size:** one migration (two guards rewritten, one new predicate, 23 policy changes, two functions), no frontend changes yet, and about 100 probes split across two files. Mechanical. No behaviour change for the four existing roles; the probes prove it.

## Slice 1b-ii — Admissions Officer role

Adds the fifth role on top of 1b-i's allowlists. It ships before any admissions table, so the role exists, and is proven to reach nothing, before it's given anything.

**Delivers:**

- **`staff.role` check constraint:** add `'Admissions Officer'` to `staff_role_check` (drop and recreate, in a new migration).
- **`handle_new_staff_signup`:** changed to reject unlisted roles explicitly instead of silently defaulting to Attendant. An invite with an unknown role raises 'Unknown staff role: <role>'. A missing `role` metadata field still defaults to Attendant (seed paths depend on it). Add `'Admissions Officer'` to the list of allowed roles.
- **`supabase/functions/invite-staff/index.ts`:** add the role to `ALLOWED_ROLES`.
- **Frontend:**
  - the `StaffRole` union in `data/auth-store.ts`, and `STAFF_ROLES` in `routes/settings.tsx` (the role dropdown and the invite dialog);
  - add `isAdmissionsOfficer()` helper to `data/auth-store.ts`.
  - the "Roles & permissions" note in Settings, which names five roles now;
  - sidebar: hide the Procurement & Stores section from the officer (Finance and HR are already hidden by `canViewFinancials`). No Admissions section until slice 7a (decision 5);
  - Dashboard: a separate `OfficerDashboard()` component that loads no data (useDashboard is not called) and renders only a welcome message. Routed via `isAdmissionsOfficer()`;
  - topbar: the global search (customers, products, invoices, expenses, suppliers) is extracted into a separate `GlobalSearch()` component; it is only mounted for non-officers (since they cannot read store data);
  - route guard (decision 6): an allowlist of routes for the officer in the app shell (`"/"` and `"/settings"`). Any other route redirects to `/`. The guard also checks `resolvedLocation` (not just `pathname`) because the router keeps rendering the old match right after a redirect, and that would mount the blocked page's data-fetching hooks;
  - Settings (decision 7): hide six tabs from the officer: `documents`, `tax`, `inventory`, `expenses`, `notifications`, `security`. `documents`, `inventory` and `expenses` load store tables; `tax`, `notifications` and `security` read `business_settings`;
  - any other role-name `switch` or map (grep for `"Attendant"`).
- **`scripts/seed-local-dev-staff.sh`:** a fifth dev account, `dev-admissions@tcs.test`, role Admissions Officer. Update CLAUDE.md's dev-accounts table too.
- **`scripts/role-matrix.sh`:** six roles (anon, Attendant, Manager, Accountant, Auditor, Admissions Officer), Column widths are unchanged (the officer is the last column, so only its header label overflows). `-- expect:` parsing now trims around commas instead of deleting every space, so `Admissions Officer` can match. Header docs updated.
- **Probes:**
  - all five existing probe files re-run with the sixth column (the officer was added to 9 `-- expect:` lines in the two 1b-i files and `campuses-main-annex.sql`). The five existing columns are byte-identical to a baseline run with the committed script and probe files on the pre-migration schema, once the officer column and its error lines are removed.
  - `supabase/role-matrix/20260929130000_admissions_officer_role.sql` (new): 30 probes proving the officer is **denied** on finance (`accounts`, `journal_entries`, `expenses`, `bank_accounts`), payroll (`payroll_runs`, `payslips`, `employee_pay_config`, `create_payslip`), HR (`employees`, `employee_documents`, the onboarding tables) and the three storage buckets (`receipts`, `onboarding-documents`, `employee-generated-documents`). The officer also has probes for `list_staff_names()`, `branches` read, and seeing only their own `staff` row. Signup probes confirm that an invite with role 'Admissions Officer' lands as that role, 'Janitor' is rejected, and a missing role defaults to Attendant.
- **DESIGN.md:** the role list gains Admissions Officer; the RLS model bullet updated to five roles; a new note on the UI side of role-gating (split components and checking resolvedLocation).

**Not included:** any admissions table or capability (slice 2 onward). The role has no admissions data to see until slice 3.

**TCS OS files to read:** `docs/admissions/02-stack-and-schema.md:804-911` (the coordinator permission bundle the role replaces); `migrations/0017_administration_group.py`, `0019_coordinator_groups.py`.

**DESIGN.md conventions:** the RLS role model; explicit grants; the CONSTRAINTS.md "Adding a role" procedure.

**Role matrix:** six columns. The officer is ✗ on every finance, payroll, HR and store probe, ✓ on `branches` read, `list_staff_names()` and their own `staff` row. anon is ✗ everywhere.

**Anon surface:** none.

**Open unknowns:**

- **(a) Officer inactivity auto-logout never arms.** Addressed by slice 1c (committed): `get_session_timeout_minutes()` returns the timeout value to every staff role including the officer, bypassing the restriction on `business_settings`.
- **(b) Missing role defaults to Attendant.** `handle_new_staff_signup` still defaults a missing `role` metadata field to Attendant (seed paths and local-dev scripts rely on it). An explicit unlisted role is now rejected. Tighten it (reject a missing role) once the seed paths (supabase/seed.sql, scripts/seed-local-dev-staff.sh) pass a role explicitly.
- Route guards for the other four roles are still not built (existing open item).

**Gates:** all permissions (the officer's `branches` read, own `staff` row and `list_staff_names()`) decided 2026-09-29 (D-1b-b, D-1b-d, decisions 4–7 above). Committed as slice 1b-ii (Admissions Officer role).

**Size:** one small migration, one Edge Function line, a frontend pass (role type, dropdown, sidebar, Dashboard, topbar, route guard, Settings tabs), two script edits, a new 30-probe file, and the five existing probe files re-run with the sixth column.

## Slice 2 — Admissions grade reference data and the capabilities layer

**Delivers:**

- Migration:
  - `admissions_grades` (seeded).
  - `staff_admissions_capabilities` (see "Roles and capabilities"), with checks that `grade_bands <@ array['preschool','primary','jhs']` and that `all_grades` and a non-empty `grade_bands` aren't both set (D-2g).
  - A trigger enforcing who may hold what (decided D-2b-revised): `can_decide` only for Manager or Admissions Officer; `grade_bands` and `all_grades` only for Admissions Officer; `can_view_health` for any role. It also re-checks when a staff member's role changes: a role change that would leave a disallowed capability is refused until the capability is cleared.
  - Predicates `admissions_grade_band(text)`, `admissions_grade_visible(text)` and `has_admissions_capability(text)`, all SECURITY DEFINER, stable, `search_path` pinned. They follow `has_role()`'s shape.
  - `set_admissions_capabilities(...)`, active Manager only; self-grant allowed and audited (D-2e).
  - An audit trigger.
- Settings → Staff: an "Admissions access" panel per staff member. Manager edits; everyone else is read-only. The panel shows only the capabilities the member's role may hold.
- A DESIGN.md entry for the capabilities convention.

**Not included:** no admissions data tables yet; the predicates are tested against invented grade strings. The role itself is slice 1b.

**TCS OS files to read:** `models.py:24-52` and `:930-967`; `access.py`; `admin.py:26-83` (GradeBandScopedAdmin and Inline); migrations `0017_administration_group.py`, `0018_staffprofile.py`, `0019_coordinator_groups.py`; `management/commands/audit_staff_roles.py`; `docs/admissions/02-stack-and-schema.md:282-310, 804-911`; `docs/DESIGN.md` (TCS OS) "Architecture & RBAC".

**Conventions:** explicit grants; RLS via predicates, never hand-rolled checks; identity columns server-forced (`granted_by`); computed-never-stored (bands resolve live from the grade applied for, never stored per application); no `update` grant (writes go through the RPC); audit_log is trigger-written.

**Role matrix:** six columns, and AO is Admissions Officer. Rows starting with "AO with …" are capability variants on the officer's dev account.

| Probe | anon | Att | Mgr | Acc | Aud | AO |
|---|---|---|---|---|---|---|
| `set_admissions_capabilities` | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| Direct insert or update on `staff_admissions_capabilities` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Select own capability row | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Select all capability rows | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ |
| `admissions_grade_visible('Grade 3')`, no capability row | — | false | true | false | true | false |
| Same, AO with `{primary}` | | | | | | true |
| Same, AO with `{preschool}` | | | | | | false |
| Same, AO with `all_grades` | | | | | | true |
| `admissions_grade_visible('Grade 11')` (unbanded), AO with all three bands | | | | | | false |
| Same, AO with `all_grades` | | | | | | true |
| Grant `can_decide` to Attendant, Accountant or Auditor | refused | | | | | |
| Grant `can_decide` to Manager or AO | allowed | | | | | |
| Grant `grade_bands` or `all_grades` to anyone but AO | refused | | | | | |
| Grant `can_view_health` to each of the five roles | allowed | | | | | |
| Change an AO holding bands to Attendant | refused until cleared | | | | | |

Each capability case is a separate probe that raises when the boolean is wrong. `admissions_grades` select: Manager, Auditor and AO ✓; Attendant and Accountant ✗; anon ✗ (the public read happens through a function in slice 8).

**Anon surface:** none. Revoke from anon on every new function; the predicates return false for anon anyway.

**Decisions:** D-2a, D-2c, D-2d, D-2e and D-2f are decided. D-2b is superseded by the fifth-role decision and its revised capability holders. D-2g is decided (an explicit `all_grades` flag). Nothing is open before this slice starts.

### Decisions (2026-10-05)

Built and confirmed as recommended:

- **O-1.** Deactivating a staff member clears their admissions access (audited as a change by the deactivating Manager).
- **O-2.** Grade name matching in `admissions_grade_band()` ignores case and extra whitespace.
- **O-3.** No SHS rows until TCS offers SHS. Legacy Grade 10 and 11 labels resolve to no grade.
- **O-4.** Predicates are executable by every staff role, not anon. The RPC is active-Manager-only.
- **O-5.** Unknown capability name raises in `has_admissions_capability()`.
- **O-6.** `can_view_health` is not offered in the UI to Attendant and Accountant unless revoking an existing grant; the DB stays permissive.
- **O-7.** All-empty row deletes the row; empty rows are forbidden by check.
- **O-8.** An Accountant reading capability changes via the existing `audit_log` policy is accepted.
- **O-9.** No guard prevents a Manager from revoking their own `can_decide`.

Also confirmed (2026-09-29, built in slice 2):

- **D-2b-revised.** `can_decide` only Manager/Officer; `grade_bands` and `all_grades` only Officer; `can_view_health` any role.
- **D-2g.** `all_grades` can't be combined with a non-empty `grade_bands` (an officer may hold neither).

Gates confirmed by Eyram (2026-10-05): the new reads (capability rows: own row for every active staff member, all rows for Manager and Auditor; `admissions_grades` for Manager, Auditor and Admissions Officer); the Accountant reading capability changes through the existing `audit_log` policy; a Manager's role change refused while a disallowed capability is held; the predicates executable by every staff role, not anon.

**Size (as built):** one migration (2 tables, 10 functions, 5 triggers, one `audit_log_action_check` value), a Staff-tab column with a Manager dialog, and 87 probes in two files.

## Slice 3a — Core admissions schema: families, guardians, students, applications, contacts, notes

Slice 3 split into two (approved 2026-10-10): 3a builds the applicant core tables with staff RLS; 3b builds decisions, offers and campus rules.

**Delivers:** one migration `20261011100000_admissions_core_applicants.sql` with six tables:

- `families`: `referral_source` (check-constrained to TCS OS's 8 values, `models.py:122-131`), `referral_source_other`, `comments`.
- `guardians`: `family_id`, `first_name`, `surname`, `email` (lowercased and trimmed by trigger, following DESIGN's email normalisation), `phone`, `relationship`, `religion`, `address`, `town_city`, `bulk_email_unsubscribe_token_hash` (unique, nullable until slice 14), `bulk_email_unsubscribed_at`.
- `students`: `family_id`, `full_name`, `date_of_birth`, `gender`, `nationality`, address block, `current_school`, `previous_school_location`, `current_grade`, and `student_id` (unique, null until enrolment, assigned in slice 6).
- `applications`: `student_id`, `stage` (the eight TCS OS values, no UPDATE grant), `academic_year`, `year_group_applied_for`, `month_of_enrollment`, `inquiry_reference` and `application_reference` (both nullable, unique when set), `branch_id` (nullable: inquiries carry no campus), `wants_scholarship_info`, `scholarship_interest_details`, `declaration_signature_name`, `declaration_agreed`, `declaration_agreed_at`, `declaration_ip_address`, `media_consent_agreed`, `created_at`, `updated_at`.
- `application_emergency_contacts`: `application_id`, `name`, `relationship`, `phone`.
- `application_notes`: `application_id`, `author_id` (server-forced when auth.uid() is set, so hand imports keep original authors), `content`, `created_at` (server-set only when auth.uid() is set).

Select-only RLS on every table for `authenticated`; no write grants or policies yet (slice 5 adds write RPCs). Staff reads go through three SECURITY DEFINER visibility helpers that resolve scope live from `applications.year_group_applied_for` (D-3d):
- **`admissions_application_visible(uuid)`**: true when the application exists and its grade is visible to the caller (Manager and Auditor: every application; an Admissions Officer: in scope only; Attendant and Accountant: never). Emergency contacts and notes use it.
- **`admissions_student_visible(uuid)`**: true when one of the student's applications is visible; Manager and Auditor get true for any id, so they also see a student with no application.
- **`admissions_family_visible(uuid)`**: true when one of the family's students has a visible application; Manager and Auditor get true for any id. Guardians use it too, so siblings in other bands stay hidden (D-3d).

**Deviations from the planner's draft:** (1) student_id accepts 4+ trailing digits (TCS OS pads to 4 but doesn't cap, `models.py:113`); (2) `inquiry_reference` and `application_reference` regexes accept 4+ digits, not exactly 4 (`models.py:65-74`); (3) the note trigger forces both `author_id` and `created_at` when `auth.uid()` is set; with no signed-in user (the slice 15 import) the supplied values stand.

**Corrections found during planning:** the plan said "about 11 tables" — slice 3 is actually 10 (6 here in 3a, 4 in 3b: decisions, offers, capacity, campus rules). Annex campus grade rules can't be seeded in the migration because Annex is inserted by `supabase/seed.sql` and `supabase/seed.production.sql`, which run after migrations, so 3b puts those rows in both `seed.sql` and `seed.production.sql` keyed by `branch_id`. The plan omitted several columns: `declaration_signature_name`, `declaration_agreed`, `wants_scholarship_info`, `scholarship_interest_details`, `applications.updated_at`, emergency contact name/relationship/phone. The IP column keeps TCS OS's name `declaration_ip_address`, type `inet`.

**Not included:** decisions, offers, capacity, campus rules (slice 3b); health info, documents, storage (slice 4); numbering, stage RPCs (slice 5); public anything.

**TCS OS files to read:** `models.py:118-300, 581-594, 656-666`; `serializers.py:14-31`; `docs/admissions/02-stack-and-schema.md:11-46, 467-530`.

**Conventions:** explicit grants; select-only tables with RPC-only writes (slice 5 adds them); identity columns server-forced only when auth.uid() is set; `drop function` before changing an argument list (for 3b and later).

**Role matrix:** `supabase/role-matrix/20261011100000_admissions_core_applicants_visibility.sql` (51 probes) + `…_structure.sql` (39 probes). Sample rows: Manager and Auditor read every application; Admissions Officer with `{primary}` reads Grade 3, not Grade 7; unbanded Grade 11 visible to Manager, Auditor and all_grades officers only; siblings in different bands hidden from an in-band officer; a live grade change (Grade 6 → 7) moves an application between visible and hidden for a band-scoped officer; direct insert/update/delete on any table refused for all roles; anon has no table grant.

**Anon surface:** none. No anon grants; `revoke all … from anon` on every table and visibility helper.

**Decisions (approved 2026-10-10):**

- **D-3a (decided 2026-09-29, as recommended).** Is `students` the long-term Student record? Yes — it becomes the Student Management record later (PLANNING.md).
- **D-3b (decided 2026-09-29, as recommended).** Is `academic_year` free text? Yes, picked from a list in the form.
- **D-3c.** Capacity readable by: **Manager and Auditor only** (not Admissions Officers). Writes are slice 7b.
- **D-3d.** Sibling visibility: officers read families, guardians, students and applications **only for in-scope children**. Siblings in other bands are hidden — a deliberate change from TCS OS's unscoped StudentInline on the family page (`tcs-os admin.py:90-93`).
- **D-3e.** Capacity keyed by: **grade_id FK to admissions_grades, not free-text year_group**. (This is a 3b carry-forward.)
- **D-3f.** Legacy references: **strict formats kept** (`YYPPNNNN` / `INQ/APP-YYYY-NNNN` with 4+ digits). Fallback, if the slice 15 inventory finds non-conforming legacy ids, is to drop the student_id check.
- **D-3g.** Officer read-decision: officers read decisions and offers **only if in scope AND holding can_decide** (matches TCS OS's coordinator bundle, `tcs-os migration 0019`). Built in slice 3b.

**Size:** one migration (6 tables, 3 SECURITY DEFINER visibility helpers, 2 triggers, 6 select policies), no write RPCs, 90 probes across two files.

### Carry-forwards for later slices

- **Slices 5 and 6 (deletes):** restrict deletes deliberately, because families, students and applications cascade to notes and contacts.
- **Slice 9 (submission snapshot):** it can hold health answers, so it must not live on `applications` or any table officers read without the health gate.
- **Slice 14 (guardian tokens):** guardians created in the ERP before slice 14 have no unsubscribe hash, and a stored hash can't rebuild a permanent unsubscribe link, so slice 14 needs a token design that covers them.
- **Slice 7a (demo rows):** nothing can create admissions rows until slice 8, so 7a's UI tests need invented demo rows in `seed.sql` because the live creation RPCs don't exist yet.
- **Slice 5 (done):** the numbering trigger has a stable name, `applications_assign_references`.

## Slice 3b — Decisions, offers, capacity, campus grade rules

**Status:** built, awaiting Eyram's review (uncommitted).

**Delivers:** one migration `20261012100000_admissions_decisions_offers_capacity_rules.sql` with four tables, with select-only RLS and no write RPCs, like 3a:

- `application_decisions` (one per application: `decision_type` accepted/waitlisted/rejected, `decided_by` FK staff on delete set null, `decided_at`, `notes` up to 10000 chars). Readable by Manager and Auditor, and by an Admissions Officer only when the application is in scope **and** they hold `can_decide` (D-3g). One trigger function `set_application_decision_identity()` forces `decided_by` and `decided_at` on insert and every update, only when `auth.uid()` is set.
- `application_offers` (one per application: `token_hash` not null, unique, matches `^[0-9a-f]{64}$`, `sent_at`, `expires_at`, `responded_at` nullable, `response` pending/accepted/declined/expired). Same read rule as decisions (D-3g).
- `admissions_capacity` (`academic_year` text, `grade_id` FK `admissions_grades` on delete restrict, `branch_id` nullable FK `branches` on delete restrict, `capacity` >= 0, unique nulls not distinct on (academic_year, grade_id, branch_id)). Readable by Manager and Auditor only (D-3c).
- `admissions_campus_grade_rules` (`branch_id`, `grade_id`, composite primary key, both FKs on delete restrict). Readable by Manager, Auditor and Admissions Officer. Annex's rows (Pre Nursery and Nursery 1, the rule from `serializers.py:18`) go in `supabase/seed.sql` and `supabase/seed.production.sql`, keyed by `branch_id`, not by name, which removes TCS OS's rename fragility noted at `02-stack-and-schema.md:476-480`.

**Design choices (decided 2026-10-11):** (a) composite primary key on campus rules; (b) restrict FKs from capacity and rules to grades and branches; (c) `decided_at` re-stamped on every signed-in update; (d) no consistency checks between offer dates; (e) academic_year matched as exact text; (f) campus rule enforced only in slice 9's submit RPC, never as a trigger on applications.

**Grades:** no `grade_id` on `applications`. `year_group_applied_for` stays free text, and text that matches no grade (legacy labels such as "2027", "Grade 10" and "Grade 11" seen in TCS OS) resolves to no grade and no band. No SHS (Grade 10 to 12) rows are added.

**Seeds:** `seed.sql` inserts Annex's two rules after the branches insert. In `seed.production.sql` the Annex rules are a separate, final block that can be run on its own; it fails loudly if Annex is missing or the two rules aren't there. The file's header now says it's safe on a fresh project, but on a live project the whole file shouldn't be re-run (it can re-create deleted or renamed expense categories or allowance types, and a renamed Annex would get a second Annex branch).

**Role matrix:** `supabase/role-matrix/20261012100000_admissions_decisions_offers_capacity_rules_visibility.sql` (40 probes) and `..._structure.sql` (48 probes).

**No new helper functions or write RPCs.** Numbering, stage RPCs and the offer email are deferred to slices 5, 6 and 12.

## Slice 4 — Health info, documents metadata, private bucket

**Status:** committed (admissions 4).

**Delivers:** Migration `20261013100000_admissions_health_documents_storage.sql`:

- **`application_health_info`:** one row per application, only once health questions are answered (D-4m). Three pairs, each a boolean flag plus a details field capped at 2,000 characters (D-4e): `has_learning_or_physical_needs` + `learning_or_physical_needs_details`, `has_medical_conditions` + `medical_conditions_details`, `has_allergies_or_dietary_requirements` + `allergies_dietary_details`. Deleted cascade with the application.
- **`application_documents`:** metadata only: `application_id`, `document_type` (the 8 TCS OS values: `proof_of_vaccination`, `financial_clearance`, `previous_report`, `application_fee_proof`, `proof_of_funds`, `passport_photo`, `birth_certificate`, `other`), `status` (`required`, `pending_review`, `approved`, `rejected`), `storage_path` (nullable, unique when set, max 500 chars, [A-Za-z0-9._/-] only, no "..", no leading/trailing "/", must end in .pdf/.jpg/.jpeg/.png case-insensitive), `uploaded_at` (set exactly when `storage_path` is set). Any status other than `required` requires a file. Deletes restricted (D-4f): an application with documents cannot be deleted.
- **Private bucket `admissions-documents`:** `public = false` from the insert (the receipts lesson, `on conflict do update` so a pre-existing public bucket is forced private), 10485760 bytes (10 MiB), allowed MIME types `application/pdf`, `image/jpeg`, `image/png` only (D-4g, no HEIC). No write policy for the bucket. One read policy `admissions_documents_select`: authenticated only, checks `bucket_id = 'admissions-documents'` and a visible `application_documents` row has exactly `storage_path = objects.name` (subquery runs under the caller's RLS, so file visibility follows document visibility).
- **Health reads:** Manager, Auditor and Admissions Officer only, and only while they hold `can_view_health` (D-4a, D-4k) AND the application is visible to them (band scope). Attendant and Accountant read nothing, even holding the capability (D-4l).
- **Document reads:** Manager, Auditor and an Admissions Officer in scope (D-4j); no health capability needed. Reads by scope only.
- **File reads:** readable only through a visible `application_documents` row with that exact path. A file with no row is unreadable by everyone.
- **Grants:** `authenticated` select only on both tables, `anon` nothing, `service_role` full CRUD.

**Not included:** write RPCs (slice 5 reviews, slice 9 creates), uploads by anyone, anon write, health read audit (D-4c), UI (slice 7a).

**Decisions (decided 2026-10-11):**

- **D-4a.** Health gate shape: can_view_health AND band scope (decided as recommended).
- **D-4b.** Grant timing: everything starts ungranted, and no migration or seed grants a capability. Eyram grants `can_view_health` to named staff through Settings (audited) once TCS names who needs it.
- **D-4c.** Health read audit: not in Phase 2, since audit_log is reserved for state transitions. The last good moment to revisit is before slice 7a builds on the table.
- **D-4d.** Retention: keep health data for enrolled students. Purge closed applications (for example `rejected` or `offer_declined`) after about 12 months, once the period is checked against Ghana's Data Protection Act 2012 (Act 843). The purge is a later slice. It must remove files through the Storage API (SQL can't delete stored files), and remove document rows and files before the application, because documents restrict. Any "draft data" it purges means the ERP's own slice 10 drafts.
- **D-4e.** Health details limit: 2,000 characters per field (slice 9 form must match).
- **D-4f.** Application deletes: restricted if documents exist (applications with documents can't be deleted).
- **D-4g.** Bucket size and MIME: 10 MiB, pdf/jpeg/png only, no HEIC.
- **D-4h.** Signed file URLs: 300 seconds (a slice 7a constant).
- **D-4i.** Staff edit RPC for health: none built.
- **D-4j.** Document read gate: scope only, not the health capability.
- **D-4k.** Manager and Auditor: need can_view_health for health reads.
- **D-4l.** Attendant and Accountant: may hold can_view_health (O-6) but read nothing.
- **D-4m.** Health rows: only when answered (inquiries have none).

**Probes:** `supabase/role-matrix/20261013100000_admissions_health_documents_storage_visibility.sql` (59 probes) and `…_structure.sql` (31 probes). Breaks: 23 deliberate breaks; 20 caught; break 5 (dropping has_role allowlist from health policy) is an equivalent mutant (has_admissions_capability already limits roles); break 9a (prefix match on storage_path) was not caught, so probe SV7c was added; break 23 (storage bucket on conflict do nothing instead of do update) can't be caught by SQL probes. B1 runs bucket check as postgres because storage.buckets has RLS.

**Verification:** baseline at HEAD (17 probe files and the golden suite green, anon-executable 169; the golden suite isn't required for this slice). test-runner: lint (0 errors, 13 warnings), tsc, build, overload check pass; types regen additive (76 lines); earlier files byte-identical; both new files green; no function added or changed, exactly 3 policies added (table select for both, storage select), none changed; anon-executable 169; golden unchanged. Storage API check (local only): bucket not public, public URL refused with "Bucket not found"; Manager and Auditor sign and fetch; Attendant, Accountant and officers without capability or wrong band refused; officer with right band can sign; file with no row can't be signed; uploads refused for Manager and anon; 11 MiB, HEIC and application/x-msdownload rejected; PNG and JPEG accepted; no cleanup leftovers. code-reviewer: no blocking findings. Noted: PORT-PLAN still lists a document read function and two storage policies (now removed); storage_path still allows "a//b" and "a/./b" (harmless, because matching is exact and unique); slice 9 must sanitize file names to the allowed characters.

**Size:** one migration (2 tables, 1 bucket, 3 policies; no functions, triggers, write RPCs); 90 probes.

## Slice 5 — Reference numbering, stage transitions, notes and document review

**Status:** committed (8b9c1d4) and applied on hosted.

**Delivers:** Migration `20261014100000_admissions_numbering_stages_notes_documents.sql`:

- **`admissions_reference_counters`** (key, next_value): PK on key (text check allowing INQ-YYYY, APP-YYYY, STUDENT-YY-PP). RLS on, no policy, revoke all from public, anon, authenticated and service_role. Nobody reads it; counters start empty (nothing imported from TCS OS).
- **Helpers (no grant):** `_admissions_reference_year()`, `_admissions_sequence_text()` (4 digits minimum, widens past 9999, lpad-aware), `_next_admissions_sequence(key)` (one atomic upsert holding the counter row lock until commit), `_next_admissions_reference(INQ/APP only; skips a number a hand-entered row already holds)`, `_require_admissions_writer()` (Manager or Admissions Officer; "Auditor is read-only and cannot perform this action"; "This action is not available to your role").
- **Triggers on applications** (stable names, BEFORE ones fire in name order): `applications_assign_references` (INQ on insert only when row starts at inquiry; APP the first time stage is past inquiry; never reassigned), `applications_guard_update` (nothing leaves enrolled for any caller; a signed-in caller can't change or clear an assigned reference; postgres and service_role can for hand corrections), `applications_set_updated_at` (reuses set_updated_at()), `applications_audit_stage` (AFTER UPDATE OF stage). Trigger `application_documents_audit_status` on application_documents.
- **`application_notes.edited_at`** (nullable).
- **RPCs** (granted to authenticated and service_role, not anon): `move_application_to_document_review()` (Manager or in-scope officer; only from inquiry or application; re-checked under row lock), `set_application_stage()` (Manager only; targets application, document_review, waitlisted, rejected; never inquiry, offer, offer_declined or enrolled; never out of offer or enrolled; refuses same stage), `add_application_note()` (Manager or in-scope officer; trimmed; not blank; at most 10,000 chars; author and time set by 3a note trigger), `update_application_note()` (author only, while active and in scope; content and edited_at only; no delete RPC), `set_application_document_status()` (Manager or in-scope officer; between pending_review, approved, rejected; never to required; refused on document with no file; refuses same status). Out of scope and not found give same error in every RPC ("Application not found", "Note not found", "Document not found"). can_decide and can_view_health play no part. Auditor never writes.
- **Audit rows** only when a signed-in staff member made the change (no actor, no row). Stage row: before {stage}, after {stage, application_reference}. Document row: before {status}, after {status, document_type, application_reference}; no file path, names or health data. Readable through existing audit_log_select (Manager, Accountant, Auditor).
- **audit_log_action_check** rewritten from 29 to 31 values: adds application_stage_changed and application_document_status_changed.

**Formats** (D-5a decided, year pinned to Africa/Accra): `INQ-YYYY-NNNN` assigned on inquiry insert; `APP-YYYY-NNNN` the first time stage is past inquiry. YYYY is the year at assignment. Sequences reset per year. Four-digit minimum, widening past 9999 with no cap (lpad gotcha noted in DESIGN.md). Each number assigned once, never reassigned.

**Decisions** (decided 2026-10-11): D-5a formats kept, 4-digit minimum, widening past 9999; D-5b Manager may move out of rejected, waitlisted or offer_declined, audited; D-5c set_application_stage limits above; D-5d no leaving enrolled for any caller, by trigger; D-5e gaps only from hand actions, never failures (counter and row commit or roll back together); D-5f student IDs (YYPPNNNN, counter key STUDENT-YY-PP) assigned in slice 6 reusing _next_admissions_sequence and _admissions_sequence_text; D-5g notes.edited_at, author-only edit, no delete (bad note by deactivated author fixed only by postgres; Manager redact can be added later); D-5h changed from plan: document status changes ARE audited (payload above); D-5i stage audit rows carry application reference; service_role/postgres changes write no audit row; D-5j counters with no privilege for any API role including service_role and no read for anyone; D-5k offer needs-accepted-decision and enrolled needs-decision-and-offer gate built in slice 6; D-5l year pinned to Africa/Accra.

**Probes:** `supabase/role-matrix/20261014100000_admissions_numbering_stages_notes_documents_structure.sql` (16), `_numbering.sql` (18), `_rpcs.sql` (81): 115 in all. Probe A4 in slice 4 structure file changed on purpose: asserts none on application_health_info and exactly application_documents_audit_status on application_documents (slice 9 will update if it adds a document trigger).

**Verification:** baseline at HEAD d5580d8 on fresh reset (19 probe files and golden suite green, anon-executable 169). After build: lint (0 errors, 13 warnings), tsc, build, overload check pass; types regen additive (155 lines); 18 earlier probe files byte-identical, slice 4 structure file differing only in A4's name line; three new files green; golden suite byte-identical before and after audit list rewrite; catalog diff 14 new functions (set_updated_at reused), none changed, no policy change, anon-executable 169. Concurrency races on local DB: new counter key (A=1, B=2, B waited about 5 s), existing key, two committed inquiry inserts (consecutive numbers, no unique violation), stage race (second call raised "currently at 'document_review'", exactly one audit row written). Deliberate breaks: 32 variants; 30 caught by probes or races (lock and stage re-lock only by races); two gaps (INQ assigned on update; RPC's 10,000-character check backed by table check) closed by new probes N3c and NO8b, each verified to catch its break.

**code-reviewer:** no blocking findings. Fix round 1: skip-if-in-use check split per prefix so always uses unique index. Not changed: probe A3d keeps fixed anon-executable count of 169 on purpose (standing rule); setup-only probes run identically for every role (accepted). Noted for later: service_role already has table-level insert and update on applications, so slices 8 and 9 stage changes bypass RPC rules and write no audit row (keep in view on those reviews); counter locks held to commit (future transaction numbering both INQ and APP in opposite orders could deadlock, keep intake short and consistent); lpad truncation also affects existing invoice and deposit numbering (out of scope, noted only).

**Carry-forwards for later slices:**
- Slice 6: reuses _next_admissions_sequence('STUDENT-YY-PP') and _admissions_sequence_text for student IDs; the offer/enrolled gate (D-5k) built there.
- Slices 8 and 9: service_role writes bypass RPC stage rules and write no audit row; intake transactions should stay short and number in consistent order (counter locks held to commit).
- Slice 9: adding a trigger on application_documents means updating slice 4's probe A4 and slice 5's probe A4.

**Size:** one migration (one table, 14 functions, 5 triggers, one added column); 115 probes in three files.

**Anon surface:** none.

**Confirmation gates (approved 2026-10-11):** the new write ability (Manager and in-scope officer through the RPCs, Manager only for `set_application_stage`), and stage and document audit rows readable by Manager, Accountant and Auditor.

**Role matrix** (AO base: Grade 3 with `{primary}`; Attendant and Accountant have no admissions access):

| RPC | anon | Att | Mgr | Acc | Aud | AO |
|---|---|---|---|---|---|---|
| `move_application_to_document_review`, from inquiry or application | ✗ | ✗ | ✓ | ✗ | ✗ | in scope only (bands or `all_grades`; unbanded and legacy grades only with `all_grades`) |
| same, from any other stage, or every staff member inactive | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `set_application_stage` (allowed targets) | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `add_application_note` | ✗ | ✗ | ✓ | ✗ | ✗ | in scope only |
| `update_application_note`, own note | ✗ | ✗ | ✓ | ✗ | ✗ | in scope only |
| `update_application_note`, someone else's or no author | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `set_application_document_status` | ✗ | ✗ | ✓ | ✗ | ✗ | in scope only |
| counters table, any direct access | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

An officer holding only `can_decide` or only `can_view_health`, with no bands and no `all_grades`, is refused on every RPC.

**Not included:** decisions, offers, enrolment and student IDs (slice 6), UI (slice 7a).

## Slice 6 — Decisions, offers, the enrolment gate, the capacity warning (staff side)

**Status:** split into 6a and 6b (decided 2026-10-12). 6a committed (5c56735) and applied on hosted. 6b committed (6c1f014) and applied on hosted. Evidence: Eyram's `npx supabase migration list` on 2026-10-12 shows 20261015100000 (6a) and 20261016100000 (6b) on both Local and Remote.

**Design carry-forwards:**
- Slice 3b (D-3c): capacity figures are readable by Manager and Auditor only. An officer gets a figure-free warning, never the numbers.
- Slice 5: student IDs (YYPPNNNN) reuse `_next_admissions_sequence('STUDENT-YY-PP')` and `_admissions_sequence_text` (D-5f). The gate "an offer needs an accepted decision; enrolled needs a decision and an offer" is built here (D-5k). `set_application_stage` never targets offer, offer_declined or enrolled, and never moves out of offer or enrolled, so those stages are reached only through this slice's RPCs.
- Slice 3a: deletes stay restricted deliberately, because families, students and applications cascade to notes and contacts. No delete RPC for decisions or offers.

**Who may do what (D-2f, D-6d):** the decision and offer RPCs need the decide capability, held explicitly by a Manager too, and an Admissions Officer needs the application in scope (grade bands, or `all_grades`; unbanded and legacy grades only with `all_grades`). Checks run role, then capability, then scope; out of scope and not found give the same error. `mark_enrolled`, the capacity RPCs and the offer TTL setting are Manager only, with no capability needed. Auditor, Attendant and Accountant never write.

### 6a: decisions and capacity

**Delivers:** migration `20261015100000_admissions_decisions_capacity.sql`:

- **`application_offers.response`** gains `withdrawn` (D-6j), a change to the 3b check. A withdrawn offer counts like a declined one everywhere.
- **Helpers (no grant):** `_require_admissions_decider()` (`_require_admissions_writer()`, then the decide capability), `_admissions_grade_id()` (same normalisation as `admissions_grade_band()`), `_offer_effective_response()` (a pending offer strictly past `expires_at` reads as expired, using `clock_timestamp()`; computed, never stored), `_admissions_capacity_warning()`.
- **`record_decision(p_application_id, p_decision_type, p_notes)`:** creates the single decision and refuses when one exists (D-6k). Refused at inquiry or enrolled (D-6f). waitlisted and rejected move the stage to match; accepted never moves it. Returns `{decision_type, stage, capacity_warning}`.
- **`change_decision(p_application_id, p_decision_type, p_notes)`:** changes the existing decision and refuses when there is none, when nothing changes, and at inquiry or enrolled. Leaving accepted withdraws a pending offer (response `withdrawn`) and is refused once the parent has accepted the offer; a declined, withdrawn or expired offer is left as it is (D-6j). Returns `{decision_type, stage, offer_withdrawn, capacity_warning}`.
- **Capacity warning (D-6c, D-6o):** returned when the resulting decision is accepted. It matches the capacity row on exact `academic_year` text, the grade resolved from `year_group_applied_for`, and the campus (a null campus matches only a null-campus row). It counts applications with an accepted decision for that key, leaving out those at `offer_declined` and those whose offer is declined, withdrawn or past its expiry (a deliberate change from TCS OS, which counted every accepted decision). It warns only when the count is strictly greater than the capacity, never at equality; capacity 0 warns on the first acceptance; no capacity row means no warning. It never blocks. A Manager's text gives the figures; an officer's says only that the grade is over its planned capacity.
- **Capacity RPCs, Manager only:** `create_admissions_capacity` (year trimmed, 1 to 50 characters; grade and campus must exist; 0 to 100,000; a duplicate gets a plain message), `update_admissions_capacity` (the figure only; the year, grade and campus never change), `delete_admissions_capacity`.
- **Campus rules:** not checked here (3b decision (f): slice 9's submit RPC only).
- **Audit (D-6n):** `application_decision_changed` (insert, or the decision type changes; a notes-only edit writes no row): before `{decision_type}` or null, after `{decision_type, application_reference}`. `admissions_capacity_changed` (insert, change, delete): `{academic_year, grade, campus, capacity}` by name. Only for a signed-in actor; no names of people, notes or health data. The audit action list goes from 31 to 33 values.
- **Production step after the 6a push:** no migration grants a capability, so on hosted a Manager must grant themselves can_decide in Settings before anyone can record a decision.

**Probes:** supabase/role-matrix/20261015100000_admissions_decisions_capacity_structure.sql (28), _decisions.sql (80), _capacity.sql (72): 180 in all. One intended change to an earlier file: slice 5 structure probe A5 now checks that the audit list still contains its 31 values, and the 6a structure file pins the exact 33. No 3b probe listed the offer response values, so no 3b file changed. Probe S13 checks the source of `record_decision` and `change_decision` for the row lock and the scope re-check under it.

**Verification:** baseline at HEAD 8b9c1d4 on fresh reset (22 probe files and golden suite green, anon-executable 169). After build: db reset, duplicate-overload check, lint 0 errors 13 warnings, tsc and build pass; types regen additive; all 25 probe files green (the 22 earlier files' output unchanged from baseline); golden suite unchanged; anon-executable 169. Deliberate breaks: 45 variants; all caught by probes except two equivalent mutants (clock_timestamp() with >= instead of >, and dropping anon or authenticated revoke when PUBLIC revoke remains). Gaps found and closed: probe helper passed silently on NULL (fixed with coalesce), and missing lock or under-lock scope re-check (closed by probe S13, also shown by races). Races on local DB: two record_decision calls (second waited, then refused "already been recorded"; one decision, one audit row); change_decision against offer acceptance, both call orders (accept-first: change refused; change-first: offer withdrew); two change_decision calls serialized with two audit rows; scope re-check under lock refused a decision on an application moved out of band.

### 6b: offers, the enrolment gate and student IDs

- **`admissions_settings`** singleton with `offer_ttl_days` (default 14, 1 to 90; D-6a), read by Manager and Auditor, changed by the Manager-only `set_admissions_offer_ttl_days`, audited as `admissions_settings_changed`. Slice 8 adds its own columns to this table.
- **`generate_offer`:** needs an accepted decision (the gate checks the decision, not the stage, so waitlisted then accepted then offer works); allowed from application, document_review, waitlisted or rejected; refused when an offer row exists. Mints a 32-byte token, stores only its SHA-256 hash, sets `sent_at`, `expires_at` (now plus the TTL) and `response = 'pending'`, moves the stage to offer, and returns the raw token once.
- **`reset_offer`:** always a new token, so the old link finds nothing (D-6b); allowed on a pending offer, which is how a lost link is recovered, and refused once the parent has accepted (D-6m). Moves the stage back to offer.
- **`record_offer_response`:** a reply the parent gives staff (D-6e). accepted or declined only, on an offer that is effectively pending; declined moves the stage to offer_declined.
- **Expiry (D-6l):** no read path writes. Staff RPCs compute the effective response and refuse an expired offer; only a service_role sweep, `settle_expired_offers()`, writes `expired` and moves the stage from offer to offer_declined (no actor, so no audit row). Slice 12 schedules the sweep.
- **View `application_offer_status`** (`security_invoker`), without `token_hash`, showing `effective_response` (withdrawn shown as withdrawn).
- **`mark_enrolled`:** Manager only (D-6d). Needs stage offer, an accepted decision and an offer whose effective response is accepted. Assigns `students.student_id` once per student (D-5f, D-6g, D-6h, D-6i): YY is the calendar year of enrolment in Africa/Accra (TCS OS parity); PP is the grade's classification code; NNNN comes from the counter key `STUDENT-YY-PP`. An unbanded or legacy grade (Grade 10 to 12, "2027", free text) refuses enrolment instead of leaving the ID empty. A student who already has an ID keeps it; a second enrolment for the same student in the same academic year is refused. The enrolment stage audit row carries the student ID. A `students_guard_student_id` trigger stops a signed-in caller changing an assigned ID.
- **Audit:** `application_offer_changed` (no token or hash), `admissions_settings_changed`. The list goes from 33 to 35 values.
- **Carry-forwards from the 6a tests and review:** every path that accepts an offer (`record_offer_response`, and slice 11's `respond_to_offer`) must lock the application, then the offer, and re-check under the lock that the response is still pending, the offer is in date and the decision is still accepted; a 6a race showed that an unguarded write can leave a rejected decision with an accepted offer. Every 6b read of an offer must use the effective response, never the stored `response`, because an expired offer keeps a stored `pending`. `mark_enrolled` takes locks in the same order as `change_decision`: application, then decision, then offer.
- **Races to test:** two enrolments at the same grade and year, the same application twice, two applications of one student, `generate_offer` against `reset_offer`, `change_decision` against `generate_offer`, and the sweep against `record_offer_response`.

**Built (2026-10-12), awaiting Eyram's review, uncommitted.** Migration `20261016100000_admissions_offers_enrolment.sql`: 12 new functions (`generate_offer`, `reset_offer`, `record_offer_response`, `mark_enrolled`, `set_admissions_offer_ttl_days`, `settle_expired_offers`; helpers with no grant `_admissions_grade_code`, `_next_admissions_student_id`, `_settle_offer_expiry`; trigger functions `guard_student_id`, `audit_application_offer`, `audit_admissions_settings`), one replaced (`audit_application_stage`, which now adds `student_id` to the after payload when the stage becomes enrolled), 4 new triggers (`application_offers_audit`, `admissions_settings_audit`, `admissions_settings_set_updated_at`, `students_guard_student_id`), the `admissions_settings` table and the `application_offer_status` view. 6a's `_offer_effective_response` and `_admissions_grade_id` are reused, not redefined. As built, beyond the bullets above:

- **Lock order** on every accept and enrol path: application, decision, offer, student, counter. This satisfies both the request for application, offer, student, counter and the carry-forward that `mark_enrolled` matches `change_decision` (application, decision, offer). Everything is re-checked under the locks. `settle_expired_offers` locks the application, then the offer.
- **`settle_expired_offers`** also refuses any caller with `auth.uid()` set, as a backstop behind the grant.
- **The view** writes the expiry rule out inline, because `_offer_effective_response` has no grant for authenticated.
- **`reset_offer`** needs an accepted decision and an existing offer, works on a pending (including expired), declined, expired or withdrawn offer, and is refused at inquiry or enrolled.
- **`admissions_settings`:** service_role gets select and update only. `application_offer_changed` carries the response, `expires_at`, a `token_replaced` boolean and the application reference. 6a's `change_decision` withdrawal now also writes one of these rows.

**Probes:** `supabase/role-matrix/20261016100000_admissions_offers_enrolment_structure.sql` (20), `_offers.sql` (53), `_enrolment.sql` (23): 96 in all. Probe S13 checks the lock order and the re-checks under the locks by source; S15 checks token minting and hashing by source. Two intended changes to the 6a structure file: S6 now checks that the audit list still contains its 33 values (the 6b structure file pins the exact 35), and S8 now allows the new `application_offers_audit` trigger (S8 had pinned "offers has no trigger"; this second change follows from the approved offer audit trigger).

**Verification:** baseline at HEAD 5c56735 on a fresh reset: overload check clean, types matched, golden suite green. After the build: db reset, overload check clean, types regen additive and identical to the working-tree file, lint 0 errors 13 warnings, tsc and build pass, all 28 probe files green, golden suite green, anon-executable count 169. 20 deliberate breaks, each run only against its target probe file, all caught (capability, scope and their order 4; locks and re-checks 6; token hashing and storage 2; the view 2; grants and anon surface 2; audit rows 2; student ID guard and counter 2).

**Races (local, two sessions):** `change_decision` against `record_offer_response`, both orders (accept first: the change waited and was refused; change first: the accept waited and was refused, offer withdrawn); `change_decision` against `generate_offer`, both orders; two enrolments at one grade and year (consecutive IDs); the same application twice (second refused, one stage audit row); one student's two applications in one year (second refused) and in two years (second kept the ID); the sweep against `record_offer_response`, both orders (accept first: sweep settled nothing; sweep first: accept refused). `generate_offer` against `reset_offer` was dropped: both serialize on the application lock with no distinct outcome.

**code-reviewer:** no blocking findings. Not changed: authenticated still has table-level select on `application_offers`, `token_hash` included (from 3b), so the view alone doesn't hide the hash from a Manager, Auditor or deciding officer. Decided 2026-10-12 to leave the grant as it is (D-6q). `mark_enrolled` has no grade-visibility re-check under the lock (Manager only).

**Production step after commit:** `npx supabase db push` (Eyram's to run).

**Not included:** the parent-facing respond flow (slice 11), the offer email (slice 12), a document gate (no document has to be approved before an offer or enrolment; decided 2026-10-12).

**Open question for Eyram (D-6g):** do the real current TCS student IDs already follow YYPPNNNN, and if so which year did they use: the enrolment year, or the academic year's start year?

**TCS OS files read:** `models.py:93-116, 300-352, 392-541`; `admin.py:129-170, 256-307, 384-433`; `docs/admissions/02-stack-and-schema.md:207-328`; `tcs_os/settings.py:458` (`OFFER_EXPIRY_DAYS`, default 14).

**Conventions:** create-can't-overwrite (decision create and change are separate RPCs); the onboarding token pattern (CSPRNG, hash only, reveal once, expiry checked on every use); audit via triggers; computed, never stored, for the effective offer response.

**Role matrix** (six columns; base: a Grade 3 application, Manager and officer both hold can_decide, officer holds `{primary}`):

| Probe | anon | Att | Mgr | Acc | Aud | AO |
|---|---|---|---|---|---|---|
| `record_decision`, `change_decision` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ in scope |
| same, nobody holds can_decide | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| same, officer holds can_decide with no bands, out of band, or an unbanded grade without `all_grades` | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| same, officer holds can_decide and `all_grades`, Grade 11 or "2027" | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ |
| capacity create, update, delete | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `generate_offer`, `reset_offer`, `record_offer_response` (6b) | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ in scope |
| `mark_enrolled` with an accepted offer (6b) | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `mark_enrolled` with a pending offer, or one past its expiry (6b) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `settle_expired_offers` (6b) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

An expired offer is probed as a refusal plus `effective_response = 'expired'`: an RPC that raises rolls back anything it wrote, so the stage settling to offer_declined is probed on the sweep, not on a refused call.

**Anon surface:** none. The anon-executable function count stays at 169.

**Decisions (decided 2026-10-12):** D-6a to D-6i and D-6k to D-6p as recommended; D-6j changed to a `withdrawn` response; D-6q, the `token_hash` read grant stays. See the consolidated table.

## Slice 7a — Staff pipeline UI: list, detail, notes, documents, health panel

Slice 7a built 2026-10-12, uncommitted, awaiting Eyram's review.

**Delivers:**

- `routes/admissions/index.tsx`: a list filterable by stage, campus, academic year and grade. Search by student name and references, never by health data.
- `routes/admissions/$applicationId.tsx`: family, guardians, student, emergency contact, notes (add and edit), documents (signed-URL view and status change), and a health panel:
  - For a user holding `can_view_health` and the application has no health row: show "No health information on file".
  - For anyone else: show nothing, so nobody learns whether a child has health answers.
  - Signed file URLs last 300 seconds (D-4h).
  - Health stays out of list views, search and export.
- A "Move to Document Review" action.
- An "Admissions" sidebar section (DESIGN.md sidebar convention).
- Module code in `src/modules/admissions/` with `data/`, `hooks/`, `components/`, `permissions.ts` and `labels.ts` (docs/DESIGN.md, "Project layout"). `data/` makes RPC and select calls only, with explicit column lists.

**Not included:** decision, offer and enrolment actions (7b), public pages.

**Carry-forward from slice 3a:** nothing can create admissions rows until slice 8, so this UI needs invented demo rows seeded in `seed.sql` for development.

**Carry-forward from slice 6b (D-6q):** every query selects explicit columns, and the UI never selects `token_hash`. Offer status is read from `application_offer_status`, which leaves it out. Authenticated keeps a table-level select on `application_offers`, so nothing in the database stops a `select *` from returning the hash.

**Design note (D-4c):** Health read audit must be decided before this slice builds on the table. Auditing health reads would mean reading through a SECURITY DEFINER RPC instead of the table policy.

**TCS OS files to read:** `admin.py:85-127, 172-236, 437-470`; `docs/admissions/01-vision.md` "UX principles".

**Conventions:** `getErrorMessage()` duck-typing; no client-side business logic; signed URLs, never public ones; the sidebar convention (no placeholder nav).

**Role matrix:** no new RPCs. The UI hides what RLS already denies. Browser checks use the four dev accounts with capability variants.

**Anon surface:** none. Staff routes sit behind AuthGate.

**Decisions for Eyram:** **D-7a.** Staff route prefix. Recommendation: `/admissions`, because public routes use TCS OS's bare paths (see "Links already sent").

**Size:** two routes, one store, reusing existing list and detail components.

## Slice 7b — Staff pipeline UI: decisions, offers, enrolment, capacity, capabilities

**Delivers:**

- A decision dialog that shows the capacity warning as a toast.
- Generate and reset offer, with a reveal-once copyable link until slice 12.
- Mark enrolled, showing the refusal message when the grade has no student ID code (D-6h), and listing any documents not yet approved as a warning (not a gate; decided 2026-10-12).
- Settings → Admissions: the capacity table (Manager and Auditor only) and the campus grade rules (read-only display).

**Not included:** email.

**Carry-forwards from slice 6:**
- A small Manager-only RPC to correct an application's applied-for grade (`year_group_applied_for`), since an application with an unbanded or legacy grade can otherwise never be enrolled (D-6h). Audited, scope-checked like the other stage RPCs; it needs its own role matrix probes, so 7b is no longer UI only. The RPC also checks that the Annex campus (if the application is for Annex) accepts the new grade.
- The decision and offer actions show only to staff holding can_decide; a Manager without it gets the RPC's refusal.

**TCS OS files to read:** `admin.py:384-433, 480-491`.

**Conventions:** as for 7a.

**Role matrix:** the grade-correction RPC only.

**Anon surface:** none.

**Carry-forwards from slice 7a:**
- Manager-only add and deactivate RPCs for `admissions_academic_years`, and `create_admissions_capacity` refuses a year not on that list (same signature). Slices 8 and 9 validate the submitted year against the same list.
- Demo rows at `offer` and `enrolled` in `seed.sql`, with their decision and offer rows.

**Decisions for Eyram:** none new beyond D-6*. The grade-correction RPC's Annex check above was approved with the 7a plan (2026-10-12).

**Proposed, not decided:** a read-only Audit log screen (Manager, Accountant, Auditor; filters by action and date) as its own slice after 7b (working name 7c).

**Size:** UI over existing RPCs, plus the one grade-correction RPC.

## Slice 8 — Public request path and the public Inquiry form

**Delivers:**

- **Edge Function `admissions-public`** (`verify_jwt = false` in `config.toml`):
  - Accepts POST with JSON `{action, turnstile_token, payload}`.
  - Verifies Turnstile against `siteverify` with `TURNSTILE_SECRET_KEY` from Supabase secrets, and additionally checks `hostname` against an allow-list (TCS OS doesn't, `turnstile.py`).
  - Computes an IP key from the request.
  - Calls service-role-only RPCs with the service-role key held in the function's env, never in the client.
  - Uses the same CORS and origin pattern as `invite-staff`, but with an explicit origin allow-list instead of `*`.
- `admissions_settings`: a single row with `public_intake_open boolean default false`, `offer_ttl_days`, `draft_ttl_days`, Manager write. It's the **technical enforcement of no dual intake**: every submit RPC refuses while intake is closed.
- `public_rate_limits (bucket, key_hash, window_start, count)` plus `check_public_rate_limit(bucket, key, limit, window)`, service-role-only. Buckets and defaults from TCS OS (`settings.py:184-199`):
  - `submit`: 20 per hour per IP;
  - `draft`: 120 per hour;
  - `lead`: 60 per hour.
- `submit_inquiry(p_payload jsonb, p_client_ip text)` is service-role-only. It validates exactly what `InquirySerializer` validates (`serializers.py:34-126`):
  - 1–2 guardians and 1–5 students;
  - required fields;
  - relationship and referral enums, with `referral_source_other` required when the source is `other`;
  - phone matching `^\+\d{3}\d{9}$`;
  - email format.

  It creates a family, guardians, students and one `inquiry` application per child. INQ references come from slice 5's trigger. **No de-duplication**, matching TCS OS (D-8c).
- `get_public_admissions_options()` is **anon**, SECURITY DEFINER and read-only. It returns active grades, campus names with accepted grades, and open academic years.
- Public route `/inquiry` (`routes/inquiry.tsx`), added to `__root.tsx`'s auth-free allow-list (`__root.tsx:155`).
- A Turnstile widget with explicit render, no `cf-turnstile` class, and a reset after every attempt (`02-stack-and-schema.md:615-619`).
- `VITE_TURNSTILE_SITE_KEY` as a build-time public value.

**Not included:** emails (slice 12; the outbox row is added then), the application form.

**TCS OS files to read:** `views.py:25-80`; `turnstile.py`; `serializers.py:1-126`; `templates/public/inquiry.html`; `tcs_os/settings.py:160-200, 452-453`; `docs/admissions/02-stack-and-schema.md:605-619`; `deployment.md` step 13.

**Conventions:** the anon surface is SECURITY DEFINER only, and a function that trusts Turnstile isn't anon-executable at all; `revoke execute … from public, anon, authenticated` then `grant … to service_role` on the submit RPCs; `VITE_*` values are build-time and public (only the site key); secrets live in Supabase secrets; jsonb multi-row input; create-can't-overwrite.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `submit_inquiry` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `get_public_admissions_options` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `admissions_settings` write | ✗ | ✗ | ✓ | ✗ | ✗ |
| `check_public_rate_limit` | ✗ | ✗ | ✗ | ✗ | ✗ |

Separately, as `service_role` in rolled-back psql: a valid payload creates the rows; closed intake raises; a bad phone raises; 6 students raise.

**Anon surface:** HTTP `admissions-public` (Turnstile, IP rate limit, origin allow-list) and DB `get_public_admissions_options()` (read-only, non-sensitive). **Confirmation gate.**

**Decisions for Eyram:**

- **D-8a.** Bot-check placement: Edge Function (recommended) versus Worker server function. See "Bot check and email placement".
- **D-8b.** Turnstile keys. Recommendation: a new Turnstile widget for the ERP host names, or the existing "TCS OS" widget with ERP hosts added. Keys go in Supabase secrets (secret) and the Cloudflare build env (site key). Eyram runs this.
- **D-8c.** Keep "inquiries never de-duplicate"? Recommendation: keep TCS OS parity for now.
- **D-8d.** Rate-limit numbers and IP source. Recommendation: TCS OS's numbers; confirm which forwarded-IP header the hosted Edge runtime supplies before trusting it.
- **D-8e.** CORS allow-list for the function. Recommendation: the ERP origin(s), `admissions.tcsch.edu.gh`, plus the marketing origins for slice 13.

**Carry-forwards from slice 5:** service_role writes bypass RPC stage rules and write no audit row; intake transactions should stay short and number in consistent order (counter locks held to commit).

**Size:** one Edge Function with one action wired up, two small tables, three RPCs, one public route. It's the first anon slice, and its gate review is part of the pass.

## Slice 9 — Public Application form: direct submit, uploads, matching, rules

**Delivers:**

- `admissions-public` action `upload_url`:
  1. rate-limit by IP;
  2. validate the declared type (the 4 public document types, `serializers.py:22-23`), extension (`pdf`, `jpg`, `jpeg`, `png`) and size (10 MiB or less);
  3. call service-role-only `reserve_application_upload(p_document_type, p_extension)`, which inserts `application_upload_reservations` (`id`, `path = 'pending/<uuid>/<type>.<ext>'` generated server-side, `expires_at` now plus 2 h, `consumed_at`);
  4. mint a Supabase **signed upload URL** for that exact path;
  5. return `{upload_url, reservation_id}`.

  No raw token appears in any path.
- Three validation layers: browser → Edge Function → bucket limits (slice 4). This matches `02-stack-and-schema.md:111-137`, and the bucket is the only layer that can't be bypassed.
- `submit_application(p_payload jsonb, p_client_ip text)` is service-role-only, and the payload shape equals `ApplicationSerializer`'s (`serializers.py:180-203`). It enforces:
  - intake open;
  - declaration agreed and signature present; `declaration_agreed_at = now()` and `declaration_ip = p_client_ip`, both server-set;
  - **preschool vaccination rule:** when the applied-for grade's `is_preschool_vaccination_required` is set, a `proof_of_vaccination` document is required (`serializers.py:209-216`);
  - **campus grade rule:** when the chosen campus has rules, the grade must be in them (`serializers.py:218-221`);
  - every document must reference an **unconsumed, unexpired reservation**, and the object must exist in `storage.objects`. The RPC then consumes them. This fixes contradiction 9.
- Matching, from `serializers.py:251-330`:
  1. a guardian email match (case-insensitive) finds the family, otherwise a new one is created;
  2. the student match is name (case-insensitive) plus DOB within that family;
  3. an application match is (academic year, grade) for that student.
- Per D-9b the recommendation is that an anon submission **never overwrites** existing guardian or student fields or health info, and **only advances** a matched application from `inquiry`. Any other matched stage gets a new application row, or is refused (D-9c). Submitted details are stored on the new application as a submission snapshot for staff to review.
- It writes emergency contact and health info, and sets the stage to `application`, which assigns the APP reference through slice 5.
- Public route `/apply` with the 6-section free-navigation form (`02-stack-and-schema.md:562-604`). Turnstile renders lazily on the Declaration step.
- pg_cron cleanup of unconsumed reservations and orphaned `pending/` objects after 24 h (needs `pg_cron`; D-12b).

**Not included:** drafts and resume (slice 10), confirmation emails (slice 12).

**Carry-forwards:**
- Slice 3a: the submission snapshot can hold health answers, so it must not live on `applications` or any table officers read without the health gate.
- Slice 4: the form's health details limit is 2,000 characters (D-4e); minted storage paths must use only [A-Za-z0-9._/-] and end in .pdf/.jpg/.jpeg/.png, so file names must be sanitized.
- Slice 5: service_role writes bypass RPC stage rules and write no audit row; intake transactions should stay short and number in consistent order (counter locks held to commit). Adding a trigger on application_documents means updating slice 4's probe A4 and slice 5's probe A4.

**TCS OS files to read:** `serializers.py:128-398`; `storage.py`; `views.py:82-148`; `templates/public/apply.html` (sections, `handleFileSelected` near :1764, nationality list); `docs/admissions/02-stack-and-schema.md:57-140, 461-651`.

**Conventions:** the anon surface rule; the document storage lesson; signed upload URLs issued server-side (DESIGN.md anon-surface rule); jsonb input; identity and time columns server-forced; lowercase normalisation of email.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `submit_application` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `reserve_application_upload` | ✗ | ✗ | ✗ | ✗ | ✗ |
| Storage insert into `admissions-documents` as anon | ✗ | | | | |

Service-role value probes cover: Annex plus Grade 3 raises; Main plus Grade 3 passes; Nursery 1 without vaccination raises; a path not reserved raises; a reserved path whose object doesn't exist raises; a matched `inquiry` app advances and keeps its INQ; a matched `enrolled` app doesn't reset.

**Anon surface:** HTTP actions `upload_url` and `application` (Turnstile on `application`, IP limit on both). The signed upload URL is single-object and short-lived. **Confirmation gate.**

**Decisions for Eyram:**

- **D-9a.** Upload mechanism. Recommendation: a signed upload URL from the Edge Function, bound to a reservation. The alternative is an anon storage insert policy that checks the reservation, the onboarding style, with no service role.
- **D-9b.** Should anon re-submission overwrite existing guardian, student and health data? Recommendation: no; snapshot the submission and flag differences.
- **D-9c.** A matched application in any stage other than `inquiry`: create a new row, or refuse with "contact the school"? Recommendation: create a new row for a different year or grade; refuse for the same year and grade.
- **D-9d.** Keep the phone rule `+CCC` plus exactly 9 digits (Ghana-shaped)? Recommendation: keep it for parity.
- **D-9e.** Application-fee proof. TCS OS doesn't enforce it (`02-stack-and-schema.md:509-516`). Recommendation: keep it optional.

**Size:** two Edge Function actions, one table, two RPCs, one large public form. If the form overruns, the fallback split is 9a (upload path plus RPC with a minimal form) and 9b (the full 6-section UX).

## Slice 10 — Application drafts: save and resume tokens

**Delivers:**

- `application_drafts`: `token_hash` unique, `email`, `data jsonb` (the same payload shape as slice 9), `current_step`, `expires_at` (D-10a), `submitted_application_id`, `save_count_window`, `resume_emails_sent_today`.
- **No staff select policy on `data`**, because it can hold health answers. Staff get a metadata-only function (Manager) for "look up a stuck parent's draft".
- `admissions-public` action `draft_create` (Turnstile once, IP limit) calls service-role `create_application_draft(p_email, p_data, p_step)`, which returns the raw token once.
- `get_application_draft(p_token)` is **anon**, SECURITY DEFINER. It hashes, then requires unexpired and not submitted. The errors match TCS OS's two messages (`views.py:182-199`).
- `save_application_draft(p_token, p_data, p_step, p_email, p_send_resume_email)` is **anon**, SECURITY DEFINER.
  - Same checks, with a **size cap** on `p_data` (proposal 256 KB).
  - A per-draft save cap (proposal 240 per hour, roughly twice TCS OS's per-IP 120 per hour).
  - The resume-email request is capped at 3 per draft per day, and only to the draft's stored email. That closes an email-bombing path TCS OS left to IP throttling. The email itself arrives in slice 12.
- `admissions-public` action `draft_submit`: Turnstile, then service-role `submit_application_draft(p_token, p_client_ip)`. It locks the draft `for update`, re-checks not submitted and unexpired, runs `submit_application(draft.data)` and links it (the equivalent of `views.py:226-259`).
- `/apply?draft_token=…` resume, with `lockFormAsSubmitted()` behaviour (`02-stack-and-schema.md:646-650`).

**Not included:** the resume email send (slice 12).

**TCS OS files to read:** `models.py:620-654`; `views.py:150-259`; `serializers.py:400-411`; `templates/public/apply.html:1870-1960`; `docs/admissions/02-stack-and-schema.md:531-560, 591-600, 646-650`.

**Conventions:** the onboarding token pattern (hash-only, expiry on every use, row lock at submit); the anon surface rule; computed-never-stored doesn't apply.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `get_application_draft(valid)` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `get_application_draft(expired)` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `get_application_draft(submitted)` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `save_application_draft`, oversized payload | ✗ for all | | | | |
| `create_application_draft` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `submit_application_draft` | ✗ | ✗ | ✗ | ✗ | ✗ |
| Select `application_drafts` | ✗ | ✗ | ✗ | ✗ | ✗ |
| Draft metadata function | ✗ | ✗ | ✓ | ✗ | ✗ |

The token functions are token-gated, so any caller holding the token succeeds.

**Anon surface:** DB `get_application_draft` and `save_application_draft` (256-bit token, hash lookup, expiry, not submitted, size and frequency caps); HTTP `draft_create` and `draft_submit` (Turnstile). **Confirmation gate.**

**Decisions for Eyram:**

- **D-10a.** Draft TTL. Recommendation: 30 days, TCS OS's default (`settings.py:495`). Eyram confirms the live env value.
- **D-10b.** Do drafts ever expire server-side? Recommendation: purge expired unsubmitted drafts 30 days after expiry (pg_cron), since they may hold health data.

**Size:** one table, four RPCs, two Edge Function actions, and resume wiring on the existing form.

## Slice 11 — Public offer response page

**Delivers:**

- `get_offer_context(p_token)` is **anon**, SECURITY DEFINER. It hashes the token it is given (SHA-256 hex), looks the offer up by `token_hash` (already unique, so indexed), and returns only student first name, grade, campus name, `expires_at` and the effective response, computed without writing: an anon read path never settles expiry. A withdrawn, declined, expired or accepted offer shows as closed.
- `admissions-public` action `offer_respond`: Turnstile (TCS OS gates this, `views.py:268-270`), then service-role `respond_to_offer(p_token, p_response)`:
  1. look up the application by token hash, lock the application `for update`, then lock the offer and re-check the hash (the same lock order as `reset_offer`, so the two can't deadlock);
  2. settle expiry, committing that result rather than raising after it;
  3. require `pending`;
  4. accept only `accepted` or `declined` (`serializers.py:413-418`);
  5. set `responded_at`.

  `declined` propagates to `offer_declined`. `accepted` doesn't move the stage (`models.py:484-511`).
- Public route `/offer?token=…`.

**Not included:** email.

**TCS OS files to read:** `views.py:261-294`; `models.py:448-511`; `templates/public/offer.html`; `docs/admissions/02-stack-and-schema.md:252-262`.

**Conventions:** the onboarding token pattern; the anon surface rule.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `get_offer_context(valid)` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `get_offer_context(unknown)` | returns nothing or raises | | | | |
| `respond_to_offer` | ✗ | ✗ | ✗ | ✗ | ✗ |

Service-role value probes: expired offer → response refused and stage `offer_declined`; second response refused.

**Anon surface:** DB `get_offer_context`; HTTP `offer_respond`. **Confirmation gate.**

**Decisions for Eyram:** **D-11a.** Show the child's name before the parent responds? TCS OS shows it only after. Recommendation: show first name and grade, so the parent knows which offer it is.

**Size:** two RPCs, one Edge Function action, one small page.

## Slice 12 — Transactional email

**Delivers:**

- `admissions_email_outbox`: `kind` (`inquiry_parent`, `inquiry_staff`, `application_parent`, `application_staff`, `draft_resume`, `offer`, `pdf_gate`, `lead_staff`), `to_email`, `subject`, `body_text`, `attachments` (Storage paths only, never bytes), `status` (`pending` | `sending` | `sent` | `failed`), `attempts`, `next_attempt_at`, `last_error`, `provider_message_id`, `application_id`, timestamps.
- The slice 8–11 RPCs gain an outbox insert **in the same transaction** as the record, which is what makes it "never blocking, never lost".
  - One parent email and one staff email per submission event, not per child (`02-stack-and-schema.md:144-147`).
  - Staff alerts go to `ADMISSIONS_STAFF_EMAIL`, default `admissions@tcsch.edu.gh` (`emails.py:29-30`), stored as an admissions setting.
- Email bodies must never include health fields.
- Links with raw tokens (offer, draft resume) exist in `body_text` only until sent; the mailer blanks them once status is `sent` (D-12c).
- Edge Function `admissions-mailer` (not public, shared secret):
  1. service-role `claim_outbound_emails(limit)` runs `update … set status='sending' … where status='pending' and next_attempt_at <= now() … for update skip locked returning *`;
  2. send through the Resend HTTP API, using the row id as an idempotency key;
  3. `mark_outbound_email_result(...)`. On failure, back off (1, 5, 15 and 60 minutes) and mark `failed` after 5 attempts. That mirrors TCS OS's `max-attempts=5` on the transactional queue (`02-stack-and-schema.md:786-788`).
- Triggers:
  - `pg_cron` every minute calls `pg_net.http_post` to the mailer, with the secret read from `vault.decrypted_secrets`;
  - `admissions-public` also kicks the mailer after a successful submit, for low latency.
- Attachment: the "Admissions Overview & Fees" PDF (about 4.9 MB) stored once in a private bucket and attached to `inquiry_parent` and `pdf_gate` (`02-stack-and-schema.md:387-404`).
- Staff UI: an outbox list with "Resend failed" (Manager), the equivalent of `TransactionalEmailAdmin.resend_failed`.
- Offer generation (slice 6) now enqueues the `offer` email. The reveal-once copy link stays as a fallback.

**Not included:** bulk email.

**TCS OS files to read:** `emails.py` (whole file; links at `:203` and `:361`); `models.py:879-928`; `views.py:390-426`; `internal_auth.py`; `tests.py:476-620`; `docs/admissions/02-stack-and-schema.md:142-153, 434-443, 633-644, 748-802`; `deployment.md` steps 5d, 6 and 7.

**Conventions:** select-only tables with RPC writes; explicit grants (outbox: no anon, no Attendant; Manager and Auditor select without body D-12c; service_role full); secrets in Supabase secrets and Vault, never `VITE_`; the reuse of invite-staff's function patterns.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| Outbox select | ✗ | ✗ | ✓ | ✗ | ✓ |
| `claim_outbound_emails` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `mark_outbound_email_result` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `requeue_failed_emails` | ✗ | ✗ | ✓ | ✗ | ✗ |

Service-role probes: a claim twice returns no row twice (idempotent); the fifth failure marks the row `failed`.

**Anon surface:** none new. The mailer is secret-gated, and the harness should prove it refuses an empty or unset secret (`internal_auth.py` rule).

**Decisions for Eyram:**

- **D-12a.** Provider. Recommendation: Resend through the HTTP API from Deno. Both `tcsch.edu.gh` and `updates.tcsch.edu.gh` are already verified in the TCS OS Resend account (`deployment.md:16`). Create a new API key for the ERP. The alternative is nodemailer over Resend SMTP, the existing invite-staff pattern.
- **D-12b.** Queue. Recommendation: the outbox plus pg_cron plus pg_net, which needs `create extension pg_cron, pg_net` in a migration and enabling them on the hosted project (Eyram).
- **D-12c.** Plaintext token links at rest in the outbox. Recommendation: blank the body after send, and hide `body_text` from staff selects with column-level grants.
- **D-12d.** GoTrue's production SMTP for invites. Recommendation: point it at the same Resend account in the same session. That's Eyram's dashboard step.

**Size:** one table, three RPCs, one Edge Function, a cron job, templates and one small UI.

## Slice 13 — Lead capture (marketing-site endpoints)

**Delivers:**

- `admissions_leads`: `name`, `email`, `phone` (at least one required), `grade_interest`, `source` (server-set: `quick_interest_widget` | `pdf_gate_admissions_overview`), `consent_to_marketing` (default false; only an explicit true is honoured), `utm_source`, `utm_medium`, `utm_campaign` (truncated to 200 characters, never rejected), `bulk_email_unsubscribe_token_hash`, `bulk_email_unsubscribed_at`, `created_at`. Per `models.py:668-738` and `serializers.py:421-495`.
- `admissions-public` actions `quick_interest` and `pdf_gate` (Turnstile, `lead` rate bucket), which call service-role `capture_lead(p_source, p_payload)`. `pdf_gate` requires an email and enqueues a `pdf_gate` email with the attachment; both enqueue a staff alert.
- CORS for the marketing origins: `https://tcsch.edu.gh`, `https://www.tcsch.edu.gh`, and `^https://[a-z0-9-]+\.vercel\.app$` (`02-stack-and-schema.md:744-746`).
- A Manager and Auditor read list (no grade band applies, since `grade_interest` is free text).

**Not included:** bulk sending to leads.

**TCS OS files to read:** `models.py:668-738`; `serializers.py:421-495`; `views.py:94-123`; `tests.py:39-236`; `docs/admissions/02-stack-and-schema.md:710-746`.

**Conventions:** the anon surface rule; server-forced `source`; consent default false.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `capture_lead` | ✗ | ✗ | ✗ | ✗ | ✗ |
| Leads select | ✗ | ✗ | ✓ | ✗ | ✓ |

Service-role value probes are ported from TCS OS tests: a client-sent `source` is ignored; missing both email and phone raises; overlong UTM is truncated; null UTM is accepted; consent defaults false.

**Anon surface:** HTTP `quick_interest` and `pdf_gate` (Turnstile, IP limit, CORS allow-list). **Confirmation gate.**

**Decisions for Eyram:**

- **D-13a.** Does the marketing site get repointed to the ERP endpoint, or does the ERP serve TCS OS's exact paths on `admissions.tcsch.edu.gh`? Recommendation: serve the exact paths through the Worker (slice 15). Then the marketing site needs no change at cutover and can be repointed at leisure.
- **D-13b.** Turnstile widget host names must include the marketing origins.

**Size:** one table, one RPC, two Edge Function actions, one list page.

## Slice 14 — Bulk email and one-click unsubscribe

**Delivers:**

- `email_campaigns`:
  - `name`, `subject`, `body` (plain text, whitelisted `{{placeholders}}`, `bulk_email.py`);
  - `audience` (`guardians` | `leads` | `both`);
  - optional filters: stage, academic year, campus (`branch_id`), lead source;
  - `status` (`draft`, `queued`, `sending`, `sent`, `failed`);
  - a check that the body contains `{{unsubscribe_link}}` (`models.py:809-812`).
- `email_campaign_recipients`: exactly one of `guardian_id` or `lead_id` (check), `email` snapshot, `status` (`pending`, `sent`, `failed`, `skipped_unsubscribed`, `skipped_invalid`), `provider_message_id`, `error_message`, `batch_no`, and partial unique indexes per target (`models.py:817-870`).
- Unsubscribe token hashes on `guardians` and `leads`, generated eagerly at creation and permanent. It's one token space across both tables (`views.py:315-326`).
- `queue_campaign(p_campaign_id)` (Manager, D-2d). In one transaction it:
  1. computes recipients once;
  2. unions the guardian pool (not unsubscribed, filters applied) and the lead pool (consented, not unsubscribed, optional source filter);
  3. de-duplicates by lowercased email with the guardian winning (`bulk_email.py:119-190`);
  4. pre-validates addresses, including the placeholder-domain blocklist (`bulk_email.py:39-50`), marking them `skipped_invalid`;
  5. assigns batches of 100 or fewer.
- The mailer gains a bulk lane:
  - Transactional mail always goes first.
  - One Resend batch call per batch (all-or-nothing); on success each row is `sent` with its message id. A transient failure leaves the rows `pending` for retry. The last attempt (3, matching `CLOUD_TASKS_MAX_ATTEMPTS`) marks them `failed` (`views.py:337-388`).
  - Pacing stays under Resend's rate limit (TCS OS measured 10 requests per second per team; re-check).
  - Every message carries `List-Unsubscribe: <…>` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (`bulk_email.py:248-249`).
- `bulk_email_unsubscribe(p_token)` is **anon**, SECURITY DEFINER. It checks guardians then leads, sets `unsubscribed_at` only if null (idempotent), and returns the first name or not-found. Transactional mail never reads the flag, a hard separation.
- The **Worker's first server route**, `/api/admissions/unsubscribe/$token/` (GET and POST), calls the anon RPC with the public anon key. POST returns an empty `200` (RFC 8058). GET renders the confirmation page (D-14b). Using the same path as TCS OS keeps old links working at cutover.
- Staff UI: campaign CRUD, preview against one sample per audience type, send, and retry failed. Send and retry are Manager only.
- From address: `updates@updates.tcsch.edu.gh` (`settings.py:527`).

**Not included:** bounce or open webhooks, topic-level opt-outs (TCS OS Phase 6.1, never built).

**Carry-forward from slice 3a:** guardians created in the ERP before this slice have no unsubscribe hash, and a stored hash can't rebuild a permanent link, so the token design must cover them (see slice 3a, carry-forwards).

**TCS OS files to read:** `bulk_email.py` (whole); `models.py:740-877`; `views.py:297-388`; `admin.py:447-470, 541-872`; `templates/public/unsubscribed.html`; migrations `0010`–`0014`; `tests.py:238-410`; `docs/admissions/02-stack-and-schema.md:652-708`; `deployment.md` steps 5c and 6b.

**Conventions:** the anon surface rule; select-only with RPC writes; recipients computed once and stored as the historical record (a deliberate snapshot, not a derived value); explicit grants.

**Role matrix:**

| Probe | anon | Att | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| Campaign create or edit | ✗ | ✗ | ✓ | ✗ | ✗ |
| `queue_campaign` | ✗ | ✗ | ✓ | ✗ | ✗ |
| Campaigns and recipients select | ✗ | ✗ | ✓ | ✗ | ✓ |
| `bulk_email_unsubscribe(valid)` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `bulk_email_unsubscribe(unknown)` | not found | | | | |

The unsubscribe probe is token-gated and idempotent: a second call keeps the first timestamp. Value probes are ported from TCS OS: audience union and de-duplication, the guardian winning, consent respected, unsubscribed excluded, an invalid address skipped without failing the batch, and a missing `{{unsubscribe_link}}` refused.

**Anon surface:** DB `bulk_email_unsubscribe`; HTTP Worker route `/api/admissions/unsubscribe/$token/` (GET and POST, no secrets, anon key only). **Confirmation gate.**

**Decisions for Eyram:**

- **D-14a.** Who may send. Recommendation: Manager only (D-2d).
- **D-14b.** Should GET unsubscribe immediately (TCS OS behaviour) or render a one-button confirm? Recommendation: GET shows a confirm button, and POST unsubscribes, whether from the button or from RFC 8058. That protects against link scanners. Legacy links still work, with one extra click.
- **D-14c.** Sending subdomain. Recommendation: keep `updates.tcsch.edu.gh`, which is already verified in Resend.
- **D-14d.** Confirm that TanStack Start server routes, with trailing-slash handling on this router version, can serve the exact `/api/admissions/unsubscribe/<token>/` path. The fallback is handling that path in `src/server.ts` before the TanStack handler.

**Size:** two tables, three or four RPCs, the mailer's bulk lane, one Worker route, a UI. This is the largest slice after 9. If it overruns, split 14a (the unsubscribe token, anon RPC and Worker route, which slice 15 needs anyway) from 14b (campaigns and send).

## Slice 15: Cutover, domain, TCS OS shutdown

**Delivers:**

- The Worker host routing for `admissions.tcsch.edu.gh` (legacy-path table under "Links already sent" and `410 Gone` for dead TCS OS endpoints).
- The runbook below (see "Cutover runbook").
- **Parity sign-off.**

**TCS OS files to read:** `docs/deployment.md` (whole); `docs/admissions/02-stack-and-schema.md` (URL shapes and the marketing-site endpoints).

**Conventions:** data safety (never connect the ERP to TCS OS's project, and no shared connection string); real contents never in any repo file; production steps are Eyram's.

**Role matrix:** re-run every admissions probe file against the local stack as a final regression. No new functions.

**Anon surface:** adds only the Worker's legacy-host routing (redirects, the unsubscribe proxy, and the slice 13 lead paths if D-13a). **Confirmation gate.**

**Decisions for Eyram:** D-15a through D-15f in the consolidated list.

**Size:** one Worker routing change and a written runbook. The migration script is Eyram-reviewed and Eyram-run.

---

## Links already sent to parents: how they keep resolving

Since all TCS OS applications and inquiries are test data, offer and draft links do not need to keep resolving on the ERP. Unsubscribe links matter only if some of the 6 leads and 17 guardians who received campaigns are real (still open question).

### Exact TCS OS URL shapes, token formats and lifetimes (for reference)

| Link | URL in the email | Called by the page | Token | Lifetime |
|---|---|---|---|---|
| Offer accept/decline | `{FRONTEND_BASE_URL}/offer?token=<t>` (`emails.py:361`) | `POST /api/admissions/offers/<t>/respond/` (`admissions/urls.py:14`, `templates/public/offer.html:202-234`) | `secrets.token_urlsafe(32)`, 43 base64url characters, **stored in plaintext**, unique (`models.py:77-78, 465`) | `OFFER_EXPIRY_DAYS`, default 14 (`settings.py:458`), from generation or reset. **Lazy** expiry (`models.py:474-482`). Reset reuses the token (`admin.py:417-433`). |
| Draft resume | `{FRONTEND_BASE_URL}/apply?draft_token=<t>` (`emails.py:203`) | `GET` and `PATCH /api/admissions/application-drafts/<t>/`; `POST …/<t>/submit/` (`urls.py:15-21`, `apply.html:1872-1960`) | Same format (`models.py:81-82, 633`) | `DRAFT_EXPIRY_DAYS`, default 30 (`settings.py:495`), fixed at creation, lazy (`models.py:648-650`). Dead once submitted. |
| Bulk-email unsubscribe | `{FRONTEND_BASE_URL}/api/admissions/unsubscribe/<t>/` in the body and in `List-Unsubscribe` with `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (`bulk_email.py:77-78, 248-249`) | GET renders the page; POST returns an empty 200 (`views.py:297-335`), CSRF-exempt | Same format, on `Guardian` and `Lead` (`models.py:169, 715`), eager, one shared space | **Permanent.** It never expires, and is idempotent. |
| PDF-gate email CTA | `{FRONTEND_BASE_URL}/inquiry` (`emails.py:422`) | — | none | permanent |

`FRONTEND_BASE_URL` in production is `https://admissions.tcsch.edu.gh`, per `settings.py:461-465` and `deployment.md`; Eyram confirms the env value. The root `/` redirects to `/inquiry` (`tcs_os/urls.py:19`).

### Options

1. **Migrate tokens with the records.** Dropped (2026-10-11): all TCS OS data is test data and nothing is imported, so no offer, draft or token is carried across. Whether any unsubscribe address is real stays the open question above.
2. **TCS OS keeps honouring tokens until they expire.** That conflicts with retiring TCS OS. It also breaks "no dual intake" for offers (a response is a state change) and for draft submit (which is intake). Unsubscribe tokens never expire, so TCS OS could never shut down. **Not recommended.**
3. **Redirect or serve on `admissions.tcsch.edu.gh`** (recommended):
   - Attach `admissions.tcsch.edu.gh` as a **custom domain on the ERP Worker**. The zone is already on Cloudflare (`deployment.md`: CNAME to `ghs.googlehosted.com`, and Turnstile allowed-domains).
   - The ERP's public routes use TCS OS's paths exactly: `/inquiry`, `/apply` (reads `?draft_token=`), `/offer` (reads `?token=`), and the server route `/api/admissions/unsubscribe/$token/`. So legacy links resolve with **no redirect at all**, query strings intact, and the RFC 8058 POST is answered directly with a `200`. Mail providers aren't required to follow redirects on POST.
   - `/` returns a 302 to `/inquiry`. `/admin/*` returns a 302 to the ERP staff host's `/admissions`.
   - `/api/admissions/quick-interest/` and `/api/admissions/pdf-gate/admissions-overview/` are served, proxying to the `admissions-public` actions (D-13a).
   - Every other old endpoint returns `410 Gone` with a short message: `inquiries/`, `applications/`, `upload-url/`, `application-drafts/*`, `offers/*/respond/`, `internal/*`, `/hr/*`, `/finance/*`. Those are only called by stale open TCS OS tabs, or by Cloud Tasks, which is shut down.
   - A pure Cloudflare Redirect Rule (host swap with the query kept) would work for the GETs, but not for the unsubscribe POST or the cross-origin lead POSTs. That's why serving is recommended over redirecting.

### How the no-dual-intake rule interacts

- **Drafts.** Once TCS OS intake stops, a parent's unexpired draft can't be submitted on TCS OS. Options:
  - (a) migrate unsubmitted, unexpired drafts (the token hash, `data` JSON in the same payload shape as the slice 10 drafts, `expires_at`), so `/apply?draft_token=…` resumes on the ERP after the DNS flip. Any draft-referenced files have to be copied too, and their paths remapped into ERP reservations or documents;
  - (b) don't migrate, and have TCS contact those parents;
  - (c) extend their expiry during migration.

  Recommendation: decide from the inventory count. If it's 0–3 drafts, (b) is simplest and safest for health data. Draft `data` can hold health answers.
- **Offers.** TCS OS offers are test data and aren't carried across, so no parent needs to respond across the window.
- **Unsubscribes.** These aren't intake. During the window TCS OS can still honour them if only intake POSTs are blocked. Any `unsubscribed_at` set in the window must be carried across, so migrate *after* the block, with a final unsubscribe re-sync just before the DNS flip.

---

## Bot check and email placement

**Where the Turnstile check lives.**

| | A. Supabase Edge Function (recommended) | B. TanStack Start server function or route in the Cloudflare Worker |
|---|---|---|
| Secrets | `TURNSTILE_SECRET_KEY`, `RESEND_API_KEY` and the service-role key (auto-injected) live in Supabase secrets, next to `invite-staff`'s SMTP secrets | Worker runtime secrets (`wrangler secret put`), read through `env`. Nothing reads Worker `env` today (`src/server.ts`). The service-role key would then live in two vendors. |
| Existing precedent | `invite-staff` has the two-client pattern, CORS and env handling (`index.ts`) | None: no `createServerFn` or `*.server.ts` exists |
| Enforcing "only after verification" | Submit RPCs are `revoke … from public, anon, authenticated` and `grant … to service_role`. Only a holder of the service-role key can call them, and only the Edge Function holds it. A role-matrix `expect: none` row proves every JWT role is denied. | Same DB grant pattern, but the Worker must hold the service-role key. That means a code-review risk of it leaking into the client bundle if a server-only module is imported client-side (CLAUDE.md's `server-only` rule). |
| IP for rate limiting | forwarded headers on the Edge runtime (confirm which is trustworthy) | `cf-connecting-ip` (reliable), and Cloudflare WAF rules apply if the Worker is on a custom domain in the `tcsch.edu.gh` zone |
| Async email | Same platform as the DB: pg_cron plus pg_net call the mailer function, and `EdgeRuntime.waitUntil` can kick it after a submit | Cron Triggers, or Cloudflare Queues (plan availability to check), polling the outbox with the service-role key |

**Recommendation:** A for Turnstile-verified writes, upload-URL minting and the mailer. The Worker gets only secret-free routing: legacy host handling and the unsubscribe server route, which calls an anon SECURITY DEFINER RPC with the public anon key. That keeps every secret in one place and every public write behind a DB grant that `anon` can't satisfy.

An alternative that avoids the service role: the Edge Function signs `HMAC(secret, sha256(payload) || ts)`, and an anon-executable RPC verifies it against the same secret in Vault. It's more moving parts, and not recommended for the first cut.

**Rate limiting.** Direct RPC calls go to `*.supabase.co`, **not** through the `tcsch.edu.gh` Cloudflare zone, so a Cloudflare rate-limit rule can't protect anon RPCs. The layers are:

1. Turnstile on every creating action;
2. the per-IP `public_rate_limits` counter inside service-role RPCs, with the IP passed by the Edge Function;
3. per-token caps on the direct anon token functions (draft save count, resume-email count, payload size);
4. optionally, Cloudflare's single free-plan rate-limit rule on the Worker host.

**Email async and retry.** The outbox row is written in the same transaction as the record, so there's never an email without a record or a record without its email. Delivery and retries follow slice 12, and the bulk lane follows slice 14. Transactional mail is always claimed first, which mirrors TCS OS's separate queues (`02-stack-and-schema.md:786-788`).

**Secrets placement.**

| Where | What |
|---|---|
| Supabase secrets | `TURNSTILE_SECRET_KEY`, `RESEND_API_KEY`, `MAILER_SHARED_SECRET`, `PUBLIC_BASE_URL` |
| Vault | `MAILER_SHARED_SECRET`, for pg_net |
| Cloudflare build env | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_TURNSTILE_SITE_KEY` (all public) |
| Worker runtime secrets | none |

`VITE_*` is build-time and public (DESIGN.md), so only public values ever carry that prefix.

## Slices that touch anon-callable surface (every function listed must be reviewed)

| Slice | Anon-reachable DB functions | Anon-reachable HTTP | Service-role-only DB functions behind it |
|---|---|---|---|
| 8 | `get_public_admissions_options()` | `admissions-public`: `inquiry` | `submit_inquiry`, `check_public_rate_limit` |
| 9 | — | `admissions-public`: `upload_url`, `application` | `reserve_application_upload`, `submit_application` |
| 10 | `get_application_draft(text)`, `save_application_draft(text, jsonb, int, text, boolean)` | `admissions-public`: `draft_create`, `draft_submit` | `create_application_draft`, `submit_application_draft` |
| 11 | `get_offer_context(text)` | `admissions-public`: `offer_respond` | `respond_to_offer` |
| 13 | — | `admissions-public`: `quick_interest`, `pdf_gate` (cross-origin, CORS allow-list) | `capture_lead` |
| 14 | `bulk_email_unsubscribe(text)` | Worker `GET` and `POST /api/admissions/unsubscribe/$token/` | — |
| 15 | — | Worker host routing for `admissions.tcsch.edu.gh` (redirects, `410`s, lead-path proxy) | — |

Slice 12's mailer is secret-gated, not anon, but it's reviewed with the same rigour. There are no anon table grants, no anon storage policies (under recommendation D-9a), and no new anon select policy.

---

## Decisions that are Eyram's (consolidated)

Each decision has a recommendation. Rows marked **Decided** or **Superseded** are Eyram's recorded decisions (see "Decisions recorded"); every other row is still open.

| ID | Decision | Recommendation |
|---|---|---|
| D-0a | Full figures for Abena Konadu Owusu and Yaw Darko Asamoah | **Written off 2026-10-07:** they were dummy records. No cases. |
| D-0b | Expected values for the payroll coverage-gap cases | **Partly decided 2026-10-07** (accountant confirmed (reported, written copy to be saved)): see slice 0. Five cases stay PENDING. |
| D-0c | Import TCS OS's hand-computed flag and band cases | **Decided 2026-10-07, as recommended:** a separate file, `payslips-tcsos-hand.sql`. |
| D-0d | Statutory numbers to reconfirm | GRA "Year 2024" PAYE bands (the unchecked CONSTRAINTS item) and the SSNIT/Tier 2 split (0.5/13/5) against an official SSNIT source. **2026-10-07:** the split is accountant confirmed (reported, written copy to be saved); the 2025 set is asserted as current behaviour, not confirmed correct. |
| D-1a | Campus seeding | **Decided 2026-09-29, as recommended.** Rename the existing branch to "Main"; add "Annex" in both seed files. |
| D-1b | Which modules stay school-wide | **Decided 2026-09-29, as recommended.** All existing ones, on Main. |
| D-1c | Campus filter on existing screens | **Decided 2026-09-29, as recommended.** None in Phase 2. |
| D-2a | Capabilities storage shape | **Decided 2026-09-29, as recommended.** Side table `staff_admissions_capabilities`, RPC-only writes, audited. |
| D-2b | Which roles may hold which capability | **Superseded 2026-09-29 by the fifth role.** `can_decide`: Manager or Admissions Officer. `can_view_health`: any role. `grade_bands` (and `all_grades`): Admissions Officer only. |
| D-2g | How a full officer sees all grades | **Decided 2026-09-29, as recommended:** an explicit `all_grades boolean`, which includes unbanded grades and is mutually exclusive with `grade_bands`. See "Roles and capabilities". |
| D-1b-a | Guard predicates for the new role | **Decided 2026-09-29, as recommended:** rewrite `can_write()` and `require_writable_role()` as allowlists. |
| D-1b-b | Officer reads outside admissions | **Decided 2026-09-29, as recommended:** `branches` yes; `staff` names only through a narrow function; `business_settings` and the store no. |
| D-1b-c | Auditor reading admissions | **Decided 2026-09-29, as recommended:** yes, read-only; health only if granted. |
| D-1b-d | Role string | **Decided 2026-09-29, as recommended:** `Admissions Officer`. |
| D-2c | Band source column | **Decided 2026-09-29, as recommended.** `applications.year_group_applied_for`, live. |
| D-2d | `can_send_bulk_email` | **Decided 2026-09-29, as recommended.** Not a capability; bulk send is Manager only. |
| D-2e | Who grants capabilities; self-grant | **Decided 2026-09-29, as recommended.** Active Manager only; self-grant allowed and audited. |
| D-2f | Does a Manager need explicit `can_decide`? | **Decided 2026-09-29, as recommended.** Yes. |
| D-3a | Is `students` the long-term student model? | **Decided 2026-09-29, as recommended.** Yes. Created at inquiry or application, `student_id` at enrolment, extended by the Student Management phase. |
| D-3b | `academic_year` format | **Decided 2026-09-29, as recommended.** Text, picked from a list. |
| D-4a | Health-gate shape | A boolean capability intersected with band scope. |
| D-4b | Who holds the health gate at go-live | Eyram plus the confirmed coordinators; all ungranted by default. |
| D-4c | Audit health reads | Not in Phase 2. |
| D-4d | Retention of health data | Keep for enrolled students; purge for closed-negative applications and expired drafts after a period set with TCS (Act 843 check). |
| D-5a | Reference formats final | Keep verbatim. |
| D-5b | Manager moving an application out of a terminal stage | Allowed except out of `enrolled`; audited. |
| D-6a | Offer TTL | **Decided 2026-10-12, as recommended:** 14 days in `admissions_settings.offer_ttl_days` (1 to 90), changed by a Manager-only RPC, read by Manager and Auditor (6b). |
| D-6b | Re-offer token | **Decided 2026-10-12, as recommended:** always a new token; reset moves the stage back to offer. |
| D-6c | Capacity count basis | **Decided 2026-10-12, as recommended:** leave out `offer_declined` and offers declined, withdrawn or past expiry (a deliberate change from TCS OS). |
| D-6d | `mark_enrolled` | **Decided 2026-10-12, as recommended:** Manager only, no capability needed. |
| D-6e | Staff-recorded offer response | **Decided 2026-10-12, as recommended:** `record_offer_response` for a reply the parent gives staff (6b). |
| D-6f | Decisions at inquiry or enrolled | **Decided 2026-10-12, as recommended:** refused. |
| D-6g | Student ID year | **Decided 2026-10-12, as recommended:** the calendar year of enrolment, Africa/Accra (TCS OS parity). Open: do the real current TCS student IDs follow YYPPNNNN, and which year did they use? |
| D-6h | Unbanded or legacy grade at enrolment | **Decided 2026-10-12, as recommended:** refuse enrolment. Slice 7b adds a Manager-only grade-correction RPC. |
| D-6i | A student's second application | **Decided 2026-10-12, as recommended:** keep the existing ID; refuse a second enrolment in the same academic year; the enrolment stage audit row carries the ID. |
| D-6j | Decision change once an offer exists | **Decided 2026-10-12, changed from the recommendation:** a pending offer is withdrawn with a new `withdrawn` response (not `expired`); an accepted offer blocks the change; enrolled blocks it. |
| D-6k | Separate create and change RPCs for decisions | **Decided 2026-10-12, as recommended:** `record_decision` and `change_decision`. |
| D-6l | Offer expiry writes | **Decided 2026-10-12, as recommended:** no read path writes; a service_role sweep settles; slice 12 schedules it. |
| D-6m | `reset_offer` on a pending or accepted offer | **Decided 2026-10-12, as recommended:** allowed on pending, refused on accepted. |
| D-6n | Audit capacity and TTL changes | **Decided 2026-10-12, as recommended:** yes. |
| D-6o | Capacity academic year | **Decided 2026-10-12, as recommended:** exact text, no year list yet; carried to slices 7b and 8. |
| D-6p | Split slice 6 | **Decided 2026-10-12, as recommended:** 6a (decisions, capacity) and 6b (offers, enrolment). |
| D-6q | Staff read of `application_offers.token_hash` | **Decided 2026-10-12:** leave the table-level select grant as it is, no revoke. The hash is the SHA-256 of 32 random bytes and can't be reversed; the offer page compares hashes, so the hash alone gives no access; `application_offer_status` hides it; and a column-level grant would make `select *` on the table fail. Slice 7a carries this forward: the UI selects explicit columns and never selects `token_hash`. |
| D-7a | Staff route prefix | `/admissions`. Public routes keep TCS OS's bare paths. |
| D-8a | Bot-check placement | Supabase Edge Function; submit RPCs service-role-only. |
| D-8b | Turnstile keys | New widget for the ERP hosts (or add hosts to the existing widget). Secret in Supabase secrets, site key in the Cloudflare build env. Eyram runs this. |
| D-8c | Inquiry de-duplication | Keep none, for parity. |
| D-8d | Rate-limiting approach | Turnstile, a per-IP DB counter through the Edge Function, and per-token caps. TCS OS's numbers (20, 120 and 60 per hour). |
| D-8e | CORS allow-list | ERP origin(s), `admissions.tcsch.edu.gh`, marketing origins. |
| D-9a | Upload mechanism | Signed upload URL from the Edge Function, bound to a reservation. |
| D-9b | Anon re-submission overwriting existing data | No: snapshot and flag. |
| D-9c | Matched application in a stage other than `inquiry` | New row for a different year or grade; refuse the same year and grade. |
| D-9d | Phone rule | Keep `+CCC` plus 9 digits. |
| D-9e | Application-fee proof | Optional. |
| D-10a | Draft TTL | 30 days; confirm the live value. |
| D-10b | Draft purge | 30 days after expiry. |
| D-11a | Offer page shows the child's name before response | First name and grade. |
| D-12a | Email provider | Resend HTTP API, with a new key in the existing Resend team (domains already verified). |
| D-12b | Email queue | Outbox plus pg_cron plus pg_net, calling the mailer Edge Function. Enable both extensions on hosted. |
| D-12c | Plaintext token links in the outbox | Blank after send; hide the body column from staff. |
| D-12d | GoTrue production SMTP | Point it at Resend in the same session. |
| D-13a | Marketing-site lead endpoints at cutover | Serve TCS OS's exact paths through the Worker; repoint the marketing site later. |
| D-13b | Turnstile host names | Include the marketing origins. |
| D-14a | Who may send bulk email | Manager. |
| D-14b | Unsubscribe GET behaviour | Confirm button on GET; POST unsubscribes. |
| D-14c | Bulk sending subdomain | `updates.tcsch.edu.gh`. |
| D-14d | Server-route path handling | Confirm the exact trailing-slash path works; fallback in `src/server.ts`. |
| D-15a | Token migration versus TCS OS honouring tokens | **Dropped 2026-10-11:** nothing is imported, so no tokens move. Don't keep TCS OS alive for tokens. |
| D-15b | Redirect mapping | Attach `admissions.tcsch.edu.gh` to the ERP Worker. Serve identical public paths, 302 `/` and `/admin`, 410 everything else. |
| D-15c | Pending offers across the window | **Dropped 2026-10-11:** TCS OS offers are test data and aren't carried across. |
| D-15d | Stopping TCS OS intake | A Cloudflare WAF rule blocking `POST /api/admissions/{inquiries,applications,upload-url,application-drafts,offers}*` (needs the record proxied), or a maintenance deploy of TCS OS by Eyram. |
| D-15e | DNS and cutover sequence | As in the runbook, including `app.tcsch.edu.gh` for the ERP staff host (confirm the ERP's production host). |
| D-15f | How long TCS OS stays read-only before shutdown | 30 days, covering one full draft TTL. Then delete the Cloud Run service, queues and secrets, and rotate or delete the TCS OS Resend key and Turnstile secret. |

## Slice 0 detail: reference payslip figures and coverage gaps

**Engine facts the probes depend on** (live `create_payslip`, from `20260909130000_employees_and_approval_workflow.sql:379`):

- SSNIT employee, SSNIT employer and Tier 2 are computed on **basic salary only**, each rounded to 2 decimal places and each gated on its `pays_*` flag.
- Taxable income = basic + overtime pay + taxable allowances − SSNIT − Tier 2, floored at 0.
- PAYE walks the latest `paye_bands` set **with per-band rounding**.
- Gross = basic + overtime + all allowances.
- Deductions = PAYE + Tier 2 + SSNIT + fines + IOU. Net = gross − deductions.
- Live rates (local database): `statutory_rates` 0.5 / 13 / 5 / 0 (accountant confirmed, reported 2026-10-07), effective 2025-01-01.
- `paye_bands` (monthly), two sets: effective 2025-01-01 (labelled "current behaviour, not confirmed correct") and effective 2026-09-01 (applies to first real payroll):

| Band | From | To | Rate |
|---|---|---|---|
| 1 | 0 | 490 | 0% |
| 2 | 490 | 600 | 5% |
| 3 | 600 | 730 | 10% |
| 4 | 730 | 3,896.67 | 17.5% |
| 5 | 3,896.67 | 19,896.67 | 25% |
| 6 | 19,896.67 | 50,000 | 30% |
| 7 | 50,000 | — | 35% |

**Fully specified, confirmed against a real ERP payslip:**

| Case | Basic | SSNIT (emp) | Tier 2 | Taxable | PAYE | Total ded. | Net | SSNIT (employer) | Source |
|---|---|---|---|---|---|---|---|---|---|
| Emmanuel Ansah (all flags on) | 6,500.00 | 32.50 | 325.00 | 6,142.50 | 1,134.13 | 1,491.63 | **5,008.37** | 845.00 | `tcs-os/docs/DESIGN.md:145-149`; `backend/modules/hr/tests.py:84-104`; `run_parity_test_payroll.py:60-66` |

Per-band PAYE for this case: 5.50 + 13.00 + 554.17 + 561.46 = 1,134.13. Sum-then-round would give 1,134.12, the bug recorded in `hr/tests.py:197-212`.

**TCS OS hand-computed cases (independent arithmetic, never ERP-confirmed)** (`hr/tests.py:116-195`):

| Case | PAYE | Net |
|---|---|---|
| 6,500, no SSNIT | 1,142.25 | 5,032.75 |
| 6,500, no Tier 2 | 1,215.38 | 5,252.12 |
| 6,500, no PAYE | 0.00 | 6,142.50 |
| 400, all on | 0.00 | 378.00 |

The 400 case has SSNIT 2.00 and Tier 2 20.00. These carry the D-0c label.

**What the suite asserts** (`supabase/golden/payslips.sql`; months: August 2026 = 2025 set, September 2026 = 2026 set, October 2026 = 2026 set plus the overtime row):

| Group | Cases | Status |
|---|---|---|
| G0 | rate rows pinned (statutory rates, both band sets, the overtime row) | asserted |
| S26 | 2026 band edges 588 to 60,000 (PAYE-only), an edge reached through an allowance, band set picked by month, basic 2,000, taxable allowance, National Service (taxable income not asserted), PAYE-exempt only (taxable income not asserted) | asserted |
| S26-HI | basic 25,000 and 60,000 | asserted; no ceiling known to the accountant |
| S26-D | fines 100, IOU 250, both (basic 3,100); half-pesewa PAYE tie (449.225 to 449.23) | asserted; accountant confirmed (reported, written copy to be saved) |
| S25 | 2025 band edges 490 to 60,000, an allowance edge, set picked by month, basic 2,000 | asserted; current behaviour, not confirmed correct |
| E | Eyram's overtime figures (20.00 / 78.05 / 1,435.95; 50.00 / 1,805.95; 263.81 / 1,931.69; 3.5 h at 40.37 gives 7.07) | asserted |
| E-R | non-qualifying overtime at the printed figure: 2.5 h × 40.05 = 100.125, taxed as 100.13 (September, basic 1,900, PAYE 211.34; was Q-OT-UNR); 1.5 h × 20.05 = 30.075, taxed as 30.08 (October, basic 4,500, PAYE 675.15) | asserted; accountant confirmed (reported, written copy to be saved) |
| P | Emmanuel Ansah, August 2026 (net 5,008.37, the parity figure) and September 2026 (5,002.37, derived) | asserted |
| GA-X | October run with one excluded employee, posted (overtime-tax line present); September run posted (no overtime-tax line); unaccounted employee blocks submission | asserted |
| H (`payslips-tcsos-hand.sql`) | the four TCS OS cases above, August 2026 (H3 doesn't assert taxable income) | asserted; TCS OS hand-computed, not ERP-confirmed |

**PENDING, commented out with expected values:** Q-ALW-N (non-taxable allowance 500), Q-ALW-MIX (taxable 500 plus non-taxable 300), Q-NSS-ALW (National Service plus allowance 300, taxable income 1,800 shown with no PAYE), Q-POST-3 (posting fines to 4910 and IOU to 1350).

## TCS OS runway (as of 2026-10-10)

How long TCS OS can keep running, to set the pace of this port. From a read-only investigation of `~/projects/tcs-os` on 2026-10-08 (code, config and docs only, no production access), plus what Eyram reported on 2026-10-10. Three kinds of statement, kept apart: **found** (in TCS OS's code or docs), **reported** (Eyram, or the Cloud Run console as Eyram read it), and **inferred** (not written down anywhere).

### Found in the code and docs

- **Hosting.** One Cloud Run service, `admissions`, in GCP project `tcs-os`, region `europe-west1`, `--min-instances=0` (scales to zero). The image is `python:3.12-slim`, running gunicorn. You deploy by hand with `gcloud`; CI only runs check and test.
- **Domain.** `admissions.tcsch.edu.gh` uses a Cloud Run domain mapping with a Google-managed certificate, reached through a Cloudflare CNAME to `ghs.googlehosted.com` (DNS-only). No certificate expiry is recorded. The Cloudflare rate-limit rule (TCS OS `deployment.md` step 13) was never applied.
- **Data and secrets.** Supabase is used as plain Postgres plus the `admissions-documents` Storage bucket. Six secrets are in GCP Secret Manager. Cloud Tasks queues: `admissions-bulk-email`, plus `admissions-transactional-email` if the `0015` deploy happened.
- **Third-party services.** GCP, Supabase, Resend (transactional and bulk, from `tcsch.edu.gh` and `updates.tcsch.edu.gh`), Cloudflare Turnstile and Cloudflare DNS. If GCP or Supabase lapses, TCS OS goes down. If Resend lapses, emails stop but forms still save. There's no payment gateway and no SMS; the application fee is paid by bank transfer.
- **No hard deadline.** The code and docs contain no hosting renewal, certificate expiry, contract or licence date.
- **No scheduler.** There's no cron and no Celery. Offer expiry (14 days) and draft expiry (30 days) are applied lazily, the next time a record is read. Every management command is run by hand.
- **Last recorded deploy.** TCS OS `deployment.md`, last reconciled 2026-09-03, records revision `admissions-00019-qm7`, with migrations `0015`–`0019` not yet applied.
- **HR and Finance were never deployed.** They hold only test data, and nothing needs porting from them.
- **Hidden dependency.** The marketing site at `tcsch.edu.gh` (with Vercel previews) POSTs cross-origin to `/api/admissions/quick-interest/` and `/api/admissions/pdf-gate/admissions-overview/`.
- **Links already sent never expire.** Unsubscribe links are permanent. Offer and draft links last 14 and 30 days.
- **Data that would be lost unless deliberately exported:** `django_admin_log`, the `TransactionalEmail` and `EmailCampaignRecipient` delivery logs, staff accounts, and Cloud Run logs.
- **Local config.** TCS OS's `backend/.env` points `DATABASE_URL` and `SUPABASE_URL` at a hosted Supabase project, not a local one.

### Reported (2026-10-10, not verified from code)

- **The Cloud Run console shows** revision `admissions-00024-xxb` serving 100% of traffic, deployed about 12 days before 2026-10-10. The `admissions-migrate` job was updated at the same time. So production is probably newer than the docs say, and **the docs' last recorded revision (`admissions-00019-qm7`) is stale**. Which migrations production is on is still unconfirmed.
- The TCS OS Supabase project and this ERP's Supabase project are **separate projects, both on free plans**.
- **The Google Cloud trial was ending on about 2026-10-13 and needed upgrading.** Eyram is doing that on 2026-10-10. It is **not recorded as done**.

### Inferred

- Nothing technical expires, so the runway is set by billing (the GCP trial above) and by the admissions season.
- The academic year starts in September, and the forms offer 2027/2028 onward. That suggests the 2027/28 enquiry and application season runs roughly January to August 2027, so cutover should land in a quiet period, plausibly before January 2027, or after the season.
- All TCS OS applications and inquiries are test data. Still open: whether the 6 leads and 17 guardians who received campaigns are test data (see point 6 under "Where the code contradicts the brief").
- The hr/finance migrations and the parity-test payroll may have been run against whatever database `backend/.env` points at.
- Django 5.2 LTS and Python 3.12 force no upgrade before about April 2028.

### What has to be ported before switch-off, and what can be dropped

- **Must port:** slices 3–7b (the staff pipeline), 8 and 9 (inquiry and application forms), 11 (offer response, which live offer links depend on), 12 (transactional email), 13 (lead capture, unless the marketing site's widgets are repointed instead), the unsubscribe endpoint and unsubscribe state from slice 14, and slice 15.
- **Could drop or defer:** TCS OS's HR and Finance; campaign sending itself (only unsubscribe must keep working); drafts (slice 10), if the few affected parents are contacted by hand; `audit_staff_roles` and `reset_admissions_data`.
- **Order:** as in the Status table. Slice 10 and campaign sending can move to after cutover if time is short. The runbook's step-1 inventory comes before slice 15 is planned.

### Questions only Eyram can answer

1. Which date are GCP (after the trial upgrade) and Resend paid until, and on which plans? Does either free Supabase plan's inactivity pausing affect TCS OS?
2. When does `tcsch.edu.gh` renew, and who holds the registrar account?
3. Which TCS OS migrations is `admissions-00024-xxb` on? Did `0015`–`0019` reach production?
4. Is the hosted Supabase project in TCS OS's `backend/.env` its production database? If so, were the HR and Finance migrations and the parity-test payroll run against it?
5. Which staff actually use the TCS OS Django admin for admissions, and how often? Who else depends on the staff alert emails?
6. When does TCS's 2027/28 enquiry and application season really start, and what's the busiest stretch?
7. Which host will the ERP staff app use? The TCS OS journal says `app.tcsch.edu.gh`; its deployment docs only mention `admissions.tcsch.edu.gh`.
8. Who maintains the marketing site, and can its two widgets be repointed, or must the ERP serve those exact paths?
9. Partly answered 2026-10-11: all TCS OS applications and inquiries are test data. Still open: are the 6 leads and 17 guardians who received TCS OS campaigns real or test data? That decides whether their unsubscribe links need handling at cutover.

## Cutover runbook (slice 15)

**[E]** marks Eyram's production steps. The main session hands over exact commands and never runs them.

**Parity means all of the following, before step 1:**

- Every slice 0–14 has been reviewed.
- Every role-matrix file passes locally.
- These flows have been run end to end in a browser against the hosted ERP with **invented** data, intake flag on only for the test and then off again:
  - an inquiry;
  - an application with uploads, including a preschool grade without vaccination (refused) and Annex with Grade 3 (refused);
  - a draft save, resume and submit;
  - a decision with a capacity warning;
  - an offer email, then accept, then mark enrolled (student ID assigned);
  - an expired offer that turns into `offer_declined`;
  - a lead capture from a marketing-origin test page;
  - a bulk campaign to test addresses, with one invalid address skipped;
  - a one-click unsubscribe POST that returns 200;
  - a capability matrix check with real dev accounts.
- Test rows are deleted afterwards through the Manager-run purge RPC or hand SQL. **[E]**

**Sequence:**

1. **[E] Prepare the ERP.** `npx supabase db push`; enable `pg_cron` and `pg_net`; `npx supabase functions deploy admissions-public admissions-mailer`; `npx supabase secrets set TURNSTILE_SECRET_KEY=… RESEND_API_KEY=… MAILER_SHARED_SECRET=… PUBLIC_BASE_URL=…`; add the Vault secret; deploy the frontend with `frontend/scripts/deploy-production.sh` (CONSTRAINTS.md, "Deployment"). That script currently passes only the two Supabase values into the build, so the slice that adds `VITE_TURNSTILE_SITE_KEY` must extend it to read that key from `frontend/.env.deploy` too. Leave `admissions_settings.public_intake_open = false`.
2. **[E] Stop TCS OS intake** (D-15d). Block the creating POSTs. Staff stop using the TCS OS admin. Leave unsubscribe and GET pages working.
3. **[E] Set roles and grant capabilities** to the real staff (fifth-role decision, D-2g, D-4b) through Settings. **[E] Open intake:** set `public_intake_open = true`.
4. **[E] DNS.**
   - Remove the Cloud Run domain mapping for `admissions.tcsch.edu.gh`, and attach `admissions.tcsch.edu.gh` as a Worker custom domain.
   - Point `app.tcsch.edu.gh` at the ERP Worker, if that's the ERP staff host (D-15e).
   - Add both hosts to the Turnstile widget and to Supabase Auth `site_url` and `additional_redirect_urls` for the staff host.
   - Smoke-test the four legacy URL shapes, including `curl -X POST …/api/admissions/unsubscribe/<test-token>/` returning 200.
5. **[E] Keep TCS OS read-only** for N days (D-15f): Cloud Run still up behind its `*.run.app` URL, with intake blocked. It's only for reference; it gets no traffic after the DNS flip.
6. **[E] Shut down TCS OS:** delete the Cloud Run service, Cloud Tasks queues and Secret Manager secrets; rotate or delete the TCS OS Resend key and Turnstile secret; delete the TCS OS Supabase project when Eyram decides (the data is test data). Then update both repos' docs.

**Open items for the runbook:**

- Are the 6 leads and 17 guardians who received TCS OS campaigns real or test data?
- Hosted Annex (2026-10-11): slices 3a and 3b are applied on hosted. Hosted has one branch, "Treasures Christian School" (created 2026-09-09), and no Annex row, so `seed.production.sql` has not been run there. Don't run that file on hosted: its first block would rename the existing branch to Main and re-seed expense categories and allowance types. Instead run `docs/admissions/hosted-annex-setup.sql` by hand in the SQL editor: it adds Annex (only if missing) and its two grade rules, and touches nothing else. [E]

---

## Future slice (not scheduled): Student emergency summary

**Timing:** after enrolment exists (Student Management).

**Delivers:** a student-level record of emergency fields only (allergies, conditions, medication, doctor, emergency contacts), for enrolled students only, filled from the application's health answers at enrolment. Staff who need it in an emergency include the class teacher, admissions officer, administrator, a cook checking food allergies, and a nurse or health officer; more roles may be added over time.

**Access model (decided 2026-10-11):**
- Readable by all active staff (`is_active_staff()`).
- Enrolled students only, and the emergency fields only.
- Edits restricted to a nurse or administrator role.
- Read logging is proposed, because access is broad.

**New staff roles:** cook, nurse and class teacher don't exist in the system yet, so this slice must add them.

**Note:** this future slice differs from slice 4. Slice 4 covers admissions application health answers, which include children who never enrol. This future slice covers enrolled students.

---

## Regression carry-back for admissions (TCS OS rules to re-express as probes)

| TCS OS source | Rule | ERP probe (slice) |
|---|---|---|
| `tests.py:819-840` GradeBandDefinitionTests | Bands are disjoint, cover exactly the classified grades, and Grade 10 has none | Select on `admissions_grades`, raising on violation (2) |
| `tests.py:842-1020` GradeBandCoordinatorScopingTests | In-band visibility across both campuses; unbanded grades visible only to admin; misconfigured coordinator sees nothing; live grade change moves the application; out-of-band object blocked; health, document and family scoping with de-duplication | Capability-variant read probes (3, 4) |
| `tests.py:1022-1095` MoveToDocumentReview* | Only from inquiry or application; APP reference assigned through the real write path; terminal stages refused; a double call is safe | (5) |
| `tests.py:47-236` Lead endpoints and UTM | Source server-forced; email or phone required; consent default false; UTM truncated, null accepted, not echoed | Service-role value probes (13) |
| `tests.py:238-410` Audience, placeholders, unsubscribe | Audience union, de-dup with guardian winning, consent and unsubscribe respected, one-target check, unknown token not found, one-click POST | (14) |
| `tests.py:541-620` TransactionalEmailWorker | Missing, wrong or unset secret refused; redelivery idempotent; transient failure stays pending; final attempt marks failed | Mailer RPCs (12) |
| `tests.py:622-815` Administration permissions | No delete anywhere; capabilities never auto-granted | "Direct write denied for all" and "no capability means denied" probes (2–6) |
| `models.py:65-75, 93-116, 329-352` (untested in TCS OS) | INQ and APP formats, assigned once, per-year sequences; student ID `YYPPNNNN`; SHS gets no ID | (5, 6) |
| `models.py:300-320, 418-511` (untested) | Offer needs an accepted decision; enrolled needs decision and offer; waitlisted/rejected propagate (not onto enrolled); declined or expired → `offer_declined`; accepted never advances | (6, 11) |
| `admin.py:273-307` (untested) | Capacity warning only on accepted, per (year, grade, campus), silent with no capacity row, never blocks | (6) |
| `serializers.py:204-229` (untested) | Preschool needs vaccination proof; Annex accepts only Pre Nursery and Nursery 1; declaration required | (9) |
| `serializers.py:251-330` (untested) | Guardian email, then student name and DOB, then (year, grade) matching; inquiry-to-application advance keeps the INQ reference | (9), with D-9b and D-9c changes asserted explicitly |
| `views.py:182-259` (untested) | Draft expired or submitted refused on get, save and submit; submit single-use | (10) |
| `storage.py`, `serializers.py:371-398` (untested) | Extension and size limits; path generated server-side | Edge Function and bucket (9), plus the reservation-binding probe |

---

## Open unknowns from the planning pass

These are the planner's own caveats. Resolve each during the slice it
affects.

The main session spot-checked these citations against the code on
2026-09-29, and each one held:

- band scoping on `year_group_applied_for` (`admin.py:209`);
- the re-submission overwrite and stage reset (`serializers.py:262-322`);
- `OFFER_EXPIRY_DAYS` = 14 and `DRAFT_EXPIRY_DAYS` = 30 (`settings.py:458,495`);
- the unsubscribe GET that changes state (`views.py:320-335`);
- the SHS TODO (`models.py:14-24`);
- the offer link shape (`emails.py:361`) and the public API paths (`urls.py`);
- Resend batch being all-or-nothing (`02-stack-and-schema.md:670-675`);
- production on migrations through `0014` only (`deployment.md:15`);
- Abena Konadu Owusu and Yaw Darko Asamoah recorded with basic salary only (`JOURNAL.md:878-886`);
- the onboarding raw token in the storage path (`onboarding-store.ts:312`);
- 13 unordered `branches … limit(1).single()` lookups in 13 files under `frontend/src/data/` (first counted as 14; see "ERP-side findings").

- **CONSTRAINTS.md says "current grade", but the code scopes on the grade applied for.** CONSTRAINTS.md's wording is "resolved live from the applicant's current grade". TCS OS actually scopes on `year_group_applied_for` (`admin.py:209`; `tcs-os/docs/DESIGN.md`, "Live queryset scoping"). The plan assumes the latter (D-2c). If Eyram confirms, CONSTRAINTS.md's wording should be tightened.
- **The brief's rule list isn't in the TCS OS tests.** Reference formats, stage gating, capacity, Annex, vaccination, matching, expiry and upload limits have no tests in `admissions/tests.py`; I checked by grepping the test names. Those probes are derived from model, serializer and admin code.
- **I couldn't confirm what's deployed on TCS OS.** `deployment.md` was last reconciled 2026-09-03, with production at `0014`. Later TCS OS journal entries cover HR and finance only and don't mention an admissions deploy. So I don't know whether `0015`–`0019` ever reached production. That affects what data exists (TransactionalEmail, StaffProfile rows) and what the ~3 records look like.
- **The Abena and Yaw figures in the plan are my own arithmetic.** It assumes all three `pays_*` flags are on, and must not be asserted without D-0a. The TCS OS journal only says "matched to the cent" and gives basic salary.
- **I don't know the production state of the ERP itself.** The CONSTRAINTS.md checklist still shows "Create a dedicated hosted Supabase project" unchecked. But the journal describes production onboarding testing, a migration that failed "against production", and a pending `db push`. So a hosted project seems to exist. I don't know its branch name, or whether it's already on a custom domain. The ERP's production host (`app.tcsch.edu.gh`?) is unconfirmed; `wrangler.jsonc` has no routes.
- **Three platform capabilities need confirming during the relevant slice's planning, not now:**
  - Resend's idempotency-key support and current batch rate limit;
  - Cloudflare Queues availability on TCS's plan (only relevant if option B is chosen);
  - whether TanStack Start server routes on `@tanstack/react-start ^1.168` can serve the exact trailing-slash path `/api/admissions/unsubscribe/<token>/` (D-14d).
- **Out-of-scope issues worth their own later ticket** (not planned here):
  - the onboarding flow's raw token in the storage path (`onboarding-store.ts:312`);
  - onboarding's unchecked client-supplied `storage_path` in `submit_onboarding_form`;
  - `invite-staff`'s `Access-Control-Allow-Origin: *`.
- **Slice 1 touches finance and POS stores** (13 call sites), which is outside admissions. It's included because adding Annex without it makes payroll and expense writes land on an undefined branch. The main session should get Eyram's OK that this fix belongs in Phase 2.
- **No route has an access guard (open item, 2026-09-29).** There's no `beforeLoad` anywhere in `frontend/src/routes/`. Pages are protected only by sidebar visibility, some in-page checks, and RLS. Slice 1b-ii adds a route-guard allowlist for the Admissions Officer only. Guards for the existing roles (for example an Attendant opening a finance URL directly, which renders with empty or denied data) aren't planned. Eyram to decide whether and when.
- **Don't run `pg_available_extensions` as proof of hosted support.** I only confirmed `pg_cron`, `pg_net`, `pgmq` and `http` are *available* locally. Whether they're enabled on the hosted project is for Eyram to check.
- **I didn't read `templates/public/apply.html` in full**, only the draft, upload and Turnstile regions. The exact draft `data` key shape comes from the fact that the draft submit feeds `draft.data` straight into `ApplicationSerializer` (`views.py`, `ApplicationDraftSubmitView`). If the form stores extra UI-only keys, slice 10's shape needs to tolerate them.
