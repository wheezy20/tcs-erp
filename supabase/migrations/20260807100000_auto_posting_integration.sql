-- Session 14: Auto-Posting Integration. Wires Sessions 1-11's real
-- transactions into automatic double-entry journal entries via
-- Session 13's post_journal_entry() infrastructure — except it doesn't
-- literally call post_journal_entry() itself; see the architecture note
-- below for why a parallel, narrower path was built instead.
--
-- ============================================== architecture: why not just
-- ============================================== call post_journal_entry()
--
-- post_journal_entry() is deliberately NOT SECURITY DEFINER (Session 13's
-- own reasoning: "it runs with the calling Manager's own grants+RLS, so the
-- INSERT policies are what actually enforce 'Manager can post,' not just
-- this function's own has_role() check"). create_sale()/create_invoice()/
-- create_expense()/etc. are ALSO not SECURITY DEFINER, and are called by
-- Attendants routinely — so if auto-posting simply called
-- post_journal_entry() from inside create_sale(), it would run under the
-- calling Attendant's own privileges, hit journal_entries_insert's
-- has_role(['Manager']) policy, and fail every single Attendant checkout.
--
-- Broadening that policy to can_write() (Manager or Attendant) was
-- considered and rejected: it would let an Attendant INSERT an arbitrary,
-- free-form manual-looking entry directly via a raw REST call, walking back
-- the real security property Session 13 built (not just its RPC-level
-- nicety) for no reason connected to this session's actual goal.
--
-- The design that preserves both goals: eight new SECURITY DEFINER
-- "poster" functions (post_sale_journal_entry(), post_invoice_journal_entry(),
-- ...), one per transaction type, each taking ONLY the id of an
-- already-inserted row (never a free-form line array from its caller) and
-- deriving every debit/credit itself by re-reading that row's own
-- already-committed-in-this-transaction data. Granting them EXECUTE to
-- authenticated (required, so create_sale() can call one under an
-- Attendant's own role) is safe specifically because of that shape: a
-- direct call by any role can only ever (a) post the single, correct,
-- real entry for a real, already-existing transaction, and (b) do it once
-- — the unique (source_table, source_id) constraint on journal_entries
-- makes a second attempt fail, not double-post. Neither property depends
-- on trusting the caller's role at all, which is a cleaner and stronger
-- guarantee than a role check would have been. Each poster then calls a
-- shared private helper, _post_journal_entry_rows() (SECURITY DEFINER,
-- granted to no one — only reachable from within another SECURITY DEFINER
-- function's execution, which already runs as the owner) that does the
-- actual numbering/insert/balance-precheck work, duplicating
-- post_journal_entry()'s own shape rather than calling it, so
-- post_journal_entry()'s Session 13 security property is never touched by
-- this migration at all.
--
-- Atomicity ("a sale and its journal entry either both succeed or both
-- fail") falls out of this for free: each poster call is one more
-- statement inside create_sale()'s own plpgsql body, inside the same
-- transaction as the sale/stock/payment inserts. If it raises (e.g. a
-- required account is missing), the exception propagates and the whole
-- transaction rolls back, exactly like any other failure already did.
--
-- ============================================================= amounts
--
-- Every poster anchors its entry to the transaction's OWN already-computed,
-- already-validated total (sales.total, invoices.total, ...) — the actual
-- money that was actually validated against actual payments — rather than
-- recomputing everything from scratch and hoping it lines up to the cent.
-- compute_sale_posting_amounts()/compute_invoice_posting_amounts() derive
-- subtotal and discount from the line items (same arithmetic as
-- compute_sale_total()/compute_invoice_total(), duplicated rather than
-- shared for the same reason Session 11's compute_day_totals() duplicated
-- compute_sale_total()'s math: avoid touching a function every checkout
-- already depends on), each rounded to 2dp, then derive VAT as whatever
-- residual makes total = subtotal - discount + vat exactly. This isn't
-- cutting a corner: it *guarantees* the posted entry balances against the
-- real total by construction, rather than hoping two independent roundings
-- happen to agree, which is what actually matters for a ledger.
--
-- ============================================================ COGS
--
-- Cost of Goods Sold uses products.cost read fresh within the same
-- transaction as the sale/invoice/return, right alongside (or shortly
-- after) the stock deduction. Since nothing else in the same transaction
-- can change a product's cost, "current cost, read now" and "cost at the
-- moment of sale" are the same value — no need to snapshot cost onto
-- sale_lines/invoice_lines just for this.
--
-- ==================================================== flagged, not built
--
-- Four things this session deliberately does NOT do, each because the
-- user's own instructions describe a narrower scope than the surrounding
-- transaction type technically has, and "tell me, don't invent" governs
-- all of them:
--
-- 1. Store credit has no redemption path anywhere in this codebase today
--    (checked, not assumed — no balance column on customers, no
--    "Store Credit" payment method on sale_payments/invoice_payments, no
--    UI to spend it). 2400 Customer Store Credit will accrue correctly
--    every time a return resolves to store credit, but nothing anywhere
--    ever debits it back down, because there is no feature that spends
--    accrued credit. This is flagged to the user directly, not fixed here.
-- 2. sale_returns.resolution has two more values this session doesn't
--    post for: 'Top-up collected' and 'Even exchange'. The user's own
--    transaction list names exactly "Cash refund" and "Store credit
--    issued" for returns; those two others get no journal entry at all,
--    on the reasoning that inventing their treatment would be exactly the
--    kind of scope decision the user asked not to be made unilaterally.
-- 3. stock_movements rows with movement_type = 'Purchase' (new stock
--    received) are not posted. adjust_product_stock() — the only RPC this
--    session touches — always writes movement_type = 'Adjustment'
--    (verified by reading its body: the literal is hardcoded, not a
--    parameter), so this is naturally out of scope by construction, not a
--    gap in coverage of what the user asked for. A real Purchase-side
--    entry needs an Accounts Payable/supplier counterpart that doesn't
--    exist until Session 17 (Suppliers & Purchasing); inventing one now
--    would be scope creep into a module explicitly deferred.
-- 4. Card, Bank Transfer, Bank (expenses' own spelling), and Cheque all
--    post to the same 1010 Cash in Bank — the user's own payment-method
--    breakdown says "Cash/Bank/MoMo," not four separate settlement
--    accounts. A dedicated Card Clearing/Undeposited Funds account is
--    exactly the kind of thing Session 16 (the real Bank Reconciliation
--    module) would introduce; this session's own COA (Session 12) never
--    built one, and adding it here without being asked would be inventing
--    structure ahead of the module that actually needs it.
--
-- ==================================================== one loop closed
--
-- Session 12 deliberately made 1350 Advances to Staff an Asset, not an
-- Expense, flagging "how the existing Staff advances expense category
-- maps onto this chart is Session 14's call." That call: an expense
-- recorded under the "Staff advances" category posts Dr 1350 (a
-- receivable, recoverable from future wages) / Cr Cash-or-whatever, not
-- Dr 5xxx Expense — the one category in expense_category_accounts that
-- doesn't map to an Expense-category account at all, on purpose.

-- ============================================================ new accounts
--
-- 5210 (shrinkage) and 5220 (cash over/short) are genuinely new judgment
-- calls, not in Session 12's original 38. Both are seeded in seed.sql, not
-- inserted directly here — unlike business_settings' vat_rate singleton
-- (no FK dependency at all), accounts.created_by is `not null references
-- staff(id)`, and staff has no rows yet at migration time (seed.sql runs
-- after every migration and is the only place staff rows are created), so
-- a migration-time insert here would fail its own FK constraint. This
-- mirrors exactly why Session 12's original 38 accounts were seed-only too.
--
-- 5210 Inventory Shrinkage & Loss is kept separate from 5000 Cost of Goods
-- Sold rather than folded into it — standard retail practice keeps
-- shrinkage/damage/theft visible as its own line so management can see
-- loss trends distinctly from cost-of-sales trends; COGS should represent
-- the cost of goods actually SOLD, not goods that left the business
-- unsold. This is the mapping judgment call flagged as least certain.
--
-- 5220 Cash Over/Short is the standard named account for exactly this
-- purpose in retail bookkeeping: it can carry either a debit balance
-- (net historical shortages) or credit balance (net historical overages)
-- over time, which is the intended, normal behavior for this one account,
-- not a bug in how it's used.

-- accounts.code stability: Session 13 onward, every poster below refers to
-- accounts by their well-known code (account_id_by_code() looks them up by
-- code every time). Session 12 already made code non-editable in the Edit
-- Account dialog's UI, but flagged that nothing enforced it at the
-- database level ("revisit... if needed"). It's needed now: a renamed code
-- would silently break every poster that references it. Enforced here,
-- not in Session 12's own migration (already applied, never rewritten).
create or replace function public.prevent_account_code_change()
returns trigger language plpgsql as $$
begin
  if new.code <> old.code then
    raise exception 'Account code cannot be changed once created — deactivate and create a new account instead';
  end if;
  return new;
end;
$$;

create trigger accounts_prevent_code_change
before update on public.accounts
for each row execute function public.prevent_account_code_change();

-- ==================================================== journal_entries: source

-- Nullable — null for every manual entry (post_journal_entry() never sets
-- these; its signature doesn't even accept them). Populated only by
-- _post_journal_entry_rows() below. The unique constraint is the real,
-- structural "can't double-post the same transaction" guarantee — not an
-- application-level "check first" race, which two near-simultaneous calls
-- could both pass. Postgres's default NULLS DISTINCT behavior means many
-- manual entries with (null, null) coexist fine; only two real
-- (source_table, source_id) pairs actually collide.
alter table public.journal_entries
  add column source_table text,
  add column source_id text;

alter table public.journal_entries
  add constraint journal_entries_source_unique unique (source_table, source_id);

create index journal_entries_source_idx on public.journal_entries (source_table, source_id);

-- ==================================================================== helpers

create or replace function public.account_id_by_code(p_code text)
returns uuid
language plpgsql
stable
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.accounts where code = p_code;
  if v_id is null then
    raise exception 'Chart of Accounts is missing required account %', p_code;
  end if;
  return v_id;
end;
$$;

-- Card/Bank Transfer/Bank/Cheque all settle to the bank, so they all map
-- to 1010 — see the migration header's "flagged, not built" item 4 for why
-- this session doesn't introduce a separate clearing account. Every value
-- currently allowed by any method/source check constraint in this schema
-- is enumerated explicitly (rather than a catch-all default) so a future
-- new payment method added elsewhere fails loudly here instead of silently
-- posting to the wrong account.
create or replace function public.payment_method_account(p_method text)
returns uuid
language plpgsql
stable
as $$
begin
  case p_method
    when 'Cash' then return public.account_id_by_code('1000');
    when 'Mobile Money' then return public.account_id_by_code('1020');
    when 'Card', 'Bank Transfer', 'Bank', 'Cheque' then return public.account_id_by_code('1010');
    else raise exception 'No GL account mapping for payment method %', p_method;
  end case;
end;
$$;

-- expense_category_accounts (below) is the source of truth; a category
-- with no explicit row (including any a Manager adds later through
-- Settings' free-text, runtime-editable list — Session 4's own design)
-- falls back to 5900 Miscellaneous Expense rather than failing. Unlike
-- account_id_by_code()'s "the chart itself is broken" case, an unmapped
-- category is an ordinary, expected situation, not a configuration error.
create or replace function public.expense_category_account(p_branch_id uuid, p_category text)
returns uuid
language plpgsql
stable
as $$
declare
  v_id uuid;
begin
  select account_id into v_id from public.expense_category_accounts
  where branch_id = p_branch_id and category = p_category;
  if v_id is null then
    return public.account_id_by_code('5900');
  end if;
  return v_id;
end;
$$;

-- ==================================================== expense_category_accounts

create table public.expense_category_accounts (
  branch_id uuid not null references public.branches (id) on delete restrict,
  category text not null,
  account_id uuid not null references public.accounts (id) on delete restrict,
  primary key (branch_id, category)
);

alter table public.expense_category_accounts enable row level security;

-- Same shape as accounts (Session 12): no UI reads or writes this table
-- yet (a Settings screen for it is a reasonable future session, not this
-- one), but the locked 3-tier model applies to every new table regardless
-- of whether a client currently exercises it.
create policy expense_category_accounts_select on public.expense_category_accounts
for select
using (public.has_role(array['Manager', 'Accountant/Auditor']));

create policy expense_category_accounts_insert on public.expense_category_accounts
for insert
with check (public.has_role(array['Manager']));

create policy expense_category_accounts_update on public.expense_category_accounts
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

create policy expense_category_accounts_delete on public.expense_category_accounts
for delete
using (public.has_role(array['Manager']));

revoke all on public.expense_category_accounts from anon;
grant select, insert, update, delete on public.expense_category_accounts to authenticated;
grant select, insert, update, delete on public.expense_category_accounts to service_role;

-- ============================================================ posting amounts
--
-- Both duplicate compute_sale_total()/compute_invoice_total()'s per-line
-- arithmetic (see migration header) but return the subtotal/discount
-- breakdown instead of just the final total, and take that final total
-- (already computed and stored on the row) as a parameter rather than
-- recomputing it — VAT is derived as whatever residual makes the three
-- figures reconcile exactly to that real, authoritative total.

create or replace function public.compute_sale_posting_amounts(
  p_lines jsonb, p_sale_discount_mode text, p_sale_discount_value numeric, p_total numeric
)
returns table(subtotal numeric, discount numeric, vat numeric)
language plpgsql
as $$
declare
  v_line jsonb;
  v_gross numeric;
  v_line_discount numeric;
  v_net numeric;
  v_subtotal numeric := 0;
  v_sale_discount numeric;
  v_net_total numeric;
begin
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_gross := (v_line ->> 'quantity')::numeric * (v_line ->> 'unit_price')::numeric;
    v_line_discount := case when coalesce(v_line ->> 'discount_mode', 'amount') = 'percent'
      then v_gross * coalesce((v_line ->> 'discount_value')::numeric, 0) / 100
      else coalesce((v_line ->> 'discount_value')::numeric, 0) end;
    v_net := greatest(v_gross - greatest(v_line_discount, 0), 0);
    v_subtotal := v_subtotal + v_net;
  end loop;

  v_sale_discount := case when p_sale_discount_mode = 'percent'
    then v_subtotal * greatest(p_sale_discount_value, 0) / 100
    else greatest(p_sale_discount_value, 0) end;
  v_sale_discount := least(v_sale_discount, v_subtotal);

  subtotal := round(v_subtotal, 2);
  discount := round(v_sale_discount, 2);
  v_net_total := subtotal - discount;
  vat := p_total - v_net_total;
  return next;
end;
$$;

create or replace function public.compute_invoice_posting_amounts(
  p_lines jsonb, p_invoice_discount numeric, p_total numeric
)
returns table(subtotal numeric, discount numeric, vat numeric)
language plpgsql
as $$
declare
  v_line jsonb;
  v_line_gross numeric;
  v_line_discount numeric;
  v_line_net numeric;
  v_subtotal numeric := 0;
  v_invoice_discount numeric;
  v_net_after_discount numeric;
begin
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_gross := (v_line ->> 'quantity')::numeric * (v_line ->> 'unit_price')::numeric;
    v_line_discount := coalesce((v_line ->> 'discount')::numeric, 0);
    v_line_net := greatest(v_line_gross - v_line_discount, 0);
    v_subtotal := v_subtotal + v_line_net;
  end loop;

  v_invoice_discount := least(greatest(p_invoice_discount, 0), v_subtotal);

  subtotal := round(v_subtotal, 2);
  discount := round(v_invoice_discount, 2);
  v_net_after_discount := subtotal - discount;
  vat := p_total - v_net_after_discount;
  return next;
end;
$$;

-- ==================================================== core insert (private)
--
-- Granted to no one — only reachable from within another SECURITY DEFINER
-- function's execution (the eight posters below), which by that point is
-- already running as the owner and needs no separate grant to call a
-- function the same owner owns. Duplicates post_journal_entry()'s
-- numbering/insert shape (see migration header for why this isn't shared
-- with post_journal_entry() itself) including the same pre-check-then-
-- deferred-trigger-backstop balance discipline.
create or replace function public._post_journal_entry_rows(
  p_branch_id uuid,
  p_date date,
  p_description text,
  p_reference text,
  p_lines jsonb,
  p_source_table text,
  p_source_id text
)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_year_month text := to_char(p_date, 'YYMM');
  v_seq integer;
  v_id text;
  v_row public.journal_entries;
  v_total_debit numeric;
  v_total_credit numeric;
begin
  select coalesce(sum((line ->> 'debit')::numeric), 0), coalesce(sum((line ->> 'credit')::numeric), 0)
  into v_total_debit, v_total_credit
  from jsonb_array_elements(p_lines) as line;

  if v_total_debit <> v_total_credit then
    raise exception 'Auto-posted entry for % % is not balanced: debits % do not equal credits %',
      p_source_table, p_source_id, v_total_debit, v_total_credit;
  end if;
  if v_total_debit = 0 then
    raise exception 'Auto-posted entry for % % has no amount', p_source_table, p_source_id;
  end if;

  insert into public.journal_entry_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = journal_entry_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'JE-' || v_year_month || lpad(v_seq::text, 4, '0');

  begin
    insert into public.journal_entries (id, branch_id, entry_date, description, reference, source_table, source_id)
    values (
      v_id, p_branch_id, p_date, p_description,
      nullif(trim(coalesce(p_reference, '')), ''),
      p_source_table, p_source_id
    )
    returning * into v_row;
  exception when unique_violation then
    raise exception '% % has already been posted to the ledger', p_source_table, p_source_id;
  end;

  insert into public.journal_lines (entry_id, position, account_id, debit, credit, description)
  select
    v_id,
    ord - 1,
    (line ->> 'account_id')::uuid,
    coalesce((line ->> 'debit')::numeric, 0),
    coalesce((line ->> 'credit')::numeric, 0),
    coalesce(line ->> 'description', '')
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_row;
end;
$$;

-- ============================================================== POS sale
--
-- Dr Cash/Bank/MoMo per payment method (a split-payment sale posts one
-- debit line per method actually used) for the total, Cr Sales Revenue for
-- subtotal, Cr VAT Payable for VAT, Dr Sales Discounts Given for the
-- sale-level discount (only if nonzero — per-line discounts stay silently
-- netted into "subtotal," matching this app's own existing terminology, not
-- separately broken out). Plus Dr COGS / Cr Inventory for the cost of
-- items sold (only if nonzero).
create or replace function public.post_sale_journal_entry(p_sale_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_sale public.sales;
  v_lines_json jsonb;
  v_totals record;
  v_cogs numeric;
  v_lines jsonb := '[]'::jsonb;
  v_payment record;
begin
  select * into v_sale from public.sales where id = p_sale_id;
  if not found then
    raise exception 'Sale % not found', p_sale_id;
  end if;

  select jsonb_agg(jsonb_build_object(
    'quantity', quantity, 'unit_price', unit_price,
    'discount_mode', discount_mode, 'discount_value', discount_value
  ))
  into v_lines_json
  from public.sale_lines where sale_id = p_sale_id;

  select * into v_totals from public.compute_sale_posting_amounts(
    v_lines_json, v_sale.sale_discount_mode, v_sale.sale_discount_value, v_sale.total
  );

  select coalesce(sum(sl.quantity * p.cost), 0) into v_cogs
  from public.sale_lines sl join public.products p on p.id = sl.product_id
  where sl.sale_id = p_sale_id;

  for v_payment in
    select method, sum(amount) as amount from public.sale_payments where sale_id = p_sale_id group by method
  loop
    if v_payment.amount > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'account_id', public.payment_method_account(v_payment.method),
        'debit', v_payment.amount, 'credit', 0, 'description', v_payment.method
      ));
    end if;
  end loop;

  if v_totals.discount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4200'),
      'debit', v_totals.discount, 'credit', 0, 'description', 'Sale discount'
    ));
  end if;

  if v_totals.subtotal > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4000'),
      'debit', 0, 'credit', v_totals.subtotal, 'description', 'Sale revenue'
    ));
  end if;

  if v_totals.vat > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('2100'),
      'debit', 0, 'credit', v_totals.vat, 'description', 'VAT collected'
    ));
  end if;

  if v_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('5000'),
      'debit', v_cogs, 'credit', 0, 'description', 'Cost of goods sold'
    ));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('1200'),
      'debit', 0, 'credit', v_cogs, 'description', 'Inventory'
    ));
  end if;

  if jsonb_array_length(v_lines) < 2 then
    return null;
  end if;

  return public._post_journal_entry_rows(
    v_sale.branch_id, v_sale.sold_at::date, 'POS sale ' || p_sale_id, p_sale_id, v_lines, 'sales', p_sale_id
  );
