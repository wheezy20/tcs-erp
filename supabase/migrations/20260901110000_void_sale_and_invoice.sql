-- Void a mistaken POS sale / invoice (Phase 1.5 follow-up).
--
-- Distinct from returning individual line items: a return is a real customer
-- interaction (goods come back, money or credit moves, the sale still
-- happened); a void says "this whole transaction was rung up by mistake and
-- should never have existed." So a void is an *erasure*, not a new
-- transaction: it reverses every ledger entry the original produced, restores
-- every unit of stock it moved, and marks the row dead — it does not create a
-- refund/return record.
--
-- Shape, matching the cash-refund precedent (role_permissions_rewrite):
--   * Manager only. Checked in the RPC (has_role(['Manager'])) AND, because
--     the RPC is the only sanctioned path, structurally: the void columns on
--     sales/invoices are writable ONLY from inside void_sale()/void_invoice()
--     (SECURITY DEFINER, so current_user is the function owner, not one of the
--     PostgREST app roles) — a direct REST PATCH of voided_at is rejected by
--     the guard trigger below regardless of role.
--   * A non-empty reason is mandatory, stored on the row, and logged to
--     audit_log via an AFTER UPDATE trigger (same "entries come from triggers
--     on the action, never client inserts" rule Session 8 established — and
--     audit_log has no insert grant for anyone, so it could not be otherwise).
--
-- Four hard blocks, each with a clear message, no exceptions:
--   1. Closed day. If the transaction's own day (sale: sold_at::date;
--      invoice: its issue date OR any of its payments' dates) has a
--      day_closes row with closed_at set, the void is refused — a closed day
--      has been reconciled and signed off, and its frozen figures must not be
--      silently invalidated.
--   2. Has returns/exchanges against it. Those moved real stock and money and
--      must be unwound through the returns flow first. (Invoices have no
--      returns mechanism in this codebase at all, so this block is
--      structurally POS-only; kept symmetric in the RPC for clarity.)
--   3. Older than 7 days from the original transaction date. A void is for a
--      fresh mistake; anything older goes through returns / a manual journal
--      correction.
--   4. Not a Manager.
--   (A fifth guard, not one of the four the feature is specified around but a
--   real integrity constraint: a sale/invoice that fulfilled a customer
--   deposit cannot be voided — that would strand the deposit as Fulfilled
--   against a dead document. Unwind it through the deposit instead.)
--
-- Ledger reversal reuses reverse_journal_entry() exactly as built — one call
-- per journal entry the transaction produced (a POS sale has exactly one; an
-- invoice has its creation entry plus one per payment, WHT-credit and
-- deposit legs included). No reversal lines are hand-built here.

-- ============================================================ schema

alter table public.sales
  add column voided_at timestamptz,
  add column voided_by uuid references public.staff (id) on delete restrict,
  add column void_reason text,
  add constraint sales_void_shape check (
    (voided_at is null) = (voided_by is null)
    and (voided_at is null) = (void_reason is null)
  );

alter table public.invoices
  add column voided_at timestamptz,
  add column voided_by uuid references public.staff (id) on delete restrict,
  add column void_reason text,
  add constraint invoices_void_shape check (
    (voided_at is null) = (voided_by is null)
    and (voided_at is null) = (void_reason is null)
  );

-- Stock restored on a void is its own movement type, not 'Return' — so a
-- voided-sale reversal is never mistaken for a customer return in stock
-- history.
alter table public.stock_movements drop constraint stock_movements_movement_type_check;
alter table public.stock_movements
  add constraint stock_movements_movement_type_check
  check (movement_type in ('Sale', 'Purchase', 'Adjustment', 'Return', 'Void'));

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log
  add constraint audit_log_action_check
  check (action in ('discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided'));

-- ============================================================ guard triggers

