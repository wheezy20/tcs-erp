-- Same-day follow-up to Session 14 (Auto-Posting Integration), before
-- moving on: two posting gaps found during that session's own "flagged,
-- not built" list, plus building store credit redemption for real instead
-- of leaving it flagged.
--
-- ============================================================ fix 1: top-up
--
-- Session 14 skipped 'Top-up collected' entirely. It shouldn't have — a
-- top-up is real cash (or Mobile Money/Card/Bank Transfer) actually
-- collected, same shape as an ordinary sale: Dr the payment method, Cr
-- Sales Revenue and VAT Payable for the difference. The gap was real
-- because create_sale_return() never captured *how* a top-up was paid —
-- sale_returns.payment_method is new, required exactly when
-- resolution = 'Top-up collected', and null otherwise.
--
-- VAT on the top-up follows the original sale's own vat_mode/vat_rate
-- (sales.difference is a VAT-exclusive amount, same convention as
-- sale_lines.unit_price — see compute_sale_total()) rather than inventing
-- a separate per-return VAT choice the UI has no way to express.
--
-- ======================================================= fix 2: even exchange
--
-- Session 14's post_sale_return_journal_entry() returned null immediately
-- for any resolution other than 'Cash refund'/'Store credit' — which
-- meant an exchange with no cash/credit component (Even exchange, and
-- Top-up before fix 1 above) got no Inventory/COGS adjustment either, even
-- though real stock genuinely moved both directions. The Inventory/COGS
-- net adjustment is now computed unconditionally, for every resolution;
-- only the monetary side (refund/credit/top-up) is resolution-specific.
-- An Even exchange with equal-cost items still posts nothing (net COGS is
-- exactly zero, nothing to reconcile) — that remains correct, not a bug.
--
-- ================================================ feature: store credit
--
-- customers.store_credit_balance is new, deliberately separate from the
-- existing customers.balance column and never touched by the same trigger
-- or code path — balance is accounts-receivable-style (what the customer
-- owes the business, auto-recomputed from invoices by
-- sync_customer_totals()); store_credit_balance is the opposite direction
-- (what the business owes the customer) and is maintained by plain,
-- explicit updates inside the three RPCs that legitimately touch it, not a
-- trigger recomputing it from source data the way balance is. That's a
-- deliberate departure from the balance/lifetime_total precedent: balance
-- has many write paths into invoices (create, edit, payment, bulk import)
-- where a trigger genuinely can't be forgotten by a future call site,
-- while store_credit_balance has exactly three, all touched by this one
-- migration, each already holding the relevant row lock at the moment it
-- writes — a recompute-from-source trigger would need to net two sources
-- across three tables with two different customer-resolution joins for
-- comparatively little benefit here.
--
-- Increases (create_sale_return(), resolution = 'Store credit'): a plain
-- `balance = balance + x` update needs no prior lock — there's no cap to
-- protect, so no check-then-act race exists to guard against. Also closes
-- a real pre-existing gap: create_sale_return() never required a customer
-- for a Store credit resolution at all (sales.customer_id can be null for
-- a Walk-in sale), so a Walk-in store-credit return would have silently
-- credited nobody. Now rejected outright with a clear error.
--
-- Decreases (create_sale(), record_invoice_payment(), a new 'Store Credit'
-- payment method): both lock the customer row (`for update`) before
-- checking the balance covers the requested amount, then deduct — the
-- same check-then-act-under-lock discipline create_sale() already uses for
-- stock, for the same reason (two concurrent spends against the same
-- balance must not both pass the check before either deducts).
-- payment_method_account() gains 'Store Credit' -> 2400 Customer Store
-- Credit, so both create_sale()'s and record_invoice_payment()'s existing
-- generic posting logic (which already calls payment_method_account() per
-- payment method) picks this up with no further changes to either poster.
-- Store Credit is treated as a non-cash method for the existing "only cash
-- may exceed the total" check in create_sale() — it already falls into
-- that bucket automatically (`method <> 'Cash'`), so it's capped at its
-- own allocated share of the sale by the pre-existing math, no new logic
-- needed for that half of "capped at the sale total remaining."

alter table public.customers
  add column store_credit_balance numeric(12, 2) not null default 0 check (store_credit_balance >= 0);

