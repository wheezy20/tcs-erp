-- Probes for 20261019100000_audit_log_admissions_read (slice 7c,
-- docs/admissions/PORT-PLAN.md): Manager and Auditor read every audit row,
-- the Accountant every row except the admissions ones (D-1b), and nobody
-- else reads any. audit_log stays write-proof for every role.
--
-- Each probe seeds one row per action with entity_id 'probe-7c' and counts
-- only those, so the rows already in seed.sql don't matter.
--
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261019100000_audit_log_admissions_read.sql

-- probe: S1 every action in the audit CHECK is classified: 9 admissions, 31 other
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$
declare
  v_admissions text[] := array[
    'admissions_capabilities_changed', 'application_stage_changed',
    'application_document_status_changed', 'application_decision_changed',
    'admissions_capacity_changed', 'application_offer_changed', 'admissions_settings_changed',
    'application_grade_corrected', 'admissions_academic_year_changed'];
  v_other text[] := array[
    'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
    'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
    'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
    'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
    'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
    'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
    'staff_advance_proposed', 'staff_advance_approved', 'staff_advance_rejected',
    'staff_advance_change_proposed', 'staff_advance_change_approved',
    'staff_advance_change_rejected', 'employees_imported',
    -- 20261026100000_hr_staff_numbers: HR actions, read like the employee ones.
    'staff_number_issued', 'staff_number_retired', 'position_staff_class_changed'];
  v_def text;
  v_listed text[];
begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint
  where conrelid = 'public.audit_log'::regclass and conname = 'audit_log_action_check';
  select array_agg(m[1] order by m[1]) into v_listed
  from regexp_matches(v_def, '''([a-z_]+)''', 'g') as m;
  if v_listed is distinct from (select array_agg(a order by a) from unnest(v_admissions || v_other) a) then
    raise exception 'audit action list changed: classify the new action in this file';
  end if;
  if exists (select 1 from unnest(v_admissions) a
             where not (starts_with(a, 'application_') or starts_with(a, 'admissions_'))) then
    raise exception 'an admissions action lacks the application_ or admissions_ prefix';
  end if;
  if exists (select 1 from unnest(v_other) a
             where starts_with(a, 'application_') or starts_with(a, 'admissions_')) then
    raise exception 'a non-admissions action has an admissions prefix';
  end if;
end $$;
-- as role:
select 1;

-- probe: S2 audit_log has exactly one policy, a select policy, and no insert, update or delete grant for any API role
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- TRUNCATE is probed in 20261019110000_audit_log_revoke_truncate.sql, the
-- migration that revokes it.
do $$ declare r text; p text;
begin
  if (select array_agg(polname::text || ':' || polcmd::text) from pg_policy
      where polrelid = 'public.audit_log'::regclass) is distinct from array['audit_log_select:r'] then
    raise exception 'audit_log policies changed';
  end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['insert', 'update', 'delete'] loop
      if has_table_privilege(r, 'public.audit_log', p) then
        raise exception '% holds % on audit_log', r, p;
      end if;
    end loop;
  end loop;
  if has_table_privilege('anon', 'public.audit_log', 'select') then
    raise exception 'anon can select audit_log';
  end if;
end $$;
-- as role:
select 1;

-- probe: S3 anon can still execute exactly 170 public functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) <> 170 then
    raise exception 'anon-executable function count changed';
  end if;
end $$;
-- as role:
select 1;

-- probe: R1 sees all 9 admissions action rows
-- expect: Manager,Auditor
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select (select id from public.branches order by created_at limit 1),
       (select id from public.staff where role = 'Manager' and active order by id limit 1),
       a, 'probe', 'probe-7c'
from unnest(array[
  'admissions_capabilities_changed', 'application_stage_changed',
  'application_document_status_changed', 'application_decision_changed',
  'admissions_capacity_changed', 'application_offer_changed', 'admissions_settings_changed',
  'application_grade_corrected', 'admissions_academic_year_changed']) a;
-- as role:
do $$ begin
  if (select count(distinct action) from public.audit_log where entity_id = 'probe-7c') <> 9 then
    raise exception 'not every admissions row is visible';
  end if;
end $$;

-- probe: R2 sees no admissions action row (anon has no select at all)
-- expect: anon,Attendant,Accountant,Admissions Officer
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select (select id from public.branches order by created_at limit 1),
       (select id from public.staff where role = 'Manager' and active order by id limit 1),
       a, 'probe', 'probe-7c'
