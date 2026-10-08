-- Role matrix for 20261009100000_employee_bulk_import (bulk upload of
-- employees: preview_employee_import(), import_employees() and the private
-- checker).
-- Run: ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261009100000_employee_bulk_import.sql
--
-- Expected access (approved by Eyram 2026-10-08): the roles that can add an
-- employee by hand (Manager and Accountant, require_finance_writer()) can
-- preview and import; nobody can call the private helpers; anon executes
-- none of the new functions. Every import creates Pending Approval
-- employees (and Pending Approval pay config), never live pay config, and
-- an import with any problem row saves nothing.
--
-- Fixture names are invented (MATRIX IMPORT ...).

-- ============================================================ A. preview

-- probe: A1 preview a valid row
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix Import One",
    "basic_salary": "1500", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}}]');
  if jsonb_array_length(v -> 0 -> 'errors') <> 0 or v -> 0 ? 'values' then
    raise exception 'A1: exp no errors and no values got %', v;
  end if;
  if exists (select 1 from public.employees where name = 'MATRIX IMPORT ONE') then
    raise exception 'A1: preview saved a row';
  end if;
end $$;

-- probe: A2 preview an empty file
-- expect: Manager,Accountant
-- as role:
do $$
begin
  if public.preview_employee_import('[]') <> '[]'::jsonb then
    raise exception 'A2: exp []';
  end if;
end $$;

-- probe: A3 preview errors name the column only, never the value
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status, national_id, phone) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'MATRIX EXISTING', 'Active', 'GHA-777', '0209998887');
-- as role:
do $$
declare v text;
begin
  v := public.preview_employee_import('[
    {"row": 2, "cells": {"name": "Matrix Import Two", "basic_salary": "1500.005",
      "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes", "national_id": "gha-777",
      "phone": "020 999 8887", "date_of_birth": "13/13/1999"}},
    {"row": 3, "cells": {"name": "Matrix Existing", "basic_salary": "-15.5",
      "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}}]')::text;
  if v ~ '1500|005|GHA-777|gha-777|999|887|13/13|15\.5|MATRIX EXISTING' then
    raise exception 'A3: a value from the file or the existing employee leaked: %', v;
  end if;
  if v !~ 'at most 2 decimal places' or v !~ 'already exists' or v !~ 'must not be negative'
     or v !~ 'matches an existing employee' then
    raise exception 'A3: expected messages missing: %', v;
  end if;
end $$;

-- probe: A4 money cells: non-ASCII digits and misplaced commas are refused cleanly
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb; t text;
begin
  v := public.preview_employee_import('[
    {"row": 2, "cells": {"name": "Matrix Money A", "basic_salary": "١٢٣", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}},
    {"row": 3, "cells": {"name": "Matrix Money B", "basic_salary": "１２３", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}},
    {"row": 4, "cells": {"name": "Matrix Money C", "basic_salary": "1,50", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}},
    {"row": 5, "cells": {"name": "Matrix Money D", "basic_salary": "1 500", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}},
    {"row": 6, "cells": {"name": "Matrix Money E", "basic_salary": "GHS 12,345.50", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}}]');
  t := v::text;
  if t ~ '١٢٣|１２３|1,50|1 500|12,345' then
    raise exception 'A4: a value leaked: %', t;
  end if;
  if (select array_agg(r -> 'errors' ->> 0 order by ord) from jsonb_array_elements(v) with ordinality x(r, ord))
     is distinct from array['Basic salary is not a valid amount', 'Basic salary is not a valid amount',
       'Basic salary is not a valid amount', 'Basic salary is not a valid amount', null] then
    raise exception 'A4: unexpected result %', t;
  end if;
end $$;

-- ============================================================ B. import

-- probe: B1 import a row with only a name: Pending employee, no pay config
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb; s text; n integer;
begin
  v := public.import_employees('[{"row": 2, "cells": {"name": "Matrix Import Three"}}]');
  if v <> '{"created": 1, "with_pay_config": 0}'::jsonb then
    raise exception 'B1: result exp created 1 got %', v;
  end if;
  select employment_status into s from public.employees where name = 'MATRIX IMPORT THREE';
  if s is distinct from 'Pending Approval' then
    raise exception 'B1: status exp Pending Approval got %', s;
  end if;
  select count(*) into n from public.employee_pay_config c
    join public.employees e on e.id = c.employee_id where e.name = 'MATRIX IMPORT THREE';
  if n <> 0 then raise exception 'B1: pay config rows exp 0 got %', n; end if;
end $$;

-- probe: B2 import a National Service row with salary: Pending pay config, flags as given, never Active
-- expect: Manager,Accountant
-- as role:
do $$
declare c public.employee_pay_config; n integer;
begin
  perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix Import Four",
    "basic_salary": "1,500.50", "pays_ssnit": "No", "pays_tier2": "No", "pays_paye": "No",
    "effective_from": "2026-11-01"}}]');
  select c2.* into c from public.employee_pay_config c2
    join public.employees e on e.id = c2.employee_id where e.name = 'MATRIX IMPORT FOUR';
  if c.approval_status <> 'Pending Approval' or c.basic_salary <> 1500.50
     or c.pays_ssnit or c.pays_tier2 or c.pays_paye or c.effective_from <> date '2026-11-01'
     or c.payment_method <> 'Bank' then
    raise exception 'B2: pay config not as expected';
  end if;
  select count(*) into n from public.employee_pay_config c3
    join public.employees e on e.id = c3.employee_id
    where e.name = 'MATRIX IMPORT FOUR' and c3.approval_status = 'Active';
  if n <> 0 then raise exception 'B2: an Active pay config was written'; end if;
