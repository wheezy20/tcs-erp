-- "National Service" as an employment type (an HR label only).
--
-- Approved by Eyram, 2026-10-08:
--   1. employees.employment_type's check constraint allows 'National Service'.
--   2. update_employee_profile(): only its list of allowed employment types
--      changes (same signature, grants kept).
--   3. _employee_import_check(): accepts the type, and adds a warning that
--      doesn't block when a National Service row with a salary would still
--      pay SSNIT, Tier 2 or PAYE (blank flags already count as Yes).
-- It is a label only: no payroll function reads employment_type, no pay
-- figure changes, and the SSNIT / Tier 2 / PAYE flags are never set from it;
-- they stay explicit, as on the manual form and in the import. Existing
-- employees keep their current type; nothing is rewritten.

-- ============================================================ 1. constraint

alter table public.employees drop constraint employees_employment_type_check;
alter table public.employees add constraint employees_employment_type_check
  check (employment_type in ('Full-Time', 'Part-Time', 'Contract', 'Volunteer', 'Intern',
                             'National Service'));

-- ============================================================ 2. update_employee_profile()

-- Copied from 20260923100000; only the allowed list and its message change.
create or replace function public.update_employee_profile(
  p_employee_id uuid,
  p_phone text,
  p_position text,
  p_department text,
  p_date_of_birth date default null,
  p_gender text default null,
  p_national_id text default null,
  p_personal_email text default null,
  p_school_email text default null,
  p_employment_type text default null,
  p_start_date date default null,
  p_probation_end_date date default null,
  p_contract_end_date date default null,
  p_emergency_contact_name text default null,
  p_emergency_contact_phone text default null,
  p_residential_address text default null,
  p_qualifications text[] default null,
  p_ssnit_number text default null,
  p_tin_number text default null,
  p_church_denomination text default null,
  p_preferred_name text default null
)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp public.employees;
begin
  perform public.require_finance_writer();

  select * into v_emp from public.employees where id = p_employee_id for update;
  if not found then
    raise exception 'Employee % not found', p_employee_id;
  end if;
  if v_emp.employment_status = 'Rejected' then
    raise exception 'Cannot edit a rejected employee record';
  end if;
  if p_employment_type is not null
     and p_employment_type not in ('Full-Time', 'Part-Time', 'Contract', 'Volunteer', 'Intern',
                                   'National Service') then
    raise exception 'Employment type must be Full-Time, Part-Time, Contract, Volunteer, Intern or National Service';
  end if;

  update public.employees
  set phone = nullif(trim(p_phone), ''),
      position = nullif(trim(p_position), ''),
      department = nullif(trim(p_department), ''),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      national_id = case when p_national_id is not null
                         then nullif(trim(p_national_id), '') else national_id end,
      personal_email = case when p_personal_email is not null
                            then nullif(trim(p_personal_email), '') else personal_email end,
      school_email = case when p_school_email is not null
                          then nullif(trim(p_school_email), '') else school_email end,
      employment_type = coalesce(p_employment_type, employment_type),
      start_date = coalesce(p_start_date, start_date),
      probation_end_date = coalesce(p_probation_end_date, probation_end_date),
      contract_end_date = coalesce(p_contract_end_date, contract_end_date),
      emergency_contact_name = case when p_emergency_contact_name is not null
                                    then nullif(trim(p_emergency_contact_name), '')
                                    else emergency_contact_name end,
      emergency_contact_phone = case when p_emergency_contact_phone is not null
                                     then nullif(trim(p_emergency_contact_phone), '')
                                     else emergency_contact_phone end,
      residential_address = case when p_residential_address is not null
                                 then nullif(trim(p_residential_address), '')
                                 else residential_address end,
      -- Array replaces wholesale (null = unchanged, '{}' = explicitly
      -- clear) — same amend-in-place idiom as every other field here,
      -- just without the text-specific nullif/trim dance.
      qualifications = coalesce(p_qualifications, qualifications),
      ssnit_number = case when p_ssnit_number is not null
                          then nullif(trim(p_ssnit_number), '') else ssnit_number end,
      tin_number = case when p_tin_number is not null
                        then nullif(trim(p_tin_number), '') else tin_number end,
      church_denomination = case when p_church_denomination is not null
                                 then nullif(trim(p_church_denomination), '')
                                 else church_denomination end,
      preferred_name = case when p_preferred_name is not null
                            then nullif(trim(p_preferred_name), '') else preferred_name end
  where id = p_employee_id
  returning * into v_emp;

  return v_emp;
end;
$$;

-- ============================================================ 3. _employee_import_check()

-- Copied from 20261009100000; only the employment-type list, its message and
-- the National Service reminder change. No grant: it stays callable only by
-- preview_employee_import() and import_employees().
create or replace function public._employee_import_check(p_rows jsonb)
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
      from unnest(array['Full-Time', 'Part-Time', 'Contract', 'Volunteer', 'Intern',
                        'National Service']) t
      where lower(t) = lower(v_t ->> 'employment_type');
      if v_match is null then
        v_errors := v_errors || 'Employment type must be Full-Time, Part-Time, Contract, Volunteer, Intern or National Service'::text;
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

    -- National Service is an HR label only: the flags stay exactly as
    -- given (a blank one already counts as Yes above). A reminder, never a
    -- block, when such a row would still pay any of them.
    if v_vals ->> 'employment_type' = 'National Service' and v_has_pay
       and (coalesce((v_vals ->> 'pays_ssnit')::boolean, false)
            or coalesce((v_vals ->> 'pays_tier2')::boolean, false)
            or coalesce((v_vals ->> 'pays_paye')::boolean, false)) then
      v_notes := v_notes || 'National Service staff are normally exempt: check the SSNIT, Tier 2 and PAYE flags'::text;
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
