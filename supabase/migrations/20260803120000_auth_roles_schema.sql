-- Authentication & Roles (Phase 1.5, Session 7).
--
-- Two things happen in this migration, and they're deliberately coupled:
--   1. Real Supabase Auth + a `staff` table with three roles (Attendant,
--      Manager, Accountant/Auditor), and every free-text "who did this"
--      column flagged since Session 1 (stock_movements.performed_by,
--      invoices.issued_by, invoice_payments.recorded_by, expenses.recorded_by,
--      sales.cashier) converted to a real foreign key against it. sale_returns
--      never had a "who processed this" column at all — create_sale_return()
--      hardcoded 'System' — so one is added here too (processed_by), closing
--      that gap rather than leaving it as a text column with nothing to convert.
--   2. RLS, enabled now that real roles exist to write policies against. Not
--      fully locked down (that's Session 9, once Manager PIN exists for
--      step-up authorization on the sensitive stuff) — every authenticated,
--      active staff member can read/write the normal operational tables
--      regardless of role, matching today's de-facto access exactly. The one
--      restriction that doesn't need any deeper business-rule knowledge to
--      justify: DELETE is Manager/Accountant-Auditor only, everywhere.
--
-- The identity columns above are NOT client-supplied parameters, on any
-- table, in any function, from this point on. Every one of them is set by a
-- BEFORE INSERT trigger that overwrites whatever the client sent with
-- auth.uid() unconditionally — the same "server decides, client can't
-- override" discipline every prior session applied to totals and record
-- ids, extended here to identity. This closes a gap none of those sessions
-- had to think about: a table with plain `grant insert` is writable directly
-- via PostgREST, not just through the RPCs built for it (addProduct()/
-- addProducts() in inventory-store.ts insert into stock_movements directly,
-- bypassing adjust_product_stock() entirely) — a trigger is the only place
-- that closes the gap for every insert path at once, RPC or direct.

-- ============================================================ staff table

create table public.staff (
  -- References auth.users directly rather than having its own surrogate key:
  -- a staff row *is* a login, one-to-one, not a separate profile that could
  -- drift out of sync with one.
  id uuid primary key references auth.users (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete restrict,
  name text not null,
  email text not null,
  role text not null check (role in ('Attendant', 'Manager', 'Accountant/Auditor')),
  -- Deactivating is the only "removal" path this app exposes. Historical
  -- records (stock_movements.performed_by, invoices.issued_by, ...) all
  -- reference staff with `on delete restrict`, so a staff row can never
  -- actually be deleted while it's the "who" on any real business record —
  -- the audit trail must never lose its subject. active=false is how a
  -- departed staff member stops being able to sign in and stops appearing
  -- as a choice for new records, without erasing what they already did.
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index staff_branch_id_idx on public.staff (branch_id);

create trigger staff_set_updated_at
before update on public.staff
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------- helper functions

-- security definer on all three functions below is load-bearing, not
-- incidental: the SELECT policy on public.staff itself calls
-- is_active_staff() (see the RLS section further down) — if these functions
-- ran with the caller's own privileges, evaluating that policy would call
-- is_active_staff(), which queries staff, which re-evaluates the same SELECT
-- policy, which calls is_active_staff() again — infinite recursion ("stack
-- depth limit exceeded"), caught by testing this migration directly against
-- the RPCs before trusting it, not by reasoning alone. security definer
-- makes their own internal lookup bypass RLS on staff entirely, breaking the
-- cycle. Still safe: each one only ever reads the CALLING user's own row
-- (always scoped to auth.uid()) and returns a boolean or that single row,
-- never arbitrary data belonging to other staff.
create or replace function public.is_active_staff()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from public.staff where id = auth.uid() and active);
$$;

create or replace function public.has_role(p_roles text[])
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.staff where id = auth.uid() and active and role = any (p_roles)
  );
$$;

-- Used inside the RPCs (create_invoice(), create_sale(), ...) as an early,
-- clearly-worded check. RLS on the underlying tables would catch an
-- unauthenticated/inactive caller regardless — "Not signed in as an active
-- staff member" is just a far more useful error than whatever generic denial
-- message falling through to the first blocked INSERT would produce.
create or replace function public.require_staff()
returns public.staff
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_staff public.staff;
begin
  select * into v_staff from public.staff where id = auth.uid() and active;
  if not found then
    raise exception 'Not signed in as an active staff member';
  end if;
  return v_staff;
end;
$$;

-- ------------------------------------------------- signup -> staff row

-- The only way a staff row is ever created: signing up (supabase.auth.signUp())
-- inserts into auth.users, and this trigger mirrors it into public.staff.
-- There is deliberately no INSERT policy on public.staff for authenticated
-- users (see the RLS section below) — going through auth.users, not a direct
-- table write, is the only path, and security definer is what lets this
-- trigger write to public.staff before the new user could possibly pass an
-- is_active_staff() check on themselves.
--
-- Role is never read from the client-supplied signup metadata: raw_user_meta_data
-- is caller-controlled input (anyone signing up could put anything in it), so
-- trusting a self-reported "role": "Manager" would be a privilege-escalation
-- hole. Every new signup becomes an Attendant, except the very first one ever
-- (bootstrapping the first Manager so someone can promote everyone else) —
-- every role change after that has to go through an existing Manager in the
-- Staff settings screen, which is a real is_active_staff()-gated app action,
-- not free-form signup input.
create or replace function public.handle_new_staff_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_role text;
begin
  select id into v_branch_id from public.branches order by created_at limit 1;

  v_role := case when not exists (select 1 from public.staff) then 'Manager' else 'Attendant' end;

  insert into public.staff (id, branch_id, name, email, role)
  values (
    new.id,
    v_branch_id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)),
    new.email,
    v_role
  );

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_staff_signup();

