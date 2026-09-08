-- Payroll schema (TCS ERP build, Phase: Accounting/Finance focus).
-- Adds staff pay configuration, a flexible allowance-type system, editable
-- statutory rate/band tables (SSNIT, Tier 2, PAYE), and payroll
-- runs/payslips. Mirrors the existing app's conventions: effective-dated
-- config rows instead of a single mutable row (same pattern as nothing
-- else in this app yet, but matches how invoices/expenses treat history
-- as append-only), server-side plpgsql calculation (never trust the
-- client to compute tax), and RLS via has_role() scoped to
-- Manager/Accountant-Auditor only, matching journal_entries/ledger.

-- ---------------------------------------------------------------------
-- Allowance types: a configurable list (Extra Classes, Transport, etc.)
-- instead of fixed columns, same instinct as expense_categories — the
-- school edits this list themselves as pay structure changes, no
-- migration needed to add a new allowance type later.
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
-- today.
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
-- GHS 200/month by default"). A payroll run copies these into
-- payslip_allowances as a starting point, but each month's actual amount
-- can be adjusted at the payslip-line level without changing the
-- standing default.
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
-- Statutory rates: SSNIT (employer 13%, employee 0.5%) and Tier 2
-- (employee 5%, employer-side is 0 in this school's setup per staff
-- confirmation — SSNIT's 13% employer + 0.5% employee = 13.5% Tier 1;
-- Tier 2 is the employee's separate 5%). Stored as an editable,
-- effective-dated table rather than constants, since these are set by
-- national policy and can change — a rate correction should be a data
-- edit, not a code deploy.
--
-- IMPORTANT: the percentages below are placeholders reflecting what was
-- confirmed in conversation (0.5% SSNIT employee / 13% SSNIT employer /
-- 5% Tier 2 employee). Verify the exact current split directly against
-- SSNIT/GRA before relying on this for real payroll — online tax-guide
-- sites disagree on some of the finer points and none of them are the
-- primary source.
-- ---------------------------------------------------------------------
create table public.statutory_rates (
  id uuid primary key default gen_random_uuid(),
  ssnit_employee_pct numeric(5, 3) not null,
  ssnit_employer_pct numeric(5, 3) not null,
  tier2_employee_pct numeric(5, 3) not null,
  tier2_employer_pct numeric(5, 3) not null default 0,
  effective_from date not null,
  created_at timestamptz not null default now()
);

create index statutory_rates_effective_from_idx on public.statutory_rates (effective_from desc);

-- ---------------------------------------------------------------------
-- PAYE bands: graduated tax bands, editable and effective-dated the same
-- way. upper_bound null means "and above" (the top band). Same
-- verify-before-trusting caveat as statutory_rates above.
-- ---------------------------------------------------------------------
create table public.paye_bands (
  id uuid primary key default gen_random_uuid(),
  effective_from date not null,
  lower_bound numeric(12, 2) not null,
  upper_bound numeric(12, 2),
  rate numeric(5, 3) not null,
  band_order integer not null,
  check (upper_bound is null or upper_bound > lower_bound)
);

create index paye_bands_effective_from_idx on public.paye_bands (effective_from desc, band_order);

-- ---------------------------------------------------------------------
-- Payroll runs: one per branch per month. Posting a run creates the
-- corresponding journal entry in the existing accounting system (wired
-- up in a later migration once the accounting posting function for
-- payroll is written) — kept as a separate explicit step (draft ->
-- posted) rather than auto-posting on creation, same "don't silently
-- touch the ledger" discipline as everything else in Accounting.
-- ---------------------------------------------------------------------
create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  month integer not null check (month between 1 and 12),
  year integer not null check (year >= 2020),
  status text not null default 'Draft' check (status in ('Draft', 'Posted')),
  created_by uuid references public.staff (id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (branch_id, month, year)
);

-- ---------------------------------------------------------------------
-- Payslips: one row per staff per run. Columns mirror the existing
-- Google Sheet directly (Basic Salary, Overtime, Total Earning, Gross
-- Salary, Taxable Income, Tax, Tier 2, SSNIT, Fines, IOU, Deductions,
-- Net Pay) so the transition off the sheet feels like the same system,
-- not a new one. All amounts are snapshotted at generation time — later
-- edits to staff_pay_config or statutory_rates must never silently
-- change a historical payslip.
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

  pdf_path text,
  generated_at timestamptz not null default now(),

  unique (payroll_run_id, staff_id)
);

create index payslips_payroll_run_id_idx on public.payslips (payroll_run_id);
create index payslips_staff_id_idx on public.payslips (staff_id);

-- Line-item allowances actually applied on a given payslip. Seeded from
-- staff_allowances defaults when a run is created, but independently
-- editable per month (Extra Classes especially will vary month to
-- month).
create table public.payslip_allowances (
  id uuid primary key default gen_random_uuid(),
  payslip_id uuid not null references public.payslips (id) on delete cascade,
  allowance_type_id uuid not null references public.allowance_types (id) on delete restrict,
  amount numeric(12, 2) not null check (amount >= 0),
  note text
);