end;
$$;

grant execute on function public.post_sale_journal_entry(text) to authenticated;

-- ======================================================= invoice created

-- Dr Accounts Receivable for the full total (nothing has been paid yet),
-- Cr Sales Revenue / Cr VAT Payable / Dr Sales Discounts Given the same
-- way as a POS sale, plus the same COGS/Inventory pair.
create or replace function public.post_invoice_journal_entry(p_invoice_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_invoice public.invoices;
  v_lines_json jsonb;
  v_totals record;
  v_cogs numeric;
  v_lines jsonb := '[]'::jsonb;
begin
  select * into v_invoice from public.invoices where id = p_invoice_id;
  if not found then
    raise exception 'Invoice % not found', p_invoice_id;
  end if;

  select jsonb_agg(jsonb_build_object('quantity', quantity, 'unit_price', unit_price, 'discount', discount))
  into v_lines_json
  from public.invoice_lines where invoice_id = p_invoice_id;

  select * into v_totals from public.compute_invoice_posting_amounts(
    v_lines_json, v_invoice.invoice_discount, v_invoice.total
  );

  select coalesce(sum(il.quantity * p.cost), 0) into v_cogs
  from public.invoice_lines il
  join public.products p on p.id = il.product_id
  where il.invoice_id = p_invoice_id;

  if v_invoice.total > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('1100'),
      'debit', v_invoice.total, 'credit', 0, 'description', 'Accounts receivable'
    ));
  end if;

  if v_totals.discount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4200'),
      'debit', v_totals.discount, 'credit', 0, 'description', 'Invoice discount'
    ));
  end if;

  if v_totals.subtotal > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('4000'),
      'debit', 0, 'credit', v_totals.subtotal, 'description', 'Sale revenue'
    ));
  end if;

  if v_totals.vat > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('2100'),
      'debit', 0, 'credit', v_totals.vat, 'description', 'VAT collected'
    ));
  end if;

  if v_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('5000'),
      'debit', v_cogs, 'credit', 0, 'description', 'Cost of goods sold'
    ));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', public.account_id_by_code('1200'),
      'debit', 0, 'credit', v_cogs, 'description', 'Inventory'
    ));
  end if;

  if jsonb_array_length(v_lines) < 2 then
    return null;
  end if;

  return public._post_journal_entry_rows(
    v_invoice.branch_id, v_invoice.date, 'Invoice ' || p_invoice_id, p_invoice_id, v_lines, 'invoices', p_invoice_id
  );
