-- Employees vs ERP logins + payroll approval workflow (TCS ERP).
--
-- Splits "person TCS pays" from "person with an ERP login". Until now
-- staff_pay_config / staff_allowances / payslips all keyed off staff.id,
-- and a staff row only exists for someone with a real login. TCS needs pay
-- profiles for teachers / drivers / kitchen staff who will not have logins
-- for a long time.
--
-- 1. New `employees` table — everyone TCS pays, independent of ERP access.
-- 2. `staff.employee_id` — optional link, for someone who has both.
-- 3. staff_pay_config -> employee_pay_config, staff_allowances ->
--    employee_allowances, payslips.staff_id -> employee_id (all repointed).
-- 4. phone / position / department move from staff to employees.
-- 5. Approval workflow: creating an employee, changing basic salary, and
--    changing bank/account number are proposed by an Accountant and take
--    effect only on Manager approval. A pending proposal never touches the
--    live config. Suspend/reactivate are direct (no gate). Every
--    proposal/approval/rejection lands in audit_log via triggers.
-- 6. RLS: Accountant proposes + suspends directly; Manager also
--    approves/rejects; Auditor reads everything including pending.
-- 8. Existing staff pay data is migrated to linked `employees` rows with
--    all effective-dated history and payslip figures preserved.
--
-- Design notes: see docs/DESIGN.md. The proposal mechanism reuses the
-- existing effective-dated snapshot pattern — a pending pay change IS an
-- employee_pay_config row in 'Pending Approval' state; approving it
-- promotes it, rejecting it tombstones it. No parallel proposals table.

-- =====================================================================
-- 1. employees
-- =====================================================================
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  name text not null,
  phone text,
  position text,
  department text,
  -- Pending Approval -> Active (Manager approves) | Rejected (Manager rejects).
  -- Active <-> Suspended is a direct Accountant/Manager toggle, no gate.
  -- Rejected is terminal. Not usable in a payroll run unless 'Active'.
  employment_status text not null default 'Pending Approval'
    check (employment_status in ('Pending Approval', 'Active', 'Suspended', 'Rejected')),
  -- Who proposed the record (server-forced from auth.uid() by trigger;
  -- nullable for the seed/migration context, same as accounts.created_by).
  proposed_by uuid references public.staff (id) on delete set null,
  created_at timestamptz not null default now(),
  -- Who approved or rejected the record creation.
  reviewed_by uuid references public.staff (id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  updated_at timestamptz not null default now()
);

create index employees_branch_id_idx on public.employees (branch_id);
create index employees_employment_status_idx on public.employees (employment_status);

create or replace function public.set_employee_proposed_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.proposed_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger employees_set_proposed_by
before insert on public.employees
for each row execute function public.set_employee_proposed_by();

create trigger employees_set_updated_at
before update on public.employees
for each row execute function public.set_updated_at();

-- =====================================================================
-- 2. staff.employee_id — optional login <-> paid-person link
-- =====================================================================
alter table public.staff
  add column employee_id uuid references public.employees (id) on delete set null;

create unique index staff_employee_id_key
  on public.staff (employee_id) where employee_id is not null;

-- =====================================================================
-- 3. Rename + repoint the pay tables
-- =====================================================================
alter table public.staff_pay_config rename to employee_pay_config;
alter table public.staff_allowances rename to employee_allowances;

alter index staff_pay_config_pkey rename to employee_pay_config_pkey;
alter table public.employee_pay_config
  rename constraint staff_pay_config_basic_salary_check to employee_pay_config_basic_salary_check;
alter table public.employee_pay_config
  rename constraint staff_pay_config_check to employee_pay_config_effective_dates_check;
alter index staff_allowances_pkey rename to employee_allowances_pkey;
alter table public.employee_allowances
  rename constraint staff_allowances_check to employee_allowances_effective_dates_check;
alter table public.employee_allowances
  rename constraint staff_allowances_default_amount_check to employee_allowances_default_amount_check;

