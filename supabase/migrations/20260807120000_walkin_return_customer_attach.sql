-- Follow-up to the store-credit-and-return-fixes migration: that migration
-- correctly rejected a Store-credit return against a Walk-in sale (no
-- customer_id to credit) but gave staff no way to actually complete one —
-- a real counter scenario, since a customer who bought as a Walk-in can
-- still come back for a return and only be identified at that moment.
--
-- sale_returns.customer_id is new: the customer a Store-credit return
-- attaches (selected or created inline on the return screen) when the
-- original sale had none. Null for every other case — an already-attached
-- sale (v_sale.customer_id is not null) still credits that customer
-- directly and never touches this column, and no other resolution needs a
-- customer at all. This is deliberately a return-level fact, not a rewrite
-- of sales.customer_id: the original sale really was a Walk-in sale, and
-- changing that after the fact would misrepresent it.
alter table public.sale_returns
  add column customer_id uuid references public.customers(id);

-- Old 9-parameter overload (p_payment_method added, no p_customer_id yet)
-- must be dropped explicitly first — see the create_sale_return() comment
-- in the prior migration for why CREATE OR REPLACE alone can't do this.
drop function if exists public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text, text);

create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text, p_payment_method text default null,
  p_customer_id uuid default null
) returns public.sale_returns language plpgsql as $$
declare
  v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products;
  v_prior integer; v_difference numeric; v_return public.sale_returns; v_refund_amount numeric;
  v_credit_customer_id uuid;
begin
  perform public.require_writable_role();

  if p_resolution = 'Cash refund' and not public.has_role(array['Manager']) then
    raise exception 'A cash refund requires a Manager — store credit does not';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update; if not found then raise exception 'Sale % not found', p_sale_id; end if;

  v_credit_customer_id := coalesce(v_sale.customer_id, p_customer_id);
  if p_resolution = 'Store credit' then
    if v_credit_customer_id is null then
      raise exception 'Store credit requires a customer — select or add one for this return';
    end if;
    if v_sale.customer_id is null then
      -- Not on the original (Walk-in) sale: lock it now, same discipline as
      -- create_sale()'s own customer lock, and confirm it's real before the
      -- return is allowed to reference it — a plain UPDATE later would
      -- otherwise silently match zero rows for a bad id.
      perform 1 from public.customers where id = p_customer_id for update;
      if not found then raise exception 'Customer % not found', p_customer_id; end if;
    end if;
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

  insert into public.sale_returns(sale_id, branch_id, returned_sale_line_id, returned_product_id, returned_name, returned_unit, returned_quantity, returned_unit_price, replacement_product_id, replacement_name, replacement_unit, replacement_quantity, replacement_unit_price, difference, resolution, approval_state, reason, payment_method, customer_id)
  values(p_sale_id, v_sale.branch_id, v_line.id, v_line.product_id, v_line.name, v_line.unit, p_returned_quantity, v_line.unit_price, p_replacement_product_id, v_replacement.name, v_replacement.unit, p_replacement_quantity, v_replacement.price, v_difference, p_resolution, p_approval_state, coalesce(p_reason, ''), case when p_resolution = 'Top-up collected' then p_payment_method else null end, case when p_resolution = 'Store credit' and v_sale.customer_id is null then p_customer_id else null end)
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
      update public.customers set store_credit_balance = store_credit_balance + v_refund_amount where id = v_credit_customer_id;
    end if;
  end if;

  perform public.post_sale_return_journal_entry(v_return.id);
  return v_return;
end; $$;

grant execute on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text, text, uuid) to authenticated;