end;
$$;

grant execute on function public.post_invoice_journal_entry(text) to authenticated;

-- ================================================= invoice payment received

create or replace function public.post_invoice_payment_journal_entry(p_payment_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_payment public.invoice_payments;
  v_lines jsonb;
begin
  select * into v_payment from public.invoice_payments where id = p_payment_id;
  if not found then
    raise exception 'Invoice payment % not found', p_payment_id;
  end if;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', public.payment_method_account(v_payment.method),
      'debit', v_payment.amount, 'credit', 0, 'description', v_payment.method
    ),
    jsonb_build_object(
      'account_id', public.account_id_by_code('1100'),
      'debit', 0, 'credit', v_payment.amount, 'description', 'Invoice payment received'
    )
  );

  return public._post_journal_entry_rows(
    v_payment.branch_id, v_payment.paid_at::date, 'Payment received on ' || v_payment.invoice_id,
    v_payment.id::text, v_lines, 'invoice_payments', v_payment.id::text
  );
end;
$$;

grant execute on function public.post_invoice_payment_journal_entry(uuid) to authenticated;

-- ============================================================= expense paid
--
-- Dr the mapped expense (or, for "Staff advances" specifically, Dr 1350
-- Advances to Staff — an asset, not an expense; see the migration header's
-- "one loop closed" note), Cr Cash/Bank/MoMo by the expense's own method.
create or replace function public.post_expense_journal_entry(p_expense_id text)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_expense public.expenses;
  v_lines jsonb;
