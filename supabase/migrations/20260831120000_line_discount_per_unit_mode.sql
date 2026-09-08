-- Line-item discount: add a third mode, 'amount_per_unit'.
--
-- 'amount'          — a flat GHS figure off the whole line, regardless of
--                     quantity. UNCHANGED. Every historical sale_lines row
--                     with this mode keeps its exact original meaning; no
--                     data is migrated or reinterpreted.
-- 'amount_per_unit' — NEW. The typed figure is multiplied by the line
--                     quantity, so the discount scales as quantity changes.
-- 'percent'         — UNCHANGED.
--
-- The clamp is the one already in place for the other two modes: the
-- per-line discount can never exceed that line's gross (quantity ×
-- unit_price) and can never go negative. Nothing about that changes here.
--
-- Three functions carry the per-line discount arithmetic and each gets the
-- same one extra branch, matching the existing shape exactly:
--   * compute_sale_total()           — the checkout total (create_sale)
--   * compute_sale_posting_amounts() — the auto-posted journal entry split
--   * compute_day_totals()           — End of Day's per-line discount/VAT
--                                      re-derivation from persisted rows
-- The investigation that prompted this named the first two plus the cart;
-- compute_day_totals() carries the identical case and had to be updated too
-- or an amount_per_unit sale would understate its discount (and overstate
-- cash_sales / expected_cash / VAT) for that day's reconciliation.
--
-- Sale-level (whole-sale) discount stays 'amount' | 'percent' only —
-- 'amount_per_unit' has no meaning without a single line quantity, the
-- sale-level UI selector doesn't offer it, and create_sale() rejects any
-- other value for p_sale_discount_mode. So only sale_lines' CHECK widens;
-- sales.sale_discount_mode and held_sales.sale_discount_mode are left alone.

alter table public.sale_lines drop constraint if exists sale_lines_discount_mode_check;
alter table public.sale_lines add constraint sale_lines_discount_mode_check
  check (discount_mode in ('amount', 'percent', 'amount_per_unit'));

-- ---------------------------------------------------------------------------
-- compute_sale_total() — body carried verbatim from 20260802110000_pos_schema
-- (its only prior definition), with the v_discount CASE gaining one branch.
-- Same signature, so CREATE OR REPLACE keeps the existing grants; re-granted
-- below for parity with that migration.
-- ---------------------------------------------------------------------------
create or replace function public.compute_sale_total(p_lines jsonb, p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text, p_vat_rate numeric)
returns numeric language plpgsql as $$
declare v_line jsonb; v_gross numeric; v_discount numeric; v_net numeric; v_subtotal numeric := 0; v_taxable numeric := 0; v_sale_discount numeric; v_net_total numeric; v_ratio numeric; v_vat numeric;
begin
  if jsonb_array_length(p_lines) = 0 then raise exception 'A sale needs at least one line'; end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if coalesce((v_line->>'quantity')::integer, 0) <= 0 then raise exception 'Sale quantities must be positive'; end if;
    v_gross := (v_line->>'quantity')::numeric * (v_line->>'unit_price')::numeric;
    v_discount := case
      when coalesce(v_line->>'discount_mode', 'amount') = 'percent'
        then v_gross * coalesce((v_line->>'discount_value')::numeric, 0) / 100
      when coalesce(v_line->>'discount_mode', 'amount') = 'amount_per_unit'
        then coalesce((v_line->>'discount_value')::numeric, 0) * (v_line->>'quantity')::numeric
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

grant execute on function public.compute_sale_total(jsonb, text, numeric, text, numeric) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- compute_sale_posting_amounts() — body carried verbatim from
-- 20260807100000_auto_posting_integration (its only prior definition), with
-- the v_line_discount CASE gaining the same branch.
-- ---------------------------------------------------------------------------
create or replace function public.compute_sale_posting_amounts(
  p_lines jsonb, p_sale_discount_mode text, p_sale_discount_value numeric, p_total numeric
)
returns table(subtotal numeric, discount numeric, vat numeric)
language plpgsql
as $$
declare
  v_line jsonb;
  v_gross numeric;
  v_line_discount numeric;
  v_net numeric;
  v_subtotal numeric := 0;
  v_sale_discount numeric;
  v_net_total numeric;
begin
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_gross := (v_line ->> 'quantity')::numeric * (v_line ->> 'unit_price')::numeric;
    v_line_discount := case
      when coalesce(v_line ->> 'discount_mode', 'amount') = 'percent'
        then v_gross * coalesce((v_line ->> 'discount_value')::numeric, 0) / 100
      when coalesce(v_line ->> 'discount_mode', 'amount') = 'amount_per_unit'
        then coalesce((v_line ->> 'discount_value')::numeric, 0) * (v_line ->> 'quantity')::numeric
      else coalesce((v_line ->> 'discount_value')::numeric, 0) end;
    v_net := greatest(v_gross - greatest(v_line_discount, 0), 0);
    v_subtotal := v_subtotal + v_net;
  end loop;

  v_sale_discount := case when p_sale_discount_mode = 'percent'
    then v_subtotal * greatest(p_sale_discount_value, 0) / 100
    else greatest(p_sale_discount_value, 0) end;
  v_sale_discount := least(v_sale_discount, v_subtotal);

  subtotal := round(v_subtotal, 2);
  discount := round(v_sale_discount, 2);
  v_net_total := subtotal - discount;
  vat := p_total - v_net_total;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- compute_day_totals() — body carried verbatim from