-- employee_pay_config: approval-workflow columns.
alter table public.employee_pay_config
  -- Open Question 1 (confirmed): default 'Active'. Raw inserts (migration,
  -- seed, service_role) are live-by-default; only propose_pay_config_change()
  -- writes a 'Pending Approval' row, and there is no authenticated insert
  -- policy, so nothing else can create one.
  add column approval_status text not null default 'Active'
    check (approval_status in ('Pending Approval', 'Active', 'Rejected')),
  add column proposed_by uuid references public.staff (id) on delete set null,
  add column reviewed_by uuid references public.staff (id) on delete set null,
  add column reviewed_at timestamptz,
  add column rejection_reason text,
  add column employee_id uuid;

alter table public.employee_allowances add column employee_id uuid;

alter table public.payslips add column employee_id uuid;
alter table public.payslips rename column staff_pay_config_id to employee_pay_config_id;
alter table public.payslips
  rename constraint payslips_staff_pay_config_id_fkey to payslips_employee_pay_config_id_fkey;

-- =====================================================================
-- 5-8. Backfill: turn every staff row that has pay data into a linked
-- 'Active' employee, preserving all history. No-op on a fresh local
-- reset (migrations run before seed.sql, so the payroll tables are
-- empty here and seed.sql inserts directly into the new shape).
-- =====================================================================
do $$
declare
  r record;
  v_emp_id uuid;
begin
  for r in
    select s.id as staff_id, s.name, s.branch_id, s.phone, s.position, s.department, s.created_at
    from public.staff s
    where s.id in (
      select staff_id from public.employee_pay_config
      union
      select staff_id from public.employee_allowances
      union
      select staff_id from public.payslips
    )
  loop
    insert into public.employees
      (branch_id, name, phone, position, department, employment_status,
       proposed_by, created_at, reviewed_by, reviewed_at)
    values
      (r.branch_id, r.name, r.phone, r.position, r.department, 'Active',
       null, r.created_at, null, r.created_at)
    returning id into v_emp_id;

    update public.staff set employee_id = v_emp_id where id = r.staff_id;
    update public.employee_pay_config set employee_id = v_emp_id where staff_id = r.staff_id;
    update public.employee_allowances set employee_id = v_emp_id where staff_id = r.staff_id;
    update public.payslips set employee_id = v_emp_id where staff_id = r.staff_id;
  end loop;
end $$;

-- Enforce NOT NULL, swap FKs, drop the old staff_id columns.
alter table public.employee_pay_config
  alter column employee_id set not null,
  add constraint employee_pay_config_employee_id_fkey
    foreign key (employee_id) references public.employees (id) on delete restrict;
alter table public.employee_pay_config drop column staff_id;

alter table public.employee_allowances
  alter column employee_id set not null,
  add constraint employee_allowances_employee_id_fkey
    foreign key (employee_id) references public.employees (id) on delete restrict;
alter table public.employee_allowances drop column staff_id;

alter table public.payslips
  alter column employee_id set not null,
  add constraint payslips_employee_id_fkey
    foreign key (employee_id) references public.employees (id) on delete restrict;
alter table public.payslips drop column staff_id;
alter table public.payslips add constraint payslips_payroll_run_id_employee_id_key
  unique (payroll_run_id, employee_id);

-- Indexes on the new keys.
create index employee_pay_config_employee_id_idx
  on public.employee_pay_config (employee_id, effective_from desc);
-- Exactly one *current* approved config per employee.
create unique index employee_pay_config_one_active_idx
  on public.employee_pay_config (employee_id)
  where effective_to is null and approval_status = 'Active';
-- At most one outstanding proposal per employee.
create unique index employee_pay_config_one_pending_idx
  on public.employee_pay_config (employee_id)
  where approval_status = 'Pending Approval';
create index employee_allowances_employee_id_idx
  on public.employee_allowances (employee_id);
create index payslips_employee_id_idx on public.payslips (employee_id);

-- =====================================================================
-- 4. phone / position / department are employee attributes now.
-- =====================================================================
alter table public.staff
  drop column phone,
  drop column position,
  drop column department;