begin
  select * into v_expense from public.expenses where id = p_expense_id;
  if not found then
    raise exception 'Expense % not found', p_expense_id;
  end if;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', public.expense_category_account(v_expense.branch_id, v_expense.category),
      'debit', v_expense.amount, 'credit', 0, 'description', v_expense.category
    ),
    jsonb_build_object(
      'account_id', public.payment_method_account(v_expense.method),
      'debit', 0, 'credit', v_expense.amount, 'description', v_expense.method
    )
  );

  return public._post_journal_entry_rows(
    v_expense.branch_id, v_expense.date, v_expense.description, p_expense_id, v_lines, 'expenses', p_expense_id
  );
end;
$$;

grant execute on function public.post_expense_journal_entry(text) to authenticated;

-- ===================================================== return: cash refund
-- ===================================================== / store credit
--
-- Only 'Cash refund' and 'Store credit' resolutions are posted — see the
-- migration header's "flagged, not built" item 2 for 'Top-up collected'
-- and 'Even exchange'. Dr Sales Returns / Cr Cash-or-2400 for the refund/
-- credit amount (the negative portion of sale_returns.difference — the
-- only case these two resolutions are ever used for, per the app's own
-- business rule), plus a net COGS/Inventory adjustment covering BOTH the
-- returned item going back into stock and, if this was an undervalue
-- exchange, the replacement item leaving stock.
create or replace function public.post_sale_return_journal_entry(p_return_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_return public.sale_returns;
  v_refund_amount numeric;
  v_returned_cost numeric;
  v_replacement_cost numeric;
  v_net_cogs numeric;
  v_lines jsonb := '[]'::jsonb;
  v_target_account uuid;
begin
  select * into v_return from public.sale_returns where id = p_return_id;
  if not found then
    raise exception 'Return % not found', p_return_id;
  end if;

  if v_return.resolution not in ('Cash refund', 'Store credit') then
    return null;
  end if;

  v_refund_amount := abs(least(v_return.difference, 0));
  if v_refund_amount = 0 then
    return null;
  end if;

  v_target_account := case v_return.resolution
    when 'Cash refund' then public.account_id_by_code('1000')
    when 'Store credit' then public.account_id_by_code('2400')
  end;

  v_lines := v_lines || jsonb_build_array(
    jsonb_build_object(
      'account_id', public.account_id_by_code('4100'),
      'debit', v_refund_amount, 'credit', 0, 'description', v_return.resolution
    ),
    jsonb_build_object(
      'account_id', v_target_account,
      'debit', 0, 'credit', v_refund_amount, 'description', v_return.resolution
    )
  );

  select coalesce(cost, 0) * v_return.returned_quantity into v_returned_cost
  from public.products where id = v_return.returned_product_id;
  v_returned_cost := coalesce(v_returned_cost, 0);

  v_replacement_cost := 0;
  if v_return.replacement_product_id is not null then
    select coalesce(cost, 0) * v_return.replacement_quantity into v_replacement_cost
    from public.products where id = v_return.replacement_product_id;
    v_replacement_cost := coalesce(v_replacement_cost, 0);
  end if;

  v_net_cogs := v_replacement_cost - v_returned_cost;

  if v_net_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('5000'),
        'debit', v_net_cogs, 'credit', 0, 'description', 'Return exchange COGS'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', 0, 'credit', v_net_cogs, 'description', 'Return exchange inventory'
      )
    );
  elsif v_net_cogs < 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', abs(v_net_cogs), 'credit', 0, 'description', 'Return inventory'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('5000'),
        'debit', 0, 'credit', abs(v_net_cogs), 'description', 'Return COGS reversal'
      )
    );
  end if;

  return public._post_journal_entry_rows(
    v_return.branch_id, v_return.returned_at::date, v_return.resolution || ' on ' || v_return.sale_id,
    p_return_id::text, v_lines, 'sale_returns', p_return_id::text
  );
