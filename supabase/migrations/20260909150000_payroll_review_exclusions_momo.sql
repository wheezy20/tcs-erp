-- Payroll run review workflow + per-run exclusions + Mobile Money as a
-- payment method (TCS ERP — Group A follow-up to 20260909130000 /
-- 20260909140000).
--
-- 1. Run review state machine. Was Draft -> Posted (any finance writer
--    posts). Now:
--        Draft --submit--> Ready for Review --approve--> Posted
--          ^                      |
--          +------ reject --------+   (reason required)
--    An Accountant submits a run they're satisfied with; a Manager either
--    approves (which IS the post — approval and posting are one step, so
--    posting is now Manager-only) or rejects with a reason, sending it
--    back to Draft for revision. Payslip edits are already blocked on any
--    non-Draft run (create_payslip / delete_payslip raise), so
--    'Ready for Review' locks them for free.
--
-- 2. "Exclude from this run" — payroll_run_exclusions. A per-run marker
--    that an active employee is deliberately not being paid this cycle
--    (optional reason, audit-logged). The completeness check that gates
--    submission now passes when every active employee with an approved
--    pay config either has a payslip OR an exclusion.
--
-- 3. Mobile Money. `banks` becomes `payment_providers` with a `kind`
--    discriminator ('Bank' | 'Mobile Money') — same editable-list shape,
--    it just also holds MTN / Telecel Cash / AirtelTigo Money now.
--    `employee_pay_config` gains `payment_method`; `bank` / `account_no`
--    double as the destination pair (network name / wallet number when
--    the method is Mobile Money). Recording the destination only — how a
--    run is actually disbursed is out of scope, and the journal entry is
--    unchanged (net still credits 2300 regardless of method).
--
-- "Email payslips" (a Posted-run bulk action) is deferred to its own task
-- — no email provider is wired in this repo and `employees` has no email
-- column. The run page ships a disabled "coming soon" affordance.

-- =====================================================================
-- 1. payroll_runs — review state machine
-- =====================================================================
alter table public.payroll_runs drop constraint if exists payroll_runs_status_check;
alter table public.payroll_runs add constraint payroll_runs_status_check
  check (status in ('Draft', 'Ready for Review', 'Posted'));

alter table public.payroll_runs
  add column submitted_by uuid references public.staff (id) on delete set null,
  add column submitted_at timestamptz,
  add column reviewed_by uuid references public.staff (id) on delete set null,
  add column reviewed_at timestamptz,
  -- Set on reject, shown in the Draft banner so the submitter sees why;
  -- cleared on the next submit.
  add column rejection_reason text;

-- =====================================================================
-- 2. payroll_run_exclusions
-- =====================================================================
create table public.payroll_run_exclusions (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.payroll_runs (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete restrict,
  reason text,
  -- Server-forced from auth.uid() by the RPC; nullable for the seed /
  -- service_role context, same as payroll_runs.created_by.
  excluded_by uuid references public.staff (id) on delete set null,
  excluded_at timestamptz not null default now(),
  unique (payroll_run_id, employee_id)
);

create index payroll_run_exclusions_run_idx
  on public.payroll_run_exclusions (payroll_run_id);

alter table public.payroll_run_exclusions enable row level security;

-- select for the three back-office roles; no write policy — the two RPCs
-- below (SECURITY DEFINER) are the only write path, same model as
-- payslips / payroll_runs.
create policy payroll_run_exclusions_select on public.payroll_run_exclusions
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

revoke all on public.payroll_run_exclusions from anon;
grant select on public.payroll_run_exclusions to authenticated;
grant select, insert, update, delete on public.payroll_run_exclusions to service_role;

-- =====================================================================
-- 3. audit_log: new action values
-- =====================================================================
alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action in (
  'discount_applied', 'vat_override', 'return_processed',
  'sale_voided', 'invoice_voided', 'expense_voided',
  'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated',
  'pay_config_proposed', 'pay_config_approved', 'pay_config_rejected',
  'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed'
));

-- payroll_runs status transitions. No trigger existed on this table before;
-- INSERT (always Draft) is not audited, only the review transitions.
create or replace function public.audit_payroll_run()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.submitted_by, new.reviewed_by, new.created_by);
  v_action text;
  v_period text := to_char(make_date(new.year, new.month, 1), 'FMMonth YYYY');