-- The void columns are writable only from inside void_sale()/void_invoice().
-- Those run SECURITY DEFINER, so current_user is the function owner; every
-- real client request (and every local tooling call) arrives as one of the
-- PostgREST/Supabase app roles. Blocking that set is robust across
-- environments (it does not assume the owner is literally "postgres"). Also
-- enforces one-way: a void, once set, can never be cleared — by anyone.
create or replace function public.reject_direct_void_write()
returns trigger
language plpgsql
as $$
begin
  if (new.voided_at is distinct from old.voided_at
      or new.voided_by is distinct from old.voided_by
      or new.void_reason is distinct from old.void_reason)
     and current_user = any (array['authenticated', 'anon', 'authenticator', 'service_role']) then
    raise exception 'Void status can only be changed through void_%()', tg_argv[0];
  end if;

  if old.voided_at is not null and new.voided_at is null then
    raise exception 'A void cannot be undone (%)', tg_argv[0] || ' ' || old.id;
  end if;

  -- Once voided, the row is frozen against every other write path too
  -- (update_invoice, record_invoice_payment's balance update, ...). The void
  -- transition itself (old.voided_at null -> new.voided_at set) is allowed.
  if old.voided_at is not null and new.voided_at is not null then
    raise exception '% has been voided and can no longer be modified',
      initcap(tg_argv[0]) || ' ' || old.id;
  end if;

  return new;
end;
$$;

create trigger sales_reject_direct_void_write
before update on public.sales
for each row execute function public.reject_direct_void_write('sale');

create trigger invoices_reject_direct_void_write
before update on public.invoices
for each row execute function public.reject_direct_void_write('invoice');

-- A voided sale/invoice can take no further returns or payments — catches
-- every write path (create_sale_return[_batch](), record_invoice_payment(),
-- and any direct insert) in one place rather than editing each RPC body.
create or replace function public.block_activity_on_voided_sale()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.sales where id = new.sale_id and voided_at is not null) then
    raise exception 'Sale % has been voided; a return cannot be processed against it', new.sale_id;
  end if;
  return new;
end;
$$;

create trigger sale_returns_block_voided_sale
before insert on public.sale_returns
for each row execute function public.block_activity_on_voided_sale();

create or replace function public.block_activity_on_voided_invoice()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.invoices where id = new.invoice_id and voided_at is not null) then
    raise exception 'Invoice % has been voided; a payment cannot be recorded against it', new.invoice_id;
  end if;
  return new;
end;
$$;

create trigger invoice_payments_block_voided_invoice
before insert on public.invoice_payments
for each row execute function public.block_activity_on_voided_invoice();

-- ============================================================ audit triggers

create or replace function public.audit_sale_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.voided_at is null and new.voided_at is not null then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      new.branch_id,
      coalesce(auth.uid(), new.voided_by),
      'sale_voided',
      'sales',
      new.id,
      jsonb_build_object('total', old.total, 'voided', false),
      jsonb_build_object('voided_at', new.voided_at, 'reason', new.void_reason)
    );
  end if;
  return new;
end;
$$;

create trigger sales_audit_void
after update of voided_at on public.sales
for each row execute function public.audit_sale_void();

create or replace function public.audit_invoice_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.voided_at is null and new.voided_at is not null then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      new.branch_id,
      coalesce(auth.uid(), new.voided_by),
      'invoice_voided',
      'invoices',
      new.id,
      jsonb_build_object('total', old.total, 'balance', old.balance, 'voided', false),
      jsonb_build_object('voided_at', new.voided_at, 'reason', new.void_reason)
    );
  end if;
  return new;
end;
$$;

create trigger invoices_audit_void
after update of voided_at on public.invoices
for each row execute function public.audit_invoice_void();

-- ============================================================ void_sale()

