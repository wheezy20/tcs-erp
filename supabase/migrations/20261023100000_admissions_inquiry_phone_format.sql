-- Admissions: a strict phone format on the public enquiry form (D-9d
-- revised 2026-10-14, replacing the earlier rule that removed spaces and
-- dashes before checking).
--
-- A guardian phone is a plus sign and digits only, stored as sent:
--   Ghana (+233): exactly 9 digits after +233, the first not 0 (a Ghana
--     number drops its leading 0), for example +233590000000;
--   any other country: a country code not starting with 0, and 8 to 15
--     digits in all after the plus sign, for example +442079460958.
-- Spaces, dashes, letters, anything else and extra digits are refused;
-- nothing is cleaned or stripped any more. The form puts +233 in front of
-- digits typed without a plus sign and shows the number with no spaces.
--
-- Re-creates submit_inquiry from 20261022100000 with only the phone check,
-- its message and the stored value changed. Same signature and grants
-- (service_role only; create or replace keeps them).

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
    -- A plus sign and digits only (D-9d revised 2026-10-14): +233 and
    -- exactly 9 digits, or another country code and 8 to 15 digits in all.
    v_phone := public._public_text(v_g, 'phone', v_label || ': phone', 32, true, v_path || 'phone');
    if not (v_phone ~ '^\+233[1-9][0-9]{8}$'
            or (v_phone ~ '^\+[1-9][0-9]{7,14}$' and v_phone !~ '^\+233')) then
      perform public._public_invalid(
        v_label || ': format +233590000000, country code and number, no spaces',
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
      btrim(v_g ->> 'phone'), btrim(v_g ->> 'email')
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