-- ------------------------------------------- identity-forcing triggers

-- One function per distinct column name (recorded_by is shared by
-- invoice_payments and expenses — same column name, same logic). Each is a
-- BEFORE INSERT trigger, which runs (and can rewrite NEW) before RLS's WITH
-- CHECK is evaluated on the same statement, so ordering is never a problem.
--
-- Only overrides when auth.uid() is actually non-null. That's not a hole:
-- every real app request goes through PostgREST as `authenticated`, where
-- RLS's is_active_staff() check already requires a non-null auth.uid() to
-- insert at all — a logged-in client can never reach the "leave it alone"
-- branch below. The branch exists for the one context that legitimately has
-- no JWT at all: migrations/seed.sql, which run as the postgres superuser
-- and bypass RLS entirely regardless of what this trigger does. Without it,
-- seed.sql couldn't attribute historical rows to specific seeded staff — a
-- superuser session has no auth.uid() to force onto NEW, and the column is
-- NOT NULL with no default to silently fall back on.
create or replace function public.set_performed_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.performed_by := auth.uid(); end if;
  return new;
end;
$$;

create or replace function public.set_issued_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.issued_by := auth.uid(); end if;
  return new;
end;
$$;

create or replace function public.set_recorded_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.recorded_by := auth.uid(); end if;
  return new;
end;
$$;

create or replace function public.set_cashier()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.cashier := auth.uid(); end if;
  return new;
end;
$$;

create or replace function public.set_processed_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.processed_by := auth.uid(); end if;
  return new;
end;
$$;

-- ============================================== convert "who" columns to FKs

-- Every table this touches is rebuilt from migrations + seed.sql on every
-- `db reset` (this project has never needed to preserve data across a schema
-- change) — so these are plain drop-and-recreate, not data-preserving ALTERs.
-- seed.sql is updated in the same commit to insert real staff uuids instead
-- of the free-text names it used before.

-- `default auth.uid()` on every one of these columns exists purely so the
-- frontend can omit them from its insert/RPC payloads (and so the generated
-- TypeScript Insert types mark them optional) — it is NOT the security
-- boundary. A default only fills in a value the client left out; a client
-- that explicitly sends someone else's uuid would sail right past it. The
-- BEFORE INSERT triggers below are what actually enforce identity: they
-- unconditionally overwrite the column with auth.uid() whenever there is an
-- authenticated caller, so the default and the trigger always agree, and
-- spoofing is blocked either way.
alter table public.stock_movements drop column performed_by;
alter table public.stock_movements
  add column performed_by uuid not null default auth.uid() references public.staff (id) on delete restrict;

create trigger stock_movements_set_performed_by
before insert on public.stock_movements
for each row execute function public.set_performed_by();

alter table public.invoices drop column issued_by;
alter table public.invoices
  add column issued_by uuid not null default auth.uid() references public.staff (id) on delete restrict;

create trigger invoices_set_issued_by
before insert on public.invoices
for each row execute function public.set_issued_by();

alter table public.invoice_payments drop column recorded_by;
alter table public.invoice_payments
  add column recorded_by uuid not null default auth.uid() references public.staff (id) on delete restrict;

create trigger invoice_payments_set_recorded_by
before insert on public.invoice_payments
for each row execute function public.set_recorded_by();

alter table public.expenses drop column recorded_by;
alter table public.expenses
  add column recorded_by uuid not null default auth.uid() references public.staff (id) on delete restrict;

create trigger expenses_set_recorded_by
before insert on public.expenses
for each row execute function public.set_recorded_by();

alter table public.sales drop column cashier;
alter table public.sales
  add column cashier uuid not null default auth.uid() references public.staff (id) on delete restrict;

create trigger sales_set_cashier
before insert on public.sales
for each row execute function public.set_cashier();

