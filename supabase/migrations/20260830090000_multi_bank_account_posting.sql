-- Multi-bank-account posting.
--
-- The gap (investigated and reported before this migration): every
-- Card / Bank Transfer / Cheque settlement — across POS, invoicing,
-- expenses, sale-return top-ups and supplier payments — plus every bank
-- deposit, funnelled into ONE shared ledger account, 1010 Cash in Bank,
-- via payment_method_account(). bank_accounts.gl_account_id is `unique`,
-- so only the first real bank account could ever be connected; a second
-- had no distinct GL account to point at, and Bank Reconciliation (which
-- distinguishes one bank from another ONLY by which GL account its
-- activity landed on — there is no bank_account_id on journal_lines or on
-- any transaction row) could not tell two banks' activity apart even if
-- the constraint were dropped. It "worked" purely because exactly one
-- bank existed.
--
-- The fix, in one migration:
--
--   1. 1010 Cash in Bank becomes a NON-POSTABLE rollup parent
--      (accounts.is_postable = false). A BEFORE INSERT trigger on
--      journal_lines rejects any new direct posting to it (reversals of
--      pre-existing 1010 activity are still allowed — historical postings
--      must stay correctable). Existing 1010 journal lines are left
--      EXACTLY where they are; nothing is rewritten or moved.
--
--   2. Every real bank account gets its own dedicated, postable Assets
--      sub-account (1011, 1012, ...). create_bank_account() provisions (or
--      attaches) one in the same step a bank account is created, so the
--      two can never be out of sync. Existing bank accounts that were
--      pointed at 1010 are repointed here to a freshly-provisioned
--      sub-account each.
--
--   3. The real bank account is captured EXPLICITLY on each transaction at
--      entry time — a new bank_account_id column on sale_payments,
--      invoice_payments, expenses, supplier_payments and sale_returns
--      (bank_deposits already had one since Session 16). Not a default
--      setting, not a method->bank mapping: this business routes different
--      transactions to different accounts transaction by transaction
--      (clearing cheques through one bank, sales toward a purchase through
--      another), so the choice is made per transaction and is never
--      silently guessed when more than one real option exists.
--
--   4. settlement_account(method, bank_account_id) replaces
--      payment_method_account() for the bank-settled methods in every
--      poster: it resolves Card/Bank Transfer/Cheque/Bank to that
--      transaction's own bank account's sub-account, and RAISES if a
--      bank-settled method arrives with no bank account — no silent
--      fallback to 1010 anywhere. payment_method_account() keeps the fixed
--      mappings for the non-bank methods (Cash -> 1000, Mobile Money ->
--      1020, Store Credit -> 2400, WHT Credit -> 1150) and now raises on
--      the bank methods rather than returning 1010.
--
-- Scope note: the user's brief named POS, invoicing, expenses and bank
-- deposits for the selector UI. Sale-return top-ups and supplier payments
-- also settle Card/Bank Transfer/Cheque to a bank, so they get the same
-- bank_account_id capture and selector here too — the "never silently
-- guess" rule and the reconciliation-correctness goal both require it, and
-- leaving them posting to a now-non-postable 1010 would be a regression,
-- not a smaller change.

-- ============================================================ 1. is_postable

alter table public.accounts
  add column is_postable boolean not null default true;

comment on column public.accounts.is_postable is
  'False for a rollup/parent account that must never receive a direct journal line (e.g. 1010 Cash in Bank once each real bank account has its own dedicated sub-account). Enforced structurally by the journal_lines_reject_non_postable trigger; a reversal of pre-existing activity on such an account is still allowed.';

-- Structural boundary: every write path into journal_lines goes through
-- this (auto-posters, post_journal_entry() for manual entries, a raw
-- INSERT). SECURITY DEFINER + fixed search_path so it reads accounts /
-- journal_entries regardless of the caller's own grants.
create or replace function public.reject_non_postable_journal_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_postable boolean;
  v_code text;
  v_is_reversal boolean;
