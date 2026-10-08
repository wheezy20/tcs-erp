-- Bulk upload of employees (HR and pay records) from a spreadsheet.
--
-- Decisions (Eyram, 2026-10-08):
--   * Employees only. Staff logins and roles stay manual.
--   * Preview first, then all-or-nothing: preview_employee_import() checks
--     every row and saves nothing; import_employees() checks the whole file
--     again under a lock and creates every row, or refuses with nothing
--     saved. Both use one private checker, so they can't disagree.
--   * Each row goes through the manual path unchanged: propose_employee()
--     (a Pending Approval employee, plus a Pending Approval pay config when
--     a salary is given; never live pay config) and then
--     update_employee_profile() for the HR fields. Every existing rule,
--     trigger and audit row applies as for manual entry. A Manager approves
--     each employee on the existing screens.
--   * Only Name is required (the duplicate checks depend on it); every
--     other column may be left blank and filled in by hand later. A blank
--     date or list cell is accepted as blank; a wrong value is an error.
--   * On a row with a salary, a blank SSNIT, Tier 2 or PAYE flag is treated
--     as Yes, the default manual entry uses, with a warning on that row
--     that doesn't block the import (Eyram, 2026-10-08, replacing the
--     earlier "blank flag is an error"). A value other than Yes/No is an
--     error. A National Service row says No, No, No.
--   * Pay details (payment method, bank, account, effective from, flags)
--     need a salary: propose_employee() stores them only in a pay config,
--     which it creates only when a salary is given, so a row with pay
--     details and no salary is refused rather than losing them.
--   * Duplicates are refused: national ID, SSNIT number, TIN or school email
--     matching an existing (not Rejected) employee or an earlier row, and a
--     name matching one ("add them by hand"). A matching phone number is a
--     warning only. Nothing is ever updated or overwritten.
--   * The template's example row is refused if uploaded unchanged.
--   * No error message or notice contains a value from the file: messages
--     name the column only, and a failure while saving is reported by row
--     number only. The per-employee audit rows are exactly what manual
--     entry writes; the import adds one summary row with counts only.
--   * Limits: 200 rows and 512 KB per file.
--   * Standing allowances are not imported (set by hand after approval).
--
-- Payload: a jsonb array of {"row": <spreadsheet row number>, "cells":
-- {"<key>": "<text>" | null, ...}} using the keys below. All parsing (money,
-- dates, Yes/No, list matching) happens here, not in the browser.

-- ============================================================ 1. audit action

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
  'employees_imported'
]));

-- ============================================================ 2. parsing helpers

-- A money cell: an optional leading "GHS" or cedi sign, ASCII digits, commas
-- only as thousands separators (so "1,50" is refused, not read as 150), and
-- at most 2 decimals. Returns the amount, or a problem phrase that never
-- contains the value. [0-9], not \d: \d also matches non-ASCII digits, which
-- the numeric cast would then reject with the value in its message.
create function public._employee_import_money(p_text text, out amount numeric, out problem text)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := btrim(regexp_replace(btrim(p_text), '^(GHS|GH¢|₵|¢)\s*', '', 'i'));
begin
  if v ~ '^-' or v ~ '^\(.*\)$' then
    problem := 'must not be negative';
    return;
  end if;
  if v ~ '^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$' then
    v := replace(v, ',', '');
  end if;
  if v ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then
    amount := v::numeric;
  elsif v ~ '^[0-9]{1,10}\.[0-9]{3,}$' then
    problem := 'must have at most 2 decimal places';
  elsif v ~ '^[0-9]+(\.[0-9]+)?$' then
    problem := 'is too large';
  else
    problem := 'is not a valid amount';
  end if;
end;
$$;

-- A date cell, written YYYY-MM-DD.
create function public._employee_import_date(p_text text, out value date, out problem text)
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    problem := 'must be a date written YYYY-MM-DD';
    return;
  end if;
  begin
    value := p_text::date;
  exception when others then
    problem := 'must be a real date written YYYY-MM-DD';
  end;