create index payslip_allowances_payslip_id_idx on public.payslip_allowances (payslip_id);

-- =======================================================================
-- Row-level security. Payroll is the most sensitive data in the app
-- (individual salaries) — restricted to Manager and Accountant/Auditor
-- only, same roles as journal_entries/ledger, and explicitly NOT
-- Attendant. No staff self-service view of their own payslip yet; that's
-- a deliberate deferral, not an oversight — add a narrower policy later
-- if/when staff logins should be able to see their own pay history.
-- =======================================================================
alter table public.allowance_types enable row level security;
alter table public.staff_pay_config enable row level security;
alter table public.staff_allowances enable row level security;
alter table public.statutory_rates enable row level security;
alter table public.paye_bands enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payslips enable row level security;
alter table public.payslip_allowances enable row level security;

do $$
declare
  t text;
  tables text[] := array[
    'allowance_types', 'staff_pay_config', 'staff_allowances',
    'statutory_rates', 'paye_bands', 'payroll_runs', 'payslips',
    'payslip_allowances'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create policy %I_select on public.%I for select using (public.has_role(array[''Manager'',''Accountant/Auditor'']))',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert with check (public.has_role(array[''Manager'',''Accountant/Auditor'']))',
      t, t
    );
    execute format(
      'create policy %I_update on public.%I for update using (public.has_role(array[''Manager'',''Accountant/Auditor''])) with check (public.has_role(array[''Manager'',''Accountant/Auditor'']))',
      t, t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Calculation engine. Takes raw inputs for one staff member's payslip
-- and computes every derived figure server-side — the client never
-- computes tax or statutory deductions itself, same trust boundary as
-- create_invoice()/post_journal_entry_rows(). Allowances are passed as
-- an array of (allowance_type_id, amount) pairs so the caller can adjust
-- month-specific amounts before calling this.
-- ---------------------------------------------------------------------
create type public.payslip_allowance_input as (
  allowance_type_id uuid,
  amount numeric
);

create or replace function public.create_payslip(
  p_payroll_run_id uuid,
  p_staff_id uuid,
  p_overtime_hours numeric default 0,
  p_overtime_rate numeric default 0,
  p_allowances public.payslip_allowance_input[] default array[]::public.payslip_allowance_input[],
  p_fines numeric default 0,
  p_iou numeric default 0
)
returns public.payslips
language plpgsql
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
  a public.payslip_allowance_input;
  v_allowance_taxable boolean;
begin
  select * into v_run from public.payroll_runs where id = p_payroll_run_id;
  if v_run is null then
    raise exception 'Payroll run % not found', p_payroll_run_id;
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
  foreach a in array p_allowances loop
    select taxable into v_allowance_taxable
    from public.allowance_types where id = a.allowance_type_id;

    v_total_allowances := v_total_allowances + a.amount;
    if coalesce(v_allowance_taxable, true) then
      v_total_taxable_allowances := v_total_taxable_allowances + a.amount;
    end if;
  end loop;

  v_total_earning := v_config.basic_salary + v_overtime_pay + v_total_allowances;
  v_gross_salary := v_total_earning;

  -- SSNIT (employee side) and Tier 2, only if this staff member actually
  -- participates (National Service etc. would have both flags false).
  if v_config.pays_ssnit then
    v_ssnit := round(v_config.basic_salary * v_rates.ssnit_employee_pct / 100, 2);
  end if;
  if v_config.pays_tier2 then
    v_tier2 := round(v_config.basic_salary * v_rates.tier2_employee_pct / 100, 2);
  end if;

  -- Taxable income: basic + overtime + taxable allowances, minus the
  -- employee's SSNIT+Tier2 (both are pre-tax per standard treatment),
  -- only when this staff member actually pays PAYE at all.
  v_taxable_income := v_config.basic_salary + v_overtime_pay + v_total_taxable_allowances - v_ssnit - v_tier2;
  if v_taxable_income < 0 then
    v_taxable_income := 0;
  end if;

  if v_config.pays_paye then
    v_remaining := v_taxable_income;
    for v_band in
      select * from public.paye_bands
      where effective_from <= v_run_date
      order by effective_from desc, band_order asc
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

  foreach a in array p_allowances loop
    insert into public.payslip_allowances (payslip_id, allowance_type_id, amount)
    values (v_payslip.id, a.allowance_type_id, a.amount);
  end loop;

  return v_payslip;
end;
$$;

grant select, insert, update on public.allowance_types to authenticated;
grant select, insert, update on public.staff_pay_config to authenticated;
grant select, insert, update on public.staff_allowances to authenticated;
grant select, insert, update on public.statutory_rates to authenticated;
grant select, insert, update on public.paye_bands to authenticated;
grant select, insert, update on public.payroll_runs to authenticated;
grant select on public.payslips to authenticated;
grant select on public.payslip_allowances to authenticated;
grant execute on function public.create_payslip(uuid, uuid, numeric, numeric, public.payslip_allowance_input[], numeric, numeric) to authenticated;
