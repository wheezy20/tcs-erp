-- Payroll schema (TCS ERP — Phase 1: Accounting/Finance focus).
--
-- Adds staff pay configuration, a flexible allowance-type system, editable
-- statutory rate/band tables (SSNIT, Tier 2, PAYE), and payroll
-- runs/payslips + a server-side calculation function.
--
-- Conventions this follows (see docs/DESIGN.md):
--   * Effective-dated config rows instead of a single mutable row, so a
--     raise or a rate correction never silently rewrites a historical
--     payslip. A payslip references the config row that was active at the
--     time it was generated.
--   * All financial calculation server-side in plpgsql — the client never
--     computes tax or a statutory deduction itself.
--   * Create-can't-overwrite: create_payroll_run() / create_payslip() take
--     no client-supplied id and never upsert. delete_payslip() is a
--     separate, explicitly-named function, Draft-runs only.
--   * Server-forced identity: payroll_runs.created_by is set from
--     auth.uid() by create_payroll_run(), never trusted from the client.
--   * Three-tier RLS (docs/DESIGN.md): Manager full read/write/delete;
--     Accountant/Auditor read-only, no exceptions; Attendant no access at
--     all. Same shape as accounts / journal_entries — payroll (individual
--     salaries) is the most sensitive data in the app.
--   * Explicit grants for all three roles, decided per table below;
--     service_role always gets full CRUD.
--
-- Deliberately NOT in this migration (a follow-up once the core flow works
-- end to end): posting a payroll run to the accounting ledger. See the
-- TODO in create_payroll_run() / near payroll_runs.status.

-- ---------------------------------------------------------------------
-- Allowance types: a configurable list (Extra Classes, Transport, etc.)
-- instead of fixed columns, same instinct as expense_categories — the
-- school edits this list itself as pay structure changes, no migration
-- needed to add a new allowance type later.
-- ---------------------------------------------------------------------
create table public.allowance_types (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete cascade,
  name text not null,
  -- Whether this allowance counts toward taxable_income. Transport is
  -- commonly non-taxable up to a statutory cap in Ghana; that nuance is
  -- deliberately NOT modeled here (no cap field) — this is a simple
  -- taxable/non-taxable flag. Revisit if a per-allowance cap is ever
  -- actually needed; don't guess at GRA's exact transport-allowance
  -- relief rules without checking them first.
  taxable boolean not null default true,
  position integer not null default 0,
  unique (branch_id, name)
);

create index allowance_types_branch_id_idx on public.allowance_types (branch_id, position);

