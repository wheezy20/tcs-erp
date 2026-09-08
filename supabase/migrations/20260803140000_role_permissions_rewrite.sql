-- Rewrites RLS to match business-app-spec.md section 6 exactly (the "locked
-- model for Session 8 onward"), replacing Session 7's deliberately-shallow
-- "any active staff, any role, same access" placeholder:
--
--   Manager:              read and write on every model, including delete.
--   Accountant/Auditor:   read-only on every model, no write access anywhere,
--                         not even to their own actions.
--   Attendant/Cashier:    read and write on Sales/POS/returns/invoices;
--                         discounts restricted to Manager-created,
--                         customer-attached ones; no Expenses access at all;
--                         Reports stays off-limits entirely.
--
-- Also adds `customer_discounts` (a Manager-created discount attached to one
-- customer, section 5's "an Attendant can only apply a discount a Manager
-- already created and attached to a specific customer, never an arbitrary
-- amount" made real), and two business-rule gates that were previously only
-- descriptive: create_sale()'s discount can no longer be an arbitrary
-- Attendant-typed number, and create_sale_return()'s cash-refund path now
-- actually requires a Manager instead of just labelling the row
-- "Pending manager approval" with nothing checking it.
--
-- Scope notes, so later sessions don't have to re-derive these judgment
-- calls from scratch:
--
-- - Inventory (products/stock_movements) write access is UNCHANGED for
--   Attendant (still "any active staff", same as Session 7) — the spec's
--   Attendant capability list doesn't mention Inventory either way, no
--   verification step in this task touches it, and Attendant already needs
--   SELECT+UPDATE on `products` (stock deduction) and INSERT on
--   `stock_movements` for create_sale()/create_sale_return() to run at all
--   (neither function is security definer, so the invoker's own grants+RLS
--   apply to every statement inside them). Tightening Inventory specifically
--   to Manager-only is a real follow-up if wanted, not attempted here.
-- - `branches`/`business_settings`/`staff` SELECT stay "any active staff" for
--   the same invoker-privilege reason: create_sale()/create_invoice() read
--   business_settings.vat_rate as whoever called them, and every "who did
--   this" display needs staff names. Only Accountant/Auditor's universal
--   read-only rule and Manager's universal write access actually change here.
-- - "Attendant: their own day's sales" is enforced on the *write* side only
--   (a dedicated sales_insert policy requiring cashier = auth.uid() and
--   sold_at::date = current_date for non-Managers) — not as a SELECT
--   restriction. A SELECT restriction would also hide every OTHER day's and
--   OTHER cashier's sales, which breaks Returns entirely: pos.returns.tsx
--   looks up a sale by receipt number or customer name with no date bound
--   (a customer can return something bought last week, rung up by whoever
--   was on till that day), and "can make returns and exchanges" is an
--   explicit, unqualified Attendant grant. Restricting the row the return
--   references would contradict the capability being granted at all, so
--   full SELECT stays available and only the write side is narrowed.
-- - "Reports must stay off-limits to Attendants entirely" has no clean
--   backend equivalent: `data/reports.ts` is a client-side useMemo over the
--   exact same useInventory()/useSales()/usePosSales()/useExpenses() hooks
--   Sales, POS and Invoices already call — there is no separate "Reports
--   query" RLS could distinguish from an ordinary Sales/POS read. This
--   migration gives Attendant zero access (not just restricted, none at all)
--   to `expenses`/`expense_categories`, which is both spec-consistent
--   (Expenses was never in Attendant's granted module list either) and a
--   real backend block on the specific reports the deferred-items note
--   called out (Profit & Margin, Expenses, Operating Margin, Cash on Hand
--   all need expense data). The frontend route guard on /reports (added in
--   the same commit as this migration) is what actually makes "Reports
--   returns nothing" true end-to-end — documented here as a UI-layer
--   control, not a substitute for RLS, because there is no table-level
--   mechanism to substitute it with.
-- - `products.cost` is still readable by Attendant at the column level.
--   Postgres RLS is row-level only; column-masking it from Attendant while
--   still allowing Attendant to read `products.price`/`stock` for POS would
--   need a security-definer view (or column-level GRANTs, which can't
--   differentiate by app role since every app role shares the single
--   `authenticated` Postgres role) — a materially larger change than
--   anything else in this migration. Flagged as a known, accepted gap
--   rather than silently left undone.

-- ============================================================ helper: can_write

-- Manager and Attendant can write (subject to whatever narrower policy a
-- given table/RPC adds on top); Accountant/Auditor never can. This is the
-- single predicate every write policy below is built from, so "no write
-- access anywhere, not even to their own actions" only has to be encoded
-- once.
create or replace function public.can_write()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_active_staff() and not public.has_role(array['Accountant/Auditor']);
$$;

grant execute on function public.can_write() to authenticated;

-- Same idea as require_staff(), but for RPCs: raises a clear, specific error
-- instead of letting an Accountant/Auditor's write fail deep inside the
-- function on a generic RLS/grant violation. Every mutating RPC below calls
-- this instead of bare require_staff().
create or replace function public.require_writable_role()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_staff();
  if public.has_role(array['Accountant/Auditor']) then
    raise exception 'Accountant/Auditor is read-only and cannot perform this action';
  end if;
end;
$$;

grant execute on function public.require_writable_role() to authenticated;

-- ======================================================= customer_discounts

-- A Manager-created discount attached to one specific customer. Session 5
-- built POS's discount field as a plain number anyone could type into;
-- section 5 of the spec requires that an Attendant can only ever apply a
-- discount that already exists here for that customer, never invent one.
create table public.customer_discounts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete cascade,
  label text not null,
  mode text not null check (mode in ('amount', 'percent')),
  value numeric not null check (value > 0),
  active boolean not null default true,
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger customer_discounts_set_updated_at
before update on public.customer_discounts
for each row execute function public.set_updated_at();

-- Same identity-forcing pattern as performed_by/issued_by/etc: force
-- created_by from auth.uid() whenever there's an authenticated caller, leave
-- it alone only for the superuser/seed context where auth.uid() is null.
create or replace function public.set_discount_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger customer_discounts_set_created_by
before insert on public.customer_discounts
for each row execute function public.set_discount_created_by();

-- Insert-only creation path, same create-can't-overwrite discipline as every
-- other table in this build: no p_id parameter, a plain insert (never an
-- upsert), id generated by the column default. Deactivating an existing
-- discount is a plain state-replace (active=false), not a creation, so it
-- goes through ordinary RLS-gated PostgREST updates instead of its own RPC —
-- same reasoning Session 4 used for setStaffActive()/set_expense_categories().
create or replace function public.create_customer_discount(
  p_customer_id uuid,
  p_label text,
  p_mode text,
  p_value numeric
)
returns public.customer_discounts
language plpgsql
as $$
declare
  v_branch_id uuid;
  v_row public.customer_discounts;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can create a customer discount';
  end if;

  if p_mode not in ('amount', 'percent') then
    raise exception 'Invalid discount mode';
  end if;
  if p_value <= 0 then
    raise exception 'Discount value must be greater than zero';
  end if;

  select branch_id into v_branch_id from public.customers where id = p_customer_id;
  if not found then
    raise exception 'Customer % not found', p_customer_id;
  end if;

  insert into public.customer_discounts (branch_id, customer_id, label, mode, value)
  values (v_branch_id, p_customer_id, p_label, p_mode, p_value)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_customer_discount(uuid, text, text, numeric) to authenticated;

alter table public.customer_discounts enable row level security;

-- Select is broad (every active staff member, including Attendant) since an
-- Attendant has to be able to see which discounts exist for a customer in
-- order to apply one. Write is Manager-only across the board.
create policy customer_discounts_select on public.customer_discounts
for select
using (public.is_active_staff());

create policy customer_discounts_insert on public.customer_discounts
for insert
with check (public.has_role(array['Manager']));

create policy customer_discounts_update on public.customer_discounts
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

create policy customer_discounts_delete on public.customer_discounts
for delete
using (public.has_role(array['Manager']));

revoke all on public.customer_discounts from anon;
grant select, insert, update, delete on public.customer_discounts to authenticated;
grant select, insert, update, delete on public.customer_discounts to service_role;

-- ============================================================ RLS: rewrite

-- Replace Session 7's uniform "any active staff, same for every role"
-- policies on every ordinary business table with the real 3-tier model.
-- expenses/expense_categories are handled separately below (Attendant gets
-- nothing there at all, not even select); sales gets its own insert policy
-- below too (the today+own-cashier write restriction); everything else here
-- is: select = any active staff, insert/update = can_write() (Manager or
-- Attendant), delete = Manager only.
do $$
declare
  t text;
  tables text[] := array[
    'branches', 'products', 'stock_movements',
    'customers',
    'invoices', 'invoice_lines', 'invoice_payments', 'invoice_number_counters',
    'sales', 'sale_lines', 'sale_payments', 'sale_returns', 'sale_number_counters'
  ];
begin
  foreach t in array tables loop
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('drop policy if exists %I_delete on public.%I', t, t);

    execute format('create policy %I_select on public.%I for select using (public.is_active_staff())', t, t);
    execute format('create policy %I_insert on public.%I for insert with check (public.can_write())', t, t);
    execute format('create policy %I_update on public.%I for update using (public.can_write()) with check (public.can_write())', t, t);
    execute format('create policy %I_delete on public.%I for delete using (public.has_role(array[''Manager'']))', t, t);
  end loop;
end;
$$;

-- sales gets a stricter insert check than the generic one just installed
-- above: Manager can insert any row (matches "everything"); Attendant is
-- limited to a row attributed to themselves, dated today — "their own day's
-- sales" as a write-side rule. Nothing about the normal checkout path is
-- affected: create_sale() never sets sold_at explicitly (column default is
-- now()) and the sales_set_cashier trigger already forces cashier to
-- auth.uid() regardless of what's supplied, so a real Attendant checkout
-- always satisfies this trivially. It only bites a direct/bypassing insert
-- attempting to backdate a sale or attribute it to someone else.
drop policy if exists sales_insert on public.sales;
create policy sales_insert on public.sales
for insert
with check (
  public.has_role(array['Manager'])
  or (public.can_write() and cashier = auth.uid() and sold_at::date = current_date)
);

-- expenses / expense_categories: Attendant isn't granted the Expenses module
-- at all (not in the spec's Attendant capability list), so unlike every
-- table above, Attendant gets none of select/insert/update/delete here.
-- Manager: full access. Accountant/Auditor: read-only, same as everywhere
-- else.
do $$
declare
  t text;
  tables text[] := array['expenses', 'expense_categories'];
begin
  foreach t in array tables loop
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('drop policy if exists %I_delete on public.%I', t, t);

    execute format(
      'create policy %I_select on public.%I for select using (public.has_role(array[''Manager'',''Accountant/Auditor'']))',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert with check (public.has_role(array[''Manager'']))',
      t, t
    );
    execute format(
      'create policy %I_update on public.%I for update using (public.has_role(array[''Manager''])) with check (public.has_role(array[''Manager'']))',
      t, t
    );
    execute format(
      'create policy %I_delete on public.%I for delete using (public.has_role(array[''Manager'']))',
      t, t
    );
  end loop;
end;
$$;

-- staff: select stays "any active staff" (unchanged — everyone needs names
-- for display). Update stays Manager-only (unchanged). Adds a delete policy
-- for consistency with "Manager: ...including delete...everything" — in
-- practice a no-op for any staff member with real history, since every
-- historical FK into staff is on delete restrict.
drop policy if exists staff_update on public.staff;
create policy staff_update on public.staff
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

drop policy if exists staff_delete on public.staff;
create policy staff_delete on public.staff
for delete
using (public.has_role(array['Manager']));

-- business_settings: select stays "any active staff" (create_sale()/
-- create_invoice() read vat_rate as whoever called them). Update narrows
-- from Manager-or-Accountant (Session 7's placeholder) to Manager only, now
-- that Accountant/Auditor must be read-only everywhere.
drop policy if exists business_settings_update on public.business_settings;
create policy business_settings_update on public.business_settings
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

-- ================================================================ RPC gates

-- adjust_product_stock(): only the write-role guard changes here (blocks
-- Accountant/Auditor with a clear message instead of a generic RLS error);
-- Attendant keeps access, per the Inventory scope note in the header above.
create or replace function public.adjust_product_stock(
  p_product_id uuid,
  p_new_stock integer,
  p_reason text
)
returns public.stock_movements
language plpgsql
as $$
declare
  v_old_stock integer;
  v_branch_id uuid;
  v_movement public.stock_movements;
begin
  perform public.require_writable_role();

  if p_new_stock < 0 then
    raise exception 'Stock cannot be negative';
  end if;

  select stock, branch_id into v_old_stock, v_branch_id
  from public.products
  where id = p_product_id
  for update;

  if not found then
    raise exception 'Product % not found', p_product_id;
  end if;

  update public.products set stock = p_new_stock where id = p_product_id;

  insert into public.stock_movements (product_id, branch_id, movement_type, change, balance_after, reason)
  values (p_product_id, v_branch_id, 'Adjustment', p_new_stock - v_old_stock, p_new_stock, p_reason)
  returning * into v_movement;

  return v_movement;
end;
$$;

-- create_invoice()/update_invoice()/record_invoice_payment(): only the
-- write-role guard changes (require_writable_role() instead of
-- require_staff()) — Attendant keeps full access, per "can create and issue
-- invoices" being an unqualified grant in the spec.
create or replace function public.create_invoice(
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb
)
returns public.invoices
language plpgsql
as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_vat_rate numeric;
  v_total numeric;
  v_invoice public.invoices;
begin
  perform public.require_writable_role();

  insert into public.invoice_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = invoice_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'INV-' || v_year_month || lpad(v_seq::text, 4, '0');

  select vat_rate into v_vat_rate from public.business_settings where id = 1;
  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  insert into public.invoices
    (id, branch_id, customer_id, customer_name, date, due_date, notes, invoice_discount, vat_rate, total, amount_paid, balance)
  values
    (v_id, p_branch_id, p_customer_id, p_customer_name, p_date, p_due_date, p_notes, p_invoice_discount, v_vat_rate, v_total, 0, v_total)
  returning * into v_invoice;

  insert into public.invoice_lines (invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select
    v_id,
    nullif(line->>'product_id', '')::uuid,
    line->>'name',
    line->>'unit',
    (line->>'quantity')::numeric,
    (line->>'unit_price')::numeric,
    coalesce((line->>'discount')::numeric, 0),
    coalesce((line->>'vat')::boolean, true),
    (ord - 1)::integer
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_invoice;
end;
$$;

create or replace function public.update_invoice(
  p_id text,
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb
)
returns public.invoices
language plpgsql
as $$
declare
  v_vat_rate numeric;
  v_total numeric;
  v_invoice public.invoices;
begin
  perform public.require_writable_role();

  select vat_rate into v_vat_rate from public.invoices where id = p_id for update;
  if not found then
    raise exception 'Invoice % not found', p_id;
  end if;

  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  update public.invoices set
    branch_id = p_branch_id,
    customer_id = p_customer_id,
    customer_name = p_customer_name,
    date = p_date,
    due_date = p_due_date,
    notes = p_notes,
    invoice_discount = p_invoice_discount,
    total = v_total,
    balance = greatest(v_total - amount_paid, 0)
  where id = p_id
  returning * into v_invoice;

  delete from public.invoice_lines where invoice_id = p_id;

  insert into public.invoice_lines (invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select
    p_id,
    nullif(line->>'product_id', '')::uuid,
    line->>'name',
    line->>'unit',
    (line->>'quantity')::numeric,
    (line->>'unit_price')::numeric,
    coalesce((line->>'discount')::numeric, 0),
    coalesce((line->>'vat')::boolean, true),
    (ord - 1)::integer
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_invoice;
end;
$$;

create or replace function public.record_invoice_payment(
  p_invoice_id text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_note text default '',
  p_paid_at timestamptz default now()
)
returns public.invoice_payments
language plpgsql
as $$
declare
  v_branch_id uuid;
  v_total numeric;
  v_amount_paid numeric;
  v_payment public.invoice_payments;
begin
  perform public.require_writable_role();

  if p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  select branch_id, total, amount_paid into v_branch_id, v_total, v_amount_paid
  from public.invoices
  where id = p_invoice_id
  for update;

  if not found then
    raise exception 'Invoice % not found', p_invoice_id;
  end if;

  if p_amount > (v_total - v_amount_paid) + 0.01 then
    raise exception 'Payment of % exceeds the remaining balance of %', p_amount, v_total - v_amount_paid;
  end if;

  insert into public.invoice_payments (invoice_id, branch_id, amount, method, reference, note, paid_at)
  values (p_invoice_id, v_branch_id, p_amount, p_method, p_reference, p_note, p_paid_at)
  returning * into v_payment;

  update public.invoices
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_total - (v_amount_paid + p_amount), 0)
  where id = p_invoice_id;

  return v_payment;
end;
$$;

-- create_sale(): write-role guard upgraded, plus the real discount gate.
-- Manager: p_sale_discount_value/mode and every line's discount_value can be
-- anything (matches "applying discounts...everything"). Anyone else who
-- reaches this point is necessarily an Attendant (require_writable_role()
-- already rejected Accountant/Auditor): their whole-sale discount must be
-- zero, or must exactly match an active customer_discounts row for that
-- customer — never a typed-in amount — and every per-line discount must be
-- zero outright (POS's cart UI removes the free-text per-line input for
-- non-Managers to match; this is the server-side half so a direct RPC call
-- can't bypass what the UI hides).
create or replace function public.create_sale(
  p_branch_id uuid, p_customer_id uuid, p_customer_name text,
  p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text,
  p_lines jsonb, p_payments jsonb
) returns public.sales language plpgsql as $$
declare v_year_month text := to_char(now(), 'YYMM'); v_seq integer; v_id text; v_rate numeric; v_total numeric; v_paid numeric; v_cash numeric; v_non_cash numeric; v_sale public.sales; v_line jsonb; v_product public.products; v_payment jsonb;
begin
  perform public.require_writable_role();

  if p_sale_discount_mode not in ('amount', 'percent') or p_vat_mode not in ('per-item', 'all', 'none') then raise exception 'Invalid discount or VAT mode'; end if;

  if not public.has_role(array['Manager']) then
    if p_sale_discount_value <> 0 then
      if p_customer_id is null or not exists (
        select 1 from public.customer_discounts
        where customer_id = p_customer_id
          and mode = p_sale_discount_mode
          and value = p_sale_discount_value
          and active
      ) then
        raise exception 'Only a Manager can apply a discount that is not an active, customer-attached discount';
      end if;
    end if;

    if exists (
      select 1 from jsonb_array_elements(p_lines) as l
      where coalesce((l.value->>'discount_value')::numeric, 0) <> 0
    ) then
      raise exception 'Only a Manager can apply a per-item discount';
    end if;
  end if;

  select vat_rate into v_rate from public.business_settings where id = 1;
  v_total := public.compute_sale_total(p_lines, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate);
  select coalesce(sum((value->>'amount')::numeric), 0), coalesce(sum(case when value->>'method' = 'Cash' then (value->>'amount')::numeric else 0 end), 0), coalesce(sum(case when value->>'method' <> 'Cash' then (value->>'amount')::numeric else 0 end), 0) into v_paid, v_cash, v_non_cash from jsonb_array_elements(p_payments);
  if jsonb_array_length(p_payments) = 0 or v_paid < v_total - .01 or v_non_cash > v_total + .01 then raise exception 'Payments must cover the sale; only cash may exceed the total'; end if;
  for v_payment in select value from jsonb_array_elements(p_payments) loop
    if (v_payment->>'method') not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer') or coalesce((v_payment->>'amount')::numeric, 0) <= 0 then raise exception 'Invalid POS payment'; end if;
  end loop;
  -- Lock each product in stable UUID order before deducting it. The check and
  -- update happen while those row locks are held, so concurrent tills cannot oversell.
  for v_line in select value from jsonb_array_elements(p_lines) order by (value->>'product_id')::uuid loop
    select * into v_product from public.products where id = (v_line->>'product_id')::uuid and branch_id = p_branch_id for update;
    if not found then raise exception 'Product % is not available at this branch', v_line->>'product_id'; end if;
    if v_product.stock < (v_line->>'quantity')::integer then raise exception 'Insufficient stock for %', v_product.name; end if;
  end loop;
  insert into public.sale_number_counters(year_month, last_number) values(v_year_month, 1) on conflict(year_month) do update set last_number = sale_number_counters.last_number + 1 returning last_number into v_seq;
  v_id := 'POS-' || v_year_month || lpad(v_seq::text, 4, '0');
  insert into public.sales(id, branch_id, customer_id, customer_name, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total) values(v_id, p_branch_id, p_customer_id, p_customer_name, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate, v_total) returning * into v_sale;
  insert into public.sale_lines(sale_id, product_id, name, unit, category, quantity, unit_price, discount_mode, discount_value, vat, position)
  select v_id, (line->>'product_id')::uuid, line->>'name', line->>'unit', line->>'category', (line->>'quantity')::integer, (line->>'unit_price')::numeric, coalesce(line->>'discount_mode', 'amount'), coalesce((line->>'discount_value')::numeric, 0), coalesce((line->>'vat')::boolean, true), ord - 1 from jsonb_array_elements(p_lines) with ordinality as t(line, ord);
  for v_line in select value from jsonb_array_elements(p_lines) loop
    update public.products set stock = stock - (v_line->>'quantity')::integer where id = (v_line->>'product_id')::uuid returning * into v_product;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_product.id, p_branch_id, 'Sale', -(v_line->>'quantity')::integer, v_product.stock, v_id);
  end loop;
  insert into public.sale_payments(sale_id, branch_id, method, amount, reference) select v_id, p_branch_id, payment->>'method', (payment->>'amount')::numeric, coalesce(payment->>'reference', '') from jsonb_array_elements(p_payments) payment;
  return v_sale;
end; $$;

-- create_sale_return(): write-role guard upgraded, plus the one real
-- authorization gate this task asked for — a cash refund specifically
-- requires a Manager, no exceptions (section 5). Store credit, top-up and
-- even-exchange resolutions are untouched: an Attendant can complete any of
-- those alone. This is deliberately the whole of what's needed for now —
-- "requires Manager approval" here just means a Manager is the one who calls
-- this function; a proper in-session PIN-elevation flow that lets an
-- Attendant's own session get authorized without switching accounts is
-- Session 9's job, not this one's.
create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text
) returns public.sale_returns language plpgsql as $$
declare v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products; v_prior integer; v_difference numeric; v_return public.sale_returns;
begin
  perform public.require_writable_role();

  if p_resolution = 'Cash refund' and not public.has_role(array['Manager']) then
    raise exception 'A cash refund requires a Manager — store credit does not';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update; if not found then raise exception 'Sale % not found', p_sale_id; end if;
  select * into v_line from public.sale_lines where id = p_returned_sale_line_id and sale_id = p_sale_id for update; if not found then raise exception 'Sale line does not belong to this sale'; end if;
  select coalesce(sum(returned_quantity), 0) into v_prior from public.sale_returns where returned_sale_line_id = p_returned_sale_line_id;
  if p_returned_quantity <= 0 or p_returned_quantity + v_prior > v_line.quantity then raise exception 'Return quantity exceeds quantity sold'; end if;
  -- Lock both affected product rows in UUID order. This is the same
  -- check-then-adjust pattern as create_sale()/adjust_product_stock(), with a
  -- stable lock order so opposing exchanges cannot deadlock each other.
  perform 1 from public.products
  where id in (v_line.product_id, p_replacement_product_id)
  order by id for update;
  select * into v_returned from public.products where id = v_line.product_id;
  if p_replacement_product_id is not null then
    select * into v_replacement from public.products where id = p_replacement_product_id and branch_id = v_sale.branch_id;
    if not found or p_replacement_quantity is null or p_replacement_quantity <= 0 then raise exception 'Invalid replacement item'; end if;
    if v_replacement.stock < p_replacement_quantity then raise exception 'Insufficient stock for %', v_replacement.name; end if;
  end if;
  v_difference := round(coalesce(v_replacement.price * p_replacement_quantity, 0) - (v_line.unit_price * p_returned_quantity), 2);
  insert into public.sale_returns(sale_id, branch_id, returned_sale_line_id, returned_product_id, returned_name, returned_unit, returned_quantity, returned_unit_price, replacement_product_id, replacement_name, replacement_unit, replacement_quantity, replacement_unit_price, difference, resolution, approval_state, reason)
  values(p_sale_id, v_sale.branch_id, v_line.id, v_line.product_id, v_line.name, v_line.unit, p_returned_quantity, v_line.unit_price, p_replacement_product_id, v_replacement.name, v_replacement.unit, p_replacement_quantity, v_replacement.price, v_difference, p_resolution, p_approval_state, coalesce(p_reason, '')) returning * into v_return;
  update public.products set stock = stock + p_returned_quantity where id = v_returned.id returning * into v_returned;
  insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_returned.id, v_sale.branch_id, 'Return', p_returned_quantity, v_returned.stock, v_return.id::text);
  if p_replacement_product_id is not null then
    update public.products set stock = stock - p_replacement_quantity where id = v_replacement.id returning * into v_replacement;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_replacement.id, v_sale.branch_id, 'Sale', -p_replacement_quantity, v_replacement.stock, v_return.id::text || ' replacement');
  end if;
  return v_return;
end; $$;

-- create_expense(): Expenses isn't in Attendant's granted module list at
-- all (same reasoning as the table policies above), so this becomes
-- Manager-only outright, not just "not Accountant/Auditor".
create or replace function public.create_expense(
  p_branch_id uuid,
  p_date date,
  p_category text,
  p_description text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_receipt_path text default null
)
returns public.expenses
language plpgsql
as $$
declare
  v_id text;
  v_expense public.expenses;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record an expense';
  end if;

  v_id := 'EXP-' || nextval('public.expense_number_seq')::text;

  insert into public.expenses
    (id, branch_id, date, category, description, amount, method, reference, receipt_path)
  values
    (v_id, p_branch_id, p_date, p_category, p_description, p_amount, p_method, nullif(p_reference, ''), p_receipt_path)
  returning * into v_expense;

  return v_expense;
end;
$$;