-- 20260831110000_fix_cash_overpayment_posting (the current definition), with
-- the per-line v_discount CASE gaining the same branch. Same signature and
-- return type, so CREATE OR REPLACE preserves grants; re-granted below for
-- parity with the prior migration.
-- ---------------------------------------------------------------------------
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

  -- Sales: per-line discount/VAT breakdown, a day-scoped SQL port of
  -- compute_sale_total()'s math (same per-line-discount-capped-at-gross,
  -- sale-discount-capped-at-subtotal, VAT-prorated-by-taxable-ratio shape)
  -- reading real rows for one day instead of client-submitted JSON --
  -- duplicated rather than shared with compute_sale_total() to avoid
  -- touching a function create_sale() depends on for every checkout.
  for v_sale in
    select id, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total
    from public.sales
    where branch_id = p_branch_id and sold_at::date = p_business_date
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

  -- POS sales by payment method -- scoped by each payment's own paid_at.
  select
    coalesce(sum(amount) filter (where method = 'Cash'), 0),
    coalesce(sum(amount) filter (where method = 'Mobile Money'), 0),
    coalesce(sum(amount) filter (where method = 'Card'), 0),
    coalesce(sum(amount) filter (where method = 'Bank Transfer'), 0)
  into v_pos_cash_sales, v_mobile_money_sales, v_card_sales, v_bank_transfer_sales
  from public.sale_payments
  where branch_id = p_branch_id and paid_at::date = p_business_date;

  -- Change handed back on overpaid cash sales -- always cash (create_sale()
  -- lets only cash exceed the total). The cash sum above counts the full
  -- amount tendered; net out the change so pos_cash_sales reflects only
  -- what actually stayed in the drawer, and expected_cash (which reads
  -- cash_sales) stops over-expecting the till. Scoped by the sale's own
  -- sold_at::date -- the same scope the day's sales loop above uses; for
  -- POS a payment's paid_at is the same instant as its sale's sold_at.
  select coalesce(sum(greatest(per_sale.paid - s.total, 0)), 0)
  into v_pos_cash_change
  from public.sales s
  join (
    select sale_id, sum(amount) as paid
    from public.sale_payments
    group by sale_id
  ) per_sale on per_sale.sale_id = s.id
  where s.branch_id = p_branch_id and s.sold_at::date = p_business_date;

  v_pos_cash_sales := v_pos_cash_sales - v_pos_cash_change;

  -- Invoice payments by payment method -- same paid_at scoping. Store Credit
  -- and WHT Credit are intentionally not selected at all: neither is real
  -- money received today (see migration header). Card isn't a valid
  -- invoice_payments method, so there's nothing to fold into card_sales.
  select
    coalesce(sum(amount) filter (where method = 'Cash'), 0),
    coalesce(sum(amount) filter (where method = 'Mobile Money'), 0),
    coalesce(sum(amount) filter (where method = 'Bank Transfer'), 0),
    coalesce(sum(amount) filter (where method = 'Cheque'), 0)
  into v_invoice_cash_sales, v_invoice_mobile_money, v_invoice_bank_transfer, v_invoice_cheque_sales
  from public.invoice_payments
  where branch_id = p_branch_id and paid_at::date = p_business_date;

  -- Mobile Money/Bank Transfer are blended (informational only, nothing
  -- downstream needs the POS/invoice split); Cash stays split into two
  -- visible line items, combined here into the one total everything else
  -- (expected_cash, the "Cash" row) already expects.
  v_mobile_money_sales := v_mobile_money_sales + v_invoice_mobile_money;
  v_bank_transfer_sales := v_bank_transfer_sales + v_invoice_bank_transfer;
  v_cash_sales := v_pos_cash_sales + v_invoice_cash_sales;

  -- Cash refunds -- money actually paid out, scoped by returned_at, never
  -- the original sale's sold_at. greatest(-difference, 0) is the cash
  -- outflow whether it's a plain refund (no replacement, difference =
  -- -returned_value) or an undervalue exchange (difference < 0); Store
  -- credit/Top-up/Even exchange never pay out cash, so only
  -- resolution = 'Cash refund' counts here.
  select coalesce(sum(greatest(-difference, 0)), 0)
  into v_cash_refunds
  from public.sale_returns
  where branch_id = p_branch_id and returned_at::date = p_business_date and resolution = 'Cash refund';

  -- Cash expenses -- scoped by the expense's own business date, not
  -- recorded_at's insert-time metadata.
  select coalesce(sum(amount), 0)
  into v_cash_expenses
  from public.expenses
  where branch_id = p_branch_id and date = p_business_date and method = 'Cash';

  -- Cash deposits -- drawer cash physically banked during the day, scoped
  -- by the deposit's own business date (bank_deposits.date), mirroring
  -- cash_expenses above. Only source = 'Cash': a Mobile Money deposit
  -- draws down the MoMo float, which End of Day never physically counts,
  -- so it must not reduce the expected till-drawer figure.
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