-- ---------------------------------------------------------------------
-- Staff pay configuration. Effective-dated (effective_to null = current)
-- rather than a single mutable row on `staff`, so a salary raise doesn't
-- erase what someone was actually paid last month — payslips reference
-- the config row that was active at the time, not whatever is current
-- today. Editing a staff member's pay = close the current row
-- (effective_to = day before the change) and insert a new open-ended one.
-- ---------------------------------------------------------------------
create table public.staff_pay_config (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff (id) on delete restrict,
  position text,
  department text,
  bank text,
  account_no text,
  basic_salary numeric(12, 2) not null check (basic_salary >= 0),
  -- Per-staff statutory participation. National Service personnel and
  -- other temporary/contract staff commonly pay none of these — default
  -- true (permanent-staff assumption) but every one of the three is
  -- independently toggleable, since a staff member could conceivably be
  -- exempt from one but not the others.
  pays_ssnit boolean not null default true,
  pays_tier2 boolean not null default true,
  pays_paye boolean not null default true,
  effective_from date not null,
  effective_to date,
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create index staff_pay_config_staff_id_idx on public.staff_pay_config (staff_id, effective_from desc);

-- Only one "current" (effective_to is null) config per staff member at a
-- time — prevents accidentally leaving two open-ended rows after an
-- update.
create unique index staff_pay_config_one_current_idx
  on public.staff_pay_config (staff_id)
  where effective_to is null;

-- ---------------------------------------------------------------------
-- Standing allowances per staff (e.g. "this teacher gets Transport
-- GHS 200/month by default"). The generate-payslip UI pre-fills a run's
-- payslip lines from these, but each month's actual amount is editable at
-- the payslip-line level without changing the standing default.
-- ---------------------------------------------------------------------
create table public.staff_allowances (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff (id) on delete restrict,
  allowance_type_id uuid not null references public.allowance_types (id) on delete restrict,
  default_amount numeric(12, 2) not null check (default_amount >= 0),
  effective_from date not null,
  effective_to date,
  check (effective_to is null or effective_to >= effective_from)
);

create index staff_allowances_staff_id_idx on public.staff_allowances (staff_id);

-- ---------------------------------------------------------------------
-- Statutory rates: SSNIT and Tier 2, employee and employer side. Stored
-- as an editable, effective-dated table rather than constants, since
-- these are set by national policy and change — a rate correction should
-- be a data edit, not a code deploy.
--
-- The employee split confirmed for this school (see docs/CONSTRAINTS.md):
-- SSNIT 0.5% employee + 13% employer, Tier 2 5% employee (employer-side
-- Tier 2 is 0 here). 0.5% + 5% = the standard 5.5% total employee
-- contribution, split across the two schemes.
--
-- The seed rows at the bottom of this migration are PLACEHOLDERS. Verify
-- the exact current split directly against SSNIT/GRA before relying on
-- this for real payroll.
-- ---------------------------------------------------------------------
create table public.statutory_rates (
  id uuid primary key default gen_random_uuid(),
  ssnit_employee_pct numeric(5, 3) not null,
  ssnit_employer_pct numeric(5, 3) not null,
  tier2_employee_pct numeric(5, 3) not null,
  tier2_employer_pct numeric(5, 3) not null default 0,
  effective_from date not null unique,
  created_at timestamptz not null default now()
);

create index statutory_rates_effective_from_idx on public.statutory_rates (effective_from desc);

-- ---------------------------------------------------------------------
-- PAYE bands: graduated tax bands, editable and effective-dated the same
-- way. Bounds are CUMULATIVE taxable-income thresholds (band N runs from
-- lower_bound to upper_bound of total taxable income); upper_bound null
-- means "and above" (the top band). create_payslip() walks them ascending
-- and taxes each band's slice at its own rate.
--
-- Seed rows at the bottom are PLACEHOLDERS — real numbers must come from
-- GRA's published schedule before go-live (docs/CONSTRAINTS.md).
-- ---------------------------------------------------------------------
create table public.paye_bands (
  id uuid primary key default gen_random_uuid(),
  effective_from date not null,
  lower_bound numeric(12, 2) not null,
  upper_bound numeric(12, 2),
  rate numeric(5, 3) not null,
  band_order integer not null,
  check (upper_bound is null or upper_bound > lower_bound),
  unique (effective_from, band_order)
);

create index paye_bands_effective_from_idx on public.paye_bands (effective_from desc, band_order);

-- ---------------------------------------------------------------------
-- Payroll runs: one per branch per month. status goes Draft -> Posted;
-- payslips can only be added to / removed from a Draft run.
--
-- TODO (follow-up migration): posting a run should create the payroll
-- journal entry in the accounting ledger (a post_payroll_run() function
-- alongside the other post_*_journal_entry() functions), kept as an
-- explicit step rather than auto-posting — same "don't silently touch the
-- ledger" discipline as everything else in Accounting. Until that exists,
-- 'Posted' is just a lock against further payslip edits.
-- ---------------------------------------------------------------------
create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  month integer not null check (month between 1 and 12),
  year integer not null check (year >= 2020),
  status text not null default 'Draft' check (status in ('Draft', 'Posted')),
  -- Server-forced by create_payroll_run() from auth.uid(); nullable so the
  -- superuser/seed context (no auth.uid()) can insert without a fake staff
  -- uuid, same as accounts.created_by post-seed_gap.
  created_by uuid references public.staff (id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (branch_id, month, year)
);

create index payroll_runs_branch_period_idx on public.payroll_runs (branch_id, year desc, month desc);

-- ---------------------------------------------------------------------
-- Payslips: one row per staff per run. Columns mirror the existing
-- Google Sheet directly (Basic Salary, Overtime, Total Earning, Gross
-- Salary, Taxable Income, Tax, Tier 2, SSNIT, Fines, IOU, Deductions,
-- Net Pay) so the transition off the sheet feels like the same system,
-- not a new one. All amounts are snapshotted at generation time by
-- create_payslip() — later edits to staff_pay_config or statutory_rates
-- must never silently change a historical payslip. Not directly writable:
-- create_payslip() / delete_payslip() are the only paths (RLS below has
-- no insert/update/delete policy).
-- ---------------------------------------------------------------------
create table public.payslips (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.payroll_runs (id) on delete cascade,
  staff_id uuid not null references public.staff (id) on delete restrict,
  staff_pay_config_id uuid not null references public.staff_pay_config (id) on delete restrict,

  basic_salary numeric(12, 2) not null,
  overtime_hours numeric(8, 2) not null default 0,
  overtime_rate numeric(12, 2) not null default 0,
  overtime_pay numeric(12, 2) not null default 0,

  total_allowances numeric(12, 2) not null default 0,
  total_earning numeric(12, 2) not null,
  gross_salary numeric(12, 2) not null,
  taxable_income numeric(12, 2) not null,

  tax numeric(12, 2) not null default 0,
  tier2 numeric(12, 2) not null default 0,
  ssnit numeric(12, 2) not null default 0,
  fines numeric(12, 2) not null default 0,
  iou numeric(12, 2) not null default 0,
  total_deductions numeric(12, 2) not null,

  net_pay numeric(12, 2) not null,

  -- Forward-looking: set once payslip PDFs are uploaded to Storage. The
  -- current UI generates the PDF client-side (like invoice-pdf.ts) and
  -- doesn't populate this.
  pdf_path text,
  generated_at timestamptz not null default now(),

  unique (payroll_run_id, staff_id)
);

create index payslips_payroll_run_id_idx on public.payslips (payroll_run_id);
create index payslips_staff_id_idx on public.payslips (staff_id);

-- Line-item allowances actually applied on a given payslip. Written by
-- create_payslip() from the (UI-adjusted) array it's handed — the UI
-- pre-fills that array from staff_allowances but every amount is editable
-- per month (Extra Classes especially varies month to month).
create table public.payslip_allowances (
  id uuid primary key default gen_random_uuid(),
  payslip_id uuid not null references public.payslips (id) on delete cascade,
  allowance_type_id uuid not null references public.allowance_types (id) on delete restrict,
  amount numeric(12, 2) not null check (amount >= 0),
  note text
);

create index payslip_allowances_payslip_id_idx on public.payslip_allowances (payslip_id);

-- =======================================================================
-- Row-level security — three-tier (docs/DESIGN.md):
--   select: Manager + Accountant/Auditor        (Attendant: nothing)
--   write : Manager only                        (Auditor: read-only)
-- Same shape as accounts / journal_entries. No staff self-service view of
-- their own payslip yet — a deliberate deferral; add a narrower policy
-- later if staff logins should see their own pay history.
-- =======================================================================
alter table public.allowance_types enable row level security;
alter table public.staff_pay_config enable row level security;
alter table public.staff_allowances enable row level security;
alter table public.statutory_rates enable row level security;
alter table public.paye_bands enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payslips enable row level security;
alter table public.payslip_allowances enable row level security;

-- Config tables: Manager gets plain RLS-gated CRUD (editing an allowance
-- type / pay config / rate row is a plain update, same reasoning as
-- accounts edits — no extra invariant beyond the unique constraints).
do $$
declare
  t text;
  tables text[] := array[
    'allowance_types', 'staff_pay_config', 'staff_allowances',
    'statutory_rates', 'paye_bands'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create policy %I_select on public.%I for select using (public.has_role(array[''Manager'',''Accountant/Auditor'']))',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert with check (public.has_role(array[''Manager'']))',
      t, t
    );
    execute format(
      'create policy %I_update on public.%I for update using (public.has_role(array[''Manager''])) with check (public.has_role(array[''Manager'']))',
      t, t
    );
    execute format(
      'create policy %I_delete on public.%I for delete using (public.has_role(array[''Manager'']))',
      t, t
    );
  end loop;
end;
$$;

-- payroll_runs: select for Manager + Auditor; no insert/update policy
-- (create_payroll_run() is the only creation path, and Draft->Posted will
-- be its own RPC in the accounting follow-up). Delete is Manager-only and
-- Draft-only — a Posted run is a lock, and once it posts to the ledger it
-- must not be deletable at all.
create policy payroll_runs_select on public.payroll_runs
for select using (public.has_role(array['Manager', 'Accountant/Auditor']));

create policy payroll_runs_delete on public.payroll_runs
for delete using (public.has_role(array['Manager']) and status = 'Draft');

-- payslips / payslip_allowances: select only. All writes go through the
-- security-definer functions below (same "only its own function writes
-- here" shape as journal_entries).
create policy payslips_select on public.payslips
for select using (public.has_role(array['Manager', 'Accountant/Auditor']));

create policy payslip_allowances_select on public.payslip_allowances
for select using (public.has_role(array['Manager', 'Accountant/Auditor']));

-- ---------------------------------------------------------------------
-- Grants. anon: nothing. authenticated: full CRUD on config tables,
-- select-only on runs/payslips (writes via RPC). service_role: full CRUD
-- everywhere (bypasses RLS anyway; withholding buys nothing here).
-- ---------------------------------------------------------------------
revoke all on public.allowance_types from anon;
revoke all on public.staff_pay_config from anon;
revoke all on public.staff_allowances from anon;
revoke all on public.statutory_rates from anon;
revoke all on public.paye_bands from anon;
revoke all on public.payroll_runs from anon;
revoke all on public.payslips from anon;
revoke all on public.payslip_allowances from anon;

grant select, insert, update, delete on public.allowance_types to authenticated;
grant select, insert, update, delete on public.staff_pay_config to authenticated;
grant select, insert, update, delete on public.staff_allowances to authenticated;
grant select, insert, update, delete on public.statutory_rates to authenticated;
grant select, insert, update, delete on public.paye_bands to authenticated;
-- payroll_runs: created via create_payroll_run() (SECURITY DEFINER, no
-- insert grant needed), but deleted directly through PostgREST — the
-- payroll_runs_delete policy (Manager + Draft only) is what gates it, so
-- the delete grant is required for that policy to ever be reached.
grant select, delete on public.payroll_runs to authenticated;
-- payslips / payslip_allowances: never written directly — create_payslip()
-- / delete_payslip() (SECURITY DEFINER) are the only paths.
grant select on public.payslips to authenticated;
grant select on public.payslip_allowances to authenticated;

grant select, insert, update, delete on public.allowance_types to service_role;
grant select, insert, update, delete on public.staff_pay_config to service_role;
grant select, insert, update, delete on public.staff_allowances to service_role;
grant select, insert, update, delete on public.statutory_rates to service_role;
grant select, insert, update, delete on public.paye_bands to service_role;
grant select, insert, update, delete on public.payroll_runs to service_role;
grant select, insert, update, delete on public.payslips to service_role;
grant select, insert, update, delete on public.payslip_allowances to service_role;

-- =====================================================================
-- create_payroll_run(): the only path that creates a run. Manager-only,
-- id server-generated, plain insert (never upsert), created_by forced
-- from auth.uid(). Friendly error on the (branch, month, year) clash.
-- =====================================================================
create or replace function public.create_payroll_run(
  p_branch_id uuid,
  p_month integer,
  p_year integer
)
returns public.payroll_runs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payroll_runs;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can create a payroll run';
  end if;

  if p_month is null or p_month < 1 or p_month > 12 then
    raise exception 'Month must be between 1 and 12';
  end if;
  if p_year is null or p_year < 2020 then
    raise exception 'Year is out of range';
  end if;

  begin
    insert into public.payroll_runs (branch_id, month, year, created_by)
    values (p_branch_id, p_month, p_year, auth.uid())
    returning * into v_row;
  exception when unique_violation then
    raise exception 'A payroll run for % / % already exists for this branch', p_month, p_year;
  end;

  return v_row;
end;
$$;

grant execute on function public.create_payroll_run(uuid, integer, integer) to authenticated;
grant execute on function public.create_payroll_run(uuid, integer, integer) to service_role;

-- =====================================================================
-- create_payslip(): computes every derived figure server-side for one
-- staff member's payslip and inserts it. The client never computes tax or
-- a statutory deduction. p_allowances is a jsonb array of
-- {"allowance_type_id": uuid, "amount": number} — same jsonb-array
-- convention as create_invoice()/create_sale()'s p_lines — so the caller
-- can adjust month-specific amounts (the UI pre-fills them from
-- staff_allowances) before calling this.
-- Manager-only; Draft runs only; one payslip per staff per run.
-- =====================================================================
create or replace function public.create_payslip(
  p_payroll_run_id uuid,
  p_staff_id uuid,
  p_overtime_hours numeric default 0,
  p_overtime_rate numeric default 0,
  p_allowances jsonb default '[]'::jsonb,
  p_fines numeric default 0,
  p_iou numeric default 0
)
returns public.payslips
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
  v_config public.staff_pay_config;
  v_rates public.statutory_rates;
  v_run_date date;
  v_overtime_pay numeric;
  v_total_taxable_allowances numeric := 0;
  v_total_allowances numeric := 0;
  v_total_earning numeric;
  v_gross_salary numeric;
  v_taxable_income numeric;
  v_tax numeric := 0;
  v_tier2 numeric := 0;
  v_ssnit numeric := 0;
  v_total_deductions numeric;
  v_net_pay numeric;
  v_payslip public.payslips;
  v_band record;
  v_remaining numeric;
  v_band_amount numeric;
  v_alw jsonb;
  v_alw_type_id uuid;
  v_alw_amount numeric;
  v_allowance_taxable boolean;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can generate a payslip';
  end if;

  select * into v_run from public.payroll_runs where id = p_payroll_run_id;
  if v_run is null then
    raise exception 'Payroll run % not found', p_payroll_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Payroll run % is already posted and cannot take new payslips', v_run.id;
  end if;

  v_run_date := make_date(v_run.year, v_run.month, 1);

  -- Current pay config for this staff member as of the run's month.
  select * into v_config
  from public.staff_pay_config
  where staff_id = p_staff_id
    and effective_from <= v_run_date
    and (effective_to is null or effective_to >= v_run_date)
  order by effective_from desc
  limit 1;

  if v_config is null then
    raise exception 'No pay config found for staff % as of %', p_staff_id, v_run_date;
  end if;

  -- Latest statutory rates effective on/before the run date.
  select * into v_rates
  from public.statutory_rates
  where effective_from <= v_run_date
  order by effective_from desc
  limit 1;

  if v_rates is null then
    raise exception 'No statutory_rates configured effective on or before %', v_run_date;
  end if;

  v_overtime_pay := coalesce(p_overtime_hours, 0) * coalesce(p_overtime_rate, 0);

  -- Sum allowances, tracking taxable vs non-taxable separately.
  for v_alw in select * from jsonb_array_elements(coalesce(p_allowances, '[]'::jsonb)) loop
    v_alw_type_id := (v_alw->>'allowance_type_id')::uuid;
    v_alw_amount := coalesce((v_alw->>'amount')::numeric, 0);

    select taxable into v_allowance_taxable
    from public.allowance_types where id = v_alw_type_id;
    if v_allowance_taxable is null then
      raise exception 'Unknown allowance type %', v_alw_type_id;
    end if;

    v_total_allowances := v_total_allowances + v_alw_amount;
    if v_allowance_taxable then
      v_total_taxable_allowances := v_total_taxable_allowances + v_alw_amount;
    end if;
  end loop;

  v_total_earning := v_config.basic_salary + v_overtime_pay + v_total_allowances;
  v_gross_salary := v_total_earning;

  -- SSNIT (employee side) and Tier 2, on basic salary, only if this staff
  -- member actually participates (National Service etc. would have both
  -- flags false).
  if v_config.pays_ssnit then
    v_ssnit := round(v_config.basic_salary * v_rates.ssnit_employee_pct / 100, 2);
  end if;
  if v_config.pays_tier2 then
    v_tier2 := round(v_config.basic_salary * v_rates.tier2_employee_pct / 100, 2);
  end if;

  -- Taxable income: basic + overtime + taxable allowances, minus the
  -- employee's SSNIT + Tier 2 (both pre-tax per standard treatment).
  v_taxable_income := v_config.basic_salary + v_overtime_pay + v_total_taxable_allowances - v_ssnit - v_tier2;
  if v_taxable_income < 0 then
    v_taxable_income := 0;
  end if;

  -- Graduated PAYE, only if this staff member pays it. Bands are
  -- cumulative thresholds; each band's slice is taxed at its own rate.
  if v_config.pays_paye then
    v_remaining := v_taxable_income;
    for v_band in
      select * from public.paye_bands
      where effective_from <= v_run_date
        and effective_from = (
          select max(effective_from) from public.paye_bands where effective_from <= v_run_date
        )
      order by band_order asc
    loop
      exit when v_remaining <= 0;
      v_band_amount := least(
        v_remaining,
        coalesce(v_band.upper_bound, v_remaining + v_band.lower_bound) - v_band.lower_bound
      );
      if v_band_amount > 0 then
        v_tax := v_tax + round(v_band_amount * v_band.rate / 100, 2);
        v_remaining := v_remaining - v_band_amount;
      end if;
    end loop;
  end if;

  v_total_deductions := v_tax + v_tier2 + v_ssnit + coalesce(p_fines, 0) + coalesce(p_iou, 0);
  v_net_pay := v_gross_salary - v_total_deductions;

  insert into public.payslips (
    payroll_run_id, staff_id, staff_pay_config_id,
    basic_salary, overtime_hours, overtime_rate, overtime_pay,
    total_allowances, total_earning, gross_salary, taxable_income,
    tax, tier2, ssnit, fines, iou, total_deductions, net_pay
  ) values (
    p_payroll_run_id, p_staff_id, v_config.id,
    v_config.basic_salary, coalesce(p_overtime_hours, 0), coalesce(p_overtime_rate, 0), v_overtime_pay,
    v_total_allowances, v_total_earning, v_gross_salary, v_taxable_income,
    v_tax, v_tier2, v_ssnit, coalesce(p_fines, 0), coalesce(p_iou, 0), v_total_deductions, v_net_pay
  )
  returning * into v_payslip;

  insert into public.payslip_allowances (payslip_id, allowance_type_id, amount)
  select
    v_payslip.id,
    (elem->>'allowance_type_id')::uuid,
    coalesce((elem->>'amount')::numeric, 0)
  from jsonb_array_elements(coalesce(p_allowances, '[]'::jsonb)) as elem;

  return v_payslip;
end;
$$;

grant execute on function public.create_payslip(uuid, uuid, numeric, numeric, jsonb, numeric, numeric) to authenticated;
grant execute on function public.create_payslip(uuid, uuid, numeric, numeric, jsonb, numeric, numeric) to service_role;

-- =====================================================================
-- delete_payslip(): the escape hatch for a mistaken payslip — Manager
-- only, and only while the parent run is still Draft. payslip_allowances
-- cascade. Regenerate with create_payslip() afterward.
-- =====================================================================
create or replace function public.delete_payslip(p_payslip_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can delete a payslip';
  end if;

  select r.status into v_status
  from public.payslips p
  join public.payroll_runs r on r.id = p.payroll_run_id
  where p.id = p_payslip_id;

  if not found then
    raise exception 'Payslip % not found', p_payslip_id;
  end if;
  if v_status <> 'Draft' then
    raise exception 'Cannot delete a payslip from a posted payroll run';
  end if;

  delete from public.payslips where id = p_payslip_id;
end;
$$;

grant execute on function public.delete_payslip(uuid) to authenticated;
grant execute on function public.delete_payslip(uuid) to service_role;

-- =====================================================================
-- Seed: statutory rates + PAYE bands.
--
-- These live in the migration (not seed.sql) on purpose: they're
-- entity-wide statutory reference data with no branch/staff FK, and
-- seed.sql never runs on a real deployment — the same lesson as
-- 20260819090000_seed_gap_accounts_expense_categories.sql. Idempotent so
-- re-applying is safe.
--
-- ⚠️  PLACEHOLDER VALUES — NOT VERIFIED AGAINST AN OFFICIAL SOURCE.
--     * SSNIT/Tier 2 split (0.5% / 13% / 5%) is what was confirmed in
--       conversation against the school's current practice — treat as
--       likely-right but confirm against SSNIT before go-live.
--     * PAYE monthly bands below are the commonly-cited 2024 resident-
--       individual schedule. They MUST be replaced with GRA's actual
--       published, current schedule (correct thresholds AND effective
--       date) before running real payroll. See docs/CONSTRAINTS.md.
-- =====================================================================
insert into public.statutory_rates
  (ssnit_employee_pct, ssnit_employer_pct, tier2_employee_pct, tier2_employer_pct, effective_from)
values
  (0.5, 13, 5, 0, date '2025-01-01')
on conflict (effective_from) do nothing;

insert into public.paye_bands (effective_from, lower_bound, upper_bound, rate, band_order)
values
  (date '2025-01-01', 0,          490,        0,     1),
  (date '2025-01-01', 490,        600,        5,     2),
  (date '2025-01-01', 600,        730,        10,    3),
  (date '2025-01-01', 730,        3896.67,    17.5,  4),
  (date '2025-01-01', 3896.67,    19896.67,   25,    5),
  (date '2025-01-01', 19896.67,   50416.67,   30,    6),
  (date '2025-01-01', 50416.67,   null,       35,    7)
on conflict (effective_from, band_order) do nothing;
