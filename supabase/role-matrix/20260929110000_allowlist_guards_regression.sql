-- Role matrix for admissions slice 1b-i (allowlist guards), REGRESSION file.
-- docs/admissions/PORT-PLAN.md, slice 1b; decisions D-1b-a/b.
--
-- Proves the guard rewrite changes nothing for the five existing columns.
-- It only touches surface that exists on BOTH schemas, so the same file runs
-- on the pre-1b-i schema and on the new one, and the two outputs must be
-- byte-identical (grid and error lines). New surface (can_read_store(),
-- list_staff_names()) is in the sibling *_new_surface.sql file.
--
-- Generated from the local catalog on 2026-09-29 (every table whose policies
-- use can_write() or is_active_staff(), and every require_writable_role()
-- caller). Fixture rows are invented.
--
-- Write probes: RLS WITH CHECK runs before NOT NULL/CHECK/unique/FK checks,
-- so a 23xxx constraint error means the row got PAST the policy and counts
-- as "ok". Only 42501 (insufficient_privilege: RLS violation or no table
-- privilege) and "0 rows updated/deleted" count as denied. Anything else
-- (a trigger raising) is re-raised and shows up as denied with its message.
--
-- RPC probes call each require_writable_role() caller with NULL arguments.
-- An access-control error (the guards, require_staff(), a function's own
-- has_role check, a missing grant) is re-raised as denied; any later error
-- (a NULL-argument validation) means the caller got past access control and
-- counts as "ok". Expected sets were recorded from the pre-1b-i schema:
-- Manager-only RPCs carry their own has_role check; create_invoice,
-- create_pro_forma_invoice and create_sale stop Accountant at a counter
-- table's can_write() policy; the rest pass Accountant through the guard
-- and fail later on the NULL arguments.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh <this file>

-- ======================================================== A. guards

-- probe: guard: is_active_staff()
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not public.is_active_staff() then raise exception 'false'; end if; end $$;

-- probe: guard: can_write()
-- expect: Attendant,Manager
do $$ begin if not public.can_write() then raise exception 'false'; end if; end $$;

-- probe: guard: require_writable_role()
-- expect: Attendant,Manager,Accountant
select public.require_writable_role();

-- probe: guard: can_write(), every staff row inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
do $$ begin if not public.can_write() then raise exception 'false'; end if; end $$;

-- probe: guard: require_writable_role(), all inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
select public.require_writable_role();

-- probe: guard: is_active_staff(), all inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
do $$ begin if not public.is_active_staff() then raise exception 'false'; end if; end $$;

-- ======================================================== B. reads

-- probe: read branches
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.branches) then raise exception 'no rows visible'; end if; end $$;

-- probe: read business_settings
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.business_settings) then raise exception 'no rows visible'; end if; end $$;

-- probe: read customer_deposits
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.customer_deposits (id, branch_id, customer_id, customer_name, amount, method) values ('DEP-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', 10, 'Cash');
-- as role:
do $$ begin if not exists (select 1 from public.customer_deposits) then raise exception 'no rows visible'; end if; end $$;

-- probe: read customer_discounts
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.customer_discounts) then raise exception 'no rows visible'; end if; end $$;

-- probe: read customers
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.customers) then raise exception 'no rows visible'; end if; end $$;

-- probe: read day_closes
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.day_closes (branch_id, business_date, opening_float) values ((select id from public.branches order by created_at limit 1), current_date - 4000, 0);
-- as role:
do $$ begin if not exists (select 1 from public.day_closes) then raise exception 'no rows visible'; end if; end $$;

-- probe: read deposit_number_counters
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.deposit_number_counters (year_month, last_number) values ('9901', 0);
-- as role:
do $$ begin if not exists (select 1 from public.deposit_number_counters) then raise exception 'no rows visible'; end if; end $$;

-- probe: read held_sales
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.held_sales (branch_id, lines) values ((select id from public.branches order by created_at limit 1), '[{"probe": 1}]');
-- as role:
do $$ begin if not exists (select 1 from public.held_sales) then raise exception 'no rows visible'; end if; end $$;