end $$;

-- probe: B3 one summary audit row, counts only
-- expect: Manager,Accountant
-- as role:
do $$
declare n integer; a jsonb;
begin
  perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix Import Five",
    "basic_salary": "2000", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}},
    {"row": 3, "cells": {"name": "Matrix Import Six"}}]');
  select count(*), max(after::text)::jsonb into n, a from public.audit_log
    where action = 'employees_imported' and occurred_at = now();
  if n <> 1 or a <> '{"rows": 2, "created": 2, "with_pay_config": 1}'::jsonb then
    raise exception 'B3: audit exp one row with counts got % %', n, a;
  end if;
end $$;

-- probe: B4 any problem row means nothing is saved
-- expect: Manager,Accountant
-- as role:
do $$
begin
  begin
    perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix Import Seven"}},
      {"row": 3, "cells": {"name": "Matrix Import Eight", "basic_salary": "1000",
        "pays_ssnit": "maybe", "pays_tier2": "Yes", "pays_paye": "Yes"}}]');
  exception when others then
    if sqlerrm <> 'Import refused: 1 row(s) have problems. Nothing was saved.' then raise; end if;
    if exists (select 1 from public.employees where name in ('MATRIX IMPORT SEVEN', 'MATRIX IMPORT EIGHT')) then
      raise exception 'B4: a row was saved';
    end if;
    return;
  end;
  raise exception 'B4: import accepted a file with a problem row';
end $$;

-- probe: B5 the unedited template example row is refused
-- expect: Manager,Accountant
-- as role:
do $$
begin
  begin
    perform public.import_employees('[{"row": 2, "cells": {"name": "Example Employee - Delete This Row",
      "basic_salary": "2500.00", "pays_ssnit": "Yes", "pays_tier2": "Yes", "pays_paye": "Yes"}}]');
  exception when others then
    if sqlerrm <> 'Import refused: 1 row(s) have problems. Nothing was saved.' then raise; end if;
    return;
  end;
  raise exception 'B5: the example row was imported';
end $$;

-- probe: B6 a name matching an existing employee is refused
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('90d00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'MATRIX EXISTING', 'Pending Approval');
-- as role:
do $$
begin
  begin
    perform public.import_employees('[{"row": 2, "cells": {"name": "matrix   existing"}}]');
  exception when others then
    if sqlerrm <> 'Import refused: 1 row(s) have problems. Nothing was saved.' then raise; end if;
    return;
  end;
  raise exception 'B6: a duplicate name was imported';
end $$;

-- probe: B7 more than 200 rows is refused
-- expect: Manager,Accountant
-- as role:
do $$
begin
  begin
    perform public.import_employees((select jsonb_agg(jsonb_build_object('row', g + 1,
      'cells', jsonb_build_object('name', 'Matrix Bulk ' || g))) from generate_series(1, 201) g));
  exception when others then
    if sqlerrm <> 'This file has more than 200 employees. Split it into smaller files and import each one.' then
      raise;
    end if;
    return;
  end;
  raise exception 'B7: 201 rows were accepted';
end $$;

-- probe: B8 two rows with the same name in one file are refused
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix Twin"}},
    {"row": 3, "cells": {"name": "matrix   TWIN"}}]');
  if v -> 1 -> 'errors' <> '["Same name as row 2. If this is a different person, add them by hand."]'::jsonb then
    raise exception 'B8: preview exp the same-name error got %', v;
  end if;
  begin
    perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix Twin"}},
      {"row": 3, "cells": {"name": "matrix   TWIN"}}]');
  exception when others then
    if sqlerrm <> 'Import refused: 1 row(s) have problems. Nothing was saved.' then raise; end if;
    return;
  end;
  raise exception 'B8: both rows were imported';
