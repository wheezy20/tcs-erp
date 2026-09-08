-- Cost price becomes nullable: a product can be created with cost price
-- genuinely unknown, instead of being forced to a placeholder value (the
-- previous `not null default 0` made "unknown" and "confirmed free"
-- indistinguishable, which silently understated margin/valuation/COGS for
-- exactly the products a business is least sure about).
--
-- The `check (cost >= 0)` constraint is untouched — Postgres CHECK
-- constraints pass automatically when the value is null, so this doesn't
-- need to change to keep allowing null. The `default 0` is dropped too:
-- once a blank cost is a real, distinguishable state, defaulting a truly
-- unset field to 0 (a confident, contradictory claim: "this costs nothing")
-- would immediately erase the distinction this migration exists to create.
alter table public.products alter column cost drop not null;
alter table public.products alter column cost drop default;

-- The ledger side of this: every COGS-computing poster function below
-- already coalesces a (previously guaranteed non-null) cost to 0 for
-- defensive-but-then-unreachable reasons. Once cost is genuinely nullable,
-- that same coalesce silently understates COGS for any line whose product
-- has no recorded cost, with zero indication anywhere in the ledger that
-- the posted figure is incomplete. A journal entry still has to balance
-- (Session 13's deferred trigger enforces that structurally) and still has
-- to post — a sale can't be blocked from completing because a product's
-- cost hasn't been filled in yet, that's a real usability regression this
-- task never asked for — so COGS keeps posting as an estimate (missing
-- cost treated as 0, same as today), but the entry itself now carries a
-- real, queryable flag saying so, instead of an estimate silently passing
-- as fact.
alter table public.journal_entries
  add column cost_data_incomplete boolean not null default false;

comment on column public.journal_entries.cost_data_incomplete is
  'True when this entry''s COGS/inventory figure was computed against one or more products with no recorded cost price (treated as 0 for posting purposes) — the posted amount is a known underestimate, not a confirmed figure.';

-- _post_journal_entry_rows() gains one more parameter, threaded through
-- from every poster below. Every existing call site is updated in the same
-- migration (there's no legitimate reason for a caller to silently keep
-- omitting it — a bare parameter default would make "did this poster even
-- think about cost completeness" impossible to tell apart from "this
-- transaction type genuinely never touches COGS").
create or replace function public._post_journal_entry_rows(
  p_branch_id uuid,
  p_date date,
  p_description text,
  p_reference text,
  p_lines jsonb,
  p_source_table text,
  p_source_id text,
  p_cost_data_incomplete boolean default false
)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_year_month text := to_char(p_date, 'YYMM');
  v_seq integer;
  v_id text;
  v_row public.journal_entries;
  v_total_debit numeric;
  v_total_credit numeric;
begin
  select coalesce(sum((line ->> 'debit')::numeric), 0), coalesce(sum((line ->> 'credit')::numeric), 0)
  into v_total_debit, v_total_credit
  from jsonb_array_elements(p_lines) as line;

  if v_total_debit <> v_total_credit then
    raise exception 'Auto-posted entry for % % is not balanced: debits % do not equal credits %',
      p_source_table, p_source_id, v_total_debit, v_total_credit;
  end if;
  if v_total_debit = 0 then
    raise exception 'Auto-posted entry for % % has no amount', p_source_table, p_source_id;
  end if;

  insert into public.journal_entry_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = journal_entry_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'JE-' || v_year_month || lpad(v_seq::text, 4, '0');

  begin
    insert into public.journal_entries
      (id, branch_id, entry_date, description, reference, source_table, source_id, cost_data_incomplete)
    values (
      v_id, p_branch_id, p_date, p_description,
      nullif(trim(coalesce(p_reference, '')), ''),
      p_source_table, p_source_id, p_cost_data_incomplete
    )
    returning * into v_row;
  exception when unique_violation then
    raise exception '% % has already been posted to the ledger', p_source_table, p_source_id;
  end;

  insert into public.journal_lines (entry_id, position, account_id, debit, credit, description)
  select
    v_id,
    ord - 1,
    (line ->> 'account_id')::uuid,
    coalesce((line ->> 'debit')::numeric, 0),
    coalesce((line ->> 'credit')::numeric, 0),
    coalesce(line ->> 'description', '')
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_row;
end;
$$;

-- ============================================================== POS sale
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

  for v_payment in
    select method, sum(amount) as amount from public.sale_payments where sale_id = p_sale_id group by method
  loop
    if v_payment.amount > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'account_id', public.payment_method_account(v_payment.method),
        'debit', v_payment.amount, 'credit', 0, 'description', v_payment.method
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

-- ======================================================= invoice created
create or replace function public.post_invoice_journal_entry(p_invoice_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_invoice public.invoices;
  v_lines_json jsonb;
  v_totals record;
  v_cogs numeric;
  v_cost_incomplete boolean;
  v_lines jsonb := '[]'::jsonb;
begin
  select * into v_invoice from public.invoices where id = p_invoice_id;
  if not found then
    raise exception 'Invoice % not found', p_invoice_id;
  end if;

  select jsonb_agg(jsonb_build_object('quantity', quantity, 'unit_price', unit_price, 'discount', discount))
  into v_lines_json
  from public.invoice_lines where invoice_id = p_invoice_id;

  select * into v_totals from public.compute_invoice_posting_amounts(
    v_lines_json, v_invoice.invoice_discount, v_invoice.total
  );

  select coalesce(sum(il.quantity * coalesce(p.cost, 0)), 0), bool_or(p.cost is null)
  into v_cogs, v_cost_incomplete
  from public.invoice_lines il
  join public.products p on p.id = il.product_id
  where il.invoice_id = p_invoice_id;

  if v_invoice.total > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('1100'),
      'debit', v_invoice.total, 'credit', 0, 'description', 'Accounts receivable'
    ));
  end if;

  if v_totals.discount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4200'),
      'debit', v_totals.discount, 'credit', 0, 'description', 'Invoice discount'
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
    v_invoice.branch_id, v_invoice.date, 'Invoice ' || p_invoice_id, p_invoice_id, v_lines, 'invoices', p_invoice_id,
    coalesce(v_cost_incomplete, false)
  );
