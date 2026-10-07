-- Staff advances (IOU loans): recorded once, repaid automatically through
-- payroll until fully repaid or stopped.
--
-- Decisions (Eyram, 2026-10-07):
--   * An Accountant (or Manager) proposes an advance, and proposes any
--     pause, resume, cancel or instalment change; a Manager approves or
--     rejects. Nothing takes effect until approved. A Manager may approve
--     their own proposal; proposer and approver are both recorded and
--     audited.
--   * Approval posts the payout: Dr 1350 Advances to Staff / Cr the account
--     for the payout method (Cash 1000, Mobile Money 1020, Bank Transfer the
--     chosen bank account), dated the payout date. Account 1350 is NOT YET
--     CONFIRMED by the accountant (docs/CONSTRAINTS.md).
--   * Repayment is deducted in create_payslip (20261008110000) through the
--     existing payslips.iou line: after tax, not reducing taxable income
--     (accountant confirmed, reported by Eyram 2026-10-07, written copy to be
--     saved). post_payroll_run already credits payslips.iou to 1350.
--   * Cancel only stops deductions; the balance stays outstanding on 1350
--     (write-off is PENDING).
--
-- Conventions:
--   * Balance is never stored: amount minus the sum of repayment rows.
--     "Settled" is never stored either: an Active or Paused advance whose
--     balance is 0 displays as Settled. Repayment rows cascade-delete with
--     their payslip, so deleting or regenerating a Draft payslip restores
--     the balance by itself; a posted payslip can't be deleted.
--   * The three tables are select-only for Manager, Accountant and Auditor;
--     every write goes through the SECURITY DEFINER functions below.
--   * Money inputs follow 20261007110000: plain numeric, the
--     _refuse_over_2dp() trigger (no negatives, at most 2 dp) and *_2dp
--     checks.

-- ============================================================ 1. tables

create table public.staff_advances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete restrict,
  amount numeric not null,
  instalment numeric not null,
  first_repayment_month date not null,
  disbursed_on date not null,
  disbursement_method text not null,
  bank_account_id uuid references public.bank_accounts (id) on delete restrict,
  note text,
  status text not null default 'Proposed',
  proposed_by uuid references public.staff (id) on delete set null,
  proposed_at timestamptz not null default now(),
  reviewed_by uuid references public.staff (id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  constraint staff_advances_status_check
    check (status in ('Proposed', 'Active', 'Paused', 'Cancelled', 'Rejected')),
  constraint staff_advances_method_check
    check (disbursement_method in ('Cash', 'Mobile Money', 'Bank Transfer')),
  constraint staff_advances_bank_account_check
    check ((disbursement_method = 'Bank Transfer') = (bank_account_id is not null)),
  constraint staff_advances_first_month_check
    check (first_repayment_month = date_trunc('month', first_repayment_month)::date),
  constraint staff_advances_amount_check check (amount > 0),
  constraint staff_advances_instalment_check check (instalment > 0 and instalment <= amount),
  constraint staff_advances_amount_2dp
    check (amount = round(amount, 2) and abs(amount) < 1e10),
  constraint staff_advances_instalment_2dp
    check (instalment = round(instalment, 2) and abs(instalment) < 1e10)
);

create index staff_advances_employee_idx on public.staff_advances (employee_id, status);