end $$;

-- probe: B9 a failure while saving shows the row number only, never the underlying text
-- expect: Manager,Accountant
create function public.matrix_import_fail() returns trigger language plpgsql as $f$
begin
  if new.name = 'MATRIX WRAP' then
    raise exception 'leak: % 1500.005', new.name;
  end if;
  return new;
end $f$;
create trigger matrix_import_fail before insert on public.employees
  for each row execute function public.matrix_import_fail();
-- as role:
do $$
begin
  begin
    perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix Wrap"}}]');
  exception when others then
    if sqlerrm <> 'Row 2 could not be saved. Nothing was saved.' then
      raise exception 'B9: exp the row-only message got: %', sqlerrm;
    end if;
    return;
  end;
  raise exception 'B9: the failing row was saved';
end $$;

-- probe: B10 a salaried row with blank flags: warnings only, imported as Yes
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb; c public.employee_pay_config;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix Import Flags",
    "basic_salary": "1200", "pays_tier2": "No"}}]');
  if v -> 0 -> 'errors' <> '[]'::jsonb
     or v -> 0 -> 'notes' <> '["SSNIT flag blank, will be treated as Yes", "PAYE flag blank, will be treated as Yes"]'::jsonb then
    raise exception 'B10: preview exp two warnings and no errors got %', v;
  end if;
  perform public.import_employees('[{"row": 2, "cells": {"name": "Matrix Import Flags",
    "basic_salary": "1200", "pays_tier2": "No"}}]');
  select c2.* into c from public.employee_pay_config c2
    join public.employees e on e.id = c2.employee_id where e.name = 'MATRIX IMPORT FLAGS';
  if c.approval_status <> 'Pending Approval' or not c.pays_ssnit or c.pays_tier2 or not c.pays_paye then
    raise exception 'B10: pay config exp Pending with Yes/No/Yes';
  end if;
end $$;

-- probe: B11 blank dates and lists are accepted; a wrong date or list value is still refused
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb;
begin
  v := public.preview_employee_import('[
    {"row": 2, "cells": {"name": "Matrix Blank Cells", "date_of_birth": "", "start_date": null,
      "position": "", "department": " ", "employment_type": "", "bank": null}},
    {"row": 3, "cells": {"name": "Matrix Wrong Cells", "start_date": "2026-13-01",
      "position": "Not A Position", "employment_type": "Casual"}}]');
  if v -> 0 -> 'errors' <> '[]'::jsonb then
    raise exception 'B11: blank cells refused: %', v;
  end if;
  if v -> 1 -> 'errors' <> '["Start date must be a real date written YYYY-MM-DD",
      "Employment type must be Full-Time, Part-Time, Contract, Volunteer, Intern or National Service",
      "Position is not in the list of positions"]'::jsonb then
    raise exception 'B11: exp the three field errors got %', v -> 1;
  end if;
end $$;

-- probe: B12 a row without a name is refused (the only required column)
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "  ", "position": "Administrator"}}]');
  if v -> 0 -> 'errors' <> '["Name is required"]'::jsonb then
    raise exception 'B12: exp Name is required got %', v;
  end if;
end $$;

-- probe: B13 pay details without a salary are refused, not silently dropped
-- expect: Manager,Accountant
-- as role:
do $$
declare v jsonb;
begin
  v := public.preview_employee_import('[{"row": 2, "cells": {"name": "Matrix No Salary",
    "bank": "GCB Bank", "pays_ssnit": "No"}}]');
  if v -> 0 -> 'errors' <> '["Basic salary is required when pay details are given"]'::jsonb then
    raise exception 'B13: exp the pay-details error got %', v;
  end if;
end $$;

-- ============================================================ C. helpers and anon

-- probe: C1 the private checker
-- expect: none
-- as role:
select public._employee_import_check('[]');

-- probe: C2 the private money parser
-- expect: none
-- as role:
select public._employee_import_money('1');

-- probe: C3 the private date parser
-- expect: none
-- as role:
select public._employee_import_date('2026-01-01');

-- probe: C4 the private Yes/No parser
-- expect: none
-- as role:
select public._employee_import_yes_no('yes');

-- probe: C5 anon can execute none of the new functions
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
-- as role:
do $$
declare f text;
begin
  foreach f in array array['public.preview_employee_import(jsonb)', 'public.import_employees(jsonb)',
    'public._employee_import_check(jsonb)', 'public._employee_import_money(text)',
    'public._employee_import_date(text)', 'public._employee_import_yes_no(text)'] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'anon can execute %', f;
    end if;
  end loop;
end $$;