end;
$$;

-- A Yes/No cell (also Y/N, true/false, 1/0). Null when it's neither.
create function public._employee_import_yes_no(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(p_text) in ('yes', 'y', 'true', '1') then true
    when lower(p_text) in ('no', 'n', 'false', '0') then false
  end;
$$;

-- ============================================================ 3. the checker

-- Checks every row and returns, in order, one object per row:
-- {row, errors: [text], notes: [text], values: {...typed values...}}.
-- `values` is only used by import_employees(); preview strips it.
-- A file-level problem (too many rows, too large) raises.
create function public._employee_import_check(p_rows jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_keys constant text[] := array[
    'name', 'preferred_name', 'phone', 'gender', 'date_of_birth', 'national_id',
    'personal_email', 'school_email', 'position', 'department', 'employment_type',
    'start_date', 'probation_end_date', 'contract_end_date', 'ssnit_number', 'tin_number',
    'church_denomination', 'emergency_contact_name', 'emergency_contact_phone',
    'residential_address', 'basic_salary', 'payment_method', 'bank', 'account_no',
    'effective_from', 'pays_ssnit', 'pays_tier2', 'pays_paye'];
  c_labels constant jsonb := jsonb_build_object(
    'name', 'Name', 'preferred_name', 'Preferred name', 'phone', 'Phone',
    'gender', 'Gender', 'date_of_birth', 'Date of birth', 'national_id', 'National ID',
    'personal_email', 'Personal email', 'school_email', 'School email',
    'position', 'Position', 'department', 'Department', 'employment_type', 'Employment type',
    'start_date', 'Start date', 'probation_end_date', 'Probation end date',
    'contract_end_date', 'Contract end date', 'ssnit_number', 'SSNIT number',
    'tin_number', 'TIN number', 'church_denomination', 'Church denomination',
    'emergency_contact_name', 'Emergency contact name',
    'emergency_contact_phone', 'Emergency contact phone',
    'residential_address', 'Residential address', 'basic_salary', 'Basic salary',
    'payment_method', 'Payment method', 'bank', 'Bank or network',
    'account_no', 'Account or wallet number', 'effective_from', 'Effective from',
    'pays_ssnit', 'Pays SSNIT', 'pays_tier2', 'Pays Tier 2', 'pays_paye', 'Pays PAYE');
  -- The template's example row name: must match EXAMPLE.name in
  -- frontend/src/components/employees/import-employees-dialog.tsx (upper
  -- case, spaces collapsed). Uploaded unchanged, the row is refused.
  c_example_name constant text := 'EXAMPLE EMPLOYEE - DELETE THIS ROW';
  c_pay_keys constant text[] := array[
    'payment_method', 'bank', 'account_no', 'effective_from', 'pays_ssnit', 'pays_tier2', 'pays_paye'];

  v_out jsonb := '[]'::jsonb;
  v_seen jsonb := '{}'::jsonb;   -- "<kind>:<normalised value>" -> first row number
  v_item jsonb;
  v_cells jsonb;
  v_cell jsonb;
  v_t jsonb;                     -- trimmed text per key
  v_vals jsonb;                  -- typed values for import_employees()
  v_errors text[];
  v_notes text[];
  v_row integer;
  v_i integer := 0;
  v_k text;
  v_txt text;
  v_label text;
  v_money record;
  v_date record;
  v_dates jsonb;
  v_flag boolean;
  v_match text;
  v_method text;
  v_has_pay boolean;
  v_norm text;
  v_key text;
  v_phone9 text;
  v_max integer;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'The import file could not be read';
  end if;
  if jsonb_array_length(p_rows) > 200 then
    raise exception 'This file has more than 200 employees. Split it into smaller files and import each one.';
  end if;
  if pg_column_size(p_rows) > 512 * 1024 then
    raise exception 'This file is too large to import. Split it into smaller files and import each one.';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1;
    v_row := case when jsonb_typeof(v_item -> 'row') = 'number'
                  then (v_item ->> 'row')::numeric::integer else v_i + 1 end;
    v_cells := case when jsonb_typeof(v_item -> 'cells') = 'object'
                    then v_item -> 'cells' else '{}'::jsonb end;
    v_errors := '{}';
    v_notes := '{}';
    v_t := '{}'::jsonb;
    v_vals := '{}'::jsonb;
    v_dates := '{}'::jsonb;

    -- Every cell is text (or empty).
    foreach v_k in array c_keys loop
      v_cell := v_cells -> v_k;
      continue when v_cell is null or jsonb_typeof(v_cell) = 'null';
      if jsonb_typeof(v_cell) in ('object', 'array') then
        v_errors := v_errors || ((c_labels ->> v_k) || ' could not be read');
        continue;
      end if;
      v_txt := nullif(trim(v_cell #>> '{}'), '');
      if v_txt is not null then
        v_t := v_t || jsonb_build_object(v_k, v_txt);
      end if;
    end loop;

    -- Name, and the unedited template example.
    v_txt := v_t ->> 'name';
    if v_txt is null then
      v_errors := v_errors || 'Name is required'::text;
    elsif upper(regexp_replace(v_txt, '\s+', ' ', 'g')) = c_example_name then
      v_out := v_out || jsonb_build_object('row', v_row,
        'errors', jsonb_build_array('Delete the example row before uploading'),
        'notes', '[]'::jsonb, 'values', '{}'::jsonb);
      continue;
    elsif length(v_txt) > 80 then
      v_errors := v_errors || 'Name is too long (80 characters at most)'::text;
    end if;

    -- Lengths.
    foreach v_k in array c_keys loop
      v_txt := v_t ->> v_k;
      continue when v_txt is null or v_k = 'name';
      v_max := case
        when v_k = 'residential_address' then 500
        when v_k in ('phone', 'emergency_contact_phone', 'account_no') then 40
        else 200 end;
      if length(v_txt) > v_max then
        v_errors := v_errors || ((c_labels ->> v_k) || ' is too long');
      end if;
    end loop;

    -- Dates.
    foreach v_k in array array['date_of_birth', 'start_date', 'probation_end_date',
                               'contract_end_date', 'effective_from'] loop
      v_txt := v_t ->> v_k;
      continue when v_txt is null;
      select * into v_date from public._employee_import_date(v_txt);
      if v_date.problem is not null then
        v_errors := v_errors || ((c_labels ->> v_k) || ' ' || v_date.problem);
      else
        v_dates := v_dates || jsonb_build_object(v_k, v_date.value);
      end if;
    end loop;
    if (v_dates ->> 'date_of_birth')::date >= current_date then
      v_errors := v_errors || 'Date of birth must be in the past'::text;
    end if;
    if (v_dates ->> 'probation_end_date')::date < (v_dates ->> 'start_date')::date then
      v_errors := v_errors || 'Probation end date is before the start date'::text;
    end if;
    if (v_dates ->> 'contract_end_date')::date < (v_dates ->> 'start_date')::date then
      v_errors := v_errors || 'Contract end date is before the start date'::text;
    end if;

    -- Emails.
    foreach v_k in array array['personal_email', 'school_email'] loop
      v_txt := v_t ->> v_k;
      if v_txt is not null and v_txt !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        v_errors := v_errors || ((c_labels ->> v_k) || ' is not an email address');
      end if;
    end loop;

    -- Lists: employment type, position, department (as the manual pickers).
    if v_t ? 'employment_type' then
      select t into v_match
      from unnest(array['Full-Time', 'Part-Time', 'Contract', 'Volunteer', 'Intern']) t
      where lower(t) = lower(v_t ->> 'employment_type');
      if v_match is null then
        v_errors := v_errors || 'Employment type must be Full-Time, Part-Time, Contract, Volunteer or Intern'::text;
      else
        v_vals := v_vals || jsonb_build_object('employment_type', v_match);
      end if;
    end if;
    if v_t ? 'position' then
      select name into v_match from public.positions
      where is_active and upper(trim(name)) = upper(v_t ->> 'position') limit 1;
      if v_match is null then
        v_errors := v_errors || 'Position is not in the list of positions'::text;
      else
        v_vals := v_vals || jsonb_build_object('position', v_match);
      end if;
    end if;
    if v_t ? 'department' then
      select name into v_match from public.departments
      where is_active and upper(trim(name)) = upper(v_t ->> 'department') limit 1;
      if v_match is null then
        v_errors := v_errors || 'Department is not in the list of departments'::text;
      else
        v_vals := v_vals || jsonb_build_object('department', v_match);
      end if;
    end if;

    -- Pay: all-or-none with the basic salary.
    v_has_pay := v_t ? 'basic_salary';
    if not v_has_pay then
      if exists (select 1 from unnest(c_pay_keys) k where v_t ? k) then
        v_errors := v_errors || 'Basic salary is required when pay details are given'::text;
      end if;
    else
      select * into v_money from public._employee_import_money(v_t ->> 'basic_salary');
      if v_money.problem is not null then
        v_errors := v_errors || ('Basic salary ' || v_money.problem);
      else
        v_vals := v_vals || jsonb_build_object('basic_salary', v_money.amount);
      end if;

      v_method := case
        when not v_t ? 'payment_method' then 'Bank'
        when lower(v_t ->> 'payment_method') = 'bank' then 'Bank'
        when lower(v_t ->> 'payment_method') = 'mobile money' then 'Mobile Money'
      end;
      if v_method is null then
        v_errors := v_errors || 'Payment method must be Bank or Mobile Money'::text;
      else
        v_vals := v_vals || jsonb_build_object('payment_method', v_method);
        if v_t ? 'bank' then
          select name into v_match from public.payment_providers
          where is_active and kind = v_method and lower(name) = lower(v_t ->> 'bank') limit 1;
          if v_match is null then
            v_errors := v_errors || (case when v_method = 'Bank'
              then 'Bank or network is not in the list of banks'
              else 'Bank or network is not in the list of mobile money networks' end);
          else
            v_vals := v_vals || jsonb_build_object('bank', v_match);
          end if;
        end if;
      end if;

      -- Blank = Yes (manual entry's default), with a warning; anything
      -- other than Yes/No is an error.
      foreach v_k in array array['pays_ssnit', 'pays_tier2', 'pays_paye'] loop
        if not v_t ? v_k then
          v_notes := v_notes || (case v_k
            when 'pays_ssnit' then 'SSNIT flag blank, will be treated as Yes'
            when 'pays_tier2' then 'Tier 2 flag blank, will be treated as Yes'
            else 'PAYE flag blank, will be treated as Yes' end);
          v_vals := v_vals || jsonb_build_object(v_k, true);
          continue;
        end if;
        v_flag := public._employee_import_yes_no(v_t ->> v_k);
        if v_flag is null then
          v_errors := v_errors || ((c_labels ->> v_k) || ' must be Yes or No');
        else
          v_vals := v_vals || jsonb_build_object(v_k, v_flag);
        end if;
      end loop;
    end if;

    -- Duplicates: identifiers and name refuse; phone only warns. Compared
    -- after the same normalisation the employees_uppercase trigger applies.
    -- Messages never show the matching value or the other person's name.
    foreach v_k in array array['national_id', 'ssnit_number', 'tin_number', 'school_email'] loop
      v_txt := v_t ->> v_k;
      continue when v_txt is null;
      v_norm := case when v_k = 'school_email' then lower(v_txt) else upper(v_txt) end;
      v_label := c_labels ->> v_k;
      v_key := v_k || ':' || v_norm;
      if exists (
        select 1 from public.employees e
        where e.employment_status <> 'Rejected'
          and case v_k
                when 'national_id' then e.national_id
                when 'ssnit_number' then e.ssnit_number
                when 'tin_number' then e.tin_number
                else e.school_email
              end = v_norm
      ) then
        v_errors := v_errors || ('An employee with this ' || v_label || ' already exists');
      elsif v_seen ? v_key then
        v_errors := v_errors || ('Same ' || v_label || ' as row ' || (v_seen ->> v_key));
      else
        v_seen := v_seen || jsonb_build_object(v_key, v_row);
      end if;
    end loop;

    v_txt := v_t ->> 'name';
    if v_txt is not null then
      v_norm := upper(regexp_replace(v_txt, '\s+', ' ', 'g'));
      v_key := 'name:' || v_norm;
      if exists (
        select 1 from public.employees e
        where e.employment_status <> 'Rejected'
          and upper(regexp_replace(trim(e.name), '\s+', ' ', 'g')) = v_norm
      ) then
        v_errors := v_errors || 'An employee with this name already exists. If this is a different person, add them by hand.'::text;
      elsif v_seen ? v_key then
        v_errors := v_errors || ('Same name as row ' || (v_seen ->> v_key) || '. If this is a different person, add them by hand.');
      else
        v_seen := v_seen || jsonb_build_object(v_key, v_row);
      end if;
    end if;

    v_phone9 := right(regexp_replace(coalesce(v_t ->> 'phone', ''), '[^0-9]', '', 'g'), 9);
    if length(v_phone9) = 9 then
      v_key := 'phone:' || v_phone9;
      if exists (
        select 1 from public.employees e
        where e.employment_status <> 'Rejected'
          and right(regexp_replace(coalesce(e.phone, ''), '[^0-9]', '', 'g'), 9) = v_phone9
      ) then
        v_notes := v_notes || 'Phone number matches an existing employee: check this isn''t the same person'::text;
      elsif v_seen ? v_key then
        v_notes := v_notes || ('Same phone number as row ' || (v_seen ->> v_key));
      else
        v_seen := v_seen || jsonb_build_object(v_key, v_row);
      end if;
    end if;

    -- Plain text values, as typed (the employees_uppercase trigger
    -- normalises case when the row is saved, as for manual entry).
    foreach v_k in array array['name', 'preferred_name', 'phone', 'gender', 'national_id',
      'personal_email', 'school_email', 'ssnit_number', 'tin_number', 'church_denomination',
      'emergency_contact_name', 'emergency_contact_phone', 'residential_address', 'account_no'] loop
      if v_t ? v_k then
        v_vals := v_vals || jsonb_build_object(v_k, v_t ->> v_k);
      end if;
    end loop;
    v_vals := v_vals || v_dates;

    v_out := v_out || jsonb_build_object('row', v_row, 'errors', to_jsonb(v_errors),
      'notes', to_jsonb(v_notes), 'values', v_vals);
  end loop;

  return v_out;
end;
$$;

-- ============================================================ 4. public functions

-- Checks the file and returns one {row, errors, notes} per row, in order.
-- Saves nothing.
create function public.preview_employee_import(p_rows jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_checked jsonb;
begin
  perform public.require_finance_writer();
  v_checked := public._employee_import_check(p_rows);
  return coalesce((
    select jsonb_agg(r - 'values' order by ord)
    from jsonb_array_elements(v_checked) with ordinality as t(r, ord)
  ), '[]'::jsonb);
end;
$$;

-- Checks the whole file again and creates every row through the manual
-- path, or refuses with nothing saved. Returns {created, with_pay_config}.
create function public.import_employees(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_checked jsonb;
  v_r jsonb;
  v_v jsonb;
  v_bad integer;
  v_main uuid;
  v_emp public.employees;
  v_created integer := 0;
  v_with_pay integer := 0;
  v_row integer;
begin
  perform public.require_finance_writer();
  -- Two imports run one after the other, so their duplicate checks can't
  -- both miss each other's rows.
  perform pg_advisory_xact_lock(hashtext('public.import_employees'));

  v_checked := public._employee_import_check(p_rows);
  if jsonb_array_length(v_checked) = 0 then
    raise exception 'There are no employees in this file';
  end if;
  select count(*) into v_bad
  from jsonb_array_elements(v_checked) r
  where jsonb_array_length(r -> 'errors') > 0;
  if v_bad > 0 then
    raise exception 'Import refused: % row(s) have problems. Nothing was saved.', v_bad;
  end if;

  select id into v_main from public.branches order by created_at limit 1;

  for v_r in select value from jsonb_array_elements(v_checked) loop
    v_row := (v_r ->> 'row')::integer;
    v_v := v_r -> 'values';
    begin
      v_emp := public.propose_employee(
        p_name => v_v ->> 'name',
        p_branch_id => v_main,
        p_phone => v_v ->> 'phone',
        p_position => v_v ->> 'position',
        p_department => v_v ->> 'department',
        p_staff_id => null,
        p_basic_salary => (v_v ->> 'basic_salary')::numeric,
        p_bank => v_v ->> 'bank',
        p_account_no => v_v ->> 'account_no',
        p_pays_ssnit => coalesce((v_v ->> 'pays_ssnit')::boolean, true),
        p_pays_tier2 => coalesce((v_v ->> 'pays_tier2')::boolean, true),
        p_pays_paye => coalesce((v_v ->> 'pays_paye')::boolean, true),
        p_effective_from => (v_v ->> 'effective_from')::date,
        p_payment_method => coalesce(v_v ->> 'payment_method', 'Bank')
      );
      perform public.update_employee_profile(
        p_employee_id => v_emp.id,
        p_phone => v_v ->> 'phone',
        p_position => v_v ->> 'position',
        p_department => v_v ->> 'department',
        p_date_of_birth => (v_v ->> 'date_of_birth')::date,
        p_gender => v_v ->> 'gender',
        p_national_id => v_v ->> 'national_id',
        p_personal_email => v_v ->> 'personal_email',
        p_school_email => v_v ->> 'school_email',
        p_employment_type => v_v ->> 'employment_type',
        p_start_date => (v_v ->> 'start_date')::date,
        p_probation_end_date => (v_v ->> 'probation_end_date')::date,
        p_contract_end_date => (v_v ->> 'contract_end_date')::date,
        p_emergency_contact_name => v_v ->> 'emergency_contact_name',
        p_emergency_contact_phone => v_v ->> 'emergency_contact_phone',
        p_residential_address => v_v ->> 'residential_address',
        p_qualifications => null,
        p_ssnit_number => v_v ->> 'ssnit_number',
        p_tin_number => v_v ->> 'tin_number',
        p_church_denomination => v_v ->> 'church_denomination',
        p_preferred_name => v_v ->> 'preferred_name'
      );
    exception when others then
      -- Never pass the underlying message on: it can contain a value from
      -- the file (e.g. the 2 dp trigger's "(got X)").
      raise exception 'Row % could not be saved. Nothing was saved.', v_row;
    end;
    v_created := v_created + 1;
    if v_v ? 'basic_salary' then
      v_with_pay := v_with_pay + 1;
    end if;
  end loop;

  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (v_main, auth.uid(), 'employees_imported', 'employees', gen_random_uuid()::text, null,
          jsonb_build_object('rows', v_created, 'created', v_created, 'with_pay_config', v_with_pay));

  return jsonb_build_object('created', v_created, 'with_pay_config', v_with_pay);
end;
$$;

-- ============================================================ 5. grants

-- Postgres grants EXECUTE to PUBLIC by default and Supabase adds anon, so
-- every new function is revoked explicitly. The helpers get no grant.
revoke execute on function public._employee_import_money(text) from public, anon, authenticated;
revoke execute on function public._employee_import_date(text) from public, anon, authenticated;
revoke execute on function public._employee_import_yes_no(text) from public, anon, authenticated;
revoke execute on function public._employee_import_check(jsonb) from public, anon, authenticated;

revoke execute on function public.preview_employee_import(jsonb) from public, anon;
revoke execute on function public.import_employees(jsonb) from public, anon;
grant execute on function public.preview_employee_import(jsonb) to authenticated, service_role;
grant execute on function public.import_employees(jsonb) to authenticated, service_role;
