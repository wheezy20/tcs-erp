-- Admissions slice 8b: public enquiry form polish
-- (docs/admissions/PORT-PLAN.md, slice 8b; plan and decisions approved
-- 2026-10-14, anon surface gate approved for the label string and the new
-- applications_open key only).
--
-- 1. Public campus labels. branches.public_label (nullable) is what the
--    public form shows; branches.name, used by HR, Finance and staff
--    admissions screens, is unchanged. Labels are seeded here by name:
--    "Main" (local) or "Treasures Christian School" (hosted) gets
--    "Main Campus (Somey Down)", and "Annex" gets "Annex (CK Road)". A
--    signed-in user can't set or change a label (branches has a broad
--    can_write() update policy, and the label is public), so only
--    migrations set it.
-- 2. Current grade or class becomes a choice. students.current_grade_id (an
--    active admissions grade) or students.prior_schooling
--    ('not_yet_in_school', the only value), never both. A child at a creche
--    or daycare picks Pre Nursery. The old free
--    text students.current_grade stays for legacy rows and is written empty
--    by public enquiries.
-- 3. submit_inquiry, same signature, now also:
--    - takes current_grade_id or prior_schooling (the old current_grade key
--      is refused as unknown); exactly one is required;
--    - refuses a current school with not_yet_in_school (the form hides the
--      field), and requires it for any grade;
--    - takes religion only from Christian, Muslim, Traditional, Other,
--      Prefer not to say;
--    - takes month_of_enrollment only as January or September;
--    - says "enquiry" in messages a parent can see;
--    - names the offending field in the error DETAIL (for example
--      guardians.0.phone), so the form can show the message next to it.
--    It still refuses only when public_intake_open (public inquiries) is
--    false; public_applications_open plays no part here.
-- 4. get_public_admissions_options, same signature and still the one slice 8
--    anon function (count stays 170): campus name is the public label when
--    set, and a new applications_open key reports the applications switch.
--    Nothing else changes.

-- ------------------------------------------------------------ 1. campus labels

alter table public.branches
  add column public_label text
    check (public_label is null or (btrim(public_label) <> '' and char_length(public_label) <= 60));

create or replace function public.guard_branch_public_label()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null
     and ((tg_op = 'INSERT' and new.public_label is not null)
          or (tg_op = 'UPDATE' and new.public_label is distinct from old.public_label)) then
    raise exception 'A campus public label is set by a migration, not from the app';
  end if;
  return new;
end;
$$;

create trigger branches_guard_public_label
  before insert or update on public.branches
  for each row execute function public.guard_branch_public_label();

-- Labels by name, so it works whether the main campus is called "Main"
-- (local seed) or "Treasures Christian School" (hosted). Returns how many
-- campuses it labelled. Called once below; probes call it again after
-- renaming a campus.
create or replace function public._admissions_seed_public_campus_labels()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_main integer;
  v_annex integer;
begin
  update public.branches set public_label = 'Main Campus (Somey Down)'
  where name in ('Main', 'Treasures Christian School');
  get diagnostics v_main = row_count;
  update public.branches set public_label = 'Annex (CK Road)'
  where name = 'Annex';
  get diagnostics v_annex = row_count;
  return v_main + v_annex;
end;
$$;

select public._admissions_seed_public_campus_labels();

-- ------------------------------------------------------------ 2. current grade

alter table public.students
  add column current_grade_id uuid references public.admissions_grades (id) on delete restrict,
  add column prior_schooling text
    check (prior_schooling in ('not_yet_in_school')),
  add constraint students_current_grade_one_check
    check (not (current_grade_id is not null and prior_schooling is not null));

create index students_current_grade_id_idx on public.students (current_grade_id);

-- ------------------------------------------------------------ 3. helpers with a field

-- The slice 8 helpers gain a field argument (drop before changing an
-- argument list). submit_inquiry is replaced below in the same migration.
drop function public._public_invalid(text);
drop function public._public_only_keys(jsonb, text[], text);
drop function public._public_text(jsonb, text, text, integer, boolean);