-- New column — sale_returns never had a "who processed this" field before;
-- create_sale_return() hardcoded 'System' for the stock_movements rows it
-- wrote, with no way to attribute a return to a real person at all.
alter table public.sale_returns
  add column processed_by uuid not null default auth.uid() references public.staff (id) on delete restrict;

create trigger sale_returns_set_processed_by
before insert on public.sale_returns
for each row execute function public.set_processed_by();

-- ==================================================== RPC signature changes

-- adjust_product_stock(): drop p_performed_by. The trigger on
-- stock_movements sets it from auth.uid() regardless of what this function's
-- INSERT statement does or doesn't specify.
drop function if exists public.adjust_product_stock(uuid, integer, text, text);

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
  perform public.require_staff();

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

grant execute on function public.adjust_product_stock(uuid, integer, text) to authenticated;

-- create_invoice(): drop p_issued_by. invoices_set_issued_by trigger owns it.
drop function if exists public.create_invoice(uuid, uuid, text, date, date, text, text, numeric, jsonb);

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
  perform public.require_staff();

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

grant execute on function public.create_invoice(uuid, uuid, text, date, date, text, numeric, jsonb) to authenticated;

-- update_invoice(): drop p_issued_by AND stop setting issued_by in the SET
-- clause. Session 3's version let every edit silently reassign who "issued"
-- the invoice to whatever the client sent (never noticed because the client
-- always just resent the existing value) — now that issued_by is a real
-- identity, that's exactly the kind of authorship-reassignment editing
-- shouldn't be able to do, the same principle that already kept vat_rate
-- fixed after an invoice was issued.
drop function if exists public.update_invoice(text, uuid, uuid, text, date, date, text, text, numeric, jsonb);

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
  perform public.require_staff();

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

grant execute on function public.update_invoice(text, uuid, uuid, text, date, date, text, numeric, jsonb) to authenticated;

-- record_invoice_payment(): drop p_recorded_by.
drop function if exists public.record_invoice_payment(text, numeric, text, text, text, text, timestamptz);

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
  perform public.require_staff();

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

grant execute on function public.record_invoice_payment(text, numeric, text, text, text, timestamptz) to authenticated;

-- create_sale(): drop p_cashier.
drop function if exists public.create_sale(uuid, uuid, text, text, text, numeric, text, jsonb, jsonb);

create or replace function public.create_sale(
  p_branch_id uuid, p_customer_id uuid, p_customer_name text,
  p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text,
  p_lines jsonb, p_payments jsonb
) returns public.sales language plpgsql as $$
declare v_year_month text := to_char(now(), 'YYMM'); v_seq integer; v_id text; v_rate numeric; v_total numeric; v_paid numeric; v_cash numeric; v_non_cash numeric; v_sale public.sales; v_line jsonb; v_product public.products; v_payment jsonb;
begin
  perform public.require_staff();

  if p_sale_discount_mode not in ('amount', 'percent') or p_vat_mode not in ('per-item', 'all', 'none') then raise exception 'Invalid discount or VAT mode'; end if;
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

grant execute on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb) to authenticated;

-- create_sale_return(): no parameter changes (it never had a p_performed_by),
-- but its two stock_movements inserts drop the hardcoded 'System' literal
-- (the trigger sets performed_by now) and the new sale_returns.processed_by
-- column is likewise left for its own trigger to fill in.
create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text
) returns public.sale_returns language plpgsql as $$
declare v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products; v_prior integer; v_difference numeric; v_return public.sale_returns;
begin
  perform public.require_staff();

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

grant execute on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text) to authenticated;

-- create_expense(): drop p_recorded_by.
drop function if exists public.create_expense(uuid, date, text, text, numeric, text, text, text, text);

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
  perform public.require_staff();

  v_id := 'EXP-' || nextval('public.expense_number_seq')::text;

  insert into public.expenses
    (id, branch_id, date, category, description, amount, method, reference, receipt_path)
  values
    (v_id, p_branch_id, p_date, p_category, p_description, p_amount, p_method, nullif(p_reference, ''), p_receipt_path)
  returning * into v_expense;

  return v_expense;
end;
$$;

grant execute on function public.create_expense(uuid, date, text, text, numeric, text, text, text) to authenticated;

-- ============================================================ staff writes

-- Managers can promote/demote/deactivate; the app has no separate "edit my
-- own profile" affordance yet, so self-service isn't wired up (a Manager can
-- always do it for someone, including themselves). No insert policy at all —
-- signup (the trigger above) is the only creation path. No delete policy —
-- deactivate via UPDATE active=false instead, per the on-delete-restrict
-- reasoning on the table itself.
alter table public.staff enable row level security;

create policy staff_select on public.staff
for select
using (public.is_active_staff());

create policy staff_update on public.staff
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

