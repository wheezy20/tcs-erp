-- Banks reference list + an approval guard (TCS ERP, follow-up to
-- 20260909130000).
--
-- 1. `banks` — a school-editable reference list that drives the bank
--    dropdown when proposing an employee or a bank/account change. Same
--    "configurable list beats hardcoded columns" pattern as
--    `allowance_types` / `expense_categories` (docs/DESIGN.md). Not
--    branch-scoped: the licensed-bank list is entity-wide, like the chart
--    of accounts. `employee_pay_config.bank` stays plain `text` (the bank
--    *name*), same as an expense storing its category name — the reference
--    table only constrains the picker, there is no FK and no data
--    migration for existing values.
--
--    Entity-wide reference data with no branch/staff FK goes in the
--    migration (idempotent), not seed.sql, so it exists on every
--    deployment — same lesson as the chart of accounts / statutory rates.
--
-- 2. `approve_pay_config()` gains a guard: a pay config whose employee is
--    not yet 'Active' is a *bundled* proposal from `propose_employee()`
--    and must be approved via the employee record, not on its own. The UI
--    already routes it that way; this makes the RPC refuse the nonsensical
--    path too.

create table public.banks (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  position integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index banks_position_idx on public.banks (position);

alter table public.banks enable row level security;

-- Same shape as allowance_types post-20260909090000: select for the three
-- back-office roles, write for Manager + Accountant. Not approval-gated.
create policy banks_select on public.banks
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy banks_insert on public.banks
for insert with check (public.has_role(array['Manager', 'Accountant']));
create policy banks_update on public.banks
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));
create policy banks_delete on public.banks
for delete using (public.has_role(array['Manager', 'Accountant']));

revoke all on public.banks from anon;
grant select, insert, update, delete on public.banks to authenticated;
grant select, insert, update, delete on public.banks to service_role;

-- Universal / commercial banks licensed by the Bank of Ghana, plus
-- ARB Apex Bank (the rural-bank apex). The school edits this list itself;
-- these are just the starting set. Verify against the current Bank of
-- Ghana register before real use — a few names change with mergers.
insert into public.banks (name, position) values
  ('GCB Bank', 0),
  ('Ecobank Ghana', 1),
  ('Absa Bank Ghana', 2),
  ('Standard Chartered Bank Ghana', 3),
  ('Stanbic Bank Ghana', 4),
  ('Fidelity Bank Ghana', 5),
  ('CalBank', 6),
  ('Zenith Bank Ghana', 7),
  ('Access Bank Ghana', 8),
  ('Republic Bank Ghana', 9),
  ('Societe Generale Ghana', 10),
  ('Consolidated Bank Ghana', 11),
  ('National Investment Bank', 12),
  ('Agricultural Development Bank', 13),
  ('Prudential Bank', 14),
  ('First National Bank Ghana', 15),
  ('United Bank for Africa Ghana', 16),
  ('Bank of Africa Ghana', 17),
  ('Guaranty Trust Bank Ghana', 18),
  ('FBNBank Ghana', 19),
  ('OmniBSIC Bank Ghana', 20),
  ('First Atlantic Bank', 21),
  ('ARB Apex Bank', 22)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- approve_pay_config(): refuse a bundled proposal (employee not Active).
-- Only change vs the 20260909130000 version: the employment_status check.
-- ---------------------------------------------------------------------
create or replace function public.approve_pay_config(p_config_id uuid)
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
