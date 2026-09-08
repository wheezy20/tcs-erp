-- A seed-vs-migration audit of every table in this schema found three
-- tables whose only source of initial rows was seed.sql: accounts,
-- expense_categories, expense_category_accounts (branches was a fourth,
-- already closed separately by a manual insert directly against
-- production — not touched here). Since production never runs seed.sql,
-- all three have been sitting empty there. accounts is the severe one:
-- account_id_by_code() raises 'Chart of Accounts is missing required
-- account %' unconditionally, and it's called from inside every one of the
-- ten auto-posting functions (post_sale_journal_entry,
-- post_invoice_journal_entry, post_invoice_payment_journal_entry,
-- post_expense_journal_entry, post_sale_return_journal_entry,
-- post_stock_adjustment_journal_entry, post_day_close_journal_entry,
-- post_bank_deposit_journal_entry, post_purchase_receipt_journal_entry,
-- post_supplier_payment_journal_entry), each of which runs unconditionally,
-- in the same transaction, from inside create_sale(), create_invoice(),
-- record_invoice_payment(), create_expense(), create_sale_return(),
-- adjust_product_stock(), close_day(), record_bank_deposit(),
-- receive_purchase_order() and paying a supplier. With an empty chart of
-- accounts every one of those — a POS sale, an invoice, an expense, a
-- return, a plain manual stock correction, an End of Day close, receiving
-- a purchase order — raises and rolls back. expense_categories being empty
-- is a narrower, UI-level dead end: record-expense-dialog.tsx's category
-- field is a plain <Select> sourced only from that table with no free-text
-- fallback, so with zero rows no expense can be entered through the
-- standard form at all. expense_category_accounts is a soft gap —
-- expense_category_account() already falls back to 5900 Miscellaneous
-- Expense when a mapping is missing, so it doesn't fail, but every expense
-- silently misposts there regardless of category (including the
-- deliberate "Staff advances -> 1350 Advances to Staff" asset case).
--
-- Every row below is copied verbatim from seed.sql's own three insert
-- blocks for these tables — no new data invented. Two things had to change
-- to make them applicable outside the seed-only context they were
-- originally written for, both explained where they happen below:
-- accounts.created_by (a hardcoded dummy seeded-staff uuid in seed.sql,
-- meaningless on any real deployment) and branch_id on the other two (a
-- hardcoded dummy seeded-branch uuid, likewise meaningless — production's
-- real, manually-added branch has its own, different, randomly generated
-- id). Every insert is idempotent (on conflict do nothing, or an
-- existence check first) specifically so this is safe to run against
-- production, which already has real data of its own (a branch, real
-- staff) that this migration must not duplicate or collide with.

-- accounts.created_by was `not null references staff, default auth.uid()`
-- with no other fallback — seed.sql could get away with that by hardcoding
-- one of its own just-inserted dummy staff uuids, but no such uuid exists,
-- or should be assumed to exist, on a real deployment. Dropped to nullable
-- so these system-seeded scaffolding rows can honestly record "no specific
-- staff member created this" instead of being misattributed to whichever
-- staff row happens to exist first on a given database. This does not
-- change behavior for any account created for real afterward:
-- accounts_set_created_by's trigger still unconditionally forces
-- created_by := auth.uid() whenever there's a real authenticated caller,
-- exactly as before. The frontend already renders "Unknown" when the
-- joined staff relation is absent (accounts-store.ts: `row.staff?.name ??
-- "Unknown"`), so a null created_by needed no frontend change either.
alter table public.accounts alter column created_by drop not null;