alter table public.sale_returns
  add column payment_method text check (payment_method in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer'));

alter table public.sale_payments drop constraint sale_payments_method_check;
alter table public.sale_payments
  add constraint sale_payments_method_check
  check (method in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer', 'Store Credit'));

alter table public.invoice_payments drop constraint invoice_payments_method_check;
alter table public.invoice_payments
  add constraint invoice_payments_method_check
  check (method in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque', 'Store Credit'));

-- Card/Bank Transfer/Bank/Cheque all still settle to 1010 (see the Session
-- 14 migration header for why); Store Credit is the one genuinely new
-- mapping.
create or replace function public.payment_method_account(p_method text)
returns uuid
language plpgsql
stable
as $$
begin
  case p_method
    when 'Cash' then return public.account_id_by_code('1000');
    when 'Mobile Money' then return public.account_id_by_code('1020');
    when 'Card', 'Bank Transfer', 'Bank', 'Cheque' then return public.account_id_by_code('1010');
    when 'Store Credit' then return public.account_id_by_code('2400');
    else raise exception 'No GL account mapping for payment method %', p_method;
  end case;
end;
$$;

-- ================================================ post_sale_return_journal_entry
--
-- Restructured per fixes 1 and 2 above: the Inventory/COGS net adjustment
-- is unconditional (every resolution), the monetary side branches on
-- resolution (Cash refund / Store credit / Top-up collected / nothing for
-- Even exchange).
create or replace function public.post_sale_return_journal_entry(p_return_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_return public.sale_returns;
  v_sale public.sales;
  v_returned_cost numeric;
  v_replacement_cost numeric;
  v_net_cogs numeric;
  v_refund_amount numeric;
  v_topup_vat numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_target_account uuid;
begin
  select * into v_return from public.sale_returns where id = p_return_id;
  if not found then
    raise exception 'Return % not found', p_return_id;
  end if;

  select * into v_sale from public.sales where id = v_return.sale_id;

  select coalesce(cost, 0) * v_return.returned_quantity into v_returned_cost
  from public.products where id = v_return.returned_product_id;
  v_returned_cost := coalesce(v_returned_cost, 0);

  v_replacement_cost := 0;
  if v_return.replacement_product_id is not null then
    select coalesce(cost, 0) * v_return.replacement_quantity into v_replacement_cost
    from public.products where id = v_return.replacement_product_id;
    v_replacement_cost := coalesce(v_replacement_cost, 0);
  end if;

  v_net_cogs := v_replacement_cost - v_returned_cost;

  if v_net_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('5000'),
        'debit', v_net_cogs, 'credit', 0, 'description', 'Return exchange COGS'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', 0, 'credit', v_net_cogs, 'description', 'Return exchange inventory'
      )
    );
  elsif v_net_cogs < 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', abs(v_net_cogs), 'credit', 0, 'description', 'Return inventory'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('5000'),
        'debit', 0, 'credit', abs(v_net_cogs), 'description', 'Return COGS reversal'
      )
    );
  end if;

  if v_return.resolution in ('Cash refund', 'Store credit') then
    v_refund_amount := abs(least(v_return.difference, 0));
    if v_refund_amount > 0 then
      v_target_account := case v_return.resolution
        when 'Cash refund' then public.account_id_by_code('1000')
        when 'Store credit' then public.account_id_by_code('2400')
      end;
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object(
          'account_id', public.account_id_by_code('4100'),
          'debit', v_refund_amount, 'credit', 0, 'description', v_return.resolution
        ),
        jsonb_build_object(
          'account_id', v_target_account,
          'debit', 0, 'credit', v_refund_amount, 'description', v_return.resolution
        )
      );
    end if;
  elsif v_return.resolution = 'Top-up collected' and v_return.difference > 0 then
    if v_sale.vat_mode <> 'none' then
      v_topup_vat := round(v_return.difference * v_sale.vat_rate / 100, 2);
    end if;
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', public.payment_method_account(v_return.payment_method),
        'debit', v_return.difference + v_topup_vat, 'credit', 0, 'description', 'Top-up collected'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('4000'),
        'debit', 0, 'credit', v_return.difference, 'description', 'Top-up sale revenue'
      )
    );
    if v_topup_vat > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'account_id', public.account_id_by_code('2100'),
        'debit', 0, 'credit', v_topup_vat, 'description', 'Top-up VAT collected'
      ));
    end if;
  end if;
  -- 'Even exchange' contributes no monetary lines — money-neutral by definition.

  if jsonb_array_length(v_lines) < 2 then
    return null;
  end if;

  return public._post_journal_entry_rows(
    v_return.branch_id, v_return.returned_at::date, v_return.resolution || ' on ' || v_return.sale_id,
    p_return_id::text, v_lines, 'sale_returns', p_return_id::text
  );
end;
$$;