-- =====================================================================
-- RLS + grants
-- =====================================================================
alter table public.employees enable row level security;

create policy employees_select on public.employees
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
-- No insert/update/delete policy: every write goes through a SECURITY
-- DEFINER RPC below (same model as payroll_runs / payslips / journal_entries).

revoke all on public.employees from anon;
grant select on public.employees to authenticated;
grant select, insert, update, delete on public.employees to service_role;

-- employee_pay_config: lock down to RPC-only writes (was Manager/Accountant
-- CRUD). Even a Manager now goes through the approval RPCs so the trail
-- cannot be bypassed.
drop policy staff_pay_config_select on public.employee_pay_config;
drop policy staff_pay_config_insert on public.employee_pay_config;
drop policy staff_pay_config_update on public.employee_pay_config;
drop policy staff_pay_config_delete on public.employee_pay_config;

create policy employee_pay_config_select on public.employee_pay_config
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

revoke insert, update, delete on public.employee_pay_config from authenticated;
-- select grant + full service_role grant carried over from the payroll migration.

-- employee_allowances: unchanged shape (NOT approval-gated), policies
-- renamed for tidiness.
drop policy staff_allowances_select on public.employee_allowances;
drop policy staff_allowances_insert on public.employee_allowances;
drop policy staff_allowances_update on public.employee_allowances;
drop policy staff_allowances_delete on public.employee_allowances;

create policy employee_allowances_select on public.employee_allowances
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy employee_allowances_insert on public.employee_allowances
for insert with check (public.has_role(array['Manager', 'Accountant']));
create policy employee_allowances_update on public.employee_allowances
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));
create policy employee_allowances_delete on public.employee_allowances
for delete using (public.has_role(array['Manager', 'Accountant']));

-- =====================================================================
-- audit_log: new actions + triggers on employees / employee_pay_config
-- (audit_log stays trigger-written-only — never by client or RPC).
-- =====================================================================
alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action in (
  'discount_applied', 'vat_override', 'return_processed',
  'sale_voided', 'invoice_voided', 'expense_voided',
  'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated',
  'pay_config_proposed', 'pay_config_approved', 'pay_config_rejected',
  'pay_config_exemptions_changed'
));

create or replace function public.audit_employee()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.proposed_by, new.reviewed_by);
  v_action text;
  v_before jsonb;
  v_after jsonb;
begin
  -- No actor => seed / migration backfill, not a user action.
  if v_actor is null then return new; end if;

  if tg_op = 'INSERT' then
    v_action := 'employee_created';
    v_after := jsonb_build_object(
      'name', new.name, 'employment_status', new.employment_status,
      'position', new.position, 'department', new.department
    );
  elsif old.employment_status is distinct from new.employment_status then
    v_action := case
      when old.employment_status = 'Pending Approval' and new.employment_status = 'Active'
        then 'employee_approved'
      when old.employment_status = 'Pending Approval' and new.employment_status = 'Rejected'
        then 'employee_rejected'
      when old.employment_status = 'Active' and new.employment_status = 'Suspended'
        then 'employee_suspended'
      when old.employment_status = 'Suspended' and new.employment_status = 'Active'
        then 'employee_reactivated'
      else null
    end;
    v_before := jsonb_build_object('employment_status', old.employment_status);
    v_after := jsonb_build_object(
      'employment_status', new.employment_status, 'reason', new.rejection_reason
    );
  else
    return new; -- profile-only edit: not audited here (low sensitivity)
  end if;

  if v_action is null then return new; end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (new.branch_id, v_actor, v_action, 'employees', new.id::text, v_before, v_after);
  return new;
end;
$$;

create trigger employees_audit
after insert or update on public.employees
for each row execute function public.audit_employee();

create or replace function public.audit_employee_pay_config()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.proposed_by, new.reviewed_by);
  v_action text;
  v_before jsonb;
  v_after jsonb;
  v_branch uuid;
