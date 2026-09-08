-- ============================================================================
-- Multi-line returns: several line returns from one sale as a single
-- customer-facing transaction.
--
-- Until now create_sale_return() handled exactly one sale_lines row per call,
-- and the returns screen ran one line-select-submit-reset cycle at a time,
-- with no way to tell that two returns belong to the same customer event.
--
-- ---------------------------------------------------------------------------
-- Grouping model: a shared `return_group_id uuid` column on sale_returns,
-- NOT a new header table.
--
-- Every field a header table would carry already lives on each sale_returns
-- row: reason, resolution (per line), customer_id, processed_by, branch_id,
-- sale_id, returned_at. Relocating any of them onto a header would break
-- three pieces of verified code that read them straight off the row —
-- post_sale_return_journal_entry() (v_return.resolution / .difference /
-- .returned_at), audit_sale_return() (new.resolution / .reason), and the
-- frontend return history. The only thing genuinely missing is "these N
-- rows are one event", and a single shared uuid delivers exactly that with
-- zero disturbance to any of it. Legacy single-line returns keep a NULL
-- group id (they really are standalone; nothing is backfilled).
--
-- ---------------------------------------------------------------------------
-- create_sale_return_batch() ORCHESTRATES; it does not reimplement return
-- logic. It:
--   1. validates the batch shape and the shared refund choice,
--   2. locks the sale row,
--   3. locks EVERY product the batch will touch (returned + replacement,
--      across all lines) once, in a single globally-sorted pass — the same
--      deadlock-avoidance discipline create_sale() uses for its own line
--      products, extended across the whole batch so a per-line call's own
--      `for update` never has to wait,
--   4. loops, deriving each line's resolution server-side from the shared
--      refund choice + that line's own computed difference, and delegates
--      to the UNCHANGED create_sale_return() once per line,
--   5. stamps return_group_id onto exactly the rows it just created.
--
-- Because step 4 is literally create_sale_return() running once per line
-- inside one transaction, every existing constraint is preserved exactly:
-- the cumulative-quantity cap per returned_sale_line_id, Manager-only cash
-- refunds, the Walk-in store-credit block, the replacement stock check, the
-- per-line difference, and the per-line journal posting. A partial batch
-- never commits (one plpgsql function body = one transaction).
--
-- Per-line journal entries (one per sale_returns row, keyed by return id via
-- journal_entries' unique (source_table, source_id)) are kept, not merged
-- into one combined entry: the existing poster already books per-line
-- COGS / refund / VAT correctly and is verified, N entries carry identical
-- ledger totals to one, and the ledger has no reason to reference the
-- grouping. create_sale_return() itself is untouched and remains a valid
-- single-line entry point.
-- ============================================================================

alter table public.sale_returns
  add column return_group_id uuid;

comment on column public.sale_returns.return_group_id is
  'Ties multiple sale_returns rows together as one customer-facing return transaction. NULL for standalone (pre-batch, or single) returns.';

create index sale_returns_group_idx
  on public.sale_returns (return_group_id)
  where return_group_id is not null;


create or replace function public.create_sale_return_batch(
  p_sale_id text,
  p_lines jsonb,               -- [{ returned_sale_line_id, returned_quantity,
                               --    replacement_product_id | null, replacement_quantity | null }]
  p_reason text,
  p_refund_choice text,        -- 'Cash refund' | 'Store credit' — the shared
                               -- money-back decision; only consulted for lines
                               -- that actually put money back to the customer
  p_payment_method text default null,   -- shared: how any top-up is collected
  p_customer_id uuid default null,      -- shared: Walk-in store-credit attach
  p_bank_account_id uuid default null   -- shared: bank account for a Card / Bank Transfer top-up
) returns setof public.sale_returns
language plpgsql
as $$
declare
  v_sale public.sales;
  v_group_id uuid := gen_random_uuid();
  v_line jsonb;
  v_sale_line public.sale_lines;
  v_replacement public.products;
  v_returned_qty integer;
  v_repl_id uuid;
  v_repl_qty integer;
  v_difference numeric;
  v_resolution text;
  v_seen uuid[] := '{}';
  v_ids uuid[] := '{}';
  v_ret public.sale_returns;
begin
  perform public.require_writable_role();

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'A return needs at least one line';
  end if;
  if p_refund_choice not in ('Cash refund', 'Store credit') then
    raise exception 'Invalid refund choice';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then raise exception 'Sale % not found', p_sale_id; end if;

  -- Lock every product this batch touches, once, in one globally-sorted pass.
  -- Each per-line create_sale_return() call below re-locks a subset that is
  -- already held, so its own `for update` never waits and two concurrent
  -- batches touching an overlapping product set cannot deadlock each other.
  perform 1
  from public.products
  where id in (
    select sl.product_id
    from jsonb_array_elements(p_lines) e
    join public.sale_lines sl on sl.id = (e ->> 'returned_sale_line_id')::uuid
    union
    select (e ->> 'replacement_product_id')::uuid
    from jsonb_array_elements(p_lines) e
    where nullif(e ->> 'replacement_product_id', '') is not null
  )
  order by id
  for update;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    -- The cumulative-quantity cap is enforced per returned_sale_line_id
    -- against *committed* prior returns; two entries for one line in the
    -- same uncommitted call would each under-count, so reject that outright.
    if (v_line ->> 'returned_sale_line_id')::uuid = any(v_seen) then
      raise exception 'The same line appears twice in this return';
    end if;
    v_seen := v_seen || (v_line ->> 'returned_sale_line_id')::uuid;

    v_returned_qty := (v_line ->> 'returned_quantity')::integer;
    v_repl_id := nullif(v_line ->> 'replacement_product_id', '')::uuid;
    v_repl_qty := nullif(v_line ->> 'replacement_quantity', '')::integer;

    select * into v_sale_line
    from public.sale_lines
    where id = (v_line ->> 'returned_sale_line_id')::uuid and sale_id = p_sale_id;
    if not found then raise exception 'Sale line does not belong to this sale'; end if;

    -- Derive this line's resolution the same way the single-line flow does,
    -- but server-side from the shared refund choice rather than trusting a
    -- client-passed value.
    if v_repl_id is not null then
      select * into v_replacement from public.products where id = v_repl_id;
      v_difference := round(
        coalesce(v_replacement.price, 0) * coalesce(v_repl_qty, 0)
        - v_sale_line.unit_price * v_returned_qty, 2);
    else
      v_difference := round(-(v_sale_line.unit_price * v_returned_qty), 2);
    end if;

    v_resolution := case
      when v_repl_id is null then p_refund_choice
      when v_difference > 0.01 then 'Top-up collected'
      when v_difference < -0.01 then p_refund_choice
      else 'Even exchange'
    end;

    -- Delegate: create_sale_return() runs unchanged, once per line. Every
    -- constraint it enforces (cumulative cap, Manager-only cash refund,
    -- Walk-in store-credit block, replacement stock check, per-line
    -- difference, per-line journal posting) applies here identically.
    select * into v_ret from public.create_sale_return(
      p_sale_id,
      (v_line ->> 'returned_sale_line_id')::uuid,
      v_returned_qty,
      v_repl_id,
      v_repl_qty,
      v_resolution,
      'Not required',
      p_reason,
      case when v_resolution = 'Top-up collected' then p_payment_method else null end,
      p_customer_id,
      case when v_resolution = 'Top-up collected' then p_bank_account_id else null end
    );
    v_ids := v_ids || v_ret.id;
  end loop;

  update public.sale_returns set return_group_id = v_group_id where id = any(v_ids);

  return query
    select * from public.sale_returns where id = any(v_ids) order by returned_at, id;
end;
$$;

grant execute on function public.create_sale_return_batch(text, jsonb, text, text, text, uuid, uuid)
  to authenticated;
grant execute on function public.create_sale_return_batch(text, jsonb, text, text, text, uuid, uuid)
  to service_role;
