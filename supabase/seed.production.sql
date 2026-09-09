-- ============================================================================
-- TCS ERP — production reference / config seed.
--
-- Run this ONCE against a fresh hosted Supabase project, AFTER
-- `supabase db push` has applied every migration:
--
--     psql "$PROD_DB_URL" -f supabase/seed.production.sql
--
-- It is idempotent (every insert is `on conflict do nothing` or guarded),
-- so re-running it is harmless.
--
-- It contains ONLY reference / configuration data. No demo people, no ERP
-- logins, no employees, no pay configs, no payslips, no payroll runs, no
-- products / customers / invoices / sales / expenses / suppliers /
-- bank accounts.
--
-- ---------------------------------------------------------------------------
-- What this file DOES seed (branch-scoped rows the migrations cannot):
--
--   * branches                    — one campus row. The migrations run
--                                   before any branch exists on a brand-new
--                                   project, so they cannot create it, and
--                                   the branch-scoped seeders below skip
--                                   themselves when there is no branch (see
--                                   20260819090000). This file closes that
--                                   gap.
--   * expense_categories          — the 9 standard categories, per branch.
--   * expense_category_accounts   — each category → its GL account.
--   * allowance_types             — a starting set of payroll allowance
--                                   types, per branch. The school edits
--                                   this list from Payroll → Setup.
--
-- What is ALREADY applied by the migrations (present after `db push`,
-- do NOT duplicate here — the migrations are the source of truth):
--
--   * accounts (full chart of accounts) ...... 20260819090000 + payroll migs
--   * statutory_rates, paye_bands ............. 20260908070000  (⚠ placeholder
--                                              values — verify vs GRA/SSNIT
--                                              before real payroll, see
--                                              docs/CONSTRAINTS.md)
--   * payment_providers (banks + MoMo) ....... 20260909150000
--   * positions, departments ................. 20260909160000
--   * expense_categories / _accounts ......... 20260819090000, BUT only if a
--                                              branch already existed when it
--                                              ran — which it does not on a
--                                              fresh project, hence the
--                                              re-seed below.
-- ============================================================================

do $$
declare
  v_branch_id uuid;
begin
  -- Reuse an existing branch if the project already has one (e.g. added by
  -- hand in the dashboard); otherwise create the single campus row.
  select id into v_branch_id from public.branches order by created_at limit 1;
  if v_branch_id is null then
    insert into public.branches (name, default_low_stock_threshold)
    values ('Treasures Christian School', 20)
    returning id into v_branch_id;
    raise notice 'Created branch % (Treasures Christian School)', v_branch_id;
  else
    raise notice 'Using existing branch %', v_branch_id;
  end if;

  -- Expense categories (branch-scoped). Same list as 20260819090000.
  insert into public.expense_categories (branch_id, name, position)
  values
    (v_branch_id, 'Transport', 0),
    (v_branch_id, 'Fuel', 1),
    (v_branch_id, 'Rent', 2),
    (v_branch_id, 'Utilities', 3),
    (v_branch_id, 'Casual labour', 4),
    (v_branch_id, 'Repairs & maintenance', 5),
    (v_branch_id, 'Supplies', 6),
    (v_branch_id, 'Staff advances', 7),
    (v_branch_id, 'Miscellaneous', 8)
  on conflict (branch_id, name) do nothing;

  -- Category → GL account map. "Staff advances" deliberately points at the
  -- asset account 1350, not an expense account (see 20260807100000). Any
  -- category not listed falls back to 5900 at posting time.
  insert into public.expense_category_accounts (branch_id, category, account_id)
  select v_branch_id, category, (select id from public.accounts where code = code_value)
  from (values
    ('Transport', '5120'),
    ('Fuel', '5130'),
    ('Rent', '5100'),
    ('Utilities', '5110'),
    ('Casual labour', '5150'),
    ('Repairs & maintenance', '5160'),
    ('Supplies', '5170'),
    ('Staff advances', '1350'),
    ('Miscellaneous', '5900')
  ) as mapping(category, code_value)
  on conflict (branch_id, category) do nothing;

  -- Payroll allowance types (branch-scoped). A starting set for a school —
  -- editable from Payroll → Setup. `taxable` follows the simple flag on
  -- allowance_types (no per-allowance statutory cap is modelled).
  insert into public.allowance_types (branch_id, name, taxable, position)
  values
    (v_branch_id, 'Extra Classes', true, 0),
    (v_branch_id, 'Transport', true, 1),
    (v_branch_id, 'Responsibility', true, 2),
    (v_branch_id, 'Hardship / Rural Posting', true, 3)
  on conflict (branch_id, name) do nothing;
end $$;