end;
$$;

grant execute on function public.post_sale_return_journal_entry(uuid) to authenticated;

-- ======================================================= stock adjustment
--
-- adjust_product_stock() always writes movement_type = 'Adjustment' (the
-- literal is hardcoded in its body, not a caller-supplied value) — see the
-- migration header's "flagged, not built" item 3 for why Purchase-type
-- movements (a different code path entirely) are out of scope. A decrease
-- (shrinkage/damage) debits 5210; an increase (found stock/correction)
-- credits it, offsetting past shrinkage — both valued at the product's
-- current cost.
create or replace function public.post_stock_adjustment_journal_entry(p_movement_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_movement public.stock_movements;
  v_cost numeric;
  v_amount numeric;
  v_lines jsonb;
begin
  select * into v_movement from public.stock_movements where id = p_movement_id;
  if not found then
    raise exception 'Stock movement % not found', p_movement_id;
  end if;

  if v_movement.movement_type <> 'Adjustment' then
    return null;
  end if;

  select cost into v_cost from public.products where id = v_movement.product_id;
  v_amount := round(abs(v_movement.change) * coalesce(v_cost, 0), 2);
  if v_amount = 0 then
    return null;
  end if;

  if v_movement.change < 0 then
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('5210'),
        'debit', v_amount, 'credit', 0, 'description', 'Stock shrinkage'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', 0, 'credit', v_amount, 'description', 'Stock shrinkage'
      )
    );
  else
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('1200'),
        'debit', v_amount, 'credit', 0, 'description', 'Stock correction'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('5210'),
        'debit', 0, 'credit', v_amount, 'description', 'Stock correction'
      )
    );
  end if;

  return public._post_journal_entry_rows(
    v_movement.branch_id, v_movement.occurred_at::date, 'Stock adjustment — ' || v_movement.reason,
    p_movement_id::text, v_lines, 'stock_movements', p_movement_id::text
  );
