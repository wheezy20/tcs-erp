-- Fix cash overpayment: a POS sale where the customer tenders more cash
-- than the total (change due) currently fails outright and rolls back.
--
-- create_sale() deliberately allows cash to exceed the total (its own
-- validation only rejects underpayment and *non-cash* overpayment — "only
-- cash may exceed the total") and stores the full tendered amount in
-- sale_payments.amount. But post_sale_journal_entry() then debits the
-- settlement account by sum(sale_payments.amount) — the full tender —
-- while the credit side (revenue / VAT / inventory) is anchored to
-- sale.total. The entry is unbalanced by exactly the change amount, and
-- _post_journal_entry_rows()'s balance pre-check raises, rolling back the
-- whole transaction. Reproduced live: a GHS 184 sale with GHS 200 cash
-- tendered -> "debits 316.00 do not equal credits 300.00", no sale
-- created. Broken since Session 14 (Auto-Posting); every session's
-- verification used exact payments, so the overpay path was never
-- exercised.
--
-- There is no bad historical data to migrate — overpay sales never got
-- created, they rolled back.
--
-- ================================================================ fix 1:
-- post_sale_journal_entry() — cap the cash debit at the cash actually kept
--
-- The payment debit lines must sum to sale.total, not to the amount
-- tendered. Cash is the only method that can overpay, so only the Cash
-- line needs adjusting: its debit is (cash tendered - change), which
-- algebraically equals (sale.total - the non-cash legs) and is always
-- >= 0 (create_sale() guarantees non_cash <= total). The change handed
-- back never entered the business's cash position, so the ledger
-- correctly records only what stayed in the drawer.
--
-- ================================================================ fix 2:
-- compute_day_totals() — pos_cash_sales must net out change too
--
-- Same root cause: the cash-by-method sum reads raw sale_payments.amount
-- (the tender). End of Day's expected_cash = opening + cash_sales - ...,
-- so on any overpaid sale it over-expects the drawer by the change paid
-- out — the same class of gap the mid-day cash-deposits fix
-- (20260831090000) just closed. pos_cash_sales (and therefore the
-- combined cash_sales, and therefore close_day()'s expected_cash, with no
-- change to close_day() itself — exactly as the deposits fix worked) now
-- subtracts the day's total cash change.

create or replace function public.post_sale_journal_entry(p_sale_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_sale public.sales;
  v_lines_json jsonb;
  v_totals record;
  v_cogs numeric;
  v_cost_incomplete boolean;
  v_lines jsonb := '[]'::jsonb;
  v_payment record;
  v_change numeric;
  v_debit numeric;
begin
  select * into v_sale from public.sales where id = p_sale_id;
  if not found then
    raise exception 'Sale % not found', p_sale_id;
  end if;

  select jsonb_agg(jsonb_build_object(
    'quantity', quantity, 'unit_price', unit_price,
    'discount_mode', discount_mode, 'discount_value', discount_value
  ))
  into v_lines_json
  from public.sale_lines where sale_id = p_sale_id;

  select * into v_totals from public.compute_sale_posting_amounts(
    v_lines_json, v_sale.sale_discount_mode, v_sale.sale_discount_value, v_sale.total
  );

  select coalesce(sum(sl.quantity * coalesce(p.cost, 0)), 0), bool_or(p.cost is null)
  into v_cogs, v_cost_incomplete
  from public.sale_lines sl join public.products p on p.id = sl.product_id
  where sl.sale_id = p_sale_id;

  -- Change handed back on an overpaid cash sale — always cash (create_sale()
  -- lets only cash exceed the total). Subtracted from the Cash debit line
  -- below so the payment debits sum to sale.total, not to the tender.
  select coalesce(sum(amount), 0) - v_sale.total
  into v_change
  from public.sale_payments where sale_id = p_sale_id;
  v_change := greatest(coalesce(v_change, 0), 0);

  for v_payment in
    select method, bank_account_id, sum(amount) as amount
    from public.sale_payments where sale_id = p_sale_id
    group by method, bank_account_id
  loop
    -- Cash has bank_account_id = null always (create_sale() only stores one
    -- for Card/Bank Transfer), so there is exactly one Cash group and the
    -- whole day's change applies cleanly to it.
    v_debit := v_payment.amount - case when v_payment.method = 'Cash' then v_change else 0 end;
    if v_debit > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'account_id', public.settlement_account(v_payment.method, v_payment.bank_account_id),
        'debit', v_debit, 'credit', 0, 'description', v_payment.method
      ));
    end if;
  end loop;

  if v_totals.discount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4200'),
      'debit', v_totals.discount, 'credit', 0, 'description', 'Sale discount'
    ));
  end if;

  if v_totals.subtotal > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4000'),
      'debit', 0, 'credit', v_totals.subtotal, 'description', 'Sale revenue'
    ));
  end if;

  if v_totals.vat > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('2100'),
      'debit', 0, 'credit', v_totals.vat, 'description', 'VAT collected'
    ));
  end if;

  if v_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('5000'),
      'debit', v_cogs, 'credit', 0,
      'description', case when v_cost_incomplete then 'Cost of goods sold (estimated — cost price missing for one or more items)' else 'Cost of goods sold' end
    ));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('1200'),
      'debit', 0, 'credit', v_cogs, 'description', 'Inventory'
    ));
  end if;

  if jsonb_array_length(v_lines) < 2 then
    return null;
  end if;

  return public._post_journal_entry_rows(
    v_sale.branch_id, v_sale.sold_at::date, 'POS sale ' || p_sale_id, p_sale_id, v_lines, 'sales', p_sale_id,
    coalesce(v_cost_incomplete, false)
  );