create or replace function public.void_sale(p_sale_id text, p_reason text)
returns public.sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.sales;
  v_reason text := trim(coalesce(p_reason, ''));
  v_entry record;
  v_line record;
  v_new_stock integer;
  v_deposit text;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can void a sale';
  end if;
  if v_reason = '' then
    raise exception 'A void needs a reason';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then
    raise exception 'Sale % does not exist', p_sale_id;
  end if;
  if v_sale.voided_at is not null then
    raise exception 'Sale % has already been voided', p_sale_id;
  end if;

  if exists (select 1 from public.sale_returns where sale_id = p_sale_id) then
    raise exception 'Sale % has returns or exchanges against it — unwind those through the returns flow first', p_sale_id;
  end if;

  select id into v_deposit from public.customer_deposits where fulfilled_sale_id = p_sale_id limit 1;
  if v_deposit is not null then
    raise exception 'Sale % fulfilled customer deposit % — unwind that through the deposit instead', p_sale_id, v_deposit;
  end if;

  if exists (
    select 1 from public.day_closes
    where branch_id = v_sale.branch_id and business_date = v_sale.sold_at::date and closed_at is not null
  ) then
    raise exception 'The day % has been closed and reconciled — a sale from a closed day cannot be voided', v_sale.sold_at::date;
  end if;

  if current_date - v_sale.sold_at::date > 7 then
    raise exception 'A sale can only be voided within 7 days of the transaction (% is % days old)',
      p_sale_id, current_date - v_sale.sold_at::date;
  end if;

  -- Reverse the ledger — one reverse_journal_entry() call per entry the sale
  -- produced (a POS sale has exactly one; zero for a pre-auto-posting seed
  -- sale, which the 7-day block makes unreachable anyway).
  for v_entry in
    select id from public.journal_entries where source_table = 'sales' and source_id = p_sale_id
  loop
    perform public.reverse_journal_entry(
      v_entry.id, current_date, 'Void of POS sale ' || p_sale_id || ' — ' || v_reason
    );
  end loop;

  -- Restore stock. Lock the affected product rows in a stable id order first
  -- (same discipline as create_sale()), then add each line's quantity back
  -- and log a 'Void' movement.
  perform 1 from public.products
  where id in (select distinct product_id from public.sale_lines where sale_id = p_sale_id)
  order by id
  for update;

  for v_line in
    select product_id, sum(quantity)::integer as quantity
    from public.sale_lines where sale_id = p_sale_id
    group by product_id
  loop
    update public.products set stock = stock + v_line.quantity
    where id = v_line.product_id
    returning stock into v_new_stock;

    insert into public.stock_movements (product_id, branch_id, movement_type, change, balance_after, reason)
    values (v_line.product_id, v_sale.branch_id, 'Void', v_line.quantity, v_new_stock, p_sale_id);
  end loop;

  update public.sales
  set voided_at = now(), voided_by = auth.uid(), void_reason = v_reason
  where id = p_sale_id
  returning * into v_sale;

  return v_sale;
end;
$$;

grant execute on function public.void_sale(text, text) to authenticated;
grant execute on function public.void_sale(text, text) to service_role;

-- ============================================================ void_invoice()

create or replace function public.void_invoice(p_invoice_id text, p_reason text)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_reason text := trim(coalesce(p_reason, ''));
  v_entry record;
  v_deposit text;
  v_closed_date date;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can void an invoice';
  end if;
  if v_reason = '' then
    raise exception 'A void needs a reason';
  end if;

  select * into v_invoice from public.invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'Invoice % does not exist', p_invoice_id;
  end if;
  if v_invoice.voided_at is not null then
    raise exception 'Invoice % has already been voided', p_invoice_id;
  end if;

  -- Invoices have no returns mechanism in this codebase, so there is nothing
  -- to check here — kept explicit so the absence is deliberate, not an
  -- oversight.

  select id into v_deposit from public.customer_deposits where fulfilled_invoice_id = p_invoice_id limit 1;
  if v_deposit is not null then
    raise exception 'Invoice % fulfilled customer deposit % — unwind that through the deposit instead', p_invoice_id, v_deposit;
  end if;

  -- Closed day: the invoice's own issue date, or any date it took a payment.
  select dc.business_date into v_closed_date
  from public.day_closes dc
  where dc.branch_id = v_invoice.branch_id
    and dc.closed_at is not null
    and (
      dc.business_date = v_invoice.date
      or dc.business_date in (
        select paid_at::date from public.invoice_payments where invoice_id = p_invoice_id
      )
    )
  limit 1;
  if v_closed_date is not null then
    raise exception 'The day % has been closed and reconciled — an invoice touching a closed day cannot be voided', v_closed_date;
  end if;

  if current_date - v_invoice.date > 7 then
    raise exception 'An invoice can only be voided within 7 days of the transaction (% is % days old)',
      p_invoice_id, current_date - v_invoice.date;
  end if;

  -- Reverse the ledger: the invoice-creation entry plus one entry per
  -- payment (real cash/bank, WHT-credit and deposit legs alike).
  for v_entry in
    select id from public.journal_entries
    where (source_table = 'invoices' and source_id = p_invoice_id)
       or (source_table = 'invoice_payments'
           and source_id in (select id::text from public.invoice_payments where invoice_id = p_invoice_id))
  loop
    perform public.reverse_journal_entry(
      v_entry.id, current_date, 'Void of invoice ' || p_invoice_id || ' — ' || v_reason
    );
  end loop;

  -- No stock to restore: invoices never deduct stock in this system (see
  -- create_invoice() — "Invoices never touch stock"). Only void_sale()
  -- writes 'Void' stock movements.

  -- Mark voided and zero the outstanding balance (nothing is owed on a dead
  -- invoice) — sync_customer_totals() fires on this UPDATE and drops the
  -- invoice from the customer's balance and lifetime total.
  update public.invoices
  set voided_at = now(), voided_by = auth.uid(), void_reason = v_reason, balance = 0
  where id = p_invoice_id
  returning * into v_invoice;

  return v_invoice;
