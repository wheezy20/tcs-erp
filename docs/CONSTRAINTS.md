# TCS ERP — Constraints

Things that shape how this gets built, not just what gets built.

## Checklist — must be done before real go-live

- [x] PAYE band thresholds sourced directly from GRA's published schedule
      (gra.gov.gh) — done, `20260918` (see docs/JOURNAL.md). No longer
      placeholder values.
- [ ] The GRA table used is labeled "Year 2024" and has not been
      re-confirmed against any later revision — recheck before real
      go-live. GRA has published "Year of Assessment 2026" bands,
      effective 1 September 2026; Eyram confirmed them (2026-09-29).
      The new set is built in the repo and applied locally
      (`20260929120000_paye_bands_2026.sql`); the hosted project gets it
      on `npx supabase db push`. The Year 2024 set now governs only
      payroll months before 2026-09. Overtime concession: decided
      not applicable to TCS. Bonus rule: its own later slice. See "Statutory
      accuracy" below.
- [ ] Confirm the SSNIT / Tier 2 split (0.5% / 13% / 5%) against an
      official SSNIT source — currently only confirmed verbally against
      the school's current practice (see "Statutory accuracy" below).
      Note the employer's 13% is now computed, snapshotted
      (`payslips.ssnit_employer`) and posted (Dr 5145 / Cr 2310) as of
      `20260909120000` — only the *rate* still needs the official check.
- [ ] `supabase/seed.sql` is still local-dev-only (Wilelik retail demo +
      TCS demo people). Production uses `supabase/seed.production.sql`
      instead — reference/config only, zero demo people. Before go-live,
      run it once against the hosted DB (`psql "$PROD_DB_URL" -f
      supabase/seed.production.sql`) after `supabase db push`.
- [ ] Create a dedicated hosted Supabase project for TCS and run
      `scripts/bootstrap-production-manager.sh` for the first real Manager
- [ ] Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the
      **Cloudflare Workers build environment** (build-time — see below),
      then `wrangler deploy` from a Node ≥ 22 runner with a CF API token.
- [x] Real TCS logo / favicon assets — done (favicons + manifest in
      `frontend/public/`, logomark in the sidebar + login).
- [x] Re-theme `--primary` from indigo to the brand deep teal (`#005e61`)
      — done, `20260916` (see docs/JOURNAL.md).
- [ ] A true 48×48 favicon (currently downscaled) and a dark-mode
      logomark variant are still outstanding — see docs/JOURNAL.md.
- [ ] Admissions cutover (Phase 2, see PLANNING.md). TCS OS's ~3 real
      admissions records, and their attached Storage files, are
      hand-migrated into this project's hosted Supabase and checked
      against the TCS OS originals. admissions.tcsch.edu.gh then
      redirects to this ERP. TCS OS is shut down only after both are
      done and confirmed.
- [x] **`deposit_number_counters` has RLS off** (`20260901100000`), and
      Supabase's default privileges give `anon` full table privileges on
      it. So anyone holding the public anon key, and every staff role
      including Auditor, can insert/update/delete customer-deposit
      numbering directly through the Data API. Found 2026-09-29 while
      building the role-matrix harness, and confirmed by a probe (an
      anon INSERT got past grants and RLS). Fix it in its own migration:
      enable RLS with policies matching `invoice_number_counters`, and
      revoke `anon`. It isn't fixed yet because it wasn't in that
      session's scope. It must be fixed before the ERP serves
      production traffic.
      — done in the repo and locally, `20260929100000_deposit_number_counters_rls`
      (2026-09-29): RLS on, the same four policies as
      `invoice_number_counters`, and `anon` revoked. Verified by
      `supabase/role-matrix/20260929100000_deposit_number_counters_rls.sql`
      (no mismatches). The hosted project gets it only when Eyram runs
      `npx supabase db push` (see docs/JOURNAL.md).

## Data safety

- **This project must never connect to Wilelik's real Supabase project.**
  Wilelik (the original, at `~/projects/wilelik-erp`) holds Eyram's dad's
  actual business data. TCS ERP needs its own, separate Supabase project
  before any real staff/student/financial data goes into it. As of the
  rebrand, no live connection exists either way — `supabase/config.toml`
  only sets a local Docker container name — but this needs to stay true
  as deployment gets set up.
- **This project must never connect to TCS OS's Supabase project
  either.** Three hosted Supabase projects exist across Eyram's work:
  this one, Wilelik's, and TCS OS's. Admissions
  data comes across by a reviewed, one-off hand migration (see below),
  never by pointing this app's URL/keys at TCS OS's database or
  buckets, and never by sharing a connection string.