-- Chart of Accounts (Session 12) — a real, working standard chart for a
-- building-materials retailer, not a handful of stub rows. "Advances to
-- Staff" is deliberately an Asset (1350), not an Expense mirroring the
-- Phase 1 "Staff advances" expense category — an advance recoverable from
-- future wages is a receivable, not a cost.
insert into public.accounts (code, name, category, subtype, description)
values
  -- Assets
  ('1000', 'Cash on Hand', 'Assets', 'Current Asset', 'Physical cash held at the till/store.'),
  ('1010', 'Cash in Bank', 'Assets', 'Current Asset', 'Business bank account balances.'),
  ('1020', 'Mobile Money Float', 'Assets', 'Current Asset', 'Mobile money wallet balance used for sales and deposits.'),
  ('1100', 'Accounts Receivable', 'Assets', 'Current Asset', 'Amounts owed by customers on credit invoices.'),
  ('1200', 'Inventory', 'Assets', 'Current Asset', 'Cost value of stock on hand across all product categories.'),
  ('1300', 'Prepaid Expenses', 'Assets', 'Current Asset', 'Expenses paid in advance, e.g. rent or insurance.'),
  ('1350', 'Advances to Staff', 'Assets', 'Current Asset', 'Salary advances recoverable from future wages.'),
  ('1400', 'Furniture & Fittings', 'Assets', 'Fixed Asset', 'Shop fixtures, shelving, counters and office furniture.'),
  ('1410', 'Delivery Vehicles', 'Assets', 'Fixed Asset', 'Vans and trucks used for customer deliveries.'),
  ('1420', 'Warehouse Equipment', 'Assets', 'Fixed Asset', 'Forklifts, pallet trucks and other handling equipment.'),
  ('1490', 'Accumulated Depreciation', 'Assets', 'Contra-Asset', 'Cumulative depreciation against fixed assets above.'),
  -- Liabilities
  ('2000', 'Accounts Payable', 'Liabilities', 'Current Liability', 'Amounts owed to suppliers for goods and services.'),
  ('2100', 'VAT Payable', 'Liabilities', 'Current Liability', 'VAT collected on sales, owed to the tax authority.'),
  ('2200', 'Accrued Expenses', 'Liabilities', 'Current Liability', 'Expenses incurred but not yet paid or invoiced.'),
  ('2300', 'Salaries & Wages Payable', 'Liabilities', 'Current Liability', 'Staff pay earned but not yet disbursed.'),
  ('2400', 'Customer Store Credit', 'Liabilities', 'Current Liability', 'Store credit issued on returns/exchanges, owed back to customers.'),
  ('2500', 'Short-Term Loans Payable', 'Liabilities', 'Current Liability', 'Borrowings due within one year.'),
  ('2600', 'Long-Term Loans Payable', 'Liabilities', 'Long-term Liability', 'Borrowings due beyond one year.'),
  -- Equity
  ('3000', 'Owner''s Capital', 'Equity', 'Equity', 'Capital invested into the business by its owner(s).'),
  ('3100', 'Retained Earnings', 'Equity', 'Equity', 'Accumulated profits retained in the business.'),
  ('3200', 'Owner''s Drawings', 'Equity', 'Contra-Equity', 'Cash or goods withdrawn by the owner for personal use.'),
  -- Revenue
  ('4000', 'Sales Revenue', 'Revenue', 'Revenue', 'Revenue from POS and invoiced sales of goods.'),
  ('4100', 'Sales Returns & Allowances', 'Revenue', 'Contra-Revenue', 'Reductions to revenue from returned goods.'),
  ('4200', 'Sales Discounts Given', 'Revenue', 'Contra-Revenue', 'Reductions to revenue from discounts applied at sale.'),
  ('4900', 'Other Income', 'Revenue', 'Revenue', 'Income outside of ordinary sales activity.'),
  -- Expenses
  ('5000', 'Cost of Goods Sold', 'Expenses', 'Cost of Goods Sold', 'Cost value of inventory sold.'),
  ('5100', 'Rent Expense', 'Expenses', 'Operating Expense', 'Rent for the store, warehouse or offices.'),
  ('5110', 'Utilities Expense', 'Expenses', 'Operating Expense', 'Electricity, water and similar utility bills.'),
  ('5120', 'Transport Expense', 'Expenses', 'Operating Expense', 'Fares and haulage for deliveries and errands.'),
  ('5130', 'Fuel Expense', 'Expenses', 'Operating Expense', 'Fuel for delivery vehicles and equipment.'),
  ('5140', 'Salaries & Wages Expense', 'Expenses', 'Operating Expense', 'Pay for permanent staff.'),
  ('5150', 'Casual Labour Expense', 'Expenses', 'Operating Expense', 'Pay for day labourers, e.g. loading/offloading crews.'),
  ('5160', 'Repairs & Maintenance Expense', 'Expenses', 'Operating Expense', 'Upkeep of vehicles, equipment and premises.'),
  ('5170', 'Office & Store Supplies Expense', 'Expenses', 'Operating Expense', 'Consumables such as receipt rolls, packing materials, stationery.'),
  ('5180', 'Marketing & Advertising Expense', 'Expenses', 'Operating Expense', 'Promotion and advertising spend.'),
  ('5190', 'Bank Charges & Fees', 'Expenses', 'Operating Expense', 'Bank and mobile money transaction charges.'),
  ('5200', 'Depreciation Expense', 'Expenses', 'Operating Expense', 'Periodic depreciation charge against fixed assets.'),
  ('5900', 'Miscellaneous Expense', 'Expenses', 'Operating Expense', 'Minor expenses not covered by another category.')
