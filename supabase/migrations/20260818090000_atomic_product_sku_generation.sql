-- A bulk import of 590 new products hit a real 409 Conflict on
-- products_branch_id_sku_key. Root cause: randomCode() (inventory-store.ts)
-- generated every "NEW-"/"IMP-" SKU as `${prefix}-${1000..9999}`, a random
-- 4-digit pick out of only 9000 possible values, computed client-side with
-- no coordination between rows in the same batch — nothing like the real,
-- DB-backed atomic counters this app already uses for every other numbered
-- entity (invoice_number_counters, sale_number_counters,
-- journal_entry_number_counters, expense_number_seq). At 590 rows in one
-- batch, the birthday-paradox collision odds on a 9000-value range are
-- essentially certain, not just statistically unlikely — this was never
-- going to survive real volume.
--
-- Fixed the same way expense numbering already solved an identical shape of
-- problem: SKUs don't reset on any schedule (no month/year component, unlike
-- invoice/sale/journal-entry numbers), so a plain Postgres sequence is the
-- right tool, not a counter table — nextval() is already atomic under
-- concurrency regardless of how many values are drawn in one call or how
-- many callers draw concurrently, which is what "structurally impossible to
-- collide" actually requires here.
--
-- Started at 10000, one full order of magnitude past the old scheme's
-- entire 1000-9999 range, so this can never collide with any
-- randomCode()-generated SKU that happened to already exist before this
-- migration, regardless of which specific values were drawn.
create sequence public.product_sku_seq start with 10000;

revoke usage on sequence public.product_sku_seq from anon;
grant usage on sequence public.product_sku_seq to authenticated;
grant usage, select on sequence public.product_sku_seq to service_role;

-- Vends p_count atomically-unique SKUs in one round trip — the batch-import
-- path (addProducts(), up to hundreds of rows) needs all of them before it
-- can build its single bulk insert, and a round trip per row would be both
-- slow and pointless when nextval() already guarantees no two calls, from
-- this function or any other caller, can ever return the same value.
-- Row order from generate_series carries no meaning — callers zip the
-- returned SKUs 1:1 against their own rows in whatever order comes back;
-- only uniqueness and count matter, not which row gets which number.
create or replace function public.next_product_skus(p_prefix text, p_count integer)
returns setof text
language sql
as $$
  select p_prefix || '-' || nextval('public.product_sku_seq')::text
  from generate_series(1, greatest(p_count, 0));
$$;

grant execute on function public.next_product_skus(text, integer) to authenticated;