end;
$$;

grant execute on function public.post_stock_adjustment_journal_entry(uuid) to authenticated;

-- ===================================================== end of day variance
--
-- Standard Cash Over/Short treatment: an overage (counted > expected)
-- debits Cash on Hand up to physical reality and credits 5220; a shortage
-- debits 5220 and credits Cash on Hand down to physical reality. Skipped
-- entirely when the variance is exactly zero — nothing to reconcile.
create or replace function public.post_day_close_journal_entry(p_day_close_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_close public.day_closes;
  v_amount numeric;
  v_lines jsonb;
begin
  select * into v_close from public.day_closes where id = p_day_close_id;
  if not found then
    raise exception 'Day close % not found', p_day_close_id;
  end if;

  if v_close.cash_variance is null or v_close.cash_variance = 0 then
    return null;
  end if;

  v_amount := abs(v_close.cash_variance);

  if v_close.cash_variance > 0 then
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('1000'),
        'debit', v_amount, 'credit', 0, 'description', 'Cash overage'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('5220'),
        'debit', 0, 'credit', v_amount, 'description', 'Cash overage'
      )
    );
  else
    v_lines := jsonb_build_array(
      jsonb_build_object(
        'account_id', public.account_id_by_code('5220'),
        'debit', v_amount, 'credit', 0, 'description', 'Cash shortage'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('1000'),
        'debit', 0, 'credit', v_amount, 'description', 'Cash shortage'
      )
    );
  end if;

  return public._post_journal_entry_rows(
    v_close.branch_id, v_close.business_date, 'End of day cash variance — ' || v_close.business_date,
    p_day_close_id::text, v_lines, 'day_closes', p_day_close_id::text
  );
end;
$$;

grant execute on function public.post_day_close_journal_entry(uuid) to authenticated;

-- ========================================================== bank deposit

create or replace function public.post_bank_deposit_journal_entry(p_deposit_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_deposit public.bank_deposits;
  v_source_account uuid;
  v_lines jsonb;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id;
  if not found then
    raise exception 'Deposit % not found', p_deposit_id;
  end if;

  v_source_account := case v_deposit.source
    when 'Cash' then public.account_id_by_code('1000')
    when 'Mobile Money' then public.account_id_by_code('1020')
  end;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', public.account_id_by_code('1010'),
      'debit', v_deposit.amount, 'credit', 0, 'description', 'Deposit — ' || v_deposit.source
    ),
    jsonb_build_object(
      'account_id', v_source_account,
      'debit', 0, 'credit', v_deposit.amount, 'description', 'Deposit — ' || v_deposit.source
    )
  );

  return public._post_journal_entry_rows(
    v_deposit.branch_id, v_deposit.date, 'Bank/Mobile Money deposit', p_deposit_id::text,
    v_lines, 'bank_deposits', p_deposit_id::text
  );
end;
$$;

grant execute on function public.post_bank_deposit_journal_entry(uuid) to authenticated;

