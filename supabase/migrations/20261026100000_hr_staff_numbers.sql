-- Staff ID numbers (HR). Plan approved 2026-10-16.
--
-- Format: ST + two digit approval year + '-' + two digit class + three digit
-- roll, e.g. ST26-02002. The year is the calendar year (Africa/Accra) the
-- employee record was approved. The class comes from the employee's
-- position: 01 admin, 02 teaching, 03 kitchen, 04 janitorial, 05 transport.
-- The roll runs 001 to 999 and restarts per year only, so one count runs
-- across all classes: ST26-02002 is the second person approved in 2026, who
-- is teaching, not the second teacher.
--
-- Rules:
--   * approve_employee issues the ID in the same transaction that sets the
--     record Active. An unmapped position refuses the approval.
--   * The ID is kept for life: a later position change keeps the old class,
--     suspension and reactivation keep the ID, and someone who returns is
--     reactivated on their old record.
--   * correct_staff_number lets a Manager reissue once, with a reason. The
--     old ID is retired, never reused, and the new one stays in the
--     original year with the next roll and the current position's class.
--     Correction is the only way a class changes after approval.
--   * The 1000th approval in a year is refused until the format is widened
--     in a reviewed change.
--   * No backfill: anyone approved before this migration shows "Not issued".
--
-- Who: Manager issues (by approving) and corrects. Manager, Accountant and
-- Auditor read, matching employees_select. Nobody writes the tables
-- directly. Manager alone sets a position's class (set_position_staff_class);
-- a trigger refuses a direct write of that column, see below.
--
-- No anon surface: every new function is revoked from public and anon, so
-- the anon-executable count stays 170.

-- ------------------------------------------------------------ audit actions

alter table public.audit_log drop constraint audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action = any (array[
  'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
  'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
  'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
  'admissions_capabilities_changed',
  'staff_advance_proposed', 'staff_advance_approved', 'staff_advance_rejected',
  'staff_advance_change_proposed', 'staff_advance_change_approved',
  'staff_advance_change_rejected',
  'employees_imported',
  'application_stage_changed', 'application_document_status_changed',
  'application_decision_changed', 'admissions_capacity_changed',
  'application_offer_changed', 'admissions_settings_changed',
  'application_grade_corrected', 'admissions_academic_year_changed',
  'staff_number_issued', 'staff_number_retired', 'position_staff_class_changed'
]));

-- ------------------------------------------------------------ positions.staff_class

-- Separate from is_teaching, which only picks the contract template: ICT
-- Coordinator and Librarian are class 02 but keep the non-teaching contract.
alter table public.positions
  add column staff_class text check (staff_class in ('01', '02', '03', '04', '05'));

create or replace function public.set_position_staff_class(p_position_id uuid, p_class text)
returns public.positions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pos public.positions;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can set a position''s staff classification';
  end if;
  if p_class is not null and p_class not in ('01', '02', '03', '04', '05') then
    raise exception 'Staff classification must be 01, 02, 03, 04 or 05';
  end if;

  update public.positions set staff_class = p_class
  where id = p_position_id
  returning * into v_pos;
  if not found then
    raise exception 'Position % not found', p_position_id;
  end if;
  return v_pos;
end;
$$;

revoke execute on function public.set_position_staff_class(uuid, text) from public, anon;
grant execute on function public.set_position_staff_class(uuid, text) to authenticated;