-- ============================================================ create_sale_return
--
-- Gains p_payment_method (required exactly for 'Top-up collected', see fix
-- 1) and the Store-credit-requires-a-customer check + balance credit (see
-- the store credit header note above). Every other line is unchanged from
-- the Session 14 migration's copy of this function. The old 8-parameter
-- overload must be dropped explicitly first — CREATE OR REPLACE with an
-- added parameter creates a second overload rather than replacing the
-- original (same reasoning create_sale()'s own history already hit twice:
-- see the `drop function if exists public.create_sale(...)` lines in
-- auth_roles_schema.sql and manager_pin_authorization.sql), which would
-- otherwise leave PostgREST unable to resolve which one a plain RPC call
-- means.
drop function if exists public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text);

create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text, p_payment_method text default null
) returns public.sale_returns language plpgsql as $$
declare
  v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products;
  v_prior integer; v_difference numeric; v_return public.sale_returns; v_refund_amount numeric;
begin
  perform public.require_writable_role();

  if p_resolution = 'Cash refund' and not public.has_role(array['Manager']) then
    raise exception 'A cash refund requires a Manager — store credit does not';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update; if not found then raise exception 'Sale % not found', p_sale_id; end if;

  if p_resolution = 'Store credit' and v_sale.customer_id is null then
    raise exception 'Store credit requires a customer on the original sale — it cannot be issued on a Walk-in sale';
  end if;

  select * into v_line from public.sale_lines where id = p_returned_sale_line_id and sale_id = p_sale_id for update; if not found then raise exception 'Sale line does not belong to this sale'; end if;
  select coalesce(sum(returned_quantity), 0) into v_prior from public.sale_returns where returned_sale_line_id = p_returned_sale_line_id;
  if p_returned_quantity <= 0 or p_returned_quantity + v_prior > v_line.quantity then raise exception 'Return quantity exceeds quantity sold'; end if;
  perform 1 from public.products
  where id in (v_line.product_id, p_replacement_product_id)
  order by id for update;
  select * into v_returned from public.products where id = v_line.product_id;
  if p_replacement_product_id is not null then
    select * into v_replacement from public.products where id = p_replacement_product_id and branch_id = v_sale.branch_id;
    if not found or p_replacement_quantity is null or p_replacement_quantity <= 0 then raise exception 'Invalid replacement item'; end if;
    if v_replacement.stock < p_replacement_quantity then raise exception 'Insufficient stock for %', v_replacement.name; end if;
  end if;
  v_difference := round(coalesce(v_replacement.price * p_replacement_quantity, 0) - (v_line.unit_price * p_returned_quantity), 2);

  if p_resolution = 'Top-up collected' then
    if v_difference <= 0 then
      raise exception 'Top-up collected requires the replacement to cost more than the returned item';
    end if;
    if p_payment_method is null or p_payment_method not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer') then
      raise exception 'A valid payment method is required to collect a top-up';
    end if;
  end if;

  insert into public.sale_returns(sale_id, branch_id, returned_sale_line_id, returned_product_id, returned_name, returned_unit, returned_quantity, returned_unit_price, replacement_product_id, replacement_name, replacement_unit, replacement_quantity, replacement_unit_price, difference, resolution, approval_state, reason, payment_method)
  values(p_sale_id, v_sale.branch_id, v_line.id, v_line.product_id, v_line.name, v_line.unit, p_returned_quantity, v_line.unit_price, p_replacement_product_id, v_replacement.name, v_replacement.unit, p_replacement_quantity, v_replacement.price, v_difference, p_resolution, p_approval_state, coalesce(p_reason, ''), case when p_resolution = 'Top-up collected' then p_payment_method else null end)
  returning * into v_return;
  update public.products set stock = stock + p_returned_quantity where id = v_returned.id returning * into v_returned;
  insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_returned.id, v_sale.branch_id, 'Return', p_returned_quantity, v_returned.stock, v_return.id::text);
  if p_replacement_product_id is not null then
    update public.products set stock = stock - p_replacement_quantity where id = v_replacement.id returning * into v_replacement;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_replacement.id, v_sale.branch_id, 'Sale', -p_replacement_quantity, v_replacement.stock, v_return.id::text || ' replacement');
  end if;

  if p_resolution = 'Store credit' then
    v_refund_amount := abs(least(v_difference, 0));
    if v_refund_amount > 0 then
      update public.customers set store_credit_balance = store_credit_balance + v_refund_amount where id = v_sale.customer_id;
    end if;
  end if;

  perform public.post_sale_return_journal_entry(v_return.id);
  return v_return;
end; $$;

grant execute on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text, text) to authenticated;

