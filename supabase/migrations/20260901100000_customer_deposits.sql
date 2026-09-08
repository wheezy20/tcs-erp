-- ============================================================================
-- Customer deposits — reserve an out-of-stock item by paying some/all of its
-- price up front, balance collected at hand-over.
--
-- Distinct from a pro-forma quote (non-binding, no money, no ledger) and from
-- an invoice (money owed for goods already delivered): a deposit is real
-- money in and a real liability out, the moment it is taken. Strictly
-- two-step — deposit now, balance at hand-over — no partial-installment
-- tracking in this version.
--
-- Ledger shape:
--   Take:    Dr <cash/bank/MoMo settlement account>  Cr 2450 Customer Deposits
--   Fulfil:  the deposit rides into create_sale()/record_invoice_payment() as
--            a 'Deposit' payment leg → Dr 2450 (clearing the liability) on the
--            settlement side of that document's own posting. VAT/WHT are the
--            document's own concern; the deposit itself never touches tax.
--   Cancel:  Dr 2450 (full amount)  Cr <settlement> (refund)  Cr 4900 (fee),
--            Manager-only, fee is an explicit choice at cancellation time.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. 2450 Customer Deposits ledger account
-- ---------------------------------------------------------------------------
-- accounts.created_by is nullable since 20260819090000 (seed-gap), so a
-- migration-time insert is fine — set_account_created_by only forces
-- created_by when there is an authenticated caller, which there isn't here.
-- This runs before seed.sql, which (post seed-gap) no longer inserts the
-- base chart itself, so nothing else needs to add this row. `on conflict
-- (code) do nothing` keeps it idempotent against production too.
insert into public.accounts (code, name, category, subtype, description)
values (
  '2450', 'Customer Deposits', 'Liabilities', 'Current Liability',
  'Money taken from customers up front to reserve goods, owed back to them until the sale is fulfilled or the deposit is cancelled.'
)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. customer_deposits + its number counter
-- ---------------------------------------------------------------------------
create table public.deposit_number_counters (
  year_month text primary key,
  last_number integer not null default 0
);