create table public.staff_advance_change_requests (
  id uuid primary key default gen_random_uuid(),
  advance_id uuid not null references public.staff_advances (id) on delete restrict,
  kind text not null,
  new_instalment numeric,
  reason text,
  status text not null default 'Pending Approval',
  proposed_by uuid references public.staff (id) on delete set null,
  proposed_at timestamptz not null default now(),
  reviewed_by uuid references public.staff (id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  constraint staff_advance_change_requests_kind_check
    check (kind in ('Pause', 'Resume', 'Cancel', 'Instalment')),
  constraint staff_advance_change_requests_instalment_check
    check ((kind = 'Instalment') = (new_instalment is not null) and coalesce(new_instalment, 1) > 0),
  constraint staff_advance_change_requests_new_instalment_2dp
    check (new_instalment = round(new_instalment, 2) and abs(new_instalment) < 1e10),
  constraint staff_advance_change_requests_status_check
    check (status in ('Pending Approval', 'Approved', 'Rejected'))
);

-- One pending change per advance at a time.
create unique index staff_advance_change_requests_one_pending
  on public.staff_advance_change_requests (advance_id) where status = 'Pending Approval';

create table public.staff_advance_repayments (
  id uuid primary key default gen_random_uuid(),
  advance_id uuid not null references public.staff_advances (id) on delete restrict,
  payslip_id uuid not null references public.payslips (id) on delete cascade,
  amount numeric not null,
  instalment_due numeric not null,
  created_at timestamptz not null default now(),
  constraint staff_advance_repayments_once unique (advance_id, payslip_id),
  constraint staff_advance_repayments_amount_check check (amount > 0 and amount <= instalment_due),
  constraint staff_advance_repayments_amount_2dp
    check (amount = round(amount, 2) and abs(amount) < 1e10),
  constraint staff_advance_repayments_instalment_due_2dp
    check (instalment_due = round(instalment_due, 2) and abs(instalment_due) < 1e10)
);

create index staff_advance_repayments_payslip_idx on public.staff_advance_repayments (payslip_id);

create trigger staff_advances_inputs_2dp
  before insert or update on public.staff_advances
  for each row execute function public._refuse_over_2dp(
    'amount:Advance amount:1e10',
    'instalment:Monthly instalment:1e10');

create trigger staff_advance_change_requests_inputs_2dp
  before insert or update on public.staff_advance_change_requests
  for each row execute function public._refuse_over_2dp('new_instalment:Monthly instalment:1e10');

create trigger staff_advance_repayments_inputs_2dp
  before insert or update on public.staff_advance_repayments
  for each row execute function public._refuse_over_2dp(
    'amount:Repayment:1e10',
    'instalment_due:Instalment due:1e10');

-- Once an advance leaves Proposed, only its instalment, status and review
-- columns may change (and only through the functions below).
create function public.staff_advances_freeze()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'Proposed'
     and (new.employee_id, new.amount, new.first_repayment_month, new.disbursed_on,
          new.disbursement_method, new.bank_account_id, new.proposed_by, new.proposed_at)
         is distinct from
         (old.employee_id, old.amount, old.first_repayment_month, old.disbursed_on,
          old.disbursement_method, old.bank_account_id, old.proposed_by, old.proposed_at) then
    raise exception 'An approved staff advance''s amount, dates and payout cannot be changed';
  end if;
  return new;
end;
$$;

create trigger staff_advances_freeze
  before update on public.staff_advances
  for each row execute function public.staff_advances_freeze();

-- ============================================================ 2. RLS and grants

alter table public.staff_advances enable row level security;
alter table public.staff_advance_change_requests enable row level security;
alter table public.staff_advance_repayments enable row level security;

create policy staff_advances_select on public.staff_advances
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy staff_advance_change_requests_select on public.staff_advance_change_requests
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy staff_advance_repayments_select on public.staff_advance_repayments
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

revoke all on table public.staff_advances from anon, authenticated;
revoke all on table public.staff_advance_change_requests from anon, authenticated;
revoke all on table public.staff_advance_repayments from anon, authenticated;
grant select on table public.staff_advances to authenticated;
grant select on table public.staff_advance_change_requests to authenticated;
grant select on table public.staff_advance_repayments to authenticated;
grant select, insert, update, delete on table public.staff_advances to service_role;
grant select, insert, update, delete on table public.staff_advance_change_requests to service_role;
grant select, insert, update, delete on table public.staff_advance_repayments to service_role;

-- ============================================================ 3. audit

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action = any (array[
  'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
  'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
  'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
  'admissions_capabilities_changed',
  'staff_advance_proposed', 'staff_advance_approved', 'staff_advance_rejected',
  'staff_advance_change_proposed', 'staff_advance_change_approved',
  'staff_advance_change_rejected'
]));

-- Writes with no signed-in actor (migrations, seed, service_role) aren't
-- audited, as for the other audit triggers. A withdrawal is recorded as a
-- rejection with the reason 'Withdrawn by proposer', as for pay config.
create function public.audit_staff_advances()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.proposed_by, new.reviewed_by);
  v_branch uuid;
  v_action text;