-- =======================================================================
-- Wire the eight posters into their real transaction RPCs. Every function
-- below is `create or replace` with an UNCHANGED signature — Postgres
-- preserves existing grants across a same-signature replace (verified
-- precedent: role_permissions_rewrite.sql replaced adjust_product_stock(),
-- create_invoice(), record_invoice_payment() without re-granting), so none
-- of these need a fresh grant statement. Every other line is copied
-- verbatim from each function's current body; the only change is one
-- `perform post_..._journal_entry(...)` call added right before its
-- `return`.
-- =======================================================================

create or replace function public.create_sale(
  p_branch_id uuid, p_customer_id uuid, p_customer_name text,
  p_sale_discount_mode text, p_sale_discount_value numeric, p_vat_mode text,
  p_lines jsonb, p_payments jsonb,
  p_override_ticket uuid default null
) returns public.sales language plpgsql as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_rate numeric;
  v_total numeric;
  v_paid numeric;
  v_cash numeric;
  v_non_cash numeric;
  v_sale public.sales;
  v_line jsonb;
  v_product public.products;
  v_payment jsonb;
  v_authorized boolean;
  v_override_manager_id uuid;
begin
  perform public.require_writable_role();

  if p_sale_discount_mode not in ('amount', 'percent') or p_vat_mode not in ('per-item', 'all', 'none') then raise exception 'Invalid discount or VAT mode'; end if;

  v_authorized := public.has_role(array['Manager']);

  if not v_authorized and p_override_ticket is not null then
    v_override_manager_id := public.consume_manager_override(p_override_ticket);
    v_authorized := true;
  end if;

  if not v_authorized then
    if p_sale_discount_value <> 0 then
      if p_customer_id is null or not exists (
        select 1 from public.customer_discounts
        where customer_id = p_customer_id
          and mode = p_sale_discount_mode
          and value = p_sale_discount_value
          and active
      ) then
        raise exception 'Only a Manager can apply a discount that is not an active, customer-attached discount';
      end if;
    end if;

    if exists (
      select 1 from jsonb_array_elements(p_lines) as l
      where coalesce((l.value->>'discount_value')::numeric, 0) <> 0
    ) then
      raise exception 'Only a Manager can apply a per-item discount';
    end if;

    if p_vat_mode <> 'per-item' then
      raise exception 'Only a Manager can override VAT for the whole sale';
    end if;

    if exists (
      select 1 from jsonb_array_elements(p_lines) as l
      where coalesce((l.value->>'vat')::boolean, true) = false
    ) then
      raise exception 'Only a Manager can turn off VAT for an item';
    end if;
  end if;

  select vat_rate into v_rate from public.business_settings where id = 1;
  v_total := public.compute_sale_total(p_lines, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate);
  select coalesce(sum((value->>'amount')::numeric), 0), coalesce(sum(case when value->>'method' = 'Cash' then (value->>'amount')::numeric else 0 end), 0), coalesce(sum(case when value->>'method' <> 'Cash' then (value->>'amount')::numeric else 0 end), 0) into v_paid, v_cash, v_non_cash from jsonb_array_elements(p_payments);
  if jsonb_array_length(p_payments) = 0 or v_paid < v_total - .01 or v_non_cash > v_total + .01 then raise exception 'Payments must cover the sale; only cash may exceed the total'; end if;
  for v_payment in select value from jsonb_array_elements(p_payments) loop
    if (v_payment->>'method') not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer') or coalesce((v_payment->>'amount')::numeric, 0) <= 0 then raise exception 'Invalid POS payment'; end if;
  end loop;
  for v_line in select value from jsonb_array_elements(p_lines) order by (value->>'product_id')::uuid loop
    select * into v_product from public.products where id = (v_line->>'product_id')::uuid and branch_id = p_branch_id for update;
    if not found then raise exception 'Product % is not available at this branch', v_line->>'product_id'; end if;
    if v_product.stock < (v_line->>'quantity')::integer then raise exception 'Insufficient stock for %', v_product.name; end if;
  end loop;
  insert into public.sale_number_counters(year_month, last_number) values(v_year_month, 1) on conflict(year_month) do update set last_number = sale_number_counters.last_number + 1 returning last_number into v_seq;
  v_id := 'POS-' || v_year_month || lpad(v_seq::text, 4, '0');
  insert into public.sales(id, branch_id, customer_id, customer_name, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total, override_authorized_by) values(v_id, p_branch_id, p_customer_id, p_customer_name, p_sale_discount_mode, p_sale_discount_value, p_vat_mode, v_rate, v_total, v_override_manager_id) returning * into v_sale;
  insert into public.sale_lines(sale_id, product_id, name, unit, category, quantity, unit_price, discount_mode, discount_value, vat, position)
  select v_id, (line->>'product_id')::uuid, line->>'name', line->>'unit', line->>'category', (line->>'quantity')::integer, (line->>'unit_price')::numeric, coalesce(line->>'discount_mode', 'amount'), coalesce((line->>'discount_value')::numeric, 0), coalesce((line->>'vat')::boolean, true), ord - 1 from jsonb_array_elements(p_lines) with ordinality as t(line, ord);
  for v_line in select value from jsonb_array_elements(p_lines) loop
    update public.products set stock = stock - (v_line->>'quantity')::integer where id = (v_line->>'product_id')::uuid returning * into v_product;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_product.id, p_branch_id, 'Sale', -(v_line->>'quantity')::integer, v_product.stock, v_id);
  end loop;
  insert into public.sale_payments(sale_id, branch_id, method, amount, reference) select v_id, p_branch_id, payment->>'method', (payment->>'amount')::numeric, coalesce(payment->>'reference', '') from jsonb_array_elements(p_payments) payment;
  perform public.post_sale_journal_entry(v_id);
  return v_sale;
