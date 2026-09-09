-- Position / department reference lists + uppercase name normalization
-- (TCS ERP — Group B follow-up to 20260909130000 / 20260909150000).
--
-- 1. `positions` and `departments` — school-editable reference lists, same
--    shape and RLS as `payment_providers` (name / position / is_active,
--    select for M/Acc/Aud, write for M/Acc, not approval-gated). They drive
--    dropdowns on the employee flow instead of free-text inputs.
--    `employees.position` / `employees.department` stay plain `text` — the
--    lists constrain the pickers, they are not FKs (same call as
--    `employee_pay_config.bank` vs `payment_providers`). Entity-wide
--    reference data with no branch FK, so seeded here, not in seed.sql.
--
-- 2. Uppercase normalization. `employees.name` / `.position` / `.department`
--    are forced to UPPER() by a BEFORE trigger regardless of how they are
--    entered (client, RPC, raw SQL). Ghanaian HR/payroll records are
--    conventionally kept in uppercase, and it removes "Ama"/"AMA"/"ama"
--    duplication. Email/phone are left exactly as entered. The reference
--    lists get the same treatment so a stored `employees.department` always
--    matches a list entry exactly.

-- =====================================================================
-- 1. positions / departments
-- =====================================================================
create table public.positions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  position integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index positions_position_idx on public.positions (position);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  position integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index departments_position_idx on public.departments (position);

alter table public.positions enable row level security;
alter table public.departments enable row level security;

do $$
declare t text;
begin
  foreach t in array array['positions', 'departments'] loop
    execute format(
      'create policy %I_select on public.%I for select using (public.has_role(array[''Manager'',''Accountant'',''Auditor'']))',
      t, t);
    execute format(
      'create policy %I_insert on public.%I for insert with check (public.has_role(array[''Manager'',''Accountant'']))',
      t, t);
    execute format(
      'create policy %I_update on public.%I for update using (public.has_role(array[''Manager'',''Accountant''])) with check (public.has_role(array[''Manager'',''Accountant'']))',
      t, t);
    execute format(
      'create policy %I_delete on public.%I for delete using (public.has_role(array[''Manager'',''Accountant'']))',
      t, t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

-- =====================================================================
-- 2. Uppercase normalization
-- =====================================================================
create or replace function public.uppercase_ref_list_name()
returns trigger language plpgsql as $$
begin
  new.name := upper(nullif(trim(new.name), ''));
  return new;
end;
$$;

create trigger positions_uppercase
before insert or update on public.positions
for each row execute function public.uppercase_ref_list_name();

create trigger departments_uppercase
before insert or update on public.departments
for each row execute function public.uppercase_ref_list_name();

create or replace function public.uppercase_employee_fields()
returns trigger language plpgsql as $$
begin
  new.name := upper(nullif(trim(new.name), ''));
  new.position := upper(nullif(trim(new.position), ''));
  new.department := upper(nullif(trim(new.department), ''));
  return new;
end;
$$;

create trigger employees_uppercase
before insert or update on public.employees
for each row execute function public.uppercase_employee_fields();

-- Normalize any rows that already exist (a real deployment). On a local
-- reset this table is empty here; seed.sql inserts afterward and the
-- trigger handles those.
update public.employees
set name = upper(nullif(trim(name), '')),
    position = upper(nullif(trim(position), '')),
    department = upper(nullif(trim(department), ''));

-- =====================================================================
-- Seed a starter set — uppercase, `on conflict do nothing`. The school
-- edits this itself; these are just so the dropdowns aren't empty and the
-- seeded demo employees' values resolve to a list entry.
-- =====================================================================
insert into public.positions (name, position) values
  ('HEAD TEACHER', 0),
  ('ASSISTANT HEAD TEACHER', 1),
  ('CLASS TEACHER', 2),
  ('SUBJECT TEACHER', 3),
  ('TEACHING ASSISTANT', 4),
  ('ICT COORDINATOR', 5),
  ('LIBRARIAN', 6),
  ('ADMINISTRATOR', 7),
  ('SECRETARY', 8),
  ('ACCOUNTANT', 9),
  ('BURSAR', 10),
  ('DRIVER', 11),
  ('KITCHEN STAFF', 12),
  ('CLEANER', 13),
  ('SECURITY', 14),
  ('CARETAKER', 15)
on conflict (name) do nothing;

insert into public.departments (name, position) values
  ('ADMINISTRATION', 0),
  ('KINDERGARTEN', 1),
  ('LOWER PRIMARY', 2),
  ('UPPER PRIMARY', 3),
  ('JUNIOR HIGH SCHOOL', 4),
  ('LIBRARY', 5),
  ('ICT', 6),
  ('KITCHEN', 7),
  ('TRANSPORT', 8),
  ('MAINTENANCE', 9)
on conflict (name) do nothing;
