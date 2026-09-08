-- Cash refund / Store credit returns never reversed VAT at all —
-- post_sale_return_journal_entry()'s refund line was always the returned
-- line's pre-VAT amount (abs(least(difference, 0)), and difference itself
-- is computed from sale_lines.unit_price, a pre-VAT figure), with no VAT
-- counterpart posted anywhere. Confirmed live against production
-- (POS-26080001/JE-26080004) before this fix: a full refund of a taxable
-- GHS 220 line correctly reversed GHS 220 of revenue but left the GHS 44
-- of VAT originally collected on it sitting in 2100 VAT Payable forever,
-- overstating the business's real VAT liability by exactly what it
-- shouldn't have been holding.
--
-- Taxability has to mirror compute_sale_total()'s own per-line rule
-- exactly, not a simplified "was VAT on at all" check: a line is taxable
-- iff vat_mode = 'all' (every line, regardless of its own flag) or
-- vat_mode = 'per-item' and that specific line's own vat flag is true;
-- vat_mode = 'none' means never taxable regardless of the flag. The
-- Top-up branch below only checks vat_mode <> 'none' because a top-up has
-- no original line to inherit a flag from (it's new revenue on the
-- replacement item, not a reversal of something already sold) — that
-- simplification is correct for Top-up specifically and was deliberately
-- not copied here.
--
-- The reversal amount itself turns out to collapse to exactly the same
-- shape as the Top-up branch's formula (refund_amount * vat_rate / 100),
-- not by coincidence: sales.vat_rate is a single value for the whole sale
-- (not per line), so for a plain refund (no replacement) where
-- refund_amount already equals the returned line's full pre-VAT value,
-- this is the exact VAT that line originally charged, no proration
-- needed. For an undervalue exchange (a replacement chosen that's cheaper
-- than the returned item, still resolved as Cash refund/Store credit),
-- refund_amount is a fraction of the returned line's full value — scaling
-- the line's full VAT by that same fraction (returned_line_vat_full *
-- refund_amount / returned_line_value_full) algebraically reduces to
-- refund_amount * vat_rate / 100 as well, since vat_rate is the constant
-- being scaled either way. So one formula, gated by the real per-line
-- taxability check, is exact for both shapes — not an approximation.
--
-- Posted as its own line (debit 2100, credit the same target account the
-- principal refund already credits — 1000 for Cash, 2400 for Store
-- credit), not folded into the existing 4100 line, so the ledger reads
-- the VAT reversal as its own clearly-labeled fact rather than an
-- inflated revenue-reversal figure.
--
-- Audited all of production for the same gap before writing this fix
-- (every Cash refund/Store credit return with a non-zero refund amount,
-- cross-referenced against its journal entry's own 2100 activity): only
-- one such return exists in the whole database, POS-26080001's return
-- (JE-26080004) — the already-known, already-flagged test transaction.
-- No real customer return carries this gap, so no correcting entry is
-- needed for anything beyond that one already-discussed transaction.
create or replace function public.post_sale_return_journal_entry(p_return_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_return public.sale_returns;
  v_sale public.sales;
  v_line public.sale_lines;
  v_line_taxable boolean;
  v_returned_cost_raw numeric;
  v_replacement_cost_raw numeric;
  v_returned_cost numeric;
  v_replacement_cost numeric;
  v_net_cogs numeric;
  v_refund_amount numeric;
  v_refund_vat numeric := 0;
  v_topup_vat numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_target_account uuid;
  v_cost_incomplete boolean := false;
begin
  select * into v_return from public.sale_returns where id = p_return_id;
  if not found then
    raise exception 'Return % not found', p_return_id;
  end if;

  select * into v_sale from public.sales where id = v_return.sale_id;
  select * into v_line from public.sale_lines where id = v_return.returned_sale_line_id;

  v_line_taxable := v_sale.vat_mode = 'all'
    or (v_sale.vat_mode = 'per-item' and v_line.vat);

  select cost into v_returned_cost_raw
  from public.products where id = v_return.returned_product_id;
  if v_returned_cost_raw is null then
    v_cost_incomplete := true;
  end if;
  v_returned_cost := coalesce(v_returned_cost_raw, 0) * v_return.returned_quantity;

  v_replacement_cost := 0;
  if v_return.replacement_product_id is not null then
    select cost into v_replacement_cost_raw
    from public.products where id = v_return.replacement_product_id;
    if v_replacement_cost_raw is null then
      v_cost_incomplete := true;
    end if;
    v_replacement_cost := coalesce(v_replacement_cost_raw, 0) * v_return.replacement_quantity;
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

      if v_line_taxable then
        v_refund_vat := round(v_refund_amount * v_sale.vat_rate / 100, 2);
      end if;
      if v_refund_vat > 0 then
        v_lines := v_lines || jsonb_build_array(
          jsonb_build_object(
            'account_id', public.account_id_by_code('2100'),
            'debit', v_refund_vat, 'credit', 0, 'description', v_return.resolution || ' VAT reversal'
          ),
          jsonb_build_object(
            'account_id', v_target_account,
            'debit', 0, 'credit', v_refund_vat, 'description', v_return.resolution || ' VAT reversal'
          )
        );
      end if;
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
    p_return_id::text, v_lines, 'sale_returns', p_return_id::text, v_cost_incomplete
  );
end;
$$;
