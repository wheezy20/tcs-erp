# Admissions port plan (TCS OS → TCS ERP)

**Status:** slices 0 to 5, 6a, 6b and 7a built and committed (7a is de1aff9); 6a, 6b and 7a applied on hosted, and the 7a frontend deployed on 2026-10-12. Slice 7b split 2026-10-12: 7b1 (detail page actions, grade correction) committed as f04a336; 7b2 (admin screens) committed as bed38c9. Slice 7c is committed as 7a07d6a (built 2026-10-13). The 7b2 and 7c migrations are applied on hosted (reported 2026-10-14), and the 7b2 and 7c frontends are live (reported by Eyram, 2026-10-14). Slice 8 is committed (c71b363, 6842848) and slice 8b is committed (32eae11, c3943d8, 7d80735); their migrations are applied on hosted (reported by Eyram, 2026-10-14). Slice 8 and 9 planning decisions are recorded 2026-10-13. Slice 9 checkpoint 1 (the upload backend) is committed as c822b56, its migration `20261024100000` is applied on hosted, and `admissions-public` is deployed on hosted at version 3 (reported by Eyram, 2026-10-15). Slice 9 checkpoint 2 is committed as 92346dd and applied on hosted; Eyram reports slice 9a is built and live on hosted (reported by Eyram, 2026-10-15). Slice 9b checkpoint C1 (the look foundation and `/inquiry`) is committed as dffe810, deployed to hosted and checked by Eyram (reported by Eyram, 2026-10-15). Slice 9b checkpoint C2 (`/apply` in the six-step layout) is committed as 8393551. Slice 9b checkpoint C3 (`/apply` content) is committed as 14582d0, deployed to hosted together with C2, and checked on hosted by Eyram, including a second submission that produced the match panel (reported by Eyram, 2026-10-15). Slice 9b checkpoint C4 (the close-out: checklist, contract test, docs, go-live cleanup plan) is committed as 64a7e4a. Slice 12 (confirmation email and scheduled cleanup): C1 committed as a929511, C2 and C3 as 8a45e04. Its three migrations and the staff ID migration are applied on hosted, `admissions-worker` is deployed (version 1), the function secrets and the worker URL are set, and the frontend is deployed (reported by Eyram, 2026-10-20 and 2026-10-21); see "Slice 12 rollout reported". Slice 10 (application drafts, save and finish later) is built locally: C1 is committed as dcbff52, C2 as 3ec9468, and C3 is built and uncommitted. Nothing is on hosted (see "Slice 10 as built (local only)"). The rest is plan. Decisions recorded below; the rest are open.
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
| 7a | Staff pipeline UI: list, detail, notes, documents, health panel | applied on hosted, frontend deployed (2026-10-12) | 6b |
| 7b1 | Detail page actions: decision, offer, enrolment, grade correction | committed (f04a336) | 7a |
| 7b2 | Admin screens: academic years, capacity, offer expiry, campus rules | committed (bed38c9), migrations applied on hosted (reported 2026-10-14); frontend live and checked (reported by Eyram, 2026-10-14) | 7b1 |
| 7c | Read-only Audit Log (`/audit-log`) and Accountant audit narrowing | committed (7a07d6a), migrations applied on hosted (reported 2026-10-14); frontend live and checked (reported by Eyram, 2026-10-14) | 7b2 |
| 8 | Public request path (Edge Function, Turnstile, rate limits, intake flag) + public Inquiry form | committed (c71b363, 6842848), migrations applied on hosted (reported by Eyram, 2026-10-14) | 7b |
| 8b | Public enquiry form polish and two intake switches | committed (32eae11, c3943d8, 7d80735), migrations applied on hosted (reported by Eyram, 2026-10-14) | 8 |
| 9 | Public Application form: direct submit, uploads, matching, rules | 9a checkpoint 1 (upload backend) committed as c822b56; migration `20261024100000` applied on hosted and `admissions-public` deployed on hosted at version 3 (reported by Eyram, 2026-10-15). 9a checkpoint 2 committed as 92346dd and applied on hosted; Eyram reports slice 9a is built and live on hosted (reported by Eyram, 2026-10-15). 9b checkpoint C1 (look foundation and `/inquiry`) committed as dffe810, deployed to hosted and checked by Eyram (reported by Eyram, 2026-10-15); 9b checkpoint C2 (`/apply` six-step layout) committed as 8393551; 9b checkpoint C3 (`/apply` content) committed as 14582d0, deployed with C2 and checked on hosted by Eyram (reported by Eyram, 2026-10-15); C4 close-out written locally 2026-10-15, docs only, uncommitted (decided 2026-10-15; split into 9a and 9b on 2026-10-13) | 8 |
| 10 | Application drafts: save/resume tokens | built locally (C1, C2 committed; C3 uncommitted), not on hosted | 9 |
| 11 | Public offer response page | not started | 8, 6b |
| 12 | Transactional email (outbox, mailer, templates, resend-failed) | C1 committed (a929511), C2 and C3 committed (8a45e04). Migrations applied, `admissions-worker` deployed (version 1), secrets and worker URL set, frontend deployed, and a hosted test delivered both emails (reported by Eyram, 2026-10-20 and 2026-10-21). See "Slice 12 as built" and "Slice 12 rollout reported" | 8 (and 6, 9, 10 for the emails it sends) |
| 13 | Lead capture (marketing-site endpoints) | not started | 8, 12 |
| 14 | Bulk email + one-click unsubscribe | not started | 12, 13 |
| 15 | Cutover, domain, TCS OS shutdown (nothing is imported) | not started | all |

Slice 0 is independent of admissions and can run first or in parallel.

## Go-live gates still open

Every gate here must be closed before the step it names. Each one is also listed in its slice below.

- **Published privacy policy (decided 2026-10-15, slice 9b).** A privacy policy must be published before real admissions intake opens, and before admissions.tcsch.edu.gh moves to the ERP (slice 15). The policy is being written (reported by Eyram, 2026-10-15). When it exists, add one link in one place: the declaration copy constant. Until then the declaration is ported exactly as TCS OS has it, with no link. From slice 10 the policy must also describe saved applications (what is kept, 30 days after the last save and 60 days at most in all, and deletion from the emailed link); see CONSTRAINTS.md. Also a CONSTRAINTS.md checklist item.
- **Saved applications go-live checks (slice 10, added 2026-10-21).** Before real intake: Resend click and open tracking off for `mail.tcsch.edu.gh` (handover step 0); the consent wording reviewed (drafted, not yet decided); the privacy policy describes saved applications (above); the slice 10 hosted test run in the handover order; `PUBLIC_APPLY_BASE_URL` set to the origin that serves `/apply`. Also CONSTRAINTS.md checklist items.
- **Go-live test data cleanup.** Every test record on hosted must be removed before real intake opens. The plan is in "Go-live test data cleanup plan" below (written 2026-10-15, plan only, nothing run). The records known so far:
  - **"ZZ Test Do Not Process" (slice 8b).** One test inquiry on hosted.
  - **Live-test application (slice 9a, rollout step 4).** The application created by the D-9k live test. The test was done and checked out (reported by Eyram, 2026-10-15).
  - **Test enquiry from the 9b C1 rollout (reported by Eyram, 2026-10-15).** One test enquiry submitted while checking C1.
  - **Two test enquiries from the slice 12 hosted test (reported by Eyram, 2026-10-21),** with their outbox rows (a parent confirmation and a staff alert each).
  - **Test applications from the 9b C3 hosted check (reported by Eyram, 2026-10-15).** The check included a second submission that produced the match panel (family matched by guardian email, child matched by name and date of birth, differences listed, record unchanged), so it made at least two applications, with their documents and files. The second was a new application for a family already on record, not an inquiry advancing.
- **Stored declaration version (backlog, decided before go-live).** Q16 left declaration text versioning out of 9b. Before real intake, decide whether each application stores which declaration text the parent agreed to (for example a version key next to `declaration_agreed_at`), since the privacy policy link will change that text. See "Backlog from slice 9".
- **Confirmation email or written acceptance (slice 15).** admissions.tcsch.edu.gh does not move to the ERP until a confirmation email exists (slice 12) or Eyram accepts the gap in writing (gate of 2026-10-14). A confirmation email now exists on hosted: Eyram's hosted test delivered one (reported by Eyram, 2026-10-21). The slice 12 go-live checks below are still open.
- **Confirmation email go-live checks (slice 12).** Before real intake: confirm the live From address and verified domain in Resend (From stays `@mail.tcsch.edu.gh`); `ADMISSIONS_STAFF_EMAIL` is set (reported by Eyram, 2026-10-21; the TCS OS address is unknown and not copied); confirm `admissions@tcsch.edu.gh` is not on Resend's suppression list and that a test message reaches it quickly (added 2026-10-21, after the hosted test's first staff alert was suppressed); confirm by name that `net` is not in the hosted project's Exposed schemas (reported only as "2 of 2 schemas exposed"), because pg_net briefly holds the worker secret header in `net.http_request_queue`; SPF, DKIM and DMARC passed on the hosted test's parent email (reported by Eyram, 2026-10-21); check the bounce rate after the first real week; bump the reference counters only if TCS OS issued a real reference before its intake closed. Also a CONSTRAINTS.md checklist item.

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
- **O-8.** An Accountant reading capability changes via the existing `audit_log` policy is accepted. **Superseded 2026-10-13:** D-1b is now enforced on audit reads by slice 7c, so the Accountant no longer reads `admissions_capabilities_changed` rows.
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

**D-6g, answered 2026-10-12 (the open question is closed).** Eyram's answer: two digit calendar year of enrolment, then a two digit group code, then a four digit roll starting at 0001. The roll restarts per year and per group, so 26010001, 26020001 and 26030001 can all exist. The year is the year the student is enrolled in the system: a student accepted and enrolled in 2026 who starts school in 2027 keeps the 26 ID. Group codes: Pre Nursery to Nursery 2 is 01, KG 1 and 2 is 02, Primary 1 to 6 is 03, JHS 1 to 3 is 04.

Checked against the code on 2026-10-12, no change needed:

- `admissions_grades.classification_code` (seeded only in `20261005100000_admissions_grades_and_capabilities.sql`; no later migration and nothing in `seed.sql` or `seed.production.sql` changes it): Pre Nursery, Nursery 1 and Nursery 2 are 01; Kindergarten 1 and 2 are 02; Grade 1 to Grade 6 are 03; Grade 7 to Grade 9 are 04. That matches the answer if Kindergarten 1 and 2 are KG 1 and 2, Grade 1 to 6 are Primary 1 to 6, and Grade 7 to 9 are JHS 1 to 3. The system uses the TCS OS grade names; that the names correspond this way is a reading of the names, not something Eyram stated.
- The roll restarts per year and per group: `_next_admissions_student_id(p_code, p_year)` (`20261016100000_admissions_offers_enrolment.sql`) draws from the counter key `STUDENT-YY-PP` through `_next_admissions_sequence`, whose first value is 1, padded to four digits by `_admissions_sequence_text`.
- The year is the Accra calendar year at enrolment: `mark_enrolled` passes `_admissions_reference_year(clock_timestamp())`, which is `extract(year from p_at at time zone 'Africa/Accra')` (`20261014100000_admissions_numbering_stages_notes_documents.sql`). The academic year is not used.
- Not covered by the answer: past roll 9999, `_admissions_sequence_text` prints five digits, so the ID would be nine characters.

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

Slice 7a built 2026-10-12. Migrations applied on hosted and the frontend deployed on 2026-10-12. Evidence: Eyram's `npx supabase migration list` shows 20261017100000 and 20261017110000 on both Local and Remote.

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

## Slice 7b: Staff pipeline UI (decisions, offers, enrolment, grade correction, admin screens)

