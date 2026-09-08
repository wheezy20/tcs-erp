-- Customers schema (Phase 1.5, Session 2).
-- Replaces the customer half of frontend/src/data/sales-store.ts (backed by
-- frontend/src/data/customers.ts) with real tables. See /business-app-spec.md
-- section 9 for the session plan.
--
-- Customer.orders is deliberately NOT migrated as a stored column/table here.
-- It's a loose, flattened stand-in for real invoice history (see CLAUDE.md
-- "Known Frontend Data Quirks"). Session 3 (Sales & Invoicing) will introduce
-- `invoices`, and a customer's order history gets derived from
-- `invoices where customer_id = ...` — not stored twice. Until then the
-- frontend's "Recent orders" section is a placeholder.

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  name text not null,
  phone text not null,
  email text not null default '',
  address text not null default '',
  customer_type text not null default 'Retail' check (customer_type in ('Retail', 'Contractor', 'Wholesale')),
  customer_since date not null default current_date,
  -- Both of these are plain stored figures for now, same as Product.stock in
  -- the inventory migration: there's no invoices/payments ledger yet to derive
  -- them from. Session 3 should turn `balance` into a real aggregate (invoice
  -- totals minus payments) and reconcile `lifetime_total` with invoice history
  -- rather than keeping it as an independently-maintained number.
  balance numeric(12, 2) not null default 0 check (balance >= 0),
  lifetime_total numeric(12, 2) not null default 0 check (lifetime_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, phone)
);

create index customers_branch_id_idx on public.customers (branch_id);

create trigger customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  method text not null check (method in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque')),
  reference text not null default '',
  -- free text until Phase 1.5 Session 7 (staff logins/roles) lands, same
  -- rationale as stock_movements.performed_by in the inventory migration.
  recorded_by text not null default 'System',
  paid_at timestamptz not null default now()
);

create index customer_payments_customer_id_idx on public.customer_payments (customer_id, paid_at desc);

-- RLS is intentionally left off, same as the inventory migration — no
-- auth/staff table yet (Phase 1.5 Session 7). Revisit alongside the audit log
-- in Sessions 7-9.
grant select, insert, update, delete on public.customers to anon, authenticated;
grant select, insert, update, delete on public.customer_payments to anon, authenticated;
