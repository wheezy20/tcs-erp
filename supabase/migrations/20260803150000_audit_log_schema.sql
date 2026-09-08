-- Audit Log (Phase 1.5, Session 8).
--
-- business-app-spec.md section 2 calls for "every discount, VAT toggle,
-- return, and other sensitive change recorded at the database level (who,
-- when, before/after value), not just in the UI." Section 9 scopes Session 8
-- itself to exactly that: "table plus logging wired into every discount, VAT
-- override, and return" — no UI page is named for this session (that's
-- consistent with Reports/Dashboard already surfacing everything else;
-- Session 9, Manager PIN, is the next one that touches UI), so this
-- migration is backend-only: the table, the triggers, and RLS.
--
-- The central design constraint, taken directly from this session's brief:
-- entries are only ever created by triggers on the actions themselves, never
-- inserted by client code, not even by the RPCs (create_invoice(),
-- create_sale(), etc). Two things follow from that:
--   1. Logging is wired as AFTER INSERT/UPDATE triggers on the underlying
--      tables (invoices, invoice_lines, sales, sale_lines, sale_returns),
--      not as extra INSERT statements inside the RPC bodies. This matches
--      the precedent Session 7 already established for identity columns
--      ("a trigger is the only place that closes the gap for every insert
--      path at once, RPC or direct") — inventory-store.ts's addProduct()/
--      addProducts() write to stock_movements directly, bypassing
--      adjust_product_stock() entirely, so an RPC-only audit hook would have
--      the exact same blind spot an RPC-only identity hook would have had.
--   2. audit_log itself gets NO insert/update/delete grant for anyone —
--      not anon, not authenticated, not even service_role (a deliberate,
--      documented exception to the "service_role always gets full CRUD"
--      convention below — see the grants section at the bottom). The
--      trigger functions are SECURITY DEFINER, so they can write regardless
--      of what's granted to the calling role; nothing else can.
--
-- What counts as "a discount", "a VAT override", or "a return" here, and why:
--   - Invoice-level discount: invoices.invoice_discount, logged on INSERT
--     when non-zero, and on UPDATE whenever it changes (including changing
--     back to zero — removing a discount is still a change to log).
--   - Invoice line discount / VAT toggle: invoice_lines.discount /
--     invoice_lines.vat, logged on INSERT only. There is no AFTER UPDATE
--     trigger here because invoice_lines is never actually UPDATEd —
--     update_invoice() always deletes and re-inserts the full line set (see
--     the invoice_create_update_split migration), so "before" at the line
--     level is unrecoverable once that DELETE has already run in the same
--     transaction. Every insert (create AND edit) that lands a line with a
--     non-zero discount or a false VAT flag gets an audit_log row attributed
--     to whoever performed that save; this is an "as of this save" snapshot,
--     not a diff against the line's own history. Doing better would mean
--     redesigning update_invoice() away from delete+reinsert, which is out
--     of scope for this session.
--   - Sale-level discount / VAT override: sales.sale_discount_value /
--     sales.vat_mode. INSERT only — sales are immutable receipts (no
--     update_sale() exists at all), so there's no edit case to worry about.
--     vat_mode <> 'per-item' is the "whole-sale override" the spec's "VAT
--     toggle... for the whole sale" describes; per-item vat=true is the
--     default and isn't logged, per-item vat=false is.
--   - Sale line discount / VAT toggle: sale_lines.discount_value /
--     sale_lines.vat, logged on INSERT (sale_lines is likewise insert-only).
--   - Returns: sale_returns, logged unconditionally on INSERT — every return
--     is inherently sensitive per this session's own title ("...and return"),
--     not just the cash-refund path the role-permissions-rewrite migration
--     already gates.
--   invoice_lines.vat_rate and business_settings.vat_rate are deliberately
--   NOT audited here: the invoice's own vat_rate is fixed at issue time and
--   update_invoice() never rewrites it (a rate change shouldn't rewrite an
--   already-issued invoice's math, per that migration's own reasoning), and
--   changing the configured default rate in business_settings is a distinct
--   settings action, not a per-sale/per-item "override" — the word Session 8
--   actually uses.
--
-- Actor attribution: every trigger derives the actor as
-- coalesce(auth.uid(), <the row's own already-resolved identity column>).
-- For insert-only tables (sales, sale_lines, sale_returns) this is exactly
-- right either way: a live request always has auth.uid() (require_staff()/
-- require_writable_role() already reject anyone without it), and the
-- fallback only ever matters for seed.sql, which runs as the postgres
-- superuser with no auth.uid() at all — there, it correctly falls back to
-- whatever staff uuid seed.sql already attributed the row to (cashier /
-- processed_by), so re-running seed.sql produces a real, attributed
-- historical audit trail for free, with no separate audit_log seed data
-- needed. For invoices (which DO have an update path), auth.uid() is what we
-- actually want on an edit — issued_by is fixed to the original creator and
-- update_invoice() never touches it, so falling back to issued_by on an edit
-- would misattribute the edit to the original issuer whenever auth.uid() is
-- unexpectedly null; that fallback is intentionally only a safety net for
-- the no-JWT superuser context, not something a real edit should ever reach.
--
-- Read access: Manager and Accountant/Auditor only, not Attendant. The spec's
-- Roles table doesn't put an audit trail of other staff's discount/VAT/return
-- actions in Attendant's granted module list, and this is the same shape of
-- call already made for Reports (business-app-spec.md's deferred-items note:
-- "Reports must stay off-limits to Attendants entirely... that's not the
-- same as [an Attendant's] own sales history"). An audit log is an oversight
-- tool, not an operational one Attendant needs to do their job, so it gets
-- the Reports/expenses treatment (a named-roles select policy) rather than
-- the default is_active_staff() every ordinary operational table uses.
--
-- Delete: nobody, not even Manager, despite section 6's literal "Manager:
-- read and write on every model, including delete... everything." An audit
-- log a Manager can quietly delete rows from — including rows logging that
-- same Manager's own discount overrides — isn't a trustworthy audit log,
-- which is the entire point of building one. This mirrors a precedent
-- already in this codebase: `staff` has no delete policy at all, specifically
-- because "the audit trail must never lose its subject." Treating audit_log
-- itself the same way (no delete policy, for anyone) is the same principle
-- applied to the log rather than to the things it logs.

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete restrict,
  actor_id uuid not null references public.staff (id) on delete restrict,
  action text not null check (action in ('discount_applied', 'vat_override', 'return_processed')),
  entity_table text not null,
  entity_id text not null,
  before jsonb,
  after jsonb,
  occurred_at timestamptz not null default now()
);

create index audit_log_branch_id_idx on public.audit_log (branch_id);
create index audit_log_entity_idx on public.audit_log (entity_table, entity_id);
create index audit_log_actor_id_idx on public.audit_log (actor_id);
create index audit_log_occurred_at_idx on public.audit_log (occurred_at desc);

-- ============================================================ trigger functions

create or replace function public.audit_invoice_discount()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := coalesce(auth.uid(), new.issued_by);

  if tg_op = 'INSERT' then
    if new.invoice_discount <> 0 then
      insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
      values (
        new.branch_id, v_actor, 'discount_applied', 'invoices', new.id,
        null, jsonb_build_object('invoice_discount', new.invoice_discount)
      );
    end if;
    return new;
  end if;

  if old.invoice_discount is distinct from new.invoice_discount then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      new.branch_id, v_actor, 'discount_applied', 'invoices', new.id,
      jsonb_build_object('invoice_discount', old.invoice_discount),
      jsonb_build_object('invoice_discount', new.invoice_discount)
    );
  end if;
  return new;
end;
$$;

create trigger invoices_audit_discount
after insert or update on public.invoices
for each row execute function public.audit_invoice_discount();

-- No AFTER UPDATE trigger here — see the migration header for why
-- invoice_lines never has an OLD to diff against.
create or replace function public.audit_invoice_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_actor uuid;
begin
  select branch_id, coalesce(auth.uid(), issued_by)
  into v_branch_id, v_actor
  from public.invoices
  where id = new.invoice_id;

  if new.discount <> 0 then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch_id, v_actor, 'discount_applied', 'invoice_lines', new.id::text,
      null, jsonb_build_object('invoice_id', new.invoice_id, 'name', new.name, 'discount', new.discount)
    );
  end if;

  if new.vat = false then
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch_id, v_actor, 'vat_override', 'invoice_lines', new.id::text,
      null, jsonb_build_object('invoice_id', new.invoice_id, 'name', new.name, 'vat', new.vat)
    );
  end if;

  return new;
