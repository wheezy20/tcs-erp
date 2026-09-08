-- Inventory schema (Phase 1.5, Session 1).
-- Replaces the in-memory dummy data in frontend/src/data/inventory.ts /
-- inventory-store.ts with real tables. See /business-app-spec.md section 9
-- for the session plan and CLAUDE.md "Known Frontend Data Quirks" for the
-- frontend patterns this schema needs to support.

-- Every business-record table carries a branch reference from day one (data
-- model principle in the spec), even though only one branch exists today and
-- there's no branch switcher UI until Phase 3.
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  -- global low-stock default; a product's own low_stock_threshold overrides this when set
  default_low_stock_threshold integer not null default 20 check (default_low_stock_threshold >= 0),
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  sku text not null,
  name text not null,
  description text not null default '',
  -- category/unit stay free text: the Settings > Inventory tab (frontend/src/data/settings-store.ts)
  -- already lets staff add categories/units beyond the starter list, so this
  -- can't be a fixed enum or check constraint without also touching Settings,
  -- which is Phase 3 scope.
  category text not null,
  unit text not null,
  size text not null default '',
  -- cost and selling price are always kept separate (never merged), needed for margin
  cost numeric(12, 2) not null default 0 check (cost >= 0),
  price numeric(12, 2) not null default 0 check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  -- null means "use branches.default_low_stock_threshold" for this branch
  low_stock_threshold integer check (low_stock_threshold >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, sku)
);

create index products_branch_id_idx on public.products (branch_id);
create index products_category_idx on public.products (category);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete restrict,
  movement_type text not null check (movement_type in ('Sale', 'Purchase', 'Adjustment', 'Return')),
  change integer not null,
  balance_after integer not null check (balance_after >= 0),
  reason text not null default '',
  -- free text until Phase 1.5 Session 7 (staff logins/roles) lands; becomes a
  -- real FK to the staff table then, per the "Known Frontend Data Quirks" note
  -- that history.user is currently descriptive, not a trustworthy audit trail.
  performed_by text not null default 'System',
  occurred_at timestamptz not null default now()
);

create index stock_movements_product_id_idx on public.stock_movements (product_id, occurred_at desc);

-- Atomically corrects a product's stock count and appends the audit row in one
-- transaction, so the two can never drift apart (row-locked to be safe under
-- concurrent adjustments to the same product).
create or replace function public.adjust_product_stock(
  p_product_id uuid,
  p_new_stock integer,
  p_reason text,
  p_performed_by text default 'System'
)
returns public.stock_movements
language plpgsql
as $$
declare
  v_old_stock integer;
  v_branch_id uuid;
  v_movement public.stock_movements;
begin
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

  insert into public.stock_movements (product_id, branch_id, movement_type, change, balance_after, reason, performed_by)
  values (p_product_id, v_branch_id, 'Adjustment', p_new_stock - v_old_stock, p_new_stock, p_reason, p_performed_by)
  returning * into v_movement;

  return v_movement;
end;
$$;

-- RLS is intentionally left off. There's no auth/staff table yet (Phase 1.5
-- Session 7); until then these tables are reachable the same way every other
-- pre-auth table in this app is. Revisit alongside the audit log in Sessions 7-9.
--
-- Local Supabase (see supabase/config.toml, api.auto_expose_new_tables) no
-- longer auto-grants Data API access to new tables, so that has to happen
-- explicitly here or PostgREST returns "permission denied" to the anon key
-- the frontend uses.
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.branches to anon, authenticated;
grant select, insert, update, delete on public.products to anon, authenticated;
grant select, insert, update, delete on public.stock_movements to anon, authenticated;
grant execute on function public.adjust_product_stock(uuid, integer, text, text) to anon, authenticated;
