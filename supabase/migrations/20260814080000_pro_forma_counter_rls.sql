-- Fixes a real RLS gap flagged during the End of Day / invoice_payments
-- investigation: public.pro_forma_invoice_number_counters was created
-- (proforma_and_wht.sql) with grants but no RLS at all, unlike its three
-- siblings (invoice_number_counters, sale_number_counters,
-- journal_entry_number_counters) — anyone with the anon or authenticated
-- key could read or write it directly, bypassing every other check this
-- table's own business domain otherwise enforces.
--
-- The three named siblings do NOT all share one shape, despite the ask
-- naming all three together — worth being explicit about before copying
-- either one blindly:
--   - invoice_number_counters / sale_number_counters: select = any active
--     staff (is_active_staff()), insert/update = can_write() (Manager or
--     Attendant, i.e. everyone but Accountant/Auditor), delete = Manager
--     only (present as RLS policy but never actually reachable — neither
--     table has ever had a delete GRANT, only select/insert/update; a
--     counter row is never deleted, this is just what applying the shared
--     4-policy do-loop in role_permissions_rewrite.sql mechanically produced).
--   - journal_entry_number_counters: select = Manager/Accountant-Auditor
--     only, insert/update = Manager only, no delete policy at all —
--     deliberately narrower, because Accounting isn't in Attendant's
--     spec-granted module list at all (see journal_entries_and_ledger.sql's
--     own comment).
--
-- pro_forma_invoice_number_counters belongs with the first group, not the
-- second: pro_forma_invoices/pro_forma_invoice_lines — created in the very
-- same migration as this counter table — already use exactly the
-- is_active_staff()/can_write()/Manager-delete shape, with their own
-- comment explicitly reasoning "a pro-forma quote is squarely inside
-- 'Attendant can create and issue invoices' per section 6." Giving the
-- counter table journal_entry_number_counters' narrower shape would block
-- the very Attendant pro-forma creation this migration exists to keep
-- working — matching invoice_number_counters/sale_number_counters is the
-- one that's actually correct for this domain.
--
-- Grants are untouched: pro_forma_invoice_number_counters already only has
-- select/insert/update (to authenticated and service_role, from its
-- original migration) with no delete grant to anyone — already identical
-- to invoice_number_counters/sale_number_counters' own grant shape, so
-- there's nothing to add there. The delete POLICY below is still included
-- for shape-parity with those two tables (each has one, inert without a
-- grant) rather than left out, so this table's RLS is a faithful match,
-- not just a "good enough" one.

alter table public.pro_forma_invoice_number_counters enable row level security;

create policy pro_forma_invoice_number_counters_select on public.pro_forma_invoice_number_counters
for select using (public.is_active_staff());

create policy pro_forma_invoice_number_counters_insert on public.pro_forma_invoice_number_counters
for insert with check (public.can_write());

create policy pro_forma_invoice_number_counters_update on public.pro_forma_invoice_number_counters
for update using (public.can_write()) with check (public.can_write());

create policy pro_forma_invoice_number_counters_delete on public.pro_forma_invoice_number_counters
for delete using (public.has_role(array['Manager']));