begin
  if old.status is not distinct from new.status then return new; end if;
  if v_actor is null then return new; end if;

  v_action := case
    when old.status = 'Draft' and new.status = 'Ready for Review' then 'payroll_run_submitted'
    when old.status = 'Ready for Review' and new.status = 'Posted' then 'payroll_run_approved'
    when old.status = 'Ready for Review' and new.status = 'Draft' then 'payroll_run_rejected'
    else null
  end;
  if v_action is null then return new; end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    new.branch_id, v_actor, v_action, 'payroll_runs', new.id::text,
    jsonb_build_object('status', old.status),
    jsonb_build_object('status', new.status, 'period', v_period, 'reason', new.rejection_reason)
  );
  return new;
end;
$$;

create trigger payroll_runs_audit
after update on public.payroll_runs
for each row execute function public.audit_payroll_run();

create or replace function public.audit_payroll_run_exclusion()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_row public.payroll_run_exclusions := case when tg_op = 'DELETE' then old else new end;
  v_actor uuid := coalesce(auth.uid(), v_row.excluded_by);
  v_branch uuid;
  v_emp_name text;
begin
  if v_actor is null then return null; end if;
  select branch_id into v_branch from public.payroll_runs where id = v_row.payroll_run_id;
  if v_branch is null then return null; end if;
  select name into v_emp_name from public.employees where id = v_row.employee_id;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor,
    case when tg_op = 'INSERT' then 'payroll_run_exclusion_added'
         else 'payroll_run_exclusion_removed' end,
    'payroll_run_exclusions', v_row.id::text,
    case when tg_op = 'DELETE'
      then jsonb_build_object('employee', v_emp_name, 'reason', v_row.reason) end,
    case when tg_op = 'INSERT'
      then jsonb_build_object('employee', v_emp_name, 'reason', v_row.reason,
                              'payroll_run_id', v_row.payroll_run_id::text) end
  );
  return null;
end;
$$;

create trigger payroll_run_exclusions_audit
after insert or delete on public.payroll_run_exclusions
for each row execute function public.audit_payroll_run_exclusion();

-- =====================================================================
-- Completeness helper — the shared definition of "this run accounts for
-- everyone it should". Used by submit_payroll_run_for_review(); the run
-- page computes the same set client-side for the UI gate.
--
-- An active employee with a current approved pay config must have either
-- a payslip on the run or an explicit exclusion. Employees with no
-- approved config still can't be paid and don't block — the UI surfaces
-- them as a non-blocking warning.
-- =====================================================================
create or replace function public._payroll_run_unaccounted(p_run_id uuid)
returns table (employee_id uuid, name text)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.name
  from public.employees e
  join public.payroll_runs r on r.id = p_run_id
  where e.employment_status = 'Active'
    and e.branch_id = r.branch_id
    and exists (
      select 1 from public.employee_pay_config c
      where c.employee_id = e.id
        and c.approval_status = 'Active'
        and c.effective_to is null
    )
    and not exists (
      select 1 from public.payslips ps
      where ps.payroll_run_id = p_run_id and ps.employee_id = e.id
    )
    and not exists (
      select 1 from public.payroll_run_exclusions x
      where x.payroll_run_id = p_run_id and x.employee_id = e.id
    );
$$;

-- =====================================================================
-- Review RPCs
-- =====================================================================

-- submit_payroll_run_for_review(): Draft -> Ready for Review. Any finance
-- writer (Manager or Accountant). Enforces the completeness check so a
-- half-done run can't reach the Manager.
create or replace function public.submit_payroll_run_for_review(p_run_id uuid)
returns public.payroll_runs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
  v_count integer;
  v_missing text;
begin
  perform public.require_finance_writer();

  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Only a Draft run can be submitted for review (status: %)', v_run.status;
  end if;

  select count(*) into v_count from public.payslips where payroll_run_id = p_run_id;
  if v_count = 0 then
    raise exception 'Generate at least one payslip before submitting this run for review';
  end if;

  select string_agg(name, ', ' order by name) into v_missing
  from public._payroll_run_unaccounted(p_run_id);
  if v_missing is not null then
    raise exception
      'These active employees have neither a payslip nor an exclusion on this run: %', v_missing;
  end if;

  update public.payroll_runs
  set status = 'Ready for Review',
      submitted_by = auth.uid(),
      submitted_at = now(),
      rejection_reason = null
  where id = p_run_id
  returning * into v_run;

  return v_run;
end;
$$;

