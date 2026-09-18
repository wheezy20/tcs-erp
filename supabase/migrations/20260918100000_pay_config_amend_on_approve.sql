-- Amend a pending pay config before approving (TCS ERP — follow-up to
-- 20260909130000 / 20260909140000 / 20260909150000).
--
-- Problem: an Accountant's proposed salary/bank/account change (or a
-- bundled new-hire's initial pay config) could previously only be
-- Approved-as-submitted or Rejected. A minor error (mistyped account
-- number) forced a full reject/resubmit cycle even though Contact &
-- Placement fields are already directly editable with no approval gate.
--
-- Fix: `approve_pay_config()` and `approve_employee()` each gain four
-- optional trailing override parameters (basic salary, payment method,
-- bank, account number). `null` (the default) means "leave as proposed" —
-- a plain approval-as-submitted behaves exactly as before, byte-for-byte.
-- A non-null value is applied in the *same* UPDATE that flips
-- approval_status to 'Active', so `audit_employee_pay_config()`'s OLD row
-- is always the Accountant's original proposal and NEW is whatever the
-- Manager actually approved — a direct diff, no extra bookkeeping columns.
--
-- One RPC each (not a separate amend_and_approve_pay_config()): the
-- bundled vs standalone split already forces two entry points
-- (approve_pay_config refuses a not-yet-Active employee's bundled config;
-- approve_employee cascades it instead), so widening both is no new
-- surface, and it keeps "adjust" and "approve" one atomic action/audit
-- event instead of two.
--
-- Scope: basic salary + payment method + bank + account number only.
-- `effective_from` and the exemption flags are out of scope — exemptions
-- are already direct-edit with no gate, and effective_from carries its own
-- re-validation (posted-payslip check) that would meaningfully complicate
-- this. Reject is unchanged — no amendment path there.
--
-- New audit action: pay_config_amended_and_approved, distinct from
-- pay_config_approved, so an audit trail never looks like the Accountant
-- proposed the final number when a Manager actually changed it.

-- =====================================================================
-- 1. audit_log: new action value
-- =====================================================================
alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action in (
  'discount_applied', 'vat_override', 'return_processed',
  'sale_voided', 'invoice_voided', 'expense_voided',
  'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated',
  'pay_config_proposed', 'pay_config_approved', 'pay_config_amended_and_approved',
  'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed'
));

-- =====================================================================
-- 2. audit_employee_pay_config(): detect an approval-time amendment.
-- Same signature (no args — it's a trigger function), so create or
-- replace is fine here; only approve_pay_config/approve_employee below
-- need drop + recreate for the new argument lists.
-- =====================================================================
create or replace function public.audit_employee_pay_config()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.proposed_by, new.reviewed_by);
  v_action text;
  v_before jsonb;
  v_after jsonb;
  v_branch uuid;
  v_amended boolean;
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
    -- An approval (Pending -> Active) where the Manager changed any of the
    -- four amendable fields from what was actually proposed gets its own
    -- action + a before snapshot of the *original proposal*, not just the
    -- prior approval_status — so the diff survives independently of
    -- whatever's in the earlier pay_config_proposed row.
    v_amended := new.approval_status = 'Active'
      and (old.basic_salary, old.payment_method, old.bank, old.account_no)
          is distinct from (new.basic_salary, new.payment_method, new.bank, new.account_no);

    v_action := case
      when v_amended then 'pay_config_amended_and_approved'
      when new.approval_status = 'Active' then 'pay_config_approved'
      when new.approval_status = 'Rejected' then 'pay_config_rejected'
      else null
    end;
    v_before := case
      when v_amended then jsonb_build_object(
        'approval_status', old.approval_status,
        'basic_salary', old.basic_salary, 'payment_method', old.payment_method,
        'bank', old.bank, 'account_no', old.account_no
      )
      else jsonb_build_object('approval_status', old.approval_status)
    end;
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

