-- Pro-forma Invoices & Withholding Tax (Phase 2, Session 19).
--
-- business-app-spec.md item 19: "a non-binding quote type with its own
-- numbering sequence, no ledger or stock impact until converted to a real
-- invoice; a WHT toggle available to both Attendant and Manager (a factual
-- determination, not a discretionary override, no PIN gate needed), with a
-- new WHT credit receivable asset account. Confirm the exact rate and
-- calculation base with an accountant before this handles real
-- transactions."
--
-- ================================================================ part 1:
-- Withholding Tax
--
-- FLAGGED PER THE SESSION BRIEF, NOT YET ACCOUNTANT-CONFIRMED: the 3%
-- default rate, "taxable subtotal" (post-discount, pre-VAT — the same base
-- compute_invoice_posting_amounts() already uses for the VAT calculation)
-- as the calculation base, and the recognition timing decision below are
-- all this session's own best-effort implementation, not a verified
-- statutory position. Do not treat this as tax advice or use it against
-- real transactions before a real accountant confirms the rate, the base,
-- and the timing.
--
-- Recognition timing (a real judgment call this session had to make, the
-- spec doesn't settle it): WHT is booked atomically at invoice CREATION
-- time, not deferred to whenever the customer actually pays. In strict
-- practice a customer withholds tax at the moment they pay, so recognizing
-- it at invoice issue is an approximation — but deferring it correctly would
-- mean prorating WHT across however many partial payments an invoice ends
-- up receiving, real complexity nothing in this session's brief asked for.
-- Booking it once, atomically, alongside vat_rate/invoice_discount (which
-- are already fixed at issue time and never rewritten by update_invoice())
-- keeps WHT in the same "fixed at issue, immutable after" bucket as every
-- other invoice-time financial fact in this build, and is simple enough to
-- implement without a second, parallel posting path.
--
-- The mechanism: rather than inventing a new poster function, a WHT-applied
-- invoice gets a synthetic invoice_payments row (method = 'WHT Credit',
-- amount = wht_amount) inserted via a plain call to record_invoice_payment()
-- from inside create_invoice() — the exact same function a real cash/
-- mobile-money/bank payment already goes through. This works because
-- record_invoice_payment() already does exactly what's needed: it
-- increments amount_paid, recomputes balance, and posts Dr <method account>
-- / Cr Accounts Receivable via the existing payment_method_account()
-- mapping (extended below with 'WHT Credit' -> 1150) — the same "Store
-- Credit is a payment method that reduces AR without cash moving" shape
-- already established for customer store credit, just pointed at a
-- different account. The result: the invoice-creation entry still posts Dr
-- 1100 AR / Cr 4000 Revenue / Cr 2100 VAT for the FULL total, unchanged —
-- "the invoice still shows full revenue" is true by construction, since
-- nothing about post_invoice_journal_entry() changes — and the synthetic
-- payment's own entry (Dr 1150 WHT Credit Receivable / Cr 1100 AR, for
-- wht_amount) nets AR down to exactly (total - wht_amount): what the
-- customer actually still owes in cash. A normal payment for that reduced
-- balance settles the invoice completely, matching "the customer's actual
-- payment is invoice total minus WHT" literally, with zero special-casing
-- anywhere in record_invoice_payment() itself.
--
-- update_invoice() is deliberately NOT touched by this migration: it
-- doesn't accept a p_wht_applied parameter and its `update ... set` clause
-- never mentions wht_applied/wht_rate/wht_amount, so editing a WHT
-- invoice's line items later recomputes `total` from the current lines (as
-- it always has) but leaves the already-posted WHT credit exactly as
-- booked at creation — matching vat_rate's own "a rate change shouldn't
-- rewrite an already-issued invoice's math" precedent, extended to the WHT
-- amount for the same reason: it's already a real, immutable
-- invoice_payments row with its own journal entry by the time an edit could
-- happen, and this build's "once posted, permanent" rule (journal_entries,
-- day_closes, purchase_order_receipts, ...) applies here too. `balance`
-- still comes out correct on any edit with no extra logic, since it's
-- always just `total - amount_paid` and amount_paid already includes the
-- WHT credit from creation.
alter table public.business_settings
  add column wht_rate numeric(5, 2) not null default 3 check (wht_rate >= 0);

alter table public.invoices
  add column wht_applied boolean not null default false,
  add column wht_rate numeric(5, 2),
  add column wht_amount numeric(12, 2) not null default 0 check (wht_amount >= 0);