grant select, update on public.staff to authenticated;
grant execute on function public.is_active_staff() to authenticated;
grant execute on function public.has_role(text[]) to authenticated;
grant execute on function public.require_staff() to authenticated;

-- ================================================================ RLS: rest

-- Every remaining operational table gets the same four policies: any active
-- staff member (any role) can select/insert/update, matching what anon+the
-- app already did de facto; only Manager/Accountant-Auditor can delete. This
-- is deliberately not a deep permission matrix — see the migration header —
-- just a real, auth.uid()-backed floor for Sessions 8-9 to build on instead
-- of retrofitting.
do $$
declare
  t text;
  tables text[] := array[
    'branches', 'products', 'stock_movements',
    'customers',
    'invoices', 'invoice_lines', 'invoice_payments', 'invoice_number_counters',
    'sales', 'sale_lines', 'sale_payments', 'sale_returns', 'sale_number_counters',
    'expenses', 'expense_categories'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I_select on public.%I for select using (public.is_active_staff())', t, t);
    execute format('create policy %I_insert on public.%I for insert with check (public.is_active_staff())', t, t);
    execute format('create policy %I_update on public.%I for update using (public.is_active_staff()) with check (public.is_active_staff())', t, t);
    execute format('create policy %I_delete on public.%I for delete using (public.has_role(array[''Manager'', ''Accountant/Auditor'']))', t, t);
  end loop;
end;
$$;

-- business_settings: every active staff member can read it (create_sale()/
-- create_invoice() need it, and so does the frontend directly, per Session 3),
-- but only Manager/Accountant-Auditor can change the VAT rate.
alter table public.business_settings enable row level security;

create policy business_settings_select on public.business_settings
for select
using (public.is_active_staff());

create policy business_settings_update on public.business_settings
for update
using (public.has_role(array['Manager', 'Accountant/Auditor']))
with check (public.has_role(array['Manager', 'Accountant/Auditor']));

grant select, update on public.business_settings to authenticated;

-- =================================================================== grants

-- Revoke anon from every business table now that real login exists — this is
-- the whole point of this session's RLS work: today, anyone holding the anon
-- key (which is not a secret; it ships in the client bundle) can read and
-- write everything. After this migration, only an authenticated, active
-- staff session can. `anon` keeps no table access at all from here on.
revoke all on public.branches, public.products, public.stock_movements,
  public.customers,
  public.invoices, public.invoice_lines, public.invoice_payments, public.invoice_number_counters,
  public.sales, public.sale_lines, public.sale_payments, public.sale_returns, public.sale_number_counters,
  public.expenses, public.expense_categories,
  public.business_settings, public.staff
from anon;

grant select, insert, update, delete on public.branches, public.products, public.stock_movements,
  public.customers,
  public.invoices, public.invoice_lines, public.invoice_payments,
  public.sales, public.sale_lines, public.sale_payments, public.sale_returns,
  public.expenses, public.expense_categories
to authenticated;
grant select, insert, update on public.invoice_number_counters, public.sale_number_counters to authenticated;

revoke all on function public.adjust_product_stock(uuid, integer, text) from anon;
revoke all on function public.create_invoice(uuid, uuid, text, date, date, text, numeric, jsonb) from anon;
revoke all on function public.update_invoice(text, uuid, uuid, text, date, date, text, numeric, jsonb) from anon;
revoke all on function public.record_invoice_payment(text, numeric, text, text, text, timestamptz) from anon;
revoke all on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb) from anon;
revoke all on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text) from anon;
revoke all on function public.create_expense(uuid, date, text, text, numeric, text, text, text) from anon;
revoke all on function public.compute_invoice_total(jsonb, numeric, numeric) from anon;
revoke all on function public.compute_sale_total(jsonb, text, numeric, text, numeric) from anon;
revoke all on function public.set_expense_categories(uuid, text[]) from anon;
grant execute on function public.set_expense_categories(uuid, text[]) to authenticated;
grant execute on function public.compute_invoice_total(jsonb, numeric, numeric) to authenticated;
grant execute on function public.compute_sale_total(jsonb, text, numeric, text, numeric) to authenticated;

revoke usage on sequence public.expense_number_seq from anon;
grant usage on sequence public.expense_number_seq to authenticated;

-- The receipts storage bucket follows the same anon-lockout: only signed-in
-- staff can upload/list/delete receipt photos from here on. The `public`
-- bucket flag is untouched (still lets <img src> read a receipt without a
-- signed URL, per the Session 4 reasoning — that's about downloads, this
-- policy is about uploads/deletes, same distinction as before).
drop policy if exists "receipts_full_access" on storage.objects;

create policy "receipts_staff_access" on storage.objects
for all
to authenticated
using (bucket_id = 'receipts')
with check (bucket_id = 'receipts');