begin
  select is_postable, code into v_postable, v_code
  from public.accounts where id = new.account_id;

  if v_postable is null then
    raise exception 'Journal line references unknown account %', new.account_id;
  end if;

  if v_postable then
    return new;
  end if;

  -- A reversal of pre-existing activity on a rollup account is legitimate —
  -- historical postings to 1010 that predate the sub-account split must
  -- stay correctable. Only brand-new, originating activity is blocked.
  select reverses_entry_id is not null into v_is_reversal
  from public.journal_entries where id = new.entry_id;

  if coalesce(v_is_reversal, false) then
    return new;
  end if;

  raise exception 'Account % is a non-postable rollup account and cannot receive a direct journal line — post to the specific sub-account instead', v_code;
end;
$$;

create trigger journal_lines_reject_non_postable
before insert on public.journal_lines
for each row execute function public.reject_non_postable_journal_line();

-- ============================================================ 2. bank_account_id columns

alter table public.sale_payments
  add column bank_account_id uuid references public.bank_accounts (id) on delete restrict;
alter table public.invoice_payments
  add column bank_account_id uuid references public.bank_accounts (id) on delete restrict;
alter table public.expenses
  add column bank_account_id uuid references public.bank_accounts (id) on delete restrict;
alter table public.supplier_payments
  add column bank_account_id uuid references public.bank_accounts (id) on delete restrict;
alter table public.sale_returns
  add column bank_account_id uuid references public.bank_accounts (id) on delete restrict;

-- Shape backstop: a bank_account_id may only ever accompany a bank-settled
-- method. This validates TRUE against every historical row immediately
-- (they all have a null bank_account_id), so no NOT VALID / backfill dance
-- is needed. The stronger half — "a bank-settled method REQUIRES a bank
-- account" — is enforced by each create RPC (a friendly error) and, as the
-- real structural stop, by settlement_account() inside the poster, which
-- runs in the same transaction and raises before anything commits.
alter table public.sale_payments add constraint sale_payments_bank_account_shape
  check (bank_account_id is null or method in ('Card', 'Bank Transfer'));
alter table public.invoice_payments add constraint invoice_payments_bank_account_shape
  check (bank_account_id is null or method in ('Bank Transfer', 'Cheque'));
alter table public.supplier_payments add constraint supplier_payments_bank_account_shape
  check (bank_account_id is null or method in ('Bank Transfer', 'Cheque'));
alter table public.expenses add constraint expenses_bank_account_shape
  check (bank_account_id is null or method = 'Bank');
alter table public.sale_returns add constraint sale_returns_bank_account_shape
  check (bank_account_id is null or payment_method in ('Card', 'Bank Transfer'));

-- ============================================================ 3. settlement resolution

-- Non-bank methods keep their fixed mapping; the bank methods now RAISE
-- rather than returning 1010, so nothing can silently keep posting to the
-- shared account. Every caller that legitimately handles a bank method
-- calls settlement_account() below instead.
create or replace function public.payment_method_account(p_method text)
returns uuid
language plpgsql
stable
as $$
begin
  case p_method
    when 'Cash' then return public.account_id_by_code('1000');
    when 'Mobile Money' then return public.account_id_by_code('1020');
    when 'Store Credit' then return public.account_id_by_code('2400');
    when 'WHT Credit' then return public.account_id_by_code('1150');
    when 'Card', 'Bank Transfer', 'Bank', 'Cheque' then
      raise exception 'Card/Bank Transfer/Cheque settlements route to a specific bank account — use settlement_account(method, bank_account_id), not payment_method_account()';
    else raise exception 'No GL account mapping for payment method %', p_method;
  end case;
end;
$$;

-- The single place a payment method + optional bank account resolves to a
-- GL account. Card/Bank Transfer/Cheque/Bank -> that bank account's own
-- dedicated sub-account (never 1010); a bank method with no bank account
-- is a hard error, not a fallback. Everything else delegates to the fixed
-- payment_method_account() mapping.
create or replace function public.settlement_account(p_method text, p_bank_account_id uuid)
returns uuid
language plpgsql
stable
as $$
declare
  v_gl uuid;
begin
  if p_method in ('Card', 'Bank Transfer', 'Bank', 'Cheque') then
    if p_bank_account_id is null then
      raise exception 'A bank account must be specified for a % settlement', p_method;
    end if;
    select gl_account_id into v_gl from public.bank_accounts where id = p_bank_account_id;
    if v_gl is null then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
    return v_gl;
  end if;
  return public.payment_method_account(p_method);