begin
  if v_actor is null then return new; end if;

  select branch_id into v_branch from public.employees where id = new.employee_id;
  if v_branch is null then return new; end if;

  if tg_op = 'INSERT' then
    if new.approval_status <> 'Pending Approval' then
      return new; -- migration/seed 'Active' insert, not a user proposal
    end if;
    v_action := 'pay_config_proposed';
    v_after := jsonb_build_object(
      'basic_salary', new.basic_salary, 'bank', new.bank, 'account_no', new.account_no,
      'effective_from', new.effective_from,
      'pays_ssnit', new.pays_ssnit, 'pays_tier2', new.pays_tier2, 'pays_paye', new.pays_paye
    );
  elsif old.approval_status is distinct from new.approval_status then
    v_action := case
      when new.approval_status = 'Active' then 'pay_config_approved'
      when new.approval_status = 'Rejected' then 'pay_config_rejected'
      else null
    end;
    v_before := jsonb_build_object('approval_status', old.approval_status);
    v_after := jsonb_build_object(
      'approval_status', new.approval_status, 'basic_salary', new.basic_salary,
      'bank', new.bank, 'account_no', new.account_no,
      'effective_from', new.effective_from, 'reason', new.rejection_reason
    );
  elsif (old.pays_ssnit, old.pays_tier2, old.pays_paye)
        is distinct from (new.pays_ssnit, new.pays_tier2, new.pays_paye) then
    v_action := 'pay_config_exemptions_changed';
    v_before := jsonb_build_object(
      'pays_ssnit', old.pays_ssnit, 'pays_tier2', old.pays_tier2, 'pays_paye', old.pays_paye
    );
    v_after := jsonb_build_object(
      'pays_ssnit', new.pays_ssnit, 'pays_tier2', new.pays_tier2, 'pays_paye', new.pays_paye
    );
  else
    return new; -- e.g. effective_to close on approval — the 'approved' event covers it
  end if;

  if v_action is null then return new; end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (v_branch, v_actor, v_action, 'employee_pay_config', new.id::text, v_before, v_after);
  return new;
end;
$$;

create trigger employee_pay_config_audit
after insert or update on public.employee_pay_config
for each row execute function public.audit_employee_pay_config();

-- =====================================================================
-- create_payslip(): p_staff_id -> p_employee_id (a parameter rename, so
-- drop + recreate per the check-duplicate-function-overloads.sh rule).
-- Adds: employee must be 'Active'; pay config lookup filters
-- approval_status = 'Active'.
-- =====================================================================
drop function if exists public.create_payslip(uuid, uuid, numeric, numeric, jsonb, numeric, numeric);

