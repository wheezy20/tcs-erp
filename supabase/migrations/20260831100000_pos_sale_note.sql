-- POS checkout gets an optional free-text note, printed on the receipt
-- when filled in and left off entirely when blank — matching invoices'
-- existing `notes` field exactly rather than inventing a new shape:
--
--   invoices.notes text not null default ''      -> sales.notes    (same)
--   create_invoice(p_notes text)                 -> create_sale(p_notes text default '')
--   Invoice.notes: string  (never null)          -> PosSale.notes: string
--   invoice-form.tsx <Textarea maxLength={240}>  -> pos.index.tsx same cap
--
-- Not null, default '' — an unset note and a confirmed-empty note are the
-- same thing here (a receipt line that simply isn't rendered), so there's
-- no reason to distinguish them with a nullable column the way cost/price
-- needed. update_sale() does not exist (a POS receipt is immutable once
-- rung up), so there's no edit path to consider — the note is fixed at
-- creation like every other sale field.
--
-- Held sales (held_sales) deliberately do NOT carry the note: a held sale
-- is a cart snapshot, and nothing in the ask covers preserving an
-- in-progress note across hold/resume. Resuming a held sale starts its
-- note blank, the same way it already starts its manager-override ticket
-- blank.

alter table public.sales
  add column notes text not null default '';

-- create_sale() gains a trailing p_notes parameter (default '') — a
-- changed argument list is a new overload, not a replacement, so the old
-- 9-arg signature is dropped explicitly first and the new one re-granted
-- after, the same discipline this function's own history already required
-- (auth_roles_schema.sql, manager_pin_authorization.sql,
-- multi_bank_account_posting.sql). Body is otherwise carried verbatim
-- from multi_bank_account_posting.sql's version; the only change is
-- `notes` added to the sales INSERT.
drop function if exists public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb, uuid);

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

  perform public.post_sale_journal_entry(v_id);
  return v_sale;
end; $$;

grant execute on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb, uuid, text) to authenticated;
grant execute on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb, uuid, text) to service_role;