on conflict (code) do nothing;

-- Session 14 (Auto-Posting Integration) additions to the chart.
insert into public.accounts (code, name, category, subtype, description)
values
  ('5210', 'Inventory Shrinkage & Loss', 'Expenses', 'Operating Expense', 'Stock lost to damage, theft or unexplained shrinkage, kept separate from Cost of Goods Sold so loss trends stay visible on their own.'),
  ('5220', 'Cash Over/Short', 'Expenses', 'Operating Expense', 'Reconciles counted till cash against the books at End of Day close; can run either a debit (net shortages) or credit (net overages) balance over time.')
on conflict (code) do nothing;

-- Session 19 (Pro-forma Invoices & Withholding Tax) addition to the chart.
insert into public.accounts (code, name, category, subtype, description)
values
  ('1150', 'WHT Credit Receivable', 'Assets', 'Current Asset', 'Withholding tax deducted by customers on our invoices, claimable back against our own tax liability.')
on conflict (code) do nothing;

-- expense_categories/expense_category_accounts are branch-scoped, and
-- seed.sql hardcoded its own dummy branch uuid ('00000000-...-001'), which
-- is not production's real branch id (production's branch was added
-- manually and got its own, different, randomly generated uuid — verified
-- directly before writing this migration). Resolved dynamically instead,
-- the same "pick the one branch that exists" pattern
-- handle_new_staff_signup() already uses. Gated on a branch actually
-- existing yet, not just defensively: on a fresh local `supabase db
-- reset`, migrations run before seed.sql populates branches at all, so
-- this block correctly no-ops on a fresh local database and seed.sql's own
-- untouched expense_categories/expense_category_accounts inserts still do
-- their original job moments later with no conflict. On production the
-- branch already exists, so the block runs for real.
do $$
declare
  v_branch_id uuid;
begin
  select id into v_branch_id from public.branches order by created_at limit 1;
  if v_branch_id is null then
    raise notice 'No branch exists yet — skipping expense_categories/expense_category_accounts seeding (seed.sql will handle it locally).';
    return;
  end if;

  -- Expenses (Session 4) — mirrors the dummy DEFAULT_EXPENSE_CATEGORIES
  -- list that used to live in frontend/src/data/expenses.ts.
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

  -- Maps every category in the expense_categories list above to a real GL
  -- account, so post_expense_journal_entry() has somewhere to post each
  -- one. "Staff advances" deliberately maps to 1350 Advances to Staff (an
  -- asset, not an expense account). Every category not listed here
  -- (including any a Manager adds later through Settings) falls back to
  -- 5900 Miscellaneous Expense at posting time via
  -- expense_category_account()'s own default, so this list doesn't need
  -- to be exhaustive.
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
end $$;
