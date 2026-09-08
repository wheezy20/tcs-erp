-- Extend void to expenses (follow-up to void_sale_and_invoice.sql).
--
-- Same shape, same reasoning: a void is an erasure of a mistaken record, not
-- a new transaction, and expenses is even simpler than sales/invoices — it
-- never touches stock and nothing in the schema references an expense row
-- by FK (checked directly: no returns-like concept, no deposit-fulfilment
-- analogue), so there is no fifth integrity guard to add here. The only
-- structural difference from create_sale()/create_invoice() is that
-- create_expense() is already Manager-only (Attendant has zero access to
-- Expenses at all per the role-permissions-rewrite migration, and
-- Accountant/Auditor is read-only everywhere) — void_expense() keeps that
-- same bar rather than loosening it.
--
-- Structural enforcement, identical mechanism to sales/invoices: the void
-- columns are writable only from inside void_expense() (SECURITY DEFINER),
-- and reject_direct_void_write() — already defined, reused verbatim, not
-- redefined — rejects any direct write to them from an app role via a
-- BEFORE UPDATE trigger, regardless of what RLS would otherwise allow.
-- Unlike sales, nothing else in this codebase ever legitimately UPDATEs an
-- expenses row (create_expense() is the sole, insert-only entry point —
-- "an expense ledger is append-only in this app", per its own schema
-- comment), so — unlike sales, where the UPDATE grant had to stay for
-- create_sale_return()'s row lock — the UPDATE grant on expenses is
-- revoked from the app roles outright, the stronger of the two options
-- sales couldn't take.
--
-- Same two hard blocks as sales/invoices, for consistency: closed day
-- (expenses.date, the expense's own business date) and older than 7 days.
-- Same audit logging via an AFTER UPDATE trigger (new 'expense_voided'
-- action) — never a client insert. Same ledger reversal via the existing
-- reverse_journal_entry(), one call for the expense's one journal entry
-- (post_expense_journal_entry() posts exactly one, keyed
-- ('expenses', id)) — no new posting logic.

-- ============================================================ schema

alter table public.expenses
  add column voided_at timestamptz,
  add column voided_by uuid references public.staff (id) on delete restrict,
  add column void_reason text,
  add constraint expenses_void_shape check (
    (voided_at is null) = (voided_by is null)
    and (voided_at is null) = (void_reason is null)
  );

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log
  add constraint audit_log_action_check
  check (action in (
    'discount_applied', 'vat_override', 'return_processed',
    'sale_voided', 'invoice_voided', 'expense_voided'
  ));

-- ============================================================ guard trigger

-- Reuses reject_direct_void_write() as-is (already defined in
-- void_sale_and_invoice.sql, parameterized by label) — same one-way,
-- only-through-the-RPC enforcement as sales/invoices, no new trigger
-- function needed.
create trigger expenses_reject_direct_void_write
before update on public.expenses
for each row execute function public.reject_direct_void_write('expense');

-- ============================================================ audit trigger

create or replace function public.audit_expense_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.voided_at is null and new.voided_at is not null then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      new.branch_id,
      coalesce(auth.uid(), new.voided_by),
      'expense_voided',
      'expenses',
      new.id,
      jsonb_build_object('amount', old.amount, 'category', old.category, 'voided', false),
      jsonb_build_object('voided_at', new.voided_at, 'reason', new.void_reason)
    );
  end if;
  return new;
end;
$$;

create trigger expenses_audit_void
after update of voided_at on public.expenses
for each row execute function public.audit_expense_void();

-- ============================================================ void_expense()

create or replace function public.void_expense(p_expense_id text, p_reason text)
returns public.expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense public.expenses;
  v_reason text := trim(coalesce(p_reason, ''));
  v_entry record;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can void an expense';
  end if;
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
$$;

grant execute on function public.void_expense(text, text) to authenticated;
grant execute on function public.void_expense(text, text) to service_role;

