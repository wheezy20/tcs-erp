-- HR record enrichment, Phase 1 of the HR-beyond-payroll build (TCS ERP).
-- Informed by TCS's existing Google Apps Script HR system (03 STAFF
-- DATABASE tab) — field names and the dropdown-enum values below are
-- taken directly from that live spreadsheet, not guessed. Its security
-- model (public Google Form, no RLS) is not being copied; every write
-- here still goes through the existing SECURITY DEFINER RPC pattern.
--
-- Every field below is a "current-state identity fact" exactly like the
-- existing phone/position/department: a single mutable value, no
-- approval gate, no effective-dating — that pattern stays reserved for
-- things whose *history* matters (pay, exemptions), which none of these
-- are. Two things already live elsewhere and are deliberately NOT
-- duplicated here:
--   * Bank name/account number and salary — already on
--     employee_pay_config (approval-gated, effective-dated). The source
--     spreadsheet flattens these into the same row as everything else;
--     this schema does not copy that flattening.
--   * "Staff Status" (Probationary/Confirmed/On Leave/Resigned/
--     Terminated/Retired) — the source sheet's own status dropdown,
--     deliberately not ported. It would collide with the existing
--     employment_status (Pending Approval/Active/Suspended/Rejected),
--     which already gates payroll eligibility. "Probationary" vs
--     "Confirmed" is derived from probation_end_date vs today instead of
--     a second status a person has to remember to flip — this repo's own
--     computed-never-stored convention, applied somewhere the source
--     system didn't have it. "On Leave"/"Resigned"/"Terminated"/
--     "Retired" overlap with the explicitly-deferred Leave and Exit &
--     Offboarding domains (docs/CONSTRAINTS.md) — not solved here.
--
-- "Handbook Issued?" appears in the source system's staff table AND its
-- onboarding checklist. Treated as one thing, and it belongs to
-- onboarding (a dated event with a "who confirmed it"), not repeated
-- here as a second, disconnected boolean — see the onboarding migration
-- for that.
alter table public.employees
  add column date_of_birth date,
  add column gender text,
  add column national_id text,
  add column personal_email text,
  add column school_email text,
  -- Matches the live PROPOSITION_TYPES dropdown in the source system
  -- exactly (its own user manual says "Full-Time, Part-Time, Fixed-Term,
  -- etc." but the actual seeded dropdown values are these five —
  -- confirmed directly against the spreadsheet, not the manual's prose).
  add column employment_type text
    check (employment_type in ('Full-Time', 'Part-Time', 'Contract', 'Volunteer', 'Intern')),
  add column start_date date,
  add column probation_end_date date,
  -- A plain HR-entered fact, not derived from employee_contracts —
  -- Phase 4 (contract generation) reads this when building a contract,
  -- it does not own or overwrite it.
  add column contract_end_date date,
  add column emergency_contact_name text,
  add column emergency_contact_phone text,
  add column residential_address text,
  add column qualifications text,
  add column ssnit_number text,
  add column tin_number text,
  add column church_denomination text,
  -- In the live sheet, not in the original enumerated field list — cheap
  -- enough to include for parity with the actual source of truth.
  add column preferred_name text;

-- ---------------------------------------------------------------------
-- Uppercase normalization extended to every new name-like or ID-like
-- field, same reasoning as the existing name/position/department
-- treatment (Ghanaian HR record-keeping convention; prevents
-- "Ama"/"AMA"/"ama" silently being treated as different values).
-- personal_email/school_email go the other direction — lowercased, the
-- actual convention for email addresses, not uppercased.
-- residential_address/qualifications are left as-typed: genuine free
-- text with no canonical casing.
-- ---------------------------------------------------------------------
create or replace function public.uppercase_employee_fields()
returns trigger language plpgsql as $$
begin
  new.name := upper(nullif(trim(new.name), ''));
  new.position := upper(nullif(trim(new.position), ''));
  new.department := upper(nullif(trim(new.department), ''));
  new.preferred_name := upper(nullif(trim(new.preferred_name), ''));
  new.national_id := upper(nullif(trim(new.national_id), ''));
  new.ssnit_number := upper(nullif(trim(new.ssnit_number), ''));
  new.tin_number := upper(nullif(trim(new.tin_number), ''));
  new.church_denomination := upper(nullif(trim(new.church_denomination), ''));
  new.emergency_contact_name := upper(nullif(trim(new.emergency_contact_name), ''));
  new.personal_email := lower(nullif(trim(new.personal_email), ''));
  new.school_email := lower(nullif(trim(new.school_email), ''));
  return new;
end;
$$;

-- Normalize any rows that already exist (a real deployment); harmless
-- no-op on a fresh local reset where the table is empty at this point.
update public.employees
set preferred_name = upper(nullif(trim(preferred_name), '')),
    national_id = upper(nullif(trim(national_id), '')),
    ssnit_number = upper(nullif(trim(ssnit_number), '')),
    tin_number = upper(nullif(trim(tin_number), '')),
    church_denomination = upper(nullif(trim(church_denomination), '')),
    emergency_contact_name = upper(nullif(trim(emergency_contact_name), '')),
    personal_email = lower(nullif(trim(personal_email), '')),
    school_email = lower(nullif(trim(school_email), ''));

-- ---------------------------------------------------------------------
-- update_employee_profile(): the existing phone/position/department
-- params keep their exact current behaviour (always sent, always set,
-- unchanged) — the new params are added as trailing, default-null
-- ("leave unchanged" / "explicitly send even an empty string to clear
-- it") optional fields, same amend-in-place idiom as
-- approve_pay_config()'s override params (20260918). This lets the
-- frontend save a new "HR Details" section independently from the
-- existing Contact & Placement form without changing that form's
-- behaviour at all. Drop + recreate: an argument-list change.
-- ---------------------------------------------------------------------
drop function if exists public.update_employee_profile(uuid, text, text, text);

create function public.update_employee_profile(
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
  p_qualifications text default null,
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
     and p_employment_type not in ('Full-Time', 'Part-Time', 'Contract', 'Volunteer', 'Intern') then
    raise exception 'Employment type must be Full-Time, Part-Time, Contract, Volunteer or Intern';
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
      qualifications = case when p_qualifications is not null
                            then nullif(trim(p_qualifications), '') else qualifications end,
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

grant execute on function public.update_employee_profile(
  uuid, text, text, text, date, text, text, text, text, text, date, date, date,
  text, text, text, text, text, text, text, text
) to authenticated;
grant execute on function public.update_employee_profile(
  uuid, text, text, text, date, text, text, text, text, text, date, date, date,
  text, text, text, text, text, text, text, text
) to service_role;
