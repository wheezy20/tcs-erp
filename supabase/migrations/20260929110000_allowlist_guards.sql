-- Admissions slice 1b-i: allowlist guards (docs/admissions/PORT-PLAN.md,
-- slice 1b; decisions D-1b-a and D-1b-b, 2026-09-29).
--
-- can_write() and require_writable_role() were denylists ("not Accountant or
-- Auditor", "not Auditor"), so any new staff.role value would silently get
-- store writes and pass the guard in 28 RPCs. They become allowlists with the
-- same result for the four existing roles. Store and business_settings reads
-- move from is_active_staff() to a new allowlist predicate, can_read_store().
-- No role is added here; that's slice 1b-ii. The regression proof is
-- supabase/role-matrix/20260929110000_allowlist_guards_regression.sql, which
-- gives byte-identical output on the schema before and after this file.
--
-- Signatures, volatility, security definer and search_path are unchanged on
-- every replaced function, so create or replace is enough (no drop needed)
-- and every policy that calls them is untouched.

-- ------------------------------------------------------------ write guards

-- Before: is_active_staff() and not has_role(['Accountant','Auditor']).
create or replace function public.can_write()
returns boolean
language sql
stable security definer
set search_path = public
as $$
  select public.has_role(array['Manager', 'Attendant']);
$$;

-- Before: require_staff(), then reject Auditor only. Auditor keeps its exact
-- message; any other role outside the list gets a role-neutral one.
create or replace function public.require_writable_role()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_staff();
  if not public.has_role(array['Manager', 'Attendant', 'Accountant']) then
    if public.has_role(array['Auditor']) then
      raise exception 'Auditor is read-only and cannot perform this action';
    end if;
    raise exception 'This action is not available to your role';
  end if;
end;
$$;

-- ------------------------------------------------------------ store reads

-- The four roles that read the store, sales and settings tables today.
create or replace function public.can_read_store()
returns boolean
language sql
stable security definer
set search_path = public
as $$
  select public.has_role(array['Manager', 'Attendant', 'Accountant', 'Auditor']);
$$;

revoke execute on function public.can_read_store() from public, anon;
grant execute on function public.can_read_store() to authenticated, service_role;

-- Every is_active_staff() select policy except branches (every staff role
-- reads it, D-1b-b) and staff (below).
alter policy business_settings_select on public.business_settings using (public.can_read_store());
alter policy customer_deposits_select on public.customer_deposits using (public.can_read_store());
alter policy customer_discounts_select on public.customer_discounts using (public.can_read_store());
alter policy customers_select on public.customers using (public.can_read_store());
alter policy day_closes_select on public.day_closes using (public.can_read_store());
alter policy deposit_number_counters_select on public.deposit_number_counters using (public.can_read_store());
alter policy held_sales_select on public.held_sales using (public.can_read_store());
alter policy invoice_lines_select on public.invoice_lines using (public.can_read_store());
alter policy invoice_number_counters_select on public.invoice_number_counters using (public.can_read_store());
alter policy invoice_payments_select on public.invoice_payments using (public.can_read_store());
alter policy invoices_select on public.invoices using (public.can_read_store());
alter policy manager_overrides_select on public.manager_overrides using (public.can_read_store());
alter policy pro_forma_invoice_lines_select on public.pro_forma_invoice_lines using (public.can_read_store());
alter policy pro_forma_invoice_number_counters_select on public.pro_forma_invoice_number_counters using (public.can_read_store());
alter policy pro_forma_invoices_select on public.pro_forma_invoices using (public.can_read_store());
alter policy products_select on public.products using (public.can_read_store());
alter policy sale_lines_select on public.sale_lines using (public.can_read_store());
alter policy sale_number_counters_select on public.sale_number_counters using (public.can_read_store());
alter policy sale_payments_select on public.sale_payments using (public.can_read_store());
alter policy sale_returns_select on public.sale_returns using (public.can_read_store());
alter policy sales_select on public.sales using (public.can_read_store());
alter policy stock_movements_select on public.stock_movements using (public.can_read_store());

-- staff: the four roles see everyone; any other active role sees only its own
-- row, which the app needs to resolve who is signed in (auth-store.ts). An
-- inactive member still sees nothing, as before.
alter policy staff_select on public.staff
  using (public.can_read_store() or (id = auth.uid() and public.is_active_staff()));

-- ------------------------------------------------------------ staff names

-- Names for display (note authors and the like) without read access to
-- staff. Every staff row, active or not, so a former member's name still
-- resolves. id and name only.
create or replace function public.list_staff_names()
returns table (id uuid, name text)
language plpgsql
stable security definer
set search_path = public
as $$
begin
  perform public.require_staff();
  return query select s.id, s.name from public.staff s order by s.name;
end;
$$;

revoke execute on function public.list_staff_names() from public, anon;
grant execute on function public.list_staff_names() to authenticated, service_role;

-- ------------------------------------------------------------ compute_day_totals

-- SECURITY DEFINER, so it bypasses sales RLS; it was guarded by
-- require_staff() alone. Body unchanged apart from the can_read_store() check.
create or replace function public.compute_day_totals(p_branch_id uuid, p_business_date date)
returns table (cash_sales numeric, mobile_money_sales numeric, card_sales numeric, bank_transfer_sales numeric, vat_collected numeric, discounts_given numeric, cash_refunds numeric, cash_expenses numeric, cash_deposits numeric, system_sales_total numeric, system_transaction_count integer, pos_cash_sales numeric, invoice_cash_sales numeric, invoice_cheque_sales numeric)
language plpgsql
stable security definer
set search_path = public
as $function$
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
  if not public.can_read_store() then
    raise exception 'This action is not available to your role';
  end if;

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
$function$;
