-- End of Day: fold mid-day cash deposits into the expected-cash figure.
--
-- The gap (confirmed live before this fix): compute_day_totals() never
-- queried bank_deposits, so close_day()'s expected-cash formula —
--   opening_float + cash_sales - cash_refunds - cash_expenses
-- — kept expecting the full day's uncollected cash to still be in the
-- drawer even after some of it had physically been banked. A GHS 500
-- mid-day cash deposit against a real drawer produced expected_cash 500
-- too high, a phantom cash_variance of -500, and a
-- post_day_close_journal_entry() posting of Dr 5220 Cash Over/Short /
-- Cr 1000 Cash on Hand for 500 — on top of the deposit's own already-
-- correct Dr <bank sub-account> / Cr 1000 for the same 500. Net: 1000
-- credited twice for the same cash, 5220 overstated by the deposit
-- amount, every time cash was banked before close.
--
-- The fix is confined to the *expectation*, not the posting: once
-- expected_cash subtracts the day's cash deposits, the variance for a
-- clean day lands at 0 and post_day_close_journal_entry() posts nothing
-- (or only a genuine over/short). The deposit's own journal entry already
-- moved the cash out of 1000 — no poster change is needed or wanted.
--
-- Only source = 'Cash' deposits count. expected_cash is a till-drawer
-- figure; a Mobile Money deposit draws down the MoMo float, which End of
-- Day never counts or reconciles physically, so folding it in here would
-- be wrong. Scoped by bank_deposits.date (the deposit's own business
-- date), exactly mirroring how cash_expenses already scopes by
-- expenses.date rather than an insert-time timestamp.
--
-- day_closes.cash_deposits is the frozen snapshot, nullable and set only
-- at close time, the same shape as cash_expenses / pos_cash_sales /
-- invoice_cash_sales (it is deliberately NOT added to the day_closes_check
-- two-phase constraint, which only governs counted_cash / manual tally /
-- closed_by — the same as every other snapshot column).
--
-- Already-closed days are untouched: day_closes' own RLS (closed_at is
-- null required to update) makes that structurally impossible, and a
-- backdated deposit against a closed day can never retroactively move its
-- frozen figures. Only the live preview (a fresh compute_day_totals call)
-- and any day closed from now on pick up the fix — the same
-- snapshot-once-frozen principle every other End of Day change has kept.

alter table public.day_closes
  add column cash_deposits numeric(12, 2);

-- Adding an output column changes compute_day_totals()'s return type,
-- which CREATE OR REPLACE FUNCTION cannot do — drop first, the same
-- discipline this build already used for this exact function in
-- 20260813090000_end_of_day_invoice_payments.sql.
drop function if exists public.compute_day_totals(uuid, date);

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

-- close_day(): unchanged in structure — full body copied verbatim from
-- 20260813090000_end_of_day_invoice_payments.sql, with exactly two
-- changes: `- v_totals.cash_deposits` added to the expected_cash formula,
-- and `cash_deposits = v_totals.cash_deposits` added to the frozen-
-- snapshot UPDATE. Signature is unchanged, so its EXECUTE grant carries
-- across this CREATE OR REPLACE.
create or replace function public.close_day(
  p_branch_id uuid,
  p_counted_cash numeric,
  p_manual_sales_total numeric,
  p_manual_transaction_count integer,
  p_notes text default ''
)
returns public.day_closes
language plpgsql
as $$
declare
  v_open public.day_closes;
  v_totals record;
  v_expected_cash numeric;
  v_cash_variance numeric;
  v_tally_sales_variance numeric;
  v_tally_count_variance integer;
  v_row public.day_closes;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can close the day';
  end if;
  if p_counted_cash < 0 then
    raise exception 'Counted cash cannot be negative';
  end if;
  if p_manual_sales_total < 0 or p_manual_transaction_count < 0 then
    raise exception 'Manual tally figures cannot be negative';
  end if;

  select * into v_open from public.day_closes
  where branch_id = p_branch_id and business_date = current_date;
  if not found then
    raise exception 'Confirm this morning''s opening float before closing the day';
  end if;
  if v_open.closed_at is not null then
    raise exception 'Today has already been closed';
  end if;

  select * into v_totals from public.compute_day_totals(p_branch_id, current_date);

  v_expected_cash := v_open.opening_float + v_totals.cash_sales - v_totals.cash_refunds - v_totals.cash_expenses - v_totals.cash_deposits;
  v_cash_variance := p_counted_cash - v_expected_cash;
  v_tally_sales_variance := p_manual_sales_total - v_totals.system_sales_total;
  v_tally_count_variance := p_manual_transaction_count - v_totals.system_transaction_count;

  update public.day_closes set
    cash_sales = v_totals.cash_sales,
    mobile_money_sales = v_totals.mobile_money_sales,
    card_sales = v_totals.card_sales,
    bank_transfer_sales = v_totals.bank_transfer_sales,
    vat_collected = v_totals.vat_collected,
    discounts_given = v_totals.discounts_given,
    cash_refunds = v_totals.cash_refunds,
    cash_expenses = v_totals.cash_expenses,
    cash_deposits = v_totals.cash_deposits,
    expected_cash = v_expected_cash,
    counted_cash = p_counted_cash,
    cash_variance = v_cash_variance,
    system_sales_total = v_totals.system_sales_total,
    system_transaction_count = v_totals.system_transaction_count,
    manual_sales_total = p_manual_sales_total,
    manual_transaction_count = p_manual_transaction_count,
    tally_sales_variance = v_tally_sales_variance,
    tally_count_variance = v_tally_count_variance,
    pos_cash_sales = v_totals.pos_cash_sales,
    invoice_cash_sales = v_totals.invoice_cash_sales,
    invoice_cheque_sales = v_totals.invoice_cheque_sales,
    notes = coalesce(p_notes, ''),
    closed_at = now()
  where id = v_open.id and closed_at is null
  returning * into v_row;
  if not found then
    raise exception 'Today has already been closed';
  end if;

  perform public.post_day_close_journal_entry(v_row.id);
  perform public.notify_overdue_invoices(p_branch_id, current_date);
  perform public.notify_daily_sales_summary(v_row.id);
  return v_row;
end;
$$;
