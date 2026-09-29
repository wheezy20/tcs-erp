-- Closes the deposit_number_counters gap logged in docs/CONSTRAINTS.md
-- (found 2026-09-29 while building scripts/role-matrix.sh).
-- public.deposit_number_counters was created (customer_deposits.sql) with
-- grants but RLS never enabled, and Supabase's default privileges left anon
-- holding every table privilege on it — so anyone with the public anon key,
-- and every staff role including Auditor, could read, insert, update, or
-- delete customer-deposit numbering directly through the Data API,
-- bypassing create_customer_deposit()'s own guards.
--
-- Same policies as 20260814080000_pro_forma_counter_rls.sql used for the
-- same gap (that migration didn't revoke anon; this one does, below):
-- copy invoice_number_counters' four policies (role_permissions_rewrite.sql's
-- do-loop — select = any active staff, insert/update = can_write() i.e.
-- Manager or Attendant, delete = Manager). That's the right group for this
-- counter: customer_deposits' own insert policy is can_write() too, and
-- customer_deposits.sql's comment calls recording a deposit a counter
-- action, like a sale.
--
-- create_customer_deposit() is SECURITY INVOKER, so these policies now
-- apply to its counter upsert. Who can create a deposit doesn't change:
-- Manager and Attendant pass can_write(); Accountant was already stopped by
-- customer_deposits' insert policy and is now stopped one statement earlier
-- at the counter; Auditor and anon are stopped by require_writable_role().
-- Verified with supabase/role-matrix/20260929100000_deposit_number_counters_rls.sql.
--
-- anon loses every privilege (revoke all, as 20260803120000 did for
-- invoice_number_counters — also removes TRUNCATE, which RLS doesn't cover).
-- authenticated/service_role grants are deliberately left as they are.

alter table public.deposit_number_counters enable row level security;

create policy deposit_number_counters_select on public.deposit_number_counters
for select using (public.is_active_staff());

create policy deposit_number_counters_insert on public.deposit_number_counters
for insert with check (public.can_write());

create policy deposit_number_counters_update on public.deposit_number_counters
for update using (public.can_write()) with check (public.can_write());

create policy deposit_number_counters_delete on public.deposit_number_counters
for delete using (public.has_role(array['Manager']));

revoke all on public.deposit_number_counters from anon;