end;
$$;

create trigger invoice_lines_audit
after insert on public.invoice_lines
for each row execute function public.audit_invoice_line();

-- sales has no update path at all (immutable receipts), so INSERT is the
-- whole story for both the discount and the VAT-mode override.
create or replace function public.audit_sale_header()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := coalesce(auth.uid(), new.cashier);

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

create trigger sales_audit
after insert on public.sales
for each row execute function public.audit_sale_header();

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
  select branch_id, coalesce(auth.uid(), cashier)
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

create trigger sale_lines_audit
after insert on public.sale_lines
for each row execute function public.audit_sale_line();

-- Unconditional — every return is logged, not just the cash-refund path
-- the role-permissions-rewrite migration gates.
create or replace function public.audit_sale_return()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := coalesce(auth.uid(), new.processed_by);

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    new.branch_id, v_actor, 'return_processed', 'sale_returns', new.id::text,
    null,
    jsonb_build_object(
      'sale_id', new.sale_id,
      'returned_product_id', new.returned_product_id,
      'returned_name', new.returned_name,
      'returned_quantity', new.returned_quantity,
      'replacement_product_id', new.replacement_product_id,
      'replacement_name', new.replacement_name,
      'replacement_quantity', new.replacement_quantity,
      'difference', new.difference,
      'resolution', new.resolution,
      'reason', new.reason
    )
  );

  return new;
end;
$$;

create trigger sale_returns_audit
after insert on public.sale_returns
for each row execute function public.audit_sale_return();

-- ============================================================ RLS + grants

alter table public.audit_log enable row level security;

create policy audit_log_select on public.audit_log
for select
using (public.has_role(array['Manager', 'Accountant/Auditor']));

-- No insert/update/delete policy exists, for any role — see the migration
-- header. Only SELECT is granted, and only to authenticated (RLS narrows it
-- further to Manager/Accountant-Auditor above); anon and service_role get
-- nothing at all. This is a deliberate exception to the "service_role always
-- gets full select/insert/update/delete" convention documented in CLAUDE.md:
-- that convention's own justification is "service_role already bypasses RLS
-- by role attribute, so holding back its grant buys no real security" — but
-- RLS bypass and table GRANTs are separate layers, and audit_log's security
-- property specifically depends on the GRANT layer, not RLS, since the
-- SECURITY DEFINER trigger functions write to it regardless of what's
-- granted to the calling role. service_role is local-tooling-only today
-- (per CLAUDE.md, "only local tooling scripts authenticate as it"), and
-- there is no legitimate reason any tooling script should ever need to
-- fabricate an audit_log row by hand — so this table withholds write grants
-- from service_role too, unlike every other table in this build.
grant select on public.audit_log to authenticated;