create table public.customer_deposits (
  -- 'DEP-YYMM####', the same human-facing sequential id convention as
  -- invoices / sales / pro_forma_invoices / journal_entries.
  id text primary key,
  branch_id uuid not null references public.branches (id) on delete restrict,
  -- NEVER null: a deposit is always owed back to a specific, real customer.
  customer_id uuid not null references public.customers (id) on delete restrict,
  customer_name text not null,
  description text not null default '',
  amount numeric(12, 2) not null check (amount > 0),
  -- how the deposit itself was paid in (mirrors POS_METHODS)
  method text not null check (method in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer')),
  bank_account_id uuid references public.bank_accounts (id) on delete restrict,
  status text not null default 'Open' check (status in ('Open', 'Fulfilled', 'Cancelled')),
  taken_at timestamptz not null default now(),
  taken_by uuid not null references public.staff (id) on delete restrict default auth.uid(),
  -- exactly one of these two is set when status = 'Fulfilled'
  fulfilled_sale_id text references public.sales (id) on delete restrict,
  fulfilled_invoice_id text references public.invoices (id) on delete restrict,
  fulfilled_at timestamptz,
  -- all four set together when status = 'Cancelled'
  cancelled_at timestamptz,
  cancelled_by uuid references public.staff (id) on delete restrict,
  cancellation_fee numeric(12, 2) check (cancellation_fee >= 0),
  cancellation_refund numeric(12, 2) check (cancellation_refund >= 0),
  cancellation_note text,

  constraint customer_deposits_bank_account_shape
    check (bank_account_id is null or method in ('Card', 'Bank Transfer')),
  constraint customer_deposits_open_is_clean
    check (status <> 'Open' or (
      fulfilled_sale_id is null and fulfilled_invoice_id is null and fulfilled_at is null
      and cancelled_at is null and cancelled_by is null
      and cancellation_fee is null and cancellation_refund is null
    )),
  constraint customer_deposits_fulfilled_shape
    check (status <> 'Fulfilled' or (
      fulfilled_at is not null
      and (fulfilled_sale_id is not null) <> (fulfilled_invoice_id is not null)
    )),
  constraint customer_deposits_cancelled_shape
    check (status <> 'Cancelled' or (
      cancelled_at is not null and cancelled_by is not null
      and cancellation_fee is not null and cancellation_refund is not null
    ))
);
create index customer_deposits_customer_idx on public.customer_deposits (customer_id);
create index customer_deposits_status_idx on public.customer_deposits (status);

-- Identity: taken_by forced on insert, cancelled_by forced when the row
-- transitions into Cancelled — the same unspoofable-identity discipline
-- every other actor column in this build uses (Session 7).
create or replace function public.set_customer_deposit_identity()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then new.taken_by := auth.uid(); end if;
  elsif tg_op = 'UPDATE' then
    if new.cancelled_at is not null and old.cancelled_at is null and auth.uid() is not null then
      new.cancelled_by := auth.uid();
    end if;
  end if;
  return new;
end;
$$;
create trigger customer_deposits_set_identity
before insert or update on public.customer_deposits
for each row execute function public.set_customer_deposit_identity();

-- ---------------------------------------------------------------------------
-- 3. Posters (Session 14 SECURITY DEFINER style, keyed by source_id)
-- ---------------------------------------------------------------------------
create or replace function public.post_customer_deposit_journal_entry(p_deposit_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_dep public.customer_deposits;
  v_settlement uuid;
  v_lines jsonb;
begin
  select * into v_dep from public.customer_deposits where id = p_deposit_id;
  if not found then raise exception 'Deposit % not found', p_deposit_id; end if;

  v_settlement := public.settlement_account(v_dep.method, v_dep.bank_account_id);

  v_lines := jsonb_build_array(
    jsonb_build_object('account_id', v_settlement,
      'debit', v_dep.amount, 'credit', 0, 'description', 'Customer deposit ' || v_dep.id),
    jsonb_build_object('account_id', public.account_id_by_code('2450'),
      'debit', 0, 'credit', v_dep.amount, 'description', 'Customer deposit ' || v_dep.id)
  );

  return public._post_journal_entry_rows(
    v_dep.branch_id, v_dep.taken_at::date, 'Customer deposit ' || v_dep.id, v_dep.id,
    v_lines, 'customer_deposits', v_dep.id
  );
end;
$$;

create or replace function public.post_customer_deposit_cancellation_journal_entry(p_deposit_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_dep public.customer_deposits;
  v_settlement uuid;
  v_lines jsonb;
begin
  select * into v_dep from public.customer_deposits where id = p_deposit_id;
  if not found then raise exception 'Deposit % not found', p_deposit_id; end if;
  if v_dep.status <> 'Cancelled' then
    raise exception 'Deposit % is not cancelled', p_deposit_id;
  end if;

  v_settlement := public.settlement_account(v_dep.method, v_dep.bank_account_id);

  -- Dr 2450 the whole liability; credit the refund back out the way it came
  -- in, and the fee (if any) to Other Income. refund + fee = amount, so this
  -- always balances by construction.
  v_lines := jsonb_build_array(
    jsonb_build_object('account_id', public.account_id_by_code('2450'),
      'debit', v_dep.amount, 'credit', 0, 'description', 'Cancel deposit ' || v_dep.id)
  );
  if v_dep.cancellation_refund > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', v_settlement,
      'debit', 0, 'credit', v_dep.cancellation_refund, 'description', 'Refund of deposit ' || v_dep.id));
  end if;
  if v_dep.cancellation_fee > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4900'),
      'debit', 0, 'credit', v_dep.cancellation_fee, 'description', 'Cancellation fee on deposit ' || v_dep.id));
  end if;

  return public._post_journal_entry_rows(
    v_dep.branch_id, v_dep.cancelled_at::date, 'Cancel customer deposit ' || v_dep.id,
    v_dep.id || ':cancellation', v_lines, 'customer_deposits', v_dep.id || ':cancellation'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. RPCs: create + cancel (fulfilment goes through create_sale() /
--    record_invoice_payment() further below)
-- ---------------------------------------------------------------------------
create or replace function public.create_customer_deposit(
  p_branch_id uuid,
  p_customer_id uuid,
  p_description text,
  p_amount numeric,
  p_method text,
  p_bank_account_id uuid default null
) returns public.customer_deposits
language plpgsql
as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_customer public.customers;
  v_dep public.customer_deposits;
begin
  perform public.require_writable_role();

  if p_customer_id is null then
    raise exception 'A customer deposit requires a real customer — it cannot be taken for a Walk-in';
  end if;
  select * into v_customer from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer % not found', p_customer_id; end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'The deposit amount must be greater than zero';
  end if;
  if p_method not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer') then
    raise exception 'Invalid deposit payment method %', p_method;
  end if;
  if p_method in ('Card', 'Bank Transfer') then
    if p_bank_account_id is null then
      raise exception 'Select the bank account this % deposit settled into', p_method;
    end if;
    if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
  end if;

  insert into public.deposit_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = deposit_number_counters.last_number + 1
  returning last_number into v_seq;
  v_id := 'DEP-' || v_year_month || lpad(v_seq::text, 4, '0');

  insert into public.customer_deposits (
    id, branch_id, customer_id, customer_name, description, amount, method,
    bank_account_id
  ) values (
    v_id, p_branch_id, p_customer_id, v_customer.name, coalesce(p_description, ''), p_amount, p_method,
    case when p_method in ('Card', 'Bank Transfer') then p_bank_account_id else null end
  )
  returning * into v_dep;

  perform public.post_customer_deposit_journal_entry(v_id);
  return v_dep;
end;
$$;

create or replace function public.cancel_customer_deposit(
  p_deposit_id text,
  p_fee numeric,
  p_note text default null
) returns public.customer_deposits
language plpgsql
as $$
declare
  v_dep public.customer_deposits;
  v_fee numeric;
  v_refund numeric;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can cancel a customer deposit';
  end if;

  select * into v_dep from public.customer_deposits where id = p_deposit_id for update;
  if not found then raise exception 'Deposit % not found', p_deposit_id; end if;
  if v_dep.status <> 'Open' then
    raise exception 'Only an open deposit can be cancelled (% is %)', p_deposit_id, v_dep.status;
  end if;

  v_fee := round(coalesce(p_fee, 0), 2);
  if v_fee < 0 then raise exception 'The cancellation fee cannot be negative'; end if;
  if v_fee > v_dep.amount + 0.01 then
    raise exception 'The cancellation fee (%) cannot exceed the deposit amount (%)', v_fee, v_dep.amount;
  end if;
  v_refund := round(v_dep.amount - v_fee, 2);

  update public.customer_deposits set
    status = 'Cancelled',
    cancelled_at = now(),
    cancellation_fee = v_fee,
    cancellation_refund = v_refund,
    cancellation_note = nullif(trim(coalesce(p_note, '')), '')
  where id = p_deposit_id
  returning * into v_dep;

  perform public.post_customer_deposit_cancellation_journal_entry(p_deposit_id);
  return v_dep;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. 'Deposit' as a payment method — maps to 2450, accepted by POS and
--    invoice payment paths, and clears the deposit's liability when applied.
-- ---------------------------------------------------------------------------
create or replace function public.payment_method_account(p_method text)
returns uuid
language plpgsql
stable
as $$
begin
  case p_method
    when 'Cash' then return public.account_id_by_code('1000');
    when 'Mobile Money' then return public.account_id_by_code('1020');
    when 'Store Credit' then return public.account_id_by_code('2400');
    when 'WHT Credit' then return public.account_id_by_code('1150');
    when 'Deposit' then return public.account_id_by_code('2450');
    when 'Card', 'Bank Transfer', 'Bank', 'Cheque' then
      raise exception 'Card/Bank Transfer/Cheque settlements route to a specific bank account — use settlement_account(method, bank_account_id), not payment_method_account()';
    else raise exception 'No GL account mapping for payment method %', p_method;
  end case;
end;
$$;

alter table public.sale_payments drop constraint sale_payments_method_check;
alter table public.sale_payments
  add constraint sale_payments_method_check
  check (method in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer', 'Store Credit', 'Deposit'));

alter table public.invoice_payments drop constraint invoice_payments_method_check;
alter table public.invoice_payments
  add constraint invoice_payments_method_check
  check (method in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque', 'Store Credit', 'WHT Credit', 'Deposit'));

-- ---------------------------------------------------------------------------
-- 5a. create_sale(): a 'Deposit' payment leg (rides inside p_payments, like
--     Store Credit and bank_account_id — signature UNCHANGED, so no
--     drop/overload dance). Body carried verbatim from
--     20260831100000_pos_sale_note.sql (the current definition — 10 args
--     incl. p_notes), with the deposit validation + fulfilment update added.
-- ---------------------------------------------------------------------------
create or replace function public.create_sale(
  p_branch_id uuid, p_customer_id uuid, p_customer_name text,
  p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text,
  p_lines jsonb, p_payments jsonb,
  p_override_ticket uuid default null,
  p_notes text default ''
) returns public.sales language plpgsql as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_rate numeric;
  v_total numeric;
  v_paid numeric;
  v_cash numeric;
  v_non_cash numeric;
  v_sale public.sales;
  v_line jsonb;
  v_product public.products;
  v_payment jsonb;
  v_authorized boolean;
  v_override_manager_id uuid;
  v_store_credit_used numeric;
  v_customer_credit numeric;
  v_deposit_id text;
  v_deposit_amount numeric;
  v_deposit public.customer_deposits;
begin
  perform public.require_writable_role();

  if p_sale_discount_mode not in ('amount', 'percent') or p_vat_mode not in ('per-item', 'all', 'none') then raise exception 'Invalid discount or VAT mode'; end if;

  v_authorized := public.has_role(array['Manager']);

  if not v_authorized and p_override_ticket is not null then
    v_override_manager_id := public.consume_manager_override(p_override_ticket);
    v_authorized := true;
  end if;

  if not v_authorized then
    if p_sale_discount_value <> 0 then
      if p_customer_id is null or not exists (
        select 1 from public.customer_discounts
        where customer_id = p_customer_id
          and mode = p_sale_discount_mode
          and value = p_sale_discount_value
          and active
      ) then
        raise exception 'Only a Manager can apply a discount that is not an active, customer-attached discount';
      end if;
    end if;

    if exists (
      select 1 from jsonb_array_elements(p_lines) as l
      where coalesce((l.value->>'discount_value')::numeric, 0) <> 0
    ) then
      raise exception 'Only a Manager can apply a per-item discount';
    end if;

    if p_vat_mode <> 'per-item' then
      raise exception 'Only a Manager can override VAT for the whole sale';
    end if;

    if exists (
      select 1 from jsonb_array_elements(p_lines) as l
      where coalesce((l.value->>'vat')::boolean, true) = false
    ) then
      raise exception 'Only a Manager can turn off VAT for an item';
    end if;
  end if;

  select vat_rate into v_rate from public.business_settings where id = 1;
  v_total := public.compute_sale_total(p_lines, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate);
  select coalesce(sum((value->>'amount')::numeric), 0), coalesce(sum(case when value->>'method' = 'Cash' then (value->>'amount')::numeric else 0 end), 0), coalesce(sum(case when value->>'method' <> 'Cash' then (value->>'amount')::numeric else 0 end), 0) into v_paid, v_cash, v_non_cash from jsonb_array_elements(p_payments);
  if jsonb_array_length(p_payments) = 0 or v_paid < v_total - .01 or v_non_cash > v_total + .01 then raise exception 'Payments must cover the sale; only cash may exceed the total'; end if;
  for v_payment in select value from jsonb_array_elements(p_payments) loop
    if (v_payment->>'method') not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer', 'Store Credit', 'Deposit') or coalesce((v_payment->>'amount')::numeric, 0) <= 0 then raise exception 'Invalid POS payment'; end if;
    if (v_payment->>'method') in ('Card', 'Bank Transfer') then
      if (v_payment->>'bank_account_id') is null then
        raise exception 'Select the bank account for the % payment', v_payment->>'method';
      end if;
      if not exists (select 1 from public.bank_accounts where id = (v_payment->>'bank_account_id')::uuid) then
        raise exception 'Bank account % not found', v_payment->>'bank_account_id';
      end if;
    end if;
  end loop;

  select coalesce(sum((value->>'amount')::numeric), 0) into v_store_credit_used
  from jsonb_array_elements(p_payments)
  where value->>'method' = 'Store Credit';

  if v_store_credit_used > 0 then
    if p_customer_id is null then
      raise exception 'Store credit requires a customer to be selected — it cannot be used on a Walk-in sale';
    end if;
    select store_credit_balance into v_customer_credit from public.customers where id = p_customer_id for update;
    if not found then
      raise exception 'Customer % not found', p_customer_id;
    end if;
    if v_store_credit_used > v_customer_credit + 0.01 then
      raise exception 'Store credit payment of % exceeds the customer''s available balance of %', v_store_credit_used, v_customer_credit;
    end if;
  end if;

  -- Deposit leg: at most one, must be an Open deposit for this exact
  -- customer, and the whole deposit is applied (strictly two-step — no
  -- partial application).
  select value->>'deposit_id', coalesce((value->>'amount')::numeric, 0)
  into v_deposit_id, v_deposit_amount
  from jsonb_array_elements(p_payments)
  where value->>'method' = 'Deposit'
  limit 1;

  if v_deposit_id is not null then
    if p_customer_id is null then
      raise exception 'A deposit can only be applied to a sale for the customer who made it';
    end if;
    select * into v_deposit from public.customer_deposits where id = v_deposit_id for update;
    if not found or v_deposit.status <> 'Open' then
      raise exception 'Deposit % is not an open deposit', v_deposit_id;
    end if;
    if v_deposit.customer_id <> p_customer_id then
      raise exception 'Deposit % belongs to a different customer', v_deposit_id;
    end if;
    if abs(v_deposit_amount - v_deposit.amount) > 0.01 then
      raise exception 'The full deposit amount of % must be applied', v_deposit.amount;
    end if;
    if v_total < v_deposit.amount - 0.01 then
      raise exception 'This sale total (%) is less than the deposit amount (%) — add more items, or fulfil with an invoice instead', v_total, v_deposit.amount;
    end if;
    if (select count(*) from jsonb_array_elements(p_payments) where value->>'method' = 'Deposit') > 1 then
      raise exception 'Only one deposit can be applied to a sale';
    end if;
  end if;

  -- Lock each product in stable UUID order before deducting it. The check and
  -- update happen while those row locks are held, so concurrent tills cannot oversell.
  for v_line in select value from jsonb_array_elements(p_lines) order by (value->>'product_id')::uuid loop
    select * into v_product from public.products where id = (v_line->>'product_id')::uuid and branch_id = p_branch_id for update;
    if not found then raise exception 'Product % is not available at this branch', v_line->>'product_id'; end if;
    if v_product.price is null then raise exception 'Product % has no selling price set and cannot be sold', v_product.name; end if;
    if v_product.stock < (v_line->>'quantity')::integer then raise exception 'Insufficient stock for %', v_product.name; end if;
  end loop;
  insert into public.sale_number_counters(year_month, last_number) values(v_year_month, 1) on conflict(year_month) do update set last_number = sale_number_counters.last_number + 1 returning last_number into v_seq;
  v_id := 'POS-' || v_year_month || lpad(v_seq::text, 4, '0');
  insert into public.sales(id, branch_id, customer_id, customer_name, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total, override_authorized_by, notes)
  values(v_id, p_branch_id, p_customer_id, p_customer_name, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate, v_total, v_override_manager_id, coalesce(nullif(trim(p_notes), ''), ''))
  returning * into v_sale;
  insert into public.sale_lines(sale_id, product_id, name, unit, category, quantity, unit_price, discount_mode, discount_value, vat, position)
  select v_id, (line->>'product_id')::uuid, line->>'name', line->>'unit', line->>'category', (line->>'quantity')::integer, (line->>'unit_price')::numeric, coalesce(line->>'discount_mode', 'amount'), coalesce((line->>'discount_value')::numeric, 0), coalesce((line->>'vat')::boolean, true), ord - 1 from jsonb_array_elements(p_lines) with ordinality as t(line, ord);
  for v_line in select value from jsonb_array_elements(p_lines) loop
    update public.products set stock = stock - (v_line->>'quantity')::integer where id = (v_line->>'product_id')::uuid returning * into v_product;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_product.id, p_branch_id, 'Sale', -(v_line->>'quantity')::integer, v_product.stock, v_id);
  end loop;
  insert into public.sale_payments(sale_id, branch_id, method, amount, reference, bank_account_id)
  select v_id, p_branch_id, payment->>'method', (payment->>'amount')::numeric, coalesce(payment->>'reference', ''),
    case when payment->>'method' in ('Card', 'Bank Transfer') then (payment->>'bank_account_id')::uuid else null end
  from jsonb_array_elements(p_payments) payment;

  if v_store_credit_used > 0 then
    update public.customers set store_credit_balance = store_credit_balance - v_store_credit_used where id = p_customer_id;
  end if;

  if v_deposit_id is not null then
    update public.customer_deposits
    set status = 'Fulfilled', fulfilled_sale_id = v_id, fulfilled_at = now()
    where id = v_deposit_id;
  end if;

  perform public.post_sale_journal_entry(v_id);
  return v_sale;
end; $$;

-- Signature unchanged, so CREATE OR REPLACE kept the existing grants;
-- re-granted here for parity with 20260831100000.
grant execute on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb, uuid, text) to authenticated;
grant execute on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 5b. record_invoice_payment(): + p_deposit_id (8th param, default null).
--     A signature change -> drop the 7-arg overload first, re-grant after.
--     Body carried verbatim from 20260830090000, with the deposit branch.
-- ---------------------------------------------------------------------------
drop function if exists public.record_invoice_payment(text, numeric, text, text, text, timestamptz, uuid);

create or replace function public.record_invoice_payment(
  p_invoice_id text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_note text default '',
  p_paid_at timestamptz default now(),
  p_bank_account_id uuid default null,
  p_deposit_id text default null
)
returns public.invoice_payments
language plpgsql
as $$
declare
  v_branch_id uuid;
  v_total numeric;
  v_amount_paid numeric;
  v_customer_id uuid;
  v_customer_credit numeric;
  v_bank_account_id uuid;
  v_payment public.invoice_payments;
  v_deposit public.customer_deposits;
begin
  perform public.require_writable_role();

  if p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  if p_method in ('Bank Transfer', 'Cheque') then
    if p_bank_account_id is null then
      raise exception 'Select the bank account for the % payment', p_method;
    end if;
    if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
    v_bank_account_id := p_bank_account_id;
  else
    v_bank_account_id := null;
  end if;

  select branch_id, total, amount_paid, customer_id into v_branch_id, v_total, v_amount_paid, v_customer_id
  from public.invoices
  where id = p_invoice_id
  for update;

  if not found then
    raise exception 'Invoice % not found', p_invoice_id;
  end if;

  if p_amount > (v_total - v_amount_paid) + 0.01 then
    raise exception 'Payment of % exceeds the remaining balance of %', p_amount, v_total - v_amount_paid;
  end if;

  if p_method = 'Store Credit' then
    select store_credit_balance into v_customer_credit from public.customers where id = v_customer_id for update;
    if p_amount > v_customer_credit + 0.01 then
      raise exception 'Store credit payment of % exceeds the customer''s available balance of %', p_amount, v_customer_credit;
    end if;
  end if;

  if p_method = 'Deposit' then
    if p_deposit_id is null then
      raise exception 'A deposit id is required for a Deposit payment';
    end if;
    select * into v_deposit from public.customer_deposits where id = p_deposit_id for update;
    if not found or v_deposit.status <> 'Open' then
      raise exception 'Deposit % is not an open deposit', p_deposit_id;
    end if;
    if v_deposit.customer_id <> v_customer_id then
      raise exception 'Deposit % belongs to a different customer', p_deposit_id;
    end if;
    if abs(p_amount - v_deposit.amount) > 0.01 then
      raise exception 'The full deposit amount of % must be applied', v_deposit.amount;
    end if;
  end if;

  insert into public.invoice_payments (invoice_id, branch_id, amount, method, reference, note, paid_at, bank_account_id)
  values (p_invoice_id, v_branch_id, p_amount, p_method, p_reference, p_note, p_paid_at, v_bank_account_id)
  returning * into v_payment;

  update public.invoices
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_total - (v_amount_paid + p_amount), 0)
  where id = p_invoice_id;

  if p_method = 'Store Credit' then
    update public.customers set store_credit_balance = store_credit_balance - p_amount where id = v_customer_id;
  end if;

  if p_method = 'Deposit' then
    update public.customer_deposits
    set status = 'Fulfilled', fulfilled_invoice_id = p_invoice_id, fulfilled_at = now()
    where id = p_deposit_id;
  end if;

  perform public.post_invoice_payment_journal_entry(v_payment.id);
  return v_payment;
