-- Fixes two real bugs in the Sales & Invoicing save path (Session 3):
--
-- 1. save_invoice()'s `insert ... on conflict (id) do update` meant create
--    and edit were the same operation from the database's point of view.
--    Combined with client-side invoice numbering (three unsynchronized
--    steps: read the highest number, compute the next one, write it back),
--    two near-simultaneous creates could mint the same id and the second
--    save_invoice() call would silently overwrite the first invoice's
--    header and delete+replace its line items — no error, just data loss.
--    Fixed by splitting into create_invoice() (plain insert, never upsert,
--    so a collision raises a real error) and update_invoice() (plain
--    update, requires the row to already exist) — structurally distinct
--    operations, not just a naming convention.
--
-- 2. save_invoice() trusted a client-submitted `total` outright. Fixed by
--    having the database compute it from the submitted line items itself,
--    using the exact same formula as frontend/src/data/invoices.ts's
--    invoiceTotals() (see compute_invoice_total() below).

drop function if exists public.save_invoice(text, uuid, uuid, text, date, date, text, text, numeric, numeric, numeric, jsonb);

-- Monthly-resetting invoice number sequence: INV-YYMM####, e.g. INV-26080001,
-- resetting to 0001 every calendar month. One counter row per month,
-- incremented atomically via INSERT ... ON CONFLICT ... RETURNING in the
-- same statement (and the same transaction as the invoice insert) that reads
-- it, so two concurrent create_invoice() calls can never be handed the same
-- number — unlike the old client-side nextInvoiceId(), which read, computed,
-- and wrote back the next number as three separate, unsynchronized steps.
create table public.invoice_number_counters (
  year_month text primary key,
  last_number integer not null default 0 check (last_number >= 0)
);

grant select, insert, update on public.invoice_number_counters to anon, authenticated;

-- Minimal stand-in for the not-yet-migrated Settings module (confirmed
-- localStorage-only, not backed by Supabase). Just enough for
-- create_invoice() to read a real, shared vat_rate instead of trusting
-- whatever rate a client happens to submit. Singleton row (id always 1); a
-- future Settings migration can widen this table rather than replace it.
create table public.business_settings (
  id integer primary key default 1 check (id = 1),
  vat_rate numeric(5, 2) not null default 20 check (vat_rate >= 0),
  updated_at timestamptz not null default now()
);

insert into public.business_settings (id, vat_rate) values (1, 20);

create trigger business_settings_set_updated_at
before update on public.business_settings
for each row execute function public.set_updated_at();