- `supabase/seed.sql` currently contains **Wilelik's dummy retail data**
  (building-materials products, Ghanaian customer/supplier names) plus TCS
  demo people. It is **local-dev only** — `config.toml`'s `[db.seed]
  sql_paths` lists only `./seed.sql`, and that list drives `supabase db
  reset` only; no seed file runs on `supabase db push`. Production
  reference/config data comes from the migrations (chart of accounts,
  statutory rates, PAYE bands, `payment_providers`, `positions`,
  `departments` — all seeded idempotently by their own migration) plus
  **`supabase/seed.production.sql`**, run once by hand against the hosted
  DB. That file adds only the branch-scoped rows the migrations cannot
  seed before a branch exists (the branch itself, `expense_categories`,
  `expense_category_accounts`, `allowance_types`) and contains zero demo
  people, logins, or transactions.

## Deployment (Cloudflare Workers)

- The frontend deploys to **Cloudflare Workers** via
  `@cloudflare/vite-plugin` (`frontend/vite.config.ts` +
  `frontend/wrangler.jsonc`). Build with `npm run build`, deploy with
  `wrangler deploy` (Node ≥ 22, CF API token). See STACK.md.
- **`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` are build-time, not
  runtime.** Vite statically replaces `import.meta.env.VITE_*` at build
  time (the Lovable config wrapper's `envDefine` step does this from
  `loadEnv`), so the Supabase URL and anon key are **baked into the
  JS bundle** during `npm run build`. They must be present as environment
  variables in the Cloudflare **build** step. Setting them only as Worker
  runtime secrets (`wrangler secret put`) does nothing — the code never
  reads `env` for them, and by deploy time the bundle is already frozen.
  The var name the code reads is `VITE_SUPABASE_ANON_KEY` (see
  `frontend/src/lib/supabase.ts`); a variable named `VITE_SUPABASE_KEY` is
  ignored. The anon key is a public client credential (RLS is the real
  boundary), so baking it in is expected; never bake in a `service_role`
  key.

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
- **PAYE band thresholds are sourced directly from GRA's published
  schedules**, not hardcoded. `paye_bands` stores **monthly** thresholds,
  confirmed against `create_payslip()`'s own computation (taxable income is
  built from monthly figures throughout, never annualized). Two sets:
  - **"Year 2024"**: effective 2025-01-01, sourced `20260918` (see docs/JOURNAL.md).
  - **"Year of Assessment 2026"**: effective 1 September 2026,
    confirmed by Eyram 2026-09-29, built 2026-09-29. Band sets are selected
    by the payroll month (`max(effective_from) <= make_date(year, month, 1)`).
  GRA's 2024 table has an internal rounding inconsistency: its band widths sum
  arithmetically to GHS 50,416.67, but the table's own top-band row is
  explicitly labeled "Exceeding 50,000.00" — GHS 50,000 is used as
  authoritative here, per GRA's literal stated threshold, not the arithmetic
  sum.
- **The overtime concession does not apply to TCS (decided 2026-09-29,
  confirmed by TCS's accountant).** GRA's concessionary overtime rate is
  for qualifying junior employees only. Qualifying also requires annual
  income of GHS 18,000 or less. TCS's overtime stays ordinary income
  taxed on the graduated bands, which is what `create_payslip()` already
  does. Don't build a concessionary overtime path. (This supersedes the
  earlier "unconfirmed" flag, which quoted a GHS 800/month, 9,600/year
  threshold from the Year 2024 notes.)
- **GRA's bonus rule is its own later slice (decided 2026-09-29), not
  built yet.** A bonus up to 15% of annual basic salary is taxed at a
  flat 5%. Any excess is added to employment income and taxed on the
  graduated bands. Until that slice lands, the engine has no bonus
  treatment.
- **Extra classes stay a normal taxable allowance (decided 2026-09-29)**
  until TCS's accountant confirms in writing how they're classified.
  Don't give them special tax treatment without that written
  confirmation.
- Rates and bands are stored as **editable database rows, never
  hardcoded constants** — a correction or an annual update should be a
  data change, not a code deploy.
- Some staff (e.g. National Service personnel, other temporary/contract
  staff) are **exempt from some or all of SSNIT/PAYE/Tier 2**. This is
  handled per-employee via boolean flags on `employee_pay_config`
  (`pays_ssnit`, `pays_tier2`, `pays_paye`), independently toggleable
  (renamed from `staff_pay_config` in `20260909130000`).
- **National Service staff are fully exempt (decided 2026-09-29):** no
  SSNIT, no Tier 2 and no PAYE. In practice that means `pays_ssnit`,
  `pays_tier2` and `pays_paye` are all false on their
  `employee_pay_config`.

## Staff roles (as of 20260909090000; fifth role decided 2026-09-29)

Four roles are live on `staff.role`:

- **Manager:** full write everywhere.
- **Accountant:** Manager-equivalent write on Payroll, Accounting and
  Expenses; read-only elsewhere.
- **Auditor:** read-only everywhere the old combined role could read.
- **Attendant:** Sales, POS and invoices; no finance access.

They're enforced by RLS plus the `can_write()`,
`require_writable_role()` and `require_finance_writer()` predicates (see
DESIGN.md). When adding a new table, decide which roles it's for and
gate it with the matching predicate. Don't hand-roll a per-table role
check.

**A fifth role, Admissions Officer, is built locally (2026-09-29, slice
1b-ii)** in migration `20260929130000` and the frontend. It's awaiting
Eyram's review and not yet committed or deployed. This is a **deliberate, confirmed exception**
to the earlier "don't invent a fifth role" rule, and it supersedes the same day's
earlier decision to model admissions as capabilities on the four roles alone.

The reason is that none of the four fits an admissions coordinator:

- Attendant would bring store write access.
- Accountant would bring payroll and finance write access.
- Manager is everything.

An Admissions Officer gets **baseline access to admissions tables
only**, and nothing in finance, payroll, HR or the store. Attendant
stays the store role.

**Adding a role (this one, and any future one).** More roles are
expected as the ERP grows to cover other school functions: academics,
transport and so on. A new role is never added on a slice's own
authority. It needs:

1. **Eyram's explicit decision**, recorded in this section with its date
   and the reason no existing role fits.
2. **Its own slice**, before anything uses the role. That slice covers:
   - the `staff_role_check` constraint;
   - the guard predicates;
   - `invite-staff`'s `ALLOWED_ROLES`;
   - `handle_new_staff_signup`;
   - the frontend role type, the Settings dropdown and sidebar gating;
   - a dev account in `seed-local-dev-staff.sh`;
   - a column in `scripts/role-matrix.sh`.
3. **Allowlist guards, never denylists.** The live `can_write()` (not
   Accountant or Auditor) and `require_writable_role()` (not Auditor)
   are denylists, so a new role would silently inherit store write
   access. The first new-role slice converts them to allowlists. After
   that, every predicate names the roles it admits.
4. **A read-exposure audit.** List every `is_active_staff()` policy and
   staff-only function the new role would pass. That's 24 tables and
   `compute_day_totals` as of 2026-09-29; the table is in PORT-PLAN.md
   slice 1b. Decide each one.
5. **Role-matrix probes proving the role is denied** everywhere outside
   its module, and that every existing role's result is unchanged.

**Admissions capabilities (decided 2026-09-29).** Capabilities narrow or
unlock actions *inside* admissions, on top of the role:

- **`can_decide`** (record a decision, generate an offer). Held by
  Manager or Admissions Officer.
- **Grade bands.** A coordinator sees and works only applicants whose
  grade falls in their bands. Held by Admissions Officer only;
  Accountant is excluded because that role carries payroll and finance
  write access. Bands resolve live from the **grade applied for**
  (`applications.year_group_applied_for`), never from the child's
  current grade, and are never stored per application. That's what TCS
  OS does (`admin.py:209`), confirmed as D-2c. A full officer is marked
  by an explicit `all_grades` flag, which is exclusive with a band list
  and also covers unbanded grades (D-2g, decided 2026-09-29).
- **A separate gate for child health data.** Any role may hold it. It's
  independent of the role, `can_decide` and grade bands: none of those
  ever implies health-data access.

Capabilities never grant anything outside admissions and never stand in
for a role. Each is **ungranted by default**: granting one is a
deliberate human decision by an active Manager, audited, never a
migration default. That's the same rule TCS OS followed for
`can_decide`, `can_view_health_info` and `can_send_bulk_email`. The
storage shape (a side table) is decided and recorded in PORT-PLAN.md,
and goes into DESIGN.md when built.

## Architecture

- **TCS has two campuses, Main and Annex (decided 2026-09-29).** Each
  is one row in `branches`, and every campus-scoped table uses the
  existing `branch_id` for it. No separate `campus` table or column.
  This replaces the earlier "single-campus now" framing, which was
  wrong for TCS. It came from Wilelik's single-branch rollout, and TCS
  OS's admissions already treats Main and Annex as separate seat pools.
  `seed.production.sql` currently creates a single "Treasures Christian
  School" branch. Renaming that row to Main and adding Annex, and
  deciding which existing screens (payroll, expenses, accounting) need a
  campus filter versus staying school-wide, are admissions port-plan
  items, not assumed here.
- **This ERP is the target system; TCS OS is being retired into it**
  (reversed 2026-09-29; the old plan was to merge this ERP into TCS OS).
  See the "TCS OS retirement & admissions port" section below.

## HR expansion beyond payroll (as of 20260919)

Building HR out beyond Payroll, informed by TCS's existing Google Apps
Script HR system (field names, workflow logic, email conventions —
**not** its security model, which is a public Google Form with no RLS).
Recruitment (Careers form, Applicant pipeline, Interview Tracker) stays
on that existing Apps Script system for now — out of scope here, to be
migrated in its own later phase.

**Explicitly deferred, uniformly, per Eyram's confirmed decision**: Leave,
KPI & Performance, Training, Disciplinary, and Exit & Offboarding. All
five exist in the source spreadsheet as full column structures with
seeded dropdown enums, but none has any actual working logic behind it
(no Apps Script automation touches any of them) — there's nothing
"existing" to preserve, just a column shape to copy later if any of
these becomes real work. Not building placeholder schema for features
that were never functioning anywhere. If/when one of these becomes real,
the source spreadsheet's own tab (`05 LEAVE`, `06 KPI & PERFORMANCE`,
`07 TRAINING`, `08 DISCIPLINARY`, `09 EXIT & OFFBOARDING`) is the
reference for field names and dropdown enums to start from.

## TCS OS retirement & admissions port (as of 2026-09-29)

Direction reversed on 2026-09-29: **TCS OS (Django, `~/projects/tcs-os`)
is retired into this ERP**, not the other way round. See PLANNING.md and
docs/JOURNAL.md.

- **TCS OS is read-only reference.** Sessions in this repo never edit,
  migrate, deploy, or run management commands in `~/projects/tcs-os`.
  Its `docs/` (especially `docs/admissions/` and `docs/DESIGN.md`'s
  payroll section) are the source of truth for the business rules
  being ported. Read them, cite them, and don't rewrite them.
- **Port the logic, not the code.** Django models, views, admin
  actions, and Cloud Tasks wiring don't carry over. Each rule gets
  re-expressed with this repo's conventions (DESIGN.md): plpgsql RPCs,
  RLS, and server-forced identity columns. When a TCS OS rule is
  enforced in `Model.save()`, the port has to enforce it in the
  database (an RPC or trigger), not in the React client.
- **HR and Finance are not ported.** TCS OS's versions came from this
  repo. Its verified payroll parity results (Emmanuel Ansah, basic
  6,500 → net 5,008.37; Abena Konadu Owusu and Yaw Darko Asamoah
  matched to the cent) are carried back as **regression-test cases**
  for `create_payslip()`. Its untested paths (allowances, overtime,
  fines, IOU, higher PAYE bands) are carried back as **known coverage
  gaps**, not assumed correct.
- **Real admissions data: ~3 records, migrated by hand.** They go into
  this project's own hosted Supabase project, along with any attached
  documents in TCS OS's Storage buckets. This is a one-off, reviewed
  step run by Eyram: a script or SQL run by hand against
  production, never something wired into `supabase db push`,
  `seed.sql`, or `seed.production.sql`. These records include real
  child health information and guardian contact details, so their
  contents never go into docs, the journal, commit messages, test
  fixtures, or chat transcripts.
- **admissions.tcsch.edu.gh must keep working until cutover.** It stays
  served by TCS OS's Cloud Run deployment until the ERP's admissions
  reaches parity. At cutover it becomes a **redirect** to this ERP's
  public admissions routes rather than being turned off. Links already
  sent to parents must keep resolving: offer accept/decline tokens,
  application save-and-resume drafts, and bulk-email unsubscribe links
  (RFC 8058 one-click POST included). Either those tokens migrate with
  their records, or TCS OS keeps honouring them until they expire; the
  port plan decides which. Separately, TCS OS's own journal records
  that `app.tcsch.edu.gh` gets repointed from Cloud Run to this ERP.
  Both are DNS/infra steps Eyram runs.
- TCS OS stays live and unmodified until cutover. **No dual-intake
  window (confirmed 2026-09-29):** TCS OS and this ERP never both
  accept real admissions submissions at the same time. The ERP's public
  admissions forms don't take real submissions until TCS OS's intake is
  switched off, and the hand migration of TCS OS's records happens
  after that point, so no real record ever exists in both places or
  needs reconciling. The port plan's cutover slice orders the steps.

## Ghana-specific context worth keeping in mind

- Currency: GH₵ throughout.
- Academic year: three-term structure (First/Second/Third Term), not
  semesters — relevant once Academic Settings/Exams get built.
- SMS: Mnotify is the common Ghana-specific aggregator (seen in Royal
  Avenue's system) — worth considering over Twilio-only when
  Communication gets built.