create function public.create_payslip(
  p_payroll_run_id uuid,
  p_employee_id uuid,
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
  v_emp_status text;
  v_config public.employee_pay_config;
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
  v_ssnit_employer numeric := 0;
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
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules; Auditor is read-only.
  perform public.require_finance_writer();

  select * into v_run from public.payroll_runs where id = p_payroll_run_id;
  if v_run is null then
    raise exception 'Payroll run % not found', p_payroll_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Payroll run % is already posted and cannot take new payslips', v_run.id;
  end if;

  select employment_status into v_emp_status from public.employees where id = p_employee_id;
  if v_emp_status is null then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp_status <> 'Active' then
    raise exception 'Employee % is not active (status: %) and cannot be paid', p_employee_id, v_emp_status;
  end if;

  v_run_date := make_date(v_run.year, v_run.month, 1);

  -- Current APPROVED pay config for this employee as of the run's month.
  select * into v_config
  from public.employee_pay_config
  where employee_id = p_employee_id
    and approval_status = 'Active'
    and effective_from <= v_run_date
    and (effective_to is null or effective_to >= v_run_date)
  order by effective_from desc
  limit 1;

  if v_config is null then
    raise exception 'No approved pay config for employee % as of %', p_employee_id, v_run_date;
  end if;

  select * into v_rates
  from public.statutory_rates
  where effective_from <= v_run_date
  order by effective_from desc
  limit 1;

  if v_rates is null then
    raise exception 'No statutory_rates configured effective on or before %', v_run_date;
  end if;

  v_overtime_pay := coalesce(p_overtime_hours, 0) * coalesce(p_overtime_rate, 0);

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

  -- Employee SSNIT + Tier 2, and the employer's 13% SSNIT, all on basic
  -- salary and all gated on pays_ssnit / pays_tier2.
  if v_config.pays_ssnit then
    v_ssnit := round(v_config.basic_salary * v_rates.ssnit_employee_pct / 100, 2);
    v_ssnit_employer := round(v_config.basic_salary * v_rates.ssnit_employer_pct / 100, 2);
  end if;
  if v_config.pays_tier2 then
    v_tier2 := round(v_config.basic_salary * v_rates.tier2_employee_pct / 100, 2);
  end if;

  v_taxable_income := v_config.basic_salary + v_overtime_pay + v_total_taxable_allowances - v_ssnit - v_tier2;
  if v_taxable_income < 0 then
    v_taxable_income := 0;
  end if;

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
    payroll_run_id, employee_id, employee_pay_config_id,
    basic_salary, overtime_hours, overtime_rate, overtime_pay,
    total_allowances, total_earning, gross_salary, taxable_income,
    tax, tier2, ssnit, ssnit_employer, fines, iou, total_deductions, net_pay
  ) values (
    p_payroll_run_id, p_employee_id, v_config.id,
    v_config.basic_salary, coalesce(p_overtime_hours, 0), coalesce(p_overtime_rate, 0), v_overtime_pay,
    v_total_allowances, v_total_earning, v_gross_salary, v_taxable_income,
    v_tax, v_tier2, v_ssnit, v_ssnit_employer, coalesce(p_fines, 0), coalesce(p_iou, 0),
    v_total_deductions, v_net_pay
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
-- Approval-workflow RPCs
--
-- propose_*  -> require_finance_writer()  (Manager + Accountant)
-- approve_* / reject_*  -> Manager only
-- set_employee_status / update_employee_profile / set_pay_config_exemptions
-- / withdraw_pay_config_proposal  -> require_finance_writer()
--
-- employees / employee_pay_config have NO authenticated write policy, so
-- these SECURITY DEFINER functions are the only write path.
-- =====================================================================

-- propose_employee(): new employee starts 'Pending Approval'. Optionally
-- carries an initial pay config (bundled — one proposal, one approval) and
-- an optional link to an existing login (staff row). Not usable in a
-- payroll run until approved.
create function public.propose_employee(
  p_name text,
  p_branch_id uuid,
  p_phone text default null,
  p_position text default null,
  p_department text default null,
  p_staff_id uuid default null,
  p_basic_salary numeric default null,
  p_bank text default null,
  p_account_no text default null,
  p_pays_ssnit boolean default true,
  p_pays_tier2 boolean default true,
  p_pays_paye boolean default true,
  p_effective_from date default null
)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
  v_eff date := coalesce(p_effective_from, date_trunc('month', current_date)::date);
begin
  perform public.require_finance_writer();

  if coalesce(trim(p_name), '') = '' then
    raise exception 'Employee name is required';
  end if;
  if not exists (select 1 from public.branches where id = p_branch_id) then
    raise exception 'Branch % not found', p_branch_id;
  end if;

  if p_staff_id is not null then
    if not exists (select 1 from public.staff where id = p_staff_id) then
      raise exception 'Login account % not found', p_staff_id;
    end if;
    if exists (select 1 from public.staff where id = p_staff_id and employee_id is not null) then
      raise exception 'That login account is already linked to an employee';
    end if;
  end if;

  insert into public.employees
    (branch_id, name, phone, position, department, employment_status)
  values
    (p_branch_id, trim(p_name),
     nullif(trim(p_phone), ''), nullif(trim(p_position), ''), nullif(trim(p_department), ''),
     'Pending Approval')
  returning * into v_emp;

  -- Link the login now; reject_employee() unlinks it if the record is
  -- rejected. create_payslip() gates on employment_status, not the link,
  -- so a link to a still-Pending employee is harmless.
  if p_staff_id is not null then
    update public.staff set employee_id = v_emp.id where id = p_staff_id;
  end if;

  if p_basic_salary is not null then
    if p_basic_salary < 0 then
      raise exception 'Basic salary cannot be negative';
    end if;
    insert into public.employee_pay_config
      (employee_id, bank, account_no, basic_salary, pays_ssnit, pays_tier2, pays_paye,
       effective_from, approval_status, proposed_by)
    values
      (v_emp.id, nullif(trim(p_bank), ''), nullif(trim(p_account_no), ''), p_basic_salary,
       p_pays_ssnit, p_pays_tier2, p_pays_paye, v_eff, 'Pending Approval', auth.uid());
  end if;

  return v_emp;
end;
$$;

grant execute on function public.propose_employee(text, uuid, text, text, text, uuid, numeric, text, text, boolean, boolean, boolean, date) to authenticated;
grant execute on function public.propose_employee(text, uuid, text, text, text, uuid, numeric, text, text, boolean, boolean, boolean, date) to service_role;

-- approve_employee(): Manager only. 'Pending Approval' -> 'Active', and
-- approves the bundled initial pay config (there can be no prior Active
-- config for a brand-new employee).
create function public.approve_employee(p_employee_id uuid)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve an employee record';
  end if;

  select * into v_emp from public.employees where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp.employment_status <> 'Pending Approval' then
    raise exception 'Employee % is not pending approval (status: %)', p_employee_id, v_emp.employment_status;
  end if;

  update public.employees
  set employment_status = 'Active', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_employee_id
  returning * into v_emp;

  -- Approve the bundled initial config, if any and only if nothing is
  -- already Active for this employee (always true for a new record).
  update public.employee_pay_config
  set approval_status = 'Active', reviewed_by = auth.uid(), reviewed_at = now()
  where employee_id = p_employee_id
    and approval_status = 'Pending Approval'
    and not exists (
      select 1 from public.employee_pay_config a
      where a.employee_id = p_employee_id and a.approval_status = 'Active' and a.effective_to is null
    );

  return v_emp;
end;
$$;

grant execute on function public.approve_employee(uuid) to authenticated;
grant execute on function public.approve_employee(uuid) to service_role;

-- reject_employee(): Manager only. 'Pending Approval' -> 'Rejected'
-- (terminal). Rejects any bundled pending config and unlinks the login.
create function public.reject_employee(p_employee_id uuid, p_reason text)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can reject an employee record';
  end if;

  select * into v_emp from public.employees where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp.employment_status <> 'Pending Approval' then
    raise exception 'Employee % is not pending approval (status: %)', p_employee_id, v_emp.employment_status;
  end if;

  update public.employees
  set employment_status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = nullif(trim(p_reason), '')
  where id = p_employee_id
  returning * into v_emp;

  update public.employee_pay_config
  set approval_status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = 'Employee record rejected'
  where employee_id = p_employee_id and approval_status = 'Pending Approval';

  update public.staff set employee_id = null where employee_id = p_employee_id;

  return v_emp;
end;
$$;

grant execute on function public.reject_employee(uuid, text) to authenticated;
grant execute on function public.reject_employee(uuid, text) to service_role;

-- set_employee_status(): direct suspend / reactivate (Accountant or
-- Manager), no approval gate. Active <-> Suspended only.
create function public.set_employee_status(p_employee_id uuid, p_status text)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
begin
  perform public.require_finance_writer();

  if p_status not in ('Active', 'Suspended') then
    raise exception 'Status must be Active or Suspended';
  end if;

  select * into v_emp from public.employees where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;

  if p_status = 'Suspended' and v_emp.employment_status <> 'Active' then
    raise exception 'Only an active employee can be suspended (status: %)', v_emp.employment_status;
  end if;
  if p_status = 'Active' and v_emp.employment_status <> 'Suspended' then
    raise exception 'Only a suspended employee can be reactivated (status: %)', v_emp.employment_status;
  end if;

  update public.employees set employment_status = p_status
  where id = p_employee_id
  returning * into v_emp;

  return v_emp;
end;
$$;

grant execute on function public.set_employee_status(uuid, text) to authenticated;
grant execute on function public.set_employee_status(uuid, text) to service_role;

-- update_employee_profile(): direct edit of phone / position / department
-- (Accountant or Manager). Not on a Rejected record.
create function public.update_employee_profile(
  p_employee_id uuid,
  p_phone text,
  p_position text,
  p_department text
)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
begin
  perform public.require_finance_writer();

  select * into v_emp from public.employees where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp.employment_status = 'Rejected' then
    raise exception 'Cannot edit a rejected employee record';
  end if;

  update public.employees
  set phone = nullif(trim(p_phone), ''),
      position = nullif(trim(p_position), ''),
      department = nullif(trim(p_department), '')
  where id = p_employee_id
  returning * into v_emp;

  return v_emp;
end;
$$;

grant execute on function public.update_employee_profile(uuid, text, text, text) to authenticated;
grant execute on function public.update_employee_profile(uuid, text, text, text) to service_role;

-- propose_pay_config_change(): a new 'Pending Approval' config row. The
-- current Active row is untouched. Effective date must be forward of the
-- current config's start and in a month with no Posted payslip for this
-- employee (Open Question 2 confirmed: no same-period corrections).
create function public.propose_pay_config_change(
  p_employee_id uuid,
  p_effective_from date,
  p_basic_salary numeric,
  p_bank text,
  p_account_no text,
  p_pays_ssnit boolean,
  p_pays_tier2 boolean,
  p_pays_paye boolean
)
returns public.employee_pay_config
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
  v_current public.employee_pay_config;
  v_row public.employee_pay_config;
begin
  perform public.require_finance_writer();

  select * into v_emp from public.employees where id = p_employee_id;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp.employment_status <> 'Active' then
    raise exception 'Employee must be active to change pay (status: %)', v_emp.employment_status;
  end if;
  if p_basic_salary is null or p_basic_salary < 0 then
    raise exception 'Basic salary must be zero or more';
  end if;
  if p_effective_from is null then
    raise exception 'An effective date is required';
  end if;

  if exists (
    select 1 from public.employee_pay_config
    where employee_id = p_employee_id and approval_status = 'Pending Approval'
  ) then
    raise exception 'There is already a pending pay change for this employee — approve or reject it first';
  end if;

  select * into v_current
  from public.employee_pay_config
  where employee_id = p_employee_id and approval_status = 'Active' and effective_to is null;

  if found and p_effective_from <= v_current.effective_from then
    raise exception 'Effective date must be after the current pay period start (%)', v_current.effective_from;
  end if;

  if exists (
    select 1 from public.payslips ps
    join public.payroll_runs pr on pr.id = ps.payroll_run_id
    where ps.employee_id = p_employee_id
      and pr.status = 'Posted'
      and make_date(pr.year, pr.month, 1) >= date_trunc('month', p_effective_from)::date
  ) then
    raise exception 'That month has already been paid — choose a later effective date';
  end if;

  insert into public.employee_pay_config
    (employee_id, bank, account_no, basic_salary, pays_ssnit, pays_tier2, pays_paye,
     effective_from, approval_status, proposed_by)
  values
    (p_employee_id, nullif(trim(p_bank), ''), nullif(trim(p_account_no), ''), p_basic_salary,
     p_pays_ssnit, p_pays_tier2, p_pays_paye, p_effective_from, 'Pending Approval', auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.propose_pay_config_change(uuid, date, numeric, text, text, boolean, boolean, boolean) to authenticated;
grant execute on function public.propose_pay_config_change(uuid, date, numeric, text, text, boolean, boolean, boolean) to service_role;

-- approve_pay_config(): Manager only. Closes the current Active open row
-- (effective_to = the proposal's effective_from - 1 day) and promotes the
-- pending row to Active. Order matters for the one_active partial index.
create function public.approve_pay_config(p_config_id uuid)
returns public.employee_pay_config
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pending public.employee_pay_config;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve a pay change';
  end if;

  select * into v_pending from public.employee_pay_config where id = p_config_id for update;
  if not found then
    raise exception 'Pay config % not found', p_config_id;
  end if;
  if v_pending.approval_status <> 'Pending Approval' then
    raise exception 'Pay config % is not pending approval (status: %)', p_config_id, v_pending.approval_status;
  end if;

  update public.employee_pay_config
  set effective_to = (v_pending.effective_from - 1)
  where employee_id = v_pending.employee_id
    and approval_status = 'Active'
    and effective_to is null;

  update public.employee_pay_config
  set approval_status = 'Active', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_config_id
  returning * into v_pending;

  return v_pending;
end;
$$;

grant execute on function public.approve_pay_config(uuid) to authenticated;
grant execute on function public.approve_pay_config(uuid) to service_role;

-- reject_pay_config(): Manager only. Pending -> Rejected (tombstone).
-- Live config unchanged.
create function public.reject_pay_config(p_config_id uuid, p_reason text)
returns public.employee_pay_config
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.employee_pay_config;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can reject a pay change';
  end if;

  select * into v_row from public.employee_pay_config where id = p_config_id for update;
  if not found then
    raise exception 'Pay config % not found', p_config_id;
  end if;
  if v_row.approval_status <> 'Pending Approval' then
    raise exception 'Pay config % is not pending approval (status: %)', p_config_id, v_row.approval_status;
  end if;

  update public.employee_pay_config
  set approval_status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = nullif(trim(p_reason), '')
  where id = p_config_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.reject_pay_config(uuid, text) to authenticated;
grant execute on function public.reject_pay_config(uuid, text) to service_role;

-- withdraw_pay_config_proposal(): the proposer (or any Manager) cancels a
-- still-pending proposal. Pending -> Rejected.
create function public.withdraw_pay_config_proposal(p_config_id uuid)
returns public.employee_pay_config
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.employee_pay_config;
begin
  perform public.require_finance_writer();

  select * into v_row from public.employee_pay_config where id = p_config_id for update;
  if not found then
    raise exception 'Pay config % not found', p_config_id;
  end if;
  if v_row.approval_status <> 'Pending Approval' then
    raise exception 'Pay config % is not pending approval (status: %)', p_config_id, v_row.approval_status;
  end if;
  if v_row.proposed_by is distinct from auth.uid() and not public.has_role(array['Manager']) then
    raise exception 'You can only withdraw your own pending proposal';
  end if;

  update public.employee_pay_config
  set approval_status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = 'Withdrawn by proposer'
  where id = p_config_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.withdraw_pay_config_proposal(uuid) to authenticated;
grant execute on function public.withdraw_pay_config_proposal(uuid) to service_role;

-- set_pay_config_exemptions(): direct in-place toggle of the statutory
-- flags on the current Active config (Open Question 4 confirmed: not
-- approval-gated).
create function public.set_pay_config_exemptions(
  p_employee_id uuid,
  p_pays_ssnit boolean,
  p_pays_tier2 boolean,
  p_pays_paye boolean
)
returns public.employee_pay_config
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.employee_pay_config;
begin
  perform public.require_finance_writer();

  update public.employee_pay_config
  set pays_ssnit = p_pays_ssnit, pays_tier2 = p_pays_tier2, pays_paye = p_pays_paye
  where employee_id = p_employee_id and approval_status = 'Active' and effective_to is null
  returning * into v_row;

  if not found then
    raise exception 'No active pay config for employee %', p_employee_id;
  end if;

  return v_row;
end;
$$;

grant execute on function public.set_pay_config_exemptions(uuid, boolean, boolean, boolean) to authenticated;
grant execute on function public.set_pay_config_exemptions(uuid, boolean, boolean, boolean) to service_role;