end;
$$;

-- compute_day_totals(): full body carried verbatim from
-- 20260831090000_end_of_day_cash_deposits.sql (the current definition),
-- with one addition — v_pos_cash_change, netted out of v_pos_cash_sales
-- before v_cash_sales is composed. Same signature and return type, so
-- CREATE OR REPLACE preserves the existing grants; re-granted below anyway
-- for parity with the prior migration.
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
  -- reading real rows for one day instead of client-submitted JSON —
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
      v_discount := case when v_line.discount_mode = 'percent'
        then v_gross * v_line.discount_value / 100
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

  -- POS sales by payment method — scoped by each payment's own paid_at.
  select
    coalesce(sum(amount) filter (where method = 'Cash'), 0),
    coalesce(sum(amount) filter (where method = 'Mobile Money'), 0),
    coalesce(sum(amount) filter (where method = 'Card'), 0),
    coalesce(sum(amount) filter (where method = 'Bank Transfer'), 0)
  into v_pos_cash_sales, v_mobile_money_sales, v_card_sales, v_bank_transfer_sales
  from public.sale_payments
  where branch_id = p_branch_id and paid_at::date = p_business_date;

  -- Change handed back on overpaid cash sales — always cash (create_sale()
  -- lets only cash exceed the total). The cash sum above counts the full
  -- amount tendered; net out the change so pos_cash_sales reflects only
  -- what actually stayed in the drawer, and expected_cash (which reads
  -- cash_sales) stops over-expecting the till. Scoped by the sale's own
  -- sold_at::date — the same scope the day's sales loop above uses; for
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

  -- Invoice payments by payment method — same paid_at scoping. Store Credit
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

  -- Cash refunds — money actually paid out, scoped by returned_at, never
  -- the original sale's sold_at. greatest(-difference, 0) is the cash
  -- outflow whether it's a plain refund (no replacement, difference =
  -- -returned_value) or an undervalue exchange (difference < 0); Store
  -- credit/Top-up/Even exchange never pay out cash, so only
  -- resolution = 'Cash refund' counts here.
  select coalesce(sum(greatest(-difference, 0)), 0)
  into v_cash_refunds
  from public.sale_returns
  where branch_id = p_branch_id and returned_at::date = p_business_date and resolution = 'Cash refund';

  -- Cash expenses — scoped by the expense's own business date, not
  -- recorded_at's insert-time metadata.
  select coalesce(sum(amount), 0)
  into v_cash_expenses
  from public.expenses
  where branch_id = p_branch_id and date = p_business_date and method = 'Cash';

  -- Cash deposits — drawer cash physically banked during the day, scoped
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
