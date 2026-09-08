-- End of Day Reconciliation (Phase 1.5, Session 11 — new, added after the
-- original ten sessions were complete).
--
-- Two tables: `day_closes` (the locked daily snapshot) and `bank_deposits`
-- (a lightweight cash/MoMo deposit log, not the full Bank Reconciliation
-- module — that stays Phase 2).
--
-- `day_closes` is a two-phase row, not a single insert-once record like
-- invoices/sales/expenses: a Manager "opens" the day each morning (setting
-- opening_float) and "closes" it that evening (setting counted_cash, the
-- manual tally, and everything computed). This mirrors the business's own
-- two distinct moments — the spec's own field list for the close action
-- ("counted cash, manual tally figures, note") pointedly does NOT include
-- opening float, confirming it's entered separately, not at close time.
-- The row transitions open -> closed exactly once (enforced by the RLS
-- update policy requiring closed_at is null, not just by convention), and
-- every snapshot column is null until that transition — the live preview
-- for a still-open day is never stored, only computed on demand via
-- compute_day_totals(), so a closed day is the only thing ever frozen.
--
-- "Every figure scoped by the transaction's own timestamp, not the
-- timestamp of anything it references": sales-by-method uses
-- sale_payments.paid_at (not the parent sale's sold_at — in practice the
-- same instant for POS, since a payment is captured atomically with the
-- sale, but this is the literal, defensible reading of the rule); cash
-- refunds use sale_returns.returned_at (not the original sale's sold_at —
-- this is the one that actually matters: a return processed days after its
-- sale must land on the day it happened); cash expenses use expenses.date
-- (the expense's own business date, not recorded_at's insert-time
-- metadata). VAT and discounts are properties fixed at sale creation with
-- no later "processed" event, so they use the sale's own sold_at.

-- ============================================================ day_closes

create table public.day_closes (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  business_date date not null check (business_date <= current_date),

  -- Set by open_day(), every morning, always for today (see above).
  opening_float numeric(12, 2) not null check (opening_float >= 0),
  opening_confirmed_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  opening_confirmed_at timestamptz not null default now(),

  -- Everything below is null until close_day() runs, then frozen forever —
  -- the check constraint enforces the transition is all-or-nothing.
  cash_sales numeric(12, 2),
  mobile_money_sales numeric(12, 2),
  card_sales numeric(12, 2),
  bank_transfer_sales numeric(12, 2),
  vat_collected numeric(12, 2),
  discounts_given numeric(12, 2),
  cash_refunds numeric(12, 2),
  cash_expenses numeric(12, 2),
  expected_cash numeric(12, 2),
  counted_cash numeric(12, 2),
  cash_variance numeric(12, 2),
  system_sales_total numeric(12, 2),
  system_transaction_count integer,
  manual_sales_total numeric(12, 2),
  manual_transaction_count integer,
  tally_sales_variance numeric(12, 2),
  tally_count_variance integer,
  notes text not null default '',
  closed_by uuid references public.staff (id) on delete restrict,
  closed_at timestamptz,

  created_at timestamptz not null default now(),

  unique (branch_id, business_date),
  check (
    (closed_at is null and counted_cash is null and manual_sales_total is null
      and manual_transaction_count is null and closed_by is null)
    or
    (closed_at is not null and counted_cash is not null and manual_sales_total is not null
      and manual_transaction_count is not null and closed_by is not null)
  )
);

create index day_closes_branch_date_idx on public.day_closes (branch_id, business_date desc);

create or replace function public.set_opening_confirmed_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.opening_confirmed_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger day_closes_set_opening_confirmed_by
before insert on public.day_closes
for each row execute function public.set_opening_confirmed_by();

-- Forced at the trigger level, not just inside close_day(), for the same
-- reason every other identity column in this build is: a raw PATCH from a
-- legitimate Manager session could otherwise set closed_by to a different
-- Manager's uuid and misattribute the close.
create or replace function public.set_closed_by()
returns trigger language plpgsql as $$
begin
  if new.closed_at is not null and auth.uid() is not null then new.closed_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger day_closes_set_closed_by
before update on public.day_closes
for each row execute function public.set_closed_by();

-- ========================================================== bank_deposits

create table public.bank_deposits (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  date date not null,
  source text not null check (source in ('Cash', 'Mobile Money')),
  deposited_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  reference text not null default '',
  note text not null default '',
  created_at timestamptz not null default now()
);

create index bank_deposits_branch_date_idx on public.bank_deposits (branch_id, date desc);

create or replace function public.set_deposited_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.deposited_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger bank_deposits_set_deposited_by
before insert on public.bank_deposits
for each row execute function public.set_deposited_by();

-- ==================================================== compute_day_totals()

-- Read-only aggregation for one branch/day, shared by the live preview
-- (called directly, result never stored) and close_day() (called
-- internally, result frozen into the row). SECURITY DEFINER so Attendant/
-- Accountant-Auditor can see the preview's cash_expenses figure without
-- gaining row-level SELECT on `expenses` itself (which Attendant doesn't
-- have) — the same "one aggregate number, not table access" reasoning
-- applies to every figure here, but expenses is the only one that actually
-- needs the widened read.
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
  system_transaction_count integer
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
  v_cash_sales numeric := 0;
  v_mobile_money_sales numeric := 0;
  v_card_sales numeric := 0;
  v_bank_transfer_sales numeric := 0;
  v_cash_refunds numeric := 0;
  v_cash_expenses numeric := 0;
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

  -- Sales by payment method — scoped by each payment's own paid_at.
  select
    coalesce(sum(amount) filter (where method = 'Cash'), 0),
    coalesce(sum(amount) filter (where method = 'Mobile Money'), 0),
    coalesce(sum(amount) filter (where method = 'Card'), 0),
    coalesce(sum(amount) filter (where method = 'Bank Transfer'), 0)
  into v_cash_sales, v_mobile_money_sales, v_card_sales, v_bank_transfer_sales
  from public.sale_payments
  where branch_id = p_branch_id and paid_at::date = p_business_date;

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
    v_system_sales_total, v_system_transaction_count;
