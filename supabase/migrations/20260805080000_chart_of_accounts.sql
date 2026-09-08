-- Session 12: Chart of Accounts. Spec section 10, item 12: "the account
-- structure itself, standard categories (Assets, Liabilities, Equity,
-- Revenue, Expenses), Manager can create/edit accounts, everyone with
-- accounting read access can view them." Structure only, no journal
-- entries or posting logic — that's Session 13.
--
-- Deliberately pulled forward from Phase 2 (Accounting Core), same kind of
-- exception End of Day Reconciliation (Session 11) already made for Cash
-- Management — confirmed explicitly with the user first, since CLAUDE.md's
-- own Business Domain Rules call out Accounting Core by name as something
-- to ask about before building ahead of schedule.
--
-- ================================================== not branch-scoped
--
-- Every other business-record table in this build carries a branch_id from
-- day one (CLAUDE.md's own "branch_id everywhere" rule) — but a chart of
-- accounts is deliberately the one exception, not an oversight. A COA is
-- the general ledger structure for the whole legal entity: one company, one
-- set of books, even once a second branch exists. Standard double-entry
-- practice keeps a single account list and puts the branch/cost-centre
-- dimension on the *transaction* (a journal entry line, in Session 13), not
-- on the account definition — duplicating "Sales Revenue" per branch would
-- make a future multi-branch Trial Balance/P&L (Session 15) need to sum
-- across near-duplicate accounts instead of just filtering journal lines by
-- branch. If Session 13/14 need per-branch reporting, that's a branch_id on
-- journal_entries/journal_lines, not here.
--
-- ================================================== category / normal_balance
--
-- normal_balance is `generated always as (...) stored` from category rather
-- than a separately-editable column: it's a strict accounting fact of the
-- category (Assets/Expenses are debit-normal, Liabilities/Equity/Revenue
-- are credit-normal), never an independent choice, so storing it as a plain
-- column would let it silently drift out of sync with category on an edit.
-- A generated column makes that structurally impossible rather than a
-- discipline to remember.
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category text not null check (category in ('Assets', 'Liabilities', 'Equity', 'Revenue', 'Expenses')),
  subtype text not null,
  normal_balance text generated always as (
    case when category in ('Assets', 'Expenses') then 'debit' else 'credit' end
  ) stored,
  description text not null default '',
  is_active boolean not null default true,
  created_by uuid not null references public.staff (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_code_format check (code ~ '^[0-9]{3,6}$')
);

create index accounts_category_idx on public.accounts (category);

create trigger accounts_set_updated_at
before update on public.accounts
for each row execute function public.set_updated_at();

-- Same identity-forcing pattern as customer_discounts.created_by: force
-- from auth.uid() whenever there's a real authenticated caller, leave it
-- alone only for the superuser/seed context where auth.uid() is null (the
-- column's NOT NULL with no fallback default, so seed.sql supplies a real
-- staff uuid explicitly for every seeded row instead).
create or replace function public.set_account_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger accounts_set_created_by
before insert on public.accounts
for each row execute function public.set_account_created_by();

-- create-can't-overwrite discipline: no client-supplied id, a plain insert
-- (never on conflict do update), so a create can never silently clobber an
-- existing account. Editing an existing account (name/subtype/description/
-- category/is_active) is a plain RLS-gated update through PostgREST instead
-- of its own RPC — same reasoning as customer_discounts.active/
-- setStaffActive(): there's no extra invariant to protect on an edit beyond
-- what the unique constraint and RLS already enforce, so a dedicated
-- update_account() would just be ceremony.
create or replace function public.create_account(
  p_code text,
  p_name text,
  p_category text,
  p_subtype text,
  p_description text default ''
)
returns public.accounts
language plpgsql
as $$
declare
  v_row public.accounts;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can create an account';
  end if;

  if p_category not in ('Assets', 'Liabilities', 'Equity', 'Revenue', 'Expenses') then
    raise exception 'Invalid account category: %', p_category;
  end if;

  if trim(coalesce(p_code, '')) = '' or trim(coalesce(p_name, '')) = '' then
    raise exception 'Account code and name are required';
  end if;

  begin
    insert into public.accounts (code, name, category, subtype, description)
    values (trim(p_code), trim(p_name), p_category, trim(coalesce(p_subtype, '')), coalesce(trim(p_description), ''))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Account code % is already in use', p_code;
  end;

  return v_row;
end;
$$;

grant execute on function public.create_account(text, text, text, text, text) to authenticated;

alter table public.accounts enable row level security;

-- Same shape as expenses/expense_categories: Attendant isn't granted the
-- Reports/Accounting module at all (not in the spec's Attendant capability
-- list — confirmed with the user, who explicitly said "matches Reports
-- precedent"), so Attendant gets none of select/insert/update/delete here,
-- not just a read restriction. Manager: full read/write/delete. Accountant/
-- Auditor: read-only, matching "read-only on every model" everywhere else.
create policy accounts_select on public.accounts
for select
using (public.has_role(array['Manager', 'Accountant/Auditor']));

create policy accounts_insert on public.accounts
for insert
with check (public.has_role(array['Manager']));

create policy accounts_update on public.accounts
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

create policy accounts_delete on public.accounts
for delete
using (public.has_role(array['Manager']));

revoke all on public.accounts from anon;
grant select, insert, update, delete on public.accounts to authenticated;
grant select, insert, update, delete on public.accounts to service_role;