end;
$$;

grant execute on function public.settlement_account(text, uuid) to authenticated;
grant execute on function public.settlement_account(text, uuid) to service_role;

-- ============================================================ 4. GL sub-account provisioning

-- Provisions the next free 10NN Assets sub-account for a bank account.
-- SECURITY DEFINER so it can insert into accounts regardless of the
-- caller's own grants, but reachable ONLY from create_bank_account()
-- (also SECURITY DEFINER, Manager-gated) and this migration's own repoint
-- block — never granted to anon/authenticated, so an Attendant can't use
-- it to mint arbitrary GL accounts around create_account()'s Manager gate.
create or replace function public._provision_bank_gl_account(p_bank_name text, p_created_by uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
  v_code text := null;
  v_id uuid;
begin
  for v_n in 11..99 loop
    if not exists (select 1 from public.accounts where code = '10' || v_n::text) then
      v_code := '10' || v_n::text;
      exit;
    end if;
  end loop;
  if v_code is null then
    raise exception 'No free 10NN ledger sub-account code is available for a new bank account';
  end if;

  insert into public.accounts (code, name, category, subtype, description, created_by, is_postable)
  values (
    v_code,
    'Cash in Bank — ' || p_bank_name,
    'Assets', 'Current Asset',
    'Dedicated ledger sub-account for the bank account "' || p_bank_name || '". Card/Bank Transfer/Cheque settlements and deposits for this bank post here, not to the 1010 rollup.',
    p_created_by,
    true
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public._provision_bank_gl_account(text, uuid) from public;

-- A bank account can only link to a postable, Assets-category account that
-- isn't the 1010 rollup itself.
create or replace function public.validate_bank_account_gl_link()
returns trigger
language plpgsql
as $$
declare
  v_category text;
  v_postable boolean;
  v_code text;
begin
  select category, is_postable, code into v_category, v_postable, v_code
  from public.accounts where id = new.gl_account_id;
  if v_category is null then
    raise exception 'Ledger account % not found', new.gl_account_id;
  end if;
  if v_category <> 'Assets' then
    raise exception 'A bank account must be linked to an Assets-category ledger account';
  end if;
  if v_code = '1010' then
    raise exception '1010 Cash in Bank is the rollup parent — link a dedicated sub-account (1011, 1012, ...) instead, or pass a null gl account to create_bank_account() to have one provisioned';
  end if;
  if not v_postable then
    raise exception 'A bank account must link to a postable ledger account';
  end if;
  return new;
end;
$$;

-- create_bank_account() gains "provision or attach": p_gl_account_id is now
-- optional (nullable). Null -> a dedicated sub-account is provisioned in
-- the same step. Non-null -> that existing account is attached (validated
-- by the trigger above). Becomes SECURITY DEFINER because it now inserts
-- into accounts as well as bank_accounts; its own has_role(['Manager'])
-- check is the boundary, exactly as before. The old 6-arg required-
-- p_gl_account_id signature is dropped explicitly first (a changed
-- parameter list is a new overload otherwise — the trap CLAUDE.md
-- documents for create_sale_return()/create_invoice()).
drop function if exists public.create_bank_account(text, text, uuid, numeric, date, text);

create or replace function public.create_bank_account(
  p_name text,
  p_account_number text,
  p_opening_balance numeric,
  p_opening_balance_date date,
  p_currency text default 'GHS',
  p_gl_account_id uuid default null
)
returns public.bank_accounts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.bank_accounts;
  v_gl uuid;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can add a bank account';
  end if;

  v_gl := coalesce(p_gl_account_id, public._provision_bank_gl_account(p_name, auth.uid()));

  insert into public.bank_accounts (name, account_number, gl_account_id, opening_balance, opening_balance_date, currency)
  values (p_name, p_account_number, v_gl, p_opening_balance, p_opening_balance_date, coalesce(nullif(p_currency, ''), 'GHS'))
  returning * into v_row;

  return v_row;
exception
  when unique_violation then
    raise exception 'That ledger account is already linked to another bank account';
end;
$$;

grant execute on function public.create_bank_account(text, text, numeric, date, text, uuid) to authenticated;
grant execute on function public.create_bank_account(text, text, numeric, date, text, uuid) to service_role;

-- ============================================================ 5. repoint existing bank accounts

do $$
declare
  v_1010 uuid;
  v_ba record;
  v_new_gl uuid;
begin
  select id into v_1010 from public.accounts where code = '1010';

  -- Refuse with an open reconciliation: repointing a bank account's
  -- gl_account_id would leave any already-matched statement line in that
  -- open session pointing at a journal line on the old (now rollup)
  -- account. Completed reconciliations are immutable and unaffected.
  if exists (select 1 from public.bank_reconciliations where completed_at is null) then
    raise exception 'Complete or cancel every open bank reconciliation before applying this migration (repointing bank GL accounts would orphan an in-progress reconciliation''s matched lines)';
  end if;

  -- gl_account_id is trigger-immutable (Session 16); this one-time,
  -- deliberate repoint needs that trigger off for the duration.
  alter table public.bank_accounts disable trigger bank_accounts_prevent_immutable_change;

  for v_ba in
    select id, name, created_by from public.bank_accounts
    where gl_account_id = v_1010
    order by created_at, id
  loop
    v_new_gl := public._provision_bank_gl_account(v_ba.name, v_ba.created_by);
    update public.bank_accounts set gl_account_id = v_new_gl where id = v_ba.id;
    raise notice 'Repointed bank account "%" onto a dedicated ledger sub-account', v_ba.name;
  end loop;

  alter table public.bank_accounts enable trigger bank_accounts_prevent_immutable_change;

  -- 1010 is now the rollup parent. Pre-existing journal lines on it stay
  -- exactly where they are — this only stops NEW direct postings. Any bank
  -- statement line still unmatched at this point that refers to
  -- pre-migration bank activity can no longer be matched to that activity
  -- (it lives on the 1010 rollup, not the new sub-account); clear such a
  -- line with a note during the next reconciliation.
  update public.accounts set is_postable = false where id = v_1010;
end;
$$;

-- ============================================================ 6. posters use settlement_account()

-- POS sale: one debit line per (method, bank_account_id) combination
-- actually used — a split Card+Cash sale, or two Card legs cleared through
-- two different banks, each post to their own account.
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
  v_cost_incomplete boolean;
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

  select coalesce(sum(sl.quantity * coalesce(p.cost, 0)), 0), bool_or(p.cost is null)
  into v_cogs, v_cost_incomplete
  from public.sale_lines sl join public.products p on p.id = sl.product_id
  where sl.sale_id = p_sale_id;

  for v_payment in
    select method, bank_account_id, sum(amount) as amount
    from public.sale_payments where sale_id = p_sale_id
    group by method, bank_account_id
  loop
    if v_payment.amount > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'account_id', public.settlement_account(v_payment.method, v_payment.bank_account_id),
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
      'debit', v_cogs, 'credit', 0,
      'description', case when v_cost_incomplete then 'Cost of goods sold (estimated — cost price missing for one or more items)' else 'Cost of goods sold' end
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
    v_sale.branch_id, v_sale.sold_at::date, 'POS sale ' || p_sale_id, p_sale_id, v_lines, 'sales', p_sale_id,
    coalesce(v_cost_incomplete, false)
  );
end;
$$;

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
      'account_id', public.settlement_account(v_payment.method, v_payment.bank_account_id),
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
      'account_id', public.settlement_account(v_expense.method, v_expense.bank_account_id),
      'debit', 0, 'credit', v_expense.amount, 'description', v_expense.method
    )
  );

  return public._post_journal_entry_rows(
    v_expense.branch_id, v_expense.date, v_expense.description, p_expense_id, v_lines, 'expenses', p_expense_id
  );