-- The guard. Accountant keeps its direct insert and update on positions
-- (name, order, is_teaching, is_active), so the column itself needs a guard.
--
-- It keys on current_user, the role the statement runs as, not on a
-- setting. A direct API write runs as authenticated (or anon, or
-- service_role). set_position_staff_class is SECURITY DEFINER, so its body
-- runs as the function's owner, and this trigger, which is deliberately
-- SECURITY INVOKER, sees that owner as current_user. current_user isn't a
-- setting: it changes only through SET ROLE or SET SESSION AUTHORIZATION,
-- and the API roles aren't members of the owner role, so they can't become
-- it. A custom setting (set_config('tcs.allow', ...)) would be bypassable,
-- because any role may set a custom setting, so none is used here.
--
-- The class is found by exact position name, so a rename or delete of a
-- position that has a class would move or drop the class without writing
-- the column (code review, 2026-10-16). Both are refused while a class is
-- set: to rename, a Manager clears the class, renames, then sets it again.
-- The name is compared after the same normalization positions_uppercase
-- applies, because this trigger fires first (triggers run in name order).
create or replace function public.guard_position_staff_class()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_owner text;
begin
  select r.rolname into v_owner
  from pg_proc p join pg_roles r on r.oid = p.proowner
  where p.oid = 'public.set_position_staff_class(uuid, text)'::regprocedure;

  if tg_op = 'DELETE' then
    if old.staff_class is not null and current_user is distinct from v_owner then
      raise exception 'Clear position %''s staff classification before deleting it', old.name;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.staff_class is not null
     and upper(nullif(trim(new.name), '')) is distinct from old.name
     and current_user is distinct from v_owner then
    raise exception 'Clear position %''s staff classification before renaming it', old.name;
  end if;

  if tg_op = 'INSERT' then
    if new.staff_class is null then return new; end if;
  elsif new.staff_class is not distinct from old.staff_class then
    return new;
  end if;

  if current_user is distinct from v_owner then
    raise exception 'A position''s staff classification is set only through set_position_staff_class';
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_position_staff_class() from public, anon;

create trigger positions_guard_staff_class
before insert or update or delete on public.positions
for each row execute function public.guard_position_staff_class();

create or replace function public.audit_position_staff_class()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
begin
  -- No actor => migration seed, not a user action.
  if v_actor is null then return new; end if;
  if new.staff_class is not distinct from old.staff_class then return new; end if;

  select branch_id into v_branch from public.staff where id = v_actor;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'position_staff_class_changed', 'positions', new.id::text,
    jsonb_build_object('position', old.name, 'staff_class', old.staff_class),
    jsonb_build_object('position', new.name, 'staff_class', new.staff_class)
  );
  return new;
end;
$$;

revoke execute on function public.audit_position_staff_class() from public, anon;

create trigger positions_audit_staff_class
after update of staff_class on public.positions
for each row execute function public.audit_position_staff_class();

-- Seed the 16 positions (runs as the owner, so the guard lets it through;
-- no actor, so no audit row). A position missing on a target database is
-- simply left unmapped.
update public.positions set staff_class = '01'
where name in ('ADMINISTRATOR', 'SECRETARY', 'ACCOUNTANT', 'BURSAR');
update public.positions set staff_class = '02'
where name in ('HEAD TEACHER', 'ASSISTANT HEAD TEACHER', 'CLASS TEACHER', 'SUBJECT TEACHER',
               'TEACHING ASSISTANT', 'ICT COORDINATOR', 'LIBRARIAN');
update public.positions set staff_class = '03' where name = 'KITCHEN STAFF';
update public.positions set staff_class = '04' where name in ('CLEANER', 'SECURITY', 'CARETAKER');
update public.positions set staff_class = '05' where name = 'DRIVER';

-- ------------------------------------------------------------ tables

-- Every ID ever issued, current and retired, so a retired ID can never be
-- issued again (the primary key refuses it).
create table public.staff_numbers (
  number text primary key check (number ~ '^ST[0-9]{2}-0[1-5][0-9]{3}$'),
  employee_id uuid not null references public.employees (id) on delete restrict,
  year integer not null check (year between 2000 and 2099),
  class_code text not null check (class_code in ('01', '02', '03', '04', '05')),
  roll integer not null check (roll between 1 and 999),
  issued_at timestamptz not null default now(),
  issued_by uuid references public.staff (id) on delete restrict,
  retired_at timestamptz,
  retired_by uuid references public.staff (id) on delete restrict,
  retire_reason text,
  replaced_by text references public.staff_numbers (number) deferrable initially deferred,
  unique (year, roll),
  check (number = 'ST' || lpad((year % 100)::text, 2, '0') || '-' || class_code
                  || lpad(roll::text, 3, '0')),
  check ((retired_at is null) = (retire_reason is null)),
  check (retired_at is not null or (retired_by is null and replaced_by is null))
);

-- One current ID per person.
create unique index staff_numbers_one_current
  on public.staff_numbers (employee_id) where retired_at is null;

