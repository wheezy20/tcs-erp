-- POS Hold/Park Sale — a draft, not an economic event, the same principle
-- pro_forma_invoices already established: no stock deduction, no payment
-- recorded, no journal entry until the sale is actually completed via the
-- real create_sale(). A held sale is never itself validated or priced
-- server-side (unlike a pro-forma, which still computes a real total via
-- compute_invoice_total()) — it's a pure snapshot of whatever the cart
-- looked like at the moment of holding, re-hydrated client-side through the
-- exact same posTotals() the live cart already uses, and only re-validated
-- for real (stock, price, discount/VAT authorization) the moment it's
-- actually checked out.
--
-- One table, not a header+lines split like sales/invoices/pro-formas: line
-- items and payments are stored as plain jsonb, verbatim in the same shape
-- the frontend's PosLine[]/PosPayment[] already use. This is a deliberate
-- departure from every other multi-line business record in this build —
-- justified because nothing server-side ever reads, joins, aggregates, or
-- reports on an individual held-sale line the way it does for a real sale's
-- lines; the whole row is only ever read back out whole, by the one
-- screen that wrote it. A relational child table would add a second
-- table, RLS policy pair, and mapping layer for zero real benefit.
--
-- No human-facing sequential number (unlike invoices/sales/pro-formas/POs/
-- journal entries) — a held sale is never printed, never shown to a
-- customer, never referenced outside this one screen, so a plain uuid is
-- the right id, matching customers/products' own "internal-only" convention
-- rather than the 'HOLD-YYMM####' shape reserved for real documents.
create table public.held_sales (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  -- Nullable for Walk-in, matching sales.customer_id's own shape exactly —
  -- a held sale needs the same "no customer required" flexibility a live
  -- POS sale already has.
  customer_id uuid references public.customers (id) on delete restrict,
  customer_name text not null default 'Walk-in customer',
  lines jsonb not null check (jsonb_array_length(lines) > 0),
  sale_discount_mode text not null default 'amount' check (sale_discount_mode in ('amount', 'percent')),
  sale_discount_value numeric(12, 2) not null default 0 check (sale_discount_value >= 0),
  vat_mode text not null default 'per-item' check (vat_mode in ('per-item', 'all', 'none')),
  payments jsonb not null default '[]'::jsonb,
  -- Who parked it — real, unspoofable attribution via the same
  -- before-insert-trigger discipline every other identity column in this
  -- build uses (performed_by, issued_by, cashier, processed_by, ...), not
  -- trusted from client input. The `default auth.uid()` only exists so the
  -- generated Insert type marks this optional for the frontend; the trigger
  -- below is the actual boundary.
  held_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now()
);

create index held_sales_branch_idx on public.held_sales (branch_id);
create index held_sales_created_at_idx on public.held_sales (created_at);

create or replace function public.set_held_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.held_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger held_sales_set_held_by
before insert on public.held_sales
for each row execute function public.set_held_by();

-- RLS matches the generic "any active staff reads, can_write() writes"
-- shape most operational tables use (sales, sale_lines, ...) — POS is
-- squarely in Attendant's granted module list per section 6, and "visible
-- to any staff member logged into POS at that branch, not locked to
-- whoever created it" (the task's own requirement) means SELECT can't be
-- scoped to held_by at all. No UPDATE policy or grant exists at all — a
-- held sale is never mutated in place, only created (hold) and removed
-- (resume or discard); resuming is a plain DELETE ... RETURNING via
-- PostgREST rather than a dedicated RPC, since a DELETE's own row-level
-- locking already makes "only one caller can resume a given held sale"
-- atomic for free — two attendants racing to resume the same row will
-- have exactly one succeed and the other see zero rows deleted, with no
-- extra locking code needed.
alter table public.held_sales enable row level security;

create policy held_sales_select on public.held_sales
for select using (public.is_active_staff());
create policy held_sales_insert on public.held_sales
for insert with check (public.can_write());
create policy held_sales_delete on public.held_sales
for delete using (public.can_write());

grant select, insert, delete on public.held_sales to authenticated;
grant select, insert, delete on public.held_sales to service_role;
