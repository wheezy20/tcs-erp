-- Stock Adjustment Oversight & Notifications (Phase 2, Session 18).
--
-- business-app-spec.md item 18: "Attendant can adjust stock with a mandatory
-- reason... a real notification system finally gets built, alerting a
-- Manager when an Attendant makes an adjustment. Wires up the
-- previously-unused bell icon and the Phase 1 Settings notification toggles
-- (low stock, overdue invoices, daily sales summary) for real."
--
-- ================================================================ part 1:
-- confirm/lock in "Attendant can adjust stock with a mandatory reason"
--
-- Investigated first rather than assumed, per this session's own brief:
-- adjust_product_stock() already calls require_writable_role() (Manager or
-- Attendant, only Accountant/Auditor rejected), and stock_movements_insert's
-- RLS policy is already can_write() (same two roles) — role_permissions_
-- rewrite.sql's own comment confirms this was a deliberate, considered
-- choice ("Inventory write access is UNCHANGED for Attendant... the spec's
-- Attendant capability list doesn't mention Inventory either way"). So "can
-- adjust stock" is already real and needed no change.
--
-- "Mandatory reason" was NOT already real, though — confirmed by reading,
-- not assumed: stock_movements.reason is `not null default ''`, and
-- stock-adjust-dialog.tsx's `reason.trim().length < 4` check is client-side
-- only. adjust_product_stock() itself never validated p_reason at all,
-- meaning a raw RPC call (or a client bug) could land a real stock
-- adjustment with an empty reason. Locked in two ways, matching this
-- codebase's "RPC check is a UX nicety, the real boundary is structural"
-- relationship: adjust_product_stock() now raises if p_reason is blank, and
-- a table CHECK constraint backs it up independently of that RPC — a raw
-- INSERT into stock_movements bypassing the RPC entirely (already possible
-- today, since can_write() grants any active non-Auditor staff member
-- INSERT on the table directly, not just through the RPC) is rejected too.
-- The constraint is scoped to movement_type = 'Adjustment' only, not every
-- movement type — 'Sale'/'Return'/'Purchase' rows already use `reason` for
-- a different purpose (a receipt/return/PO reference id), and blanket-
-- requiring non-blank there is a different, out-of-scope question this
-- session wasn't asked to settle.
alter table public.stock_movements
  add constraint stock_movements_adjustment_reason_required
  check (movement_type <> 'Adjustment' or trim(reason) <> '');

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

  if trim(coalesce(p_reason, '')) = '' then
    raise exception 'A reason is required to adjust stock';
  end if;

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
-- Same signature (uuid, integer, text) as every prior version of this
-- function, so CREATE OR REPLACE preserves the existing grant
-- (authenticated only, anon revoked in Session 7) with nothing to re-grant.

-- ================================================================ part 2:
-- the three Settings notification toggles, for real
--
-- These three booleans join business_settings.vat_rate as the only pieces
-- of Settings with a real backend, and for the same reason CLAUDE.md already
-- documents for that carve-out: "a database function needed a trustworthy
-- source for something client input couldn't be trusted for" — here, the
-- trigger/RPC functions below need to read "is this alert type turned on"
-- from inside Postgres itself, which a localStorage value can never answer.
-- The rest of Settings (company profile, paper sizes, editable lists, ...)
-- stays exactly as local as CLAUDE.md says it should for now; this is a
-- third narrow exception, not a start of migrating Settings wholesale.
alter table public.business_settings
  add column low_stock_alerts_enabled boolean not null default true,
  add column overdue_invoice_alerts_enabled boolean not null default true,
  add column daily_sales_summary_enabled boolean not null default false;
-- Defaults mirror the old localStorage defaults exactly (settings-store.ts's
-- `notifications: { lowStock: true, overdueInvoices: true, dailySummary:
-- false }`), so a fresh database's starting behavior matches what the app
-- already showed as "on"/"off" before this session. No new RLS policy is
-- needed — business_settings_select (any active staff) and
-- business_settings_update (Manager only, both USING and WITH CHECK already
-- explicit since the role-permissions-rewrite migration) apply row-wise to
-- the whole singleton row, these three columns included.

-- ================================================================ part 3:
-- notifications table — a personal inbox, one row per (event, recipient)
--
-- Fanned out at insert time (one row per active Manager) rather than one
-- shared "notification" row with a separate per-user read-state join table:
-- this app has exactly the shape a fan-out suits (a handful of Managers, not
-- thousands of recipients), it keeps RLS trivial (recipient_id = auth.uid(),
-- no join needed to know what's "mine" or "read"), and matches how GitHub/
-- Slack-style per-user notification inboxes are conventionally modelled.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  -- Unlike every other FK into staff in this build (all `on delete
  -- restrict`, "the audit trail must never lose its subject"), this one is
  -- `on delete cascade` deliberately: a notification is a personal inbox
  -- item, not a business record anything else needs to reference, so if a
  -- staff row were ever actually removed (it can't be today — staff has no
  -- delete policy at all — but nothing stops a future superuser cleanup),
  -- its own stale inbox rows are clutter to drop, not history to protect.
  recipient_id uuid not null references public.staff (id) on delete cascade,
  type text not null check (type in ('stock_adjustment', 'low_stock', 'overdue_invoice', 'daily_summary')),
  title text not null,
  body text not null default '',
  -- An in-app route to navigate to on click (e.g. '/inventory/<id>'), never
  -- an external URL. Null for a notification with no single natural
  -- destination (there isn't one for daily_summary beyond the reconciliation
  -- history page, which the trigger functions below always fill in).
  link text,
  -- entity_table/entity_id mirror audit_log's own shape, and serve the same
  -- two purposes here: a display cross-reference, and (for overdue_invoice
  -- specifically) the dedup key that stops the same invoice from generating
  -- a fresh notification every single day it stays overdue — see
  -- notify_overdue_invoices() below.
  entity_table text,
  entity_id text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);
create index notifications_entity_idx on public.notifications (entity_table, entity_id);

alter table public.notifications enable row level security;

create policy notifications_select on public.notifications
for select
using (recipient_id = auth.uid());

-- The only mutation a recipient ever needs is marking their own row read
-- (or un-read); a plain RLS-gated UPDATE through PostgREST is enough, the
-- same "the row-ownership check is the only real invariant, a dedicated RPC
-- would just be ceremony" call already made for customer_discounts.active /
-- setStaffActive(). No dismiss/delete path is built — nothing in this
-- session's brief asked for one, and read/unread is the only state the bell
-- icon needs.
create policy notifications_update on public.notifications
for update
using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

-- No insert or delete grant for anyone — not anon, not authenticated, not
-- even service_role. This is the same deliberate exception to the
-- "service_role always gets full CRUD" convention that audit_log uses, and
-- the same property actually applies here (CLAUDE.md is explicit that a
-- second exception needs that, not just a superficial resemblance): every
-- legitimate notifications row is created by a SECURITY DEFINER function
-- below (notify_managers(), called only from the trigger/RPC functions that
-- follow it), never by client code — structurally identical to "entries are
-- only ever created by triggers on the actions themselves" from audit_log's
-- own header. service_role is local-tooling-only per CLAUDE.md, and no
-- tooling script has any legitimate reason to fabricate a notification by
-- hand either.
grant select, update on public.notifications to authenticated;

-- ================================================================ part 4:
-- the shared fan-out helper every notification type below calls
--
-- SECURITY DEFINER so it can insert into a table with no INSERT grant for
-- any role; deliberately given NO execute grant to authenticated (or
-- anyone) at all — the same "private helper, only reachable from inside
-- another SECURITY DEFINER function's execution" shape Session 14 used for
-- _post_journal_entry_rows(). A SECURITY DEFINER function's nested calls
-- keep running as the definer, so notify_stock_adjustment()/
-- notify_low_stock() (both triggers, both SECURITY DEFINER) and
-- notify_overdue_invoices()/notify_daily_sales_summary() (both SECURITY
-- DEFINER, granted to authenticated below since close_day() calls them
-- directly under the Manager's own role) can all reach this regardless.
--
-- Scoped to "every active Manager in this branch" — per the spec's own
-- wording ("alerting a Manager") for the stock-adjustment case, extended
-- to the other two toggle-driven types too for consistency, since the spec
-- doesn't name a different audience for them and Reports/Accounting/
-- Banking/Purchasing already established the same "Manager (+ sometimes
-- Accountant/Auditor for read access)" shape for analytical, non-
-- operational information. Accountant/Auditor is deliberately left out here
-- rather than added by default: nothing in this session's brief calls for
-- it, and every existing "who sees this" precedent in this build (audit_log,
-- Reports) starts narrow and gets widened only when a session is explicitly
-- asked to. A future session can widen this without touching the schema —
-- notify_managers()'s own `role = 'Manager'` filter is the one place it
-- would change.
create or replace function public.notify_managers(
  p_branch_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_link text,
  p_entity_table text,
  p_entity_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (branch_id, recipient_id, type, title, body, link, entity_table, entity_id)
  select p_branch_id, s.id, p_type, p_title, p_body, p_link, p_entity_table, p_entity_id
  from public.staff s
  where s.branch_id = p_branch_id and s.role = 'Manager' and s.active;
end;
$$;

-- ================================================================ part 5:
-- stock_adjustment — triggered on the action itself, not called from
-- adjust_product_stock() directly
--
-- Matches the audit_log precedent exactly, and for the same reason: a
-- trigger is the only place that catches every write path to stock_movements
-- at once, not just the one going through adjust_product_stock(). In
-- practice movement_type = 'Adjustment' only ever comes from that one RPC
-- today (inventory-store.ts's addProduct()/addProducts() use 'Purchase' for
-- opening stock, receive_purchase_order() uses 'Purchase' too), but a
-- trigger doesn't depend on that staying true the way an explicit `perform`
-- call inside adjust_product_stock() alone would.
--
-- Only fires when the *performer* is an Attendant — matches the spec's own
-- framing ("alerting a Manager when an Attendant makes an adjustment"), not
-- every adjustment regardless of who made it. A Manager adjusting stock
-- themselves needs no notification about their own action.
create or replace function public.notify_stock_adjustment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_performer public.staff;
  v_product public.products;
  v_old_stock integer;
begin
  if new.movement_type <> 'Adjustment' or new.performed_by is null then
    return new;
  end if;

  select * into v_performer from public.staff where id = new.performed_by;
  if not found or v_performer.role <> 'Attendant' then
    return new;
  end if;

  select * into v_product from public.products where id = new.product_id;
  v_old_stock := new.balance_after - new.change;

  perform public.notify_managers(
    new.branch_id,
    'stock_adjustment',
    format('%s adjusted stock: %s', v_performer.name, coalesce(v_product.name, 'a product')),
    format(
      '%s%s units (%s → %s) — %s',
      case when new.change >= 0 then '+' else '' end, new.change,
      v_old_stock, new.balance_after, new.reason
    ),
    case when v_product.id is not null then '/inventory/' || v_product.id::text else null end,
    'stock_movements',
    new.id::text
  );

  return new;
end;
$$;

create trigger stock_movements_notify_adjustment
after insert on public.stock_movements
for each row execute function public.notify_stock_adjustment();

-- ================================================================ part 6:
-- low_stock — fires on the real crossing event, not on every stock write
--
-- AFTER UPDATE on products, gated by the toggle and by an actual
-- above-threshold-to-at-or-below-threshold crossing (OLD.stock > threshold
-- AND NEW.stock <= threshold) — never a bare "stock <= threshold" check,
-- which would re-fire on every single subsequent sale while a product stays
-- depleted. This also means it isn't tied to manual adjustments only: a POS
-- sale or an invoice deducting stock past the threshold notifies too, which
-- is correct and matches the toggle's own Settings description ("Notify
-- when a product drops to or below its threshold") — that's a statement
-- about the product's stock level, not about which action changed it.
-- Deliberately skips entirely when `stock` itself didn't change (a
-- threshold-only edit through the product edit dialog), so editing a
-- product's override threshold alone can never spuriously "cross" anything.
create or replace function public.notify_low_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
  v_branch_default integer;
  v_threshold integer;
begin
  if new.stock is not distinct from old.stock then
    return new;
  end if;

  select low_stock_alerts_enabled into v_enabled from public.business_settings where id = 1;
  if not coalesce(v_enabled, true) then
    return new;
  end if;

  select default_low_stock_threshold into v_branch_default from public.branches where id = new.branch_id;
  v_threshold := coalesce(new.low_stock_threshold, v_branch_default, 0);

  if old.stock > v_threshold and new.stock <= v_threshold then
    perform public.notify_managers(
      new.branch_id,
      'low_stock',
      format('Low stock: %s', new.name),
      format('%s units left · reorder at %s', new.stock, v_threshold),
      '/inventory/' || new.id::text,
      'products',
      new.id::text
    );
  end if;

  return new;
end;
$$;

create trigger products_notify_low_stock
after update on public.products
for each row execute function public.notify_low_stock();

-- ================================================================ part 7:
-- overdue_invoice and daily_summary — both hooked into close_day(), not a
-- new cron job
--
-- Neither of these has a discrete "the event just happened" write to hang a
-- trigger off, the way stock_adjustment does — "an invoice became overdue"
-- and "the day ended" are both facts about time passing, not about a row
-- being written. This project has no pg_cron (or any other scheduler)
-- configured anywhere, and standing one up wasn't part of this session's
-- brief. Session 11's close_day() is already the one deliberate, Manager-run
-- "end of day" checkpoint this app has — reusing it here matches the
-- existing discipline of hooking new side effects into an existing action
-- point rather than inventing infrastructure (Session 14's auto-posting did
-- the same thing for journal entries instead of a separate posting job).
--
-- The real limitation this carries, documented rather than silently
-- accepted: if a day is never closed, neither check ever runs for that
-- date. That's an accepted trade-off matching how this app already treats
-- close_day() elsewhere (End of Day's own figures only exist once a day is
-- closed at all) — not a gap introduced by this session.
--
-- overdue_invoice specifically notifies once per invoice, ever, not once
-- per day it stays overdue: the "not exists (... type = 'overdue_invoice')"
-- guard below is a real, structural dedup (an invoice that's still overdue
-- next week doesn't re-notify), not a convention a caller has to remember.
create or replace function public.notify_overdue_invoices(p_branch_id uuid, p_as_of date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
  v_invoice record;
begin
  select overdue_invoice_alerts_enabled into v_enabled from public.business_settings where id = 1;
  if not coalesce(v_enabled, true) then
    return;
  end if;

  for v_invoice in
    select i.* from public.invoices i
    where i.branch_id = p_branch_id
      and i.balance > 0
      and i.due_date < p_as_of
      and not exists (
        select 1 from public.notifications n
        where n.entity_table = 'invoices' and n.entity_id = i.id and n.type = 'overdue_invoice'
      )
    order by i.due_date
  loop
    perform public.notify_managers(
      p_branch_id,
      'overdue_invoice',
      format('Invoice %s is overdue', v_invoice.id),
      format(
        '%s · balance GHS %s · was due %s',
        v_invoice.customer_name,
        to_char(v_invoice.balance, 'FM999,999,990.00'),
        to_char(v_invoice.due_date, 'DD Mon YYYY')
      ),
      '/sales/' || v_invoice.id,
      'invoices',
      v_invoice.id
    );
  end loop;
end;
$$;

grant execute on function public.notify_overdue_invoices(uuid, date) to authenticated;

create or replace function public.notify_daily_sales_summary(p_day_close_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
  v_close public.day_closes;
  v_total_sales numeric;
begin
  select daily_sales_summary_enabled into v_enabled from public.business_settings where id = 1;
  if not coalesce(v_enabled, false) then
    return;
  end if;

  select * into v_close from public.day_closes where id = p_day_close_id;
  if not found then
    return;
  end if;

  v_total_sales := coalesce(v_close.cash_sales, 0) + coalesce(v_close.mobile_money_sales, 0)
    + coalesce(v_close.card_sales, 0) + coalesce(v_close.bank_transfer_sales, 0);

  perform public.notify_managers(
    v_close.branch_id,
    'daily_summary',
    format('Daily sales summary — %s', to_char(v_close.business_date, 'DD Mon YYYY')),
    format(
      'GHS %s across %s transactions · VAT GHS %s · discounts GHS %s · cash variance GHS %s',
      to_char(v_total_sales, 'FM999,999,990.00'),
      v_close.system_transaction_count,
      to_char(coalesce(v_close.vat_collected, 0), 'FM999,999,990.00'),
      to_char(coalesce(v_close.discounts_given, 0), 'FM999,999,990.00'),
      to_char(coalesce(v_close.cash_variance, 0), 'FM999,999,990.00')
    ),
    '/end-of-day/history',
    'day_closes',
    v_close.id::text
  );
end;
$$;

grant execute on function public.notify_daily_sales_summary(uuid) to authenticated;

-- close_day() itself gains two new calls, right alongside its existing
-- perform public.post_day_close_journal_entry(v_row.id) — same "one more
-- statement inside an already-atomic transaction" shape Session 14 relied
-- on for posting/close_day atomicity, here extended to notifications: if
-- close_day() rolls back for any reason, no notification for that close was
-- ever inserted either, since notify_overdue_invoices()/
-- notify_daily_sales_summary() run inside the same transaction. Full body
-- copied verbatim from auto_posting_integration.sql's version (the latest
-- prior definition — verified no migration after it redefined close_day())
-- with only the two new `perform` lines added before the final return.
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
  perform public.notify_overdue_invoices(p_branch_id, current_date);
  perform public.notify_daily_sales_summary(v_row.id);
  return v_row;
end;
$$;
