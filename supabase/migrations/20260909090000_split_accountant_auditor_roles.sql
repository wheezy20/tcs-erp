-- Split the combined 'Accountant/Auditor' staff role into two: 'Accountant'
-- (writes Payroll / Accounting / Expenses, same level Manager has there) and
-- 'Auditor' (read-only everywhere the combined role could read). Manager and
-- Attendant are unchanged.
--
-- A separate migration (not an edit to 20260803120000) because this is a real
-- behavioural change to the permission model, not a rebrand.
--
-- Mechanism:
--   * staff.role check constraint gains the two new values, drops the old
--     combined one; any existing 'Accountant/Auditor' row -> 'Accountant'.
--   * can_write()  -> excludes BOTH Accountant and Auditor (unchanged
--     meaning: "Manager + Attendant", the ordinary-table write predicate).
--   * require_writable_role() -> rejects only Auditor now. Accountant passes
--     it; ordinary RPCs still keep Accountant out via can_write()-gated RLS
--     on their target tables (documented tradeoff: a direct RPC call by an
--     Accountant to e.g. create_invoice() fails on RLS deep inside rather
--     than with an early friendly message — the security boundary holds).
--   * require_finance_writer() -> NEW. Manager or Accountant. The finance
--     RPCs (create_expense / void_expense / create_account /
--     post_journal_entry / reverse_journal_entry / create_payroll_run /
--     create_payslip / delete_payslip) swap their
--     `require_writable_role() + has_role(['Manager'])` guard for a single
--     `require_finance_writer()`.
--   * Every RLS policy that referenced 'Accountant/Auditor':
--       - finance-write tables: writes -> has_role(['Manager','Accountant']);
--         selects -> has_role(['Manager','Accountant','Auditor']).
--       - read-only-for-both tables (audit_log, bank_*, purchase_*,
--         suppliers, supplier_payments): selects -> +Auditor; writes
--         untouched (still Manager-only — Banking/Purchasing are not
--         Accountant's modules).
--   * handle_new_staff_signup() accepts the two new role names.
--
-- No grant changes: every affected table already grants the relevant CRUD to
-- `authenticated`; RLS is what differentiates the roles.

-- ============================================================ 1. role values

alter table public.staff drop constraint staff_role_check;

-- Migrate any existing combined-role rows. None on a fresh DB (seed.sql now
-- seeds 'Accountant' directly); on a real deployment this catches them. A
-- protected row can only ever be a Manager (the bootstrap script never
-- creates a protected Accountant/Auditor), so protect_staff_row() won't
-- block this.
update public.staff set role = 'Accountant' where role = 'Accountant/Auditor';

alter table public.staff add constraint staff_role_check
  check (role in ('Attendant', 'Manager', 'Accountant', 'Auditor'));

-- ============================================================ 2. predicates

create or replace function public.can_write()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_staff()
    and not public.has_role(array['Accountant', 'Auditor']);
$$;

create or replace function public.require_writable_role()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_staff();
  if public.has_role(array['Auditor']) then
    raise exception 'Auditor is read-only and cannot perform this action';
  end if;
end;
$$;

create or replace function public.require_finance_writer()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_staff();
  if not public.has_role(array['Manager', 'Accountant']) then
    raise exception 'This action is limited to Manager and Accountant roles';
  end if;
end;
$$;

grant execute on function public.require_finance_writer() to authenticated;
grant execute on function public.require_finance_writer() to service_role;

-- ============================================================ 3. RLS: finance-write tables

do $$
declare
  t text;
  fw text[] := array[
    'expenses', 'expense_categories', 'expense_category_accounts',
    'accounts', 'journal_entries', 'journal_lines', 'journal_entry_number_counters',
    'allowance_types', 'staff_pay_config', 'staff_allowances', 'statutory_rates', 'paye_bands',
    'payroll_runs', 'payslips', 'payslip_allowances'
  ];
begin
  foreach t in array fw loop
    execute format(
      'alter policy %I_select on public.%I using (public.has_role(array[''Manager'',''Accountant'',''Auditor'']))',
      t, t);
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_insert') then
      execute format(
        'alter policy %I_insert on public.%I with check (public.has_role(array[''Manager'',''Accountant'']))',
        t, t);
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_update') then
      execute format(
        'alter policy %I_update on public.%I using (public.has_role(array[''Manager'',''Accountant''])) with check (public.has_role(array[''Manager'',''Accountant'']))',
        t, t);
    end if;
    if t <> 'payroll_runs'
       and exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_delete') then
      execute format(
        'alter policy %I_delete on public.%I using (public.has_role(array[''Manager'',''Accountant'']))',
        t, t);
    end if;
  end loop;
end $$;

alter policy payroll_runs_delete on public.payroll_runs
  using (public.has_role(array['Manager', 'Accountant']) and status = 'Draft');

-- ============================================================ 4. RLS: read-only-for-both tables

do $$
declare
  t text;
  ro text[] := array[
    'audit_log',
    'bank_accounts', 'bank_deposits', 'bank_reconciliations', 'bank_statement_lines',
    'purchase_orders', 'purchase_order_lines', 'purchase_order_receipts',
    'purchase_order_receipt_lines', 'purchase_order_number_counters',
    'suppliers', 'supplier_payments'
  ];
begin
  foreach t in array ro loop
    execute format(
      'alter policy %I_select on public.%I using (public.has_role(array[''Manager'',''Accountant'',''Auditor'']))',
      t, t);
  end loop;
end $$;

-- ============================================================ 5. finance RPCs: guard swap
-- Each function below is its current definition verbatim, with only the
-- `require_writable_role() + has_role(['Manager'])` guard replaced by a
-- single `require_finance_writer()` call.

-- ---- create_expense ----
CREATE OR REPLACE FUNCTION public.create_expense(p_branch_id uuid, p_date date, p_category text, p_description text, p_amount numeric, p_method text, p_reference text, p_receipt_path text DEFAULT NULL::text, p_bank_account_id uuid DEFAULT NULL::uuid)
 RETURNS expenses
 LANGUAGE plpgsql
AS $function$
declare
  v_id text;
  v_bank_account_id uuid;
  v_expense public.expenses;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  if p_method = 'Bank' then
    if p_bank_account_id is null then
      raise exception 'Select the bank account this expense was paid from';
    end if;
    if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
    v_bank_account_id := p_bank_account_id;
  else
    v_bank_account_id := null;
  end if;

  v_id := 'EXP-' || nextval('public.expense_number_seq')::text;

  insert into public.expenses
    (id, branch_id, date, category, description, amount, method, reference, receipt_path, bank_account_id)
  values
    (v_id, p_branch_id, p_date, p_category, p_description, p_amount, p_method, nullif(p_reference, ''), p_receipt_path, v_bank_account_id)
  returning * into v_expense;

  perform public.post_expense_journal_entry(v_id);
  return v_expense;
end;
$function$

;

-- ---- void_expense ----
CREATE OR REPLACE FUNCTION public.void_expense(p_expense_id text, p_reason text)
 RETURNS expenses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_expense public.expenses;
  v_reason text := trim(coalesce(p_reason, ''));
  v_entry record;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();
  if v_reason = '' then
    raise exception 'A void needs a reason';
  end if;

  select * into v_expense from public.expenses where id = p_expense_id for update;
  if not found then
    raise exception 'Expense % does not exist', p_expense_id;
  end if;
  if v_expense.voided_at is not null then
    raise exception 'Expense % has already been voided', p_expense_id;
  end if;

  if exists (
    select 1 from public.day_closes
    where branch_id = v_expense.branch_id and business_date = v_expense.date and closed_at is not null
  ) then
    raise exception 'The day % has been closed and reconciled — an expense from a closed day cannot be voided', v_expense.date;
  end if;

  if current_date - v_expense.date > 7 then
    raise exception 'An expense can only be voided within 7 days of the transaction (% is % days old)',
      p_expense_id, current_date - v_expense.date;
  end if;

  -- Reverse the ledger — post_expense_journal_entry() posts exactly one
  -- entry per expense, keyed ('expenses', id), so this is always at most
  -- one reverse_journal_entry() call.
  for v_entry in
    select id from public.journal_entries where source_table = 'expenses' and source_id = p_expense_id
  loop
    perform public.reverse_journal_entry(
      v_entry.id, current_date, 'Void of expense ' || p_expense_id || ' — ' || v_reason
    );
  end loop;

  update public.expenses
  set voided_at = now(), voided_by = auth.uid(), void_reason = v_reason
  where id = p_expense_id
  returning * into v_expense;

  return v_expense;
end;
$function$

;

-- ---- create_account ----
CREATE OR REPLACE FUNCTION public.create_account(p_code text, p_name text, p_category text, p_subtype text, p_description text DEFAULT ''::text)
 RETURNS accounts
 LANGUAGE plpgsql
AS $function$
declare
  v_row public.accounts;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  if p_category not in ('Assets', 'Liabilities', 'Equity', 'Revenue', 'Expenses') then
    raise exception 'Invalid account category: %', p_category;
  end if;

  if trim(coalesce(p_code, '')) = '' or trim(coalesce(p_name, '')) = '' then
    raise exception 'Account code and name are required';
  end if;

  begin
    insert into public.accounts (code, name, category, subtype, description)
    values (trim(p_code), trim(p_name), p_category, trim(coalesce(p_subtype, '')), coalesce(trim(p_description), ''))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Account code % is already in use', p_code;
  end;

  return v_row;
end;
$function$

;

-- ---- post_journal_entry ----
CREATE OR REPLACE FUNCTION public.post_journal_entry(p_date date, p_description text, p_reference text, p_lines jsonb, p_reverses_entry_id text DEFAULT NULL::text)
 RETURNS journal_entries
 LANGUAGE plpgsql
AS $function$
declare
  v_branch_id uuid;
  v_year_month text := to_char(p_date, 'YYMM');
  v_seq integer;
  v_id text;
  v_row public.journal_entries;
  v_line_count integer;
  v_total_debit numeric;
  v_total_credit numeric;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  if trim(coalesce(p_description, '')) = '' then
    raise exception 'A journal entry needs a description';
  end if;

  select count(*) into v_line_count from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb));
  if v_line_count < 2 then
    raise exception 'A journal entry needs at least two lines';
  end if;

  select coalesce(sum((line ->> 'debit')::numeric), 0), coalesce(sum((line ->> 'credit')::numeric), 0)
  into v_total_debit, v_total_credit
  from jsonb_array_elements(p_lines) as line;

  -- Pre-validated here for a clean, specific error before anything is
  -- written; the deferred constraint trigger on journal_lines re-validates
  -- the same fact at commit time regardless, as the real backstop.
  if v_total_debit <> v_total_credit then
    raise exception 'Entry is not balanced: debits % do not equal credits %', v_total_debit, v_total_credit;
  end if;
  if v_total_debit = 0 then
    raise exception 'Entry has no amount';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_lines) as line
    where not exists (
      select 1 from public.accounts a where a.id = (line ->> 'account_id')::uuid
    )
  ) then
    raise exception 'One of the selected accounts no longer exists';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_lines) as line
    join public.accounts a on a.id = (line ->> 'account_id')::uuid
    where not a.is_active
  ) then
    raise exception 'One of the selected accounts is inactive and cannot be posted to';
  end if;

  select id into v_branch_id from public.branches order by created_at limit 1;

  insert into public.journal_entry_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = journal_entry_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'JE-' || v_year_month || lpad(v_seq::text, 4, '0');

  insert into public.journal_entries (id, branch_id, entry_date, description, reference, reverses_entry_id)
  values (
    v_id,
    v_branch_id,
    p_date,
    trim(p_description),
    nullif(trim(coalesce(p_reference, '')), ''),
    p_reverses_entry_id
  )
  returning * into v_row;

  insert into public.journal_lines (entry_id, position, account_id, debit, credit, description)
  select
    v_id,
    ord - 1,
    (line ->> 'account_id')::uuid,
    coalesce((line ->> 'debit')::numeric, 0),
    coalesce((line ->> 'credit')::numeric, 0),
    coalesce(line ->> 'description', '')
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_row;
end;
$function$

