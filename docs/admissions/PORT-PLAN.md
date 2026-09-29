# Admissions port plan (TCS OS → TCS ERP)

**Status:** under review, 2026-09-29. Two batches of decisions are recorded below ("Decisions recorded"); the rest are open. It's a plan only: no application code and no migrations. Nothing in Phase 2 gets built until Eyram has reviewed this file.
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

At cutover, `admissions.tcsch.edu.gh` is attached to the ERP Worker. The ERP's public routes use TCS OS's exact paths (`/inquiry`, `/apply`, `/offer`, `/api/admissions/unsubscribe/<token>/`), so every link already in a parent's inbox keeps resolving, including RFC 8058 one-click POSTs, with no redirect needed. Tokens migrate as SHA-256 hashes of the verbatim TCS OS tokens.

## Status

| # | Slice | Status | Depends on |
|---|---|---|---|
| 0 | Payroll regression carry-back (SQL probes for `create_payslip`) | not started | — |
| 1 | Campuses: make a second branch safe, seed Main + Annex | built, awaiting Eyram's review (uncommitted) | — |
| 1b | Admissions Officer role (fifth role; allowlist guards; read-exposure fixes) | not started | 1 |
| 2 | Admissions grade reference data + capabilities layer | not started | 1b |
| 3 | Core admissions schema + staff RLS (no health, no documents) | not started | 2 |
| 4 | Health info (health gate) + documents metadata + private bucket | not started | 3 |
| 5 | Reference numbering + stage transitions + notes/document review RPCs | not started | 4 |
| 6 | Decisions, offers, enrolment gate, capacity warning (staff side) | not started | 5 |
| 7a | Staff pipeline UI: list, detail, notes, documents, health panel | not started | 6 |
| 7b | Staff pipeline UI: decision/offer/enrol actions, capacity, capability admin | not started | 7a |
| 8 | Public request path (Edge Function, Turnstile, rate limits, intake flag) + public Inquiry form | not started | 7b |
| 9 | Public Application form: direct submit, uploads, matching, rules | not started | 8 |
| 10 | Application drafts: save/resume tokens | not started | 9 |
| 11 | Public offer response page | not started | 8, 6 |
| 12 | Transactional email (outbox, mailer, templates, resend-failed) | not started | 8 (and 6, 9, 10 for the emails it sends) |
| 13 | Lead capture (marketing-site endpoints) | not started | 8, 12 |
| 14 | Bulk email + one-click unsubscribe | not started | 12, 13 |
| 15 | Hand migration of real records, cutover, domain, TCS OS shutdown | not started | all |

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

   Eyram needs to confirm the live state before slice 15. It changes which tables hold data.
6. **There is probably more real data than "~3 records".** Lead capture has been live since 2026-09-02/03, with a real production submission (`deployment.md:18`). Real bulk campaigns have been sent (`deployment.md:16`). So besides the ~3 real applications, production likely holds:
   - real `Lead` rows, each with a permanent unsubscribe token already emailed out;
   - `Guardian` unsubscribe tokens embedded in sent campaigns;
   - possibly unexpired `ApplicationDraft` rows.

   `reset_admissions_data` was "built but intentionally never run" (`02-stack-and-schema.md:195-205`), so test rows sit alongside the real ones, and draft `data` JSON can hold child health answers. **Slice 15 starts with an inventory Eyram runs.**
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

- **13 frontend call sites pick "the" branch with `.from("branches").select(...).limit(1).single()` and no `order by`.** They're in `frontend/src/data/` (`payroll-store.ts:329`, `employees-store.ts:297`, `expenses-store.ts:91`, `invoice-store.ts:130`, `pos-store.ts:167`, `customer-store.ts:60`, `inventory-store.ts:122`, `end-of-day-store.ts:149`, `purchasing-store.ts:176`, `suppliers-store.ts:65`, `pro-forma-store.ts:93`, `held-sales-store.ts:127`, `branch-store.ts:32`). The plan first counted 14. The 14th, `inventory-store.ts:197`, is `setDefaultThreshold`'s `branches` UPDATE keyed by the id from `:122`, not a lookup, so fixing `:122` fixes it. Re-verified against HEAD `bd5e9ec` on 2026-09-29. Once a second branch row exists, which branch payroll, expenses and invoices write to is undefined. The unique key `payroll_runs (branch_id, month, year)` (`20260908070000_payroll_schema.sql:183`) could then split a month's run across campuses. The database side already picks deterministically: `handle_new_staff_signup` and `post_journal_entry` use `order by created_at limit 1`. **Slice 1 fixes this before any Annex row exists.**
- **No server functions and no Worker `env` access exist today.** There's no `createServerFn` or `*.server.ts` in `frontend/src`, and `frontend/src/server.ts` only wraps SSR errors. The only Edge Function is `supabase/functions/invite-staff` (CORS `*`, SMTP via nodemailer, `index.ts:42-83`). `supabase/config.toml` has no `[functions.*]` blocks. `pg_cron` and `pg_net` are available but not installed locally (`pg_available_extensions`).
- **Local and production branch names differ.** Locally the one branch is `Ho Main Branch` (id `…0001`, from `seed.sql`). `seed.production.sql` creates `Treasures Christian School`.

---

## Conventions for every slice

- **Rules live in the database.** Stage changes, reference numbers, gates, eligibility and capacity checks, token checks, the Annex and vaccination rules, and duplicate matching are all RPCs, triggers, constraints or RLS. React only displays what comes back.
- **Real record contents never appear** in docs, the journal, commits, fixtures, role-matrix probes or chat. Fixtures are invented; the seeded demo payroll people in `seed.sql` are fine because they're dummy data. The ~3 real TCS OS records hold child health data.
- **Tables have select-only RLS for staff and no write grant; writes go through their own SECURITY DEFINER RPC.** This follows the "Financial records" convention in DESIGN.md, applied to admissions because stage and decision history must be un-forgeable.
- Every new invoker RPC runs `revoke execute … from public, anon`, and every new table has explicit grants. `auto_expose_new_tables` is off.
- Every anon-reachable function is `security definer`, pins `search_path`, and validates its own token or size input. Anything that must trust a Turnstile result is **not** anon-executable at all (see "Bot check and email placement").
- Every slice adds a role-matrix probe file at `supabase/role-matrix/<migration>.sql`.
- **Six-column matrices from slice 1b on.** Slices 1b and 2 have all six columns. Slices 3 to 6 have an AO column and fold Attendant and Accountant (✗ throughout) into a note under each table. The tables in slices 7b to 14 predate the fifth role, so each of those slices' planner passes adds an Admissions Officer column. The officer is ✗ on every service-role-only function, gets the same result as anon on token-gated anon functions, and follows the roles and capabilities matrix for staff reads and writes. Attendant and Accountant are ✗ on all admissions data.
- **Capability variants are separate probes.** `scripts/role-matrix.sh` impersonates exactly one staff account per role, so each capability variant (with or without `can_decide`, in or out of band, with or without health) gets its own probe. The probe's postgres setup section grants or revokes the capability on that role's dev account.
- **Service-role-only functions** are asserted with `-- expect: none` (every JWT role denied). Their positive path is tested separately as `service_role`, in a rolled-back psql transaction.
- Every slice ends at the loop's step 7: stop for Eyram's review and don't start the next slice. Docs are updated in the same slice: DESIGN.md gets any new convention, and JOURNAL.md always gets an entry.
- Production steps (`db push`, `functions deploy`, `secrets set`, `wrangler deploy`, DNS, Cloudflare dashboard changes, the hand migration) are Eyram's. A slice hands over the exact command and never runs it.