end;
$$;

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
      'account_id', public.settlement_account(v_payment.method, v_payment.bank_account_id),
      'debit', 0, 'credit', v_payment.amount, 'description', v_payment.method
    )
  );

  return public._post_journal_entry_rows(
    v_payment.branch_id, v_payment.paid_at::date, 'Payment to supplier on ' || v_payment.purchase_order_id, p_payment_id::text,
    v_lines, 'supplier_payments', p_payment_id::text
  );
end;
$$;

-- Return poster: full body carried verbatim from fix_return_vat_reversal.sql
-- (the latest prior definition), with the one Top-up line switched from
-- payment_method_account() to settlement_account(method, bank_account_id).
create or replace function public.post_sale_return_journal_entry(p_return_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_return public.sale_returns;
  v_sale public.sales;
  v_line public.sale_lines;
  v_line_taxable boolean;
  v_returned_cost_raw numeric;
  v_replacement_cost_raw numeric;
  v_returned_cost numeric;
  v_replacement_cost numeric;
  v_net_cogs numeric;
  v_refund_amount numeric;
  v_refund_vat numeric := 0;
  v_topup_vat numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_target_account uuid;
  v_cost_incomplete boolean := false;
begin
  select * into v_return from public.sale_returns where id = p_return_id;
  if not found then
    raise exception 'Return % not found', p_return_id;
  end if;

  select * into v_sale from public.sales where id = v_return.sale_id;
  select * into v_line from public.sale_lines where id = v_return.returned_sale_line_id;

  v_line_taxable := v_sale.vat_mode = 'all'
    or (v_sale.vat_mode = 'per-item' and v_line.vat);

  select cost into v_returned_cost_raw
  from public.products where id = v_return.returned_product_id;
  if v_returned_cost_raw is null then
    v_cost_incomplete := true;
  end if;
  v_returned_cost := coalesce(v_returned_cost_raw, 0) * v_return.returned_quantity;

  v_replacement_cost := 0;
  if v_return.replacement_product_id is not null then
    select cost into v_replacement_cost_raw
    from public.products where id = v_return.replacement_product_id;
    if v_replacement_cost_raw is null then
      v_cost_incomplete := true;
    end if;
    v_replacement_cost := coalesce(v_replacement_cost_raw, 0) * v_return.replacement_quantity;
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

  if v_return.resolution in ('Cash refund', 'Store credit') then
    v_refund_amount := abs(least(v_return.difference, 0));
    if v_refund_amount > 0 then
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

      if v_line_taxable then
        v_refund_vat := round(v_refund_amount * v_sale.vat_rate / 100, 2);
      end if;
      if v_refund_vat > 0 then
        v_lines := v_lines || jsonb_build_array(
          jsonb_build_object(
            'account_id', public.account_id_by_code('2100'),
            'debit', v_refund_vat, 'credit', 0, 'description', v_return.resolution || ' VAT reversal'
          ),
          jsonb_build_object(
            'account_id', v_target_account,
            'debit', 0, 'credit', v_refund_vat, 'description', v_return.resolution || ' VAT reversal'
          )
        );
      end if;
    end if;
  elsif v_return.resolution = 'Top-up collected' and v_return.difference > 0 then
    if v_sale.vat_mode <> 'none' then
      v_topup_vat := round(v_return.difference * v_sale.vat_rate / 100, 2);
    end if;
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', public.settlement_account(v_return.payment_method, v_return.bank_account_id),
        'debit', v_return.difference + v_topup_vat, 'credit', 0, 'description', 'Top-up collected'
      ),
      jsonb_build_object(
        'account_id', public.account_id_by_code('4000'),
        'debit', 0, 'credit', v_return.difference, 'description', 'Top-up sale revenue'
      )
    );
    if v_topup_vat > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'account_id', public.account_id_by_code('2100'),
        'debit', 0, 'credit', v_topup_vat, 'description', 'Top-up VAT collected'
      ));
    end if;
  end if;
  -- 'Even exchange' contributes no monetary lines — money-neutral by definition.

  if jsonb_array_length(v_lines) < 2 then
    return null;
  end if;

  return public._post_journal_entry_rows(
    v_return.branch_id, v_return.returned_at::date, v_return.resolution || ' on ' || v_return.sale_id,
    p_return_id::text, v_lines, 'sale_returns', p_return_id::text, v_cost_incomplete
  );