-- =====================================================================
-- 3. approve_pay_config(): standalone salary/bank change. Adds four
-- optional trailing override params — drop + recreate, per this repo's
-- rule for any argument-list change (check-duplicate-function-overloads.sh).
-- =====================================================================
drop function if exists public.approve_pay_config(uuid);

create function public.approve_pay_config(
  p_config_id uuid,
  p_basic_salary numeric default null,
  p_payment_method text default null,
  p_bank text default null,
  p_account_no text default null
)
returns public.employee_pay_config
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pending public.employee_pay_config;
  v_emp_status text;
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

  select employment_status into v_emp_status from public.employees where id = v_pending.employee_id;
  if v_emp_status <> 'Active' then
    raise exception
      'This pay config is part of an employee record that is not yet active (%). Approve the employee record instead.',
      v_emp_status;
  end if;

  if p_basic_salary is not null and p_basic_salary < 0 then
    raise exception 'Basic salary cannot be negative';
  end if;
  if p_payment_method is not null and p_payment_method not in ('Bank', 'Mobile Money') then
    raise exception 'Payment method must be Bank or Mobile Money';
  end if;

  update public.employee_pay_config
  set effective_to = (v_pending.effective_from - 1)
  where employee_id = v_pending.employee_id
    and approval_status = 'Active'
    and effective_to is null;

  update public.employee_pay_config
  set approval_status = 'Active',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      basic_salary = coalesce(p_basic_salary, basic_salary),
      payment_method = coalesce(p_payment_method, payment_method),
      bank = case when p_bank is not null then nullif(trim(p_bank), '') else bank end,
      account_no = case when p_account_no is not null then nullif(trim(p_account_no), '') else account_no end
  where id = p_config_id
  returning * into v_pending;

  return v_pending;
end;
$$;

grant execute on function public.approve_pay_config(uuid, numeric, text, text, text) to authenticated;
grant execute on function public.approve_pay_config(uuid, numeric, text, text, text) to service_role;

-- =====================================================================
-- 4. approve_employee(): same four optional overrides, applied to the
-- bundled initial pay config it cascades-approves. Symmetric with
-- approve_pay_config above so a bundled new-hire proposal gets the same
-- amend-before-approve treatment as a standalone change.
-- =====================================================================
drop function if exists public.approve_employee(uuid);

create function public.approve_employee(
  p_employee_id uuid,
  p_basic_salary numeric default null,
  p_payment_method text default null,
  p_bank text default null,
  p_account_no text default null
)
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

  if p_basic_salary is not null and p_basic_salary < 0 then
    raise exception 'Basic salary cannot be negative';
  end if;
  if p_payment_method is not null and p_payment_method not in ('Bank', 'Mobile Money') then
    raise exception 'Payment method must be Bank or Mobile Money';
  end if;

  update public.employees
  set employment_status = 'Active', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_employee_id
  returning * into v_emp;

  -- Approve the bundled initial config, if any and only if nothing is
  -- already Active for this employee (always true for a new record),
  -- applying any override in the same statement that flips it Active.
  update public.employee_pay_config
  set approval_status = 'Active',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      basic_salary = coalesce(p_basic_salary, basic_salary),
      payment_method = coalesce(p_payment_method, payment_method),
      bank = case when p_bank is not null then nullif(trim(p_bank), '') else bank end,
      account_no = case when p_account_no is not null then nullif(trim(p_account_no), '') else account_no end
  where employee_id = p_employee_id
    and approval_status = 'Pending Approval'
    and not exists (
      select 1 from public.employee_pay_config a
      where a.employee_id = p_employee_id and a.approval_status = 'Active' and a.effective_to is null
    );

  return v_emp;
end;
$$;

grant execute on function public.approve_employee(uuid, numeric, text, text, text) to authenticated;
grant execute on function public.approve_employee(uuid, numeric, text, text, text) to service_role;