from unnest(array[
  'admissions_capabilities_changed', 'application_stage_changed',
  'application_document_status_changed', 'application_decision_changed',
  'admissions_capacity_changed', 'application_offer_changed', 'admissions_settings_changed',
  'application_grade_corrected', 'admissions_academic_year_changed']) a;
-- as role:
do $$ begin
  if exists (select 1 from public.audit_log where entity_id = 'probe-7c') then
    raise exception 'an admissions row is visible';
  end if;
exception when insufficient_privilege then
  null;
end $$;

-- probe: R3 sees all 28 non-admissions action rows, payroll and employee ones included
-- expect: Manager,Accountant,Auditor
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
select (select id from public.branches order by created_at limit 1),
       (select id from public.staff where role = 'Manager' and active order by id limit 1),
       a, 'probe', 'probe-7c'
from unnest(array[
  'discount_applied', 'vat_override', 'return_processed', 'sale_voided', 'invoice_voided',
  'expense_voided', 'employee_created', 'employee_approved', 'employee_rejected',
  'employee_suspended', 'employee_reactivated', 'pay_config_proposed', 'pay_config_approved',
  'pay_config_amended_and_approved', 'pay_config_rejected', 'pay_config_exemptions_changed',
  'payroll_run_submitted', 'payroll_run_approved', 'payroll_run_rejected',
  'payroll_run_exclusion_added', 'payroll_run_exclusion_removed',
  'staff_advance_proposed', 'staff_advance_approved', 'staff_advance_rejected',
  'staff_advance_change_proposed', 'staff_advance_change_approved',
  'staff_advance_change_rejected', 'employees_imported']) a;
-- as role:
do $$ begin
  if (select count(distinct action) from public.audit_log where entity_id = 'probe-7c') <> 28 then
    raise exception 'not every non-admissions row is visible';
  end if;
end $$;

-- probe: R4 the employee History section's query (employees and employee_pay_config rows) returns both
-- expect: Manager,Accountant,Auditor
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
values
  ((select id from public.branches order by created_at limit 1),
   (select id from public.staff where role = 'Manager' and active order by id limit 1),
   'employee_approved', 'employees', 'probe-7c-employee'),
  ((select id from public.branches order by created_at limit 1),
   (select id from public.staff where role = 'Manager' and active order by id limit 1),
   'pay_config_approved', 'employee_pay_config', 'probe-7c-config');
-- as role:
do $$ begin
  if (select count(*) from public.audit_log
      where (entity_table = 'employees' and entity_id = 'probe-7c-employee')
         or (entity_table = 'employee_pay_config' and entity_id in ('probe-7c-config'))) <> 2 then
    raise exception 'employee history rows not visible';
  end if;
end $$;

-- probe: R5 sees no row of any kind
-- expect: anon,Attendant,Admissions Officer
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
values
  ((select id from public.branches order by created_at limit 1),
   (select id from public.staff where role = 'Manager' and active order by id limit 1),
   'payroll_run_approved', 'probe', 'probe-7c'),
  ((select id from public.branches order by created_at limit 1),
   (select id from public.staff where role = 'Manager' and active order by id limit 1),
   'application_stage_changed', 'probe', 'probe-7c');
-- as role:
do $$ begin
  if exists (select 1 from public.audit_log where entity_id = 'probe-7c') then
    raise exception 'a row is visible';
  end if;
exception when insufficient_privilege then
  null;
end $$;

-- probe: W1 insert into audit_log
-- expect: none
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
values ((select id from public.branches order by created_at limit 1),
        (select id from public.staff where role = 'Manager' and active order by id limit 1),
        'vat_override', 'probe', 'probe-7c');

-- probe: W2 update an audit row (raises when nothing is changed)
-- expect: none
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
values ((select id from public.branches order by created_at limit 1),
        (select id from public.staff where role = 'Manager' and active order by id limit 1),
        'vat_override', 'probe', 'probe-7c');
-- as role:
do $$ declare n integer;
begin
  update public.audit_log set entity_id = 'changed' where entity_id = 'probe-7c';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'nothing updated'; end if;
end $$;

-- probe: W3 delete an audit row (raises when nothing is deleted)
-- expect: none
insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id)
values ((select id from public.branches order by created_at limit 1),
        (select id from public.staff where role = 'Manager' and active order by id limit 1),
        'vat_override', 'probe', 'probe-7c');
-- as role:
do $$ declare n integer;
begin
  delete from public.audit_log where entity_id = 'probe-7c';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'nothing deleted'; end if;
end $$;