**Status:** split on 2026-10-12 into 7b1 and 7b2. 7b1 is committed as f04a336 and applied on hosted, with its frontend deployed (Eyram's migration list on 2026-10-12 showed `20261018100000` on both Local and Remote, and the push and the deploy both succeeded). 7b2 is committed as bed38c9; its migration is applied on hosted (reported 2026-10-14), and its frontend deploy is not confirmed.

### 7b1: Actions on the application detail page

**Delivers:**

- **Decision.** Record decision and Change decision dialogs (`record_decision`, `change_decision`).
  - A capacity warning is shown as a toast with the RPC's own text: figures for a Manager, none for an officer.
  - Shown only to staff whose live `has_admissions_capability('decide')` check returns true (D-2f). A Manager without it gets a plain message instead of a button.
- **Offer.** Generate offer, Reset offer, and Record response for an answer by phone or on paper (`generate_offer`, `reset_offer`, `record_offer_response`).
  - State comes from `application_offer_status` only.
  - The token is shown once, in component state only, as a plain-text link `<origin>/offer?token=<token>` with a Copy button. A warning says not to send it until slice 11.
- **Enrolment.** Mark enrolled (`mark_enrolled`, Manager only).
  - Every document that isn't approved is listed as a warning, not a gate.
  - The button is disabled with a plain reason when the grade has no band (D-6h).
  - The student ID is shown after success.
- **Grade correction.** `correct_application_grade(p_application_id uuid, p_grade_id uuid)`, Manager only, for an unrecognised grade only.
  - The order is role, scope, arguments, then the application lock with re-checks.
  - It is refused at enrolled, and when the campus grade rules (covering Annex) don't accept the new grade.
  - It is audited as `application_grade_corrected`.
- **Offers column grant.** `application_offers` select is a column-level grant without `token_hash` (D-6q reversed).
- **Audit list.** 35 to 37 values, including `admissions_academic_year_changed` for 7b2.
- **Demo rows** at decision, offer, offer declined and enrolled in `seed.sql`, plus one capacity row.

**Role matrix:** `20261018100000_admissions_grade_correction.sql` and `_structure.sql`.

**Anon surface:** none. The anon-executable count stays 169.

### 7b2: Admin screens at `/admissions/settings`

**Delivers:**

- Migration `20261018110000_admissions_academic_years_write.sql`:
  - `add_admissions_academic_year(p_label text)`: Manager only. Returns the new row. Label trimmed and validated as YYYY/YYYY consecutive years (same rule as the table CHECK). Database assigns `position` as max+1 under a share row exclusive table lock. Duplicates (active or retired, padded or not) refused with message "That academic year is already on the list".
  - `set_admissions_academic_year_active(p_label text, p_active boolean)`: Manager only. Retire or reactivate; no rename, no delete. Refuses unknown year, null flag, and no change.
  - Helper `_require_admissions_year_manager()` runs first, before any argument is read, so every non-Manager gets the same error message regardless of input.
  - Trigger `admissions_academic_years_audit` (after insert or update of `is_active`, signed-in actor only): fires `audit_admissions_academic_year()`, action `admissions_academic_year_changed`, entity_id is the label, branch is the actor's campus.
  - `create_admissions_capacity` (same signature as 6a, create or replace): now refuses a year not active on the list with message "The academic year must be an active year on the academic year list". Takes FOR SHARE on the year row so it cannot be retired between check and insert. Existing capacity rows for an unlisted or retired year are untouched and remain editable and deletable. Consequence: a new capacity year must match the list format, so the old 50-character free text case can no longer be created.
  - Grants: revoked from public and anon; the two RPCs granted to authenticated and service_role; helper and trigger function have no grant. Anon-executable count stays 169. No new table, policy or permission.
- Frontend: `/admissions/settings` (thin route `routes/admissions/settings.tsx` and full component `modules/admissions/components/settings-page.tsx`). Sidebar item "Admissions Settings" for Manager and Auditor. Sections: Academic years (list, add, retire, reactivate); Offer expiry (show and edit `offer_ttl_days` via `set_admissions_offer_ttl_days`); Capacity (list, add, change, delete via the three 6a RPCs; rows whose year is retired or not on the list are flagged but still editable and deletable; add offers only active years); Campus grade rules (read only). Manager writes; Auditor sees no write controls and a Read-only badge. Officer, Attendant and Accountant get the role-blocked panel (new extracted component `role-blocked-panel.tsx`, also used by `/admissions` layout) and nothing is queried. New pure rules: `canViewAdmissionsSettings` and `canEditAdmissionsSettings` in `permissions.ts`. New helpers: `yearStatus`, `capacityYearOptions`, `parseWholeNumber`, `campusGradeSummary` in `settings-rules.ts` with `settings-rules.test.ts`. New `data/settings.ts` (explicit column selects) and six mutation wrappers in `data/mutations.ts`. `database.types.ts` regenerated (additive).
- Probes: new `20261018110000_admissions_academic_years_write.sql` (A1 to A13, C1 to C5) and `_structure.sql` (S1 to S7). Changed on purpose: `20261015100000_admissions_decisions_capacity_capacity.sql` V6d and V7 setups insert 2028/2029 and 2030/2031 into the year list; V7's 50-character year case moved to the new file's C1 as a refusal. No other probe changed.

**Verification:**

- Baseline before the first edit (HEAD f04a336, fresh reset): overload check clean, types identical, anon count 169. After the build (test-runner): db reset and dev staff ok, overload check clean, types regen identical, anon count 169; six role-matrix files green (the two new files, 6a capacity and 6a structure, 7a academic years, 7b1 grade correction structure whose S2 shows the audit list still exactly 37); npm test 39 tests pass; tsc clean; lint 0 errors 13 warnings (same as baseline); build ok; no `select("*")` or `token_hash` in the admissions module; no service role key in `frontend/src`; nothing staged. Golden payroll suite skipped (audit CHECK and nothing payroll related changed).
- Six deliberate breaks, all caught, each on a fresh reset against only its probe file: no Manager check on add (A1 to A5 mismatched), unlisted year accepted by capacity (C1, C2), retired year accepted (C2), anon granted execute on add (S1, S7), audit trigger dropped (structure S3; behaviour A10, A11), and Auditor allowed to edit in `canEditAdmissionsSettings` (unit test failed). None dropped.
- Races: none tested by plan (simple writes).
- Code-reviewer: no blocking findings. Non-blocking notes: unused v_staff variables; the 50-character length check in capacity create is now only reachable by labels the list check refuses anyway (kept so its message is unchanged); hard-coded "1 to 90" and maxLength copies in the UI; the null campus cast in the capacity wrapper.
- Browser walk-through: not done.

**Outstanding:**

- Committed as bed38c9.
- Eyram's production steps (`npx supabase db push`, then `frontend/scripts/deploy-production.sh`).

**Carry-forward:** slices 8 and 9 validate the submitted year against the academic year list. The list is now written only through the two Manager RPCs; years are retired rather than deleted or renamed; capacity creation requires an active listed year while older rows stay editable.

**Not included:** accepted versus capacity counts (deferred), email (slice 12).

**Built as slice 7c** (2026-10-13, committed as 7a07d6a): see "Slice 7c" below.

## Slice 7c: Read-only Audit Log and Accountant audit narrowing

**Status:** committed as 7a07d6a (built 2026-10-13).

**Delivers:**

- **Migration `20261019100000_audit_log_admissions_read.sql`** (policy only). `audit_log_select` now lets Manager and Auditor read every row. The Accountant reads every row except actions starting `application_` or `admissions_` (9 of the 37 actions). Before this, Manager, Accountant and Auditor all read every row, so the Accountant could read admissions decision outcomes by APP reference, offer changes, and who holds the health gate.
- **Migration `20261019110000_audit_log_revoke_truncate.sql`:** revokes TRUNCATE on `public.audit_log` from `anon`, `authenticated` and `service_role`. Before it, all three held TRUNCATE through Supabase's default privileges. A probe showed that every role, anon included, could truncate `audit_log` in a rolled-back transaction.
- **Frontend `/audit-log`:** a thin route (`routes/audit-log/index.tsx`) with a role guard. Module code is in `frontend/src/modules/audit/`. Manager, Accountant and Auditor only.
  - Filters: action, and a From and To date range (both days included, UTC, which is Africa/Accra).
  - 50 rows per page, newest first. Actor names come from `list_staff_names()`. Changed fields are shown before and after.
  - The Accountant sees a note that admissions entries are not shown, and the action filter offers no admissions actions to the Accountant.
  - New sidebar section "Oversight" with "Audit Log".
- **Probes:**
  - `supabase/role-matrix/20261019100000_audit_log_admissions_read.sql` (S1 to S3, R1 to R5, W1 to W3). S1 classifies all 37 actions, so a new action fails it until it is classified.
  - `supabase/role-matrix/20261019110000_audit_log_revoke_truncate.sql` (T1, T2).
  - One deliberate edit to an existing probe: `20261005100000_admissions_grades_and_capabilities.sql`, E6 `expect` changed from Manager, Accountant, Auditor to Manager, Auditor.

**Decisions and gates:**

- The Accountant narrowing enforces D-1b on audit reads and the role matrix in "Roles and capabilities" (the Accountant has no admissions rows). It is not a separately recorded decision.
- **O-8 superseded 2026-10-13:** O-8 (2026-10-05) accepted that the Accountant reads capability changes through the existing `audit_log` policy. Under 7c the Accountant no longer reads them, because `admissions_capabilities_changed` starts with `admissions_`. O-8 is superseded because D-1b is now enforced by 7c.

**Verification (2026-10-13):** overload check clean, types regen identical, anon-executable count 169 (unchanged), lint 0 errors and 13 warnings (same as baseline), `tsc` clean, `npm test` 57 tests passing (18 new), build ok, no service role string in the bundle. Both new probe files are green. The 15 earlier probe files that touch `audit_log` give identical output except for E6. Deliberate breaks (8 for the policy, 1 for TRUNCATE) were all caught. The golden payroll suite ran at the end of 7c on a fresh reset and all cases pass; it was not run before the first edit. Full detail is in JOURNAL.md, 2026-10-13. Code-reviewer found no blocking findings. The browser walk-through of `/audit-log` is not done.

**Measured, not changed (for a later sweep decision):** after the revoke, 83 of 86 public tables still hold TRUNCATE for at least one API role (anon 13, authenticated 64, the rest service_role only). The list is in JOURNAL.md, 2026-10-13.

**Production steps:** the 7b2 and 7c migrations are applied on hosted (reported 2026-10-14). Whether the 7b2 and 7c frontend has been deployed with `frontend/scripts/deploy-production.sh` is not confirmed.

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
  - phone matching `^\+\d{3}\d{9}$` (TCS OS; superseded by D-9d, revised 2026-10-14: a plus sign and digits only, stored as sent: +233 and exactly 9 digits (the first not 0), for example +233590000000, or another country code (not starting with 0) and 8 to 15 digits in all, for example +442079460958; spaces, dashes, letters and extra digits are refused);
  - email format.

  It creates a family, guardians, students and one `inquiry` application per child. INQ references come from slice 5's trigger. **No de-duplication**, matching TCS OS (D-8c).
- `get_public_admissions_options()` is **anon**, SECURITY DEFINER and read-only. It returns active grades, campus names with accepted grades, and open academic years.
- Public route `/inquiry` (`routes/inquiry.tsx`), added to `__root.tsx`'s auth-free allow-list (`__root.tsx:155`).
- A Turnstile widget with explicit render, no `cf-turnstile` class, and a reset after every attempt (`02-stack-and-schema.md:615-619`).
- `VITE_TURNSTILE_SITE_KEY` as a build-time public value.

**Built 2026-10-14 (built locally, not committed).** This is what was built. Where it differs from the plan text above, the difference is stated here.

- **`submit_inquiry(p_payload jsonb)`** takes only the payload. There is no `p_client_ip`. The per-IP check is in the Edge Function, so the database never sees an IP.
- **Payload.** The grade is `grade_id` (an active `admissions_grades` id). The academic year is an active `admissions_academic_years` label, which is that table's key. `campus_id` is optional and is a `branches` id; a campus with grade rules must accept the grade. TCS OS inquiries carried no campus, so the campus is optional to match the slice 8 spec. Unknown keys are refused at every level. The RPC returns `text[]` of INQ references, in student order.
- **Rate limits.** The buckets are `submit_ip` (20 per hour), `submit_global` (200 per hour) and `inquiry_email` (5 per day, UTC, which is Africa/Accra's day). The numbers are in one function, `_public_rate_limit_rule`. The plan's `submit`, `draft` and `lead` buckets are not built.
- **`check_public_rate_limit(bucket, key_hash)`** takes only `submit_ip` (a 64-character hex HMAC) and `submit_global` (no key). The email bucket is counted inside `submit_inquiry`'s transaction, so an invalid or refused submission counts nothing. The global cap is counted only after Turnstile passes, so unsolved requests can't exhaust it. The table CHECK refuses any key that isn't 64 lowercase hex or `global`.
- **Refusal codes.** SQLSTATEs `TCS22` (invalid), `TCS03` (closed) and `TCS29` (email limit) are mapped by the Edge Function to fixed responses.
- **Service-only guard.** `_require_public_service_caller()` refuses a uid, and the `anon` and `authenticated` SET ROLE values, so an accidental grant can't open the service-only functions. It was found while writing the probes that the older pattern (`auth.uid() is not null`) doesn't stop `anon`. `settle_expired_offers` (6b) still uses the older pattern. It is service_role only by grant, so this is a carry-forward to consider, not a live hole.
- **Edge Function secrets.** `TURNSTILE_SECRET_KEY`, `IP_HASH_KEY` (32 characters or more) and `ADMISSIONS_ALLOWED_ORIGINS` (comma-separated exact origins). On a hosted project (an https `SUPABASE_URL`), an http or loopback origin makes the config invalid, and every request is refused.
- **Turnstile.** Verification requires `success`, a hostname in the allow-list, and action `inquiry`. Any error, or a 5-second timeout, refuses.
- **Function and config.** The Edge Function is `supabase/functions/admissions-public`, with `verify_jwt = false` in `config.toml`. The anon-executable count goes from 169 to 170, the one new function being `get_public_admissions_options()`.
- **Frontend.** `/inquiry` is auth-free. Admissions Settings has a Public intake card: a Manager toggle with a confirm step, and read-only for the Auditor. `frontend/scripts/deploy-production.sh` reads `VITE_TURNSTILE_SITE_KEY` from `.env.deploy`. The key is optional: without it, `/inquiry` tells parents to call the school office. The script refuses the `.env.local` key or a Cloudflare test key.

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

**Decided 2026-10-13:**

- **D-8a (decided).** The bot check runs in the Edge Function `admissions-public`. The submit RPCs are service-role-only: `submit_inquiry` and `check_public_rate_limit` are revoked from `public`, `anon` and `authenticated`, and granted to `service_role`. The service role key never reaches the browser, Cloudflare, or any `VITE_` variable.
- **Anon surface (decided).** `get_public_admissions_options()` is the one new anon-executable function, so the anon-executable count goes from 169 to 170. A probe names the added function. The six probe files that pin 169 move to 170 in this slice.
- **D-8b (decided).** A new ERP Turnstile widget with its own keys. The marketing site's widgets are decided in slice 13 (D-13b).
- **D-8d (decided).** Rate limits: 20 per hour per IP hash, a global cap of 200 per hour, and 5 per guardian email per day. The IP hash is an HMAC made in the Edge Function, so the database never stores a raw IP. The numbers are kept in one place so they can be tuned after the first real month. The fixed refusal tells the visitor to call the school office, so a false positive (for example, parents sharing a mobile carrier address) has a way out. The draft (120) and lead (60) bucket numbers are not covered by this decision.
- **D-8e (decided).** The origin allow-list is read from configuration, not hardcoded: the workers.dev host and `app.tcsch.edu.gh` for now, plus localhost in local development only. Eyram confirms the final production host before cutover (D-15e).
- **Public forms (decided, applies to slices 8 and 9).** Free-text academic years and free-text grades are refused; only the active lists are accepted. Where a grade isn't offered, the form says to contact the school.

**Still open:**

- **D-8c (decided 2026-10-14, closed).** No de-duplication on inquiries: each inquiry creates a new family, guardians, students and applications, as built. Revisit with slice 9's matching.
- **Forwarded IP (part of D-8d, closed reported by Eyram, 2026-10-14).** The forwarded-IP test on hosted: 25 plain requests gave 20 refusals by Turnstile, then 429 from request 21; 25 requests with a spoofed X-Forwarded-For all gave 429. So the leftmost header cannot be spoofed on the hosted platform, and this open item is closed.
- **(a) Forwarded IP, launch gate.** Code review noted that with a client-controlled `x-forwarded-for`, each spoofed request makes a fresh rate-limit row and a siteverify call before Turnstile refuses it. It also lets someone burn another visitor's IP allowance. The hosted header must be tested before public intake is opened. **Closed (reported by Eyram, 2026-10-14):** see the Forwarded IP item above.
- **(b) Per-email limit, needs Eyram.** The 5 per email per day limit lets anyone learn whether an email has been submitted today (the sixth attempt is refused). It also lets someone lock a parent out for the day with five junk inquiries. This is inherent to a per-email counter. Eyram to accept or change.
- **(c) Local CORS.** Locally the Supabase CLI gateway adds `Access-Control-Allow-Origin: *` and answers preflight itself. The handler's own Origin check still refuses foreign origins with 403. The hosted headers should be checked with curl after deploy.
- **(d) D-9d phone rule (revised 2026-10-14, closed).** a plus sign and digits only, stored as sent: +233 and exactly 9 digits (the first not 0), for example +233590000000, or another country code (not starting with 0) and 8 to 15 digits in all, for example +442079460958; spaces, dashes, letters and extra digits are refused. The form puts +233 in front of digits typed without a plus sign and shows every number with no spaces; it shows an error at once for spaces, letters, dashes or other symbols, a leading 0 on a Ghana number, and too many digits. Foreign numbers are accepted. This replaces the earlier 2026-10-14 rule (a plus sign and 8 to 15 digits, spaces and dashes removed). Applied in migration `20261023100000_admissions_inquiry_phone_format.sql`, the form logic, vitest and probe Q10.
- **Non-blocking review items, left as they are.** Rate-limit row cleanup runs on every hit (a scheduled cleanup later, D-12b). The closed flag is checked only in `submit_inquiry`, after the limits and Turnstile.

**Read from TCS OS (2026-10-13, from the code, not tested):**

- TCS OS's Turnstile check verifies `success` only (no hostname or action check), and fails closed on a network error.
- Draft saves and upload-url are not Turnstile-gated.
- TCS OS's DRF throttle has `NUM_PROXIES` unset, so it keys on the whole `X-Forwarded-For` string, whose front the client controls. With no `CACHES` setting, counters are per Cloud Run instance. So its rate limits are probably ineffective, and Turnstile is its only real control.

**Carry-forwards from slice 5:** service_role writes bypass RPC stage rules and write no audit row; intake transactions should stay short and number in consistent order (counter locks held to commit).

**Size:** one Edge Function with one action wired up, two small tables, three RPCs, one public route. It's the first anon slice, and its gate review is part of the pass.

## Slice 8b: public enquiry form polish and the two intake switches

**Built 2026-10-14 (built locally, not committed).** Not applied on hosted, not deployed. It follows slice 8 and changes the public enquiry form and the intake switches. The two migrations are `20261021100000_admissions_public_applications_flag.sql` and `20261021110000_admissions_inquiry_form_polish.sql`.

**Decisions (all made 2026-10-14):**

- **Religion** is a fixed list: Christian, Muslim, Traditional, Other, Prefer not to say. It is enforced in `submit_inquiry`.
- **Month of enrolment** is January, shown as "January (Limited Admissions)" (the TCS OS wording), or September. "Other" is dropped.
- **Current grade or class** is a list: N/A (not yet in school), then the 14 active grades. A child not yet at school but in early care picks Pre Nursery (decided 2026-10-14, replacing an earlier extra option).
  - It is stored as `students.current_grade_id` (an active grade) or `students.prior_schooling` (only `'not_yet_in_school'`), never both (check `students_current_grade_one_check`).
  - The old free-text `students.current_grade` is kept for legacy rows and is written empty by public enquiries.
  - Not yet in school: the current school field is hidden, not required, and refused if sent.
  - Any grade, Pre Nursery included: the current school is required.
  - A current grade above the grade applied into is not enforced.
- **Public campus labels.** `branches.public_label` is nullable and falls back to `name`. Seeded as "Main Campus (Somey Down)" for a campus named Main or Treasures Christian School (the hosted name), and "Annex (CK Road)" for Annex.
  - It is seeded by `_admissions_seed_public_campus_labels()`, which the migration calls. `seed.sql` and `seed.production.sql` call it after inserting campuses.
  - A guard trigger stops any signed-in user from setting or changing a label. `branches` has a broad `can_write()` update policy and the label is public, so labels change only by migration. `branches.name` is unchanged, so HR and Finance see no change.
- **Wording.** Parents see "enquiry" everywhere. The route `/inquiry`, INQ references and code keep "inquiry".
- **Date of birth** is typed as dd/mm/yyyy, with a numeric keypad and automatic slashes, and is sent as ISO.
- **Age hint** is display only, never sent or trusted: "Age today: 2 years 5 months (a guide only)" under 5, whole years from 5. It lives in `inquiry-form.ts` as `ageHint`, and a test checks that the payload has no age.
- **Also added:**
  - a "Same address as above" checkbox for guardian 2, which copies the address and town or city;
  - inline errors next to each field, including server errors. `submit_inquiry` names the field in the error DETAIL, and the Edge Function passes it on only when it matches a strict path pattern;
  - asterisks on required fields;
  - a thank-you page that says the school will contact the parent and shows the INQ reference or references to keep. No confirmation email exists until slice 12;
  - the phone hint "For example 0590000000 or +233590000000. From outside Ghana, start with + and the country code." (revised 2026-10-14; client side only, the box removes spaces, dashes, dots and brackets, and turns 0 and 9 digits, or 233 and 9 digits without a plus, into +233 and the 9 digits, shown when the parent leaves the box)

**Anon surface gate (approved 2026-10-14).** `get_public_admissions_options` changes only the campus label string, and adds an `applications_open` key. Its signature is unchanged, and the anon-executable count stays at 170.

**Two independent public intake switches (approved 2026-10-14).**

- **Naming.** Slice 8's `public_intake_open` and `set_admissions_public_intake` are applied on hosted and keep their names. They now mean public inquiries. A rename would have needed a coordinated column rename, function drop and frontend deploy for no change in behaviour, so only new objects were added.
- **New:** `public_applications_open` (default false) and `set_admissions_public_applications(boolean)`. The setter is Manager only, and is audited as `admissions_settings_changed` with only the changed field.
- `submit_inquiry` refuses only when public inquiries are closed. Slice 9's application submit must check only `public_applications_open`.
- Admissions Settings shows both switches. The Applications switch is disabled, with a note that the form arrives in a later slice. The Auditor sees both read-only.

**Built (detail):**

- Migrations: the two listed above. In `20261021110000_admissions_inquiry_form_polish.sql`, the slice 8 helper functions (`_public_text`, `_public_only_keys` and `_public_invalid`) were dropped and recreated with a field argument, so the field name can reach the error DETAIL.
- Seeds: `seed.sql` and `seed.production.sql` each call the label seeder after inserting campuses.
- Edge Function `supabase/functions/admissions-public`: the enquiry wording in two messages, and field path passthrough (strict pattern, as above).
- Frontend: the enquiry form (`inquiry-form.ts`, `inquiry-form.test.ts`), `components/inquiry-page.tsx`, `components/settings-page.tsx`, `data/application-detail.ts`, `data/settings.ts`, `labels.ts`, and `routes/inquiry.tsx`. `database.types.ts` was regenerated.
- Probes: two new files in `supabase/role-matrix/`, `20261021100000_admissions_public_applications_flag.sql` (P1 to P15) and `20261021110000_admissions_inquiry_form_polish.sql` (L1 to L12). Fixtures were updated in two slice 8 probe files, `20261020120000_admissions_submit_inquiry.sql` and `20261020130000_admissions_public_options.sql`.

**Not included:** emails (slice 12) and the application form (slice 9).

**Verification (2026-10-14, local only):**

- **Baseline** (HEAD 6842848, fresh reset): clean, anon-executable count 170.
- **After the build** (test-runner, fresh reset):
  - overload check clean; types identical; anon-executable count 170;
  - lint 0 errors and 13 warnings; `tsc` and build clean;
  - `npm test` 97 pass; `handler.test.ts` 27 of 27; `integration.test.ts` 7 of 7;
  - all 42 role-matrix files green.
- **Deliberate breaks: 16, all caught:** applications setter without the Manager check; setter granted to anon; `submit_inquiry` reading the applications switch; audit branch missing; options `applications_open` reading the wrong switch; religion check removed; month check removed; inactive current grade accepted; both current grade and prior schooling accepted; not yet in school with a school accepted; students constraint dropped; options returning the internal name; label guard dropped; label seeder matching only Main; field details passed unfiltered; age added to the payload.
  - Dropped on purpose: the old `current_grade` key (covered by the unknown-key rule).
- **Browser:** a local headless Chrome render of `/inquiry`, using Cloudflare's test keys, showed the enquiry wording, the new labels and the asterisks.
- **Golden payroll suite:** skipped. Nothing payroll-related changed, and the audit action list is unchanged.

**Code review (2026-10-14):** no blocking findings. Non-blocking, recorded as open follow-ups below.

**Reported by Eyram, 2026-10-14:**

- The slice 8b migrations `20261021100000`, `20261021110000`, `20261022100000` and `20261023100000` show on both sides of the hosted migration list, so they are applied on hosted. The slice 8 migrations `20261020100000` to `20261020130000` were already applied (reported by Eyram, 2026-10-14).
- The `admissions-public` Edge Function is at version 2 on hosted, last updated 2026-10-14 08:12 UTC (reported by Eyram, 2026-10-14).
- The hosted public options return the campus labels "Annex (CK Road)" and "Main Campus (Somey Down)" (reported by Eyram, 2026-10-14).
- The forwarded-IP test on hosted: 25 plain requests gave 20 refusals by Turnstile, then 429 from request 21; 25 requests with a spoofed X-Forwarded-For all gave 429. The leftmost header cannot be spoofed on the hosted platform, and that open item is closed (reported by Eyram, 2026-10-14).
- The live end-to-end test passed on 2026-10-14: a real Turnstile solve, an INQ reference on the thank-you page, the staff detail reading "Not yet in school", the Accountant unable to see it, and audit rows for the switch. Public inquiries were closed again afterwards (reported by Eyram, 2026-10-14).
- The 7b2 and 7c frontends are live: Eyram checked Admissions Settings and the Audit Log on the live site (reported by Eyram, 2026-10-14).

**Go-live cleanup (before real intake begins):** one test inquiry labelled "ZZ Test Do Not Process" exists on hosted (reported by Eyram, 2026-10-14). It must be removed by a small reviewed migration before real intake begins.

**Open follow-ups (not decided):**

- **Campus name check before the push.** If a hosted campus name is neither Main, Treasures Christian School nor Annex, its label stays empty and the form shows the raw name. A read-only check of the hosted campus names is to be run before the push.
- **Stale form after reopen.** A parent who loaded the old form before the close and submits after the reopen gets a generic "field the form does not send" message.
- **Delete restrict.** `students.current_grade_id` is `on delete restrict`, so a grade referenced by a student can't be hard deleted. Grades are retired rather than deleted.

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
  - **application fee proof (D-9e, decided 2026-10-14):** every application, for every grade, must include an `application_fee_proof` file that was reserved, uploaded and passed the byte check. A submission without one is refused with the same generic refusal as the other document failures. No outstanding `application_fee_proof` row is ever created, because a missing fee proof can't get through;
  - **campus grade rule:** when the chosen campus has rules, the grade must be in them (`serializers.py:218-221`);
  - every document must reference an **unconsumed, unexpired reservation**, and the object must exist in `storage.objects`. The RPC then consumes them. This fixes contradiction 9.
- Matching, from `serializers.py:251-330`:
  1. a guardian email match (case-insensitive) finds the family, otherwise a new one is created;
  2. the student match is name (case-insensitive) plus DOB within that family;
  3. an application match is (academic year, grade) for that student.
- Per D-9b (firmed 2026-10-13), an anon submission **never overwrites** existing guardian, student or health data, and a matched family never gains or changes guardians. Differing details go in the staff-only submission snapshot. The recommendation that an anon submission only advances a matched application from `inquiry` stands. Per D-9c (changed 2026-10-13), a match is never refused: it is flagged for staff, and the response is identical. What happens to the new application row on a match outside `inquiry` is not covered by that decision.
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

Service-role value probes cover: Annex plus Grade 3 raises; Main plus Grade 3 passes; Nursery 1 without vaccination raises; a submission with every other document present but no fee proof raises; a path not reserved raises; a reserved path whose object doesn't exist raises; a matched `inquiry` app advances and keeps its INQ; a matched `enrolled` app doesn't reset.

**Anon surface:** HTTP actions `upload_url` and `application` (Turnstile on `application`, IP limit on both). The signed upload URL is single-object and short-lived. **Confirmation gate.**

**Decided 2026-10-13:**

- **D-9b (firmed).** A matched family never gains or changes guardians from an anonymous submission. Differing details go in the staff-only snapshot. Rationale: refusing a same-year, same-grade match would confirm that a record exists (enumeration). TCS OS's Application response returns `family_id`, application id and `student_id`.
- **D-9c (changed).** Never refuse on a match. Flag it for staff, and give an identical response. The 2026-09-29 recommendation (refuse the same year and grade) is superseded.
- **Magic-byte check (decided).** At submit, PDF, JPEG and PNG files are checked by their leading bytes, because staff open files from strangers.
- **Split (decided).** Slice 9 is pre-split into 9a (upload path, submit RPC, minimal form) and 9b (the full 6-section form).
- **Public forms (decided, see slice 8).** Free-text academic years and grades are refused; only the active lists are accepted.
- **D-9e (decided 2026-10-14).** The application fee proof is compulsory, in the 9a plain form, the 9b form and `submit_application` (option A). TCS OS marked it required in the form only and didn't enforce it on the server (`02-stack-and-schema.md:509-516`); the ERP enforces it in both places. The earlier recommendation (optional, with an outstanding row for staff) is dropped. Design consequences:
  - The required document types come from one database helper per grade, used by both `submit_application` and `get_public_admissions_options`, so the form and the server can't drift. Fee proof is required for every grade; vaccination proof is added for grades with `is_preschool_vaccination_required`.
  - The reservation design treats `application_fee_proof` like the other three public types (one file per type).
  - The staff Submission check panel lists the fee proof first, with a note that staff must match it against the bank statement before treating the fee as paid.
  - Parents pay only into the school bank account (bank deposit, GIP, or mobile money into the bank), so every parent has a slip, confirmation or receipt. There is no cash route, so no staff-side "paid in person" path is needed. The form text and the staff panel note call it "proof of payment (bank deposit slip, GIP confirmation or mobile money receipt)".
  - Test plan: a probe that a submission with every other document but no fee proof is refused, and a deliberate break that removes the fee proof check.

**Decided 2026-10-14 (slice 9 planning answers):**

- **D-9a (closed).** Signed upload URL bound to a reservation. The bucket keeps no write policy.
- **D-9f.** One Turnstile solve opens an upload session (option C). The session token is random, only its hash is stored, and every upload in it uses the token. Submit accepts only that session's files.
- **D-9g.** Sessions and reservations live 6 hours (option C). At most 8 files per session. The open-reservation cap is **400** across everyone. The cap and the lifetime are kept in `_public_rate_limit_rule` with the other numbers. **Changed 2026-10-15:** a reservation counts toward the 400 only if it is neither used nor cleaned and either its file exists in `storage.objects` at the reserved path, or it is unexpired, has no file yet and is under 30 minutes old. The 30 minutes is the window of the `upload_open_reservations` rule. The sweep age rule (2 hours 15 minutes) and the 6 hour lifetime are unchanged.
- **D-9h.** Abandoned uploads are cleaned up by an Edge Function sweep (option A): after a request, the function deletes the files of a small batch of reservations that expired more than 30 minutes ago, through the Storage API. A scheduled sweep comes in slice 12.
- **D-9i.** `applications.declaration_ip_address` stays empty (option A). The signature name and the server-set `declaration_agreed_at` are kept.
- **D-9j.** A match on student, year and grade whose application is past `inquiry` creates a new application at `application`, with its own APP reference, health, emergency contact and documents, flagged as a possible duplicate (option A). A matched `inquiry` application still advances and keeps its INQ. Health is always written to a fresh row, so the staff-only snapshot never holds health data (closes the slice 3a carry-forward).
- **D-9k.** The Applications switch becomes usable in Settings in 9a (option A), for a live test that closes it again afterwards.
- **D-9l.** Only the slice 9 buckets are added now: `application_email` 5 per day, `upload_ip` 10 per hour, `upload_global` 100 per hour counted after Turnstile. The application submit shares `submit_ip` and `submit_global` with enquiries. The draft and lead buckets are not added yet.
- **Options change (anon surface gate, approved).** `get_public_admissions_options` gains a `required_document_types` list on each grade, read from one database helper that `submit_application` also uses. The anon-executable count must stay at 170.
- **Checkpoints.** 9a is built in two checkpoints, each stopping for Eyram's go:
  - **Checkpoint 1, the upload backend:** the session and reservation tables, the upload and cleanup RPCs, the new rate buckets, the `required_document_types` helper and options change, the `upload_session` and `upload_url` Edge actions, the sweep, their probes and deliberate breaks, and the local Storage checks.
  - **Checkpoint 2, the rest of 9a:** `submit_application`, the match flags table, the `application` Edge action with the byte check, the plain `/apply` page, the staff Submission check panel (fee proof first, with the note to match it against the bank statement) and the Settings switch.
  - 9b follows. The 21 deliberate breaks are split across the two checkpoints.

**Accepted risks (2026-10-14):**

- **PDF content.** The byte check proves the kind of file, not that it is harmless (a PDF can carry scripts). Files are served only through short-lived signed URLs, and the bucket allows only the three MIME types, so nothing is served as a web page.
- **Fake child in a real family.** Anyone who knows a parent's email can add a child record to that family. It is flagged, guardians never change, and slice 12 sends confirmations to the guardian already on record, so the real parent hears about it.
- **Per-email limit.** The 5 per day limit lets someone learn that an email was submitted today, or lock a parent out for the day. Inherent to a per-email counter; the refusal points to the school office.
- **APP sequence and timing.** APP numbers show the yearly volume, and the match path takes slightly different time. Both accepted.

**Carry-forward to slice 10:** revisit routing draft saves through the Edge Function with the upload session token, instead of direct browser to database writes, so saves get a per-IP limit and the same session binding.

**Checkpoint 1 built 2026-10-14, committed as c822b56:** the upload backend. Migration `20261024100000` is applied on hosted, and `admissions-public` is deployed on hosted at version 3 (both reported by Eyram, 2026-10-15). The checkpoint definition and the decisions behind it are in "Decided 2026-10-14" above.

- **Migration `20261024100000_admissions_application_uploads.sql`:**
  - Tables `application_upload_sessions` (`token_hash`, sha256 hex only; `expires_at`; `closed_at`) and `application_upload_reservations` (`session_id`; `document_type`, one of the four public types; `extension`, pdf, jpg, jpeg or png; `storage_path`, generated as `uploads/<reservation id>/<type>.<ext>`; `expires_at`, the session's; `consumed_at`; `cleanup_claimed_at`; `cleaned_at`; a check that a row is not both used and cleaned). RLS is on with no policies, and no API role has any privilege.
  - Service-role-only RPCs, each starting with `_require_public_service_caller()`:
    - `open_application_upload_session()`: refuses while `public_applications_open` is false (TCS03) and at the open-reservation cap (TCS29); returns the raw token once.
    - `reserve_application_upload(p_session_token, p_document_type, p_extension)`: the session must be live and not closed; checks the type and extension; 8 files per session; the open-reservation cap. Returns the reservation id, path and expiry.
    - `claim_expired_application_uploads(p_limit)`, p_limit 1 to 50.
    - `finish_application_upload_cleanup(uuid[])`.
  - Helpers granted to nobody: `_application_required_document_types(grade_id)` (fee proof first for every grade, plus `proof_of_vaccination` where the grade requires it) and `_application_upload_capacity_check()` (advisory lock held to commit).
  - `_public_rate_limit_rule` gains `application_email` (5 per day), `upload_ip` (10 per hour), `upload_global` (100 per hour), and two caps that are never counted: `upload_session_files` (8, window 6 hours, the session and reservation lifetime) and `upload_open_reservations` (400, window 30 minutes, how long an empty reservation counts; changed 2026-10-15, see below). `check_public_rate_limit` accepts `upload_ip` (HMAC key) and `upload_global` (no key). `application_email` is counted by `submit_application` in checkpoint 2.
  - `get_public_admissions_options` grades gain `required_document_types` (the approved anon gate). The signature is unchanged and the anon-executable count stays at 170. The live `/inquiry` parser ignores the extra key.
- **Sweep rule (fixed in fix round 1, see Verification):** a reservation is claimed and marked cleaned only when it is unused, expired more than 30 minutes ago, and was made more than 2 hours 15 minutes ago. Storage's signed upload token lives 2 hours from signing, whatever the reservation's expiry. Once a row is cleaned its token is dead, so no file can land afterwards and be orphaned. Claims lapse after 10 minutes and are retried.
- **Edge Function `admissions-public`:**
  - `upload_session`: upload_ip HMAC; then Turnstile with action `upload`; the sweep is deferred with `EdgeRuntime.waitUntil` for every request that passes Turnstile; then `upload_global` after Turnstile; then `open_application_upload_session`.
  - `upload_url`: fast refusal of type, extension and size (1 to 10 MiB); `reserve_application_upload`; re-validates the path shape; signs exactly that path; returns `reservation_id`, `path`, `upload_token` and `expires_at`. No Turnstile and no IP limit (D-9l).
  - New `storage.ts` holds the two Storage API calls, plain `fetch`, shared by `index.ts` and the integration test: signing with no `x-upsert` header (overwrite off), and deleting by prefixes.
  - Messages use "application" wording. The sweep deletes only paths of the reservation shape.
- **Probes:** new `supabase/role-matrix/20261024100000_admissions_application_uploads.sql` (U1 to U23). Fixture O4 in `20261020130000_admissions_public_options.sql` now includes `required_document_types` in the grade field list.
- **Tests:** `handler.test.ts` now 40 (13 new upload tests). New `upload.integration.test.ts` (7 tests, local database and local Storage). `frontend/src/lib/database.types.ts` regenerated (96 lines added).

**Verification (local only):**

- **Baseline** (HEAD 378d9d1, fresh reset): 42 probe files green, anon-executable count 170.
- **Local Storage checks:** anon upload without a signed URL refused; a token for a different path refused (InvalidSignature); a second upload to the same path refused even with `x-upsert` true (KeyAlreadyExists); 11 MiB refused (413); `text/html` refused (415); `Range: bytes=0-15` returns 206 with the leading bytes; signed upload token lifetime 2 hours with upsert off.
- **test-runner, after the build** (fresh reset): lint 0 errors and 13 warnings; `tsc` clean; `npm test` 107 of 107; build clean; overload check clean; types regen identical; anon-executable 170; all 43 probe files green; `handler.test.ts` 40 of 40; `integration.test.ts` 7 of 7; `upload.integration.test.ts` 7 of 7; prettier clean.
- **Order matters:** running the integration tests before the probe loop makes probe I1 in `20261011100000_admissions_core_applicants_structure.sql` fail on a reference collision, because the integration tests commit inquiry rows. It is green on a fresh reset. Run the probes before the integration tests.
- **Deliberate breaks:** 8 of the 21, all caught: guard removed from `reserve` (U9); session opening reads the enquiries switch (U11, U15); per-session file limit removed (U14); open-reservation cap removed (U15); raw token stored instead of the hash (U11); sweep 30 minute grace removed (U16); Edge signing a path without the shape check (handler unit test); signed upload issued with overwrite on (upload integration test). The other 13 are for checkpoint 2. After the fix round, removing the new age rule is caught by U16.
- **Golden payroll suite:** skipped. Nothing payroll-related changed, and the audit action list and audit policies are unchanged.
- **Code review:** no blocking findings. Fix round 1 fixed two non-blocking findings: the sweep age rule above, and U22 split into U22 (the bucket has no write policy; expect all roles) and U23 (direct insert; expect none). Re-review: both fixes OK.

**Open after checkpoint 1 (non-blocking, for Eyram):**

- **(a) The open-reservation cap could be filled cheaply. Closed 2026-10-15** by the cap change below.
- **(b) `upload_url` has no IP limit** (per D-9l). Invalid tokens are refused on one hash lookup.
- **(c) The bucket trusts the declared Content-Type** until checkpoint 2's byte check. Staff viewing: see the checkpoint 2 requirement below.
- **(d) Sessions and cleaned reservation rows are never purged** (small growth). A purge belongs with slice 12's scheduled sweep.
- **(e) The sweep runs on every solved `upload_session` request**, and each sweep is bounded at 20 deletes.

**Cap change (2026-10-15, checkpoint 1 files, committed in c822b56):** migration `20261024100000` was changed in place. `_application_upload_capacity_check()` counts a reservation that is neither used nor cleaned only if its file is in the bucket at the reserved path (expired or not, since the file takes space until the sweep), or if it is unexpired, has no file yet and was made within the 30 minute window of `upload_open_reservations`. Used reservations never count. Empty reservations therefore can't hold the cap: one Turnstile solve can block it for at most 30 minutes.

- **Probes:** U4 now pins `upload_open_reservations=400/00:30:00`. U15 (400 fresh empty reservations block a session and a reservation), new U24 (400 reservations with files, live and expired, block both) and new U25 (1,000 empty reservations older than 30 minutes, live and expired, don't block; with 399 files the next fresh reservation is the 400th place) cover the rule.
- **Deliberate break:** counting every unused reservation again is caught by U25. This adds one break to checkpoint 1 (9 in all), at Eyram's request.
- **Residual risk (accepted 2026-10-15):** a bot can still upload to a live signed URL up to 2 hours after its reservation stopped counting (the token lives 2 hours from signing; an empty reservation stops counting after 30 minutes). Once the file lands it counts again. This is bounded by `upload_global` (100 sessions per hour), 8 files per session and the 10 MiB bucket limit, and every such file is removed by the sweep once it qualifies.

**Checkpoint 2 requirement (recorded 2026-10-15):** staff must open application documents through signed URLs that force a download (attachment disposition), not an inline viewer.

**Deploy for checkpoint 1 (reported by Eyram 2026-10-15):** migration `20261024100000` is applied on hosted and `admissions-public` is deployed on hosted at version 3. The planned commands were `npx supabase db push`, then `npx supabase functions deploy admissions-public`. No new secrets. No frontend change. Public applications stay closed, so nothing is reachable by parents until the switch is turned on.

**Eyram gave the go for checkpoint 2 on 2026-10-15** (`submit_application`, the match flags table, the `application` action with the byte check, the plain `/apply` page, the staff Submission check panel and the Settings switch).

**Checkpoint 2 built 2026-10-15, committed as 92346dd and applied on hosted (reported by Eyram, 2026-10-15):** the rest of 9a. Checkpoint 1 is committed as c822b56. Eyram reports slice 9a is built and live on hosted: the plain `/apply` page, `/inquiry`, `submit_application`, the Edge Function actions and the staff Submission check panel. Not reported in this record: the D-9k live test result, and whether the Public applications switch has been closed again. Checkpoint 2 is the submit RPC, the match flags table, the `application` action with the byte check, the plain `/apply` page, the staff Submission check panel and the Settings switch.

- **Migration `20261025100000_admissions_application_submit.sql`:**
  - `submit_application(p_payload jsonb, p_session_token text, p_sniffed jsonb)` returns text, the APP reference only. This replaces the draft signature `(p_payload, p_client_ip)`, because D-9i made the client IP unnecessary. Service-role only, and it starts with `_require_public_service_caller()`. It accepts the full `ApplicationSerializer` shape now, so 9b is UI only.
  - Order of work inside the RPC:
    1. The applications switch is read under a share lock. Only `public_applications_open` counts; the enquiries switch plays no part (TCS03).
    2. Full payload validation: the slice 8b field rules and the D-9d phone rule; unknown keys refused; health details at most 2,000 characters; campus required, with the campus grade rules.
    3. The session row is locked by token hash. A session already used returns that application's reference and writes and counts nothing (D-9o).
    4. `application_email` is counted for each email. The emails are sorted first, so the bucket row locks are always taken in one order. Two submissions sharing any email are serialized by those locks, not by the session.
    5. The session's reservations are locked in id order. Each document must be a reservation of this session, unused, not cleaned, unexpired, of the same type, at the exact path, present in `storage.objects`, and the Edge-reported kind for that reservation id and path must match the extension. Required types come from `_application_required_document_types` (fee proof for every grade, `proof_of_vaccination` where the grade needs it). Every document failure gives the same generic document message.
  - Matching (D-9p, D-9j, D-9b):
    - Family: among families with a guardian email match, the oldest one holding a child with the same name (case-insensitive) and date of birth; else the oldest such family; else a new family with the guardians.
    - Student: name plus date of birth within that family. Never updated.
    - Application: same academic year and grade. At `inquiry`, the oldest one is advanced (it keeps its INQ and gains an APP). Past `inquiry`, it is left untouched and a new application is created at `application`, with its own APP, flagged `possible_duplicate`. Otherwise a new application.
    - Matched guardians are never added or changed.
  - Always written: the emergency contact, a fresh health row, and `application_documents` rows at `pending_review`. `declaration_agreed_at` is set; `declaration_ip_address` stays null (D-9i).
  - `application_upload_sessions.submitted_application_id` (on delete set null), with a check that it implies `closed_at`.
- **New table `application_match_flags`:** one row per application (`application_id` unique), written only when a family matched. Columns: `family_matched`, `student_matched`, `outcome` (`new_application`, `inquiry_advanced` or `possible_duplicate`), `matched_application_id`, and `differences jsonb`. A check allows only guardian keys and whitelisted student keys in `differences`, so no health value can be stored. RLS select: Manager, Auditor, and Admissions Officer with the application in scope, the same as `application_documents`, with no health capability needed (D-9m). Select grant to `authenticated` only; no write grant for anyone.
- **Helpers granted to nobody:** `_public_bool`, `_public_phone_ok`, `_application_kind_for_extension`.
- **No new audit action,** no audit policy change and no payroll item changed, so the golden payroll suite was skipped.
- **Edge Function `admissions-public`, action `application`:**
  - Body cap of 64 KB for this action only; the other actions keep 32 KB. Keys: `action`, `turnstile_token`, `session_token`, `payload`.
  - Order: `submit_ip` limit; Turnstile with action `application` (a second solve, after the `upload` one; D-9n); then `submit_global`.
  - Then a 16-byte `Range` read of each document whose path has the reservation shape (at most 4), through `readHead` in `storage.ts` with a 5 second timeout. `sniffKind` returns `pdf` (strict `%PDF-` at offset 0), `jpeg`, `png` or `unknown`. A failed read is `unknown` and still goes to the database, which decides.
  - Responses: 200 with `{reference}` only; 400 TCS22 with a field path allow-list; 409 TCS03; 429 TCS29 with the office message; 500 otherwise.
- **Frontend:**
  - `/apply` (`routes/apply.tsx`, `components/application-page.tsx`): one plain page with guardians, child, health, emergency contact, documents and declaration. Document slots come from the grade's `required_document_types`. Proof of payment is listed first, labelled "Proof of payment (bank deposit slip, GIP confirmation or mobile money receipt)". The route needs no sign-in (`__root.tsx`).
  - `parsePublicOptions` reads `required_document_types` per grade. The shared `Field`, `Choice`, `Notice` and `Shell` moved to `components/public-form-parts.tsx`.
  - Staff: a Submission check panel (`submission-check-panel.tsx`) on the application detail page. Fee proof first, with the note to match it against the bank or mobile money record before treating the fee as paid. It shows the match outcome, a link to an earlier application or "not in your scope", and the differences table.
  - The documents panel and the panel's download use `createSignedUrl` with `{ download: name }`, so the file is an attachment and never opens inline. File names are built only from the reference, the document type and the extension. Fee proof is listed first.
  - Settings: the Public applications switch is usable, for Manager only, behind a confirm dialog. Changes are audited by the existing `admissions_settings_changed` trigger (D-9k).
- **Build choices by the main session (2026-10-15, not Eyram's gates):** the RPC takes the full serializer shape now; the PDF check is strict at offset 0; the 64 KB cap applies to `application` only.
- **Decided by Eyram on 2026-10-15:** flags readable like `application_documents` (D-9m); a second Turnstile solve on submit (D-9n); a repeat submit on a used session returns the same APP reference (D-9o); the family match prefers the family holding the same child, else the oldest (D-9p).
- **Tests (local):**
  - Probe file `supabase/role-matrix/20261025100000_admissions_application_submit.sql`, A1 to A26.
  - `handler.test.ts`: 51 tests (11 new).
  - New `submit.integration.test.ts`, five tests: a real upload and byte check; HTML bytes sent as PDF refused, and PNG bytes sent as PDF refused; an Edge-level double click; the staff download link has `Content-Disposition` attachment; two database sessions racing on one upload session. Names are unique per run, so the file passes on a database it has run on.
  - New vitest files `application-form.test.ts`, `document-files.test.ts` and `submission-check.test.ts`. `npm test`: 124.
- **Verification (test-runner, fresh reset, end of pass):** overload check clean; types regen identical; anon-executable 170; all 44 probe files green; `handler.test.ts` 51 of 51; `integration.test.ts` 7 of 7; `upload.integration.test.ts` 7 of 7; `submit.integration.test.ts` 4 of 4; lint 0 errors and 13 warnings (baseline); `tsc` clean; build ok; prettier clean; no service role key in the build; nothing staged.
  - After test 5 was added (main session, fresh reset): the submit probe file green and `submit.integration.test.ts` 5 of 5, both after break 15 was restored and again after fix round 1, with the overload check clean and types identical. The test also passes 5 of 5 on a database it has already run on.
- **Deliberate breaks:** 13 in this checkpoint (10 to 22), all caught:
  - 10: guard removed (A5).
  - 11: fee proof dropped from the required list (A13, A26).
  - 12: sniff comparison removed (A16).
  - 13: `storage.objects` existence check removed (A15).
  - 14: session binding removed (A14).
  - 15: session row lock removed. Not caught at first by the Edge-level double click test, because the two requests never overlapped in the transaction. The two-database-session test (`submit.integration.test.ts`, test 5) was added and catches it: the second session is refused on the used reservation.
  - 16: guardians overwritten on match (A20).
  - 17: past-inquiry match advanced (A19, A21, A22).
  - 18: snapshot check removed and health written (A20, A22).
  - 19: flags policy widened to `true` (A6, A7).
  - 20: `application_email` count removed (A10, A23).
  - 21: Edge trusts the extension (handler tests).
  - 22: staff signed URL without download (`document-files` test).
  - Not broken on purpose: the payload path check (the document row uses the reservation path, so the check is redundant); the switch independence (no break was made); the share lock (not a genuinely concurrent integrity point).
- **Code review:** no blocking findings. Fix round 1 changed the order of the email count: emails are sorted before the per-email count, to avoid a deadlock. Re-review: the fix is OK, and nothing new is blocking.
- **Accepted risks (reported 2026-10-15):**
  - (a) Per-email griefing. Someone with a valid solve and files can make 5 successful submissions naming a victim's email (as guardian 2, say) and lock that email out for the day. Only successful submissions count. Bounded by `submit_ip` and `submit_global` (D-9l).
  - (b) Two submissions at the same moment for the same new child with disjoint guardian emails can create two families. Staff see the duplicates. Submissions sharing an email are serialized by the bucket row locks.
  - (c) Edge nit, left: non-application bodies are parsed up to 64 KB before the 32 KB refusal.
- **Rollout (Eyram runs; none run here), in this order:**
  1. `npx supabase db push` (applies `20261025100000`).
  2. `npx supabase functions deploy admissions-public` (version 3 to 4; no new secrets).
  3. `frontend/scripts/deploy-production.sh` (never a bare `wrangler deploy`).
  4. The D-9k live test: open Public applications in Settings, make one real submission at `/apply`, check the Submission check panel and one download, then close the switch again.
  - Public applications stay closed until step 4, and are closed again afterwards.
- **Open after checkpoint 2:** the accepted risks (a) to (c) above; 9b (the six-section form, optional document slots, scholarship and media consent inputs, nationality list); checkpoint 1 open items (b) to (e), unchanged; the "ZZ Test Do Not Process" cleanup from 8b, unchanged; the live-test application created in step 4 needs cleaning up before real intake.

**Still open:**

- **D-9d (revised 2026-10-14, closed).** a plus sign and digits only, stored as sent: +233 and exactly 9 digits (the first not 0), for example +233590000000, or another country code (not starting with 0) and 8 to 15 digits in all, for example +442079460958; spaces, dashes, letters and extra digits are refused. Built in slices 8 and 8b; slice 9's application form and emergency contacts use the same rule.


**Added 2026-10-14 (from slice 8b):**

- Slice 9's submit must refuse only when `public_applications_open` is false. It must not check `public_intake_open` (the inquiries switch).
- Slice 9's form should follow the slice 8b field rules: the religion list, current grade or prior schooling (never both; the not-yet-in-school rule), dd/mm/yyyy date of birth sent as ISO, and the phone rule.

**Size:** two Edge Function actions, one table, two RPCs, one large public form. The split into 9a and 9b is decided (2026-10-13); see Decided above.

### Slice 9b: the full six-section form, in the TCS OS look

**Status:** C1 committed as dffe810, deployed to hosted and checked by Eyram. C2 committed as 8393551. C3 committed as 14582d0, deployed to hosted together with C2, and checked on hosted by Eyram, including a second submission that produced the match panel (all reported by Eyram, 2026-10-15). C4 (close-out) written 2026-10-15, docs only, local and uncommitted.

**Goal:** `/inquiry` and `/apply` look and read like the TCS OS forms. Frontend only: no migration, no RPC, Edge Function, RLS or grant change. The anon-executable count stays at 170. The payload contract is final: TCS OS stores one combined declaration acceptance, a separate media consent, the signature and server time (the same four columns as the ERP), and every TCS OS application field is already accepted by `submit_application`.

**Approved by Eyram, 2026-10-15.** Decisions:

- **Q1.** Self-host the fonts through `@fontsource` packages, bundled by Vite.
- **Q2.** Move Inter off Google as well, at the same weights the staff app used (400, 500, 600 and 700).
- **Q3.** The new look applies to the two public pages only.
- **Q4.** Nationality is stored as the TCS OS country names (241, Ghana first). Demonyms such as Ghanaian are search aliases only.
- **Q5.** An unlisted nationality is not allowed.
- **Q6.** No server change. `students.nationality` stays capped at 100.
- **Q7.** The application fee amount and the account details live in a frontend constants file.
- **Q8.** Neutral wording ("the school will contact you") until slice 12 sends email.
- **Q10.** Port the 1 to 5 child count select on `/inquiry`.
- **Q11.** Native selects.
- **Q12.** TCS OS document order, with the fee proof under the fee box, labelled "Proof of application fee payment (bank deposit slip, GIP confirmation or mobile money receipt)".
- **Q13.** The vaccination slot is always shown; the requirement follows the grade flag.
- **Q14.** A teal focus ring instead of TCS OS's blue.
- **Q15.** TCS OS labels: Friend/Colleague, Social Media, Legal Guardian.
- **Q16.** No declaration text versioning for now. The TCS OS declaration and media consent text (Indemnity Clause, Data Protection, Declaration and Policy, Media Consent) last changed in TCS OS commit f7b57ae on 2026-08-26 ("Phase 5: Expanded application form"). The ERP will port it verbatim in C3, with only the verse attribution reformatted. The date the ERP copy changes is recorded then.
- **Q17.** The previous school's location is shown only when the child is in school.
- **Q18.** Deploy after C1 and after C3.
- **Q9 (answers reported by Eyram, 2026-10-15).** The application fee of GHS 200.00, the Consolidated Bank Ghana account details (account 0383011100001, name Treasures Christian School), the `*170#` steps and the scholarship link are accurate as TCS OS shows them. They keep the TCS OS wording, with dashes and arrows rewritten to the house rule. Q9 is closed except for the privacy policy (see Go-live gates).

**Plan changes from Eyram, 2026-10-15:**

- **(a)** The full-contract integration test runs at the end of C2 and again before the C3 deploy, not only in C4.
- **(b)** `font-display: swap` for all three families. Inter stays at the staff app's weights, so the staff app looks unchanged.
- **(c)** This housekeeping is recorded (the status rows above and the checkpoint 2 section).

**Checkpoints.** Each one stops for Eyram's review.

- **C1, look foundation and `/inquiry`.** Committed as dffe810 and deployed (reported by Eyram, 2026-10-15), see below.
- **C2, `/apply` structure.** Six steps, a sidebar, free navigation, the new plain fields, health as Yes/No, and a warning when leaving the page. Committed as 8393551 (reported by Eyram, 2026-10-15), see below.
- **C3, `/apply` content.** Nationality combobox, four document slots, the fee box, the scholarship question and link, the declaration and media consent, and the thank-you page. Committed as 14582d0, deployed and checked on hosted (reported by Eyram, 2026-10-15), see below.
- **C4, close-out.** The side by side checklist, the contract test, the slice 9 docs reconciliation and the go-live cleanup plan. Written 2026-10-15, see below.

**Go-live gate (decided 2026-10-15):** a published privacy policy must exist before real intake and before admissions.tcsch.edu.gh moves to the ERP. The declaration then gets one link, in the declaration copy constant. See "Go-live gates still open".

**C1 built 2026-10-15 (local, uncommitted, not deployed):**

- **Fonts.** `@fontsource/cinzel`, `@fontsource/dm-sans` and `@fontsource/inter`, all at 5.3.0 (exact; OFL-1.1). Inter is self-hosted for the whole app through `frontend/src/fonts/inter.css` (400, 500, 600, 700), linked from `__root.tsx` in place of the Google Fonts link and its preconnects. Cinzel (400, 700) and DM Sans (400, 500) are imported only by `frontend/src/modules/admissions/public-form.css`, which is linked only from the `/inquiry` route head (and `/apply` from C2). Every `@font-face` rule uses `font-display: swap`. `frontend/public/fonts-licences.txt` carries the three copyright lines and the OFL text.
- **Public stylesheet.** `public-form.css` is the TCS OS stylesheet with literal values (palette #F3FAFA, #D5E5E5, #1A2E2E, #5C7373, #005E61, #0B4C50 and #11B87A; Cinzel 700 headings at 1.6rem and 1.1rem; DM Sans body; 640px main column, 880px wide; card padding 1.75rem; labels 0.85rem; inputs 0.95rem; hints 0.78rem). It is scoped under `.tcs-public`, and `body.tcs-public-body` is added while a public page is mounted and removed on unmount.
- **Deliberate deviations from TCS OS:** a teal focus ring (Q14), with a transparent outline for forced colours; a red border on invalid fields (TCS OS had none); rows stack under 480px; inputs are 16px under 480px so iOS does not zoom.
- **Components.** New `components/public-page-parts.tsx` (PublicPage, PublicNotice, Section, BlockHeading, Row, PField with aria-describedby and aria-required wiring, NativeSelect). `/apply` still uses `public-form-parts.tsx` until C2.
- **`/inquiry`.** Rewritten to the TCS OS layout and wording: centred full logo and "Admissions Enquiry"; four numbered sections (How did you hear about us?, Parent / Guardian information, The enquiry, Other information); "Referral source" with an unlabelled "Please specify"; "Parent / Guardian 1" block headings; "+ Add a second parent / guardian" and "Remove" link buttons; the 1 to 5 child count select (`withChildCount`, which trims from the end); a full-width "Submit enquiry"; the message box above the form; and a thank-you page with TCS OS's sentence, the names as typed, the INQ references and the no-email line.
- **Kept from the ERP on purpose** (slice 8b and D-9d): the religion list; no free-text Other; current school only for a child in school; optional campus; the forgiving phone box and its hint; the age hint.
- **Copy.** Parent-facing strings are in the new `src/modules/admissions/public-copy.ts`.
- **No change** to `buildInquiryPayload`, `validateInquiry`, `submit_inquiry` or the Edge Function. The payload is unchanged.
- **Tests.** New `public-copy.test.ts` (no em or en dashes in the copy or the public page sources; TCS OS headings; `joinNames`), and `withChildCount` and label tests in `inquiry-form.test.ts`. `npm test` 131 (was 124).
- **Verification (test-runner, end pass):** lint 0 errors and 13 warnings (the same as the baseline at 92346dd); `tsc` clean; 11 files and 131 tests; build ok; prettier flags only the generated `database.types.ts`; 0 files in `dist` mention fonts.googleapis.com or fonts.gstatic.com; Inter is emitted at exactly 400, 500, 600 and 700; every font face uses swap; the public form CSS is referenced only by the `/inquiry` route; no service role key in `dist/client`; nothing staged. `supabase/` is untouched, so no `db reset`, overload check, types regen or role matrix was needed. The golden payroll suite was not run: no payroll, audit action or audit policy changed.
- **Deliberate breaks** (pure logic, each against its own test file; both caught; files restored byte for byte): child count shrink dropping from the start (`inquiry-form.test.ts`); an em dash in the copy (`public-copy.test.ts`).
- **SSR check (local dev server):** `/inquiry` links `styles.css`, `inter.css` and `public-form.css`. `/login` links only the first two. Neither mentions Google. Headless screenshots at 1280 and 375 px matched the TCS OS look, and `/login` still renders in Inter.
- **Code review:** one BLOCKING finding, fixed in fix round 1. The invalid and focus borders never showed on text inputs, because the base input rule out-ranked them; the rules are now under `:where()`. Non-blocking fixes: row spacing for single-field rows, aria-describedby for inputs, a forced-colours focus fallback, 16px inputs on phones, and the licence copyright lines. Re-review: the fixes are OK and nothing new is blocking.
- **After the fixes:** lint 0 errors and 13 warnings; `tsc` clean; 131 tests; build ok.
- **Deploy for C1 (Eyram runs; not run here):** `frontend/scripts/deploy-production.sh`. No `supabase db push` and no `supabase functions deploy`.

**C1 rollout (reported by Eyram, 2026-10-15):** C1 is committed as dffe810 and deployed to hosted. Eyram checked it on hosted: the fonts are self-hosted with no Google font request, the colours and fonts match the TCS OS look, Turnstile shows, the staff app is unchanged, and a test enquiry was submitted. That test enquiry is on the go-live cleanup list ("Go-live gates still open").

**C2 built 2026-10-15, committed as 8393551 (reported by Eyram, 2026-10-15; no deploy of C2 has been reported):** `/apply` in the TCS OS six-step layout (from TCS OS `backend/templates/public/apply.html`). The steps are Guardian(s), Student, Emergency, Health, Documents and Declaration, with the TCS OS headings. A sticky 210px section nav on the right shows a dot per step that turns mint with a tick when that step's required fields are valid. At 860px and below it becomes a sideways scrolling strip above the form, and the active step is scrolled into view. Steps can be opened in any order. Back and Next are on every step; Submit is on step 6 only. At submit, a message lists every incomplete section as a link back to it (TCS OS behaviour). The page uses the C1 public look (`.tcs-public`, `public-page-parts.tsx`, `public-form.css`, now linked from `/apply` too), the title "Admissions Application", the TCS OS subtitle, and "One application per child. Fields marked * are required." under it.

- **Pure module.** New `frontend/src/modules/admissions/application-steps.ts`: `STEPS`, `stepForField` (every validation key belongs to exactly one step), `incompleteSteps`, `completeSteps` (the same validator as submit), and `routeServerError`. A server field path opens its step and marks the field; a section-only path opens the section; a child address or town error is shown on guardian 1, because the child's address follows guardian 1.
- **One validator for the sidebar and submit.** The sidebar ticks and the submit both call `completeSteps`, so a step can't show as ticked while submit would refuse it.
- **Fields.** Gender is Male then Female. "Learner's home address" has "Same address as Parent/Guardian 1" ticked by default; the address follows guardian 1 at send time, and unticking copies guardian 1's address in to edit. Postal code is optional (20 characters). Country is prefilled Ghana (optional, 100). "Location/address of that school" is shown only for a child in school (optional, 255; not sent otherwise). The labels are "Campus applying to", "Grade applying for" and "Academic year applying for". The emergency contact has "Full name" and "Relationship to learner" (placeholder "e.g. Aunt, Family friend") and the hint "Someone we can reach if a parent/guardian is unavailable." The reworded email hint is on guardian 1 only. Health is three Yes/No questions in TCS OS wording with no default, so an unanswered question blocks the Health step; details are shown on Yes, capped at 2,000 characters, and the privacy line is kept. Nationality stays free text until the C3 combobox. Steps 5 and 6 keep the 9a content, restyled.
- **Turnstile.** The upload check opens the session at the first upload in step 5. The application check sits inside step 6, is mounted only there, and its token is dropped when the parent leaves step 6. The two checks have separate failure states.
- **Leave-page warning.** A `beforeunload` warning applies once anything has been entered or uploaded. The prefilled country and the ticked address box don't count. It is removed after a successful submit.
- **Payload.** The draft also carries `wantsScholarship`, `scholarshipDetails` and `mediaConsent`, sent as false and empty until C3 adds their inputs. No change to `submit_application`, `submit_inquiry` or the Edge Function; the payload contract is unchanged.
- **Accessibility.** Focus moves to the step heading on each step change. The health questions are radiogroups. The active nav item has `aria-current`.
- **Tests.** New `application-steps.test.ts` and `application-fixtures.ts`. `application-form.test.ts` is rewritten (the health rule, address following, optional field caps, the payload, and a check that the payload has exactly the keys of the shared fixture `supabase/functions/admissions-public/fixtures/full-application-payload.json`). The no-dash scan now covers the `/apply` sources. `npm test` is 152 (was 131).
- **Full-contract integration test.** `supabase/functions/admissions-public/submit.integration.test.ts` test 6 is a real submission against the local stack with all four documents, scholarship Yes with text, media consent, postal code, country, the previous school's location, a second guardian with a +44 phone, and a 44 character nationality. The stored values are checked. 6 of 6 pass. This is plan change (a), and it runs again before the C3 deploy.
- **Verification.** Baseline at dffe810: lint 0 errors and 13 warnings, `tsc` clean, 131 tests, build ok, prettier flags only the generated `database.types.ts`. test-runner end pass: lint unchanged (0 errors, 13 warnings), `tsc` clean, 12 files and 152 tests, build ok, prettier flags only `database.types.ts`, no Google font host in `dist`, the public form CSS referenced only by `/inquiry` and `/apply`, no service role key in `dist/client`, `handler.test.ts` 51 of 51, `submit.integration.test.ts` 6 of 6, public applications closed again afterwards, nothing staged. There is no migration, so no `db reset`, overload check, types regen or role matrix. The golden payroll suite was not run: no payroll, audit action or audit policy changed.
- **Deliberate breaks** (pure logic, each against its own test file; all caught; files restored byte for byte): student fields mapped to the wrong step; an unanswered health question treated as No; the child address copied instead of followed; a child address server error not moved to guardian 1; the sidebar ticking a step with an invalid field; the payload key `postal_code` renamed.
- **Browser check.** Headless screenshots through the DevTools protocol on a local dev server, at 1280 and 375 px, of steps 1, 2 and 4 and of the submit-incomplete message, matched the TCS OS look.
- **Code review.** One BLOCKING finding, fixed in fix round 1: Next on step 5 could submit the form, because Next and Submit shared one unkeyed button slot and React changed its type during the click. They are now separate keyed buttons, and submit runs only on step 6 (checked in a browser: Next on Documents lands on Declaration with no message). Also fixed: separate failure flags for the two security checks, focus to the step heading, and errors cleared when guardian 2 is removed. Re-review: the fixes are OK and nothing new is blocking.
- **Deploy for C2.** None. Q18 is deploy after C1 and after C3, so C2 goes out with C3. If Eyram wants to see C2 on hosted before then, `frontend/scripts/deploy-production.sh` (Eyram runs it).

**C3 built 2026-10-15, committed as 14582d0 (deployed and checked on hosted, reported by Eyram, 2026-10-15; see "C3 rollout" below):** `/apply` content. Frontend only. No migration, RPC, Edge Function, RLS or grant change, the payload contract is unchanged, and `submit_application` is not changed. The anon-executable count stays at 170.

- **Nationality (Q4 to Q6).** New `frontend/src/modules/admissions/nationalities.ts` holds the 241 TCS OS country names, checked against TCS OS by diff, with Ghana first and the rest in `Intl.Collator("en")` order. The stored value is the country name, so the staff pipeline reads one spelling. Search-only aliases (Ghanaian, UK, USA, Ivory Coast, Turkey and about 50 more) each point at a listed country, and they never appear as values. Matching ignores accents and punctuation, reads a hyphen as a space, and puts prefix matches first. The combobox is the WAI-ARIA pattern with an in-page list (no portal) in `components/nationality-combobox.tsx`: Enter or ArrowDown opens the list, the arrows move, Enter picks and never submits, Escape closes and keeps focus, Tab moves on, and tapping works. A typed name in any case becomes the listed name on leaving the field. An unlisted value is refused in the form with "Choose a country from the list" and the hint "Not listed? Please contact the school.". `submit_application` still accepts any text up to 100 characters, so this refusal is in the form only.
- **Documents, in TCS OS order (Q12, Q13).** Proof of vaccination is always shown. It is starred, and required, when the grade's `required_document_types` asks for it, with the hint "Required when applying for a preschool grade.". Then proof of financial clearance from the previous school (optional), report card or transcript from the previous school (optional), then the fee box and the fee proof slot "Proof of application fee payment (bank deposit slip, GIP confirmation or mobile money receipt)", which is compulsory for every grade. The upload security check sits at the top of the step, and the file inputs wait for it. Each file shows uploading, uploaded or failed. A failed replacement keeps the earlier file, still sends it, and says so. The browser checks the extension and the 10 MB limit, and the server stays the authority. Once 8 files have been started in one visit, the form says "reload and choose your files again" (D-9g). Every slot with an upload is sent, in slot order, and an optional slot is sent only when a file is attached.
- **Fee box (Q7, Q8, Q9).** `APPLICATION_FEE` and `FEE_BOX` in `public-copy.ts` hold the fee of GHS 200.00, Consolidated Bank Ghana, account 0383011100001, name Treasures Christian School, and the *170# steps as TCS OS shows them (accuracy reported by Eyram, 2026-10-15). The steps are joined by "then". Where TCS OS promises an email, the copy says "the school will contact you regarding an admission decision" instead, until slice 12 sends email.
- **Scholarship.** "Are you interested in scholarship information?", with the Treasures Impact Foundation hint and a "View scholarship details" link that opens in a new tab. Yes and No, with No as the default. "Tell us more" appears on Yes, and the details are sent only on Yes.
- **Declaration and media consent (Q16).** The ERP copy of the declaration is ported word for word from TCS OS `backend/templates/public/apply.html` at commit f7b57ae (2026-08-26) into `DECLARATION_SECTIONS` and `DECLARATION_COPY` in `public-copy.ts`. The copy date is 2026-10-15 (required by Eyram, to be recorded here). The only change is the verse attribution, which is now in brackets, "(Proverbs 22:6)", instead of after a dash. The media consent text, the agreement label "I have read and agree to the above Indemnity Clause, Data Protection consent, and Declaration & Policy." and "Sign by entering your full name:" are word for word too. The three sections sit in a scrolling box. The agreement checkbox is the combined one. Media consent is optional, has its own checkbox, and is independent of the declaration. The signature comes next, then the application security check. "the school's privacy policy" has no link yet. When the policy is published, its link goes in that one place, and the go-live gate stays open until then.
- **Thank-you.** TCS OS's sentence, with the child's name, grade and year as entered: "Thank you! We've received the application for {name} ({grade}, {year}). Our admissions team will review your documents and be in touch soon." It shows the APP reference and says that no confirmation email is sent. It makes no email promise.
- **Copy and styling.** All parent-facing text for the public forms is in `public-copy.ts`. File inputs take the TCS OS input styling.
- **Tests.** New `nationalities.test.ts` (241 entries, Ghana first, no duplicates, nothing over 100 characters, collator order, aliases, accent and hyphen matching, unlisted refused). `public-copy.test.ts` extended (no em or en dash in any copy, the full fee box and declaration text present, no email promise, the thank-you sentence). `application-form.test.ts` extended (slot order, optional slots sent only when uploaded, fee proof still required with every other slot filled, the 8-file cap, nationality refused or normalised, media consent independent of the declaration, scholarship default No). `vitest` runs 170 tests (was 152).
- **Baseline** at 8393551: lint 0 errors and 13 warnings, `tsc` clean, 152 tests, build ok, prettier flagging only the generated `database.types.ts`.
- **test-runner end pass:** lint unchanged (0 errors, 13 warnings), `tsc` clean, 13 files and 170 tests, build ok, prettier flagging only `database.types.ts`, no Google font host in `dist`, no service role key in `dist/client`, `handler.test.ts` 51 of 51, `submit.integration.test.ts` 6 of 6 (including the full contract, test 6), public applications closed again afterwards, nothing staged. There is no migration, so no `db reset`, overload check, types regen or role matrix. The golden payroll suite was not run: no payroll, audit action or audit policy changed.
- **After fix round 1,** the main session reran `tsc`, the 170 tests, lint, build and prettier on the final tree, and the full-contract integration test, which passed 6 of 6. This is plan change (a): the full contract runs again before the C3 deploy.
- **Deliberate breaks** (pure logic, 7 in all, each against its own test file; all caught; files restored byte for byte): unlisted nationality accepted; aliases removed from search; fee proof requirement dropped; vaccination requirement dropped; scholarship text sent on No; media consent tied to the declaration; an em dash in the copy.
- **Browser check** (local dev server, DevTools protocol): "ivo" lists Côte d'Ivoire, Enter picks it and closes the list, and Escape closes the list and keeps focus. Screenshots of the Documents step (fee box, slots, scholarship) and the Declaration step match the TCS OS look.
- **Code review.** No blocking findings. Fix round 1 fixed four non-blocking items: dragging the list's scrollbar no longer closes it; reopening the list resets the highlight, so Enter works; a failed replacement says the earlier file is still attached; hyphens match as spaces. Left as they are: the reload message at the cap loses the typed form (there are no drafts until slice 10); minor screen reader notes on the "No match" row and the upload status. Re-review of fix round 1: all four fixes OK, nothing new blocking.
- **Deploy for C3 (Eyram runs it; decision Q18).** `frontend/scripts/deploy-production.sh`. No `supabase db push` and no `supabase functions deploy`. This deploy also carries C2 (8393551), which has not been reported on hosted.
- **Hosted check after the deploy (planned, not run here).** `/inquiry` unchanged. `/apply` with Public applications open: one full end-to-end submission with fake data (child named "ZZ Test Do Not Process"), covering all six steps, the combobox, the documents, the fee box, the scholarship link, the declaration, media consent and the thank-you with the APP reference. Then the staff Submission check panel and the downloads for that application. Then close the switch. The resulting test application joins the go-live cleanup list (see "Go-live gates still open").

**C3 rollout (reported by Eyram, 2026-10-15):** C3 is committed as 14582d0 and deployed to hosted. The deploy carried C2 (8393551) as well. Eyram checked it on hosted, including a second submission that produced the match panel: the family matched by guardian email, the child matched by name and date of birth, the differences were listed, and the record was unchanged. The test applications from this check are on the go-live cleanup list. Answers reported by Eyram later on 2026-10-15: the C3 hosted check list for `/apply` was run and everything checked out (see C4.1); the second submission was a new application for a family already on record, not an inquiry advancing; the slice 9a D-9k live test was done earlier and checked out; every test record on hosted uses the child name "ZZ Test Do Not Process", and Eyram will list their references for the cleanup script. Still not reported: whether Public applications is closed again.

**C4, close-out (written 2026-10-15, docs only, local and uncommitted).** No code, migration, Edge Function, RLS, grant or deploy change. Nothing was run against hosted.

**C4.1 Side by side checklist (TCS OS against the ERP, at 375, 768 and 1280 px).** The 9b plan named the areas for a 20 point manual check; these are the 20 points. Status uses three values only:

- **Reported:** Eyram reported it on hosted, with the date. No width was reported for any check, so no row is marked as checked at a given width.
- **Local only:** seen in a local test, local build scan or local headless screenshot. This is not a hosted check.
- **Not checked:** nothing reported.

| # | Check | Widths | Status |
|---|---|---|---|
| 1 | No request to fonts.googleapis.com or fonts.gstatic.com (DevTools, Network) | any | Reported for the C1 deploy (2026-10-15): "fonts are self-hosted with no Google font request". The pages checked were not named. Local only: no Google font host in `dist`. |
| 2 | Same as 1, on `/apply` after the C3 deploy | any | Not checked |
| 3 | `/inquiry` headings in Cinzel 700, body in DM Sans (computed style) | 375, 768, 1280 | Reported for C1 (2026-10-15): fonts match the TCS OS look. Width not reported. |
| 4 | `/inquiry` colours: background #F3FAFA, teal #005E61, borders #D5E5E5, text #1A2E2E, muted #5C7373 | 375, 768, 1280 | Reported for C1 (2026-10-15): colours match. Width not reported. |
| 5 | `/apply` fonts and colours as in 3 and 4, plus the mint #11B87A step tick | 375, 768, 1280 | Not checked. Local only: screenshots at 375 and 1280. |
| 6 | Sizes: 640 px column on `/inquiry`, 880 px on `/apply`, card padding 1.75rem, labels 0.85rem, inputs 0.95rem, hints 0.78rem | 768, 1280 | Not checked |
| 7 | Phone: paired fields stack under 480 px, and tapping an input does not zoom (16 px inputs) | 375 | Not checked. Local only: 375 screenshots. |
| 8 | Sidebar at 860 px and below: a sideways strip above the form, the active step scrolled into view | 375, 768 | Not checked |
| 9 | Sidebar above 860 px: a sticky 210 px column on the right that stays in view while scrolling | 1280 | Not checked. Local only: 1280 screenshots. |
| 10 | A step's dot turns mint with a tick only when its required fields are valid | 375, 1280 | Reported for the C3 hosted check (Eyram, 2026-10-15): sidebar ticks. Not checked at any of the three widths. |
| 11 | Free navigation: any step from the sidebar, Back and Next on every step, Next on Documents goes to Declaration and never submits | any | Reported for the C3 hosted check (Eyram, 2026-10-15): all six steps. Next on Documents not reported separately. Local only: browser check after the C2 fix. |
| 12 | Submit with gaps lists every incomplete section as a link back to it | any | Not checked. Local only: C2 screenshot. |
| 13 | Nationality by keyboard: type "ivo", ArrowDown, Enter picks Côte d'Ivoire and does not submit, Escape closes and keeps focus, Tab moves on | 1280 | Reported for the C3 hosted check (Eyram, 2026-10-15): typing "ghanaian" and "ivo" by keyboard. Not checked at 1280 px specifically. Local only: Escape and Tab in the C3 browser check. |
| 14 | Nationality by touch on a real phone: tap opens, the list scrolls without closing, tap picks | 375 | Not checked |
| 15 | Nationality rules: "Ghanaian" finds Ghana; an unlisted value shows "Choose a country from the list" | any | Reported for the C3 hosted check (Eyram, 2026-10-15): "ghanaian". The unlisted value message not reported. Local only: `nationalities.test.ts`. |
| 16 | Documents step: TCS OS slot order, vaccination starred for a preschool grade, fee box text and account details, the scholarship link opens in a new tab | 375, 1280 | Reported for the C3 hosted check (Eyram, 2026-10-15): vaccination required for a preschool grade and not for Grade 3; fee proof upload and the refusal without it; replacing a file; an optional document; scholarship Yes with details. Slot order, fee box text and the link opening in a new tab not reported separately. Not checked at either width. |
| 17 | Declaration step: the scrolling box with the three sections, media consent on its own checkbox, the signature line, "the school's privacy policy" with no link | 375, 1280 | Reported for the C3 hosted check (Eyram, 2026-10-15): the declaration and signature. The rest not reported separately. Not checked at either width. |
| 18 | No em or en dash in any visible copy on either page, including errors and the thank-you | any | Not checked. Local only: `public-copy.test.ts` scans the copy and the public page sources. |
| 19 | Teal focus ring on every control, red border on invalid fields; Turnstile shows on `/inquiry` and both checks show on `/apply` | 375, 1280 | Turnstile on `/inquiry`: reported for C1 (2026-10-15). Turnstile in `/apply` steps 5 and 6: reported for the C3 hosted check (Eyram, 2026-10-15). Focus ring and invalid border: not checked. |
| 20 | The staff app is unchanged: login, dashboard and an admissions page in Inter, same layout | 1280 | Reported for C1 (2026-10-15). Not reported after the C3 deploy. |

**Also reported on hosted (C3 check, Eyram, 2026-10-15), outside the 20 visual points:** the thank-you page; the Submission check panel with the fee proof first; documents arriving as downloads; and a second submission, a new application for a family already on record, which the panel showed as matched by guardian email with the child matched by name and date of birth, listed the differences (guardian first name, and the child's previous school location blank) and said the record was not changed. The blank previous school location is backlog item 1 seen on hosted.

**Not checked on hosted (Eyram, 2026-10-15):** `/apply` at 375, 768 and 1280 px, and by touch on a phone.

**C4.2 Payload contract test.** It is in the suite. The shared fixture `supabase/functions/admissions-public/fixtures/full-application-payload.json` is read by two tests: `frontend/src/modules/admissions/application-form.test.ts` (the form's payload has exactly the fixture's keys) and `supabase/functions/admissions-public/submit.integration.test.ts` test 6 (a real submission against the local stack with every field, the stored values checked). Run on 2026-10-15 at 14582d0 on the local stack (not reset first; the test uses names unique per run):

- `npm test` (vitest): 13 files, 170 tests, all passing.
- `handler.test.ts`: 51 of 51.
- `submit.integration.test.ts`: 6 of 6, including test 6, the full contract.
- Not rerun in C4, because no code changed after their last green runs: the 44 probe files (green at checkpoint 2; 9b changed no SQL), `integration.test.ts` 7 of 7, `upload.integration.test.ts` 7 of 7, and lint, `tsc`, build and prettier (green at the end of C3).

**C4.3 Slice 9 as built (reconciled 2026-10-15).** Slice 9 is complete: 9a (checkpoints 1 and 2) and 9b (C1 to C4).

- **Hosted, as reported by Eyram:** checkpoint 1 (c822b56, migration `20261024100000`, `admissions-public` version 3); checkpoint 2 (92346dd, migration `20261025100000`, applied; Eyram reports 9a live on hosted); C1 (dffe810), C2 (8393551) and C3 (14582d0) deployed. The `admissions-public` version after checkpoint 2 was planned as 4; the version number was not reported.
- **The "Delivers" list at the top of slice 9 is the original plan, kept for history.** What was built differs in these places:
  - `submit_application(p_payload, p_session_token, p_sniffed)` returns only the APP reference. The planned `p_client_ip` was dropped (D-9i).
  - Upload paths are `uploads/<reservation id>/<type>.<ext>`, not `pending/<uuid>/...`. Sessions and reservations live 6 hours, not 2 (D-9g). Uploads go through a session opened by one Turnstile solve (D-9f), and `upload_url` has no IP limit (D-9l).
  - Abandoned uploads are cleaned by an Edge Function sweep after solved requests (D-9h), not by pg_cron after 24 hours. A scheduled sweep comes with slice 12.
  - A match is never refused (D-9c). A match past `inquiry` makes a new flagged application (D-9j).
  - The role matrix in this slice is probe files U1 to U25 (checkpoint 1) and A1 to A26 (checkpoint 2).
- **Decisions:** D-9a to D-9p (slice 9 sections above) and Q1 to Q18 (slice 9b). The DESIGN.md conventions from this slice: public uploads through a session and server-made paths; stored files deleted only through the Storage API; caps kept with the counters; Edge reports, database decides; staff open stranger-uploaded files only through a download link; self-hosted fonts; and, added in C4, one shared payload fixture and parent-facing copy in one file.

**Accepted risks for the whole of slice 9 (consolidated, none new):**

- Checkpoint 1 (2026-10-14): PDF content (the byte check proves the kind, not that the file is harmless); a fake child in a real family; the per-email limit reveals or blocks an email for a day; APP numbers and match timing.
- Cap change (2026-10-15): a bot can upload to a live signed URL up to 2 hours after its reservation stopped counting.
- Checkpoint 2 (2026-10-15): (a) per-email griefing; (b) two simultaneous submissions with disjoint emails can make two families; (c) the Edge Function parses non-application bodies up to 64 KB before refusing at 32 KB.
- By decision in 9b: the nationality list is enforced in the form only, and the server accepts any text up to 100 characters (Q6).
- Left as they are after C3 review: the reload message at the 8 file cap loses the typed form (no drafts until slice 10); minor screen reader notes on the "No match" row and the upload status.

**Still open from checkpoint 1:** (b) `upload_url` has no IP limit; (c) the bucket trusts the declared Content-Type, though since checkpoint 2 submit refuses a file whose leading bytes don't match its extension and staff only download; (d) sessions and cleaned reservations are never purged (slice 12); (e) the sweep runs on every solved `upload_session` request, bounded at 20 deletes.

**Backlog from slice 9 (recorded 2026-10-15, none built):**

1. **A blank answer shows as a difference in the Submission check panel.** When a matched record holds a value and the new submission left that field empty, `differenceRows` (`submission-check.ts`) lists it with "(blank)" as the submitted value. Nothing is changed (D-9b), but an officer may read it as the parent clearing the field. Watch for officer confusion after go-live. If it confuses, either hide blank against value rows or label them "left blank on this form; record kept". No change now.
2. **A withdrawn or spam disposal.** The eight stages have no place for an application the parent withdraws or one that is spam. Today staff can leave it where it is or record a negative decision, which misstates it. Needs a decision before it is built: a stage or a disposal reason, who may set it (a permission gate), whether it frees capacity, and whether spam rows fall under the D-4d purge.
3. **A stored declaration version before go-live.** Q16 left versioning out. The privacy policy link will change the declaration text, so before real intake decide whether each application stores which text was agreed (for example a version key next to `declaration_agreed_at`). This is a schema change and needs its own slice. Also listed under "Go-live gates still open".
4. **Carried, unchanged:** draft saves through the Edge Function with the session token (slice 10); the scheduled sweep and the purge of old sessions and reservations (slice 12).

**C4.4 Go-live cleanup plan.** Written as its own section, "Go-live test data cleanup plan", before the cutover runbook. Plan only.

**Still open after C4 (slice 9 closed):** the privacy policy go-live gate; the stored declaration version decision; the go-live test data cleanup (plan written, nothing run); checklist points not yet checked on hosted (C4.1); whether Public applications is closed again after the C3 check (not reported); the accepted risks and the checkpoint 1 open items above; backlog items 1 to 4.

**Still open after C3 (history):** C4 (close-out); the privacy policy go-live gate; the test application from the C3 hosted check, if that check is run; the go-live cleanup items (the "ZZ Test Do Not Process" record, the slice 9a live-test application and the C1 rollout test enquiry); the slice 9a accepted risks (a) to (c); checkpoint 1 open items (b) to (e).

**Still open after C2 (history):** C3 (nationality combobox, four document slots, the fee box with the TCS OS wording, the scholarship question and link, the declaration and media consent text, the thank-you sentence) and C4; the privacy policy go-live gate; the go-live cleanup items (the "ZZ Test Do Not Process" record, the slice 9a live-test application and the C1 rollout test enquiry); the slice 9a accepted risks (a) to (c); checkpoint 1 open items (b) to (e). All unchanged.

**Still open after C1 (history):** C2, C3 and C4; the privacy policy go-live gate; the slice 9a accepted risks (a) to (c); the "ZZ Test Do Not Process" cleanup; checkpoint 1 open items (b) to (e). Unchanged at the time.

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

### Slice 10 as built (local only)

The text above is the original plan, kept for history. Slice 10 was planned again on 2026-10-21 and approved by Eyram with D-10a to D-10l the same day. C1 (the database) is committed as dcbff52. C2 (the Edge Functions) is committed as 3ec9468. C3 (the form) is built and uncommitted. Nothing is on hosted. The full record comes with the slice close-out (JOURNAL, 2026-10-21).

**Built (local only):**

- **C1, database (dcbff52).** Migration `20261028100000_admissions_drafts.sql`: tables `application_drafts` and `application_draft_links`, RLS on with no policy and no API privilege; a state check (an allowlist of keys) that refuses `health`, `documents`, `signature`, `agreed` and `mediaConsent` at every level; a 48 KB size cap; outbox kind `draft_resume` with `params {}` and a `draft_id`. Resume emails are left out of the 4 per address confirmation cap, out of `list_admissions_emails` and out of requeue. `get_admissions_email_health` counts exclude them and gain `draft_failed`. Housekeeping wipes expired drafts, deletes a draft 30 days after expiry or submission, purges resume rows after 7 days, and drops a wiped or submitted draft's waiting resume rows. Migration `20261028110000_admissions_draft_rpcs.sql`: service-role-only `create`, `get`, `save`, `delete`, `issue_application_draft_link` and `submit_application_from_draft`. `submit_application` is unchanged.
- **C2, Edge functions (3ec9468).** Migration `20261029100000_admissions_draft_edge_support.sql`: DETAIL codes `draft_limit` and `draft_email_limit`; `issue_application_draft_link` returns `issued`, `expired` (marks the row expired when the switch is closed, or the draft expired or was submitted) or `failed`. `20261028110000` was changed in C2 (49 lines). `admissions-public` actions: `draft_create` (`draft_ip`, Turnstile action `draft`, `draft_global`), `draft_save`, `draft_get`, `draft_delete` (`draft_use_ip`, token gated), and `application` with an optional `draft_token`. Tokens travel only in POST bodies. The live-draft limit and the rate limits return one generic refusal: "We could not save your application right now. Please contact the school office." `admissions-worker`: an unreadable claimed row is failed on its own (the batch fix); the resume link is minted between claim and send and never logged or stored; resume emails send with `Idempotency-Key: outbox-<id>-<attempt>`; a second link request in one claim counts as a failed attempt; the worker reads the optional `PUBLIC_APPLY_BASE_URL`; template "Your saved application".
- **C3, form (uncommitted).** `frontend/src/modules/admissions/saved-application.ts` (`toSavedState` and `fromSavedState`, which re-check every value against the current options; `hasUnsavedChanges`; `readResumeFragment`). The save panel on `/apply`: the email is prefilled from guardian 1, a consent tick, Turnstile on the first save only. A later save can email a new link. A resume email limit undoes that save, and later saves offer "Save without emailing a link". A version conflict re-reads the latest version and offers "Save what is on this screen". Resume is at `/apply#resume=<64 hex>`, stripped at once through the router's history. A welcome banner with Discard; files are re-attached by hand on resume; the form locks when the draft is already submitted; the leave page warning covers only unsaved changes, parts never saved and attached files. The staff email health strip shows "Saved application links failed". Copy is in `public-copy.ts` (`SAVE_COPY`, `DRAFT_REFUSED`, `PRIVACY_POLICY`; the policy URL is null until the policy is published, and that is the one place the link goes). A test ties the 30 and 60 day numbers to the migration.
- **Review decisions (Eyram, 2026-10-21).** An expired draft (not failed) also for submitted and expired drafts; a first save that hits the resume email limit is simply refused; old Prettier mismatches in the public handler files are left alone.
- **Verification (local, test-runner end pass 2026-10-21, then the main session after fix round 1).** Fresh reset; overload check clean; types identical; anon-executable 170; 50 of 50 probe files green (new D1 to D9, B1 to B10, L1 to L3); Edge unit tests admissions-public 62, worker 30, templates 13; integration tests integration 7, upload 7, submit 6, draft 6, worker 7 (fake provider, no real email); lint 0 errors and 13 warnings (baseline); `tsc` clean; vitest 216, run after the health strip count was added; build ok; no service role key in `dist/client`; Prettier clean on the changed files. Golden payroll suite not run: no payroll, audit action or audit policy was touched.
- **Not done:** no browser run of the form locally; the hosted test is in the handover below.

**Decisions (Eyram, 2026-10-21):** drafts hold no health answers at all (D-10d), no files (D-10c) and no declaration, signature or media consent; 30 days from the last save, at most 60 from creation (D-10a); wiped at expiry, deleted 30 days later, resume email rows kept 7 days (D-10b); an explicit save button only, no autosave; the resume link's token is minted at send time and only its hash stored; staff see no drafts, only a count of failed resume emails on the email health page; a resume email limit is shown to the parent, the save is undone, and the page offers to save again without the email; the live-draft limit gives only "We could not save your application right now. Please contact the school office."; a resume email no longer needed while public applications are closed (or whose draft expired or was submitted) is marked expired, not failed. Accepted in C1: the per-draft daily email cap is dropped (the per-address cap of 3 always binds first), one link per worker claim, the link backstop cap is 61.

**Accepted risks (2026-10-21):**

- Anyone who passes Turnstile can fill an address's 3 live draft slots for 30 days. The real parent then sees only the generic message and has to contact the school office.
- Plus addressing (`a+1@`, `a+2@`) gets around the per-address caps. The IP limits, the global draft limit and the 2,000 live draft cap still apply.

**Recorded rule:** any future migration that lowers the 48 KB draft size limit must also fix existing rows (CONSTRAINTS.md, "Data safety").

**Cutover additions:** `PUBLIC_APPLY_BASE_URL` and `ADMISSIONS_ALLOWED_ORIGINS` change to `admissions.tcsch.edu.gh` at cutover ("Cutover runbook", step 4). Resend click and open tracking must be off for `mail.tcsch.edu.gh` (CONSTRAINTS.md checklist; Eyram checks).

**Rollout order (for the handover):** deploy the new `admissions-worker` before `npx supabase db push`. The old worker would otherwise fail the claim for its whole batch when it met a `draft_resume` row.

### Slice 10 rollout handover (Eyram runs every step; none run here)

Do the steps in order. Stop at any step whose check doesn't match. Nothing in this section has been run on hosted.

**0. Before you start.**

- C3 committed; `git status` clean, on `main`.
- Resend dashboard, Domains, `mail.tcsch.edu.gh`: **click tracking and open tracking both off** (CONSTRAINTS.md checklist). A resume email carries a private link; click tracking would rewrite it through Resend's tracking host. Do not continue until both are off.
- Note: `MAIL_MODE` is live on hosted (reported 2026-10-21), so step 6 sends real email, to your own address only.

**1. Backups.** Dashboard, Database, Backups: a backup from today exists. Optionally the local dumps as in the slice 12 handover (encrypted disk, delete after the checks).

**2. Deploy the worker first.** It reads resume emails safely, and until the migrations are applied there are none.

```sh
npx supabase functions deploy admissions-worker --no-verify-jwt
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  "https://<project-ref>.supabase.co/functions/v1/admissions-worker" \
  -H 'content-type: application/json' -d '{"job":"mail"}'
# 401: refused without the secret
```

**3. Database.**

```sh
npx supabase db push --dry-run
```

It must list exactly these three, in this order, and nothing else: `20261028100000_admissions_drafts.sql`, `20261028110000_admissions_draft_rpcs.sql`, `20261029100000_admissions_draft_edge_support.sql`. Then:

```sh
npx supabase db push
```

Read-only checks in the SQL editor:

```sql
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');   -- 170
select count(*) from public.application_drafts;                                    -- 0
select has_table_privilege('anon', 'public.application_drafts', 'select'),
       has_table_privilege('authenticated', 'public.application_drafts', 'select'); -- f, f
select jobname from cron.job where jobname like 'admissions-%' order by jobname;    -- the same 4 jobs
```

**4. Deploy the public function.**

```sh
npx supabase functions deploy admissions-public --no-verify-jwt
```

**5. The resume link base.** The public origin that serves `/apply` today, exactly as it appears in `ADMISSIONS_ALLOWED_ORIGINS` (https, no path, no trailing slash). Not a secret value, but it is a function secret so the worker can read it:

```sh
npx supabase secrets set PUBLIC_APPLY_BASE_URL=https://<the origin that serves /apply>
npx supabase secrets list   # names only
```

Until this is set, confirmation emails still go and resume emails wait (the staff page shows a mail settings problem). At cutover it changes to `https://admissions.tcsch.edu.gh` ("Cutover runbook", step 4).

**6. Frontend, last.**

```sh
cd frontend && ./scripts/deploy-production.sh
```

Never a bare `wrangler deploy` (CONSTRAINTS.md, "Deployment").

**7. Hosted test with your own address.** Every record made here joins the go-live cleanup list.

1. Sign in as Manager and open Public applications.
2. On `/apply`, enter guardian 1 with your own email, a child named "ZZ Test Do Not Process", and answer a health question. Press "Save and finish later", check the email is prefilled, tick the consent box, complete the security check and save. The panel says the link was emailed to your masked address and the date it is kept until.
3. Admissions Emails: the resume email is **not** listed (by design) and "Saved application links failed" is 0.
4. In your inbox, "Your saved application" from `TCS Admissions <no-reply@mail.tcsch.edu.gh>`: no names, no dashes, one link `<PUBLIC_APPLY_BASE_URL>/apply#resume=…`. Hover the link: it points to your own origin, not a Resend tracking host.
5. Open the link in a private window. The address bar loses the `#resume=…` part at once; pressing Back doesn't bring it back. The banner says your answers are restored; the health question is blank again; on Documents a notice says files must be attached again.
6. Change a field and close the tab: the browser warns. Save again (no security check this time).
7. Attach a fee proof, answer the health questions, complete the declaration, submit. You get the APP reference and a confirmation email. Opening the resume link again now says the application has already been submitted.
8. Close Public applications. Optionally, check in the SQL editor that the draft is wiped: `select submitted_at is not null, data, email from public.application_drafts order by created_at desc limit 1;` (true, `{}`, null).

**8. Cleanup.** Add to the go-live cleanup: the test application and its outbox rows, the test draft (deleted by housekeeping 30 days after submission, or by hand). Decide whether to leave mail live.

**If something goes wrong.** `npx supabase secrets set MAIL_MODE=off` stops all sending at the next run. Closing Public applications stops new drafts (create, open and save all refuse while it is closed; delete still works).

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

**Not included:** email. **Moved here from slice 12 (decided 2026-10-16):** the offer email, since it needs this page. It uses the slice 12 outbox and worker; a raw token in the outbox needs the D-12c decision first.

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

### Slice 12 as built (2026-10-16 to 2026-10-20, local only)

The "Delivers" list above is the original plan, kept for history. Slice 12 was planned again on 2026-10-16 and approved by Eyram with changes the same day and on 2026-10-18 and 2026-10-20. C1 is committed as a929511, C2 and C3 as 8a45e04. The rollout as reported by Eyram is in "Slice 12 rollout reported" below; this section records what was built.

**Decisions (Eyram, 2026-10-16, 2026-10-18 and 2026-10-20):**

- **D-12a, provider.** Resend HTTP API, a separate ERP key ("tcs-erp-transactional", sending access only, limited to `mail.tcsch.edu.gh`), set only as a Supabase function secret.
- **D-12b, queue.** Outbox written in the submit transaction, emptied by the `admissions-worker` Edge Function, called by pg_cron through pg_net. Sending straight from `admissions-public` was rejected: an email would be lost if Resend were down or the function stopped after the commit.
- **D-12c, token links at rest.** Does not arise in this slice: no email carries a link with a token. The outbox stores no body at all, only params (below). Offer and draft emails, which carry tokens, are slices 11 and 10.
- **D-12d, GoTrue SMTP for invites.** Out of this slice.
- **D-12e, sender.** From `TCS Admissions <no-reply@mail.tcsch.edu.gh>` (the From address of a real TCS OS email Eyram received on 14 Oct; the bare `tcsch.edu.gh` is not a verified sending domain). Reply-To `admissions@tcsch.edu.gh`, a mailbox someone reads (reported by Eyram). Both are function secrets with no code default. Sign-off "Kind regards, / Admissions Office / Treasures Christian School".
- **D-12f, content.** No names: "Dear Parent or Guardian", the reference with grade and academic year, several children listed as "Child N on your form". No health data, no document names, no links in a parent email. The application email keeps the TCS OS decision and fee sentence without the bank details. Subjects "We have received your enquiry" and "We have received your application". No em or en dash and never the word "inquiry" in a subject or body (code names keep it).
- **D-12g, overview PDF.** Dropped from the enquiry email. TCS OS gates it behind a lead form, and a public link would bypass that. It returns with the PDF gate in slice 13.
- **D-12h, recipients.** Typed guardian emails first, then every guardian email on record for the family, de-duplicated, at most 4. A typed address not on record gets the same email, so nothing reveals whether a family exists. The parent email is identical for a new family, a matched family and a possible duplicate; only the staff alert states the match.
- **D-12i, limits.** At most 4 parent emails per address in 24 hours (`email_recipient_day` in `_public_rate_limit_rule`); more are stored as suppressed and never sent. A global daily ceiling, `MAIL_DAILY_CEILING`, a function secret Eyram sets from the real Resend plan limit, because the Resend account is shared with other domains (`updates.tcsch.edu.gh`, `erp.wilelikcompanyltd.com`).
- **D-12j, retries.** A claim is an attempt. Waits of 1, 5, 15, 60 and 240 minutes; the sixth failure marks the email failed. A 400 or 422 fails at once.
- **D-12k, retention.** Sent rows 90 days; failed, suppressed and expired rows 180 days; upload sessions 30 days after expiry.
- **D-12l, visibility.** Manager and Auditor see the email page (masked recipients, no staff address) and the health strip; anyone who can see an application sees its confirmation status line; only a Manager can retry, and only failed emails.
- **D-12m, worker.** A secret-gated public endpoint (`verify_jwt = false`). The secret is made in Vault by the migration and no person handles it. The worker uses the service role key from its function environment, only for the service-role-only functions, and never logs it (approved 2026-10-20).
- **D-12n, maximum age (2026-10-20).** A queued email older than 48 hours when the worker claims it is marked expired and never sent (age counts from a Manager's retry when there is one). This stops a backlog going out all at once when `MAIL_MODE` is switched to live after the hosted tests, and stops late emails after a long outage.
- **D-12o, staff alert address.** `ADMISSIONS_STAFF_EMAIL`, a function secret Eyram sets at rollout. The TCS OS address is unknown (nobody received the alert from Eyram's 14 Oct test) and is not copied.
- **Moved out:** the offer email to slice 11 (it needs the `/offer` page); the draft resume email stays in slice 10; the PDF gate and lead staff alerts are slice 13. Bounce and complaint webhooks are deferred (a new public endpoint and a new gate). Invite emails are out.
- **Recorded risk (accepted 2026-10-20).** Any request that carries a non-empty worker secret header causes one service-role database call (reading the expected secret) before the comparison. It is cheap and returns nothing, but it is a small amplification on a public endpoint.
- **Accepted risk (2026-10-21).** The ERP marks an email Sent when Resend accepts it, not when it is delivered. A later bounce or suppression is visible only in the Resend dashboard until bounce and complaint webhooks are built (deferred, D-12 "Moved out"). Seen in the hosted test: the first staff alert showed Sent in the ERP while Resend had suppressed it.

**C1, the database (committed as a929511):**

- `20261027100000_admissions_email_outbox.sql`: `admissions_email_outbox` and the one-row `admissions_email_worker`, neither with any API privilege. `submit_inquiry` and `submit_application` re-created with one added line each, `perform public._enqueue_admissions_emails(...)`, after every write (checked by diffing against their previous definitions). The repeat submit of a used upload session (D-9o) returns before that line. A check (`_admissions_email_params_ok`) limits params to references, grade names and academic years, plus family_matched and outcome on the application staff alert. Unique (event_key, kind, recipient) with nulls not distinct. Worker functions (service role only, `_require_public_service_caller`): `claim_admissions_emails(limit, ceiling)` (advisory lock, skip locked, 5 minute lease), `mark_admissions_email_result` (claim token required), `admissions_worker_secret()`. Staff functions: `list_admissions_emails` and `get_admissions_email_health` (Manager, Auditor), `get_application_email_status` (anyone who can see the application), `requeue_admissions_emails` (Manager, recorded as `requeued_by` and `requeued_at` on the row; no new audit action). `set_admissions_worker_url` is callable by no API role; the URL must be https, except for the local Docker host names.
- `20261027110000_admissions_scheduled_jobs.sql`: `pg_cron` and `pg_net`; `_admissions_worker_kick` (posts only when an email is due); `purge_admissions_housekeeping`; four jobs: `admissions-mail` every minute, `admissions-upload-sweep` every 15 minutes (the scheduled sweep D-9h left to this slice), `admissions-settle-offers` hourly (D-6l), `admissions-housekeeping` daily at 03:00. This closes checkpoint 1 item (d) (sessions and cleaned reservations purged).
- Probes: `supabase/role-matrix/20261027100000_admissions_email_outbox.sql`, E1 to E23. Two-session claim race. 13 deliberate breaks, all caught.

**C2, the worker (uncommitted):** `supabase/functions/admissions-worker/` (`handler.ts`, `index.ts`, `templates.ts` and their tests), `[functions.admissions-worker] verify_jwt = false`. Header missing or empty: 401 before any database call. Database secret missing or empty: 503. SHA-256 digests compared in constant time. `MAIL_MODE` unset or unknown is off; `live` always sends to `https://api.resend.com`; `test` works only against the local stack and a local fake provider, and refuses a key starting `re_`. Batches of 10, 0.5 s apart, `Idempotency-Key: outbox-<row id>`. Only an error class and the HTTP status are stored, never the provider's text. `admissions-public` is unchanged: the worker imports its sweep and `storage.ts` by relative path (the planned move to a shared folder was not needed). 7 deliberate breaks, all caught, 20 in the slice.

**C3 (uncommitted):**

- `20261027120000_admissions_email_expiry.sql` (D-12n): status `expired`; `claim_admissions_emails` expires old rows first, under the same lock; the list accepts the status; `get_admissions_email_health` gains an expired count (dropped and re-created, same grants); housekeeping keeps expired rows 180 days. Probes X1 to X4 in `supabase/role-matrix/20261027120000_admissions_email_expiry.sql`.
- Frontend: `/admissions/emails` (Manager and Auditor; a health strip with waiting, failed, expired and address-limit counts and plain messages; a filter; expired rows struck through with "Expired, never sent" and a note that it will never be sent; Retry selected for a Manager, failed rows only). A confirmation status line on the application card. The sidebar link "Admissions Emails". The thank-you copy on `/inquiry` and `/apply` is now "You should receive a confirmation email shortly. If you do not see it within a few minutes, please check your spam folder or contact the school. Please still keep this reference number." ("these reference numbers" for several children).

**Verification (local only, test-runner end pass, 2026-10-20):** fresh reset; overload check clean; types regen identical; anon-executable 170; all 46 probe files green; `admissions-public` handler 51 of 51, integration 7 of 7, upload 7 of 7, submit 6 of 6; worker handler and templates 32 of 32, worker integration 5 of 5 (fake provider on 127.0.0.1, no real email); lint 0 errors and 13 warnings (baseline); `tsc` clean; vitest 194 of 194; build ok; no service role key in `dist/client`; Prettier clean; nothing staged. A manual local run of the real wiring (pg_cron, pg_net, the local gateway, `supabase functions serve`, a fake provider) sent one email and marked it sent. Golden payroll suite not run: no audit action and no payroll item changed.

**Not done:** nothing on hosted. The new staff page and status line have not been tried in a browser.

### Rollout handover: staff ID and slice 12 together (Eyram runs every step; none run here)

Do the steps in order. Stop at any step whose check doesn't match.

**0. Before you start.**

- C2 and C3 committed. `git status` clean, on `main`.
- Resend dashboard: Domains shows `mail.tcsch.edu.gh` Verified (SPF, DKIM and the return-path MX all green). Note the plan's daily and monthly limits. API Keys: create "tcs-erp-transactional", sending access only, domain `mail.tcsch.edu.gh`. Keep the key on screen only until step 5.
- Pick `MAIL_DAILY_CEILING`: the plan's daily limit minus what TCS OS, `updates.tcsch.edu.gh` and `erp.wilelikcompanyltd.com` may send the same day. On a 100 a day plan, 60 is a reasonable start.

**1. Staff ID positions query (read only).** Run the query in CONSTRAINTS.md, "Staff IDs on hosted", in the hosted SQL editor. Note any row marked "UNMAPPED after push"; a Manager sets its class after step 4 (Payroll setup, Positions).

**2. Backups.**

- Dashboard, Database, Backups: confirm a backup from today exists.
- A local data dump, kept outside the repo (it holds personal data, so keep it on an encrypted disk and delete it after the checks):

  ```sh
  npx supabase db dump --linked --data-only -f ~/tcs-backups/pre-slice-12-data.sql
  npx supabase db dump --linked -f ~/tcs-backups/pre-slice-12-schema.sql
  ```

**3. Dry run.**

```sh
npx supabase db push --dry-run
```

It must list exactly these four, in this order, and nothing else:
`20261026100000_hr_staff_numbers.sql`, `20261027100000_admissions_email_outbox.sql`, `20261027110000_admissions_scheduled_jobs.sql`, `20261027120000_admissions_email_expiry.sql`.

**4. Push.**

```sh
npx supabase db push
```

Then in the SQL editor (read only):

```sql
select jobname, schedule, active from cron.job where jobname like 'admissions-%' order by jobname;
-- 4 rows: admissions-housekeeping, admissions-mail, admissions-settle-offers, admissions-upload-sweep
select count(*) from vault.secrets where name = 'admissions_worker_secret';   -- 1 (never select the value)
select worker_url from public.admissions_email_worker;                        -- null
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');  -- 170
```

If `create extension pg_cron` was refused, enable pg_cron in Dashboard, Database, Extensions, and push again.

**5. Function secrets.** The Resend key, with your read -rsp method (it never appears on screen, in the shell history or in a file):

```sh
read -rsp "Resend API key (tcs-erp-transactional): " K; echo
npx supabase secrets set --env-file <(printf 'RESEND_API_KEY=%s\n' "$K"); unset K
```

If the CLI refuses the `/dev/fd` path, use a private temporary file instead and delete it at once:

```sh
read -rsp "Resend API key (tcs-erp-transactional): " K; echo
D=$(mktemp -d) && chmod 700 "$D" && (umask 077; printf 'RESEND_API_KEY=%s\n' "$K" > "$D/k.env")
npx supabase secrets set --env-file "$D/k.env"; rm -rf "$D"; unset K D
```

The others, with mail still off (example values; put in the real staff mailbox, ERP address and ceiling):

```sh
npx supabase secrets set \
  MAIL_MODE=off \
  MAIL_FROM='TCS Admissions <no-reply@mail.tcsch.edu.gh>' \
  MAIL_REPLY_TO=admissions@tcsch.edu.gh \
  ADMISSIONS_STAFF_EMAIL=admissions@tcsch.edu.gh \
  ERP_BASE_URL=https://<the ERP staff app origin> \
  MAIL_DAILY_CEILING=60
npx supabase secrets list   # names and digests only
```

`ERP_BASE_URL` must be https and is only used for the link in staff alerts.

**6. Worker URL (SQL editor).** No secret in it:

```sql
select public.set_admissions_worker_url('https://<project-ref>.supabase.co/functions/v1/admissions-worker');
select worker_url from public.admissions_email_worker;
```

From now on the sweep is called every 15 minutes and the mail job whenever an email is due (it sends nothing while `MAIL_MODE=off`). Until step 7 those calls get a harmless 404.

**7. Deploy the worker.** `admissions-public` is unchanged and is not redeployed.

```sh
npx supabase functions deploy admissions-worker --no-verify-jwt
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  "https://<project-ref>.supabase.co/functions/v1/admissions-worker" \
  -H 'content-type: application/json' -d '{"job":"mail"}'
# 401: refused without the secret, and nothing ran
```

**8. Check `net` is not exposed.** Dashboard, Project Settings, Data API, Exposed schemas: only `public` and `graphql_public` (never `net`). And from a terminal, with the public anon key:

```sh
curl -s "https://<project-ref>.supabase.co/rest/v1/http_request_queue?limit=1" \
  -H "apikey: <anon key>" -H "Accept-Profile: net"
# expected: an error saying the schema must be one of public, graphql_public (PGRST106)
```

**9. Frontend, last.**

```sh
cd frontend && ./scripts/deploy-production.sh
```

Never a bare `wrangler deploy` (CONSTRAINTS.md, "Deployment"). Both public switches stay closed.

**10. Hosted test with your own address.** Every record made here joins the go-live cleanup list.

1. Sign in as Manager. Admissions Emails shows the health strip with nothing waiting.
2. Open Public inquiries, send one enquiry at `/inquiry` with your own email and the child name "ZZ Test Do Not Process", then close Public inquiries. The thank-you page shows the new sentence.
3. Admissions Emails shows two rows Waiting (your confirmation and the staff alert). After 10 minutes the strip says sending may be switched off: that is right, mail is off.
4. Switch mail on (secrets apply to the next run, no redeploy):

   ```sh
   npx supabase secrets set MAIL_MODE=live
   ```

5. Within about two minutes both rows show Sent. In your inbox: From "TCS Admissions <no-reply@mail.tcsch.edu.gh>", subject "We have received your enquiry", your INQ reference, Reply-To `admissions@tcsch.edu.gh`. "Show original": SPF pass, DKIM pass for `mail.tcsch.edu.gh`, DMARC pass; not in spam. The staff alert reaches `ADMISSIONS_STAFF_EMAIL` with the link to the ERP.
6. Optionally the same with Public applications and `/apply` (fee proof file needed), then close Public applications again. The application page shows "Confirmation email: sent to 1 address."
7. Decide where to leave mail: off until real intake opens, or live. Either is safe: anything queued while off and older than 48 hours expires instead of sending.

**11. Reading the Resend log.** Resend dashboard, Emails: search by the recipient address. Each email shows its status (Delivered, Bounced, Complained, Suppressed) and its events; click one for the headers. The ERP stores Resend's id for each sent email: in the SQL editor,

```sql
select kind, status, provider_message_id, sent_at, last_error_class, last_http_status
from public.admissions_email_outbox order by created_at desc limit 20;
```

The id matches the one in the Resend email's page. Every ERP email also carries a `kind` tag. A "Mail settings problem" message on the staff page means Resend answered 401 or 403: check the key and the domain.

**12. Kill switch.**

```sh
npx supabase secrets set MAIL_MODE=off    # stop sending; emails wait as pending
npx supabase secrets set MAIL_MODE=live   # resume
```

Off takes effect at the next run (a batch already in flight, at most 10 emails, finishes). While off, nothing is claimed; when switched back on, anything that waited more than 48 hours is expired, not sent. The staff page shows such emails as Waiting while mail is off and moves them to Expired on the first run after it is switched on; the health strip says so. To stop the scheduled calls entirely (mail and sweep), clear the URL: `select public.set_admissions_worker_url(null);`, and set it again with step 6.

**13. After the rollout.** Staff ID test approvals happen locally only (CONSTRAINTS.md, "Staff IDs on hosted"). Tell me what was run and what you saw, so the docs can record it as reported.

### Slice 12 rollout reported (2026-10-20 and 2026-10-21)

Everything here is as reported by Eyram on 2026-10-20 and 2026-10-21. Nothing else from the handover is claimed as run or checked on hosted.

**Reported:**

- **Steps 2 to 4.** A hosted backup was taken. The dry run listed exactly the four migrations, and `db push` applied them: `20261026100000` (staff ID), `20261027100000`, `20261027110000` and `20261027120000`.
- **Step 1.** The hosted positions query showed all 16 positions mapped and 0 employees in any position.
- **Step 5.** The function secrets were set: the Resend key by the read -rsp method, `MAIL_MODE`, `MAIL_DAILY_CEILING=60`, `MAIL_REPLY_TO`, `ADMISSIONS_STAFF_EMAIL`, `ERP_BASE_URL` and `MAIL_FROM`.
- **Step 6.** The worker URL was set with `set_admissions_worker_url`.
- **Step 7.** `admissions-worker` was deployed (version 1). A request with no secret and one with a wrong secret both returned 401. A plain browser GET returns `{"error":"method"}` (the 405 for anything but POST).
- **Step 8.** Exposed schemas showed "2 of 2 schemas exposed"; the names were not itemised. "Automatically expose new tables" is off.
- **Step 9.** The frontend was deployed.
- **Step 10, hosted test.** A test enquiry queued; `MAIL_MODE` was set to live; the parent email arrived in Eyram's inbox. The staff alert to `admissions@tcsch.edu.gh` was suppressed by Resend after a Google NoSuchUser bounce, because that mailbox did not exist when Resend first tried. The mailbox now works (the first delivery to it was slow), the suppression was removed in Resend, and a second test enquiry delivered the staff alert.
- **What the ERP showed.** The staff email page showed the first staff alert as Sent although Resend later suppressed it, because bounce webhooks were deferred. Recorded as an accepted risk in "Slice 12 as built".

**Also reported (Eyram, 2026-10-21):** SPF, DKIM and DMARC all showed PASS on the delivered parent email (Gmail, "Show original"). `MAIL_MODE` was left live. Public inquiries and Public applications are both closed again.

**Not checked or not reported:** the matched-family application test (step 10, item 6); the staff ID click-through; whether `net` is absent from the exposed schemas by name (the count of 2 matches `public` and `graphql_public`, but the names were not itemised).

**New go-live items (2026-10-21):** before real intake, confirm `admissions@tcsch.edu.gh` is not on Resend's suppression list and that a test message reaches it quickly. Both hosted test enquiries and their outbox rows join the go-live cleanup list.

## Slice 13 — Lead capture (marketing-site endpoints)

**Delivers:**

- `admissions_leads`: `name`, `email`, `phone` (at least one required), `grade_interest`, `source` (server-set: `quick_interest_widget` | `pdf_gate_admissions_overview`), `consent_to_marketing` (default false; only an explicit true is honoured), `utm_source`, `utm_medium`, `utm_campaign` (truncated to 200 characters, never rejected), `bulk_email_unsubscribe_token_hash`, `bulk_email_unsubscribed_at`, `created_at`. Per `models.py:668-738` and `serializers.py:421-495`.
- `admissions-public` actions `quick_interest` and `pdf_gate` (Turnstile, `lead` rate bucket), which call service-role `capture_lead(p_source, p_payload)`. `pdf_gate` requires an email and enqueues a `pdf_gate` email with the attachment; both enqueue a staff alert.
- CORS for the marketing origins: `https://tcsch.edu.gh`, `https://www.tcsch.edu.gh`, and `^https://[a-z0-9-]+\.vercel\.app$` (`02-stack-and-schema.md:744-746`).
- A Manager and Auditor read list (no grade band applies, since `grade_interest` is free text).

**Not included:** bulk sending to leads.

**TCS OS leads (reported by Eyram, 2026-10-16):** real people exist in TCS OS as PDF gate leads, each with a consent to marketing flag (only some consented), and the PDF gate is in active use. Before TCS OS is retired, these leads and their consent flags must be moved to the ERP or deliberately kept. Bulk email (slice 14) must respect the consent and unsubscribe flags (Data Protection Act, 2012 (Act 843)). The overview PDF dropped from the slice 12 enquiry email returns here, behind the gate.

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

**Gate (2026-10-14):** admissions.tcsch.edu.gh does not move to the ERP until a confirmation email exists (slice 12) or Eyram accepts the gap in writing.

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
| 9 | none new (checkpoint 1 changes the return shape of `get_public_admissions_options()`, the approved gate; the anon-executable count stays 170) | `admissions-public`: `upload_session`, `upload_url` (checkpoint 1); `application` (checkpoint 2) | `open_application_upload_session`, `reserve_application_upload`, `claim_expired_application_uploads`, `finish_application_upload_cleanup` (checkpoint 1); `submit_application` (checkpoint 2) |
| 10 | `get_application_draft(text)`, `save_application_draft(text, jsonb, int, text, boolean)` | `admissions-public`: `draft_create`, `draft_submit` | `create_application_draft`, `submit_application_draft` |
| 11 | `get_offer_context(text)` | `admissions-public`: `offer_respond` | `respond_to_offer` |
| 13 | — | `admissions-public`: `quick_interest`, `pdf_gate` (cross-origin, CORS allow-list) | `capture_lead` |
| 14 | `bulk_email_unsubscribe(text)` | Worker `GET` and `POST /api/admissions/unsubscribe/$token/` | — |
| 15 | — | Worker host routing for `admissions.tcsch.edu.gh` (redirects, `410`s, lead-path proxy) | — |

Slice 12's mailer is secret-gated, not anon, but it's reviewed with the same rigour. There are no anon table grants, no anon storage policies (D-9a, decided), and no new anon select policy.

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
| D-6g | Student ID year | **Decided 2026-10-12, as recommended:** the calendar year of enrolment, Africa/Accra (TCS OS parity). **Answered 2026-10-12, closed:** IDs are YY (calendar year of enrolment in the system) + PP (group code) + NNNN (roll from 0001, restarting per year and per group). A student enrolled in 2026 who starts in 2027 keeps the 26 ID. Matches the build; see slice 6b. |
| D-6h | Unbanded or legacy grade at enrolment | **Decided 2026-10-12, as recommended:** refuse enrolment. Slice 7b adds a Manager-only grade-correction RPC. |
| D-6i | A student's second application | **Decided 2026-10-12, as recommended:** keep the existing ID; refuse a second enrolment in the same academic year; the enrolment stage audit row carries the ID. |
| D-6j | Decision change once an offer exists | **Decided 2026-10-12, changed from the recommendation:** a pending offer is withdrawn with a new `withdrawn` response (not `expired`); an accepted offer blocks the change; enrolled blocks it. |
| D-6k | Separate create and change RPCs for decisions | **Decided 2026-10-12, as recommended:** `record_decision` and `change_decision`. |
| D-6l | Offer expiry writes | **Decided 2026-10-12, as recommended:** no read path writes; a service_role sweep settles; slice 12 schedules it. |
| D-6m | `reset_offer` on a pending or accepted offer | **Decided 2026-10-12, as recommended:** allowed on pending, refused on accepted. |
| D-6n | Audit capacity and TTL changes | **Decided 2026-10-12, as recommended:** yes. |
| D-6o | Capacity academic year | **Decided 2026-10-12, as recommended:** exact text, no year list yet; carried to slices 7b and 8. |
| D-6p | Split slice 6 | **Decided 2026-10-12, as recommended:** 6a (decisions, capacity) and 6b (offers, enrolment). |
| D-6q | Staff read of `application_offers.token_hash` | **Decided 2026-10-12:** leave the table-level select grant as it is, no revoke. The hash is the SHA-256 of 32 random bytes and can't be reversed; the offer page compares hashes, so the hash alone gives no access; `application_offer_status` hides it; and a column-level grant would make `select *` on the table fail. Slice 7a carries this forward: the UI selects explicit columns and never selects `token_hash`. **Reversed 2026-10-12 for slice 7b1:** a column-level grant without `token_hash` (`20261018100000`). |
| D-7a | Staff route prefix | `/admissions`. Public routes keep TCS OS's bare paths. |
| D-8a | Bot-check placement | **Decided 2026-10-13:** Supabase Edge Function `admissions-public`; submit RPCs service-role-only. The service role key never reaches the browser, Cloudflare, or any `VITE_` variable. |
| D-8b | Turnstile keys | **Decided 2026-10-13:** a new ERP Turnstile widget with its own keys. The marketing-site widgets are decided in slice 13. |
| D-8c | Inquiry de-duplication | **Decided 2026-10-14:** no de-duplication on inquiries; revisit with slice 9's matching. |
| D-8d | Rate-limiting approach | **Decided 2026-10-13:** 20 per hour per IP hash (HMAC made in the Edge Function; no raw IP stored), a global cap of 200 per hour, and 5 per guardian email per day. Numbers kept in one place. The draft (120) and lead (60) numbers are not covered. |
| D-8e | CORS allow-list | **Decided 2026-10-13:** read from configuration: the workers.dev host and `app.tcsch.edu.gh` for now, plus localhost in local development only. Eyram confirms the final production host before cutover (D-15e). |
| D-9a | Upload mechanism | **Decided 2026-10-14, closed:** signed upload URL from the Edge Function, bound to a reservation. |
| D-9f | Bot check on uploads | **Decided 2026-10-14:** one Turnstile solve opens an upload session. |
| D-9g | Reservation lifetime and caps | **Decided 2026-10-14:** 6 hours, 8 files per session, 400 open reservations across everyone, kept with the rate numbers. **Changed 2026-10-15:** a reservation counts only if its file exists, or it is unexpired, empty and under 30 minutes old. |
| D-9h | Abandoned upload cleanup | **Decided 2026-10-14:** Edge Function sweep now; scheduled sweep in slice 12. |
| D-9i | Declaration IP | **Decided 2026-10-14:** left empty. |
| D-9j | Match past `inquiry` | **Decided 2026-10-14:** new application, flagged as a possible duplicate. |
| D-9k | Applications switch in Settings | **Decided 2026-10-14:** usable in 9a. |
| D-9l | Rate buckets | **Decided 2026-10-14:** `application_email` 5 per day, `upload_ip` 10 per hour, `upload_global` 100 per hour after Turnstile; submit shares `submit_ip` and `submit_global`. Draft and lead buckets not added yet. |
| D-9b | Anon re-submission overwriting existing data | **Decided 2026-10-13 (firmed):** a matched family never gains or changes guardians from an anonymous submission; differing details go in the staff-only snapshot. |
| D-9c | Matched application in a stage other than `inquiry` | **Changed 2026-10-13:** never refuse on a match. Flag it for staff; the response is identical. The 2026-09-29 recommendation (refuse the same year and grade) is superseded. |
| D-9d | Phone rule | **Revised 2026-10-14:** a plus sign and digits only, stored as sent. +233 needs exactly 9 digits (first not 0); another country code needs 8 to 15 digits in all. No spaces, dashes or letters. Replaces the same day's rule that removed spaces and dashes before checking. |
| D-9e | Application-fee proof | **Decided 2026-10-14:** compulsory in both forms and in `submit_application`; a missing fee proof is refused with the generic document refusal, and no outstanding row is created. |
| D-9m | Who may read the submission match flags | **Decided 2026-10-15:** readable like `application_documents`: Manager, Auditor, and Admissions Officer with the application in scope, with no health capability. No write grant for anyone. |
| D-9n | Turnstile on submit | **Decided 2026-10-15:** a second Turnstile solve, action `application`, after the upload session's solve. |
| D-9o | Repeat submit on a used session | **Decided 2026-10-15:** returns the same APP reference, and writes and counts nothing. |
| D-9p | Which family a submission matches | **Decided 2026-10-15:** the oldest family with a guardian email match that holds a child with the same name and date of birth; else the oldest such family. |
| D-10a | Draft TTL | **Decided 2026-10-21:** 30 days from the last save (sliding), at most 60 days from creation. The live TCS OS value check from the original plan is not reported. |
| D-10b | Draft purge | **Decided 2026-10-21:** wiped at expiry; deleted 30 days after expiry or submission; resume email rows kept 7 days. |
| D-10c to D-10l | Files, health answers, declaration and consent, save model, link minting, staff visibility, limits, expired versus failed | **Decided 2026-10-21.** See "Slice 10 as built (local only)". Individual IDs are not mapped here; D-10c is no files and D-10d is no health answers. |
| D-11a | Offer page shows the child's name before response | First name and grade. |
| D-12a | Email provider | **Decided 2026-10-16:** Resend HTTP API, a separate ERP key limited to `mail.tcsch.edu.gh`, as a function secret. |
| D-12b | Email queue | **Decided 2026-10-16:** outbox in the submit transaction, the `admissions-worker` Edge Function, pg_cron and pg_net. |
| D-12c | Plaintext token links in the outbox | Does not arise in slice 12: no body is stored and no email has a token link. Revisit for slices 10 and 11. |
| D-12d | GoTrue production SMTP | **Decided 2026-10-16:** out of slice 12. |
| D-12e to D-12o | Sender, content, PDF, recipients, limits, retries, retention, visibility, worker, maximum age, staff alert address | **Decided 2026-10-16 to 2026-10-20.** See "Slice 12 as built". |
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

## Go-live test data cleanup plan (written 2026-10-15, plan only)

**Status:** plan only. Nothing has been run, nothing has been written to any database, and nothing here has connected to hosted. Every step marked **[E]** is Eyram's. The run itself is a hand data migration on production, so it is a confirmation gate: the script is written, reviewed and dry-run before anything is committed.

**Facts the plan rests on (from the migrations):**

- **D-4f.** `application_documents.application_id` is `on delete restrict`, so an application with document rows can't be deleted until those rows are deleted first.
- **D-4d.** `storage.objects` has the `protect_objects_delete` trigger (`storage.protect_delete()`), which refuses SQL deletes. It can be bypassed with the `storage.allow_delete_query` setting, but that removes only the row and leaves the file in the storage backend, so it must not be used. Files are removed only through the Storage API or the dashboard.
- **Append-only audit log.** No API role has insert, update, delete or truncate on `audit_log` (slice 7c removed truncate). Only the table owner could delete from it, and doing so would break the convention. `audit_log.entity_id` is text with no foreign key, so deleting a record leaves its audit rows in place.
- **Cascades.** Deleting an application removes its health info, emergency contacts, notes, decision, offer and match flag rows. It sets `application_upload_sessions.submitted_application_id` and any other application's `application_match_flags.matched_application_id` to null. Deleting a student deletes its applications, and deleting a family deletes its guardians and students. No delete trigger exists on any admissions table, so the deletes write no audit row.
- Inquiries are `applications` rows at stage `inquiry`, with their own family, guardians and student. They never have documents.

**What exists or will exist on hosted, and how each kind is removed:**

| Kind | Known on hosted | Personal data | How it is removed | What gets in the way |
|---|---|---|---|---|
| Inquiries | "ZZ Test Do Not Process" (slice 8b); the C1 rollout test enquiry; any other slice 8 or 8b test | names, emails, phones, child details | delete the `applications` row, then its student and family if nothing else uses them | nothing; no documents |
| Applications with documents | the C3 hosted check (at least two); the 9a D-9k live test (done, reported by Eyram, 2026-10-15) | as above, plus health answers, emergency contact, signature | delete its `application_documents` rows first, then the application (cascades health, contacts, notes, decision, offer, match flag) | D-4f: document rows first |
| Stored files in `admissions-documents` | every file attached to a test application, plus any abandoned upload the sweep has not removed (the sweep only runs on a solved upload request, so with the switch closed nothing runs it) | the documents themselves (bank slips, report cards, vaccination cards) | Storage API or the dashboard, by exact path, **before** the SQL run | D-4d: no SQL delete |
| Families, guardians, students | one per test submission, or fewer where a match reused them | names, emails, phones, addresses, date of birth | delete students whose every application is a test, then families whose every student is a test (guardians cascade) | a guard must stop a family that also holds a real child |
| Match flags | one per matched test submission | guardian and student differences | cascade with the application; a flag on a non-test application that points at a test application must be zero (guard) | none |
| Upload sessions and reservations | one session per upload visit; one reservation per file started | none readable (token hashes, types, paths) | delete the reservations of every session made before the cut-off, then those sessions, once no file remains at their paths | reservations restrict session deletes |
| `audit_log` rows | stage changes, document status changes, any decision or offer on a test record, and every switch change (`admissions_settings_changed`) | references, stages, document types, staff ids; no names or emails written by these triggers | **kept.** They are true history: the tests happened. The cleanup is recorded in JOURNAL with the list of references removed, so a reader can tell those rows apart | append-only by design |
| `public_rate_limits` rows | counters for `submit_ip`, `submit_global`, `inquiry_email`, `application_email`, `upload_ip`, `upload_global` | none readable (HMAC keys, counts) | **left.** Windows are 1 hour or 1 day and stop counting on their own; nothing purges them yet (checkpoint 1 item (d)) | none |
| Reference counters | `INQ-2026` and `APP-2026` advanced by the tests | none | **left.** The first real reference continues the sequence, leaving a gap. Resetting would reuse references that the kept audit rows already name. Eyram's call; the recommendation is no reset | none |
| Staff IDs (HR, `20261026100000`, added 2026-10-16) | none: the migration is built locally only and not applied on hosted. After the push, any employee approved on hosted gets a 2026 ID. Rule for now: test approvals happen locally only | employee names through `employee_id`; the ID itself is not personal | **left, by rule, not by script.** `staff_numbers.employee_id` is `on delete restrict` and a trigger refuses deleting any issued row, so a test employee who got an ID can't be deleted. The `staff_number_issued` audit rows are kept (append-only). `staff_number_counters` only moves forward; any reset or ID removal needs its own reviewed hand script | the delete trigger, the restrict key and the append-only audit log; see CONSTRAINTS.md, the staff ID checklist item |
| `admissions_email_outbox` (slice 12) | the rows of the two slice 12 hosted test enquiries (reported by Eyram, 2026-10-21), and any later hosted test: a confirmation row and a staff alert row each (`application_ids` holds the test application ids, `params` their references) | the recipient email address and the references | deleted by the same script, matched by the test application ids | the Resend log keeps its own copy outside the database for its retention period |
| Application drafts (slice 10, built locally, not on hosted) | the test drafts and their links (`application_drafts`, `application_draft_links`), named by draft id from the hosted test; the `draft_resume` rows in `admissions_email_outbox`, matched by `draft_id`; and the Resend log copies of the test resume emails | the email address and the answers a test draft holds (names and test child details; never health answers, files or declaration) | deleted by the same script: link rows first, then drafts, then the outbox rows; no document rows or files are involved | housekeeping deletes a submitted draft 30 days after submission and wipes an expired one, but an open test draft must be deleted by hand; the Resend log keeps its own copy of each test resume email outside the database, for its retention period |
| Later slices (will exist) | slice 11 offer tokens, slice 13 leads, slice 14 campaigns and unsubscribe rows | varies | each slice that adds a table adds a row here before the cleanup is run | to be planned with each slice |

**Stop conditions (the script refuses, and Eyram decides separately):** a test record at `enrolled` or with a `student_id` (a STUDENT counter was used); an accepted offer; a target family that also holds a student with a non-test application; a guardian email of a target family that also appears in a non-test family; a file in the bucket attached to a non-test application; either public switch open.

**Which test records Eyram must identify by name.** The script works only from an explicit list of references. It never selects by a name, not even the shared test child name. Every test record on hosted uses the child name "ZZ Test Do Not Process" (reported by Eyram, 2026-10-15), and Eyram will list the references later. The dry run shows each listed record back with its names, so Eyram can check it before the commit run:

- the "ZZ Test Do Not Process" inquiry: its INQ reference;
- the C1 rollout test enquiry: its INQ reference;
- the 9a D-9k live-test application: its APP reference;
- the C3 hosted check: every APP reference it made (the second submission was a new application, so it has its own row);
- any other submission made on hosted by anyone testing;
- a statement that no real parent has submitted. Query D1 lists every switch change, so the times the switches were open can be read off it.

**Backups first [E]:**

1. **Database.** Make sure a dashboard backup exists for the day. Then take a local dump, kept off the repo and deleted after the verification period: `npx supabase db dump --linked --data-only -f <outside the repo>/pre-cleanup-data.sql`. The dump holds personal data, so it is kept encrypted or on an encrypted disk.
2. **Files.** Database backups do not include Storage files. Download every file that query D3 lists into a local folder before deleting it.
3. **The dry-run output.** Save the results of D1 to D7 as CSV next to the backup. That is the record of exactly what was removed.

**Dry run [E], read-only, in the SQL editor.** Replace `<refs>` with the list Eyram named, for example `array['INQ-2026-0001', 'APP-2026-0003']` (made-up references).

```sql
-- D1. Switches now, and every time they changed.
select public_intake_open, public_applications_open from public.admissions_settings;
select occurred_at, actor_id, before, after from public.audit_log
where action = 'admissions_settings_changed' order by occurred_at;

-- D2. Every admissions record on hosted. Before go-live, every row should be a test.
select a.inquiry_reference, a.application_reference, a.stage, a.created_at,
       s.full_name, s.date_of_birth, s.student_id,
       (select string_agg(g.email, ', ') from public.guardians g where g.family_id = s.family_id) as guardian_emails
from public.applications a join public.students s on s.id = a.student_id
order by a.created_at;

-- D3. Every file in the bucket and what it belongs to.
select o.name, o.created_at,
       coalesce(a.application_reference, a.inquiry_reference) as belongs_to,
       (a.inquiry_reference = any(<refs>) or a.application_reference = any(<refs>)) as is_target,
       r.consumed_at, r.cleaned_at
from storage.objects o
left join public.application_documents d on d.storage_path = o.name
left join public.applications a on a.id = d.application_id
left join public.application_upload_reservations r on r.storage_path = o.name
where o.bucket_id = 'admissions-documents'
order by o.created_at;

-- D4. Target applications and what the delete would cascade.
with t as (select id from public.applications
           where inquiry_reference = any(<refs>) or application_reference = any(<refs>))
select a.inquiry_reference, a.application_reference, a.stage,
       (select count(*) from public.application_documents x where x.application_id = a.id) as documents,
       (select count(*) from public.application_health_info x where x.application_id = a.id) as health,
       (select count(*) from public.application_emergency_contacts x where x.application_id = a.id) as contacts,
       (select count(*) from public.application_notes x where x.application_id = a.id) as notes,
       (select count(*) from public.application_decisions x where x.application_id = a.id) as decisions,
       (select count(*) from public.application_offers x where x.application_id = a.id) as offers,
       (select count(*) from public.application_match_flags x where x.application_id = a.id) as flags
from public.applications a where a.id in (select id from t);
-- Must be zero: flags on non-target applications that point at a target.
-- (same t) select count(*) from public.application_match_flags f
--   where f.matched_application_id in (select id from t) and f.application_id not in (select id from t);

-- D5. Students and families that would go, and the guard on shared emails.
--   students to delete: every application of the student is a target;
--   families to delete: every student of the family is in the list above;
--   guard: guardian emails of those families that also appear in any other family (must be none).

-- D6. Upload sessions and reservations made before the cut-off.
select count(*) filter (where consumed_at is not null) as used,
       count(*) filter (where cleaned_at is not null) as cleaned,
       count(*) filter (where consumed_at is null and cleaned_at is null) as open
from public.application_upload_reservations r
join public.application_upload_sessions s on s.id = r.session_id
where s.created_at < '<cut-off>';

-- D7. Audit rows that mention the targets (kept; listed for the record).
select occurred_at, action, entity_table, entity_id, before, after
from public.audit_log
where after ->> 'application_reference' = any(<refs>)
   or entity_id in (select id::text from public.applications
                    where inquiry_reference = any(<refs>) or application_reference = any(<refs>))
order by occurred_at;
```

D5 is written out in full in the script, with the same `<refs>`. The dry run also records the expected count for each table, which the commit run checks.

**Sequence [E]:**

1. Both public switches closed (D1), and kept closed until real intake opens, so no new record arrives between the dry run and the run.
2. The backups above.
3. Delete the files that D3 marks as targets, plus the unattached leftovers from test sessions, through the dashboard (Storage, `admissions-documents`, select by path, delete). For more than a handful of files, the Storage API call `DELETE /storage/v1/object/admissions-documents` with a `prefixes` list, the same call `storage.ts` uses, with the service role key kept out of shell history. Re-run D3: no target path remains.
4. Run the cleanup script in dry-run mode, then in commit mode (below).
5. Run the verification queries.
6. Record the date, the references removed and the counts in JOURNAL (the database keeps no audit row of the deletes).

**The cleanup script (recommended shape).** One reviewed SQL file, `docs/admissions/go-live-cleanup.sql`, written when the cleanup is due, in the style of `hosted-annex-setup.sql`, and run by Eyram in the SQL editor. One `do` block, so it is one transaction:

1. Constants at the top: the list of references, the cut-off time, the expected counts from the dry run, and `v_commit boolean := false`.
2. Guards, each raising an exception that names what failed: both switches closed; every named reference exists exactly once; the stop conditions above; no file remains in `storage.objects` at any target document path or at any reservation path being deleted; no non-target match flag points at a target.
3. Deletes in this order: `application_documents` of the targets (D-4f); the target `applications`; students whose every application was a target; families whose every student was removed; reservations of sessions made before the cut-off, then those sessions.
4. After each delete, the row count must equal the expected count, or it raises.
5. Re-select: no target reference remains.
6. If `v_commit` is false, it raises a final exception "dry run OK" with the counts, which rolls everything back. Eyram sets `v_commit := true` only after reading that message.

**Why a hand script and not a migration in `supabase/migrations/`:** a migration runs on every local `db reset` and on any future project, where the references don't exist. Its guards would then need a "do nothing if absent" branch, which weakens them, and the test references and names would sit in the schema history for good. A hand script runs once, where the records are, with strict guards. If Eyram prefers a migration so the run is in the history, it must do nothing unless every named reference is present, and the review must check that branch.

**Verification [E], after the commit run:**

- V1: no target reference remains in `applications`; no student, family or guardian from D5 remains.
- V2: each admissions table's row count equals its count before the run minus the expected deletes. If Eyram confirmed every record was a test, `applications`, `students`, `families` and `guardians` are empty.
- V3: D3 shows no target file and no unattached file from a test session.
- V4: the switches are still closed (D1).
- V5: in the staff app, the application list shows no test record, and the Audit Log page still loads and shows the kept rows.
- V6: the backups open (the dump file is readable and the downloaded files are present) before they are set aside.

**Before or after the privacy policy and the confirmation email?** After both, once, as the last step before real intake opens. Publishing the privacy policy changes the declaration copy and needs a hosted check, and slice 12's confirmation email needs a hosted end-to-end test. Both create more test applications and, for email, outbox rows. The slice 15 parity tests add more again. Cleaning before them means two reviewed production deletes instead of one. The order is: privacy policy published and linked; confirmation email in place (or Eyram's written acceptance of the gap); the last hosted test; this cleanup; verification; then real intake opens. One exception: if any test record holds a real person's details (a real email, phone, child name or a real document such as an actual bank slip), remove that record sooner, with the same script and guards.

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
- Test rows are deleted afterwards by the reviewed hand script in "Go-live test data cleanup plan" above, after the last hosted test and before intake opens. **[E]**

**Sequence:**

1. **[E] Prepare the ERP.** `npx supabase db push`; enable `pg_cron` and `pg_net`; `npx supabase functions deploy admissions-public admissions-mailer`; `npx supabase secrets set TURNSTILE_SECRET_KEY=… RESEND_API_KEY=… MAILER_SHARED_SECRET=… PUBLIC_BASE_URL=…`; add the Vault secret; deploy the frontend with `frontend/scripts/deploy-production.sh` (CONSTRAINTS.md, "Deployment"). That script currently passes only the two Supabase values into the build, so the slice that adds `VITE_TURNSTILE_SITE_KEY` must extend it to read that key from `frontend/.env.deploy` too. Leave `admissions_settings.public_intake_open = false`.
2. **[E] Stop TCS OS intake** (D-15d). Block the creating POSTs. Staff stop using the TCS OS admin. Leave unsubscribe and GET pages working.
3. **[E] Set roles and grant capabilities** to the real staff (fifth-role decision, D-2g, D-4b) through Settings. **[E] Open intake:** set `public_intake_open = true`.
4. **[E] DNS.**
   - Remove the Cloud Run domain mapping for `admissions.tcsch.edu.gh`, and attach `admissions.tcsch.edu.gh` as a Worker custom domain.
   - Point `app.tcsch.edu.gh` at the ERP Worker, if that's the ERP staff host (D-15e).
   - Add both hosts to the Turnstile widget and to Supabase Auth `site_url` and `additional_redirect_urls` for the staff host.
   - Change the `PUBLIC_APPLY_BASE_URL` function secret (resume email links, slice 10) to `https://admissions.tcsch.edu.gh`, and make sure `ADMISSIONS_ALLOWED_ORIGINS` includes `https://admissions.tcsch.edu.gh` (added 2026-10-21). Resume links already sent keep working only while their old host still reaches the same Worker.
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