;

-- ---- reverse_journal_entry ----
CREATE OR REPLACE FUNCTION public.reverse_journal_entry(p_entry_id text, p_date date DEFAULT CURRENT_DATE, p_description text DEFAULT NULL::text)
 RETURNS journal_entries
 LANGUAGE plpgsql
AS $function$
declare
  v_original public.journal_entries;
  v_lines jsonb;
  v_desc text;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  select * into v_original from public.journal_entries where id = p_entry_id;
  if not found then
    raise exception 'Journal entry % does not exist', p_entry_id;
  end if;

  if exists (select 1 from public.journal_entries where reverses_entry_id = p_entry_id) then
    raise exception 'Journal entry % has already been reversed', p_entry_id;
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'account_id', account_id,
      'debit', credit,
      'credit', debit,
      'description', description
    )
    order by position
  )
  into v_lines
  from public.journal_lines
  where entry_id = p_entry_id;

  v_desc := coalesce(nullif(trim(p_description), ''), 'Reversal of ' || p_entry_id || ' — ' || v_original.description);

  return public.post_journal_entry(p_date, v_desc, v_original.reference, v_lines, p_entry_id);
end;
$function$

;

-- ---- create_payroll_run ----
CREATE OR REPLACE FUNCTION public.create_payroll_run(p_branch_id uuid, p_month integer, p_year integer)
 RETURNS payroll_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.payroll_runs;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

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
$function$

;

-- ---- create_payslip ----
CREATE OR REPLACE FUNCTION public.create_payslip(p_payroll_run_id uuid, p_staff_id uuid, p_overtime_hours numeric DEFAULT 0, p_overtime_rate numeric DEFAULT 0, p_allowances jsonb DEFAULT '[]'::jsonb, p_fines numeric DEFAULT 0, p_iou numeric DEFAULT 0)
 RETURNS payslips
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

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
$function$

;

-- ---- delete_payslip ----
CREATE OR REPLACE FUNCTION public.delete_payslip(p_payslip_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_status text;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

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
$function$

;

-- ============================================================ 6. signup trigger

CREATE OR REPLACE FUNCTION public.handle_new_staff_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_branch_id uuid;
  v_role text := coalesce(new.raw_user_meta_data ->> 'role', 'Attendant');
begin
  if v_role not in ('Attendant', 'Manager', 'Accountant', 'Auditor') then
    v_role := 'Attendant';
  end if;

  select id into v_branch_id from public.branches order by created_at limit 1;

  insert into public.staff (id, branch_id, name, email, role)
  values (
    new.id,
    v_branch_id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)),
    new.email,
    v_role
  );

  return new;
end;
$function$

;