grant execute on function public.submit_payroll_run_for_review(uuid) to authenticated;
grant execute on function public.submit_payroll_run_for_review(uuid) to service_role;

-- reject_payroll_run(): Ready for Review -> Draft, with a required reason.
-- Manager only. Payslips become editable again.
create or replace function public.reject_payroll_run(p_run_id uuid, p_reason text)
returns public.payroll_runs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can reject a payroll run';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'A reason is required to reject a run';
  end if;

  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_run.status <> 'Ready for Review' then
    raise exception 'Only a run awaiting review can be rejected (status: %)', v_run.status;
  end if;

  update public.payroll_runs
  set status = 'Draft',
      rejection_reason = trim(p_reason),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_run_id
  returning * into v_run;

  return v_run;
end;
$$;

grant execute on function public.reject_payroll_run(uuid, text) to authenticated;
grant execute on function public.reject_payroll_run(uuid, text) to service_role;

-- ---------------------------------------------------------------------
-- post_payroll_run(): now the Manager "approve" step. Changes vs the
-- 20260909120000 version:
--   * require Manager (was require_finance_writer()) — approval == posting
--   * require status 'Ready for Review' (was 'Draft')
--   * stamp reviewed_by / reviewed_at alongside the status flip
-- The journal-entry construction is byte-for-byte the same.
-- ---------------------------------------------------------------------
create or replace function public.post_payroll_run(p_run_id uuid)
returns public.journal_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
  v_entry_date date;
  v_period text;
  v_count integer := 0;
  v_gross numeric := 0;
  v_ssnit numeric := 0;
  v_ssnit_employer numeric := 0;
  v_tier2 numeric := 0;
  v_paye numeric := 0;
  v_fines numeric := 0;
  v_iou numeric := 0;
  v_net numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_entry public.journal_entries;
begin
  -- Approval and posting are one step, so this is Manager-only now
  -- (an Accountant gets the run to 'Ready for Review'; a Manager approves).
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve and post a payroll run';
  end if;

  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_run.status = 'Posted' then
    raise exception 'Payroll run % is already posted', p_run_id;
  end if;
  if v_run.status <> 'Ready for Review' then
    raise exception 'Submit the run for review before it can be approved (status: %)', v_run.status;
  end if;

  select
    count(*),
    coalesce(sum(gross_salary), 0),
    coalesce(sum(ssnit), 0),
    coalesce(sum(ssnit_employer), 0),
    coalesce(sum(tier2), 0),
    coalesce(sum(tax), 0),
    coalesce(sum(fines), 0),
    coalesce(sum(iou), 0),
    coalesce(sum(net_pay), 0)
  into v_count, v_gross, v_ssnit, v_ssnit_employer, v_tier2, v_paye, v_fines, v_iou, v_net
  from public.payslips
  where payroll_run_id = p_run_id;

  if v_count = 0 then
    raise exception 'Payroll run % has no payslips to post', p_run_id;
  end if;
  if v_net <= 0 then
    raise exception 'Total net pay for run % must be positive to post (got %)', p_run_id, v_net;
  end if;

  -- Last calendar day of the run's month — pay is accrued at period end.
  v_entry_date := (make_date(v_run.year, v_run.month, 1) + interval '1 month' - interval '1 day')::date;
  v_period := to_char(make_date(v_run.year, v_run.month, 1), 'FMMonth YYYY');

  v_lines := v_lines
    || jsonb_build_object(
      'account_id', public.account_id_by_code('5140'),
      'debit', v_gross, 'credit', 0, 'description', 'Gross pay — ' || v_period
    )
    || jsonb_build_object(
      'account_id', public.account_id_by_code('2300'),
      'debit', 0, 'credit', v_net, 'description', 'Net pay payable — ' || v_period
    );

  if v_ssnit > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2310'),
      'debit', 0, 'credit', v_ssnit, 'description', 'SSNIT withheld — ' || v_period
    );
  end if;
  if v_ssnit_employer > 0 then
    v_lines := v_lines
      || jsonb_build_object(
        'account_id', public.account_id_by_code('5145'),
        'debit', v_ssnit_employer, 'credit', 0,
        'description', 'Employer SSNIT contribution — ' || v_period
      )
      || jsonb_build_object(
        'account_id', public.account_id_by_code('2310'),
        'debit', 0, 'credit', v_ssnit_employer,
        'description', 'Employer SSNIT contribution — ' || v_period
      );
  end if;
  if v_tier2 > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2320'),
      'debit', 0, 'credit', v_tier2, 'description', 'Tier 2 withheld — ' || v_period
    );
  end if;
  if v_paye > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2330'),
      'debit', 0, 'credit', v_paye, 'description', 'PAYE withheld — ' || v_period
    );
  end if;
  if v_iou > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('1350'),
      'debit', 0, 'credit', v_iou, 'description', 'Staff advance recovery — ' || v_period
    );
  end if;
  if v_fines > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('4910'),
      'debit', 0, 'credit', v_fines, 'description', 'Staff fines recovered — ' || v_period
    );
  end if;

  v_entry := public._post_journal_entry_rows(
    v_run.branch_id,
    v_entry_date,
    'Payroll — ' || v_period,
    p_run_id::text,
    v_lines,
    'payroll_runs',
    p_run_id::text
  );

  update public.payroll_runs
  set status = 'Posted', posted_at = now(),
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_run_id;

  return v_entry;