end; $$;

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
  perform public.require_writable_role();

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

  perform public.post_invoice_journal_entry(v_id);
  return v_invoice;
end;
$$;

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
  perform public.require_writable_role();

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

  perform public.post_invoice_payment_journal_entry(v_payment.id);
  return v_payment;
end;
$$;

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
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record an expense';
  end if;

  v_id := 'EXP-' || nextval('public.expense_number_seq')::text;

  insert into public.expenses
    (id, branch_id, date, category, description, amount, method, reference, receipt_path)
  values
    (v_id, p_branch_id, p_date, p_category, p_description, p_amount, p_method, nullif(p_reference, ''), p_receipt_path)
  returning * into v_expense;

  perform public.post_expense_journal_entry(v_id);
  return v_expense;
end;
$$;

create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text
) returns public.sale_returns language plpgsql as $$
declare v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products; v_prior integer; v_difference numeric; v_return public.sale_returns;
begin
  perform public.require_writable_role();

  if p_resolution = 'Cash refund' and not public.has_role(array['Manager']) then
    raise exception 'A cash refund requires a Manager — store credit does not';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update; if not found then raise exception 'Sale % not found', p_sale_id; end if;
  select * into v_line from public.sale_lines where id = p_returned_sale_line_id and sale_id = p_sale_id for update; if not found then raise exception 'Sale line does not belong to this sale'; end if;
  select coalesce(sum(returned_quantity), 0) into v_prior from public.sale_returns where returned_sale_line_id = p_returned_sale_line_id;
  if p_returned_quantity <= 0 or p_returned_quantity + v_prior > v_line.quantity then raise exception 'Return quantity exceeds quantity sold'; end if;
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
  perform public.post_sale_return_journal_entry(v_return.id);
  return v_return;
end; $$;

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
  perform public.require_writable_role();

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

  perform public.post_stock_adjustment_journal_entry(v_movement.id);
  return v_movement;
end;
$$;

create or replace function public.close_day(
  p_branch_id uuid,
  p_counted_cash numeric,
  p_manual_sales_total numeric,
  p_manual_transaction_count integer,
  p_notes text default ''
)
returns public.day_closes
language plpgsql
as $$
declare
  v_open public.day_closes;
  v_totals record;
  v_expected_cash numeric;
  v_cash_variance numeric;
  v_tally_sales_variance numeric;
  v_tally_count_variance integer;
  v_row public.day_closes;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can close the day';
  end if;
  if p_counted_cash < 0 then
    raise exception 'Counted cash cannot be negative';
  end if;
  if p_manual_sales_total < 0 or p_manual_transaction_count < 0 then
    raise exception 'Manual tally figures cannot be negative';
  end if;

  select * into v_open from public.day_closes
  where branch_id = p_branch_id and business_date = current_date;
  if not found then
    raise exception 'Confirm this morning''s opening float before closing the day';
  end if;
  if v_open.closed_at is not null then
    raise exception 'Today has already been closed';
  end if;

  select * into v_totals from public.compute_day_totals(p_branch_id, current_date);

  v_expected_cash := v_open.opening_float + v_totals.cash_sales - v_totals.cash_refunds - v_totals.cash_expenses;
  v_cash_variance := p_counted_cash - v_expected_cash;
  v_tally_sales_variance := p_manual_sales_total - v_totals.system_sales_total;
  v_tally_count_variance := p_manual_transaction_count - v_totals.system_transaction_count;

  update public.day_closes set
    cash_sales = v_totals.cash_sales,
    mobile_money_sales = v_totals.mobile_money_sales,
    card_sales = v_totals.card_sales,
    bank_transfer_sales = v_totals.bank_transfer_sales,
    vat_collected = v_totals.vat_collected,
    discounts_given = v_totals.discounts_given,
    cash_refunds = v_totals.cash_refunds,
    cash_expenses = v_totals.cash_expenses,
    expected_cash = v_expected_cash,
    counted_cash = p_counted_cash,
    cash_variance = v_cash_variance,
    system_sales_total = v_totals.system_sales_total,
    system_transaction_count = v_totals.system_transaction_count,
    manual_sales_total = p_manual_sales_total,
    manual_transaction_count = p_manual_transaction_count,
    tally_sales_variance = v_tally_sales_variance,
    tally_count_variance = v_tally_count_variance,
    notes = coalesce(p_notes, ''),
    closed_at = now()
  where id = v_open.id and closed_at is null
  returning * into v_row;
  if not found then
    raise exception 'Today has already been closed';
  end if;

  perform public.post_day_close_journal_entry(v_row.id);
  return v_row;
end;
$$;

create or replace function public.record_bank_deposit(
  p_branch_id uuid,
  p_amount numeric,
  p_date date,
  p_source text,
  p_reference text default '',
  p_note text default ''
)
returns public.bank_deposits
language plpgsql
as $$
declare
  v_row public.bank_deposits;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record a bank/mobile money deposit';
  end if;
  if p_amount <= 0 then
    raise exception 'Deposit amount must be greater than zero';
  end if;
  if p_source not in ('Cash', 'Mobile Money') then
    raise exception 'Invalid deposit source';
  end if;

  insert into public.bank_deposits (branch_id, amount, date, source, reference, note)
  values (p_branch_id, p_amount, p_date, p_source, coalesce(p_reference, ''), coalesce(p_note, ''))
  returning * into v_row;

  perform public.post_bank_deposit_journal_entry(v_row.id);
  return v_row;
end;
$$;