## Recommended shapes the slices build on (each needs Eyram's confirmation)

**Admissions grade reference (slice 2).** One table, `admissions_grades`, replaces TCS OS's hand-kept `STUDENT_ID_CLASSIFICATION` and the `GRADE_BANDS` derived from it (`models.py:24-52`), so the two can't drift apart. Columns: `name`, `position`, `classification_code` (`01`–`04`, null for none), `band` (`preschool` | `primary` | `jhs` | null), `is_preschool_vaccination_required`, `is_active`.

It's seeded in the migration because it's entity-wide reference data. The seed is the 14 TCS OS grades: Pre Nursery, Nursery 1, Nursery 2 and KG 1–2 are preschool (codes `01` and `02`); Grades 1–6 are primary (`03`); Grades 7–9 are JHS (`04`). **No SHS rows get a code**, following the `TODO(SHS)` at `models.py:16-23`. `applications.year_group_applied_for` stays `text`, so free-text "Other" grades still round-trip and resolve to no band. That's the same pattern as `employees.position`.

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

**Delivers:** `supabase/role-matrix/payroll-regression.sql`, a probe file run by `scripts/role-matrix.sh`.

- Each probe's postgres setup inserts an invented employee, an `Active` `employee_pay_config` (basic salary and `pays_*` flags) and a `Draft` `payroll_runs` row on the seeded branch.
- The role section calls `create_payslip(p_payroll_run_id, p_employee_id, p_overtime_hours, p_overtime_rate, p_allowances jsonb, p_fines, p_iou)` and raises on any field that doesn't match (`gross_salary`, `ssnit`, `tier2`, `taxable_income`, `tax`, `ssnit_employer`, `total_deductions`, `net_pay`).
- Every probe carries `-- expect: Manager,Accountant`. That proves the finance-writer gate and the figures at the same time. A wrong figure shows up as a `denied!` mismatch for Manager, with the assertion message.
- Current signature: `20260909130000_employees_and_approval_workflow.sql:379`, grants at `:552-553`.
- Only the fully-specified cases become assertions now. Every other case is written as a **commented-out** probe marked `-- PENDING CONFIRMATION`. See the section "Slice 0 detail".

**Not included:** no code or schema change to payroll, no new statutory numbers in the database, and nothing about overtime concessionary rates or bonus tax.

**TCS OS files to read:** `docs/DESIGN.md:140-155`; `docs/JOURNAL.md:638-700, 878-919`; `docs/CONSTRAINTS.md:50-75`; `backend/modules/hr/tests.py:74-212`; `backend/modules/hr/payroll.py:70-80`; `backend/modules/hr/management/commands/run_parity_test_payroll.py:55-67`; `seed_parity_test_employees.py:40-50`.

**DESIGN.md conventions:** computed-never-stored (don't store expected values in tables); effective-dated config (the probe's run month must fall inside the pay config's and `statutory_rates`' effective range; live rates are effective 2025-01-01); flexible allowances (`allowance_types.taxable`); overtime kept out of allowances; per-employee exemption flags; mutation window (Draft only).

**Role matrix:** every `create_payslip` probe gives Manager ✓, Accountant ✓, Attendant ✗, Auditor ✗, anon ✗. Capability variants don't apply.

**Anon surface:** none.

**Decisions for Eyram:**

- **D-0a.** Confirm Abena Konadu Owusu's and Yaw Darko Asamoah's full figures. The source only records basic salary plus "matched to the cent". Recommendation: Eyram reads those two payslips from the hosted ERP's posted September 2026 test run (a read-only SELECT, Eyram's step), and slice 0 asserts those exact rows.
- **D-0b.** Confirm the expected values for each coverage-gap case with TCS's accountant before it's uncommented. This is the statutory gate.
- **D-0c.** Whether to import TCS OS's own hand-computed flag-independence cases as a separate "TCS OS hand-computed, not ERP-confirmed" tier. Recommendation: yes, clearly labelled.

**Size:** one probe file and no schema. It exercises one existing RPC. Well within one pass.

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

## Slice 1b — Admissions Officer role

Added 2026-09-29 by Eyram's decision to create a fifth role (see "Decisions recorded"). It ships before any admissions table, so the role exists, and is proven to reach nothing, before it's given anything.

**Delivers:**

- **`staff.role` check constraint:** add `'Admissions Officer'` to `staff_role_check` (currently `Attendant`, `Manager`, `Accountant`, `Auditor`). Use drop-and-recreate in a new migration.
- **Write guards become allowlists (D-1b-a, decided).** Today they're denylists, so a new role would inherit store write access automatically:
  - `can_write()` is currently `is_active_staff() and not has_role(['Accountant','Auditor'])`. It becomes `has_role(['Manager','Attendant'])`, the same meaning for the existing four roles. Without this change an Admissions Officer passes `can_write()` and gets INSERT/UPDATE on the 19 store tables listed below.
  - `require_writable_role()` currently rejects only Auditor. It becomes an allowlist of `Manager`, `Attendant` and `Accountant`, same meaning for the existing roles, plus an explicit rejection message for Admissions Officer. 28 RPCs call it (list below). The invoker ones then fall through to table RLS, which is now an allowlist too. The definer ones (`create_bank_account`, `void_invoice`, `void_sale`) already carry their own `has_role` allowlist.
  - Re-read every `has_role(...)` array in migrations and confirm none uses a negation. The live audit found none.
- **Read-exposure fixes (D-1b-b, decided)** (see the audit table below):
  - The `is_active_staff()` read policies on store tables and on `business_settings` switch to an allowlist predicate, `can_read_store()` = `has_role(['Manager','Attendant','Accountant','Auditor'])`.
  - `branches` keeps `is_active_staff()`, so the officer can read it for the campus picker.
  - The `staff` select policy moves to the same four-role allowlist.
  - A narrow SECURITY DEFINER function, `list_staff_names()`, returns only `id` and `name` of active staff, for note authors and the like. It's executable by `authenticated` and revoked from `anon`.
  - `compute_day_totals` gets a role allowlist.