alter table public.staff_numbers enable row level security;
revoke all on table public.staff_numbers from public, anon, authenticated, service_role;
grant select on table public.staff_numbers to authenticated, service_role;

create policy staff_numbers_select on public.staff_numbers
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));

-- next_roll is the next roll to hand out in that year. No privilege for
-- any API role, service_role included, and no policy: only the functions
-- below move a counter. revoke all also removes TRUNCATE.
create table public.staff_number_counters (
  year integer primary key check (year between 2000 and 2099),
  next_roll integer not null default 1 check (next_roll between 1 and 1000)
);

alter table public.staff_number_counters enable row level security;
revoke all on table public.staff_number_counters from public, anon, authenticated, service_role;

-- An issued row changes once, when it is retired, and is never deleted.
-- This holds even for the definer functions.
create or replace function public.guard_staff_number_row()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'A staff ID is never deleted';
  end if;
  if old.retired_at is not null then
    raise exception 'Staff ID % is retired and cannot change', old.number;
  end if;
  if new.number is distinct from old.number
     or new.employee_id is distinct from old.employee_id
     or new.year is distinct from old.year
     or new.class_code is distinct from old.class_code
     or new.roll is distinct from old.roll
     or new.issued_at is distinct from old.issued_at
     or new.issued_by is distinct from old.issued_by
     or new.retired_at is null then
    raise exception 'Staff ID % can only be retired', old.number;
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_staff_number_row() from public, anon;

create trigger staff_numbers_guard
before update or delete on public.staff_numbers
for each row execute function public.guard_staff_number_row();

create or replace function public.audit_staff_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_branch uuid;
begin
  select branch_id into v_branch from public.employees where id = new.employee_id;

  if tg_op = 'INSERT' then
    v_actor := coalesce(auth.uid(), new.issued_by);
    if v_actor is null then return new; end if;
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch, v_actor, 'staff_number_issued', 'employees', new.employee_id::text, null,
      jsonb_build_object('number', new.number, 'year', new.year,
                         'class_code', new.class_code, 'roll', new.roll)
    );
  elsif old.retired_at is null and new.retired_at is not null then
    v_actor := coalesce(auth.uid(), new.retired_by);
    if v_actor is null then return new; end if;
    insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
    values (
      v_branch, v_actor, 'staff_number_retired', 'employees', new.employee_id::text,
      jsonb_build_object('number', old.number),
      jsonb_build_object('number', new.number, 'reason', new.retire_reason,
                         'replaced_by', new.replaced_by)
    );
  end if;
  return new;
end;
$$;

revoke execute on function public.audit_staff_number() from public, anon;

create trigger staff_numbers_audit
after insert or update on public.staff_numbers
for each row execute function public.audit_staff_number();

-- ------------------------------------------------------------ internal helpers

-- The class for an employee's current position, by exact name match (both
-- sides are uppercased by triggers). A position renamed in Settings stops
-- matching until its class is set again. Refuses when there's no class.
create or replace function public._staff_class_for_employee(p_employee_id uuid)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_position text;
  v_class text;
begin
  select position into v_position from public.employees where id = p_employee_id;
  select p.staff_class into v_class from public.positions p where p.name = v_position;
  if v_class is null then
    raise exception 'Set a classification for position % first.',
      coalesce(v_position, '(no position)');
  end if;
  return v_class;
end;
$$;

revoke execute on function public._staff_class_for_employee(uuid) from public, anon, authenticated, service_role;

-- Takes the next roll for a year. The counter row lock is held until
-- commit, so concurrent approvals queue. A rolled-back transaction rolls
-- its roll back too, so gaps come only from corrections.
create or replace function public._take_staff_roll(p_year integer)
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_roll integer;
begin
  insert into public.staff_number_counters (year) values (p_year) on conflict (year) do nothing;
  select next_roll into v_roll from public.staff_number_counters where year = p_year for update;
  if v_roll > 999 then
    raise exception 'All 999 staff IDs for % are used. The ID format must be widened in a reviewed change first.', p_year;
  end if;
  update public.staff_number_counters set next_roll = v_roll + 1 where year = p_year;
  return v_roll;