end;
$$;

-- ===================================================== return: cash refund
-- ===================================================== / store credit /
-- ===================================================== top-up / exchange
create or replace function public.post_sale_return_journal_entry(p_return_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_return public.sale_returns;
  v_sale public.sales;
  v_returned_cost_raw numeric;
  v_replacement_cost_raw numeric;
  v_returned_cost numeric;
  v_replacement_cost numeric;
  v_net_cogs numeric;
  v_refund_amount numeric;
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

-- ============================================================ stock adjustment
create or replace function public.post_stock_adjustment_journal_entry(p_movement_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_movement public.stock_movements;
  v_cost numeric;
  v_amount numeric;
  v_lines jsonb;
begin
  select * into v_movement from public.stock_movements where id = p_movement_id;
  if not found then
    raise exception 'Stock movement % not found', p_movement_id;
  end if;

  if v_movement.movement_type <> 'Adjustment' then
    return null;
  end if;

  select cost into v_cost from public.products where id = v_movement.product_id;
  v_amount := round(abs(v_movement.change) * coalesce(v_cost, 0), 2);
  if v_amount = 0 then
    return null;
  end if;

  if v_movement.change < 0 then
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('5210'),
        'debit', v_amount, 'credit', 0,
        'description', case when v_cost is null then 'Stock shrinkage (estimated — cost price missing)' else 'Stock shrinkage' end
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', 0, 'credit', v_amount, 'description', 'Stock shrinkage'
      )
    );
  else
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', v_amount, 'credit', 0, 'description', 'Stock correction'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('5210'),
        'debit', 0, 'credit', v_amount,
        'description', case when v_cost is null then 'Stock correction (estimated — cost price missing)' else 'Stock correction' end
      )
    );
  end if;

  return public._post_journal_entry_rows(
    v_movement.branch_id, v_movement.occurred_at::date, 'Stock adjustment — ' || v_movement.reason,
    p_movement_id::text, v_lines, 'stock_movements', p_movement_id::text, v_cost is null
  );
end;
$$;