-- compute_invoice_posting_amounts() previously only ever ran inside
-- post_invoice_journal_entry() (SECURITY DEFINER, so the invoking role
-- never needed its own EXECUTE grant on a nested call). create_invoice()
-- calling it directly below is NOT security definer, so this grant is a
-- real, needed addition, not a formality — without it, a live Attendant/
-- Manager RPC call would fail with a bare permission error the moment
-- p_wht_applied is true.
grant execute on function public.compute_invoice_posting_amounts(jsonb, numeric, numeric) to authenticated;

alter table public.invoice_payments drop constraint invoice_payments_method_check;
alter table public.invoice_payments
  add constraint invoice_payments_method_check
  check (method in ('Cash', 'Mobile Money', 'Bank Transfer', 'Cheque', 'Store Credit', 'WHT Credit'));

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
    when 'Store Credit' then return public.account_id_by_code('2400');
    when 'WHT Credit' then return public.account_id_by_code('1150');
    else raise exception 'No GL account mapping for payment method %', p_method;
  end case;
end;
$$;

-- create_invoice() gains one new trailing parameter (p_wht_applied) and the
-- WHT calculation/booking step; everything else is unchanged from the
-- version in auto_posting_integration.sql (including the client never being
-- able to supply p_id/p_total — that discipline is untouched). A changed
-- parameter list is a different signature as far as Postgres/PostgREST are
-- concerned even with a default value on the new parameter — CREATE OR
-- REPLACE can't retarget an existing function onto a different argument
-- list, it would just create a second, separate overload alongside the old
-- one (exactly the trap CLAUDE.md documents for create_sale_return()'s own
-- history). The old 8-parameter overload is dropped explicitly first, the
-- same discipline used every time this function's signature has changed
-- before (see auth_roles_schema.sql's own drop of the 9-parameter version
-- that preceded today's 8-parameter one).
drop function if exists public.create_invoice(uuid, uuid, text, date, date, text, numeric, jsonb);

create or replace function public.create_invoice(
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb,
  p_wht_applied boolean default false
)
returns public.invoices
language plpgsql
as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_vat_rate numeric;
  v_wht_rate numeric;
  v_total numeric;
  v_posting record;
  v_taxable_subtotal numeric;
  v_wht_amount numeric := 0;
  v_invoice public.invoices;
begin
  perform public.require_writable_role();

  insert into public.invoice_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = invoice_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'INV-' || v_year_month || lpad(v_seq::text, 4, '0');

  select vat_rate, wht_rate into v_vat_rate, v_wht_rate from public.business_settings where id = 1;
  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  if p_wht_applied then
    -- Same subtotal/discount figures post_invoice_journal_entry() will
    -- independently recompute for posting — reusing this function instead
    -- of a third, parallel formula keeps the WHT base guaranteed consistent
    -- with what actually gets posted as revenue, by construction.
    select * into v_posting from public.compute_invoice_posting_amounts(p_lines, p_invoice_discount, v_total);
    v_taxable_subtotal := v_posting.subtotal - v_posting.discount;
    v_wht_amount := round(v_taxable_subtotal * (v_wht_rate / 100), 2);
  end if;

  insert into public.invoices
    (id, branch_id, customer_id, customer_name, date, due_date, notes, invoice_discount, vat_rate, total, amount_paid, balance, wht_applied, wht_rate, wht_amount)
  values
    (v_id, p_branch_id, p_customer_id, p_customer_name, p_date, p_due_date, p_notes, p_invoice_discount, v_vat_rate, v_total, 0, v_total, p_wht_applied, case when p_wht_applied then v_wht_rate else null end, v_wht_amount)
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

  if v_wht_amount > 0 then
    perform public.record_invoice_payment(
      v_id, v_wht_amount, 'WHT Credit', '',
      format('Withholding tax at %s%% on issue, held as a receivable pending remittance', v_wht_rate),
      now()
    );
    select * into v_invoice from public.invoices where id = v_id;
  end if;

  return v_invoice;
end;
$$;

-- ================================================================ part 2:
-- Pro-forma Invoices
--
-- Deliberately the same header/line shape as invoices (per the brief) minus
-- everything that only makes sense once real money/stock/tax is involved:
-- no amount_paid/balance (a quote is never paid), no wht_applied (WHT is a
-- toggle "on invoices" per the brief's own wording — a pro-forma is
-- non-binding, so finalizing WHT terms is deferred to the moment it
-- actually becomes a real invoice, at conversion), no issued_by trigger
-- forcing identity the way invoices/expenses/sales do... actually it does
-- get one, for the same reason every other "who did this" column in this
-- build does: `created_by` here, not `issued_by`, naming it for what it
-- actually is (nothing is "issued" until conversion).
--
-- No update_pro_forma_invoice() and no delete-and-fix path: nothing in this
-- session's brief asked for editing a quote, and a mis-typed pro-forma is
-- cheap to just re-create (unlike a real invoice, it carries no ledger/
-- stock/AR consequence to unwind) — matching this build's habit of only
-- building an edit/reversal path when something has a real, hard-to-undo
-- consequence (journal_entries' reverse_journal_entry(), invoices' own
-- update_invoice() for a real, already-issued document).
create table public.pro_forma_invoice_number_counters (
  year_month text primary key,
  last_number integer not null default 0 check (last_number >= 0)
);

grant select, insert, update on public.pro_forma_invoice_number_counters to authenticated;
grant select, insert, update on public.pro_forma_invoice_number_counters to service_role;

create table public.pro_forma_invoices (
  -- 'PF-YYMM####', matching invoices'/journal_entries'/purchase_orders' own
  -- human-facing sequential id convention, not the products/customers uuid
  -- one — this is shown to customers and referenced by staff by name.
  id text primary key,
  branch_id uuid not null references public.branches (id) on delete restrict,
  customer_id uuid not null references public.customers (id) on delete restrict,
  customer_name text not null,
  date date not null,
  -- "Valid until", not a payment due date — same column name as invoices
  -- for schema-shape parity (per the brief), different real-world meaning
  -- since nothing is owed yet.
  due_date date not null,
  notes text not null default '',
  invoice_discount numeric(12, 2) not null default 0 check (invoice_discount >= 0),
  vat_rate numeric(5, 2) not null default 20 check (vat_rate >= 0),
  total numeric(12, 2) not null default 0 check (total >= 0),
  status text not null default 'open' check (status in ('open', 'converted')),
  converted_invoice_id text references public.invoices (id) on delete set null,
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now()
);

create index pro_forma_invoices_customer_idx on public.pro_forma_invoices (customer_id);
create index pro_forma_invoices_status_idx on public.pro_forma_invoices (status);

create table public.pro_forma_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  pro_forma_invoice_id text not null references public.pro_forma_invoices (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  name text not null,
  unit text not null,
  quantity numeric(12, 2) not null check (quantity > 0),
  unit_price numeric(12, 2) not null default 0 check (unit_price >= 0),
  discount numeric(12, 2) not null default 0 check (discount >= 0),
  vat boolean not null default true,
  position integer not null default 0
);

create index pro_forma_invoice_lines_parent_idx on public.pro_forma_invoice_lines (pro_forma_invoice_id, position);

create or replace function public.set_pro_forma_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger pro_forma_invoices_set_created_by
before insert on public.pro_forma_invoices
for each row execute function public.set_pro_forma_created_by();

-- Same create-can't-overwrite shape as create_invoice(): no p_id/p_total,
-- database-generated number, total computed server-side via the same
-- compute_invoice_total() invoices already use (one implementation of the
-- pricing formula, not a second one to keep in sync).
create or replace function public.create_pro_forma_invoice(
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb
)
returns public.pro_forma_invoices
language plpgsql
as $$
declare
  v_year_month text := to_char(now(), 'YYMM');
  v_seq integer;
  v_id text;
  v_vat_rate numeric;
  v_total numeric;
  v_row public.pro_forma_invoices;
begin
  perform public.require_writable_role();

  insert into public.pro_forma_invoice_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = pro_forma_invoice_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'PF-' || v_year_month || lpad(v_seq::text, 4, '0');

  select vat_rate into v_vat_rate from public.business_settings where id = 1;
  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  insert into public.pro_forma_invoices
    (id, branch_id, customer_id, customer_name, date, due_date, notes, invoice_discount, vat_rate, total)
  values
    (v_id, p_branch_id, p_customer_id, p_customer_name, p_date, p_due_date, p_notes, p_invoice_discount, v_vat_rate, v_total)
  returning * into v_row;

  insert into public.pro_forma_invoice_lines (pro_forma_invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
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

  return v_row;
end;
$$;

-- The one sanctioned way a pro-forma ever affects anything real. Locks the
-- pro-forma row first (so two concurrent conversion attempts can't both
-- succeed), re-checks status = 'open' under that lock, snapshots its lines
-- into the same jsonb shape create_invoice() already expects, and calls
-- create_invoice() directly — no separate insert logic to duplicate or
-- drift out of sync with a real invoice's own creation path. Issued today
-- (current_date), not the pro-forma's own (possibly much older) date —
-- issuing a real invoice is a new event, not a backdated one.
create or replace function public.convert_pro_forma_to_invoice(
  p_pro_forma_invoice_id text,
  p_due_date date,
  p_wht_applied boolean default false
)
returns public.invoices
language plpgsql
as $$
declare
  v_pf public.pro_forma_invoices;
  v_lines jsonb;
  v_invoice public.invoices;
begin
  perform public.require_writable_role();

  select * into v_pf from public.pro_forma_invoices where id = p_pro_forma_invoice_id for update;
  if not found then
    raise exception 'Pro-forma invoice % not found', p_pro_forma_invoice_id;
  end if;
  if v_pf.status <> 'open' then
    raise exception 'Pro-forma invoice % has already been converted', p_pro_forma_invoice_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'product_id', product_id, 'name', name, 'unit', unit,
    'quantity', quantity, 'unit_price', unit_price, 'discount', discount, 'vat', vat
  ) order by position), '[]'::jsonb)
  into v_lines
  from public.pro_forma_invoice_lines
  where pro_forma_invoice_id = p_pro_forma_invoice_id;

  v_invoice := public.create_invoice(
    v_pf.branch_id, v_pf.customer_id, v_pf.customer_name, current_date, p_due_date,
    v_pf.notes, v_pf.invoice_discount, v_lines, p_wht_applied
  );

  update public.pro_forma_invoices
  set status = 'converted', converted_invoice_id = v_invoice.id
  where id = p_pro_forma_invoice_id;

  return v_invoice;