-- ============================================================ day totals

-- Recreated verbatim from void_sale_and_invoice.sql with cash_expenses
-- excluding voided rows too — a same-day void of a Cash expense nets
-- correctly against the drawer (money never actually left, so it must not
-- reduce expected_cash); a closed day cannot be affected at all, because
-- voiding a closed-day expense is blocked outright above.
create or replace function public.compute_day_totals(p_branch_id uuid, p_business_date date)
returns table (
  cash_sales numeric,
  mobile_money_sales numeric,
  card_sales numeric,
  bank_transfer_sales numeric,
  vat_collected numeric,
  discounts_given numeric,
  cash_refunds numeric,
  cash_expenses numeric,
  cash_deposits numeric,
  system_sales_total numeric,
  system_transaction_count integer,
  pos_cash_sales numeric,
  invoice_cash_sales numeric,
  invoice_cheque_sales numeric
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_sale record;
  v_line record;
  v_gross numeric;
  v_discount numeric;
  v_net numeric;
  v_subtotal numeric;
  v_taxable numeric;
  v_sale_discount numeric;
  v_net_total numeric;
  v_ratio numeric;
  v_vat numeric;
  v_vat_collected numeric := 0;
  v_discounts_given numeric := 0;
  v_system_sales_total numeric := 0;
  v_system_transaction_count integer := 0;
  v_pos_cash_sales numeric := 0;
  v_pos_cash_change numeric := 0;
  v_mobile_money_sales numeric := 0;
  v_card_sales numeric := 0;
  v_bank_transfer_sales numeric := 0;
  v_cash_refunds numeric := 0;
  v_cash_expenses numeric := 0;
  v_cash_deposits numeric := 0;
  v_invoice_cash_sales numeric := 0;
  v_invoice_mobile_money numeric := 0;
  v_invoice_bank_transfer numeric := 0;
  v_invoice_cheque_sales numeric := 0;
  v_cash_sales numeric := 0;
begin
  perform public.require_staff();

  for v_sale in
    select id, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total
    from public.sales
    where branch_id = p_branch_id and sold_at::date = p_business_date and voided_at is null
  loop
    v_system_transaction_count := v_system_transaction_count + 1;
    v_system_sales_total := v_system_sales_total + v_sale.total;

    v_subtotal := 0;
    v_taxable := 0;
    for v_line in
      select quantity, unit_price, discount_mode, discount_value, vat
      from public.sale_lines
      where sale_id = v_sale.id
    loop
      v_gross := v_line.quantity * v_line.unit_price;
      v_discount := case
        when v_line.discount_mode = 'percent' then v_gross * v_line.discount_value / 100
        when v_line.discount_mode = 'amount_per_unit' then v_line.discount_value * v_line.quantity
        else v_line.discount_value end;
      v_discounts_given := v_discounts_given + least(greatest(v_discount, 0), v_gross);
      v_net := greatest(v_gross - greatest(v_discount, 0), 0);
      v_subtotal := v_subtotal + v_net;
      if v_sale.vat_mode = 'all' or (v_sale.vat_mode = 'per-item' and v_line.vat) then
        v_taxable := v_taxable + v_net;
      end if;
    end loop;

    v_sale_discount := case when v_sale.sale_discount_mode = 'percent'
      then v_subtotal * v_sale.sale_discount_value / 100
      else v_sale.sale_discount_value end;
    v_sale_discount := least(greatest(v_sale_discount, 0), v_subtotal);
    v_discounts_given := v_discounts_given + v_sale_discount;

    v_net_total := v_subtotal - v_sale_discount;
    v_ratio := case when v_subtotal > 0 then v_net_total / v_subtotal else 0 end;
    v_vat := round(v_taxable * v_ratio * (v_sale.vat_rate / 100), 2);
    v_vat_collected := v_vat_collected + v_vat;
  end loop;

  select
    coalesce(sum(amount) filter (where method = 'Cash'), 0),
    coalesce(sum(amount) filter (where method = 'Mobile Money'), 0),
    coalesce(sum(amount) filter (where method = 'Card'), 0),
    coalesce(sum(amount) filter (where method = 'Bank Transfer'), 0)
  into v_pos_cash_sales, v_mobile_money_sales, v_card_sales, v_bank_transfer_sales
  from public.sale_payments
  where branch_id = p_branch_id and paid_at::date = p_business_date
    and sale_id not in (select id from public.sales where voided_at is not null);

  select coalesce(sum(greatest(per_sale.paid - s.total, 0)), 0)
  into v_pos_cash_change
  from public.sales s
  join (
    select sale_id, sum(amount) as paid
    from public.sale_payments
    group by sale_id
  ) per_sale on per_sale.sale_id = s.id
  where s.branch_id = p_branch_id and s.sold_at::date = p_business_date and s.voided_at is null;

  v_pos_cash_sales := v_pos_cash_sales - v_pos_cash_change;

  select
    coalesce(sum(amount) filter (where method = 'Cash'), 0),
    coalesce(sum(amount) filter (where method = 'Mobile Money'), 0),
    coalesce(sum(amount) filter (where method = 'Bank Transfer'), 0),
    coalesce(sum(amount) filter (where method = 'Cheque'), 0)
  into v_invoice_cash_sales, v_invoice_mobile_money, v_invoice_bank_transfer, v_invoice_cheque_sales
  from public.invoice_payments
  where branch_id = p_branch_id and paid_at::date = p_business_date
    and invoice_id not in (select id from public.invoices where voided_at is not null);

  v_mobile_money_sales := v_mobile_money_sales + v_invoice_mobile_money;
  v_bank_transfer_sales := v_bank_transfer_sales + v_invoice_bank_transfer;
  v_cash_sales := v_pos_cash_sales + v_invoice_cash_sales;

  select coalesce(sum(greatest(-difference, 0)), 0)
  into v_cash_refunds
  from public.sale_returns
  where branch_id = p_branch_id and returned_at::date = p_business_date and resolution = 'Cash refund'
    and sale_id not in (select id from public.sales where voided_at is not null);

  select coalesce(sum(amount), 0)
  into v_cash_expenses
  from public.expenses
  where branch_id = p_branch_id and date = p_business_date and method = 'Cash' and voided_at is null;

  select coalesce(sum(amount), 0)
  into v_cash_deposits
  from public.bank_deposits
  where branch_id = p_branch_id and date = p_business_date and source = 'Cash';

  return query select
    v_cash_sales, v_mobile_money_sales, v_card_sales, v_bank_transfer_sales,
    v_vat_collected, v_discounts_given, v_cash_refunds, v_cash_expenses, v_cash_deposits,
    v_system_sales_total, v_system_transaction_count,
    v_pos_cash_sales, v_invoice_cash_sales, v_invoice_cheque_sales;
end;
$$;

grant execute on function public.compute_day_totals(uuid, date) to authenticated;
grant execute on function public.compute_day_totals(uuid, date) to service_role;

-- ============================================================ expenses immutability
--
-- Unlike sales (whose UPDATE grant had to stay for create_sale_return()'s
-- row lock), nothing anywhere in this codebase ever legitimately UPDATEs an
-- expenses row — create_expense() is a plain insert-only entry point with
-- no update_expense() counterpart at all (an append-only ledger, per its
-- own schema comment) and no other function takes a lock on it either. So
-- the UPDATE grant is revoked outright from the app roles: a direct PATCH
-- fails at the grant layer before RLS or the trigger are even reached,
-- with reject_direct_void_write still the enforcement of record for
-- void_expense()'s own SECURITY DEFINER path (which bypasses grants
-- entirely as the function owner) and for service_role (kept in the
-- trigger's denylist, matching sales/invoices).
revoke update on public.expenses from anon;
revoke update on public.expenses from authenticated;
