-- Role matrix for 20261010100000_employment_type_national_service ("National
-- Service" as an employment type: the employees check constraint,
-- update_employee_profile()'s allowed list, and the import checker).
-- Run: ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261010100000_employment_type_national_service.sql
--
-- Approved by Eyram 2026-10-08. An HR label only: who can call what is
-- unchanged (update_employee_profile and the import: Manager and
-- Accountant), the SSNIT / Tier 2 / PAYE flags are never set from the type,
-- and no payroll figure depends on it.
--
-- Fixtures: employee 90d0...01 (invented name MATRIX NS ...).

-- ============================================================ A. constraint and profile

-- probe: A1 the employees constraint accepts National Service (setup fails otherwise)
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
insert into public.employees (id, branch_id, name, employment_status, employment_type) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'MATRIX NS CONSTRAINT', 'Active', 'National Service');
-- as role:
select 1;

-- probe: A2 update_employee_profile sets National Service and leaves the pay flags alone
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status, employment_type) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'MATRIX NS PROFILE', 'Active', 'Full-Time');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 1500, date '2026-01-01', true, true, true);
-- as role:
do $$
declare t text; c public.employee_pay_config;
begin
  perform public.update_employee_profile('90d00000-0000-0000-0000-000000000001', null, null, null,
    p_employment_type => 'National Service');
  select employment_type into t from public.employees where id = '90d00000-0000-0000-0000-000000000001';
  select * into c from public.employee_pay_config where employee_id = '90d00000-0000-0000-0000-000000000001';
  if t is distinct from 'National Service' then
    raise exception 'A2: type exp National Service got %', t;
  end if;
  if not (c.pays_ssnit and c.pays_tier2 and c.pays_paye) or c.basic_salary <> 1500 then
    raise exception 'A2: the pay config changed';
  end if;
end $$;

-- probe: A3 update_employee_profile still refuses an unknown type, with the new list
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'MATRIX NS UNKNOWN', 'Active');
-- as role:
do $$
begin
  begin
    perform public.update_employee_profile('90d00000-0000-0000-0000-000000000001', null, null, null,
      p_employment_type => 'Casual');
  exception when others then
    if sqlerrm <> 'Employment type must be Full-Time, Part-Time, Contract, Volunteer, Intern or National Service' then
      raise;
    end if;
    return;
  end;
  raise exception 'A3: Casual was accepted';
end $$;

-- ============================================================ B. import

-- probe: B1 an import row with National Service and No, No, No saves as given, no warning
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb; e public.employees; c public.employee_pay_config;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix NS Import",
    "employment_type": "national service", "basic_salary": "900", "pays_ssnit": "No",
    "pays_tier2": "No", "pays_paye": "No"}}]');
  if v -> 0 -> 'errors' <> '[]'::jsonb or v -> 0 -> 'notes' <> '[]'::jsonb then
    raise exception 'B1: preview exp no errors and no warnings got %', v;
  end if;
  perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix NS Import",
    "employment_type": "national service", "basic_salary": "900", "pays_ssnit": "No",
    "pays_tier2": "No", "pays_paye": "No"}}]');
  select * into e from public.employees where name = 'MATRIX NS IMPORT';
  select * into c from public.employee_pay_config where employee_id = e.id;
  if e.employment_type is distinct from 'National Service' or e.employment_status <> 'Pending Approval'
     or c.approval_status <> 'Pending Approval' or c.basic_salary <> 900
     or c.pays_ssnit or c.pays_tier2 or c.pays_paye then
    raise exception 'B1: saved row not as expected';
  end if;
end $$;

-- probe: B2 National Service with a Yes or blank flag: reminder only, imported exactly as given
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb; c public.employee_pay_config;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix NS Yes",
    "employment_type": "National Service", "basic_salary": "900", "pays_ssnit": "Yes",
    "pays_tier2": "No"}}]');
  if v -> 0 -> 'errors' <> '[]'::jsonb or v -> 0 -> 'notes' <> '["PAYE flag blank, will be treated as Yes",
      "National Service staff are normally exempt: check the SSNIT, Tier 2 and PAYE flags"]'::jsonb then
    raise exception 'B2: preview exp two warnings and no errors got %', v;
  end if;
  perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix NS Yes",
    "employment_type": "National Service", "basic_salary": "900", "pays_ssnit": "Yes",
    "pays_tier2": "No"}}]');
  select c2.* into c from public.employee_pay_config c2
    join public.employees e on e.id = c2.employee_id where e.name = 'MATRIX NS YES';
  if not c.pays_ssnit or c.pays_tier2 or not c.pays_paye then
    raise exception 'B2: flags were changed from what was given (exp Yes, No, Yes)';
  end if;
end $$;

-- probe: B3 National Service without a salary: no pay config, no reminder
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix NS No Pay",
    "employment_type": "National Service"}}]');
  if v -> 0 -> 'errors' <> '[]'::jsonb or v -> 0 -> 'notes' <> '[]'::jsonb then
    raise exception 'B3: exp no errors and no warnings got %', v;
  end if;
end $$;

-- ============================================================ C. payroll ignores the label

-- probe: C1 a National Service employee who still pays all three gets exactly the Full-Time figures
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status, employment_type) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'MATRIX NS PAYSLIP', 'Active', 'National Service');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye)
values ('90d00000-0000-0000-0000-000000000001', 3100, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year)
values ('90d00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- as role:
do $$
declare p public.payslips;
begin
  -- Same figures as the golden suite's basic 3,100 September 2026 base
  -- (supabase/golden/payslips.sql): the type changes nothing.
  p := public.create_payslip('90d00000-0000-0000-0000-0000000000a1', '90d00000-0000-0000-0000-000000000001');
  if p.taxable_income <> 2929.50 or p.tax <> 392.26 or p.ssnit <> 15.50 or p.tier2 <> 155.00
     or p.total_deductions <> 562.76 or p.net_pay <> 2537.24 then
    raise exception 'C1: figures differ from the Full-Time base';
  end if;
end $$;