begin
  if v_actor is null then return new; end if;
  select branch_id into v_branch from public.employees where id = new.employee_id;
  if v_branch is null then return new; end if;

  if tg_op = 'INSERT' then
    if new.status <> 'Proposed' then return new; end if;
    v_action := 'staff_advance_proposed';
  elsif old.status = 'Proposed' and new.status = 'Active' then
    v_action := 'staff_advance_approved';
  elsif old.status = 'Proposed' and new.status = 'Rejected' then
    v_action := 'staff_advance_rejected';
  else
    return new; -- later changes are audited on staff_advance_change_requests
  end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, v_action, 'staff_advances', new.id::text,
    case when tg_op = 'UPDATE' then jsonb_build_object('status', old.status) end,
    jsonb_build_object(
      'status', new.status, 'employee_id', new.employee_id, 'amount', new.amount,
      'instalment', new.instalment, 'first_repayment_month', new.first_repayment_month,
      'disbursed_on', new.disbursed_on, 'disbursement_method', new.disbursement_method,
      'bank_account_id', new.bank_account_id, 'proposed_by', new.proposed_by,
      'reviewed_by', new.reviewed_by, 'reason', new.rejection_reason)
  );
  return new;
end;
$$;

create trigger staff_advances_audit
  after insert or update on public.staff_advances
  for each row execute function public.audit_staff_advances();

create function public.audit_staff_advance_change_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.proposed_by, new.reviewed_by);
  v_branch uuid;
  v_action text;
begin
  if v_actor is null then return new; end if;
  select e.branch_id into v_branch
  from public.staff_advances a join public.employees e on e.id = a.employee_id
  where a.id = new.advance_id;
  if v_branch is null then return new; end if;

  if tg_op = 'INSERT' then
    v_action := 'staff_advance_change_proposed';
  elsif old.status is distinct from new.status and new.status = 'Approved' then
    v_action := 'staff_advance_change_approved';
  elsif old.status is distinct from new.status and new.status = 'Rejected' then
    v_action := 'staff_advance_change_rejected';
  else
    return new;
  end if;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, v_action, 'staff_advance_change_requests', new.id::text,
    case when tg_op = 'UPDATE' then jsonb_build_object('status', old.status) end,
    jsonb_build_object(
      'status', new.status, 'advance_id', new.advance_id, 'kind', new.kind,
      'new_instalment', new.new_instalment, 'reason', new.reason,
      'proposed_by', new.proposed_by, 'reviewed_by', new.reviewed_by,
      'rejection_reason', new.rejection_reason)
  );
  return new;
end;
$$;

create trigger staff_advance_change_requests_audit
  after insert or update on public.staff_advance_change_requests
  for each row execute function public.audit_staff_advance_change_requests();

-- ============================================================ 4. read functions