end;
$$;

-- =====================================================================
-- Exclusion RPCs — Manager or Accountant, Draft runs only.
-- =====================================================================
create or replace function public.exclude_employee_from_run(
  p_run_id uuid,
  p_employee_id uuid,
  p_reason text default null
)
returns public.payroll_run_exclusions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_row public.payroll_run_exclusions;
begin
  perform public.require_finance_writer();

  select status into v_status from public.payroll_runs where id = p_run_id;
  if v_status is null then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_status <> 'Draft' then
    raise exception 'Exclusions can only be changed while the run is a Draft (status: %)', v_status;
  end if;
  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if exists (
    select 1 from public.payslips
    where payroll_run_id = p_run_id and employee_id = p_employee_id
  ) then
    raise exception 'That employee already has a payslip on this run — delete it first';
  end if;

  insert into public.payroll_run_exclusions (payroll_run_id, employee_id, reason, excluded_by)
  values (p_run_id, p_employee_id, nullif(trim(p_reason), ''), auth.uid())
  on conflict (payroll_run_id, employee_id)
    do update set reason = excluded.reason, excluded_by = excluded.excluded_by, excluded_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.exclude_employee_from_run(uuid, uuid, text) to authenticated;
grant execute on function public.exclude_employee_from_run(uuid, uuid, text) to service_role;

