-- Role matrix for 20260929100000_deposit_number_counters_rls.sql.
-- Run: ./scripts/role-matrix.sh supabase/role-matrix/20260929100000_deposit_number_counters_rls.sql
--
-- Direct-access probes use fake year_month values ('9901'/'9902') so they
-- never collide with real numbering. The create_customer_deposit probes use
-- seed.sql's branch (Main) and customer (Adjoa Mensah), paid in
-- Cash so no bank account is needed. Deposit creators are Manager and
-- Attendant (can_write(), matching customer_deposits' own insert policy).

-- probe: counter select (seeded row visible)
-- expect: Attendant,Manager,Accountant,Auditor
insert into public.deposit_number_counters (year_month, last_number) values ('9901', 5)
on conflict (year_month) do nothing;
-- as role:
do $$ begin
  if not exists (select 1 from public.deposit_number_counters where year_month = '9901') then
    raise exception 'no rows visible';
  end if;
end $$;

-- probe: counter direct insert
-- expect: Attendant,Manager
insert into public.deposit_number_counters (year_month, last_number) values ('9902', 1);

-- probe: counter direct update (must hit the row)
-- expect: Attendant,Manager
insert into public.deposit_number_counters (year_month, last_number) values ('9901', 5)
on conflict (year_month) do nothing;
-- as role:
do $$
declare n integer;
begin
  update public.deposit_number_counters set last_number = 0 where year_month = '9901';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'update affected 0 rows (filtered by RLS)'; end if;
end $$;

-- probe: counter direct delete (must hit the row)
-- expect: Manager
insert into public.deposit_number_counters (year_month, last_number) values ('9901', 5)
on conflict (year_month) do nothing;
-- as role:
do $$
declare n integer;
begin
  delete from public.deposit_number_counters where year_month = '9901';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'delete affected 0 rows (filtered by RLS)'; end if;
end $$;

-- probe: create_customer_deposit, first of month (insert path)
-- expect: Attendant,Manager
do $$ begin
  if exists (select 1 from public.customer_deposits
             where id like 'DEP-' || to_char(now(), 'YYMM') || '%') then
    raise exception 'probe precondition: no deposits this month';
  end if;
end $$;
delete from public.deposit_number_counters where year_month = to_char(now(), 'YYMM');
-- as role:
do $$
declare v public.customer_deposits;
begin
  v := public.create_customer_deposit(
    '00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002',
    'role-matrix probe', 50, 'Cash', null);
  if v.id <> 'DEP-' || to_char(now(), 'YYMM') || '0001' then
    raise exception 'unexpected deposit id %', v.id;
  end if;
end $$;

-- probe: create_customer_deposit, counter exists (update path)
-- expect: Attendant,Manager
insert into public.deposit_number_counters (year_month, last_number)
values (to_char(now(), 'YYMM'), 9000)
on conflict (year_month) do update set last_number = 9000;
-- as role:
do $$
declare v public.customer_deposits;
begin
  v := public.create_customer_deposit(
    '00000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002',
    'role-matrix probe', 50, 'Cash', null);
  if v.id <> 'DEP-' || to_char(now(), 'YYMM') || '9001' then
    raise exception 'unexpected deposit id %', v.id;
  end if;
end $$;