-- ============================================================ create_sale
--
-- Gains 'Store Credit' as an allowed payment method plus the lock-check-
-- deduct sequence described in the header note above. The customer lock
-- (when used) happens before the product-locking loop, establishing one
-- consistent lock order (customer, then products in stable UUID order)
-- across every create_sale() call so two concurrent sales can never
-- deadlock against each other over the new lock. Every other line is
-- unchanged from the Session 14 migration's copy of this function.
create or replace function public.create_sale(
  p_branch_id uuid, p_customer_id uuid, p_customer_name text,
  p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text,
  p_lines jsonb, p_payments jsonb,
  p_override_ticket uuid default null
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
    if (v_payment->>'method') not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer', 'Store Credit') or coalesce((v_payment->>'amount')::numeric, 0) <= 0 then raise exception 'Invalid POS payment'; end if;
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

  -- Lock each product in stable UUID order before deducting it. The check and
  -- update happen while those row locks are held, so concurrent tills cannot oversell.
  for v_line in select value from jsonb_array_elements(p_lines) order by (value->>'product_id')::uuid loop
    select * into v_product from public.products where id = (v_line->>'product_id')::uuid and branch_id = p_branch_id for update;
    if not found then raise exception 'Product % is not available at this branch', v_line->>'product_id'; end if;
    if v_product.stock < (v_line->>'quantity')::integer then raise exception 'Insufficient stock for %', v_product.name; end if;
  end loop;
  insert into public.sale_number_counters(year_month, last_number) values(v_year_month, 1) on conflict(year_month) do update set last_number = sale_number_counters.last_number + 1 returning last_number into v_seq;
  v_id := 'POS-' || v_year_month || lpad(v_seq::text, 4, '0');
  insert into public.sales(id, branch_id, customer_id, customer_name, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total, override_authorized_by) values(v_id, p_branch_id, p_customer_id, p_customer_name, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate, v_total, v_override_manager_id) returning * into v_sale;
  insert into public.sale_lines(sale_id, product_id, name, unit, category, quantity, unit_price, discount_mode, discount_value, vat, position)
  select v_id, (line->>'product_id')::uuid, line->>'name', line->>'unit', line->>'category', (line->>'quantity')::integer, (line->>'unit_price')::numeric, coalesce(line->>'discount_mode', 'amount'), coalesce((line->>'discount_value')::numeric, 0), coalesce((line->>'vat')::boolean, true), ord - 1 from jsonb_array_elements(p_lines) with ordinality as t(line, ord);
  for v_line in select value from jsonb_array_elements(p_lines) loop
    update public.products set stock = stock - (v_line->>'quantity')::integer where id = (v_line->>'product_id')::uuid returning * into v_product;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_product.id, p_branch_id, 'Sale', -(v_line->>'quantity')::integer, v_product.stock, v_id);
  end loop;
  insert into public.sale_payments(sale_id, branch_id, method, amount, reference) select v_id, p_branch_id, payment->>'method', (payment->>'amount')::numeric, coalesce(payment->>'reference', '') from jsonb_array_elements(p_payments) payment;

  if v_store_credit_used > 0 then
    update public.customers set store_credit_balance = store_credit_balance - v_store_credit_used where id = p_customer_id;
  end if;

  perform public.post_sale_journal_entry(v_id);
  return v_sale;
end; $$;

-- ============================================================ record_invoice_payment
--
-- Gains the same lock-check-deduct sequence for a 'Store Credit' payment.
-- invoices.customer_id is not null (no Walk-in concept for invoices), so
-- no separate "requires a customer" check is needed the way create_sale()
-- needed one. No explicit method allow-list check is added here, matching
-- the original function's own style — invoice_payments_method_check (now
-- including 'Store Credit') already rejects anything else at insert time.
-- Every other line is unchanged from its original definition.
create or replace function public.record_invoice_payment(
  p_invoice_id text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_note text default '',
  p_paid_at timestamptz default now()
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
  v_payment public.invoice_payments;
begin
  perform public.require_writable_role();

  if p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
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

  insert into public.invoice_payments (invoice_id, branch_id, amount, method, reference, note, paid_at)
  values (p_invoice_id, v_branch_id, p_amount, p_method, p_reference, p_note, p_paid_at)
  returning * into v_payment;

  update public.invoices
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_total - (v_amount_paid + p_amount), 0)
  where id = p_invoice_id;

  if p_method = 'Store Credit' then
    update public.customers set store_credit_balance = store_credit_balance - p_amount where id = v_customer_id;
  end if;

  perform public.post_invoice_payment_journal_entry(v_payment.id);
  return v_payment;
end;
$$;