end;
$$;

revoke execute on function public._take_staff_roll(integer) from public, anon, authenticated, service_role;

-- Issues the first ID for an approved employee. Granted to nobody; called
-- only from approve_employee, inside its transaction.
create or replace function public._issue_staff_number(p_employee_id uuid, p_year integer)
returns text
language plpgsql
set search_path = public
as $$
declare
  v_status text;
  v_class text;
  v_roll integer;
  v_number text;
begin
  select employment_status into v_status from public.employees
  where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_status <> 'Active' then
    raise exception 'A staff ID is issued only to an approved employee';
  end if;
  if exists (select 1 from public.staff_numbers
             where employee_id = p_employee_id and retired_at is null) then
    raise exception 'This employee already has a staff ID';
  end if;

  v_class := public._staff_class_for_employee(p_employee_id);
  v_roll := public._take_staff_roll(p_year);

  -- Re-check under both locks.
  if exists (select 1 from public.staff_numbers
             where employee_id = p_employee_id and retired_at is null) then
    raise exception 'This employee already has a staff ID';
  end if;

  v_number := 'ST' || lpad((p_year % 100)::text, 2, '0') || '-' || v_class
              || lpad(v_roll::text, 3, '0');
  insert into public.staff_numbers (number, employee_id, year, class_code, roll, issued_by)
  values (v_number, p_employee_id, p_year, v_class, v_roll, auth.uid());
  return v_number;
end;
$$;

revoke execute on function public._issue_staff_number(uuid, integer) from public, anon, authenticated, service_role;

-- ------------------------------------------------------------ approve_employee

-- Same argument list, so create or replace and no drop. The only change is
-- the _issue_staff_number call at the end, after the record turns Active.
create or replace function public.approve_employee(
  p_employee_id uuid,
  p_basic_salary numeric default null,
  p_payment_method text default null,
  p_bank text default null,
  p_account_no text default null
)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can approve an employee record';
  end if;

  select * into v_emp from public.employees where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp.employment_status <> 'Pending Approval' then
    raise exception 'Employee % is not pending approval (status: %)', p_employee_id, v_emp.employment_status;
  end if;

  if p_basic_salary is not null and p_basic_salary < 0 then
    raise exception 'Basic salary cannot be negative';
  end if;
  if p_payment_method is not null and p_payment_method not in ('Bank', 'Mobile Money') then
    raise exception 'Payment method must be Bank or Mobile Money';
  end if;

  update public.employees
  set employment_status = 'Active', reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_employee_id
  returning * into v_emp;

  -- Approve the bundled initial config, if any and only if nothing is
  -- already Active for this employee (always true for a new record),
  -- applying any override in the same statement that flips it Active.
  update public.employee_pay_config
  set approval_status = 'Active',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      basic_salary = coalesce(p_basic_salary, basic_salary),
      payment_method = coalesce(p_payment_method, payment_method),
      bank = case when p_bank is not null then nullif(trim(p_bank), '') else bank end,
      account_no = case when p_account_no is not null then nullif(trim(p_account_no), '') else account_no end
  where employee_id = p_employee_id
    and approval_status = 'Pending Approval'
    and not exists (
      select 1 from public.employee_pay_config a
      where a.employee_id = p_employee_id and a.approval_status = 'Active' and a.effective_to is null
    );

  -- Staff ID, in the approval year (Africa/Accra). An unmapped position
  -- refuses the whole approval. Issued last, so the pay config
  -- checks above report their own errors first.
  perform public._issue_staff_number(
    p_employee_id, extract(year from v_emp.reviewed_at at time zone 'Africa/Accra')::integer
  );

  return v_emp;
end;
$$;

-- ------------------------------------------------------------ correction