end;
$$;

grant execute on function public.compute_day_totals(uuid, date) to authenticated;

-- =============================================================== open_day()

-- Always today — this is inherently a same-day action ("confirm the real
-- opening float each morning"), not a backdating mechanism, so business_date
-- is never client-supplied.
create or replace function public.open_day(p_branch_id uuid, p_opening_float numeric)
returns public.day_closes
language plpgsql
as $$
declare
  v_row public.day_closes;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can confirm the opening float';
  end if;
  if p_opening_float < 0 then
    raise exception 'Opening float cannot be negative';
  end if;

  begin
    insert into public.day_closes (branch_id, business_date, opening_float)
    values (p_branch_id, current_date, p_opening_float)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Today''s opening float has already been confirmed';
  end;

  return v_row;
end;
$$;

grant execute on function public.open_day(uuid, numeric) to authenticated;

-- ============================================================== close_day()

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

  -- Plain read, not `for update`: Postgres RLS applies the UPDATE policy's
  -- USING clause to SELECT ... FOR UPDATE too (it needs to check the row is
  -- actually lockable/updatable), and day_closes_update's USING requires
  -- closed_at is null — so a row-locking select here would silently return
  -- zero rows for an already-closed day and misreport it as "never
  -- opened." The atomic guard against a concurrent double-close instead
  -- lives on the UPDATE statement's own WHERE clause below.
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
    notes = coalesce(p_notes, ''),
    closed_at = now()
  -- closed_at is null here too: the real protection against two concurrent
  -- close_day() calls both racing past the checks above. Postgres's own
  -- per-row locking during UPDATE execution makes this atomic — whichever
  -- transaction commits first wins, the second matches zero rows.
  where id = v_open.id and closed_at is null
  returning * into v_row;
  if not found then
    raise exception 'Today has already been closed';
  end if;

  return v_row;
end;
$$;

grant execute on function public.close_day(uuid, numeric, numeric, integer, text) to authenticated;

-- ===================================================== record_bank_deposit()

-- A plain insert underneath (bank_deposits needs no generated sequential
-- id), but wrapped in an RPC anyway — same reasoning as
-- create_customer_discount(): a clear "Only a Manager can..." message
-- beats a bare RLS 403 for a role-gated action a Manager will hit routinely.
create or replace function public.record_bank_deposit(
  p_branch_id uuid,
  p_amount numeric,
  p_date date,
  p_source text,
  p_reference text default '',
  p_note text default ''
)
returns public.bank_deposits
language plpgsql
as $$
declare
  v_row public.bank_deposits;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record a bank/mobile money deposit';
  end if;
  if p_amount <= 0 then
    raise exception 'Deposit amount must be greater than zero';
  end if;
  if p_source not in ('Cash', 'Mobile Money') then
    raise exception 'Invalid deposit source';
  end if;

  insert into public.bank_deposits (branch_id, amount, date, source, reference, note)
  values (p_branch_id, p_amount, p_date, p_source, coalesce(p_reference, ''), coalesce(p_note, ''))
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.record_bank_deposit(uuid, numeric, date, text, text, text) to authenticated;

-- ===================================================================== RLS

alter table public.day_closes enable row level security;

-- Read access matches the spec's explicit role rule for this feature:
-- Attendant and Accountant/Auditor can view past closed days (and, since
-- there's no separate "preview" table, today's still-open row too) — the
-- same is_active_staff() shape every ordinary operational table uses.
create policy day_closes_select on public.day_closes
for select
using (public.is_active_staff());

-- Insert is open_day()'s path; update is close_day()'s. Both Manager-only.
create policy day_closes_insert on public.day_closes
for insert
with check (public.has_role(array['Manager']));

-- The load-bearing line: even a Manager can never update a row once
-- closed_at is set. This is what makes "a closed day must never change
-- once locked" true against a direct API call, not just against the RPCs.
create policy day_closes_update on public.day_closes
for update
using (public.has_role(array['Manager']) and closed_at is null)
with check (public.has_role(array['Manager']));

-- Delete is scoped the same way, for a narrower reason: no update RPC
-- exists for a mistyped opening float, so a Manager corrects one by
-- deleting the still-open row and calling open_day() again. Never allowed
-- once closed_at is set, for the same reason update never is.
create policy day_closes_delete on public.day_closes
for delete
using (public.has_role(array['Manager']) and closed_at is null);

revoke all on public.day_closes from anon;
grant select, insert, update, delete on public.day_closes to authenticated;
grant select, insert, update, delete on public.day_closes to service_role;

alter table public.bank_deposits enable row level security;

-- Same sensitivity class as expenses/expense_categories (a Manager-
-- controlled cash-management record) — Attendant gets none of
-- select/insert/update/delete, matching that precedent exactly rather than
-- the generic is_active_staff()/can_write() shape most other tables use.
create policy bank_deposits_select on public.bank_deposits
for select
using (public.has_role(array['Manager', 'Accountant/Auditor']));

create policy bank_deposits_insert on public.bank_deposits
for insert
with check (public.has_role(array['Manager']));

create policy bank_deposits_update on public.bank_deposits
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

create policy bank_deposits_delete on public.bank_deposits
for delete
using (public.has_role(array['Manager']));

revoke all on public.bank_deposits from anon;
grant select, insert, update, delete on public.bank_deposits to authenticated;
grant select, insert, update, delete on public.bank_deposits to service_role;