-- Every advance (optionally one employee's) with its computed repaid amount,
-- balance and display status. SECURITY INVOKER: RLS limits it to Manager,
-- Accountant and Auditor.
create function public.staff_advance_summary(p_employee_id uuid default null)
returns table (
  id uuid,
  employee_id uuid,
  employee_name text,
  employee_status text,
  amount numeric,
  instalment numeric,
  first_repayment_month date,
  disbursed_on date,
  disbursement_method text,
  bank_account_id uuid,
  note text,
  status text,
  display_status text,
  repaid numeric,
  balance numeric,
  proposed_by uuid,
  proposed_at timestamptz,
  reviewed_by uuid,
  reviewed_at timestamptz,
  rejection_reason text
)
language sql
stable
set search_path = public
as $$
  select
    a.id, a.employee_id, e.name, e.employment_status,
    a.amount, a.instalment, a.first_repayment_month, a.disbursed_on,
    a.disbursement_method, a.bank_account_id, a.note, a.status,
    case
      when a.status in ('Active', 'Paused') and a.amount - coalesce(r.repaid, 0) <= 0 then 'Settled'
      else a.status
    end,
    coalesce(r.repaid, 0),
    a.amount - coalesce(r.repaid, 0),
    a.proposed_by, a.proposed_at, a.reviewed_by, a.reviewed_at, a.rejection_reason
  from public.staff_advances a
  join public.employees e on e.id = a.employee_id
  left join (
    select advance_id, sum(amount) as repaid
    from public.staff_advance_repayments
    group by advance_id
  ) r on r.advance_id = a.id
  where p_employee_id is null or a.employee_id = p_employee_id
  order by a.proposed_at desc, a.id;
$$;

-- What create_payslip would deduct from this employee's advances for this
-- run, before the net-pay cap: one row per Active or Paused or Cancelled
-- advance, oldest approval first, with due = least(instalment, balance)
-- when it would be deducted, or a skip_reason. create_payslip uses this
-- same function, so the preview and the deduction can't disagree.
create function public.staff_advance_deduction_preview(p_employee_id uuid, p_payroll_run_id uuid)
returns table (
  advance_id uuid,
  ord integer,
  instalment numeric,
  balance numeric,
  due numeric,
  skip_reason text
)
language sql
stable
set search_path = public
as $$
  with run as (
    select make_date(year, month, 1) as run_month
    from public.payroll_runs where id = p_payroll_run_id
  ),
  adv as (
    select
      a.id, a.status, a.instalment, a.first_repayment_month, a.reviewed_at,
      a.amount - coalesce((
        select sum(r.amount) from public.staff_advance_repayments r where r.advance_id = a.id
      ), 0) as balance,
      exists (
        select 1
        from public.staff_advance_repayments r
        join public.payslips p on p.id = r.payslip_id
        join public.payroll_runs pr on pr.id = p.payroll_run_id
        where r.advance_id = a.id
          and make_date(pr.year, pr.month, 1) > (select run_month from run)
      ) as later_repaid
    from public.staff_advances a
    where a.employee_id = p_employee_id
      and a.status in ('Active', 'Paused', 'Cancelled')
  ),
  judged as (
    select
      adv.*,
      case
        when adv.status = 'Paused' then 'Paused'
        when adv.status = 'Cancelled' then 'Cancelled'
        when adv.balance <= 0 then 'Settled'
        when adv.first_repayment_month > (select run_month from run)
          then 'Repayments start ' || to_char(adv.first_repayment_month, 'FMMonth YYYY')
        when adv.later_repaid then 'Already repaid in a later payroll month'
      end as skip_reason
    from adv
  )
  select
    j.id,
    (row_number() over (order by j.reviewed_at, j.id))::integer,
    j.instalment,
    j.balance,
    case when j.skip_reason is null then least(j.instalment, j.balance) else 0 end,
    j.skip_reason
  from judged j
  where exists (select 1 from run)
  order by j.reviewed_at, j.id;
$$;

-- The advance repayments on one payslip, with the balance remaining after
-- it: amount minus every repayment on a payslip of this run's month or
-- earlier (computed at display, never stored).
create function public.staff_advance_payslip_lines(p_payslip_id uuid)
returns table (
  advance_id uuid,
  advance_amount numeric,
  disbursed_on date,
  instalment_due numeric,
  amount numeric,
  balance_after numeric
)
language sql
stable
set search_path = public
as $$
  with this_run as (
    select make_date(pr.year, pr.month, 1) as run_month
    from public.payslips p join public.payroll_runs pr on pr.id = p.payroll_run_id
    where p.id = p_payslip_id
  )
  select
    a.id, a.amount, a.disbursed_on, r.instalment_due, r.amount,
    a.amount - (
      select coalesce(sum(r2.amount), 0)
      from public.staff_advance_repayments r2
      join public.payslips p2 on p2.id = r2.payslip_id
      join public.payroll_runs pr2 on pr2.id = p2.payroll_run_id
      where r2.advance_id = a.id
        and make_date(pr2.year, pr2.month, 1) <= (select run_month from this_run)
    )
  from public.staff_advance_repayments r
  join public.staff_advances a on a.id = r.advance_id
  where r.payslip_id = p_payslip_id
  order by a.reviewed_at, a.id;
$$;

-- ============================================================ 5. write functions

create function public.propose_staff_advance(
  p_employee_id uuid,
  p_amount numeric,
  p_instalment numeric,
  p_first_repayment_month date,
  p_disbursed_on date,
  p_method text,
  p_bank_account_id uuid default null,
  p_note text default null
)
returns public.staff_advances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_row public.staff_advances;
begin
  perform public.require_finance_writer();

  select employment_status into v_status from public.employees where id = p_employee_id;
  if v_status is null then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_status <> 'Active' then
    raise exception 'An advance can only be given to an active employee (status: %)', v_status;
  end if;
  if p_amount is null or p_instalment is null then
    raise exception 'The amount advanced and the monthly instalment are required';
  end if;
  if p_amount = 0 then
    raise exception 'The amount advanced must be more than 0';
  end if;
  if p_instalment = 0 then
    raise exception 'The monthly instalment must be more than 0';
  end if;
  if p_amount > 0 and p_instalment > p_amount then
    raise exception 'The monthly instalment cannot be more than the amount advanced';
  end if;
  if p_first_repayment_month is null or p_disbursed_on is null then
    raise exception 'The payout date and the first repayment month are required';
  end if;
  if p_disbursed_on > current_date then
    raise exception 'The payout date cannot be in the future';
  end if;
  if date_trunc('month', p_first_repayment_month) < date_trunc('month', p_disbursed_on) then
    raise exception 'Repayments cannot start before the month the advance is paid out';
  end if;
  if p_method is null or p_method not in ('Cash', 'Mobile Money', 'Bank Transfer') then
    raise exception 'Payout method must be Cash, Mobile Money or Bank Transfer';
  end if;
  if p_method = 'Bank Transfer' and p_bank_account_id is null then
    raise exception 'Choose the bank account the advance was paid from';
  end if;
  if p_method <> 'Bank Transfer' and p_bank_account_id is not null then
    raise exception 'A bank account is only used for a Bank Transfer payout';
  end if;
  -- Fails early if the payout account isn't mapped to the ledger.
  perform public.settlement_account(p_method, p_bank_account_id);

  insert into public.staff_advances (
    employee_id, amount, instalment, first_repayment_month, disbursed_on,
    disbursement_method, bank_account_id, note, status, proposed_by
  ) values (
    p_employee_id, p_amount, p_instalment, date_trunc('month', p_first_repayment_month)::date,
    p_disbursed_on, p_method, p_bank_account_id, nullif(trim(p_note), ''), 'Proposed', auth.uid()
  )
  returning * into v_row;

  return v_row;
end;
$$;

-- Approves a proposed advance and posts the payout in the same transaction:
-- Dr 1350 Advances to Staff / Cr the payout account (1350 not yet confirmed
-- by the accountant). Manager only, own proposals included. Posted on Main
-- (the oldest branch), where payroll and accounting live (DESIGN.md).
create function public.approve_staff_advance(p_advance_id uuid)
returns public.staff_advances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.staff_advances;
  v_emp public.employees;
  v_main uuid;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve a staff advance';
  end if;

  select * into v_row from public.staff_advances where id = p_advance_id for update;
  if not found then
    raise exception 'Staff advance % not found', p_advance_id;
  end if;
  if v_row.status <> 'Proposed' then
    raise exception 'This advance is not awaiting approval (status: %)', v_row.status;
  end if;
  select * into v_emp from public.employees where id = v_row.employee_id;
  if v_emp.employment_status <> 'Active' then
    raise exception 'The employee is no longer active (status: %)', v_emp.employment_status;
  end if;

  select id into v_main from public.branches order by created_at limit 1;

  perform public._post_journal_entry_rows(
    v_main,
    v_row.disbursed_on,
    'Staff advance — ' || v_emp.name,
    'ADV-' || left(v_row.id::text, 8),
    jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('1350'),
        'debit', v_row.amount, 'credit', 0,
        'description', 'Staff advance to ' || v_emp.name
      ),
      jsonb_build_object(
        'account_id', public.settlement_account(v_row.disbursement_method, v_row.bank_account_id),
        'debit', 0, 'credit', v_row.amount,
        'description', 'Staff advance paid out (' || v_row.disbursement_method || ')'
      )
    ),
    'staff_advances',
    v_row.id::text
  );

  update public.staff_advances
  set status = 'Active', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_advance_id
  returning * into v_row;

  return v_row;