end;
$$;

grant execute on function public.record_invoice_payment(text, numeric, text, text, text, timestamptz, uuid, text) to authenticated;
grant execute on function public.record_invoice_payment(text, numeric, text, text, text, timestamptz, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 6. RLS + grants — the operational 3-tier (role_permissions_rewrite):
--    select = any active staff, insert/update = can_write() (Manager or
--    Attendant — recording and fulfilling a deposit are counter actions,
--    like a sale), delete = Manager. Cancellation's Manager-only rule is
--    enforced inside cancel_customer_deposit(), not RLS, so an Attendant
--    can still update a row via the fulfilment path.
-- ---------------------------------------------------------------------------
alter table public.customer_deposits enable row level security;
create policy customer_deposits_select on public.customer_deposits for select using (public.is_active_staff());
create policy customer_deposits_insert on public.customer_deposits for insert with check (public.can_write());
create policy customer_deposits_update on public.customer_deposits for update using (public.can_write()) with check (public.can_write());
create policy customer_deposits_delete on public.customer_deposits for delete using (public.has_role(array['Manager']));

revoke all on public.customer_deposits from anon;
grant select, insert, update, delete on public.customer_deposits to authenticated;
grant select, insert, update, delete on public.customer_deposits to service_role;
grant select, insert, update, delete on public.deposit_number_counters to authenticated;
grant select, insert, update, delete on public.deposit_number_counters to service_role;

grant execute on function public.create_customer_deposit(uuid, uuid, text, numeric, text, uuid) to authenticated;
grant execute on function public.create_customer_deposit(uuid, uuid, text, numeric, text, uuid) to service_role;
grant execute on function public.cancel_customer_deposit(text, numeric, text) to authenticated;
grant execute on function public.cancel_customer_deposit(text, numeric, text) to service_role;
grant execute on function public.post_customer_deposit_journal_entry(text) to authenticated;
grant execute on function public.post_customer_deposit_journal_entry(text) to service_role;
grant execute on function public.post_customer_deposit_cancellation_journal_entry(text) to authenticated;
grant execute on function public.post_customer_deposit_cancellation_journal_entry(text) to service_role;