end;
$$;

grant execute on function public.void_invoice(text, text) to authenticated;
grant execute on function public.void_invoice(text, text) to service_role;

-- ============================================================ customer totals

-- Recreated to exclude voided invoices from both sums (a voided invoice's
-- own balance is zeroed by void_invoice() anyway, but lifetime_total sums
-- `total`, which is left intact as history — so the filter is what keeps it
-- correct).
create or replace function public.sync_customer_totals()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    update public.customers c
    set balance = coalesce((select sum(i.balance) from public.invoices i where i.customer_id = c.id and i.voided_at is null), 0),
        lifetime_total = coalesce((select sum(i.total) from public.invoices i where i.customer_id = c.id and i.voided_at is null), 0)
    where c.id = old.customer_id;
    return old;
  end if;

  update public.customers c
  set balance = coalesce((select sum(i.balance) from public.invoices i where i.customer_id = c.id and i.voided_at is null), 0),
      lifetime_total = coalesce((select sum(i.total) from public.invoices i where i.customer_id = c.id and i.voided_at is null), 0)
  where c.id = new.customer_id;

  if tg_op = 'UPDATE' and old.customer_id is distinct from new.customer_id then
    update public.customers c
    set balance = coalesce((select sum(i.balance) from public.invoices i where i.customer_id = c.id and i.voided_at is null), 0),
        lifetime_total = coalesce((select sum(i.total) from public.invoices i where i.customer_id = c.id and i.voided_at is null), 0)
    where c.id = old.customer_id;
  end if;

  return new;
end;
$$;

-- ============================================================ day totals

-- Recreated verbatim from line_discount_per_unit_mode.sql with voided sales
-- and voided invoices' payments excluded — a same-day void nets correctly
-- against the drawer (cash handed back leaves the till by the same amount
-- the excluded sale would have added); a closed day cannot be affected at
-- all, because voiding a closed-day transaction is blocked outright.
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
  where branch_id = p_branch_id and date = p_business_date and method = 'Cash';

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

-- ============================================================ overdue alerts

-- A voided invoice is no longer owed (its balance is zeroed anyway) — filter
-- it out explicitly so a stale balance can never resurface it.
create or replace function public.notify_overdue_invoices(p_branch_id uuid, p_as_of date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
  v_invoice record;
begin
  select overdue_invoice_alerts_enabled into v_enabled from public.business_settings where id = 1;
  if not coalesce(v_enabled, true) then
    return;
  end if;

  for v_invoice in
    select i.* from public.invoices i
    where i.branch_id = p_branch_id
      and i.voided_at is null
      and i.balance > 0
      and i.due_date < p_as_of
      and not exists (
        select 1 from public.notifications n
        where n.entity_table = 'invoices' and n.entity_id = i.id and n.type = 'overdue_invoice'
      )
    order by i.due_date
  loop
    perform public.notify_managers(
      p_branch_id,
      'overdue_invoice',
      format('Invoice %s is overdue', v_invoice.id),
      format(
        '%s · balance GHS %s · was due %s',
        v_invoice.customer_name,
        to_char(v_invoice.balance, 'FM999,999,990.00'),
        to_char(v_invoice.due_date, 'DD Mon YYYY')
      ),
      '/sales/' || v_invoice.id,
      'invoices',
      v_invoice.id
    );
  end loop;
end;
$$;

-- ============================================================ sales immutability
--
-- The UPDATE grant on sales is deliberately NOT revoked: create_sale_return()
-- and create_sale_return_batch() take a `select ... from sales ... for update`
-- row lock on the sale, which Postgres requires the UPDATE privilege for.
-- Nothing legitimate actually writes a sales column from the client — the
-- reject_direct_void_write trigger above is what enforces "the void columns
-- are only writable through void_sale()", and a direct PATCH of any other
-- sales column was already a pre-existing no-op-in-practice allowed by the
-- generic sales_update policy, unchanged by this migration.