end;
$$;

-- ============================================================ 7. create RPCs thread bank_account_id

-- create_sale(): signature UNCHANGED — bank_account_id rides inside each
-- p_payments element. Bank-settled legs (Card / Bank Transfer) must carry
-- a real bank_account_id; other methods must not.
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
  v_store_credit_used numeric;
  v_customer_credit numeric;
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
    if (v_payment->>'method') not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer', 'Store Credit') or coalesce((v_payment->>'amount')::numeric, 0) <= 0 then raise exception 'Invalid POS payment'; end if;
    if (v_payment->>'method') in ('Card', 'Bank Transfer') then
      if (v_payment->>'bank_account_id') is null then
        raise exception 'Select the bank account for the % payment', v_payment->>'method';
      end if;
      if not exists (select 1 from public.bank_accounts where id = (v_payment->>'bank_account_id')::uuid) then
        raise exception 'Bank account % not found', v_payment->>'bank_account_id';
      end if;
    end if;
  end loop;

  select coalesce(sum((value->>'amount')::numeric), 0) into v_store_credit_used
  from jsonb_array_elements(p_payments)
  where value->>'method' = 'Store Credit';

  if v_store_credit_used > 0 then
    if p_customer_id is null then
      raise exception 'Store credit requires a customer to be selected — it cannot be used on a Walk-in sale';
    end if;
    select store_credit_balance into v_customer_credit from public.customers where id = p_customer_id for update;
    if not found then
      raise exception 'Customer % not found', p_customer_id;
    end if;
    if v_store_credit_used > v_customer_credit + 0.01 then
      raise exception 'Store credit payment of % exceeds the customer''s available balance of %', v_store_credit_used, v_customer_credit;
    end if;
  end if;

  -- Lock each product in stable UUID order before deducting it. The check and
  -- update happen while those row locks are held, so concurrent tills cannot oversell.
  for v_line in select value from jsonb_array_elements(p_lines) order by (value->>'product_id')::uuid loop
    select * into v_product from public.products where id = (v_line->>'product_id')::uuid and branch_id = p_branch_id for update;
    if not found then raise exception 'Product % is not available at this branch', v_line->>'product_id'; end if;
    if v_product.price is null then raise exception 'Product % has no selling price set and cannot be sold', v_product.name; end if;
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
  insert into public.sale_payments(sale_id, branch_id, method, amount, reference, bank_account_id)
  select v_id, p_branch_id, payment->>'method', (payment->>'amount')::numeric, coalesce(payment->>'reference', ''),
    case when payment->>'method' in ('Card', 'Bank Transfer') then (payment->>'bank_account_id')::uuid else null end
  from jsonb_array_elements(p_payments) payment;

  if v_store_credit_used > 0 then
    update public.customers set store_credit_balance = store_credit_balance - v_store_credit_used where id = p_customer_id;
  end if;

  perform public.post_sale_journal_entry(v_id);
  return v_sale;