-- probe: read invoice_lines
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.invoice_lines) then raise exception 'no rows visible'; end if; end $$;

-- probe: read invoice_number_counters
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.invoice_number_counters (year_month, last_number) values ('9901', 0);
-- as role:
do $$ begin if not exists (select 1 from public.invoice_number_counters) then raise exception 'no rows visible'; end if; end $$;

-- probe: read invoice_payments
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.invoice_payments) then raise exception 'no rows visible'; end if; end $$;

-- probe: read invoices
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.invoices) then raise exception 'no rows visible'; end if; end $$;

-- probe: read manager_overrides
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.manager_overrides (branch_id, requested_by) values ((select id from public.branches order by created_at limit 1), (select id from public.staff where role = 'Manager' and active order by id limit 1));
-- as role:
do $$ begin if not exists (select 1 from public.manager_overrides) then raise exception 'no rows visible'; end if; end $$;

-- probe: read pro_forma_invoice_lines
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date) values ('PF-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', current_date, current_date);
insert into public.pro_forma_invoice_lines (pro_forma_invoice_id, name, unit, quantity) values ('PF-PROBE-1', 'Probe item', 'pc', 1);
-- as role:
do $$ begin if not exists (select 1 from public.pro_forma_invoice_lines) then raise exception 'no rows visible'; end if; end $$;

-- probe: read pro_forma_invoice_number_counters
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoice_number_counters (year_month, last_number) values ('9901', 0);
-- as role:
do $$ begin if not exists (select 1 from public.pro_forma_invoice_number_counters) then raise exception 'no rows visible'; end if; end $$;

-- probe: read pro_forma_invoices
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date) values ('PF-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', current_date, current_date);
-- as role:
do $$ begin if not exists (select 1 from public.pro_forma_invoices) then raise exception 'no rows visible'; end if; end $$;

-- probe: read products
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.products) then raise exception 'no rows visible'; end if; end $$;

-- probe: read sale_lines
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.sale_lines) then raise exception 'no rows visible'; end if; end $$;

-- probe: read sale_number_counters
-- expect: Attendant,Manager,Accountant,Auditor
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.sale_number_counters (year_month, last_number) values ('9901', 0);
-- as role:
do $$ begin if not exists (select 1 from public.sale_number_counters) then raise exception 'no rows visible'; end if; end $$;

-- probe: read sale_payments
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.sale_payments) then raise exception 'no rows visible'; end if; end $$;

-- probe: read sale_returns
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.sale_returns) then raise exception 'no rows visible'; end if; end $$;

-- probe: read sales
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.sales) then raise exception 'no rows visible'; end if; end $$;

-- probe: read staff
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.staff) then raise exception 'no rows visible'; end if; end $$;

-- probe: read stock_movements
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin if not exists (select 1 from public.stock_movements) then raise exception 'no rows visible'; end if; end $$;

-- probe: read staff: other staff rows visible
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin
  if not exists (select 1 from public.staff where id is distinct from auth.uid()) then
    raise exception 'no other staff visible';
  end if;
end $$;

-- probe: read staff: own row visible
-- expect: Attendant,Manager,Accountant,Auditor
do $$ begin
  if not exists (select 1 from public.staff where id = auth.uid()) then
    raise exception 'own row not visible';
  end if;
end $$;

-- probe: read staff: own row, self inactive
-- expect: none
update public.staff set active = false where not protected;
-- as role:
do $$ begin
  if not exists (select 1 from public.staff where id = auth.uid()) then
    raise exception 'own row not visible';
  end if;
end $$;

-- ======================================================== C. writes (can_write() policies)

