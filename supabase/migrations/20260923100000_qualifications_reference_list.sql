-- Qualifications: free text -> a school-editable reference list
-- (same "promote free-text to a curated list" pattern as
-- positions/departments/payment_providers/allowance_types), picked as a
-- multi-select rather than one value — a person can hold several.
--
-- employees.qualifications / employee_onboarding_submissions.qualifications
-- both become text[] (matches the position/department convention: the
-- list constrains the picker, it isn't an FK — a stored value not in the
-- active list still round-trips). Existing free-text values are wrapped
-- into a single-element array rather than discarded, so nothing already
-- typed is lost; they'll show as "(not in list)" in the new picker until
-- someone reconciles them.

create table public.qualifications (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  position integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index qualifications_position_idx on public.qualifications (position);

alter table public.qualifications enable row level security;

create policy qualifications_select on public.qualifications
for select using (public.has_role(array['Manager', 'Accountant', 'Auditor']));
create policy qualifications_insert on public.qualifications
for insert with check (public.has_role(array['Manager', 'Accountant']));
create policy qualifications_update on public.qualifications
for update using (public.has_role(array['Manager', 'Accountant']))
with check (public.has_role(array['Manager', 'Accountant']));
create policy qualifications_delete on public.qualifications
for delete using (public.has_role(array['Manager', 'Accountant']));

-- The public onboarding form (anon, no session) needs to offer the
-- active list too — this is the one reference list anon reads, but
-- unlike the tables in the tokenized-form security note, there's nothing
-- sensitive here to narrow behind a function: it's a fixed list of
-- qualification names, same trust level as a static page.
create policy qualifications_select_anon on public.qualifications
for select to anon using (is_active);

grant select, insert, update, delete on public.qualifications to authenticated;
grant select on public.qualifications to anon;
grant select, insert, update, delete on public.qualifications to service_role;

insert into public.qualifications (name, position) values
  ('WASSCE / SSSCE', 0),
  ('Diploma', 1),
  ('HND', 2),
  ('Bachelor''s Degree', 3),
  ('Postgraduate Diploma in Education (PGDE)', 4),
  ('Master''s Degree', 5),
  ('Doctorate (PhD)', 6),
  ('NTC Teaching License', 7),
  ('Early Childhood Education Certificate', 8),
  ('Montessori Certificate', 9),
  ('First Aid / CPR Certificate', 10),
  ('Food Handler''s Certificate', 11),
  ('Commercial Driving License', 12),
  ('Professional Accounting Certificate (ICA/ACCA)', 13),
  ('Security Certification', 14)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- Column type changes: text -> text[]. Existing values wrapped, not lost.
-- ---------------------------------------------------------------------
alter table public.employees
  alter column qualifications type text[]
  using case when qualifications is null then null else array[qualifications] end;

alter table public.employee_onboarding_submissions
  alter column qualifications type text[]
  using case when qualifications is null then null else array[qualifications] end;

-- update_employee_profile(): p_qualifications text -> text[]. Argument
-- type change -> drop before recreate.
drop function if exists public.update_employee_profile(
  uuid, text, text, text, date, text, text, text, text, text, date, date, date,
  text, text, text, text, text, text, text, text
);

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

grant execute on function public.update_employee_profile(
  uuid, text, text, text, date, text, text, text, text, text, date, date, date,
  text, text, text, text[], text, text, text, text
) to authenticated, service_role;

-- submit_onboarding_form(): p_qualifications text -> text[]. Argument
-- type change -> drop before recreate.
drop function if exists public.submit_onboarding_form(
  text, date, text, text, text, text, text, text, text, text, text, text, boolean, text, jsonb
);

create or replace function public.submit_onboarding_form(
  p_token text,
  p_date_of_birth date default null,
  p_gender text default null,
  p_national_id text default null,
  p_personal_email text default null,
  p_emergency_contact_name text default null,
  p_emergency_contact_phone text default null,
  p_residential_address text default null,
  p_qualifications text[] default null,
  p_bank_name text default null,
  p_account_no text default null,
  p_payment_method text default null,
  p_contract_accepted boolean default false,
  p_signature_name text default null,
  p_uploaded_documents jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token_hash text := encode(digest(p_token, 'sha256'), 'hex');
  v_token_id uuid;
  v_employee_id uuid;
  v_submission_id uuid;
begin
  select id, employee_id into v_token_id, v_employee_id
  from public.employee_onboarding_tokens
  where token_hash = v_token_hash and expires_at > now() and used_at is null
  for update;

  if v_token_id is null then
    raise exception 'This onboarding link is invalid, expired, or already used.';
  end if;

  if not p_contract_accepted or coalesce(trim(p_signature_name), '') = '' then
    raise exception 'Contract acceptance and a typed signature are required.';
  end if;

  update public.employee_onboarding_tokens
  set used_at = now()
  where id = v_token_id and used_at is null;

  insert into public.employee_onboarding_submissions (
    employee_id, token_id, date_of_birth, gender, national_id, personal_email,
    emergency_contact_name, emergency_contact_phone, residential_address, qualifications,
    bank_name, account_no, payment_method, contract_accepted, signature_name, uploaded_documents
  ) values (
    v_employee_id, v_token_id, p_date_of_birth, nullif(trim(p_gender), ''),
    nullif(trim(p_national_id), ''), nullif(trim(p_personal_email), ''),
    nullif(trim(p_emergency_contact_name), ''), nullif(trim(p_emergency_contact_phone), ''),
    nullif(trim(p_residential_address), ''), p_qualifications,
    nullif(trim(p_bank_name), ''), nullif(trim(p_account_no), ''), nullif(p_payment_method, ''),
    p_contract_accepted, trim(p_signature_name), coalesce(p_uploaded_documents, '[]'::jsonb)
  ) returning id into v_submission_id;

  return v_submission_id;
end;
$$;

grant execute on function public.submit_onboarding_form(
  text, date, text, text, text, text, text, text, text[], text, text, text, boolean, text, jsonb
) to anon, authenticated, service_role;