end; $$;

-- record_invoice_payment(): + p_bank_account_id (7th param, default null).
-- Signature change -> drop the old 6-arg overload first, re-grant after.
drop function if exists public.record_invoice_payment(text, numeric, text, text, text, timestamptz);

create or replace function public.record_invoice_payment(
  p_invoice_id text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_note text default '',
  p_paid_at timestamptz default now(),
  p_bank_account_id uuid default null
)
returns public.invoice_payments
language plpgsql
as $$
declare
  v_branch_id uuid;
  v_total numeric;
  v_amount_paid numeric;
  v_customer_id uuid;
  v_customer_credit numeric;
  v_bank_account_id uuid;
  v_payment public.invoice_payments;
begin
  perform public.require_writable_role();

  if p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  if p_method in ('Bank Transfer', 'Cheque') then
    if p_bank_account_id is null then
      raise exception 'Select the bank account for the % payment', p_method;
    end if;
    if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
    v_bank_account_id := p_bank_account_id;
  else
    v_bank_account_id := null;
  end if;

  select branch_id, total, amount_paid, customer_id into v_branch_id, v_total, v_amount_paid, v_customer_id
  from public.invoices
  where id = p_invoice_id
  for update;

  if not found then
    raise exception 'Invoice % not found', p_invoice_id;
  end if;

  if p_amount > (v_total - v_amount_paid) + 0.01 then
    raise exception 'Payment of % exceeds the remaining balance of %', p_amount, v_total - v_amount_paid;
  end if;

  if p_method = 'Store Credit' then
    select store_credit_balance into v_customer_credit from public.customers where id = v_customer_id for update;
    if p_amount > v_customer_credit + 0.01 then
      raise exception 'Store credit payment of % exceeds the customer''s available balance of %', p_amount, v_customer_credit;
    end if;
  end if;

  insert into public.invoice_payments (invoice_id, branch_id, amount, method, reference, note, paid_at, bank_account_id)
  values (p_invoice_id, v_branch_id, p_amount, p_method, p_reference, p_note, p_paid_at, v_bank_account_id)
  returning * into v_payment;

  update public.invoices
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_total - (v_amount_paid + p_amount), 0)
  where id = p_invoice_id;

  if p_method = 'Store Credit' then
    update public.customers set store_credit_balance = store_credit_balance - p_amount where id = v_customer_id;
  end if;

  perform public.post_invoice_payment_journal_entry(v_payment.id);
  return v_payment;