-- probe: insert branches
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.branches t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.branches (id, name, default_low_stock_threshold, created_at)
  select r.id, r.name, r.default_low_stock_threshold, r.created_at
  from _probe_src s, jsonb_populate_record(null::public.branches, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update branches
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.branches t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.branches set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert customer_deposits
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.customer_deposits (id, branch_id, customer_id, customer_name, amount, method) values ('DEP-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', 10, 'Cash');
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.customer_deposits t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.customer_deposits (id, branch_id, customer_id, customer_name, description, amount, method, bank_account_id, status, taken_at, taken_by, fulfilled_sale_id, fulfilled_invoice_id, fulfilled_at, cancelled_at, cancelled_by, cancellation_fee, cancellation_refund, cancellation_note)
  select r.id, r.branch_id, r.customer_id, r.customer_name, r.description, r.amount, r.method, r.bank_account_id, r.status, r.taken_at, r.taken_by, r.fulfilled_sale_id, r.fulfilled_invoice_id, r.fulfilled_at, r.cancelled_at, r.cancelled_by, r.cancellation_fee, r.cancellation_refund, r.cancellation_note
  from _probe_src s, jsonb_populate_record(null::public.customer_deposits, s.j || jsonb_build_object('id', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update customer_deposits
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.customer_deposits (id, branch_id, customer_id, customer_name, amount, method) values ('DEP-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', 10, 'Cash');
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.customer_deposits t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.customer_deposits set id = id where id = (select (j ->> 'id')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert customers
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.customers t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.customers (id, branch_id, name, phone, email, address, customer_type, customer_since, balance, lifetime_total, created_at, updated_at, store_credit_balance)
  select r.id, r.branch_id, r.name, r.phone, r.email, r.address, r.customer_type, r.customer_since, r.balance, r.lifetime_total, r.created_at, r.updated_at, r.store_credit_balance
  from _probe_src s, jsonb_populate_record(null::public.customers, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update customers
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.customers t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.customers set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert deposit_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.deposit_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.deposit_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.deposit_number_counters (year_month, last_number)
  select r.year_month, r.last_number
  from _probe_src s, jsonb_populate_record(null::public.deposit_number_counters, s.j || jsonb_build_object('year_month', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update deposit_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.deposit_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.deposit_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.deposit_number_counters set year_month = year_month where year_month = (select (j ->> 'year_month')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: delete held_sales
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.held_sales (branch_id, lines) values ((select id from public.branches order by created_at limit 1), '[{"probe": 1}]');
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.held_sales t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  delete from public.held_sales where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows deleted'; end if;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: insert held_sales
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.held_sales (branch_id, lines) values ((select id from public.branches order by created_at limit 1), '[{"probe": 1}]');
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.held_sales t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.held_sales (id, branch_id, customer_id, customer_name, lines, sale_discount_mode, sale_discount_value, vat_mode, payments, held_by, created_at)
  select r.id, r.branch_id, r.customer_id, r.customer_name, r.lines, r.sale_discount_mode, r.sale_discount_value, r.vat_mode, r.payments, r.held_by, r.created_at
  from _probe_src s, jsonb_populate_record(null::public.held_sales, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: insert invoice_lines
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoice_lines t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.invoice_lines (id, invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select r.id, r.invoice_id, r.product_id, r.name, r.unit, r.quantity, r.unit_price, r.discount, r.vat, r.position
  from _probe_src s, jsonb_populate_record(null::public.invoice_lines, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update invoice_lines
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoice_lines t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.invoice_lines set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert invoice_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.invoice_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoice_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.invoice_number_counters (year_month, last_number)
  select r.year_month, r.last_number
  from _probe_src s, jsonb_populate_record(null::public.invoice_number_counters, s.j || jsonb_build_object('year_month', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update invoice_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.invoice_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoice_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.invoice_number_counters set year_month = year_month where year_month = (select (j ->> 'year_month')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert invoice_payments
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoice_payments t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.invoice_payments (id, invoice_id, branch_id, amount, method, reference, note, paid_at, recorded_by, bank_account_id)
  select r.id, r.invoice_id, r.branch_id, r.amount, r.method, r.reference, r.note, r.paid_at, r.recorded_by, r.bank_account_id
  from _probe_src s, jsonb_populate_record(null::public.invoice_payments, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update invoice_payments
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoice_payments t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.invoice_payments set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert invoices
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoices t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.invoices (id, branch_id, customer_id, customer_name, date, due_date, notes, invoice_discount, vat_rate, total, amount_paid, balance, created_at, updated_at, issued_by, wht_applied, wht_rate, wht_amount, voided_at, voided_by, void_reason)
  select r.id, r.branch_id, r.customer_id, r.customer_name, r.date, r.due_date, r.notes, r.invoice_discount, r.vat_rate, r.total, r.amount_paid, r.balance, r.created_at, r.updated_at, r.issued_by, r.wht_applied, r.wht_rate, r.wht_amount, r.voided_at, r.voided_by, r.void_reason
  from _probe_src s, jsonb_populate_record(null::public.invoices, s.j || jsonb_build_object('id', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update invoices
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.invoices t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.invoices set id = id where id = (select (j ->> 'id')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert pro_forma_invoice_lines
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date) values ('PF-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', current_date, current_date);
insert into public.pro_forma_invoice_lines (pro_forma_invoice_id, name, unit, quantity) values ('PF-PROBE-1', 'Probe item', 'pc', 1);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.pro_forma_invoice_lines t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.pro_forma_invoice_lines (id, pro_forma_invoice_id, product_id, name, unit, quantity, unit_price, discount, vat, position)
  select r.id, r.pro_forma_invoice_id, r.product_id, r.name, r.unit, r.quantity, r.unit_price, r.discount, r.vat, r.position
  from _probe_src s, jsonb_populate_record(null::public.pro_forma_invoice_lines, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update pro_forma_invoice_lines
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date) values ('PF-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', current_date, current_date);
insert into public.pro_forma_invoice_lines (pro_forma_invoice_id, name, unit, quantity) values ('PF-PROBE-1', 'Probe item', 'pc', 1);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.pro_forma_invoice_lines t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.pro_forma_invoice_lines set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert pro_forma_invoice_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoice_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.pro_forma_invoice_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.pro_forma_invoice_number_counters (year_month, last_number)
  select r.year_month, r.last_number
  from _probe_src s, jsonb_populate_record(null::public.pro_forma_invoice_number_counters, s.j || jsonb_build_object('year_month', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update pro_forma_invoice_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoice_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.pro_forma_invoice_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.pro_forma_invoice_number_counters set year_month = year_month where year_month = (select (j ->> 'year_month')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert pro_forma_invoices
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date) values ('PF-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', current_date, current_date);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.pro_forma_invoices t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date, notes, invoice_discount, vat_rate, total, status, converted_invoice_id, created_by, created_at)
  select r.id, r.branch_id, r.customer_id, r.customer_name, r.date, r.due_date, r.notes, r.invoice_discount, r.vat_rate, r.total, r.status, r.converted_invoice_id, r.created_by, r.created_at
  from _probe_src s, jsonb_populate_record(null::public.pro_forma_invoices, s.j || jsonb_build_object('id', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update pro_forma_invoices
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.pro_forma_invoices (id, branch_id, customer_id, customer_name, date, due_date) values ('PF-PROBE-1', (select id from public.branches order by created_at limit 1), (select id from public.customers order by id limit 1), 'Probe Customer', current_date, current_date);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.pro_forma_invoices t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.pro_forma_invoices set id = id where id = (select (j ->> 'id')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert products
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.products t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.products (id, branch_id, sku, name, description, category, unit, size, cost, price, stock, low_stock_threshold, created_at, updated_at)
  select r.id, r.branch_id, r.sku, r.name, r.description, r.category, r.unit, r.size, r.cost, r.price, r.stock, r.low_stock_threshold, r.created_at, r.updated_at
  from _probe_src s, jsonb_populate_record(null::public.products, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update products
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.products t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.products set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert sale_lines
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_lines t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.sale_lines (id, sale_id, product_id, name, unit, category, quantity, unit_price, discount_mode, discount_value, vat, position)
  select r.id, r.sale_id, r.product_id, r.name, r.unit, r.category, r.quantity, r.unit_price, r.discount_mode, r.discount_value, r.vat, r.position
  from _probe_src s, jsonb_populate_record(null::public.sale_lines, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update sale_lines
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_lines t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.sale_lines set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert sale_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.sale_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.sale_number_counters (year_month, last_number)
  select r.year_month, r.last_number
  from _probe_src s, jsonb_populate_record(null::public.sale_number_counters, s.j || jsonb_build_object('year_month', 'PRB-' || substr(md5(random()::text), 1, 8))) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update sale_number_counters
-- expect: Attendant,Manager
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.staff where role = 'Manager' and active order by id limit 1))::text, true);
insert into public.sale_number_counters (year_month, last_number) values ('9901', 0);
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_number_counters t order by year_month limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.sale_number_counters set year_month = year_month where year_month = (select (j ->> 'year_month')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert sale_payments
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_payments t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.sale_payments (id, sale_id, branch_id, method, amount, reference, paid_at, bank_account_id)
  select r.id, r.sale_id, r.branch_id, r.method, r.amount, r.reference, r.paid_at, r.bank_account_id
  from _probe_src s, jsonb_populate_record(null::public.sale_payments, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update sale_payments
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_payments t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.sale_payments set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert sale_returns
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_returns t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.sale_returns (id, sale_id, branch_id, returned_sale_line_id, returned_product_id, returned_name, returned_unit, returned_quantity, returned_unit_price, replacement_product_id, replacement_name, replacement_unit, replacement_quantity, replacement_unit_price, difference, resolution, approval_state, reason, returned_at, processed_by, payment_method, customer_id, bank_account_id, return_group_id)
  select r.id, r.sale_id, r.branch_id, r.returned_sale_line_id, r.returned_product_id, r.returned_name, r.returned_unit, r.returned_quantity, r.returned_unit_price, r.replacement_product_id, r.replacement_name, r.replacement_unit, r.replacement_quantity, r.replacement_unit_price, r.difference, r.resolution, r.approval_state, r.reason, r.returned_at, r.processed_by, r.payment_method, r.customer_id, r.bank_account_id, r.return_group_id
  from _probe_src s, jsonb_populate_record(null::public.sale_returns, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update sale_returns
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sale_returns t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.sale_returns set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert sales
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sales t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.sales (id, branch_id, customer_id, customer_name, sold_at, sale_discount_mode, sale_discount_value, vat_mode, vat_rate, total, created_at, cashier, override_authorized_by, notes, voided_at, voided_by, void_reason)
  select r.id, r.branch_id, r.customer_id, r.customer_name, r.sold_at, r.sale_discount_mode, r.sale_discount_value, r.vat_mode, r.vat_rate, r.total, r.created_at, r.cashier, r.override_authorized_by, r.notes, r.voided_at, r.voided_by, r.void_reason
  from _probe_src s, jsonb_populate_record(null::public.sales, s.j || jsonb_build_object('id', 'PRB-' || substr(md5(random()::text), 1, 8), 'cashier', auth.uid(), 'sold_at', now())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update sales
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.sales t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.sales set id = id where id = (select (j ->> 'id')::text from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: insert stock_movements
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.stock_movements t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ begin
  insert into public.stock_movements (id, product_id, branch_id, movement_type, change, balance_after, reason, occurred_at, performed_by)
  select r.id, r.product_id, r.branch_id, r.movement_type, r.change, r.balance_after, r.reason, r.occurred_at, r.performed_by
  from _probe_src s, jsonb_populate_record(null::public.stock_movements, s.j || jsonb_build_object('id', gen_random_uuid())) r;
exception
  when insufficient_privilege then raise;
  when integrity_constraint_violation then null;  -- past RLS
end $$;

-- probe: update stock_movements
-- expect: Attendant,Manager
create temp table _probe_src on commit drop as select to_jsonb(t) as j from public.stock_movements t order by id limit 1;
grant select on _probe_src to public;
-- as role:
do $$ declare n int; begin
  update public.stock_movements set id = id where id = (select (j ->> 'id')::uuid from _probe_src);
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- ======================================================== D. require_writable_role() callers

-- probe: rpc adjust_product_stock
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.adjust_product_stock(null::uuid, null::integer, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc cancel_bank_reconciliation
-- expect: Manager
do $$ begin
  perform public.cancel_bank_reconciliation(null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc cancel_customer_deposit
-- expect: Manager
do $$ begin
  perform public.cancel_customer_deposit(null::text, null::numeric, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc cancel_purchase_order
-- expect: Manager
do $$ begin
  perform public.cancel_purchase_order(null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc clear_statement_line
-- expect: Manager
do $$ begin
  perform public.clear_statement_line(null::uuid, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc complete_bank_reconciliation
-- expect: Manager
do $$ begin
  perform public.complete_bank_reconciliation(null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc convert_pro_forma_to_invoice
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.convert_pro_forma_to_invoice(null::text, null::date, null::boolean);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_bank_account
-- expect: Manager
do $$ begin
  perform public.create_bank_account(null::text, null::text, null::numeric, null::date, null::text, null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_customer_deposit
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.create_customer_deposit(null::uuid, null::uuid, null::text, null::numeric, null::text, null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_customer_discount
-- expect: Manager
do $$ begin
  perform public.create_customer_discount(null::uuid, null::text, null::text, null::numeric);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_invoice
-- expect: Attendant,Manager
do $$ begin
  perform public.create_invoice(null::uuid, null::uuid, null::text, null::date, null::date, null::text, null::numeric, null::jsonb, null::boolean);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_pro_forma_invoice
-- expect: Attendant,Manager
do $$ begin
  perform public.create_pro_forma_invoice(null::uuid, null::uuid, null::text, null::date, null::date, null::text, null::numeric, null::jsonb);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_purchase_order
-- expect: Manager
do $$ begin
  perform public.create_purchase_order(null::uuid, null::uuid, null::text, null::date, null::date, null::text, null::jsonb);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_sale
-- expect: Attendant,Manager
do $$ begin
  perform public.create_sale(null::uuid, null::uuid, null::text, null::text, null::numeric, null::text, null::jsonb, null::jsonb, null::uuid, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_sale_return
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.create_sale_return(null::text, null::uuid, null::integer, null::uuid, null::integer, null::text, null::text, null::text, null::text, null::uuid, null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_sale_return_batch
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.create_sale_return_batch(null::text, null::jsonb, null::text, null::text, null::text, null::uuid, null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc create_supplier
-- expect: Manager
do $$ begin
  perform public.create_supplier(null::uuid, null::text, null::text, null::text, null::text, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc import_bank_statement_lines
-- expect: Manager
do $$ begin
  perform public.import_bank_statement_lines(null::uuid, null::jsonb);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc match_statement_line
-- expect: Manager
do $$ begin
  perform public.match_statement_line(null::uuid, null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc place_purchase_order
-- expect: Manager
do $$ begin
  perform public.place_purchase_order(null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc receive_purchase_order
-- expect: Manager
do $$ begin
  perform public.receive_purchase_order(null::text, null::date, null::text, null::jsonb);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc record_invoice_payment
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.record_invoice_payment(null::text, null::numeric, null::text, null::text, null::text, null::timestamp with time zone, null::uuid, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc record_supplier_payment
-- expect: Manager
do $$ begin
  perform public.record_supplier_payment(null::text, null::numeric, null::text, null::text, null::text, null::timestamp with time zone, null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc start_bank_reconciliation
-- expect: Manager
do $$ begin
  perform public.start_bank_reconciliation(null::uuid, null::date, null::numeric);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc unmatch_statement_line
-- expect: Manager
do $$ begin
  perform public.unmatch_statement_line(null::uuid);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc update_invoice
-- expect: Attendant,Manager,Accountant
do $$ begin
  perform public.update_invoice(null::text, null::uuid, null::uuid, null::text, null::date, null::date, null::text, null::numeric, null::jsonb);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc void_invoice
-- expect: Manager
do $$ begin
  perform public.void_invoice(null::text, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- probe: rpc void_sale
-- expect: Manager
do $$ begin
  perform public.void_sale(null::text, null::text);
exception when others then
  if sqlstate = '42501' or sqlerrm ~* '(read-only|not available to your role|not signed in|limited to|only (a |the )?(manager|accountant|attendant)|manager (approval|role)|not permitted|not allowed|permission denied)' then raise; end if;
end $$;

-- ======================================================== E. compute_day_totals

-- probe: compute_day_totals
-- expect: Attendant,Manager,Accountant,Auditor
select * from public.compute_day_totals('00000000-0000-0000-0000-000000000001', current_date);