end;
$$;

create function public.reject_staff_advance(p_advance_id uuid, p_reason text)
returns public.staff_advances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.staff_advances;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can reject a staff advance';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'A reason is required to reject';
  end if;

  select * into v_row from public.staff_advances where id = p_advance_id for update;
  if not found then
    raise exception 'Staff advance % not found', p_advance_id;
  end if;
  if v_row.status <> 'Proposed' then
    raise exception 'This advance is not awaiting approval (status: %)', v_row.status;
  end if;

  update public.staff_advances
  set status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = trim(p_reason)
  where id = p_advance_id
  returning * into v_row;

  return v_row;
end;
$$;

create function public.withdraw_staff_advance_proposal(p_advance_id uuid)
returns public.staff_advances
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.staff_advances;
begin
  perform public.require_finance_writer();

  select * into v_row from public.staff_advances where id = p_advance_id for update;
  if not found then
    raise exception 'Staff advance % not found', p_advance_id;
  end if;
  if v_row.status <> 'Proposed' then
    raise exception 'This advance is not awaiting approval (status: %)', v_row.status;
  end if;
  if v_row.proposed_by is distinct from auth.uid() and not public.has_role(array['Manager']) then
    raise exception 'You can only withdraw your own pending proposal';
  end if;

  update public.staff_advances
  set status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = 'Withdrawn by proposer'
  where id = p_advance_id
  returning * into v_row;

  return v_row;