- **`supabase/functions/invite-staff/index.ts`:** add the role to `ALLOWED_ROLES`.
- **`handle_new_staff_signup`:** confirm it passes the invited role through without defaulting or rejecting the new value, and add it where roles are enumerated.
- **Frontend:**
  - the role type (the TypeScript union, and the regenerated `database.types.ts` if the check is surfaced);
  - the Settings → Staff role dropdown;
  - sidebar and route gating, so an Admissions Officer sees only the Admissions section (empty until slice 7a) and Settings pages they're allowed, never store, finance, payroll or HR;
  - any role-name `switch` or map (grep for `"Attendant"`).
- **`scripts/seed-local-dev-staff.sh`:** a fifth dev account, `dev-admissions@tcs.test`, role Admissions Officer. Update CLAUDE.md's dev-accounts table too.
- **`scripts/role-matrix.sh`:** six roles (anon, Attendant, Manager, Accountant, Auditor, Admissions Officer), with column width adjusted for the longer name. Update its header and `-- expect:` docs.
- **Probe file:** `supabase/role-matrix/<migration>_admissions_officer_role.sql` proves the new role is **denied** on:
  - finance: `accounts`, `journal_entries`, `expenses`, `bank_accounts`;
  - payroll: `payroll_runs`, `payslips`, `employee_pay_config`, `create_payslip`;
  - HR: `employees`, `employee_documents`, onboarding tables;
  - store: `sales`, `invoices`, `customers`, `products`, `stock_movements`, `create_sale`, `create_invoice`, `create_customer_deposit`, `adjust_product_stock`;
  - storage: the `receipts`, `onboarding-documents` and `employee-generated-documents` buckets.

  Each denial is a seeded read that must raise as "no rows visible", or a write that must fail. It also re-runs the existing guard probes to prove the four existing roles are unchanged.
- **DESIGN.md:** the role list gains Admissions Officer, and the guard predicates are documented as allowlists.

**Not included:** any admissions table or capability (slice 2 onward). The role has no admissions data to see until slice 3.

**Read exposure today: what a new role would reach through `is_active_staff()` and friends.** This is the live audit of the local DB (`pg_policies`, `pg_proc`), 2026-09-29.

| Mechanism | Tables or functions a new active role would reach today | After slice 1b (recommended) |
|---|---|---|
| `is_active_staff()` SELECT policies (24 tables) | `branches`, `business_settings`, `customer_deposits`, `customer_discounts`, `customers`, `day_closes`, `deposit_number_counters`, `held_sales`, `invoice_lines`, `invoice_number_counters`, `invoice_payments`, `invoices`, `manager_overrides`, `pro_forma_invoice_lines`, `pro_forma_invoice_number_counters`, `pro_forma_invoices`, `products`, `sale_lines`, `sale_number_counters`, `sale_payments`, `sale_returns`, `sales`, `staff`, `stock_movements` | Store tables and `business_settings` move to `can_read_store()`. `staff` moves to the same allowlist, and officers get names via `list_staff_names()`. `branches` stays `is_active_staff()` (D-1b-b). |
| `can_write()` INSERT/UPDATE/DELETE policies (19 tables) | `branches`, `customer_deposits`, `customers`, `deposit_number_counters`, `held_sales`, `invoice_lines`, `invoice_number_counters`, `invoice_payments`, `invoices`, `pro_forma_invoice_lines`, `pro_forma_invoice_number_counters`, `pro_forma_invoices`, `products`, `sale_lines`, `sale_number_counters`, `sale_payments`, `sale_returns`, `sales`, `stock_movements` | Denied (allowlist). |
| RPCs guarded by `require_writable_role()` (28) | `adjust_product_stock`, `cancel_bank_reconciliation`, `cancel_customer_deposit`, `cancel_purchase_order`, `clear_statement_line`, `complete_bank_reconciliation`, `convert_pro_forma_to_invoice`, `create_bank_account`, `create_customer_deposit`, `create_customer_discount`, `create_invoice`, `create_pro_forma_invoice`, `create_purchase_order`, `create_sale`, `create_sale_return`, `create_sale_return_batch`, `create_supplier`, `import_bank_statement_lines`, `match_statement_line`, `place_purchase_order`, `receive_purchase_order`, `record_invoice_payment`, `record_supplier_payment`, `start_bank_reconciliation`, `unmatch_statement_line`, `update_invoice`, `void_invoice`, `void_sale`. Of these, 8 have no `has_role` of their own (`adjust_product_stock`, `convert_pro_forma_to_invoice`, `create_customer_deposit`, `create_invoice`, `create_pro_forma_invoice`, `create_sale_return_batch`, `record_invoice_payment`, `update_invoice`), all invoker, so today only table RLS (`can_write()`) stops them. | Rejected at the guard. |
| Staff-only definer function | `compute_day_totals` (SECURITY DEFINER, guarded only by `require_staff`/`is_active_staff`, so it bypasses sales RLS) | Add a role allowlist. |
| Own-row policy | `notifications` (`recipient_id = auth.uid()`) | Unchanged; harmless. |
| `has_role([...])` allowlists | every finance, payroll, HR and onboarding table and every storage bucket policy | Already excluded. Nothing to change. |

**TCS OS files to read:** `docs/admissions/02-stack-and-schema.md:804-911` (the coordinator permission bundle the role replaces); `migrations/0017_administration_group.py`, `0019_coordinator_groups.py`.

**DESIGN.md conventions:** the RLS role model (this slice rewrites its predicates); explicit grants; `drop function` before changing an argument list (the predicates keep their signatures); identity columns unchanged.

**Role matrix:** six columns. Every existing guard probe keeps its current result for the four existing roles, and Admissions Officer is ✗ on every finance, payroll, HR and store probe. anon is ✗ everywhere.

**Anon surface:** none.

**Decisions (all decided 2026-09-29, as recommended):**

- **D-1b-a.** Allowlist guards, not added deny arrays, which would repeat the same trap for every future role.
- **D-1b-b.** The officer reads `branches`, and reads staff names only through `list_staff_names()`. No `business_settings`, no store tables.
- **D-1b-c.** Auditor reads admissions read-only; health only if granted.
- **D-1b-d.** The role string is `Admissions Officer`.

Nothing is open before this slice starts.

**Size:** one migration (check constraint, three predicates, about 24 policy swaps, one function), one Edge Function edit, a frontend role-type, dropdown and sidebar pass, and two script edits with about 25 probes. It's big but mechanical. If it overruns, split it: 1b-i (allowlist guards and probes, with no new role yet, so no behaviour change for the four existing roles) then 1b-ii (add the role).

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

**Size:** one migration of 2 tables, 4 functions and 2 triggers, one small Settings panel, and about 20 probes.

## Slice 3 — Core admissions schema and staff RLS (no health, no documents)

**Delivers:** one migration with these tables:

- `families`: `referral_source` (check-constrained to TCS OS's 8 values, `models.py:122-131`), `referral_source_other`, `comments`.
- `guardians`: `family_id`, `first_name`, `surname`, `email` (lowercased by trigger, following DESIGN's uppercase/lowercase normalisation), `phone`, `relationship`, `religion`, `address`, `town_city`, `bulk_email_unsubscribe_token_hash` (unique, nullable until slice 14), `bulk_email_unsubscribed_at`.
- `students`: `family_id`, `full_name`, `date_of_birth`, `gender`, `nationality`, address block, `current_school`, `previous_school_location`, `current_grade`, and `student_id` (unique, null until enrolment, assigned in slice 6).
- `applications`: `student_id`, `stage`, `academic_year`, `year_group_applied_for`, `month_of_enrollment`, `inquiry_reference` and `application_reference` (unique), `branch_id` (nullable: inquiries carry no campus), scholarship fields, declaration fields (`declaration_agreed_at` and `declaration_ip` server-set), `media_consent_agreed`, timestamps.
- `application_emergency_contacts` and `application_notes` (`author_id` server-forced).
- `application_decisions` (one per application: `decision_type`, `decided_by`, `decided_at`, `notes`).
- `application_offers` (one per application: `token_hash` unique, `sent_at`, `expires_at`, `response`, `responded_at`).
- `admissions_capacity` (`academic_year`, `year_group`, `branch_id` nullable, `capacity`), with a unique index that treats NULL campus as equal. That fixes the gap TCS OS accepted at `models.py:514-541`.
- `admissions_campus_grade_rules`: `branch_id`, `grade`. When a campus has rows, it only accepts those grades. Seeded for Annex with Pre Nursery and Nursery 1 (the rule from `serializers.py:18`), keyed by `branch_id`, not by name, which removes TCS OS's rename fragility noted at `02-stack-and-schema.md:476-480`.

Select RLS on every table goes through `admissions_grade_visible(year_group_applied_for)`, joined up from family, guardian and student. There are no write grants and no write RPCs yet; setup seeds rows as postgres.

**Not included:** health info, documents, storage, numbering, stage RPCs, public anything.

**TCS OS files to read:** `models.py:118-541, 581-594, 656-666`; `serializers.py:14-31`; `docs/admissions/02-stack-and-schema.md:11-46, 467-530`.

**Conventions:** explicit grants; select-only tables with RPC-only writes; identity columns server-forced; nullable-override-with-global-default (capacity campus null means not campus-specific; campus grade rules default to "all grades"); `drop function` before changing an argument list, for later slices.

**Role matrix:** one read probe per table, with an application seeded at Grade 3 and one at Grade 11.

| Probe | anon | AO | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| Read Grade 3 application, no capability rows | ✗ | ✗ | ✓ | ✗ | ✓ |
| Read Grade 3, AO with `{primary}` | | ✓ | | | |
| Read Grade 3, AO with `{jhs}` | | ✗ | | | |
| Read Grade 3, AO with `all_grades` | | ✓ | | | |
| Read Grade 11 (unbanded) | ✗ | ✗ (even with all 3 bands); ✓ with `all_grades` | ✓ | ✗ | ✓ |
| Live move: update the grade Grade 6 → Grade 7 as postgres | | a `{primary}` AO loses it, a `{jhs}` AO gains it | | | |
| Direct insert, update or delete on any admissions table | ✗ | ✗ | ✗ | ✗ | ✗ |

The live-move probe mirrors `test_grade_change_moves_application_between_coordinators_live`.
Attendant and Accountant are ✗ on every probe in this table, because they have no admissions access (fifth-role decision, 2026-09-29). They stay in the file as regression rows. The AO column is the Admissions Officer.


**Anon surface:** none. No anon grants; `revoke all … from anon` on every new table.

**Decisions for Eyram:**

- **D-3a (decided 2026-09-29, as recommended).** Is `students` the long-term Student record? Recommendation: yes, a single `students` table. A child becomes a `students` row at inquiry or application (TCS OS shape, `serializers.py:111-124`) and gets `student_id` at enrolment, so the future Student Management phase extends this table instead of adding a second student model (PLANNING.md "Student Management").
- **D-3b (decided 2026-09-29, as recommended).** Is `academic_year` free text or constrained? Recommendation: text, picked from a list in the form. TCS OS has legacy free-text values (`02-stack-and-schema.md:631`).
- **D-3c.** Who sees capacity rows. Recommendation: every staff member who sees admissions; writes are Manager only (slice 7b).

**Size:** one migration with about 11 tables and select policies only, no RPCs. Mechanical but long. If the fix rounds run over, split into 3a (families, guardians, students, applications) and 3b (decisions, offers, capacity, rules).

## Slice 4 — Health info, documents metadata, private bucket

**Delivers:**

- `application_health_info`: one per application, the three boolean-plus-details pairs from `models.py:596-617`. Select only when `admissions_grade_visible(...) and has_admissions_capability('health')`. It never joins into any list or search view, and never into export.
- `application_documents`: `application_id`, `document_type` (the 8 TCS OS values, `models.py:547-556`), `storage_path`, `status` (`required` | `pending_review` | `approved` | `rejected`), `uploaded_at`.
- A private bucket, `admissions-documents`: `public = false` from the insert, `file_size_limit` 10 MiB, `allowed_mime_types` `application/pdf`, `image/jpeg`, `image/png`. That's the TCS OS allow-list; HEIC is deliberately excluded (`02-stack-and-schema.md:111-140`).
- A staff storage select policy that mirrors `application_documents` visibility. Reads go through `createSignedUrls()`.
- A staff read function for documents that returns metadata only.

**Not included:** uploads by anyone (slice 9), document review RPC (slice 5), health UI (slice 7a).

**TCS OS files to read:** `models.py:546-617`; `storage.py`; `admin.py:103-121, 177-205`; `management/commands/configure_storage_bucket.py`; `docs/admissions/02-stack-and-schema.md:95-140, 486-494, 873-875`.

**Conventions:** document storage applies the receipts-bucket lesson (private from the first commit, signed URLs, verified with a `404 Bucket not found` on `/object/public/`); explicit grants; the health gate is independent of role, `can_decide` and bands (CONSTRAINTS.md).

**Role matrix:**

| Probe | anon | AO | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| Health, Grade 1, no capability | ✗ | ✗ | ✗ | ✗ | ✗ |
| Health, Manager with `can_view_health` | | | ✓ | | |
| Health, Auditor with `can_view_health` | | | | | ✓ |
| Health, AO with `{preschool}` and health, Nursery 1 app | | ✓ | | | |
| Health, AO with `{preschool}` and health, Grade 3 app | | ✗ | | | |
| Health, AO with `{primary}` but no health, Grade 3 app | | ✗ | | | |
| Health, Attendant or Accountant with `can_view_health` | | | | ✗ (sees no admissions rows) | |
| Documents read | ✗ | in scope | ✓ | ✗ | ✓ |
| Storage object read | ✗ | in scope | ✓ | ✗ | ✓ |
| Any storage insert | ✗ | ✗ | ✗ | ✗ | ✗ |

The health rows after the first are capability variants.
Attendant and Accountant are ✗ on every probe in this table, because they have no admissions access (fifth-role decision, 2026-09-29). They stay in the file as regression rows. The AO column is the Admissions Officer.


**Anon surface:** none. No anon storage policy.

**Decisions for Eyram:**

- **D-4a.** Health-gate shape. Recommendation: a boolean capability intersected with band scope (TCS OS "Option B", `02-stack-and-schema.md:873-875`).
- **D-4b.** Who holds the health gate at go-live. Recommendation: Eyram's own Manager account plus the three band coordinators, if TCS confirms them. Everything starts ungranted.
- **D-4c.** Is a health read audited (who viewed which child's health info)? Recommendation: not in Phase 2, since audit_log is reserved for state transitions. Revisit if TCS's data-protection obligations require it.
- **D-4d.** Retention of health data. Recommendation:
  - keep it for enrolled students (it moves to Student Management later);
  - delete health info, draft `data` and documents for applications that end `rejected`, `offer_declined` or withdrawn after a set period (proposal: 12 months), using a Manager-run purge RPC;
  - Eyram checks Ghana's Data Protection Act 2012 (Act 843) obligations with TCS before fixing the period.

  The purge itself is a later slice.

**Size:** two tables, a bucket, two storage policies, about 12 probes.

## Slice 5 — Reference numbering, stage transitions, notes and document review

**Delivers:**

- `admissions_reference_counters` (`key` PK, `next_value`): RLS on, no anon grant, no `authenticated` write grant, touched only by SECURITY DEFINER functions. This learns from the `deposit_number_counters` gap.
- `_next_admissions_reference(key)` runs under a row lock, the equivalent of TCS OS's `select_for_update`.
- Formats, from `models.py:65-75` and `02-stack-and-schema.md:161-174`:
  - `INQ-YYYY-NNNN`, assigned when an application row is created at `inquiry`.
  - `APP-YYYY-NNNN`, assigned the first time the stage reaches any value in `STAGES_REQUIRING_APPLICATION_REFERENCE` (`models.py:251-255`).
  - YYYY is the year at the moment of assignment. Sequences reset per year. Each number is assigned once, guarded by "still null", and never reassigned.
- A BEFORE INSERT OR UPDATE trigger on `applications` assigns both references. It's the equivalent of `Application.save()`, and it fires on every write path.
- Stage RPCs:
  - `move_application_to_document_review(p_application_id)`: Manager, or an Admissions Officer with the application in scope. Allowed only from `inquiry` or `application`, re-checked under `select … for update` (`models.py:354-390`).
  - `set_application_stage(p_application_id, p_stage)`: Manager only; TCS OS's unrestricted `mark_as_*` (`admin.py:309-343`). It refuses `offer` and `enrolled`, which are only reachable through slice 6's RPCs, and refuses leaving `enrolled`.
- Notes: `add_application_note` (Manager or in-scope Admissions Officer) and `update_application_note` (author only, same audience). No delete, matching coordinator groups having no `delete_note`.
- Documents: `set_application_document_status(p_document_id, p_status)` (Manager or in-scope Admissions Officer).
- An audit trigger: stage transitions become audit_log action `application_stage_changed`.

**Not included:** decisions, offers, enrolment and `student_id` (slice 6), UI (slice 7a).

**TCS OS files to read:** `models.py:55-116, 229-390`; `tcs_os/reference_counter.py`; `admin.py:208-254, 309-382`; `tests.py:1022-1095`; `docs/admissions/02-stack-and-schema.md:154-205, 854-871`.

**Conventions:** create-can't-overwrite; `drop function` before changing an argument list; computed-never-stored doesn't apply because references are identifiers, not derived values; audit_log is trigger-written for state transitions; the mutation window (no transition out of `enrolled`).

**Role matrix:**

| Probe | anon | AO | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `move_…_to_document_review`, Grade 3 | ✗ | ✓ only with `{primary}` or `all_grades` | ✓ | ✗ | ✗ |
| Same RPC from `rejected` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `set_application_stage(…,'waitlisted')` | ✗ | ✗ | ✓ | ✗ | ✗ |
| `set_application_stage(…,'offer')` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `add_application_note` | ✗ | in-band ✓ | ✓ | ✗ | ✗ |
| `update_application_note` (someone else's note) | ✗ | ✗ | ✗ | ✗ | ✗ |
| `set_application_document_status` | ✗ | in-band ✓ | ✓ | ✗ | ✗ |
| Direct write to the counters table | ✗ | ✗ | ✗ | ✗ | ✗ |

Attendant and Accountant are ✗ on every probe in this table (no admissions access).

Value probes, run as postgres setup plus assertion: the first inquiry insert gets `INQ-<year>-0001`; advancing it assigns `APP-<year>-0001` and keeps the INQ; a row created straight at `application` gets no INQ.

**Anon surface:** none.

**Decisions for Eyram:**

- **D-5a.** Confirm the formats are final. TCS OS records them as settled with TCS, "no legacy convention" (`02-stack-and-schema.md:156-159`). Recommendation: keep them verbatim, zero-padded to 4 digits (TCS OS doesn't say what happens past 9999).
- **D-5b.** May a Manager move an application *out* of a terminal stage, for example `rejected` back to `application`? TCS OS allows it for Administration. Recommendation: allow it for Manager except out of `enrolled`, and audit it.

**Size:** one counter table, one trigger, five RPCs, about 14 probes.

## Slice 6 — Decisions, offers, the enrolment gate, the capacity warning (staff side)

**Delivers:**

- `record_decision(p_application_id, p_decision_type, p_notes)` requires `can_decide`, the grade scope for an Admissions Officer, and a Manager or Admissions Officer role. It updates or inserts the single decision row through an explicit update path rather than an upsert.
  - A **negative** decision (`waitlisted` or `rejected`) sets the stage to match, unless the stage is `enrolled` (`models.py:418-445`).
  - `accepted` never moves the stage.
  - It returns `{capacity_warning: text | null}`. The warning appears when `accepted` and a capacity row exists for (year, grade, campus) and the count of `accepted` decisions for that key exceeds capacity. It never blocks (`admin.py:273-307`).
- `generate_offer(p_application_id)` requires `can_decide`. In one transaction:
  1. require an accepted decision (the gate checks `decision_type`, not current stage, so waitlisted → accepted → offer works, `02-stack-and-schema.md:241-250`);
  2. mint a new 32-byte token and store only its SHA-256 hash (the onboarding pattern);
  3. set `sent_at` to now and `expires_at` to now plus the offer TTL (D-6a), with `response = 'pending'`;
  4. set the stage to `offer`;
  5. return the raw token once. Staff can copy the link, reveal-once as in onboarding, until slice 12 emails it.
- `reset_offer(p_application_id)` requires `can_decide` and mints a **new** token, killing the old link (D-6b).
- `_settle_offer_expiry(offer_id)`: if `pending` and `now() > expires_at`, set `expired`, then apply the negative propagation (stage `offer` becomes `offer_declined`, `models.py:484-511`). Every RPC that reads or acts on an offer calls it.
- Staff read functions expose `effective_response`, computed as expired when pending and past expiry, so a display is never stale even before the settle runs.
- `mark_enrolled(p_application_id)` is Manager only. Gate: an accepted decision and an accepted offer, after settling expiry (`models.py:306-320`). Then assign `students.student_id` = `YY` + `PP` (classification code from `admissions_grades`, by the grade applied for) + `NNNN`, from counter key `STUDENT-YY-PP`, once per student. If the grade has no code (SHS or free text), **leave it null** and return a warning (`models.py:93-116`).
- Capacity CRUD RPCs, Manager only.
- An audit trigger for decisions and offers.

**Not included:** the parent-facing respond flow (slice 11), the offer email (slice 12).

**TCS OS files to read:** `models.py:300-352, 392-541`; `admin.py:129-170, 256-307, 384-433`; `docs/admissions/02-stack-and-schema.md:207-328`; settings `OFFER_EXPIRY_DAYS` (`tcs_os/settings.py:458`).

**Conventions:** create-can't-overwrite (decision update is explicit); the onboarding token pattern (CSPRNG, hash-only, reveal-once, expiry checked on every use, single-use under a row lock); mutation window; audit via triggers; computed-never-stored for `effective_response`.

**Role matrix:**

| Probe | anon | AO | Mgr | Acc | Aud |
|---|---|---|---|---|---|
| `record_decision`, no capability | ✗ | ✗ | ✗ | ✗ | ✗ |
| Same, with `can_decide` on that role | | ✓ if in scope | ✓ | ✗ (grant refused) | ✗ (grant refused) |
| `generate_offer` without an accepted decision | ✗ | ✗ | ✗ | ✗ | ✗ |
| `generate_offer` with an accepted decision, with `can_decide` | | in scope ✓ | ✓ | | |
| `mark_enrolled`, offer pending | ✗ | ✗ | ✗ | ✗ | ✗ |
| `mark_enrolled`, offer accepted | ✗ | ✗ | ✓ | ✗ | ✗ |
| `mark_enrolled`, accepted but past expiry | ✗ for everyone | | | | |
| Capacity write | ✗ | ✗ | ✓ | ✗ | ✗ |

Attendant and Accountant are ✗ on every probe in this table.

The expired case asserts the settle marks the offer `expired` and the stage `offer_declined`, even though the transaction is rolled back. Value probes: the student ID format; the Grade 10 case leaves it null; the capacity warning text appears once the count exceeds capacity and not at equality.

**Anon surface:** none.

**Decisions for Eyram:**

- **D-6a.** Offer TTL. Recommendation: 14 days, TCS OS's default. Eyram checks the live `OFFER_EXPIRY_DAYS` env value on Cloud Run. Store it as an admissions setting row, not a constant.
- **D-6b.** Re-offer. Recommendation: always a new token. TCS OS reuses the old one.
- **D-6c.** Capacity count basis. TCS OS counts **all** accepted decisions, including applications later `offer_declined`. Recommendation: exclude `offer_declined` and count the rest, and flag it as a deliberate change from TCS OS. Or keep TCS OS parity.
- **D-6d.** Is `mark_enrolled` Manager only? Recommendation: yes. It matches TCS OS hiding `mark_as_enrolled` from coordinators.

**Size:** about six RPCs, one helper, one trigger, about 16 probes. This is the densest backend slice. If it overruns, split 6a (decisions and capacity) from 6b (offers and enrolment).

## Slice 7a — Staff pipeline UI: list, detail, notes, documents, health panel

**Delivers:**

- `routes/admissions.index.tsx`: a list filterable by stage, campus, academic year and grade. Search by student name and references, never by health data.
- `routes/admissions.$applicationId.tsx`: family, guardians, student, emergency contact, notes (add and edit), documents (signed-URL view and status change), and a health panel that renders **only** when the health read returns a row.
- A "Move to Document Review" action.
- An "Admissions" sidebar section (DESIGN.md sidebar convention).
- `data/admissions-store.ts` makes RPC and select calls only.

**Not included:** decision, offer and enrolment actions (7b), public pages.

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
- Mark enrolled, showing a missing-student-ID warning.
- Settings → Admissions: the capacity table and the campus grade rules (read-only display).
- Wiring the slice 2 capabilities panel into the staff list.

**Not included:** email.

**TCS OS files to read:** `admin.py:384-433, 480-491`.

**Conventions:** as for 7a.

**Role matrix:** none new.

**Anon surface:** none.

**Decisions for Eyram:** none new beyond D-6*.

**Size:** UI only, over existing RPCs.

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

- `application_drafts`: `token_hash` unique, `email`, `data jsonb` (the same shape as the slice 9 payload, so the TCS OS drafts migrated in slice 15 resume), `current_step`, `expires_at` (D-10a), `submitted_application_id`, `save_count_window`, `resume_emails_sent_today`.
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

- `get_offer_context(p_token)` is **anon**, SECURITY DEFINER. It settles expiry first and returns only student first name, grade, campus name, `expires_at` and `response`.
- `admissions-public` action `offer_respond`: Turnstile (TCS OS gates this, `views.py:268-270`), then service-role `respond_to_offer(p_token, p_response)`:
  1. lock `for update`;
  2. settle expiry;
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

## Slice 15 — Hand migration, cutover, domain, TCS OS shutdown

**Delivers:**

- A reviewed, hand-run migration script. It's not a migration file, and not part of `seed*.sql`.
- The Worker host routing for `admissions.tcsch.edu.gh`, with the legacy-path table under "Links already sent" and `410 Gone` for dead TCS OS endpoints.
- Counter seeding.
- The runbook below (see "Cutover runbook").
- **Parity sign-off.**

**TCS OS files to read:** `docs/deployment.md` (whole); `management/commands/reset_admissions_data.py` (for the table list); `models.py` (every field to map); `docs/admissions/02-stack-and-schema.md` (whole).

**Conventions:** data safety (never connect the ERP to TCS OS's project, and no shared connection string: the export and import are two separate, hand-run steps); real contents never in any repo file; production steps are Eyram's.

**Role matrix:** re-run every admissions probe file against the local stack as a final regression. No new functions.

**Anon surface:** adds only the Worker's legacy-host routing (redirects, the unsubscribe proxy, and the slice 13 lead paths if D-13a). **Confirmation gate.**

**Decisions for Eyram:** D-15a through D-15f in the consolidated list.

**Size:** one Worker routing change and a written runbook. The migration script is Eyram-reviewed and Eyram-run.

---

## Links already sent to parents: how they keep resolving

### Exact TCS OS URL shapes, token formats and lifetimes

| Link | URL in the email | Called by the page | Token | Lifetime |
|---|---|---|---|---|
| Offer accept/decline | `{FRONTEND_BASE_URL}/offer?token=<t>` (`emails.py:361`) | `POST /api/admissions/offers/<t>/respond/` (`admissions/urls.py:14`, `templates/public/offer.html:202-234`) | `secrets.token_urlsafe(32)`, 43 base64url characters, **stored in plaintext**, unique (`models.py:77-78, 465`) | `OFFER_EXPIRY_DAYS`, default 14 (`settings.py:458`), from generation or reset. **Lazy** expiry (`models.py:474-482`). Reset reuses the token (`admin.py:417-433`). |
| Draft resume | `{FRONTEND_BASE_URL}/apply?draft_token=<t>` (`emails.py:203`) | `GET` and `PATCH /api/admissions/application-drafts/<t>/`; `POST …/<t>/submit/` (`urls.py:15-21`, `apply.html:1872-1960`) | Same format (`models.py:81-82, 633`) | `DRAFT_EXPIRY_DAYS`, default 30 (`settings.py:495`), fixed at creation, lazy (`models.py:648-650`). Dead once submitted. |
| Bulk-email unsubscribe | `{FRONTEND_BASE_URL}/api/admissions/unsubscribe/<t>/` in the body and in `List-Unsubscribe` with `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (`bulk_email.py:77-78, 248-249`) | GET renders the page; POST returns an empty 200 (`views.py:297-335`), CSRF-exempt | Same format, on `Guardian` and `Lead` (`models.py:169, 715`), eager, one shared space | **Permanent.** It never expires, and is idempotent. |
| PDF-gate email CTA | `{FRONTEND_BASE_URL}/inquiry` (`emails.py:422`) | — | none | permanent |

`FRONTEND_BASE_URL` in production is `https://admissions.tcsch.edu.gh`, per `settings.py:461-465` and `deployment.md`; Eyram confirms the env value. The root `/` redirects to `/inquiry` (`tcs_os/urls.py:19`).

### Options

1. **Migrate tokens with the records** (recommended for offers and unsubscribes; decide drafts from the inventory).
   - The migration script computes `encode(digest(<raw token>, 'sha256'), 'hex')` from TCS OS's plaintext column and inserts only the hash. The raw token never lands in the ERP database.
   - The ERP's token functions hash whatever string they're given, so 43-character legacy tokens work unchanged, provided no ERP function enforces a 64-hex format. **Constraint for slices 6, 10 and 14.**
   - `expires_at` and `response` copy verbatim, so lazy expiry carries on.
   - Unsubscribe hashes migrate for every Guardian and Lead that received any campaign, including rows otherwise considered test data, if their addresses are real (inventory).
2. **TCS OS keeps honouring tokens until they expire.** That conflicts with retiring TCS OS. It also breaks "no dual intake" for offers (a response is a state change) and for draft submit (which is intake). Unsubscribe tokens never expire, so TCS OS could never shut down. **Not recommended.**
3. **Redirect or serve on `admissions.tcsch.edu.gh`** (recommended, combined with option 1):
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
- **Offers.** Between "TCS OS intake stopped" and "DNS flipped", a parent can't respond. Keep that window short (hours), or extend pending offers' `expires_at` by the window length during migration (D-15c).
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
| D-0a | Full figures for Abena Konadu Owusu and Yaw Darko Asamoah | Eyram reads them from the hosted ERP's posted September 2026 test run (read-only). Assert those. |
| D-0b | Expected values for the payroll coverage-gap cases | Hand-computed, then confirmed by TCS's accountant before being uncommented (statutory gate). |
| D-0c | Import TCS OS's hand-computed flag and band cases | Yes, as a separately labelled tier. |
| D-0d | Statutory numbers to reconfirm | GRA "Year 2024" PAYE bands (the unchecked CONSTRAINTS item) and the SSNIT/Tier 2 split (0.5/13/5) against an official SSNIT source. Slice 0 asserts current behaviour, not correctness. |
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
| D-6a | Offer TTL | 14 days, as a setting; confirm the live Cloud Run value. |
| D-6b | Re-offer token | Always a new token. |
| D-6c | Capacity count basis | Exclude `offer_declined` (a deliberate change from TCS OS), or keep parity. |
| D-6d | `mark_enrolled` | Manager only. |
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
| D-15a | Token migration versus TCS OS honouring tokens | Migrate hashes of the verbatim tokens (offers, unsubscribes, and drafts if any are kept). Don't keep TCS OS alive for tokens. |
| D-15b | Redirect mapping | Attach `admissions.tcsch.edu.gh` to the ERP Worker. Serve identical public paths, 302 `/` and `/admin`, 410 everything else. |
| D-15c | Pending offers across the window | Extend `expires_at` by the window length during migration. |
| D-15d | Stopping TCS OS intake | A Cloudflare WAF rule blocking `POST /api/admissions/{inquiries,applications,upload-url,application-drafts,offers}*` (needs the record proxied), or a maintenance deploy of TCS OS by Eyram. |
| D-15e | DNS and cutover sequence | As in the runbook, including `app.tcsch.edu.gh` for the ERP staff host (confirm the ERP's production host). |
| D-15f | How long TCS OS stays read-only before shutdown | 30 days, covering one full draft TTL. Then delete the Cloud Run service, queues and secrets, and rotate or delete the TCS OS Resend key and Turnstile secret. |

## Slice 0 detail: reference payslip figures and coverage gaps

**Engine facts the probes depend on** (live `create_payslip`, from `pg_get_functiondef` and `20260909130000_employees_and_approval_workflow.sql:379`):

- SSNIT employee, SSNIT employer and Tier 2 are computed on **basic salary only**, each rounded to 2 decimal places and each gated on its `pays_*` flag.
- Taxable income = basic + overtime pay + taxable allowances − SSNIT − Tier 2, floored at 0.
- PAYE walks the latest `paye_bands` set **with per-band rounding**.
- Gross = basic + overtime + all allowances.
- Deductions = PAYE + Tier 2 + SSNIT + fines + IOU. Net = gross − deductions.
- Live rates (local database): `statutory_rates` 0.5 / 13 / 5 / 0, effective 2025-01-01.
- `paye_bands` (monthly), effective 2025-01-01:

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

**"Matched to the cent" only. The source records the basic salary, not the figures:**

| Case | Basic | Source | Status |
|---|---|---|---|
| Abena Konadu Owusu | 1,900.00 | `tcs-os/docs/JOURNAL.md:880-885` | Figures not recorded; `pays_*` flags not recorded |
| Yaw Darko Asamoah | 1,700.00 | same | same |

For reference only, **not to be asserted without D-0a**: if both pay all three deductions, the engine as it stands gives:

- Abena: SSNIT 9.50, Tier 2 95.00, taxable 1,795.50, PAYE 204.96, net 1,590.54, employer 247.00.
- Yaw: SSNIT 8.50, Tier 2 85.00, taxable 1,606.50, PAYE 171.89, net 1,434.61, employer 221.00.

These were derived by the planner, not sourced.

**TCS OS hand-computed cases (independent arithmetic, never ERP-confirmed)** (`hr/tests.py:116-195`):

| Case | PAYE | Net |
|---|---|---|
| 6,500, no SSNIT | 1,142.25 | 5,032.75 |
| 6,500, no Tier 2 | 1,215.38 | 5,252.12 |
| 6,500, no PAYE | 0.00 | 6,142.50 |
| 400, all on | 0.00 | 378.00 |

The 400 case has SSNIT 2.00 and Tier 2 20.00. These carry the D-0c label.

**Known coverage gaps.** Each becomes a commented probe with its inputs fixed and its expected values blank until D-0b.

| Gap | Probe inputs (invented employee) | What it checks | Open statutory question |
|---|---|---|---|
| Taxable allowance | basic 3,000 plus a 500 allowance whose type has `taxable = true` | gross includes it, taxable includes it, SSNIT and Tier 2 unchanged | none beyond the band table |
| Non-taxable allowance | basic 3,000 plus a 500 allowance with `taxable = false` | gross includes it, taxable excludes it | Which TCS allowances are genuinely non-taxable under GRA. All seeded types are `taxable = true`. |
| Mixed allowances | both of the above together | `total_allowances` versus the taxable subset | — |
| Overtime | basic 700 (a junior employee, 800/month or less), 10 h × 15 | `overtime_pay = hours × rate`, taxed graduated today | GRA's concessionary flat rate for qualifying junior employees (CONSTRAINTS "Statutory accuracy"): the expected value depends on the answer |
| Fines | basic 3,000, fines 100 | deducted after tax, no PAYE effect | — |
| IOU | basic 3,000, IOU 250 | deducted after tax | — |
| 30% band | basic 25,000 | band 6 walk | GRA table recheck (D-0d) |
| 35% band | basic 60,000 | band 7 walk; the 50,000 threshold follows GRA's literal label (CONSTRAINTS) | GRA table recheck |
| Band edges | taxable exactly 490.00, 730.00, 3,896.67 | per-band boundaries | — |
| All-exempt | 1,500 with every flag off (Kojo Boadu's seeded shape) | net = gross | whether National Service staff are fully exempt |
| Bonus | not modelled | flag only; no probe until the flat 5% treatment is decided | CONSTRAINTS "bonus income" |

**Harness.** One file, `supabase/role-matrix/payroll-regression.sql`, run by `./scripts/role-matrix.sh` after `./scripts/seed-local-dev-staff.sh`. Every probe runs in a rolled-back transaction.

- Setup, as postgres: insert an employee with `employment_status='Active'` on the Main branch, an `employee_pay_config` with `approval_status='Active'` and `effective_from` on or before the run month, and a `payroll_runs` row with `status='Draft'`. Probes that need allowances also insert `allowance_types`.
- Body: `select * into v from create_payslip(...)`, then `if v.net_pay <> 5008.37 then raise exception 'net_pay %', v.net_pay; end if;` for each field.
- Expect line: `-- expect: Manager,Accountant`.

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

1. **[E] Inventory TCS OS production (read-only SELECT counts).** Real versus test Families, Guardians, Students and Applications by stage; pending offers and their `expires_at`; unsubmitted unexpired drafts; Leads (consented and unsubscribed); Guardians and Leads that received campaigns; `ReferenceCounter` rows; `admissions-documents` object count. Also confirm the live migration level (0014 or 0019) and the env values `OFFER_EXPIRY_DAYS`, `DRAFT_EXPIRY_DAYS`, `FRONTEND_BASE_URL` and `ADMISSIONS_STAFF_EMAIL`. Record counts only, never contents.
2. **[E] Prepare the ERP.** `npx supabase db push`; enable `pg_cron` and `pg_net`; `npx supabase functions deploy admissions-public admissions-mailer`; `npx supabase secrets set TURNSTILE_SECRET_KEY=… RESEND_API_KEY=… MAILER_SHARED_SECRET=… PUBLIC_BASE_URL=…`; add the Vault secret; set `VITE_TURNSTILE_SITE_KEY` in the Cloudflare build env; `wrangler deploy`. Leave `admissions_settings.public_intake_open = false`.
3. **[E] Stop TCS OS intake** (D-15d). Block the creating POSTs. Leave unsubscribe and GET pages working. From this moment no new real record can appear in TCS OS.
4. **[E] Export** the in-scope rows from TCS OS to a local, access-restricted file. That's a hand SQL export against TCS OS's database, never a connection from the ERP. Include plaintext tokens only transiently, to hash them.
5. **[E] Import into the ERP** with the reviewed script:
   - map integer ids to uuids;
   - insert token **hashes** only;
   - copy `expires_at` and responses, and extend pending offers per D-15c;
   - copy references and `student_id` verbatim;
   - **seed `admissions_reference_counters` from TCS OS's `ReferenceCounter` next values**, not from max(migrated). Test records consumed numbers that may have been emailed.
   - Copy the Storage objects from `admissions-documents` in TCS OS to the ERP's `admissions-documents`. Keep the relative paths or rewrite them, and update `application_documents.storage_path` to match.
6. **[E] Verify** against TCS OS record by record (counts, references, stages, decisions, offer states, document count and bytes). Open each migrated document through a signed URL. Check that one migrated offer token and one unsubscribe token resolve through `get_offer_context` and `bulk_email_unsubscribe`, run in a rolled-back transaction.
7. **[E] Final unsubscribe re-sync.** Copy any `unsubscribed_at` set on TCS OS since step 4.
8. **[E] Set roles and grant capabilities** to the real staff (fifth-role decision, D-2g, D-4b) through Settings. **[E] Open intake:** set `public_intake_open = true`.
9. **[E] DNS.**
   - Remove the Cloud Run domain mapping for `admissions.tcsch.edu.gh`, and attach `admissions.tcsch.edu.gh` as a Worker custom domain.
   - Point `app.tcsch.edu.gh` at the ERP Worker, if that's the ERP staff host (D-15e).
   - Add both hosts to the Turnstile widget and to Supabase Auth `site_url` and `additional_redirect_urls` for the staff host.
   - Smoke-test the four legacy URL shapes, including `curl -X POST …/api/admissions/unsubscribe/<test-token>/` returning 200.
10. **[E] Keep TCS OS read-only** for N days (D-15f): Cloud Run still up behind its `*.run.app` URL, with intake blocked. It's only for reference; it gets no traffic after the DNS flip.
11. **[E] Shut down TCS OS:** delete the Cloud Run service, Cloud Tasks queues and Secret Manager secrets; rotate or delete the TCS OS Resend key and Turnstile secret; archive or delete TCS OS's Supabase project data per D-4d. Then update both repos' docs.

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
- **Don't run `pg_available_extensions` as proof of hosted support.** I only confirmed `pg_cron`, `pg_net`, `pgmq` and `http` are *available* locally. Whether they're enabled on the hosted project is for Eyram to check.
- **I didn't read `templates/public/apply.html` in full**, only the draft, upload and Turnstile regions. The exact draft `data` key shape comes from the fact that the draft submit feeds `draft.data` straight into `ApplicationSerializer` (`views.py`, `ApplicationDraftSubmitView`). If the form stores extra UI-only keys, slice 10's shape needs to tolerate them.
