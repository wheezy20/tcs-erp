-- POS (Phase 1.5, Session 5).
-- Sales are immutable receipts: create_sale() owns receipt numbers, VAT and
-- totals, and never accepts an id or total from the client.  Stock writes use
-- the same SELECT ... FOR UPDATE + product update + stock-movement insert
-- transaction shape as adjust_product_stock() from Session 1.

create table public.sale_number_counters (
  year_month text primary key,
  last_number integer not null default 0 check (last_number >= 0)
);

create table public.sales (
  id text primary key,
  branch_id uuid not null references public.branches(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete restrict,
  customer_name text not null,
  sold_at timestamptz not null default now(),
  cashier text not null default 'System',
  sale_discount_mode text not null default 'amount' check (sale_discount_mode in ('amount', 'percent')),
  sale_discount_value numeric(12, 2) not null default 0 check (sale_discount_value >= 0),
  vat_mode text not null default 'per-item' check (vat_mode in ('per-item', 'all', 'none')),
  vat_rate numeric(5, 2) not null check (vat_rate >= 0),
  total numeric(12, 2) not null check (total >= 0),
  created_at timestamptz not null default now()
);
create index sales_branch_sold_at_idx on public.sales(branch_id, sold_at desc);
create index sales_customer_id_idx on public.sales(customer_id);

create table public.sale_lines (
  id uuid primary key default gen_random_uuid(),
  sale_id text not null references public.sales(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  name text not null,
  unit text not null,
  category text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12, 2) not null check (unit_price >= 0),
  discount_mode text not null default 'amount' check (discount_mode in ('amount', 'percent')),
  discount_value numeric(12, 2) not null default 0 check (discount_value >= 0),
  vat boolean not null default true,
  position integer not null default 0
);
create index sale_lines_sale_id_idx on public.sale_lines(sale_id, position);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id text not null references public.sales(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  method text not null check (method in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer')),
  amount numeric(12, 2) not null check (amount > 0),
  reference text not null default '',
  paid_at timestamptz not null default now()
);
create index sale_payments_sale_id_idx on public.sale_payments(sale_id);

create table public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  sale_id text not null references public.sales(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  returned_sale_line_id uuid not null references public.sale_lines(id) on delete restrict,
  returned_product_id uuid not null references public.products(id) on delete restrict,
  returned_name text not null,
  returned_unit text not null,
  returned_quantity integer not null check (returned_quantity > 0),
  returned_unit_price numeric(12, 2) not null check (returned_unit_price >= 0),
  replacement_product_id uuid references public.products(id) on delete restrict,
  replacement_name text,
  replacement_unit text,
  replacement_quantity integer check (replacement_quantity > 0),
  replacement_unit_price numeric(12, 2) check (replacement_unit_price >= 0),
  difference numeric(12, 2) not null,
  resolution text not null check (resolution in ('Top-up collected', 'Cash refund', 'Store credit', 'Even exchange')),
  approval_state text not null check (approval_state in ('Not required', 'Pending manager approval')),
  reason text not null default '',
  returned_at timestamptz not null default now(),
  check ((replacement_product_id is null) = (replacement_name is null)),
  check ((replacement_product_id is null) = (replacement_unit is null)),
  check ((replacement_product_id is null) = (replacement_quantity is null)),
  check ((replacement_product_id is null) = (replacement_unit_price is null))
);
create index sale_returns_sale_id_idx on public.sale_returns(sale_id, returned_at desc);

-- Mirrors posTotals(): per-line discounts are capped at each line gross,
-- sale discount is capped at subtotal, and the remaining sale discount is
-- prorated before VAT is calculated. VAT rate comes from business_settings.
create or replace function public.compute_sale_total(p_lines jsonb, p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text, p_vat_rate numeric)
returns numeric language plpgsql as $$
declare v_line jsonb; v_gross numeric; v_discount numeric; v_net numeric; v_subtotal numeric := 0; v_taxable numeric := 0; v_sale_discount numeric; v_net_total numeric; v_ratio numeric; v_vat numeric;
begin
  if jsonb_array_length(p_lines) = 0 then raise exception 'A sale needs at least one line'; end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if coalesce((v_line->>'quantity')::integer, 0) <= 0 then raise exception 'Sale quantities must be positive'; end if;
    v_gross := (v_line->>'quantity')::numeric * (v_line->>'unit_price')::numeric;
    v_discount := case when coalesce(v_line->>'discount_mode', 'amount') = 'percent'
      then v_gross * coalesce((v_line->>'discount_value')::numeric, 0) / 100
      else coalesce((v_line->>'discount_value')::numeric, 0) end;
    v_net := greatest(v_gross - greatest(v_discount, 0), 0);
    v_subtotal := v_subtotal + v_net;
    if p_vat_mode = 'all' or (p_vat_mode = 'per-item' and coalesce((v_line->>'vat')::boolean, true)) then v_taxable := v_taxable + v_net; end if;
  end loop;
  v_sale_discount := case when p_sale_discount_mode = 'percent' then v_subtotal * greatest(p_sale_discount_value, 0) / 100 else greatest(p_sale_discount_value, 0) end;
  v_sale_discount := least(v_sale_discount, v_subtotal);
  v_net_total := v_subtotal - v_sale_discount;
  v_ratio := case when v_subtotal > 0 then v_net_total / v_subtotal else 0 end;
  v_vat := round(v_taxable * v_ratio * (p_vat_rate / 100), 2);
  return round(v_net_total + v_vat, 2);
end; $$;

create or replace function public.create_sale(
  p_branch_id uuid, p_customer_id uuid, p_customer_name text, p_cashier text,
  p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text,
  p_lines jsonb, p_payments jsonb
) returns public.sales language plpgsql as $$
declare v_year_month text := to_char(now(), 'YYMM'); v_seq integer; v_id text; v_rate numeric; v_total numeric; v_paid numeric; v_cash numeric; v_non_cash numeric; v_sale public.sales; v_line jsonb; v_product public.products; v_payment jsonb;
begin
  if p_sale_discount_mode not in ('amount', 'percent') or p_vat_mode not in ('per-item', 'all', 'none') then raise exception 'Invalid discount or VAT mode'; end if;
  select vat_rate into v_rate from public.business_settings where id = 1;
  v_total := public.compute_sale_total(p_lines, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate);
  select coalesce(sum((value->>'amount')::numeric), 0), coalesce(sum(case when value->>'method' = 'Cash' then (value->>'amount')::numeric else 0 end), 0), coalesce(sum(case when value->>'method' <> 'Cash' then (value->>'amount')::numeric else 0 end), 0) into v_paid, v_cash, v_non_cash from jsonb_array_elements(p_payments);
  if jsonb_array_length(p_payments) = 0 or v_paid < v_total - .01 or v_non_cash > v_total + .01 then raise exception 'Payments must cover the sale; only cash may exceed the total'; end if;
  for v_payment in select value from jsonb_array_elements(p_payments) loop
    if (v_payment->>'method') not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer') or coalesce((v_payment->>'amount')::numeric, 0) <= 0 then raise exception 'Invalid POS payment'; end if;
  end loop;
  -- Lock each product in stable UUID order before deducting it. The check and
  -- update happen while those row locks are held, so concurrent tills cannot oversell.
  for v_line in select value from jsonb_array_elements(p_lines) order by (value->>'product_id')::uuid loop
    select * into v_product from public.products where id = (v_line->>'product_id')::uuid and branch_id = p_branch_id for update;
    if not found then raise exception 'Product % is not available at this branch', v_line->>'product_id'; end if;
    if v_product.stock < (v_line->>'quantity')::integer then raise exception 'Insufficient stock for %', v_product.name; end if;
  end loop;
  insert into public.sale_number_counters(year_month, last_number) values(v_year_month, 1) on conflict(year_month) do update set last_number = sale_number_counters.last_number + 1 returning last_number into v_seq;
  v_id := 'POS-' || v_year_month || lpad(v_seq::text, 4, '0');
  insert into public.sales(id, branch_id, customer_id, customer_name, cashier, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total) values(v_id, p_branch_id, p_customer_id, p_customer_name, p_cashier, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate, v_total) returning * into v_sale;
  insert into public.sale_lines(sale_id, product_id, name, unit, category, quantity, unit_price, discount_mode, discount_value, vat, position)
  select v_id, (line->>'product_id')::uuid, line->>'name', line->>'unit', line->>'category', (line->>'quantity')::integer, (line->>'unit_price')::numeric, coalesce(line->>'discount_mode', 'amount'), coalesce((line->>'discount_value')::numeric, 0), coalesce((line->>'vat')::boolean, true), ord - 1 from jsonb_array_elements(p_lines) with ordinality as t(line, ord);
  for v_line in select value from jsonb_array_elements(p_lines) loop
    update public.products set stock = stock - (v_line->>'quantity')::integer where id = (v_line->>'product_id')::uuid returning * into v_product;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason, performed_by) values(v_product.id, p_branch_id, 'Sale', -(v_line->>'quantity')::integer, v_product.stock, v_id, p_cashier);
  end loop;
  insert into public.sale_payments(sale_id, branch_id, method, amount, reference) select v_id, p_branch_id, payment->>'method', (payment->>'amount')::numeric, coalesce(payment->>'reference', '') from jsonb_array_elements(p_payments) payment;
  return v_sale;
end; $$;

create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text
) returns public.sale_returns language plpgsql as $$
declare v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products; v_prior integer; v_difference numeric; v_return public.sale_returns;
begin
  select * into v_sale from public.sales where id = p_sale_id for update; if not found then raise exception 'Sale % not found', p_sale_id; end if;
  select * into v_line from public.sale_lines where id = p_returned_sale_line_id and sale_id = p_sale_id for update; if not found then raise exception 'Sale line does not belong to this sale'; end if;
  select coalesce(sum(returned_quantity), 0) into v_prior from public.sale_returns where returned_sale_line_id = p_returned_sale_line_id;
  if p_returned_quantity <= 0 or p_returned_quantity + v_prior > v_line.quantity then raise exception 'Return quantity exceeds quantity sold'; end if;
  -- Lock both affected product rows in UUID order. This is the same
  -- check-then-adjust pattern as create_sale()/adjust_product_stock(), with a
  -- stable lock order so opposing exchanges cannot deadlock each other.
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
  insert into public.sale_returns(sale_id, branch_id, returned_sale_line_id, returned_product_id, returned_name, returned_unit, returned_quantity, returned_unit_price, replacement_product_id, replacement_name, replacement_unit, replacement_quantity, replacement_unit_price, difference, resolution, approval_state, reason)
  values(p_sale_id, v_sale.branch_id, v_line.id, v_line.product_id, v_line.name, v_line.unit, p_returned_quantity, v_line.unit_price, p_replacement_product_id, v_replacement.name, v_replacement.unit, p_replacement_quantity, v_replacement.price, v_difference, p_resolution, p_approval_state, coalesce(p_reason, '')) returning * into v_return;
  update public.products set stock = stock + p_returned_quantity where id = v_returned.id returning * into v_returned;
  insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason, performed_by) values(v_returned.id, v_sale.branch_id, 'Return', p_returned_quantity, v_returned.stock, v_return.id::text, 'System');
  if p_replacement_product_id is not null then
    update public.products set stock = stock - p_replacement_quantity where id = v_replacement.id returning * into v_replacement;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason, performed_by) values(v_replacement.id, v_sale.branch_id, 'Sale', -p_replacement_quantity, v_replacement.stock, v_return.id::text || ' replacement', 'System');
  end if;
  return v_return;
end; $$;

grant select, insert, update on public.sale_number_counters to anon, authenticated;
grant select, insert, update, delete on public.sales, public.sale_lines, public.sale_payments, public.sale_returns to anon, authenticated;
grant execute on function public.compute_sale_total(jsonb, text, numeric, text, numeric) to anon, authenticated;
grant execute on function public.create_sale(uuid, uuid, text, text, text, numeric, text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text) to anon, authenticated;