end;
$$;

-- Checks that a change of this kind fits the advance's current state.
-- Shared by propose and approve (the state can change in between).
create function public._staff_advance_change_problem(
  p_advance public.staff_advances,
  p_kind text,
  p_new_instalment numeric
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_balance numeric;
begin
  if p_kind is null or p_kind not in ('Pause', 'Resume', 'Cancel', 'Instalment') then
    return 'Change must be Pause, Resume, Cancel or Instalment';
  end if;
  if p_advance.status not in ('Active', 'Paused') then
    return format('This advance can''t be changed (status: %s)', p_advance.status);
  end if;
  select p_advance.amount - coalesce(sum(amount), 0) into v_balance
  from public.staff_advance_repayments where advance_id = p_advance.id;
  if v_balance <= 0 then
    return 'This advance is fully repaid';
  end if;
  if p_kind = 'Pause' and p_advance.status <> 'Active' then
    return 'Only an active advance can be paused';
  end if;
  if p_kind = 'Resume' and p_advance.status <> 'Paused' then
    return 'Only a paused advance can be resumed';
  end if;
  if p_kind = 'Instalment' then
    if p_new_instalment is null then
      return 'Enter the new monthly instalment';
    end if;
    if p_new_instalment = 0 then
      return 'The monthly instalment must be more than 0';
    end if;
    if p_new_instalment > p_advance.amount then
      return 'The monthly instalment cannot be more than the amount advanced';
    end if;
    if p_new_instalment = p_advance.instalment then
      return 'That is already the monthly instalment';
    end if;
  elsif p_new_instalment is not null then
    return 'A new instalment is only used for an instalment change';
  end if;
  return null;
end;
$$;

create function public.propose_staff_advance_change(
  p_advance_id uuid,
  p_kind text,
  p_new_instalment numeric default null,
  p_reason text default null
)
returns public.staff_advance_change_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adv public.staff_advances;
  v_problem text;
  v_row public.staff_advance_change_requests;
begin
  perform public.require_finance_writer();

  select * into v_adv from public.staff_advances where id = p_advance_id for update;
  if not found then
    raise exception 'Staff advance % not found', p_advance_id;
  end if;
  if exists (
    select 1 from public.staff_advance_change_requests
    where advance_id = p_advance_id and status = 'Pending Approval'
  ) then
    raise exception 'There is already a pending change for this advance — approve, reject or withdraw it first';
  end if;
  v_problem := public._staff_advance_change_problem(v_adv, p_kind, p_new_instalment);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;

  insert into public.staff_advance_change_requests (advance_id, kind, new_instalment, reason, proposed_by)
  values (p_advance_id, p_kind, p_new_instalment, nullif(trim(p_reason), ''), auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;

-- Applies an approved change to payslips generated from now on. Draft and
-- posted payslips already generated are never recalculated.
create function public.approve_staff_advance_change(p_request_id uuid)
returns public.staff_advance_change_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.staff_advance_change_requests;
  v_adv public.staff_advances;
  v_problem text;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve a change to a staff advance';
  end if;

  select * into v_req from public.staff_advance_change_requests where id = p_request_id for update;
  if not found then
    raise exception 'Change request % not found', p_request_id;
  end if;
  if v_req.status <> 'Pending Approval' then
    raise exception 'This change is not awaiting approval (status: %)', v_req.status;
  end if;
  select * into v_adv from public.staff_advances where id = v_req.advance_id for update;
  v_problem := public._staff_advance_change_problem(v_adv, v_req.kind, v_req.new_instalment);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;

  update public.staff_advances
  set status = case v_req.kind
        when 'Pause' then 'Paused'
        when 'Resume' then 'Active'
        when 'Cancel' then 'Cancelled'
        else status
      end,
      instalment = case when v_req.kind = 'Instalment' then v_req.new_instalment else instalment end
  where id = v_req.advance_id;

  update public.staff_advance_change_requests
  set status = 'Approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_request_id
  returning * into v_req;

  return v_req;
end;
$$;

create function public.reject_staff_advance_change(p_request_id uuid, p_reason text)
returns public.staff_advance_change_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.staff_advance_change_requests;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can reject a change to a staff advance';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'A reason is required to reject';
  end if;

  select * into v_req from public.staff_advance_change_requests where id = p_request_id for update;
  if not found then
    raise exception 'Change request % not found', p_request_id;
  end if;
  if v_req.status <> 'Pending Approval' then
    raise exception 'This change is not awaiting approval (status: %)', v_req.status;
  end if;

  update public.staff_advance_change_requests
  set status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = trim(p_reason)
  where id = p_request_id
  returning * into v_req;

  return v_req;
end;
$$;

create function public.withdraw_staff_advance_change(p_request_id uuid)
returns public.staff_advance_change_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.staff_advance_change_requests;
begin
  perform public.require_finance_writer();

  select * into v_req from public.staff_advance_change_requests where id = p_request_id for update;
  if not found then
    raise exception 'Change request % not found', p_request_id;
  end if;
  if v_req.status <> 'Pending Approval' then
    raise exception 'This change is not awaiting approval (status: %)', v_req.status;
  end if;
  if v_req.proposed_by is distinct from auth.uid() and not public.has_role(array['Manager']) then
    raise exception 'You can only withdraw your own pending proposal';
  end if;

  update public.staff_advance_change_requests
  set status = 'Rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      rejection_reason = 'Withdrawn by proposer'
  where id = p_request_id
  returning * into v_req;

  return v_req;
end;
$$;

-- ============================================================ 6. function grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. Trigger functions and the
-- internal helper get no grant at all.
revoke execute on function public.staff_advances_freeze() from public, anon, authenticated;
revoke execute on function public.audit_staff_advances() from public, anon, authenticated;
revoke execute on function public.audit_staff_advance_change_requests() from public, anon, authenticated;
revoke execute on function public._staff_advance_change_problem(public.staff_advances, text, numeric) from public, anon, authenticated;

revoke execute on function public.staff_advance_summary(uuid) from public, anon;
revoke execute on function public.staff_advance_deduction_preview(uuid, uuid) from public, anon;
revoke execute on function public.staff_advance_payslip_lines(uuid) from public, anon;
revoke execute on function public.propose_staff_advance(uuid, numeric, numeric, date, date, text, uuid, text) from public, anon;
revoke execute on function public.approve_staff_advance(uuid) from public, anon;
revoke execute on function public.reject_staff_advance(uuid, text) from public, anon;
revoke execute on function public.withdraw_staff_advance_proposal(uuid) from public, anon;
revoke execute on function public.propose_staff_advance_change(uuid, text, numeric, text) from public, anon;
revoke execute on function public.approve_staff_advance_change(uuid) from public, anon;
revoke execute on function public.reject_staff_advance_change(uuid, text) from public, anon;
revoke execute on function public.withdraw_staff_advance_change(uuid) from public, anon;

grant execute on function public.staff_advance_summary(uuid) to authenticated, service_role;
grant execute on function public.staff_advance_deduction_preview(uuid, uuid) to authenticated, service_role;
grant execute on function public.staff_advance_payslip_lines(uuid) to authenticated, service_role;
grant execute on function public.propose_staff_advance(uuid, numeric, numeric, date, date, text, uuid, text) to authenticated, service_role;
grant execute on function public.approve_staff_advance(uuid) to authenticated, service_role;
grant execute on function public.reject_staff_advance(uuid, text) to authenticated, service_role;
grant execute on function public.withdraw_staff_advance_proposal(uuid) to authenticated, service_role;
grant execute on function public.propose_staff_advance_change(uuid, text, numeric, text) to authenticated, service_role;
grant execute on function public.approve_staff_advance_change(uuid) to authenticated, service_role;
grant execute on function public.reject_staff_advance_change(uuid, text) to authenticated, service_role;
grant execute on function public.withdraw_staff_advance_change(uuid) to authenticated, service_role;