create or replace function public.correct_staff_number(p_employee_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_status text;
  v_old public.staff_numbers;
  v_class text;
  v_roll integer;
  v_number text;
begin
  perform public.require_staff();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can correct a staff ID';
  end if;
  if v_reason is null then
    raise exception 'A reason is required to correct a staff ID';
  end if;
  if length(v_reason) > 500 then
    raise exception 'The reason must be 500 characters or fewer';
  end if;

  select employment_status into v_status from public.employees
  where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_status not in ('Active', 'Suspended') then
    raise exception 'A staff ID can be corrected only for an Active or Suspended employee';
  end if;
  if exists (select 1 from public.staff_numbers
             where employee_id = p_employee_id and retired_at is not null) then
    raise exception 'This employee''s staff ID has already been corrected once';
  end if;
  select * into v_old from public.staff_numbers
  where employee_id = p_employee_id and retired_at is null;
  if not found then
    raise exception 'This employee has no staff ID to correct';
  end if;

  v_class := public._staff_class_for_employee(p_employee_id);
  v_roll := public._take_staff_roll(v_old.year);

  -- Re-check under both locks.
  if exists (select 1 from public.staff_numbers
             where employee_id = p_employee_id and retired_at is not null)
     or not exists (select 1 from public.staff_numbers
                    where number = v_old.number and retired_at is null) then
    raise exception 'This employee''s staff ID changed while correcting; reload and try again';
  end if;

  v_number := 'ST' || lpad((v_old.year % 100)::text, 2, '0') || '-' || v_class
              || lpad(v_roll::text, 3, '0');

  -- replaced_by is deferred, so the old row can point at the new one
  -- before it exists; the partial unique index needs the old one retired
  -- first.
  update public.staff_numbers
  set retired_at = now(), retired_by = auth.uid(), retire_reason = v_reason, replaced_by = v_number
  where number = v_old.number;

  insert into public.staff_numbers (number, employee_id, year, class_code, roll, issued_by)
  values (v_number, p_employee_id, v_old.year, v_class, v_roll, auth.uid());

  return v_number;
end;
$$;

revoke execute on function public.correct_staff_number(uuid, text) from public, anon;
grant execute on function public.correct_staff_number(uuid, text) to authenticated;

-- ------------------------------------------------------------ {{staff_id}} merge field

-- A template that uses {{staff_id}} can be generated only once the
-- employee has a current ID, and the merge data must carry that ID, so a
-- document never shows a missing or stale one. There's no placeholder
-- text: the generation is refused. The PDF is rendered in the browser, so
-- the dialog checks the same thing before it renders or uploads anything;
-- this is the enforcement. Same argument list, so create or replace; the
-- only change is the staff_id block.
create or replace function public.generate_employee_document(
  p_employee_id uuid,
  p_document_kind text,
  p_storage_path text,
  p_merge_data jsonb
)
returns public.employee_generated_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resolved_kind text;
  v_is_teaching boolean;
  v_next_version integer;
  v_doc public.employee_generated_documents;
  v_number text;
begin
  perform public.require_finance_writer();

  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'Employee not found.';
  end if;

  if p_document_kind = 'Contract' then
    select p.is_teaching into v_is_teaching
    from public.employees e
    join public.positions p on p.name = e.position
    where e.id = p_employee_id;

    v_resolved_kind := case when coalesce(v_is_teaching, false)
      then 'Contract-Teaching' else 'Contract-Non-Teaching' end;
  elsif p_document_kind in ('Appointment Letter', 'Probation Letter') then
    v_resolved_kind := p_document_kind;
  else
    raise exception 'Unknown document kind: %', p_document_kind;
  end if;

  if exists (select 1 from public.contract_templates
             where category = v_resolved_kind and strpos(html_body, '{{staff_id}}') > 0) then
    select number into v_number from public.staff_numbers
    where employee_id = p_employee_id and retired_at is null;
    if v_number is null then
      raise exception 'Approve this employee first so a staff ID exists';
    end if;
    if p_merge_data->>'staff_id' is distinct from v_number then
      raise exception 'The staff ID in this document is out of date. Reload the page and generate it again.';
    end if;
  end if;

  select coalesce(max(version), 0) + 1 into v_next_version
  from public.employee_generated_documents
  where employee_id = p_employee_id and document_kind = v_resolved_kind;

  insert into public.employee_generated_documents (
    employee_id, document_kind, version, storage_path, merge_data
  ) values (
    p_employee_id, v_resolved_kind, v_next_version, p_storage_path, p_merge_data
  ) returning * into v_doc;

  return v_doc;
end;
$$;
