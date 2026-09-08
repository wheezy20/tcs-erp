-- Sales & Invoicing schema (Phase 1.5, Session 3).
-- Replaces the in-memory dummy invoices in frontend/src/data/invoices.ts /
-- sales-store.ts with real tables, and resolves two open questions Sessions
-- 1 and 2 deliberately left for this session:
--   1. Whether customer_payments (Session 2) or per-invoice payments become
--      the real payments ledger. Answer: invoice_payments. customer_payments
--      is dropped — nothing ever wrote to it (the customer profile page's
--      "Record payment" button was always inert), and a customer's payment
--      history is better derived by joining through their invoices, exactly
--      like order history already was designed to be.
--   2. How Product.stock's "plain stored column" pattern extends to
--      Customer.balance / lifetime_total now that real invoices exist.
--      Answer: keep them as stored columns (cheap to read for list views),
--      but maintain them with a trigger instead of an explicit RPC, because
--      unlike stock (one write path: adjustStock), invoices have several
--      write paths (create, edit, record payment, bulk import) and a
--      trigger can't be forgotten by a future call site the way a
--      "remember to call the sync function" convention could be.

drop table if exists public.customer_payments;

create table public.invoices (
  -- Invoice numbers are a human-facing sequential business identifier (used
  -- in URLs, print/export, and spoken about with customers), not a surrogate
  -- key, so this is text ("INV-2431"), not the uuid convention used for
  -- products/customers.
  id text primary key,
  branch_id uuid not null references public.branches (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  -- Snapshot of the customer's name at issue time, matching real invoicing
  -- practice (a later name change shouldn't rewrite historical invoices).
  customer_name text not null,
  date date not null,
  due_date date not null,
  -- free text until Phase 1.5 Session 7 (staff logins/roles) lands, same
  -- rationale as stock_movements.performed_by / customers is missing here
  -- because customer_payments (which had recorded_by) is gone; the pattern
  -- continues via invoice_payments.recorded_by below.
  issued_by text not null default 'System',
  notes text not null default '',
  invoice_discount numeric(12, 2) not null default 0 check (invoice_discount >= 0),
  vat_rate numeric(5, 2) not null default 20 check (vat_rate >= 0),
  -- total/amount_paid/balance are maintained by save_invoice() and
  -- record_invoice_payment() below, not recomputed by a trigger from line
  -- items: the VAT/discount math (per-line VAT flags, discount capping,
  -- proportional VAT base) already lives correctly in
  -- frontend/src/data/invoices.ts's invoiceTotals(), and duplicating that in
  -- SQL would just be a second implementation to keep in sync. The client
  -- computes `total` with the existing function and passes it in; the
  -- database only ever does the simple arithmetic (total - paid).
  total numeric(12, 2) not null default 0 check (total >= 0),
  amount_paid numeric(12, 2) not null default 0 check (amount_paid >= 0),
  balance numeric(12, 2) not null default 0 check (balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index invoices_branch_id_idx on public.invoices (branch_id);
create index invoices_customer_id_idx on public.invoices (customer_id);

create trigger invoices_set_updated_at
before update on public.invoices
for each row execute function public.set_updated_at();

create table public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id text not null references public.invoices (id) on delete cascade,
  -- nullable: some lines aren't inventory items (e.g. "Installation labour")
  product_id uuid references public.products (id) on delete set null,
  name text not null,
  unit text not null,
  -- numeric rather than integer: unlike stock counts, a sold quantity can be
  -- fractional (e.g. 2.5 metres of skirting sold off a longer length)
  quantity numeric(12, 2) not null check (quantity > 0),
  unit_price numeric(12, 2) not null default 0 check (unit_price >= 0),
  discount numeric(12, 2) not null default 0 check (discount >= 0),
  vat boolean not null default true,
  -- preserves the original line order (frontend showed "Item 1", "Item 2", ...)
  position integer not null default 0
);

create index invoice_lines_invoice_id_idx on public.invoice_lines (invoice_id, position);

create table public.invoice_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id text not null references public.invoices (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  method text not null check (method in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque')),
  reference text not null default '',
  note text not null default '',
  recorded_by text not null default 'System',
  paid_at timestamptz not null default now()
);

create index invoice_payments_invoice_id_idx on public.invoice_payments (invoice_id, paid_at desc);

-- Recomputes a customer's balance/lifetime_total by summing across all of
-- their invoices, whenever an invoice is inserted, updated (including
-- reassigned to a different customer), or deleted. Using a trigger rather
-- than requiring every write path to remember to call a sync function.
create or replace function public.sync_customer_totals()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    update public.customers c
    set balance = coalesce((select sum(i.balance) from public.invoices i where i.customer_id = c.id), 0),
        lifetime_total = coalesce((select sum(i.total) from public.invoices i where i.customer_id = c.id), 0)
    where c.id = old.customer_id;
    return old;
  end if;

  update public.customers c
  set balance = coalesce((select sum(i.balance) from public.invoices i where i.customer_id = c.id), 0),
      lifetime_total = coalesce((select sum(i.total) from public.invoices i where i.customer_id = c.id), 0)
  where c.id = new.customer_id;

  if tg_op = 'UPDATE' and old.customer_id is distinct from new.customer_id then
    update public.customers c
    set balance = coalesce((select sum(i.balance) from public.invoices i where i.customer_id = c.id), 0),
        lifetime_total = coalesce((select sum(i.total) from public.invoices i where i.customer_id = c.id), 0)
    where c.id = old.customer_id;
  end if;

  return new;
end;
$$;

create trigger invoices_sync_customer_totals
after insert or update or delete on public.invoices
for each row execute function public.sync_customer_totals();

-- Atomically replaces an invoice's header + line items (create or edit).
-- `p_total` is computed client-side by invoiceTotals() (see comment on
-- invoices.total above) — this function trusts it and only does simple
-- arithmetic (balance = total - amount_paid), never re-derives VAT/discounts.
create or replace function public.save_invoice(
  p_id text,
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_issued_by text,
  p_notes text,
  p_invoice_discount numeric,
  p_vat_rate numeric,
  p_total numeric,
  p_lines jsonb
)
returns public.invoices
language plpgsql
as $$
declare
  v_invoice public.invoices;
begin
  insert into public.invoices
    (id, branch_id, customer_id, customer_name, date, due_date, issued_by, notes, invoice_discount, vat_rate, total, amount_paid, balance)
  values
    (p_id, p_branch_id, p_customer_id, p_customer_name, p_date, p_due_date, p_issued_by, p_notes, p_invoice_discount, p_vat_rate, p_total, 0, p_total)
  on conflict (id) do update set
    branch_id = excluded.branch_id,
    customer_id = excluded.customer_id,
    customer_name = excluded.customer_name,
    date = excluded.date,
    due_date = excluded.due_date,
    issued_by = excluded.issued_by,
    notes = excluded.notes,
    invoice_discount = excluded.invoice_discount,
    vat_rate = excluded.vat_rate,
    total = excluded.total;
  -- amount_paid is intentionally untouched above (editing line items doesn't
  -- change what's already been paid); balance is recomputed against it next.

  update public.invoices set balance = greatest(total - amount_paid, 0) where id = p_id;

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

  select * into v_invoice from public.invoices where id = p_id;
  return v_invoice;
end;
$$;

-- Atomically logs a payment against an invoice and updates its
-- amount_paid/balance in the same transaction — same discipline as
-- adjust_product_stock() in the inventory migration (row-locked, one
-- audit-row insert + one parent-row update).
create or replace function public.record_invoice_payment(
  p_invoice_id text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_note text default '',
  p_recorded_by text default 'System',
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

  insert into public.invoice_payments (invoice_id, branch_id, amount, method, reference, note, recorded_by, paid_at)
  values (p_invoice_id, v_branch_id, p_amount, p_method, p_reference, p_note, p_recorded_by, p_paid_at)
  returning * into v_payment;

  update public.invoices
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_total - (v_amount_paid + p_amount), 0)
  where id = p_invoice_id;

  return v_payment;
end;
$$;

-- RLS is intentionally left off, same as the inventory and customers
-- migrations — no auth/staff table yet (Phase 1.5 Session 7).
grant select, insert, update, delete on public.invoices to anon, authenticated;
grant select, insert, update, delete on public.invoice_lines to anon, authenticated;
grant select, insert, update, delete on public.invoice_payments to anon, authenticated;
grant execute on function public.save_invoice(text, uuid, uuid, text, date, date, text, text, numeric, numeric, numeric, jsonb) to anon, authenticated;
grant execute on function public.record_invoice_payment(text, numeric, text, text, text, text, timestamptz) to anon, authenticated;
