-- Manager PIN Authorization (Phase 1.5, Session 9).
--
-- business-app-spec.md's Phase 1.5 summary calls for a "Manager PIN/password
-- popup to authorize discount or VAT overrides, and to approve returns."
-- Returns are already handled: create_sale_return()'s cash-refund path
-- requires a real Manager login (role-permissions-rewrite migration), and
-- this session is explicitly told not to build a second, redundant
-- authorization path for that. What's left, and what this migration builds,
-- is the POS discount/VAT half: an Attendant, already signed in on their own
-- session, needs a way to get a specific sale's discount or VAT deviation
-- authorized by a Manager standing next to them, without switching the
-- active browser session away from the Attendant.
--
-- Password vs a numeric PIN: this migration reuses real Supabase Auth
-- email+password (the same mechanism /login already uses), not a new PIN
-- scheme. A PIN would mean inventing a whole parallel, weaker authentication
-- path — a `staff.pin` column, custom hashing, and a way to turn "PIN
-- matched" into something a signed RPC call can trust — since GoTrue itself
-- has no PIN grant type and can't hand back a real, verifiable session token
-- for one. Reusing password-grant sign-in costs nothing new: it's already
-- battle-tested (Session 7), and it produces a real Supabase Auth JWT that
-- Postgres's own auth.uid()/RLS can trust with zero additional plumbing.
--
-- The mechanism, in one paragraph: the Attendant's browser asks for a
-- Manager's email+password in a dialog, then makes a plain HTTP call to
-- GoTrue's password grant endpoint directly (bypassing the shared
-- supabase-js client entirely, so the app's persisted session/localStorage
-- never changes and the Attendant's own session is never touched) to get a
-- short-lived Manager access token. That token is used for exactly one
-- follow-up call: authorize_manager_override() below, which mints a
-- single-use, short-lived "ticket" (manager_overrides row) recording which
-- real Manager (auth.uid(), unspoofable) approved it. The Manager token is
-- then discarded — nothing about it is ever persisted client-side. The
-- Attendant's own, still-active session then calls create_sale() as normal,
-- passing the ticket id; create_sale() calls consume_manager_override()
-- (below) to redeem it exactly once, and if valid, treats this one call's
-- discount/VAT restrictions as satisfied — without ever touching `cashier`,
-- which stays the Attendant throughout, since the checkout call itself never
-- runs under the Manager's identity. This is the crux of the design: the
-- *authorization* runs as the Manager (one small RPC call, one token, thrown
-- away immediately after); the *sale* runs as the Attendant, exactly as it
-- always has.
--
-- Why this needs its own table rather than, say, a client-supplied
-- manager_id parameter on create_sale(): a bare uuid parameter is exactly
-- the kind of spoofable client input Session 7 already eliminated everywhere
-- else in this codebase (an Attendant could just type in any Manager's id).
-- A ticket minted via a real, freshly-verified Manager JWT — where
-- manager_id is forced from that JWT's own auth.uid(), the same
-- identity-forcing-trigger discipline used throughout this build, not
-- trusted from client input — is the only way to make "a Manager actually
-- approved this" a claim the database itself can verify.

-- ============================================================ manager_overrides

create table public.manager_overrides (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  -- Forced from auth.uid() by the trigger below, at the moment a Manager's
  -- fresh token calls authorize_manager_override() — this is the one column
  -- in this table whose trustworthiness is actually load-bearing.
  manager_id uuid not null default auth.uid() references public.staff (id) on delete restrict,
  -- Who asked for it. Passed as a plain parameter by the Attendant's own
  -- client (the RPC call that inserts this row runs under the MANAGER's
  -- token, which has no way to independently know the Attendant's identity —
  -- different JWT, different request) — so this is informational at mint
  -- time, not independently verified. It becomes a real check at redemption
  -- time instead: consume_manager_override() only redeems a ticket for the
  -- session whose auth.uid() matches requested_by, so a mis-declared or
  -- stolen ticket id simply can't be redeemed by anyone else.
  requested_by uuid not null references public.staff (id) on delete restrict,
  reason text not null default '',
  used_at timestamptz,
  -- Five minutes: long enough for a Manager to walk over, type credentials,
  -- and for the Attendant to finish the one checkout it's for; short enough
  -- that a leaked/forgotten ticket id can't be replayed hours later.
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  created_at timestamptz not null default now()
);

create index manager_overrides_requested_by_idx on public.manager_overrides (requested_by);

create or replace function public.set_override_manager_id()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.manager_id := auth.uid(); end if;
  return new;
end;
$$;

create trigger manager_overrides_set_manager_id
before insert on public.manager_overrides
for each row execute function public.set_override_manager_id();

-- Called with a Manager's freshly-obtained token (see the migration header).
-- Not security definer: the insert runs under the real Manager's own
-- privileges, so ordinary RLS (below) is the actual gate, same as every
-- other plain RPC in this codebase (create_sale(), create_invoice(), ...).
-- The has_role() check here exists purely to raise a clear, specific error
-- instead of a generic RLS violation, same reasoning as require_writable_role().
create or replace function public.authorize_manager_override(
  p_requested_by uuid,
  p_reason text default ''
)
returns public.manager_overrides
language plpgsql
as $$
declare
  v_branch_id uuid;
  v_row public.manager_overrides;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can authorize an override';
  end if;

  select branch_id into v_branch_id from public.staff where id = p_requested_by;
  if not found then
    raise exception 'Requesting staff member % not found', p_requested_by;
  end if;

  insert into public.manager_overrides (branch_id, requested_by, reason)
  values (v_branch_id, p_requested_by, coalesce(p_reason, ''))
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.authorize_manager_override(uuid, text) to authenticated;

-- Redeems a ticket exactly once, for exactly the staff member it was
-- requested for. SECURITY DEFINER is load-bearing here (unlike
-- authorize_manager_override() above): this runs under the ATTENDANT's own
-- session (called from inside create_sale(), which itself is not security
-- definer), and manager_overrides has no UPDATE grant for authenticated at
-- all — see the grants section below — so only this one controlled function
-- can ever mark a ticket used. Returns the authorizing manager_id so the
-- caller (create_sale()) can attribute the override correctly without
-- trusting anything the client supplied.
create or replace function public.consume_manager_override(p_ticket_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_manager_id uuid;
begin
  update public.manager_overrides
  set used_at = now()
  where id = p_ticket_id
    and requested_by = auth.uid()
    and used_at is null
    and expires_at > now()
  returning manager_id into v_manager_id;

  if not found then
    raise exception 'Manager override ticket is invalid, already used, or expired';
  end if;

  return v_manager_id;
end;
$$;

grant execute on function public.consume_manager_override(uuid) to authenticated;

alter table public.manager_overrides enable row level security;

create policy manager_overrides_select on public.manager_overrides
for select
using (public.is_active_staff());

create policy manager_overrides_insert on public.manager_overrides
for insert
with check (public.has_role(array['Manager']));

-- No update/delete policy for authenticated, on purpose — the same
-- "nothing outside its own controlled function can write to this" shape
-- Session 8 used for audit_log. consume_manager_override() is SECURITY
-- DEFINER and bypasses RLS for its own UPDATE; nothing else can flip
-- used_at, extend expires_at, or otherwise tamper with a ticket's state.
revoke all on public.manager_overrides from anon;
grant select, insert on public.manager_overrides to authenticated;
grant select, insert, update, delete on public.manager_overrides to service_role;

-- ==================================================================== sales

-- Nullable: null for an ordinary sale (no override needed), null for a sale
-- a Manager rang up directly (their own auth.uid() already attributes it
-- correctly without this column), and set only when a ticket was actually
-- redeemed for this specific sale. This is purely an audit-attribution
-- column — see the updated audit_sale_header()/audit_sale_line() below —
-- it plays no part in stock, totals, or payment logic.
alter table public.sales
  add column override_authorized_by uuid references public.staff (id) on delete restrict;

-- ============================================================ create_sale()

-- Adds one new trailing, defaulted parameter (p_override_ticket). Postgres
-- treats a different parameter list as a different overload even under
-- CREATE OR REPLACE — confirmed the hard way: without the DROP below,
-- PostgREST ended up with both the old 8-arg and new 9-arg signatures at
-- once and refused every call that omitted p_override_ticket with
-- "Could not choose the best candidate function." The DROP is what actually
-- replaces it instead of shadowing it. The one other change of substance:
-- what used to be an unconditional "if not Manager" block gating only
-- discounts now also gates VAT, and is gated by a broader v_authorized flag
-- that a redeemed ticket can also satisfy.
drop function if exists public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb);

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

  -- A Manager needs no ticket at all (matches "applying discounts...
  -- everything" being an unqualified Manager grant). Anyone else who
  -- reaches this point is necessarily an Attendant (require_writable_role()
  -- already rejected Accountant/Auditor); a redeemed, valid ticket lifts the
  -- same restrictions a Manager's own role would have lifted, and records
  -- who actually approved it for the audit trail below.
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

    -- New in this session: VAT gets the same treatment as discounts. Before
    -- now, create_sale() never restricted vat_mode or a line's vat flag for
    -- anyone — this closes that gap, matching the Phase 1.5 brief's "Manager
    -- PIN... to authorize discount OR VAT overrides" (until now there was
    -- nothing for that popup to actually gate on the VAT side).
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
  -- Lock each product in stable UUID order before deducting it. The check and
  -- update happen while those row locks are held, so concurrent tills cannot oversell.
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
  return v_sale;
end; $$;

grant execute on function public.create_sale(uuid, uuid, text, text, numeric, text, jsonb, jsonb, uuid) to authenticated;

-- ============================================== Session 8 audit attribution

-- Both functions gain the same one-line change: prefer
-- sales.override_authorized_by (set only when a ticket was actually
-- redeemed) over auth.uid() when deriving who to attribute a
-- discount_applied/vat_override entry to. For a Manager's own direct sale,
-- override_authorized_by is null and auth.uid() already correctly resolves
-- to that Manager, so behavior there is unchanged. For a ticket-authorized
-- Attendant sale, auth.uid() during create_sale() is the Attendant (they're
-- the one who called it) — exactly the misattribution this session exists
-- to prevent — so override_authorized_by has to come first.
create or replace function public.audit_sale_header()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := coalesce(new.override_authorized_by, auth.uid(), new.cashier);

  if new.sale_discount_value <> 0 then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      new.branch_id, v_actor, 'discount_applied', 'sales', new.id,
      null, jsonb_build_object('sale_discount_mode', new.sale_discount_mode, 'sale_discount_value', new.sale_discount_value)
    );
  end if;

  if new.vat_mode <> 'per-item' then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      new.branch_id, v_actor, 'vat_override', 'sales', new.id,
      null, jsonb_build_object('vat_mode', new.vat_mode)
    );
  end if;

  return new;
end;
$$;

create or replace function public.audit_sale_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_actor uuid;
begin
  select branch_id, coalesce(override_authorized_by, auth.uid(), cashier)
  into v_branch_id, v_actor
  from public.sales
  where id = new.sale_id;

  if new.discount_value <> 0 then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch_id, v_actor, 'discount_applied', 'sale_lines', new.id::text,
      null, jsonb_build_object('sale_id', new.sale_id, 'name', new.name, 'discount_mode', new.discount_mode, 'discount_value', new.discount_value)
    );
  end if;

  if new.vat = false then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch_id, v_actor, 'vat_override', 'sale_lines', new.id::text,
      null, jsonb_build_object('sale_id', new.sale_id, 'name', new.name, 'vat', new.vat)
    );
  end if;

  return new;
end;
$$;