-- TCS22 with the message for the parent and the payload path of the field
-- in DETAIL. The Edge Function passes the path through only when it has
-- the expected shape.
create or replace function public._public_invalid(p_message text, p_field text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'TCS22', message = p_message, detail = coalesce(p_field, '');
end;
$$;

create or replace function public._public_only_keys(
  p_obj jsonb, p_allowed text[], p_what text, p_field text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_extra text;
begin
  select k into v_extra from jsonb_object_keys(p_obj) k where k <> all (p_allowed) limit 1;
  if v_extra is not null then
    perform public._public_invalid(p_what || ' has a field the form does not send', p_field);
  end if;
end;
$$;

create or replace function public._public_text(
  p_obj jsonb, p_key text, p_label text, p_max integer, p_required boolean, p_field text
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_type text := jsonb_typeof(p_obj -> p_key);
  v_text text;
begin
  if v_type is null or v_type = 'null' then
    v_text := '';
  elsif v_type <> 'string' then
    perform public._public_invalid(p_label || ' must be text', p_field);
  else
    v_text := btrim(p_obj ->> p_key);
  end if;
  if char_length(v_text) > p_max then
    perform public._public_invalid(p_label || ' must be ' || p_max || ' characters or fewer', p_field);
  end if;
  if p_required and v_text = '' then
    perform public._public_invalid(p_label || ' is required', p_field);
  end if;
  return v_text;
end;
$$;

-- ------------------------------------------------------------ 3. submit_inquiry

create or replace function public.submit_inquiry(p_payload jsonb)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open boolean;
  v_referral text;
  v_referral_other text;
  v_comments text;
  v_guardians jsonb;
  v_students jsonb;
  v_g jsonb;
  v_s jsonb;
  v_label text;
  v_path text;
  v_i integer;
  v_phone text;
  v_email text;
  v_emails text[] := '{}';
  v_relationship text;
  v_religion text;
  v_dob_text text;
  v_dob date;
  v_grade_id uuid;
  v_grade_name text;
  v_current_grade_text text;
  v_current_grade_id uuid;
  v_prior text;
  v_school text;
  v_year text;
  v_month text;
  v_campus_id uuid;
  v_family_id uuid;
  v_student_id uuid;
  v_ref text;
  v_refs text[] := '{}';
begin
  perform public._require_public_service_caller();

  -- Public inquiries only: the applications switch plays no part here.
  select public_intake_open into v_open from public.admissions_settings where id = 1 for share;
  if v_open is not true then
    raise exception using errcode = 'TCS03', message = 'Online enquiries are closed';
  end if;

  -- ---------------------------------------------------- shape
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    perform public._public_invalid('The enquiry must be a JSON object', null);
  end if;
  perform public._public_only_keys(
    p_payload, array['referral_source', 'referral_source_other', 'comments', 'guardians', 'students'],
    'The enquiry', null);

  v_referral := public._public_text(p_payload, 'referral_source', 'How you heard about us', 30, true, 'referral_source');
  if v_referral not in ('current_parent', 'former_parent', 'parent_referral', 'staff_referral',
                        'website', 'friend_colleague', 'social_media', 'other') then
    perform public._public_invalid('How you heard about us: choose one of the listed options', 'referral_source');
  end if;
  v_referral_other := public._public_text(
    p_payload, 'referral_source_other', 'How you heard about us (other)', 255, v_referral = 'other',
    'referral_source_other');
  if v_referral <> 'other' then
    v_referral_other := '';
  end if;
  v_comments := public._public_text(p_payload, 'comments', 'Comments', 10000, false, 'comments');

  v_guardians := p_payload -> 'guardians';
  if v_guardians is null or jsonb_typeof(v_guardians) <> 'array'
     or jsonb_array_length(v_guardians) not between 1 and 2 then
    perform public._public_invalid('Give one or two parents or guardians', 'guardians');
  end if;
  v_students := p_payload -> 'students';
  if v_students is null or jsonb_typeof(v_students) <> 'array'
     or jsonb_array_length(v_students) not between 1 and 5 then
    perform public._public_invalid('Give between one and five children', 'students');
  end if;

  -- ---------------------------------------------------- guardians
  for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
    v_g := v_guardians -> v_i;
    v_label := 'Parent or guardian ' || (v_i + 1);
    v_path := 'guardians.' || v_i || '.';
    if jsonb_typeof(v_g) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object', 'guardians.' || v_i);
    end if;
    perform public._public_only_keys(
      v_g, array['surname', 'first_name', 'relationship', 'religion', 'address', 'town_city', 'phone', 'email'],
      v_label, 'guardians.' || v_i);
    perform public._public_text(v_g, 'surname', v_label || ': surname', 255, true, v_path || 'surname');
    perform public._public_text(v_g, 'first_name', v_label || ': first name', 255, true, v_path || 'first_name');
    v_relationship := public._public_text(v_g, 'relationship', v_label || ': relationship', 20, true, v_path || 'relationship');
    if v_relationship not in ('mother', 'father', 'guardian', 'other') then
      perform public._public_invalid(v_label || ': choose a relationship from the list', v_path || 'relationship');
    end if;
    v_religion := public._public_text(v_g, 'religion', v_label || ': religion', 30, true, v_path || 'religion');
    if v_religion not in ('Christian', 'Muslim', 'Traditional', 'Other', 'Prefer not to say') then
      perform public._public_invalid(v_label || ': choose a religion from the list', v_path || 'religion');
    end if;
    perform public._public_text(v_g, 'address', v_label || ': address', 255, true, v_path || 'address');
    perform public._public_text(v_g, 'town_city', v_label || ': town or city', 255, true, v_path || 'town_city');
    v_phone := regexp_replace(
      public._public_text(v_g, 'phone', v_label || ': phone', 32, true, v_path || 'phone'), '[[:space:]-]', '', 'g');
    if v_phone !~ '^\+[0-9]{8,15}$' then
      perform public._public_invalid(
        v_label || ': start with a plus sign and the country code, then 8 to 15 digits, for example +233 55 179 4822',
        v_path || 'phone');
    end if;
    v_email := lower(public._public_text(v_g, 'email', v_label || ': email', 254, true, v_path || 'email'));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      perform public._public_invalid(v_label || ': enter a valid email address', v_path || 'email');
    end if;
    if not v_email = any (v_emails) then
      v_emails := v_emails || v_email;
    end if;
  end loop;

  -- ---------------------------------------------------- students
  for v_i in 0 .. jsonb_array_length(v_students) - 1 loop
    v_s := v_students -> v_i;
    v_label := 'Child ' || (v_i + 1);
    v_path := 'students.' || v_i || '.';
    if jsonb_typeof(v_s) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object', 'students.' || v_i);
    end if;
    perform public._public_only_keys(
      v_s, array['full_name', 'date_of_birth', 'current_school', 'current_grade_id', 'prior_schooling',
                 'grade_id', 'academic_year', 'campus_id', 'month_of_enrollment'],
      v_label, 'students.' || v_i);
    perform public._public_text(v_s, 'full_name', v_label || ': full name', 255, true, v_path || 'full_name');

    v_dob_text := public._public_text(v_s, 'date_of_birth', v_label || ': date of birth', 10, true, v_path || 'date_of_birth');
    if v_dob_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
    end if;
    begin
      v_dob := v_dob_text::date;
    exception when others then
      perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
    end;
    if v_dob > (clock_timestamp() at time zone 'Africa/Accra')::date or v_dob < date '1900-01-01' then
      perform public._public_invalid(v_label || ': enter a valid date of birth', v_path || 'date_of_birth');
    end if;

    -- Current grade or class: an active grade id, or not yet in school.
    -- Exactly one.
    v_current_grade_text := public._public_text(
      v_s, 'current_grade_id', v_label || ': current grade or class', 36, false, v_path || 'current_grade_id');
    v_prior := public._public_text(
      v_s, 'prior_schooling', v_label || ': current grade or class', 30, false, v_path || 'current_grade_id');
    if v_current_grade_text <> '' and v_prior <> '' then
      perform public._public_invalid(v_label || ': choose one current grade or class', v_path || 'current_grade_id');
    end if;
    if v_current_grade_text = '' and v_prior = '' then
      perform public._public_invalid(v_label || ': current grade or class is required', v_path || 'current_grade_id');
    end if;
    if v_prior <> '' and v_prior <> 'not_yet_in_school' then
      perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
    end if;
    if v_current_grade_text <> '' then
      begin
        v_current_grade_id := v_current_grade_text::uuid;
      exception when invalid_text_representation then
        perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
      end;
      if not exists (select 1 from public.admissions_grades g where g.id = v_current_grade_id and g.is_active) then
        perform public._public_invalid(v_label || ': choose a current grade or class from the list', v_path || 'current_grade_id');
      end if;
    end if;

    -- Current school: none when not yet in school, required otherwise.
    v_school := public._public_text(
      v_s, 'current_school', v_label || ': current school', 255, v_prior <> 'not_yet_in_school', v_path || 'current_school');
    if v_prior = 'not_yet_in_school' and v_school <> '' then
      perform public._public_invalid(
        v_label || ': leave current school empty for a child not yet in school', v_path || 'current_school');
    end if;

    v_month := public._public_text(v_s, 'month_of_enrollment', v_label || ': month of enrolment', 20, true, v_path || 'month_of_enrollment');
    if v_month not in ('January', 'September') then
      perform public._public_invalid(v_label || ': choose a month of enrolment from the list', v_path || 'month_of_enrollment');
    end if;

    -- Grade applying into: an active grade id, nothing else.
    begin
      v_grade_id := public._public_text(v_s, 'grade_id', v_label || ': grade', 36, true, v_path || 'grade_id')::uuid;
    exception when invalid_text_representation then
      perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
    end;
    v_grade_name := null;
    select g.name into v_grade_name from public.admissions_grades g
    where g.id = v_grade_id and g.is_active;
    if v_grade_name is null then
      perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
    end if;

    -- Academic year: an active label, nothing else.
    v_year := public._public_text(v_s, 'academic_year', v_label || ': academic year', 20, true, v_path || 'academic_year');
    if not exists (select 1 from public.admissions_academic_years y where y.label = v_year and y.is_active) then
      perform public._public_invalid(v_label || ': choose an academic year from the list', v_path || 'academic_year');
    end if;

    -- Campus: optional, a campus id, and it must accept the grade.
    v_campus_id := null;
    if public._public_text(v_s, 'campus_id', v_label || ': campus', 36, false, v_path || 'campus_id') <> '' then
      begin
        v_campus_id := (v_s ->> 'campus_id')::uuid;
      exception when invalid_text_representation then
        perform public._public_invalid(v_label || ': choose a campus from the list', v_path || 'campus_id');
      end;
      if not exists (select 1 from public.branches b where b.id = v_campus_id) then
        perform public._public_invalid(v_label || ': choose a campus from the list', v_path || 'campus_id');
      end if;
      if exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = v_campus_id)
         and not exists (select 1 from public.admissions_campus_grade_rules r
                         where r.branch_id = v_campus_id and r.grade_id = v_grade_id) then
        perform public._public_invalid(
          v_label || ': this campus does not take ' || v_grade_name || '. Please contact the school',
          v_path || 'grade_id');
      end if;
    end if;
  end loop;

  -- ---------------------------------------------------- per-email limit
  foreach v_email in array v_emails loop
    if not public._public_rate_limit_hit(
      'inquiry_email', encode(sha256(convert_to(v_email, 'UTF8')), 'hex')
    ) then
      raise exception using errcode = 'TCS29', message = 'Too many enquiries for this email today';
    end if;
  end loop;

  -- ---------------------------------------------------- writes
  insert into public.families (referral_source, referral_source_other, comments)
  values (v_referral, v_referral_other, v_comments)
  returning id into v_family_id;

  for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
    v_g := v_guardians -> v_i;
    insert into public.guardians
      (family_id, surname, first_name, relationship, religion, address, town_city, phone, email)
    values (
      v_family_id,
      btrim(v_g ->> 'surname'), btrim(v_g ->> 'first_name'), btrim(v_g ->> 'relationship'),
      btrim(v_g ->> 'religion'), btrim(v_g ->> 'address'), btrim(v_g ->> 'town_city'),
      regexp_replace(v_g ->> 'phone', '[[:space:]-]', '', 'g'), btrim(v_g ->> 'email')
    );
  end loop;

  for v_i in 0 .. jsonb_array_length(v_students) - 1 loop
    v_s := v_students -> v_i;
    select g.name into v_grade_name from public.admissions_grades g
    where g.id = (v_s ->> 'grade_id')::uuid;
    v_campus_id := nullif(btrim(coalesce(v_s ->> 'campus_id', '')), '')::uuid;

    insert into public.students
      (family_id, full_name, date_of_birth, current_school, current_grade, current_grade_id, prior_schooling)
    values (
      v_family_id, btrim(v_s ->> 'full_name'), (btrim(v_s ->> 'date_of_birth'))::date,
      btrim(coalesce(v_s ->> 'current_school', '')), '',
      nullif(btrim(coalesce(v_s ->> 'current_grade_id', '')), '')::uuid,
      nullif(btrim(coalesce(v_s ->> 'prior_schooling', '')), '')
    )
    returning id into v_student_id;

    insert into public.applications
      (student_id, stage, academic_year, year_group_applied_for, month_of_enrollment, branch_id)
    values (
      v_student_id, 'inquiry', btrim(v_s ->> 'academic_year'), v_grade_name,
      btrim(v_s ->> 'month_of_enrollment'), v_campus_id
    )
    returning inquiry_reference into v_ref;
    v_refs := v_refs || v_ref;
  end loop;

  return v_refs;
end;
$$;

-- ------------------------------------------------------------ 4. options

create or replace function public.get_public_admissions_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with active_grades as (
    select g.id, g.name, g.position from public.admissions_grades g where g.is_active
  )
  select jsonb_build_object(
    'intake_open', coalesce((select s.public_intake_open from public.admissions_settings s where s.id = 1), false),
    'applications_open', coalesce((select s.public_applications_open from public.admissions_settings s where s.id = 1), false),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'position', g.position)
                       order by g.position, g.name)
      from active_grades g
    ), '[]'::jsonb),
    'campuses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'name', coalesce(b.public_label, b.name),
        'accepted_grade_ids', coalesce((
          select jsonb_agg(g.id order by g.position, g.name)
          from active_grades g
          where not exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = b.id)
             or exists (select 1 from public.admissions_campus_grade_rules r
                        where r.branch_id = b.id and r.grade_id = g.id)
        ), '[]'::jsonb)
      ) order by coalesce(b.public_label, b.name))
      from public.branches b
    ), '[]'::jsonb),
    'academic_years', coalesce((
      select jsonb_agg(y.label order by y.position, y.label)
      from public.admissions_academic_years y where y.is_active
    ), '[]'::jsonb)
  );
$$;

-- ------------------------------------------------------------ grants

-- create or replace keeps the options function's grants (anon,
-- authenticated, service_role) and submit_inquiry's (service_role only).
revoke execute on function public.guard_branch_public_label() from public, anon, authenticated, service_role;
revoke execute on function public._admissions_seed_public_campus_labels() from public, anon, authenticated, service_role;
revoke execute on function public._public_invalid(text, text) from public, anon, authenticated, service_role;
revoke execute on function public._public_only_keys(jsonb, text[], text, text) from public, anon, authenticated, service_role;
revoke execute on function public._public_text(jsonb, text, text, integer, boolean, text) from public, anon, authenticated, service_role;