end;
$$;

-- ============================================================ RLS + grants
--
-- Matches invoices' own tier exactly (the generic "any active staff reads,
-- can_write() writes, Manager deletes" shape role_permissions_rewrite.sql
-- put on invoices itself) — a pro-forma quote is squarely inside "Attendant
-- can create and issue invoices" per section 6, just for a document that
-- precedes the real one.
alter table public.pro_forma_invoices enable row level security;
alter table public.pro_forma_invoice_lines enable row level security;

create policy pro_forma_invoices_select on public.pro_forma_invoices
for select using (public.is_active_staff());
create policy pro_forma_invoices_insert on public.pro_forma_invoices
for insert with check (public.can_write());
create policy pro_forma_invoices_update on public.pro_forma_invoices
for update using (public.can_write()) with check (public.can_write());
create policy pro_forma_invoices_delete on public.pro_forma_invoices
for delete using (public.has_role(array['Manager']));

create policy pro_forma_invoice_lines_select on public.pro_forma_invoice_lines
for select using (public.is_active_staff());
create policy pro_forma_invoice_lines_insert on public.pro_forma_invoice_lines
for insert with check (public.can_write());
create policy pro_forma_invoice_lines_update on public.pro_forma_invoice_lines
for update using (public.can_write()) with check (public.can_write());
create policy pro_forma_invoice_lines_delete on public.pro_forma_invoice_lines
for delete using (public.has_role(array['Manager']));

grant select, insert, update, delete on public.pro_forma_invoices to authenticated;
grant select, insert, update, delete on public.pro_forma_invoices to service_role;
grant select, insert, update, delete on public.pro_forma_invoice_lines to authenticated;
grant select, insert, update, delete on public.pro_forma_invoice_lines to service_role;

-- create_invoice()'s new 9-parameter overload needs its own fresh grant
-- (the old 8-parameter overload's grant doesn't carry over to a differently-
-- shaped function, and that overload no longer exists after the drop
-- above); the two new pro-forma functions need first-time grants too.
grant execute on function public.create_invoice(uuid, uuid, text, date, date, text, numeric, jsonb, boolean) to authenticated;
grant execute on function public.create_pro_forma_invoice(uuid, uuid, text, date, date, text, numeric, jsonb) to authenticated;
grant execute on function public.convert_pro_forma_to_invoice(text, date, boolean) to authenticated;
