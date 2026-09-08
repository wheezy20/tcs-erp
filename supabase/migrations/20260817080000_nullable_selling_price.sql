-- Selling price becomes nullable, same as cost price before it — but with
-- a structural block instead of a "post it as an estimate, flag it"
-- treatment. A missing cost only makes a report less accurate; a missing
-- price defaulting to zero would mean actually giving stock away for free
-- at the register or on an invoice, so there is no safe estimate to fall
-- back to the way COGS could fall back to 0. This migration therefore has
-- no ledger-flag counterpart the way nullable_cost_price.sql did —
-- products.price never feeds a journal posting directly (sale_lines.
-- unit_price / invoice_lines.unit_price are their own already-submitted,
-- already-validated figures), the risk here is entirely "can an unpriced
-- product be added to a transaction at all," not "is a posted total an
-- underestimate."
--
-- The `check (price >= 0)` constraint is untouched — it already passes
-- automatically on null. `default 0` is dropped for the same reason the
-- cost migration dropped it: once a blank price is a real, distinguishable
-- state, defaulting an unset one to 0 would immediately erase the
-- distinction this migration exists to create.
alter table public.products alter column price drop not null;
alter table public.products alter column price drop default;

-- ============================================================== create_sale
--
-- Reuses the row lock create_sale() already takes on every line's product
-- (for the oversell check) — the price check just needs to run inside the
-- same loop, no new lock required. Raises immediately on the first
-- unpriced product found, matching this function's own existing style
-- (the stock-insufficiency check right above it does the same).
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
    if v_product.price is null then raise exception 'Product % has no selling price set and cannot be sold', v_product.name; end if;
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

-- ============================================================ create_invoice
--
-- Invoices never touch stock, so create_invoice() has no product-locking
-- loop to piggyback the check onto the way create_sale() does — a plain
-- existence check against the referenced products is enough (no row lock
-- needed, there's no concurrent-mutation race to protect against: nothing
-- else can make a product's own price flip null out from under this call
-- in a way that matters here). Runs first, before anything is inserted, so
-- a blocked invoice never partially creates.
create or replace function public.create_invoice(
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb,
  p_wht_applied boolean default false
)
returns public.invoices
language plpgsql
as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_vat_rate numeric;
  v_wht_rate numeric;
  v_total numeric;
  v_posting record;
  v_taxable_subtotal numeric;
  v_wht_amount numeric := 0;
  v_invoice public.invoices;
  v_unpriced_name text;
begin
  perform public.require_writable_role();

  select p.name into v_unpriced_name
  from jsonb_array_elements(p_lines) as l
  join public.products p on p.id = nullif(l.value->>'product_id', '')::uuid
  where p.price is null
  limit 1;

  if v_unpriced_name is not null then
    raise exception 'Product "%" has no selling price set and cannot be invoiced', v_unpriced_name;
  end if;

  insert into public.invoice_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = invoice_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'INV-' || v_year_month || lpad(v_seq::text, 4, '0');

  select vat_rate, wht_rate into v_vat_rate, v_wht_rate from public.business_settings where id = 1;
  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  if p_wht_applied then
    -- Same subtotal/discount figures post_invoice_journal_entry() will
    -- independently recompute for posting — reusing this function instead
    -- of a third, parallel formula keeps the WHT base guaranteed consistent
    -- with what actually gets posted as revenue, by construction.
    select * into v_posting from public.compute_invoice_posting_amounts(p_lines, p_invoice_discount, v_total);
    v_taxable_subtotal := v_posting.subtotal - v_posting.discount;
    v_wht_amount := round(v_taxable_subtotal * (v_wht_rate / 100), 2);
  end if;

  insert into public.invoices
    (id, branch_id, customer_id, customer_name, date, due_date, notes, invoice_discount, vat_rate, total, amount_paid, balance, wht_applied, wht_rate, wht_amount)
  values
    (v_id, p_branch_id, p_customer_id, p_customer_name, p_date, p_due_date, p_notes, p_invoice_discount, v_vat_rate, v_total, 0, v_total, p_wht_applied, case when p_wht_applied then v_wht_rate else null end, v_wht_amount)
  returning * into v_invoice;

  insert into public.invoice_lines (invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select
    v_id,
    nullif(line->>'product_id', '')::uuid,
    line->>'name',
    line->>'unit',
    (line->>'quantity')::numeric,
    (line->>'unit_price')::numeric,
    coalesce((line->>'discount')::numeric, 0),
    coalesce((line->>'vat')::boolean, true),
    (ord - 1)::integer
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  perform public.post_invoice_journal_entry(v_id);

  if v_wht_amount > 0 then
    perform public.record_invoice_payment(
      v_id, v_wht_amount, 'WHT Credit', '',
      format('Withholding tax at %s%% on issue, held as a receivable pending remittance', v_wht_rate),
      now()
    );
    select * into v_invoice from public.invoices where id = v_id;
  end if;

  return v_invoice;
end;
$$;

-- ============================================================ update_invoice
--
-- update_invoice() deletes and re-inserts the full line set on every edit
-- (see the invoice_create_update_split migration), so editing an existing
-- invoice is, mechanically, "adding lines" again — the same guard applies,
-- otherwise a Manager editing an invoice could add a new line referencing
-- a since-unpriced product and bypass create_invoice()'s own protection
-- entirely.
create or replace function public.update_invoice(
  p_id text,
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb
)
returns public.invoices
language plpgsql
as $$
declare
  v_vat_rate numeric;
  v_total numeric;
  v_invoice public.invoices;
  v_unpriced_name text;
begin
  perform public.require_writable_role();

  select p.name into v_unpriced_name
  from jsonb_array_elements(p_lines) as l
  join public.products p on p.id = nullif(l.value->>'product_id', '')::uuid
  where p.price is null
  limit 1;

  if v_unpriced_name is not null then
    raise exception 'Product "%" has no selling price set and cannot be invoiced', v_unpriced_name;
  end if;

  select vat_rate into v_vat_rate from public.invoices where id = p_id for update;
  if not found then
    raise exception 'Invoice % not found', p_id;
  end if;

  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  update public.invoices set
    branch_id = p_branch_id,
    customer_id = p_customer_id,
    customer_name = p_customer_name,
    date = p_date,
    due_date = p_due_date,
    notes = p_notes,
    invoice_discount = p_invoice_discount,
    total = v_total,
    balance = greatest(v_total - amount_paid, 0)
  where id = p_id
  returning * into v_invoice;

  delete from public.invoice_lines where invoice_id = p_id;

  insert into public.invoice_lines (invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select
    p_id,
    nullif(line->>'product_id', '')::uuid,
    line->>'name',
    line->>'unit',
    (line->>'quantity')::numeric,
    (line->>'unit_price')::numeric,
    coalesce((line->>'discount')::numeric, 0),
    coalesce((line->>'vat')::boolean, true),
    (ord - 1)::integer
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_invoice;
end;
$$;