end;
$$;

grant execute on function public.record_invoice_payment(text, numeric, text, text, text, timestamptz, uuid) to authenticated;
grant execute on function public.record_invoice_payment(text, numeric, text, text, text, timestamptz, uuid) to service_role;

-- create_expense(): + p_bank_account_id (9th param, default null).
drop function if exists public.create_expense(uuid, date, text, text, numeric, text, text, text);

create or replace function public.create_expense(
  p_branch_id uuid,
  p_date date,
  p_category text,
  p_description text,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_receipt_path text default null,
  p_bank_account_id uuid default null
)
returns public.expenses
language plpgsql
as $$
declare
  v_id text;
  v_bank_account_id uuid;
  v_expense public.expenses;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record an expense';
  end if;

  if p_method = 'Bank' then
    if p_bank_account_id is null then
      raise exception 'Select the bank account this expense was paid from';
    end if;
    if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
    v_bank_account_id := p_bank_account_id;
  else
    v_bank_account_id := null;
  end if;

  v_id := 'EXP-' || nextval('public.expense_number_seq')::text;

  insert into public.expenses
    (id, branch_id, date, category, description, amount, method, reference, receipt_path, bank_account_id)
  values
    (v_id, p_branch_id, p_date, p_category, p_description, p_amount, p_method, nullif(p_reference, ''), p_receipt_path, v_bank_account_id)
  returning * into v_expense;

  perform public.post_expense_journal_entry(v_id);
  return v_expense;
end;
$$;

grant execute on function public.create_expense(uuid, date, text, text, numeric, text, text, text, uuid) to authenticated;
grant execute on function public.create_expense(uuid, date, text, text, numeric, text, text, text, uuid) to service_role;

-- record_supplier_payment(): + p_bank_account_id (7th param, default null).
drop function if exists public.record_supplier_payment(text, numeric, text, text, text, timestamptz);

create or replace function public.record_supplier_payment(
  p_purchase_order_id text,
  p_amount numeric,
  p_method text,
  p_reference text default '',
  p_note text default '',
  p_paid_at timestamptz default now(),
  p_bank_account_id uuid default null
) returns public.supplier_payments language plpgsql as $$
declare
  v_branch_id uuid;
  v_received_value numeric;
  v_amount_paid numeric;
  v_bank_account_id uuid;
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

  if p_method in ('Bank Transfer', 'Cheque') then
    if p_bank_account_id is null then
      raise exception 'Select the bank account for the % payment', p_method;
    end if;
    if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
    v_bank_account_id := p_bank_account_id;
  else
    v_bank_account_id := null;
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

  insert into public.supplier_payments (purchase_order_id, branch_id, amount, method, reference, note, paid_at, bank_account_id)
  values (p_purchase_order_id, v_branch_id, p_amount, p_method, coalesce(p_reference, ''), coalesce(p_note, ''), p_paid_at, v_bank_account_id)
  returning * into v_payment;

  update public.purchase_orders
  set amount_paid = v_amount_paid + p_amount,
      balance = greatest(v_received_value - (v_amount_paid + p_amount), 0)
  where id = p_purchase_order_id;

  perform public.post_supplier_payment_journal_entry(v_payment.id);
  return v_payment;
end;
$$;

grant execute on function public.record_supplier_payment(text, numeric, text, text, text, timestamptz, uuid) to authenticated;
grant execute on function public.record_supplier_payment(text, numeric, text, text, text, timestamptz, uuid) to service_role;

-- create_sale_return(): + p_bank_account_id (11th param, default null).
-- Only meaningful for a Top-up collected via Card / Bank Transfer.
drop function if exists public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text, text, uuid);