create or replace function public.include_employee_in_run(p_run_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  perform public.require_finance_writer();

  select status into v_status from public.payroll_runs where id = p_run_id;
  if v_status is null then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_status <> 'Draft' then
    raise exception 'Exclusions can only be changed while the run is a Draft (status: %)', v_status;
  end if;

  delete from public.payroll_run_exclusions
  where payroll_run_id = p_run_id and employee_id = p_employee_id;
end;
$$;

grant execute on function public.include_employee_in_run(uuid, uuid) to authenticated;
grant execute on function public.include_employee_in_run(uuid, uuid) to service_role;

-- =====================================================================
-- 3. banks -> payment_providers (+ kind), Mobile Money networks
-- =====================================================================
alter table public.banks rename to payment_providers;
alter table public.payment_providers rename constraint banks_pkey to payment_providers_pkey;
alter table public.payment_providers rename constraint banks_name_key to payment_providers_name_key;
alter index public.banks_position_idx rename to payment_providers_position_idx;
alter policy banks_select on public.payment_providers rename to payment_providers_select;
alter policy banks_insert on public.payment_providers rename to payment_providers_insert;
alter policy banks_update on public.payment_providers rename to payment_providers_update;
alter policy banks_delete on public.payment_providers rename to payment_providers_delete;

-- The list is no longer only banks: a kind discriminator drives which
-- picker (bank vs mobile-money network) offers the row. Existing 23 rows
-- are all banks.
alter table public.payment_providers
  add column kind text not null default 'Bank'
    check (kind in ('Bank', 'Mobile Money'));

-- The three mobile-money schemes operating in Ghana. Telecel Cash is the
-- post-2023 name for what was Vodafone Cash. The school edits this list
-- itself; positions sit above the banks so they group at the end.
insert into public.payment_providers (name, kind, position) values
  ('MTN Mobile Money', 'Mobile Money', 100),
  ('Telecel Cash', 'Mobile Money', 101),
  ('AirtelTigo Money', 'Mobile Money', 102)
on conflict (name) do nothing;

-- =====================================================================
-- employee_pay_config.payment_method. 'Bank' | 'Mobile Money'. When it's
-- Mobile Money the existing `bank` column holds the network name and
-- `account_no` the wallet phone — no new columns, no data migration
-- (existing rows are all 'Bank', which is what they are). The journal
-- entry never reads these; changing the method rides the same approval
-- gate as changing bank/account.
-- =====================================================================
alter table public.employee_pay_config
  add column payment_method text not null default 'Bank'
    check (payment_method in ('Bank', 'Mobile Money'));

-- ---------------------------------------------------------------------
-- audit_employee_pay_config(): carry payment_method in the proposal /
-- approval payloads. Only change vs the 20260909130000 version.
-- ---------------------------------------------------------------------
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
      'basic_salary', new.basic_salary, 'payment_method', new.payment_method,
      'bank', new.bank, 'account_no', new.account_no,
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
      'payment_method', new.payment_method, 'bank', new.bank, 'account_no', new.account_no,
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
    return new;
  end if;

  if v_action is null then return new; end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (v_branch, v_actor, v_action, 'employee_pay_config', new.id::text, v_before, v_after);
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- propose_employee() / propose_pay_config_change(): add p_payment_method
-- (a new trailing parameter, so drop + recreate per the
-- check-duplicate-function-overloads.sh rule). Bodies are otherwise the
-- 20260909130000 versions with payment_method threaded into the config
-- insert.
-- ---------------------------------------------------------------------
drop function if exists public.propose_employee(
  text, uuid, text, text, text, uuid, numeric, text, text, boolean, boolean, boolean, date);

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
  p_effective_from date default null,
  p_payment_method text default 'Bank'
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
  if coalesce(p_payment_method, 'Bank') not in ('Bank', 'Mobile Money') then
    raise exception 'Payment method must be Bank or Mobile Money';
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

  if p_staff_id is not null then
    update public.staff set employee_id = v_emp.id where id = p_staff_id;
  end if;

  if p_basic_salary is not null then
    if p_basic_salary < 0 then
      raise exception 'Basic salary cannot be negative';
    end if;
    insert into public.employee_pay_config
      (employee_id, payment_method, bank, account_no, basic_salary,
       pays_ssnit, pays_tier2, pays_paye, effective_from, approval_status, proposed_by)
    values
      (v_emp.id, coalesce(p_payment_method, 'Bank'),
       nullif(trim(p_bank), ''), nullif(trim(p_account_no), ''), p_basic_salary,
       p_pays_ssnit, p_pays_tier2, p_pays_paye, v_eff, 'Pending Approval', auth.uid());
  end if;

  return v_emp;
end;
$$;

grant execute on function public.propose_employee(
  text, uuid, text, text, text, uuid, numeric, text, text, boolean, boolean, boolean, date, text
) to authenticated;
grant execute on function public.propose_employee(
  text, uuid, text, text, text, uuid, numeric, text, text, boolean, boolean, boolean, date, text
) to service_role;

drop function if exists public.propose_pay_config_change(
  uuid, date, numeric, text, text, boolean, boolean, boolean);

create function public.propose_pay_config_change(
  p_employee_id uuid,
  p_effective_from date,
  p_basic_salary numeric,
  p_bank text,
  p_account_no text,
  p_pays_ssnit boolean,
  p_pays_tier2 boolean,
  p_pays_paye boolean,
  p_payment_method text default 'Bank'
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
  if coalesce(p_payment_method, 'Bank') not in ('Bank', 'Mobile Money') then
    raise exception 'Payment method must be Bank or Mobile Money';
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
    (employee_id, payment_method, bank, account_no, basic_salary,
     pays_ssnit, pays_tier2, pays_paye, effective_from, approval_status, proposed_by)
  values
    (p_employee_id, coalesce(p_payment_method, 'Bank'),
     nullif(trim(p_bank), ''), nullif(trim(p_account_no), ''), p_basic_salary,
     p_pays_ssnit, p_pays_tier2, p_pays_paye, p_effective_from, 'Pending Approval', auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.propose_pay_config_change(
  uuid, date, numeric, text, text, boolean, boolean, boolean, text
) to authenticated;
grant execute on function public.propose_pay_config_change(
  uuid, date, numeric, text, text, boolean, boolean, boolean, text
) to service_role;

-- create_payslip() is unaffected: payment_method changes where net pay is
-- sent, not how it's computed or posted.
