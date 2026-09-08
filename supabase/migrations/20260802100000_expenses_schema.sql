-- Expenses schema (Phase 1.5, Session 4). Replaces the in-memory dummy
-- expenses in frontend/src/data/expenses.ts / expenses-store.ts with real
-- tables, and also migrates the editable expense category list (currently
-- Settings' `expenses.categories`, localStorage-only) into its own
-- branch-scoped table — the only piece of Settings pulled forward this
-- session; the rest of Settings stays local until its own Phase 1.5 session.

-- Expense categories are deliberately plain text on `expenses.category`, not
-- a foreign key into this table: the Settings UI already promises "Removing
-- a category leaves existing expenses untouched", which rules out a FK/
-- cascade relationship. This table only drives what's offered when
-- recording a new expense or filtering the list — same trust boundary as
-- Product.category/unit in the inventory migration (a free-text column,
-- validated against a suggestion list at the UI layer, not the DB layer).
create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete cascade,
  name text not null,
  position integer not null default 0,
  unique (branch_id, name)
);

create index expense_categories_branch_id_idx on public.expense_categories (branch_id, position);

create table public.expenses (
  -- Text, not uuid — same reasoning as invoices.id: "EXP-1043" is a
  -- human-facing sequential reference, not a surrogate key.
  id text primary key,
  branch_id uuid not null references public.branches (id) on delete restrict,
  date date not null,
  category text not null,
  description text not null,
  amount numeric(12, 2) not null check (amount > 0),
  method text not null check (method in ('Cash', 'Mobile Money', 'Bank')),
  reference text,
  -- free text until Phase 1.5 Session 7 (staff logins/roles) lands, same
  -- pattern as invoices.issued_by / stock_movements.performed_by.
  recorded_by text not null default 'System',
  recorded_at timestamptz not null default now(),
  -- Object key within the `receipts` storage bucket below, not the receipt
  -- itself — unlike the old dummy data's `receiptDataUrl` (a full base64
  -- data: URL kept in memory), a real image belongs in Storage, not a text
  -- column. Null when no receipt was attached.
  receipt_path text
);

create index expenses_branch_id_idx on public.expenses (branch_id);
create index expenses_date_idx on public.expenses (date);

-- Plain sequence rather than a counter table like invoice_number_counters:
-- expense numbers don't reset monthly (no "EXP-YYMM####" requirement), so
-- there's no monthly bucket to key a counter row on. A sequence's nextval()
-- is itself atomic under concurrency — no separate insert/update/lock
-- dance needed for a single ever-incrementing number. Started one past the
-- highest dummy id (EXP-1042) so newly created expenses can't collide with
-- the reseeded dummy ledger below.
create sequence public.expense_number_seq start with 1043;

-- Same discipline as create_invoice(): a plain insert (never an upsert),
-- with no p_id parameter at all, so the client cannot supply — and
-- therefore cannot collide or overwrite — an expense id. There is no
-- update_expense(): nothing in the UI edits or deletes an existing expense
-- record once recorded (an expense ledger is append-only in this app), so
-- unlike invoices there's no create/update split to make here — only a
-- single, structurally insert-only entry point.
create or replace function public.create_expense(
  p_branch_id uuid,
  p_date date,
  p_category text,
  p_description text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_recorded_by text,
  p_receipt_path text default null
)
returns public.expenses
language plpgsql
as $$
declare
  v_id text;
  v_expense public.expenses;
begin
  v_id := 'EXP-' || nextval('public.expense_number_seq')::text;

  insert into public.expenses
    (id, branch_id, date, category, description, amount, method, reference, recorded_by, receipt_path)
  values
    (v_id, p_branch_id, p_date, p_category, p_description, p_amount, p_method, nullif(p_reference, ''), p_recorded_by, p_receipt_path)
  returning * into v_expense;

  return v_expense;
end;
$$;

-- Full-list replace, matching the existing ListEditor UX in Settings (the
-- caller always submits the complete desired category list, not a single
-- add/remove) — this is intentionally a state-replace operation, not a
-- record-creation one, so the create/update-can't-collide discipline above
-- doesn't apply the same way here: there's nothing to "silently overwrite"
-- when replacing the whole set is the explicit, intended action.
create or replace function public.set_expense_categories(p_branch_id uuid, p_categories text[])
returns setof public.expense_categories
language plpgsql
as $$
begin
  delete from public.expense_categories where branch_id = p_branch_id;

  insert into public.expense_categories (branch_id, name, position)
  select p_branch_id, trim(name), (ord - 1)::integer
  from unnest(p_categories) with ordinality as t(name, ord)
  where trim(name) <> ''
  on conflict (branch_id, name) do nothing;

  return query
    select * from public.expense_categories where branch_id = p_branch_id order by position;
end;
$$;

-- Local dev storage for receipt photos. Public so the UI can render
-- <img src> directly from a stored path without a signed-URL round trip —
-- consistent with this phase's trust level (no auth/RLS exists anywhere
-- else in the app yet either).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', true, 3145728, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

-- storage.objects has row-level security enabled by default regardless of a
-- bucket's `public` flag — public only bypasses RLS for unauthenticated
-- *downloads*, not uploads. Without a policy, anon/authenticated could
-- never upload/list/delete objects in this bucket at all. Scoped to the
-- `receipts` bucket only, not a blanket storage-wide policy, and matches
-- the same no-auth-yet trust level every other table in this app already
-- has with RLS off.
create policy "receipts_full_access" on storage.objects
for all
to anon, authenticated
using (bucket_id = 'receipts')
with check (bucket_id = 'receipts');

grant select, insert, update, delete on public.expense_categories to anon, authenticated;
grant select, insert, update, delete on public.expenses to anon, authenticated;
grant execute on function public.create_expense(uuid, date, text, text, numeric, text, text, text, text) to anon, authenticated;
grant execute on function public.set_expense_categories(uuid, text[]) to anon, authenticated;