create or replace function public.create_sale_return(
  p_sale_id text, p_returned_sale_line_id uuid, p_returned_quantity integer,
  p_replacement_product_id uuid, p_replacement_quantity integer, p_resolution text,
  p_approval_state text, p_reason text, p_payment_method text default null,
  p_customer_id uuid default null, p_bank_account_id uuid default null
) returns public.sale_returns language plpgsql as $$
declare
  v_sale public.sales; v_line public.sale_lines; v_returned public.products; v_replacement public.products;
  v_prior integer; v_difference numeric; v_return public.sale_returns; v_refund_amount numeric;
  v_credit_customer_id uuid;
  v_bank_account_id uuid;
begin
  perform public.require_writable_role();

  if p_resolution = 'Cash refund' and not public.has_role(array['Manager']) then
    raise exception 'A cash refund requires a Manager — store credit does not';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update; if not found then raise exception 'Sale % not found', p_sale_id; end if;

  v_credit_customer_id := coalesce(v_sale.customer_id, p_customer_id);
  if p_resolution = 'Store credit' then
    if v_credit_customer_id is null then
      raise exception 'Store credit requires a customer — select or add one for this return';
    end if;
    if v_sale.customer_id is null then
      perform 1 from public.customers where id = p_customer_id for update;
      if not found then raise exception 'Customer % not found', p_customer_id; end if;
    end if;
  end if;

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

  if p_resolution = 'Top-up collected' then
    if v_difference <= 0 then
      raise exception 'Top-up collected requires the replacement to cost more than the returned item';
    end if;
    if p_payment_method is null or p_payment_method not in ('Cash', 'Mobile Money', 'Card', 'Bank Transfer') then
      raise exception 'A valid payment method is required to collect a top-up';
    end if;
    if p_payment_method in ('Card', 'Bank Transfer') then
      if p_bank_account_id is null then
        raise exception 'Select the bank account for the % top-up', p_payment_method;
      end if;
      if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
        raise exception 'Bank account % not found', p_bank_account_id;
      end if;
      v_bank_account_id := p_bank_account_id;
    end if;
  end if;

  insert into public.sale_returns(sale_id, branch_id, returned_sale_line_id, returned_product_id, returned_name, returned_unit, returned_quantity, returned_unit_price, replacement_product_id, replacement_name, replacement_unit, replacement_quantity, replacement_unit_price, difference, resolution, approval_state, reason, payment_method, customer_id, bank_account_id)
  values(p_sale_id, v_sale.branch_id, v_line.id, v_line.product_id, v_line.name, v_line.unit, p_returned_quantity, v_line.unit_price, p_replacement_product_id, v_replacement.name, v_replacement.unit, p_replacement_quantity, v_replacement.price, v_difference, p_resolution, p_approval_state, coalesce(p_reason, ''), case when p_resolution = 'Top-up collected' then p_payment_method else null end, case when p_resolution = 'Store credit' and v_sale.customer_id is null then p_customer_id else null end, v_bank_account_id)
  returning * into v_return;
  update public.products set stock = stock + p_returned_quantity where id = v_returned.id returning * into v_returned;
  insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_returned.id, v_sale.branch_id, 'Return', p_returned_quantity, v_returned.stock, v_return.id::text);
  if p_replacement_product_id is not null then
    update public.products set stock = stock - p_replacement_quantity where id = v_replacement.id returning * into v_replacement;
    insert into public.stock_movements(product_id, branch_id, movement_type, change, balance_after, reason) values(v_replacement.id, v_sale.branch_id, 'Sale', -p_replacement_quantity, v_replacement.stock, v_return.id::text || ' replacement');
  end if;

  if p_resolution = 'Store credit' then
    v_refund_amount := abs(least(v_difference, 0));
    if v_refund_amount > 0 then
      update public.customers set store_credit_balance = store_credit_balance + v_refund_amount where id = v_credit_customer_id;
    end if;
  end if;

  perform public.post_sale_return_journal_entry(v_return.id);
  return v_return;
end; $$;

grant execute on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text, text, uuid, uuid) to authenticated;
grant execute on function public.create_sale_return(text, uuid, integer, uuid, integer, text, text, text, text, uuid, uuid) to service_role;
