-- No way to delete a product existed anywhere — no UI, no RPC. A raw
-- Manager DELETE against products was technically reachable (RLS's generic
-- per-table policy loop gave every table including products a
-- `products_delete` policy, Manager-only), but it was never actually safe:
-- stock_movements.product_id is `on delete cascade` (a raw delete would
-- silently wipe the product's own audit trail, not be blocked by it), and
-- invoice_lines/pro_forma_invoice_lines.product_id are `on delete set null`
-- (a raw delete would silently orphan those lines' product reference
-- instead of being stopped by it). Only sale_lines, purchase_order_lines,
-- purchase_order_receipt_lines, and sale_returns are genuinely `restrict` —
-- so the raw path was only partially, accidentally safe, and never
-- reachable from the frontend anyway.
--
-- delete_product() is the one sanctioned path now. It's SECURITY DEFINER
-- and the generic products_delete RLS policy is dropped along with the
-- ordinary delete grant — a deliberate, narrower version of the
-- audit_log/journal_entries/manager_overrides precedent ("nothing outside
-- its own controlled function can write here"), applied here because a raw
-- delete's FK behavior doesn't actually match "block the delete" the way
-- restrict alone does everywhere else in this schema. service_role keeps
-- its delete grant, matching the standard "service_role always gets full
-- CRUD" convention — this isn't a tamper-evidence exception the way
-- audit_log/journal_entries are, just an ordinary table that needs a
-- smarter delete path than RLS alone can express; a local script
-- deliberately cleaning up test data as service_role is expected to bypass
-- this, the same way test cleanup already bypasses every other
-- delete-restricted table in this build.
revoke delete on public.products from anon, authenticated;
drop policy if exists products_delete on public.products;

create or replace function public.delete_product(p_id uuid)
returns void
security definer
set search_path = public
language plpgsql
as $$
declare
  v_product public.products;
  v_reasons text[] := '{}';
  v_count integer;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can delete a product';
  end if;

  select * into v_product from public.products where id = p_id;
  if not found then
    raise exception 'Product not found';
  end if;

  -- Every table that can carry real history against this product, checked
  -- explicitly rather than trusted to each FK's own on-delete behavior —
  -- see the header note above for why that behavior alone isn't enough.
  -- purchase_order_receipt_lines is deliberately not checked separately: a
  -- receipt line can only exist for a product that already has a
  -- purchase_order_lines row (receiving happens against an existing order
  -- line), so the purchase_order_lines check below already covers it.
  -- pro_forma_invoice_lines is deliberately not checked either — a
  -- pro-forma is a non-binding quote with no ledger/stock/AR consequence
  -- (see the Session 19 notes), not real transaction history; if one is
  -- ever converted, convert_pro_forma_to_invoice() creates a real
  -- invoice_lines row, which *is* checked below.

  -- addProduct()/addProducts() (inventory-store.ts) always log one
  -- "Opening stock..." stock_movements row at creation, unconditionally,
  -- even for a brand-new product with zero real activity — that row is
  -- the product's own creation snapshot, not evidence of anything having
  -- happened to it since. More than that one row is only possible if a
  -- later, genuine event added another (a POS sale, a return, a manual
  -- adjustment, a received purchase order all insert their own row), so
  -- "more than 1" is what actually means "has been sold or adjusted" —
  -- count(*) > 0 would incorrectly block every product ever created
  -- through the ordinary UI, including ones with truly zero history.
  select count(*) into v_count from public.stock_movements where product_id = p_id;
  if v_count > 1 then
    v_reasons := v_reasons || format('%s stock movement(s) beyond its opening stock entry', v_count - 1);
  end if;

  select count(*) into v_count from public.sale_lines where product_id = p_id;
  if v_count > 0 then
    v_reasons := v_reasons || format('%s POS sale line(s)', v_count);
  end if;

  select count(*) into v_count from public.invoice_lines where product_id = p_id;
  if v_count > 0 then
    v_reasons := v_reasons || format('%s invoice line(s)', v_count);
  end if;

  select count(*) into v_count from public.purchase_order_lines where product_id = p_id;
  if v_count > 0 then
    v_reasons := v_reasons || format('%s purchase order line(s)', v_count);
  end if;

  select count(*) into v_count from public.sale_returns
  where returned_product_id = p_id or replacement_product_id = p_id;
  if v_count > 0 then
    v_reasons := v_reasons || format('%s return/exchange record(s)', v_count);
  end if;

  -- journal_lines has no product_id column anywhere, direct or indirect —
  -- a product only ever reaches the ledger as a side effect of
  -- stock_movements/sale_lines/invoice_lines auto-posting, all three
  -- already checked above. There is no journal history this delete could
  -- reach that isn't already caught by one of those three checks first, so
  -- a literal "select from journal_lines" query here would just be a
  -- no-op that looks like a check but checks nothing.

  if array_length(v_reasons, 1) > 0 then
    raise exception 'Cannot delete "%": has %. Products with real transaction history can never be deleted.',
      v_product.name, array_to_string(v_reasons, ', ');
  end if;

  delete from public.products where id = p_id;
end;
$$;

grant execute on function public.delete_product(uuid) to authenticated;
