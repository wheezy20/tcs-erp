# TCS ERP — Constraints

Things that shape how this gets built, not just what gets built.

## Checklist — must be done before real go-live

- [x] PAYE band thresholds sourced directly from GRA's published schedule
      (gra.gov.gh) — done, `20260918` (see docs/JOURNAL.md). No longer
      placeholder values.
- [ ] The GRA table used is labeled "Year 2024" and has not been
      re-confirmed against any later revision — recheck before real
      go-live. Also unresolved from the same GRA notes: overtime income
      for qualifying junior employees may need a flat concessionary rate
      instead of graduated PAYE, and bonus income has an unmodeled flat
      5% final-tax treatment — see the "Statutory accuracy" section below
      for both; not building either without confirmation first.
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
  schedule** (gra.gov.gh, labeled "Year 2024") as of `20260918` — no
  longer placeholder values (see docs/JOURNAL.md). `paye_bands` stores
  **monthly** thresholds, confirmed against `create_payslip()`'s own
  computation (taxable income is built from monthly figures throughout,
  never annualized). GRA's table has an internal rounding inconsistency:
  its band widths sum arithmetically to GHS 50,416.67, but the table's own
  top-band row is explicitly labeled "Exceeding 50,000.00" — GHS 50,000 is
  used as authoritative here, per GRA's literal stated threshold, not the
  arithmetic sum. **Not yet re-confirmed against any GRA revision
  published after this "Year 2024" table.**
- **Overtime and bonus income may need non-graduated tax treatment —
  unconfirmed, not built.** Per GRA's monthly PAYE schedule's own
  completion notes (items 23–24): overtime pay for a *qualifying junior
  employee* (income ≤ GHS 800/month or GHS 9,600/year) may be taxed at a
  separate concessionary flat rate rather than folded into the graduated
  bands the way `create_payslip()` currently treats it — every overtime
  cedi is taxed as ordinary graduated income today, which could be wrong
  specifically for TCS's lower-paid staff. Separately, and lower priority:
  bonus income reportedly has its own unmodeled flat 5% final-tax
  treatment (up to 15% of annual basic), also not implemented. Neither is
  built pending confirmation from TCS's accountant or GRA directly — this
  is a "know it might be wrong" flag, not a fix.
- Rates and bands are stored as **editable database rows, never
  hardcoded constants** — a correction or an annual update should be a
  data change, not a code deploy.
- Some staff (e.g. National Service personnel, other temporary/contract
  staff) are **exempt from some or all of SSNIT/PAYE/Tier 2**. This is
  handled per-employee via boolean flags on `employee_pay_config`
  (`pays_ssnit`, `pays_tier2`, `pays_paye`), independently toggleable
  (renamed from `staff_pay_config` in `20260909130000`).

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

**Admissions capabilities (decided 2026-09-29) — not a fifth role.**
TCS OS's admissions has staff shapes the four roles don't express on
their own: the `can_decide` holder, grade-band coordinators scoped to
Preschool/Primary/JHS applicants, and the people allowed to see child
health data. These are modelled as a **small capabilities layer on top
of the four roles**, not as a new role:

- a `can_decide` flag per staff member (who may record a decision /
  generate an offer);
- a list of grade bands per staff member (a coordinator sees and works
  only applicants whose grade falls in their bands, resolved live from
  the applicant's current grade, never stored per application);
- a **separate gate for child health data**, independent of both of the
  above. Holding a role, `can_decide`, or a grade band never implies
  health-data access on its own.

Why this isn't a fifth role: `staff.role` still answers "what kind of
access does this person have across the whole ERP", and every existing
predicate keeps working unchanged. The capabilities only **narrow or
unlock specific admissions actions** for someone who already holds one
of the four roles; they never grant anything outside admissions and
never stand in for a role. Each capability is **ungranted by default**:
granting one is a deliberate human decision, not a migration default
(same rule TCS OS followed for `can_decide`, `can_view_health_info` and
`can_send_bulk_email`). The exact shape (columns vs a side table, which
role may hold which capability) is settled in
`docs/admissions/PORT-PLAN.md` and recorded in DESIGN.md when built.

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
