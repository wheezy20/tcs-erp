-- End of Day: fold invoice_payments into compute_day_totals() (a same-day
-- follow-up, not a numbered session).
--
-- The gap: compute_day_totals() has, since Session 11, only ever read
-- public.sale_payments — a cash (or Mobile Money/Bank Transfer) payment
-- recorded against an INVOICE via record_invoice_payment() lands in
-- public.invoice_payments instead, a table this function never queried.
-- Concretely: a customer paying cash today against a WHT invoice (or any
-- invoice) was completely invisible to today's live preview, expected_cash,
-- and the frozen closing snapshot — money that's really in the till, with
-- nothing in End of Day accounting for it. Found by investigation, not by a
-- bug report; fixed here.
--
-- The fix folds invoice_payments in for every one of its payment methods,
-- not just Cash:
--   - Cash: kept as two separate, visible line items (pos_cash_sales,
--     invoice_cash_sales) rather than blended into one number — this is the
--     one figure a Manager physically counts and reconciles against, so
--     losing the ability to see "how much of today's cash came from the
--     till vs. from someone settling an invoice" would be a real loss of
--     information, the same "keep related-but-distinct money sources
--     visibly separate" reasoning already applied throughout this build
--     (e.g. journal-store.ts's sourceLabel(), financial-reports.ts's
--     Cash Flow by-source breakdown). cash_sales itself stays as the
--     existing column, now genuinely the combined total
--     (pos_cash_sales + invoice_cash_sales) — expected_cash and every other
--     consumer that already reads cash_sales picks up the fix for free,
--     with no call-site changes needed beyond storing the two new columns
--     alongside it.
--   - Mobile Money / Bank Transfer: blended directly into the existing
--     mobile_money_sales/bank_transfer_sales totals, not split. Neither
--     figure drives expected_cash or any reconciliation math — they're
--     informational totals in the "Sales by payment method" breakdown only
--     — so decomposing them the way cash needed to be would add a UI
--     distinction with no reconciliation payoff.
--   - Cheque: invoice_payments' one payment method with no POS/sale_payments
--     equivalent at all. Added as a new, invoice-only informational column
--     (invoice_cheque_sales) rather than silently dropped — "for every
--     payment method, not just cash" means this one too. Like Mobile Money/
--     Bank Transfer, it's informational only: a cheque isn't physical till
--     cash, so it was never going to affect expected_cash.
--   - Store Credit and WHT Credit are deliberately excluded from every
--     figure here — neither is real money changing hands today (Store
--     Credit draws down a balance accrued from an earlier return, WHT
--     Credit is a tax-withheld receivable, not cash or a bank instrument).
--     This mirrors sale_payments' own Store Credit rows, already silently
--     excluded by compute_day_totals()'s original method filter.
--
-- Deliberately NOT folded in: vat_collected, discounts_given,
-- system_sales_total, system_transaction_count all stay POS-only, exactly
-- as before. The reported gap was specifically about payments/cash — real
-- money that either does or doesn't show up in a till count — not about
-- invoice-level VAT/discount bookkeeping (already covered by the ledger,
-- Session 13+) or the manual tally cross-check (a Manager's own written
-- receipt log, which in this business is a POS-till log, not an invoice
-- log). Expanding those would be a materially different feature than the
-- one gap actually found; flagged here as a deliberate scope boundary
-- rather than silently left alone.
--
-- This does NOT retroactively touch any already-closed day — day_closes'
-- own RLS (closed_at is null required to update) already makes that
-- structurally impossible, the same snapshot-once-frozen principle as
-- every other closed day. Only the live preview (a fresh compute_day_totals
-- call every time) and any day closed from now on pick up the fix.

alter table public.day_closes
  add column pos_cash_sales numeric(12, 2),
  add column invoice_cash_sales numeric(12, 2),
  add column invoice_cheque_sales numeric(12, 2);

-- Adding output columns changes compute_day_totals()'s return type, which
-- CREATE OR REPLACE FUNCTION cannot do — drop first, the same discipline
-- this build's own signature-change precedent (create_sale_return(), etc.)
-- already established for parameter changes, here applying to the return
-- side instead.
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

  return query select
    v_cash_sales, v_mobile_money_sales, v_card_sales, v_bank_transfer_sales,
    v_vat_collected, v_discounts_given, v_cash_refunds, v_cash_expenses,
    v_system_sales_total, v_system_transaction_count,
    v_pos_cash_sales, v_invoice_cash_sales, v_invoice_cheque_sales;
end;
$$;

grant execute on function public.compute_day_totals(uuid, date) to authenticated;

-- close_day() itself is untouched in structure — same three checks, same
-- expected_cash formula (v_totals.cash_sales is already the combined
-- total now, so this line needed zero changes to pick up the fix), same
-- post_day_close_journal_entry()/notify_overdue_invoices()/
-- notify_daily_sales_summary() calls at the end. Full body copied verbatim
-- from stock_oversight_and_notifications.sql's version (the latest prior
-- definition — verified no migration after it redefined close_day()) with
-- only the three new columns added to the UPDATE's SET clause.
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

  v_expected_cash := v_open.opening_float + v_totals.cash_sales - v_totals.cash_refunds - v_totals.cash_expenses;
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