-- Read-only from the client's perspective for now — nothing writes to this
-- table yet (Settings itself isn't migrated), so update isn't granted.
grant select on public.business_settings to anon, authenticated;

-- Recomputes an invoice's total from its own line items, replicating
-- invoiceTotals() (frontend/src/data/invoices.ts) exactly: gross -> each
-- line's discount capped at that line's own gross -> subtotal -> the
-- invoice-level discount capped at the subtotal -> VAT prorated across only
-- VAT-flagged lines by the post-discount ratio -> round to 2dp at the VAT
-- and total steps only (matching invoiceTotals()'s round2() calls; nothing
-- in between is rounded). Shared by create_invoice() and update_invoice()
-- so neither ever trusts a client-submitted total.
create or replace function public.compute_invoice_total(
  p_lines jsonb,
  p_invoice_discount numeric,
  p_vat_rate numeric
)
returns numeric
language plpgsql
as $$
declare
  v_line jsonb;
  v_line_gross numeric;
  v_line_discount numeric;
  v_line_net numeric;
  v_subtotal numeric := 0;
  v_vat_subtotal numeric := 0;
  v_invoice_discount numeric;
  v_net_after_discount numeric;
  v_ratio numeric;
  v_vat numeric;
begin
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_gross := (v_line->>'quantity')::numeric * (v_line->>'unit_price')::numeric;
    v_line_discount := coalesce((v_line->>'discount')::numeric, 0);
    v_line_net := greatest(v_line_gross - v_line_discount, 0);
    v_subtotal := v_subtotal + v_line_net;
    if coalesce((v_line->>'vat')::boolean, true) then
      v_vat_subtotal := v_vat_subtotal + v_line_net;
    end if;
  end loop;

  v_invoice_discount := least(greatest(p_invoice_discount, 0), v_subtotal);
  v_net_after_discount := v_subtotal - v_invoice_discount;
  v_ratio := case when v_subtotal > 0 then v_net_after_discount / v_subtotal else 0 end;
  v_vat := round(v_vat_subtotal * v_ratio * (p_vat_rate / 100), 2);

  return round(v_net_after_discount + v_vat, 2);
end;
$$;

grant execute on function public.compute_invoice_total(jsonb, numeric, numeric) to anon, authenticated;

-- Always inserts a brand new invoice. Generates its own number from
-- invoice_number_counters (the client never invents or submits one) and
-- computes total server-side via compute_invoice_total(), reading vat_rate
-- from business_settings rather than trusting the client — the rate that
-- drives the total the database now owns has to come from a source the
-- database also trusts. A plain insert, never "on conflict do update": a
-- collision shouldn't be reachable given the atomic counter, but if the
-- counter table were ever hand-edited into a bad state, this raises a
-- unique_violation instead of silently overwriting an existing row.
create or replace function public.create_invoice(
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_issued_by text,
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
  insert into public.invoice_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = invoice_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'INV-' || v_year_month || lpad(v_seq::text, 4, '0');

  select vat_rate into v_vat_rate from public.business_settings where id = 1;
  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  insert into public.invoices
    (id, branch_id, customer_id, customer_name, date, due_date, issued_by, notes, invoice_discount, vat_rate, total, amount_paid, balance)
  values
    (v_id, p_branch_id, p_customer_id, p_customer_name, p_date, p_due_date, p_issued_by, p_notes, p_invoice_discount, v_vat_rate, v_total, 0, v_total)
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

  return v_invoice;
end;
$$;

grant execute on function public.create_invoice(uuid, uuid, text, date, date, text, text, numeric, jsonb) to anon, authenticated;

-- Only ever updates an existing invoice — a plain UPDATE can't insert, and
-- "if not found" makes a missing id fail loudly instead of doing nothing.
-- Recomputes total the same way create_invoice() does, for the same
-- reason (don't trust a client-submitted total), but keeps the invoice's
-- own already-issued vat_rate rather than re-reading business_settings: a
-- rate change shouldn't rewrite the math on an invoice that was already
-- issued under the old rate. amount_paid is left untouched, same as the
-- old save_invoice() — editing line items doesn't change what's already
-- been paid.
create or replace function public.update_invoice(
  p_id text,
  p_branch_id uuid,
  p_customer_id uuid,
  p_customer_name text,
  p_date date,
  p_due_date date,
  p_issued_by text,
  p_notes text,
  p_invoice_discount numeric,
  p_lines jsonb
)
returns public.invoices
language plpgsql
as $$
declare
  v_vat_rate numeric;
  v_total numeric;
  v_invoice public.invoices;
begin
  select vat_rate into v_vat_rate from public.invoices where id = p_id for update;
  if not found then
    raise exception 'Invoice % not found', p_id;
  end if;

  v_total := public.compute_invoice_total(p_lines, p_invoice_discount, v_vat_rate);

  update public.invoices set
    branch_id = p_branch_id,
    customer_id = p_customer_id,
    customer_name = p_customer_name,
    date = p_date,
    due_date = p_due_date,
    issued_by = p_issued_by,
    notes = p_notes,
    invoice_discount = p_invoice_discount,
    total = v_total,
    balance = greatest(v_total - amount_paid, 0)
  where id = p_id
  returning * into v_invoice;

  delete from public.invoice_lines where invoice_id = p_id;

  insert into public.invoice_lines (invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select
    p_id,
    nullif(line->>'product_id', '')::uuid,
    line->>'name',
    line->>'unit',
    (line->>'quantity')::numeric,
    (line->>'unit_price')::numeric,
    coalesce((line->>'discount')::numeric, 0),
    coalesce((line->>'vat')::boolean, true),
    (ord - 1)::integer
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_invoice;
end;
$$;

grant execute on function public.update_invoice(text, uuid, uuid, text, date, date, text, text, numeric, jsonb) to anon, authenticated;
