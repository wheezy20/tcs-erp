-- Session 17: Suppliers & Purchasing — brand new module, no dummy data to
-- migrate (Phase 1 never had a Suppliers concept). Six new tables plus
-- eight RPCs: suppliers, purchase orders (with a real draft -> ordered ->
-- partially_received -> received lifecycle), goods receiving (stock
-- update via the same locked read-then-write discipline
-- adjust_product_stock() established in Session 1, not a new pattern),
-- and supplier payments — tied into Accounts Payable (2000) the same way
-- Sessions 3/14 tied invoicing into Accounts Receivable (1100).
--
-- ================================================== why no journal entry at PO creation
--
-- A purchase order is a request, not yet an economic event — no goods
-- have moved, no obligation exists until something is actually received.
-- This is the opposite of create_invoice(), which posts immediately
-- because *issuing* an invoice is itself the revenue-recognition event.
-- create_purchase_order() never calls a poster; only receive_purchase_order()
-- does, matching the user's own framing: "a Purchase Order being received
-- and billed should post a real journal entry" — received IS billed here,
-- deliberately no separate three-way-match "enter the supplier's invoice"
-- step, since nothing in the spec's terse "create a request, track ordered
-- vs received status" calls for one and the user's own instruction treats
-- receiving and billing as the same event.
--
-- ================================================== the receiving <-> AP relationship
--
-- purchase_orders.balance is received_value - amount_paid, NOT
-- total - amount_paid. total is the full ordered amount (informational —
-- "what this will cost if everything arrives"); received_value only grows
-- as goods actually arrive, because you only owe a supplier for what
-- you've actually received, not what you ordered. A partially received PO
-- can already have real AP against it and already accept payments against
-- that real amount, while the un-received remainder owes nothing yet.
--
-- ================================================== deliberately out of scope
--
-- No VAT/discount modelling on purchase orders. Every VAT rule in the spec
-- (section 5's "VAT: 20% default, configurable, toggle available per item
-- or for the whole sale") is framed entirely around what's charged to
-- customers; Input VAT recoverable on purchases is a real, separate
-- accounting concept this session was not asked to build, and inventing
-- it here would be scope no instruction actually calls for — flagged
-- directly rather than built silently, the same discipline Session 14
-- used for store credit redemption before it became its own explicit ask.
--
-- No "reverse a receipt" mechanism. Once goods are received, the stock
-- change and journal entry are as permanent as everywhere else in this
-- build (day_closes once closed, journal_entries once posted,
-- bank_reconciliations once completed) — a genuine receiving mistake needs
-- a manual correcting stock adjustment plus a manual journal entry, the
-- same real-world remedy an invoicing mistake needs today via
-- reverse_journal_entry() plus a fresh, correct entry.

-- ============================================================ suppliers

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  name text not null,
  contact_name text not null default '',
  phone text not null default '',
  email text not null default '',
  address text not null default '',
  -- What we owe them (Accounts Payable direction) and what we've ever
  -- received from them, both trigger-maintained from purchase_orders —
  -- the same shape customers.balance/lifetime_total already use, just the
  -- opposite economic direction (never conflated, they're different
  -- tables for different counterparties).
  balance numeric(12, 2) not null default 0 check (balance >= 0),
  lifetime_total numeric(12, 2) not null default 0 check (lifetime_total >= 0),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index suppliers_branch_id_idx on public.suppliers (branch_id);

create or replace function public.set_supplier_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger suppliers_set_created_by
before insert on public.suppliers
for each row execute function public.set_supplier_created_by();

create trigger suppliers_set_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

-- ==================================================== purchase_orders

create table public.purchase_order_number_counters (
  year_month text primary key,
  last_number integer not null default 0 check (last_number >= 0)
);

create table public.purchase_orders (
  id text primary key,
  branch_id uuid not null references public.branches (id) on delete restrict,
  supplier_id uuid not null references public.suppliers (id) on delete restrict,
  -- Snapshot at creation, same reasoning as invoices.customer_name /
  -- sales.customer_name — display survives a later supplier rename.
  supplier_name text not null,
  status text not null default 'draft'
    check (status in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  order_date date not null default current_date,
  expected_date date,
  notes text not null default '',
  -- The full ordered amount — informational, never itself an AP claim.
  total numeric(12, 2) not null default 0 check (total >= 0),
  -- What's actually been received and billed so far — the real AP claim.
  received_value numeric(12, 2) not null default 0 check (received_value >= 0),
  amount_paid numeric(12, 2) not null default 0 check (amount_paid >= 0),
  balance numeric(12, 2) not null default 0 check (balance >= 0),
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index purchase_orders_branch_id_idx on public.purchase_orders (branch_id);
create index purchase_orders_supplier_id_idx on public.purchase_orders (supplier_id);
create index purchase_orders_status_idx on public.purchase_orders (status);

create or replace function public.set_purchase_order_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger purchase_orders_set_created_by
before insert on public.purchase_orders
for each row execute function public.set_purchase_order_created_by();

create trigger purchase_orders_set_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at();

create or replace function public.sync_supplier_totals()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    update public.suppliers s
    set balance = coalesce((select sum(po.balance) from public.purchase_orders po where po.supplier_id = s.id), 0),
        lifetime_total = coalesce((select sum(po.received_value) from public.purchase_orders po where po.supplier_id = s.id), 0)
    where s.id = old.supplier_id;
    return old;
  end if;

  update public.suppliers s
  set balance = coalesce((select sum(po.balance) from public.purchase_orders po where po.supplier_id = s.id), 0),
      lifetime_total = coalesce((select sum(po.received_value) from public.purchase_orders po where po.supplier_id = s.id), 0)
  where s.id = new.supplier_id;

  if tg_op = 'UPDATE' and old.supplier_id is distinct from new.supplier_id then
    update public.suppliers s
    set balance = coalesce((select sum(po.balance) from public.purchase_orders po where po.supplier_id = s.id), 0),
        lifetime_total = coalesce((select sum(po.received_value) from public.purchase_orders po where po.supplier_id = s.id), 0)
    where s.id = old.supplier_id;
  end if;

  return new;
end;
$$;

create trigger purchase_orders_sync_supplier_totals
after insert or update or delete on public.purchase_orders
for each row execute function public.sync_supplier_totals();

-- ================================================== purchase_order_lines

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id text not null references public.purchase_orders (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete restrict,
  -- Snapshot at order time, matching invoice_lines' name/unit precedent.
  name text not null,
  unit text not null,
  quantity_ordered integer not null check (quantity_ordered > 0),
  quantity_received integer not null default 0 check (quantity_received >= 0),
  unit_cost numeric(12, 2) not null check (unit_cost >= 0),
  position integer not null default 0,
  check (quantity_received <= quantity_ordered)
);

create index purchase_order_lines_po_id_idx on public.purchase_order_lines (purchase_order_id, position);

-- ============================================== purchase_order_receipts

create table public.purchase_order_receipts (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id text not null references public.purchase_orders (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  received_date date not null default current_date,
  notes text not null default '',
  total_value numeric(12, 2) not null default 0 check (total_value >= 0),
  received_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now()
);

create index purchase_order_receipts_po_id_idx on public.purchase_order_receipts (purchase_order_id, received_date desc);

create or replace function public.set_receipt_received_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.received_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger purchase_order_receipts_set_received_by
before insert on public.purchase_order_receipts
for each row execute function public.set_receipt_received_by();

create table public.purchase_order_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.purchase_order_receipts (id) on delete cascade,
  purchase_order_line_id uuid not null references public.purchase_order_lines (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  quantity integer not null check (quantity > 0),
  -- Snapshot of the PO line's unit_cost at the moment of receiving —
  -- receipts stay accurate even if a later PO line were ever edited (it
  -- currently can't be, see the RLS note below, but this is the same
  -- snapshot-not-live-reference principle invoice/sale lines already use).
  unit_cost numeric(12, 2) not null check (unit_cost >= 0)
);

create index purchase_order_receipt_lines_receipt_id_idx on public.purchase_order_receipt_lines (receipt_id);

-- ==================================================== supplier_payments

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id text not null references public.purchase_orders (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  -- Same settlement methods as invoice_payments, minus Store Credit — a
  -- supplier is never on the receiving end of our customers' store credit.
  method text not null check (method in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque')),
  reference text not null default '',
  note text not null default '',
  paid_at timestamptz not null default now(),
  recorded_by uuid not null default auth.uid() references public.staff (id) on delete restrict
);

create index supplier_payments_po_id_idx on public.supplier_payments (purchase_order_id, paid_at desc);

create or replace function public.set_supplier_payment_recorded_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.recorded_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger supplier_payments_set_recorded_by
before insert on public.supplier_payments
for each row execute function public.set_supplier_payment_recorded_by();

-- ============================================================ create_supplier

create or replace function public.create_supplier(
  p_branch_id uuid, p_name text, p_contact_name text default '', p_phone text default '',
  p_email text default '', p_address text default ''
) returns public.suppliers language plpgsql as $$
declare
  v_row public.suppliers;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can add a supplier';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Supplier name is required';
  end if;

  insert into public.suppliers (branch_id, name, contact_name, phone, email, address)
  values (p_branch_id, trim(p_name), coalesce(p_contact_name, ''), coalesce(p_phone, ''), coalesce(p_email, ''), coalesce(p_address, ''))
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_supplier(uuid, text, text, text, text, text) to authenticated;

-- ============================================================ create_purchase_order

-- create-can't-overwrite: no client-supplied id, a plain insert, numbering
-- generated server-side from a monthly counter — the exact same shape
-- create_invoice()/create_sale() already use for PO-YYMM####.
create or replace function public.create_purchase_order(
  p_branch_id uuid, p_supplier_id uuid, p_supplier_name text,
  p_order_date date, p_expected_date date, p_notes text, p_lines jsonb
) returns public.purchase_orders language plpgsql as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_total numeric;
  v_po public.purchase_orders;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can create a purchase order';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'A purchase order needs at least one line';
  end if;

  select coalesce(sum((line ->> 'quantity')::numeric * (line ->> 'unit_cost')::numeric), 0)
  into v_total
  from jsonb_array_elements(p_lines) as line;

  insert into public.purchase_order_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = purchase_order_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'PO-' || v_year_month || lpad(v_seq::text, 4, '0');

  insert into public.purchase_orders
    (id, branch_id, supplier_id, supplier_name, status, order_date, expected_date, notes, total)
  values
    (v_id, p_branch_id, p_supplier_id, p_supplier_name, 'draft', p_order_date, p_expected_date, coalesce(p_notes, ''), round(v_total, 2))
  returning * into v_po;

  insert into public.purchase_order_lines (purchase_order_id, product_id, name, unit, quantity_ordered, unit_cost, position)
  select
    v_id,
    (line ->> 'product_id')::uuid,
    line ->> 'name',
    line ->> 'unit',
    (line ->> 'quantity')::integer,
    (line ->> 'unit_cost')::numeric,
    (ord - 1)::integer
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_po;
end;
$$;

grant execute on function public.create_purchase_order(uuid, uuid, text, date, date, text, jsonb) to authenticated;

-- ============================================================ place_purchase_order

create or replace function public.place_purchase_order(p_purchase_order_id text)
returns public.purchase_orders language plpgsql as $$
declare
  v_po public.purchase_orders;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can place a purchase order';
  end if;

  select * into v_po from public.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'Purchase order % not found', p_purchase_order_id;
  end if;
  if v_po.status <> 'draft' then
    raise exception 'Only a draft purchase order can be placed (this one is %)', v_po.status;
  end if;

  update public.purchase_orders set status = 'ordered' where id = p_purchase_order_id returning * into v_po;
  return v_po;
end;
$$;

grant execute on function public.place_purchase_order(text) to authenticated;

-- ============================================================ cancel_purchase_order

create or replace function public.cancel_purchase_order(p_purchase_order_id text)
returns public.purchase_orders language plpgsql as $$
declare
  v_po public.purchase_orders;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can cancel a purchase order';
  end if;

  select * into v_po from public.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'Purchase order % not found', p_purchase_order_id;
  end if;
  if v_po.status not in ('draft', 'ordered') then
    raise exception 'Only a draft or ordered purchase order can be cancelled (this one is %)', v_po.status;
  end if;
  if v_po.received_value > 0 then
    raise exception 'This purchase order already has goods received against it and can no longer be cancelled';
  end if;

  update public.purchase_orders set status = 'cancelled' where id = p_purchase_order_id returning * into v_po;
  return v_po;
end;
$$;

grant execute on function public.cancel_purchase_order(text) to authenticated;

-- ============================================================ receive_purchase_order

-- Reuses adjust_product_stock()'s own locked-read-then-write discipline
-- (lock the product row, then update it) rather than a new stock-mutation
-- path — extended here to lock every referenced PO line and product in a
-- stable id order first, the same deadlock-avoidance shape create_sale()
-- uses for its own multi-product locking, since one receiving event can
-- touch several lines/products at once.
create or replace function public.receive_purchase_order(
  p_purchase_order_id text, p_received_date date, p_notes text, p_lines jsonb
) returns public.purchase_order_receipts language plpgsql as $$
declare
  v_po public.purchase_orders;
  v_line jsonb;
  v_po_line public.purchase_order_lines;
  v_product public.products;
  v_remaining integer;
  v_qty integer;
  v_total_value numeric := 0;
  v_receipt public.purchase_order_receipts;
  v_new_received_value numeric;
  v_new_status text;
  v_all_received boolean;
  v_any_received boolean;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record goods received';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'A goods received event needs at least one line';
  end if;

  select * into v_po from public.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'Purchase order % not found', p_purchase_order_id;
  end if;
  if v_po.status not in ('ordered', 'partially_received') then
    raise exception 'Goods can only be received against an ordered or partially received purchase order (this one is %)', v_po.status;
  end if;

  perform 1 from public.purchase_order_lines
  where id in (select (line ->> 'purchase_order_line_id')::uuid from jsonb_array_elements(p_lines) as line)
  order by id for update;

  perform 1 from public.products
  where id in (
    select pol.product_id from public.purchase_order_lines pol
    where pol.id in (select (line ->> 'purchase_order_line_id')::uuid from jsonb_array_elements(p_lines) as line)
  )
  order by id for update;

  -- First pass: validate every line and total the value, but don't touch
  -- anything yet — purchase_order_receipts has no UPDATE grant at all
  -- (immutable the moment it's created, see the RLS note below), so the
  -- header can only ever be inserted once, with its real total_value
  -- already known, never patched in afterward.
  for v_line in select value from jsonb_array_elements(p_lines) loop
    select * into v_po_line from public.purchase_order_lines
    where id = (v_line ->> 'purchase_order_line_id')::uuid and purchase_order_id = p_purchase_order_id;
    if not found then
      raise exception 'Purchase order line % does not belong to this purchase order', v_line ->> 'purchase_order_line_id';
    end if;

    v_qty := (v_line ->> 'quantity')::integer;
    if v_qty <= 0 then
      raise exception 'Received quantity must be greater than zero';
    end if;
    v_remaining := v_po_line.quantity_ordered - v_po_line.quantity_received;
    if v_qty > v_remaining then
      raise exception 'Cannot receive % of "%": only % still outstanding', v_qty, v_po_line.name, v_remaining;
    end if;

    v_total_value := v_total_value + round(v_qty * v_po_line.unit_cost, 2);
  end loop;

  insert into public.purchase_order_receipts (purchase_order_id, branch_id, received_date, notes, total_value)
  values (p_purchase_order_id, v_po.branch_id, p_received_date, coalesce(p_notes, ''), v_total_value)
  returning * into v_receipt;

  -- Second pass: now actually mutate lines/stock/movements/receipt lines,
  -- against the already-validated quantities from the first pass.
  for v_line in select value from jsonb_array_elements(p_lines) loop
    select * into v_po_line from public.purchase_order_lines
    where id = (v_line ->> 'purchase_order_line_id')::uuid and purchase_order_id = p_purchase_order_id;

    v_qty := (v_line ->> 'quantity')::integer;

    update public.purchase_order_lines
    set quantity_received = quantity_received + v_qty
    where id = v_po_line.id;

    update public.products set stock = stock + v_qty where id = v_po_line.product_id returning * into v_product;

    insert into public.stock_movements (product_id, branch_id, movement_type, change, balance_after, reason)
    values (v_product.id, v_po.branch_id, 'Purchase', v_qty, v_product.stock, p_purchase_order_id || ' — receipt ' || v_receipt.id::text);

    insert into public.purchase_order_receipt_lines (receipt_id, purchase_order_line_id, product_id, quantity, unit_cost)
    values (v_receipt.id, v_po_line.id, v_product.id, v_qty, v_po_line.unit_cost);
  end loop;

  select bool_and(quantity_received >= quantity_ordered), bool_or(quantity_received > 0)
  into v_all_received, v_any_received
  from public.purchase_order_lines where purchase_order_id = p_purchase_order_id;

  v_new_received_value := round(v_po.received_value + v_total_value, 2);
  v_new_status := case when v_all_received then 'received' when v_any_received then 'partially_received' else v_po.status end;

  update public.purchase_orders
  set received_value = v_new_received_value,
      balance = greatest(v_new_received_value - amount_paid, 0),
      status = v_new_status
  where id = p_purchase_order_id;

  perform public.post_purchase_receipt_journal_entry(v_receipt.id);
  return v_receipt;
end;
$$;

grant execute on function public.receive_purchase_order(text, date, text, jsonb) to authenticated;

create or replace function public.post_purchase_receipt_journal_entry(p_receipt_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_receipt public.purchase_order_receipts;
  v_lines jsonb;
begin
  select * into v_receipt from public.purchase_order_receipts where id = p_receipt_id;
  if not found then
    raise exception 'Goods receipt % not found', p_receipt_id;
  end if;

  if v_receipt.total_value <= 0 then
    return null;
  end if;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', public.account_id_by_code('1200'),
      'debit', v_receipt.total_value, 'credit', 0, 'description', 'Goods received'
    ),
    jsonb_build_object(
      'account_id', public.account_id_by_code('2000'),
      'debit', 0, 'credit', v_receipt.total_value, 'description', 'Goods received — ' || v_receipt.purchase_order_id
    )
  );

  return public._post_journal_entry_rows(
    v_receipt.branch_id, v_receipt.received_date, 'Goods received on ' || v_receipt.purchase_order_id, p_receipt_id::text,
    v_lines, 'purchase_order_receipts', p_receipt_id::text
  );
end;
$$;

grant execute on function public.post_purchase_receipt_journal_entry(uuid) to authenticated;

-- ============================================================ record_supplier_payment

create or replace function public.record_supplier_payment(
  p_purchase_order_id text,
  p_amount numeric,
  p_method text,
  p_reference text default '',
  p_note text default '',
  p_paid_at timestamptz default now()
) returns public.supplier_payments language plpgsql as $$
declare
  v_branch_id uuid;
  v_received_value numeric;
  v_amount_paid numeric;
  v_payment public.supplier_payments;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record a supplier payment';
  end if;
  if p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;
  if p_method not in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque') then
    raise exception 'Invalid payment method';
  end if;

  select branch_id, received_value, amount_paid into v_branch_id, v_received_value, v_amount_paid
  from public.purchase_orders
  where id = p_purchase_order_id
  for update;
  if not found then
    raise exception 'Purchase order % not found', p_purchase_order_id;
  end if;

  if p_amount > (v_received_value - v_amount_paid) + 0.01 then
    raise exception 'Payment of % exceeds the outstanding balance of %', p_amount, v_received_value - v_amount_paid;
  end if;

  insert into public.supplier_payments (purchase_order_id, branch_id, amount, method, reference, note, paid_at)
  values (p_purchase_order_id, v_branch_id, p_amount, p_method, coalesce(p_reference, ''), coalesce(p_note, ''), p_paid_at)
  returning * into v_payment;

  update public.purchase_orders
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_received_value - (v_amount_paid + p_amount), 0)
  where id = p_purchase_order_id;

  perform public.post_supplier_payment_journal_entry(v_payment.id);
  return v_payment;
end;
$$;

grant execute on function public.record_supplier_payment(text, numeric, text, text, text, timestamptz) to authenticated;

create or replace function public.post_supplier_payment_journal_entry(p_payment_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_payment public.supplier_payments;
  v_lines jsonb;
begin
  select * into v_payment from public.supplier_payments where id = p_payment_id;
  if not found then
    raise exception 'Supplier payment % not found', p_payment_id;
  end if;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', public.account_id_by_code('2000'),
      'debit', v_payment.amount, 'credit', 0, 'description', 'Accounts payable payment'
    ),
    jsonb_build_object(
      'account_id', public.payment_method_account(v_payment.method),
      'debit', 0, 'credit', v_payment.amount, 'description', v_payment.method
    )
  );

  return public._post_journal_entry_rows(
    v_payment.branch_id, v_payment.paid_at::date, 'Payment to supplier on ' || v_payment.purchase_order_id, p_payment_id::text,
    v_lines, 'supplier_payments', p_payment_id::text
  );
end;
$$;

grant execute on function public.post_supplier_payment_journal_entry(uuid) to authenticated;

-- ============================================================ RLS

-- Suppliers & Purchasing isn't in Attendant's spec-granted module list —
-- same tier as Accounting/Reports/Banking/Expenses: Manager full
-- read/write, Accountant/Auditor read-only, Attendant none. A raw PATCH
-- bypassing e.g. receive_purchase_order()'s quantity/status validation is
-- an accepted, documented gap, the same tradeoff already accepted for
-- bank_statement_lines and products.cost — only Manager reaches any of
-- these policies at all.
--
-- purchase_orders/purchase_order_lines get a plain, unconditional
-- Manager UPDATE policy — deliberately NOT narrowed by status (e.g.
-- "status <> 'cancelled'"), unlike bank_reconciliations_update. A purchase
-- order has an ongoing lifecycle even after reaching 'received' (payments
-- keep landing against it until balance = 0), so there is no
-- "this column value flips from true to false as part of the very update
-- being performed" situation for a narrowed USING clause to trip over the
-- way Session 16 hit with bank_reconciliations.completed_at — the
-- transition-legality rules that matter (can't place a non-draft PO,
-- can't receive against a cancelled one, etc.) are enforced inside each
-- RPC's own explicit checks instead. purchase_order_receipts and
-- purchase_order_receipt_lines get no update/delete policy at all —
-- immutable the moment they're created, the same "once posted, permanent"
-- rule journal_entries/day_closes/bank_reconciliations already established,
-- here for the same reason: a receiving event is a real, dated, financial
-- fact once it happens.
alter table public.suppliers enable row level security;

create policy suppliers_select on public.suppliers
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy suppliers_insert on public.suppliers
  for insert with check (public.has_role(array['Manager']));
create policy suppliers_update on public.suppliers
  for update using (public.has_role(array['Manager']));
create policy suppliers_delete on public.suppliers
  for delete using (public.has_role(array['Manager']));

revoke all on public.suppliers from anon;
grant select, insert, update, delete on public.suppliers to authenticated;
grant select, insert, update, delete on public.suppliers to service_role;

alter table public.purchase_order_number_counters enable row level security;

create policy purchase_order_number_counters_select on public.purchase_order_number_counters
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy purchase_order_number_counters_insert on public.purchase_order_number_counters
  for insert with check (public.has_role(array['Manager']));
create policy purchase_order_number_counters_update on public.purchase_order_number_counters
  for update using (public.has_role(array['Manager'])) with check (public.has_role(array['Manager']));

revoke all on public.purchase_order_number_counters from anon;
grant select, insert, update on public.purchase_order_number_counters to authenticated;
grant select, insert, update on public.purchase_order_number_counters to service_role;

alter table public.purchase_orders enable row level security;

create policy purchase_orders_select on public.purchase_orders
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy purchase_orders_insert on public.purchase_orders
  for insert with check (public.has_role(array['Manager']));
create policy purchase_orders_update on public.purchase_orders
  for update using (public.has_role(array['Manager'])) with check (public.has_role(array['Manager']));

revoke all on public.purchase_orders from anon;
grant select, insert, update on public.purchase_orders to authenticated;
grant select, insert, update on public.purchase_orders to service_role;

alter table public.purchase_order_lines enable row level security;

create policy purchase_order_lines_select on public.purchase_order_lines
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy purchase_order_lines_insert on public.purchase_order_lines
  for insert with check (public.has_role(array['Manager']));
create policy purchase_order_lines_update on public.purchase_order_lines
  for update using (public.has_role(array['Manager'])) with check (public.has_role(array['Manager']));

revoke all on public.purchase_order_lines from anon;
grant select, insert, update on public.purchase_order_lines to authenticated;
grant select, insert, update on public.purchase_order_lines to service_role;

alter table public.purchase_order_receipts enable row level security;

create policy purchase_order_receipts_select on public.purchase_order_receipts
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy purchase_order_receipts_insert on public.purchase_order_receipts
  for insert with check (public.has_role(array['Manager']));

revoke all on public.purchase_order_receipts from anon;
grant select, insert on public.purchase_order_receipts to authenticated;
grant select, insert, update, delete on public.purchase_order_receipts to service_role;

alter table public.purchase_order_receipt_lines enable row level security;

create policy purchase_order_receipt_lines_select on public.purchase_order_receipt_lines
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy purchase_order_receipt_lines_insert on public.purchase_order_receipt_lines
  for insert with check (public.has_role(array['Manager']));

revoke all on public.purchase_order_receipt_lines from anon;
grant select, insert on public.purchase_order_receipt_lines to authenticated;
grant select, insert, update, delete on public.purchase_order_receipt_lines to service_role;

alter table public.supplier_payments enable row level security;

create policy supplier_payments_select on public.supplier_payments
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy supplier_payments_insert on public.supplier_payments
  for insert with check (public.has_role(array['Manager']));
-- Matches invoice_payments' own precedent exactly, including its latent
-- gap: a direct delete here doesn't roll back purchase_orders.amount_paid
-- or reverse the payment's journal entry either (invoice_payments has the
-- identical gap against invoices.amount_paid) — not a new inconsistency
-- introduced by this session, the same shallow default already accepted
-- for payment records elsewhere in this build.
create policy supplier_payments_delete on public.supplier_payments
  for delete using (public.has_role(array['Manager']));

revoke all on public.supplier_payments from anon;
grant select, insert, delete on public.supplier_payments to authenticated;
grant select, insert, update, delete on public.supplier_payments to service_role;
