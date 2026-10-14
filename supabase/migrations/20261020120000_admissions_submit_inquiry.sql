-- Admissions slice 8: submit_inquiry, the public Inquiry form's write
-- (docs/admissions/PORT-PLAN.md, slice 8; D-8a, D-8d and the public forms
-- decision recorded 2026-10-13).
--
-- service_role only: the admissions-public Edge Function calls it after the
-- origin, size, Turnstile and IP and global rate limit checks. No JWT role
-- can execute it, and _require_public_service_caller() refuses anon,
-- authenticated and any signed-in caller even if a grant is ever added by
-- mistake.
--
-- It validates everything itself, as TCS OS's InquirySerializer does
-- (serializers.py:34-126): 1 or 2 guardians and 1 to 5 students, required
-- fields, the relationship and referral enums, referral_source_other when
-- the source is other, the phone rule and the email shape.
--
-- Phone (D-9d, decided 2026-10-14, looser than TCS OS): spaces and dashes
-- are removed first, then the result must be a plus sign followed by 8 to
-- 15 digits. The cleaned form (plus sign and digits only) is what's stored. Unknown keys are refused at every level, so a free-text
-- grade, year or campus can't ride along.
--
-- Stricter than TCS OS (the public forms decision): the grade, academic
-- year and campus come only as ids from the active lists. grade_id is an
-- active admissions_grades id, academic_year is an active
-- admissions_academic_years label (that table's key), and campus_id is
-- optional; when given it is a branches id, and a campus with grade rules
-- must accept the grade. The application stores the grade's name and the
-- year's label as before, so staff screens are unchanged.
--
-- It refuses while admissions_settings.public_intake_open is false (no dual
-- intake). It counts the 5 per guardian email per day limit in the same
-- transaction, so a refused or invalid submission counts nothing.
--
-- It creates a family, its guardians, and one student and one inquiry
-- application per child. INQ references come from slice 5's trigger, in
-- payload order (the counter lock is held to commit). No de-duplication,
-- matching TCS OS (D-8c is open; parity kept). It returns only the INQ
-- references, in student order, so the response never says whether an
-- email or family is already known.
--
-- Errors use three SQLSTATEs the Edge Function maps to fixed responses:
--   TCS22  invalid input; the message names the field and is safe to show
--   TCS03  public intake is closed
--   TCS29  the per-email limit is reached
-- Carry-forward from slice 5: service_role inserts write no audit row.

-- ------------------------------------------------------------ helpers

create or replace function public._public_invalid(p_message text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'TCS22', message = p_message;
end;
$$;

-- Refuses keys outside p_allowed. p_what names the object in the message.
create or replace function public._public_only_keys(p_obj jsonb, p_allowed text[], p_what text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_extra text;
begin
  -- The key's name isn't echoed: a fixed message is enough for the sender.
  select k into v_extra from jsonb_object_keys(p_obj) k where k <> all (p_allowed) limit 1;
  if v_extra is not null then
    perform public._public_invalid(p_what || ' has a field the form does not send');
  end if;
end;
$$;

-- A trimmed string field. Absent and null read as blank. Anything that
-- isn't a JSON string is refused, as is a value over p_max characters or a
-- blank required one.
create or replace function public._public_text(
  p_obj jsonb, p_key text, p_label text, p_max integer, p_required boolean
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
    perform public._public_invalid(p_label || ' must be text');
  else
    v_text := btrim(p_obj ->> p_key);
  end if;
  if char_length(v_text) > p_max then
    perform public._public_invalid(p_label || ' must be ' || p_max || ' characters or fewer');
  end if;
  if p_required and v_text = '' then
    perform public._public_invalid(p_label || ' is required');
  end if;
  return v_text;
end;
$$;

-- ------------------------------------------------------------ the RPC

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
  v_i integer;
  v_phone text;
  v_email text;
  v_emails text[] := '{}';
  v_dob_text text;
  v_dob date;
  v_grade_id uuid;
  v_grade_name text;
  v_year text;
  v_campus_id uuid;
  v_family_id uuid;
  v_student_id uuid;
  v_ref text;
  v_refs text[] := '{}';
  v_relationship text;
begin
  perform public._require_public_service_caller();

  -- Share lock: closing intake waits for in-flight submissions, and a
  -- submission after the close sees it.
  select public_intake_open into v_open from public.admissions_settings where id = 1 for share;
  if v_open is not true then
    raise exception using errcode = 'TCS03', message = 'Online inquiries are closed';
  end if;

  -- ---------------------------------------------------- shape
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    perform public._public_invalid('The inquiry must be a JSON object');
  end if;
  perform public._public_only_keys(
    p_payload, array['referral_source', 'referral_source_other', 'comments', 'guardians', 'students'],
    'The inquiry');

  v_referral := public._public_text(p_payload, 'referral_source', 'How you heard about us', 30, true);
  if v_referral not in ('current_parent', 'former_parent', 'parent_referral', 'staff_referral',
                        'website', 'friend_colleague', 'social_media', 'other') then
    perform public._public_invalid('How you heard about us: choose one of the listed options');
  end if;
  v_referral_other := public._public_text(
    p_payload, 'referral_source_other', 'How you heard about us (other)', 255, v_referral = 'other');
  if v_referral <> 'other' then
    v_referral_other := '';
  end if;
  v_comments := public._public_text(p_payload, 'comments', 'Comments', 10000, false);

  v_guardians := p_payload -> 'guardians';
  if v_guardians is null or jsonb_typeof(v_guardians) <> 'array'
     or jsonb_array_length(v_guardians) not between 1 and 2 then
    perform public._public_invalid('Give one or two parents or guardians');
  end if;
  v_students := p_payload -> 'students';
  if v_students is null or jsonb_typeof(v_students) <> 'array'
     or jsonb_array_length(v_students) not between 1 and 5 then
    perform public._public_invalid('Give between one and five children');
  end if;

  -- ---------------------------------------------------- guardians
  for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
    v_g := v_guardians -> v_i;
    v_label := 'Parent or guardian ' || (v_i + 1);
    if jsonb_typeof(v_g) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object');
    end if;
    perform public._public_only_keys(
      v_g, array['surname', 'first_name', 'relationship', 'religion', 'address', 'town_city', 'phone', 'email'],
      v_label);
    perform public._public_text(v_g, 'surname', v_label || ': surname', 255, true);
    perform public._public_text(v_g, 'first_name', v_label || ': first name', 255, true);
    v_relationship := public._public_text(v_g, 'relationship', v_label || ': relationship', 20, true);
    if v_relationship not in ('mother', 'father', 'guardian', 'other') then
      perform public._public_invalid(v_label || ': choose a relationship from the list');
    end if;
    perform public._public_text(v_g, 'religion', v_label || ': religion', 255, true);
    perform public._public_text(v_g, 'address', v_label || ': address', 255, true);
    perform public._public_text(v_g, 'town_city', v_label || ': town or city', 255, true);
    v_phone := regexp_replace(
      public._public_text(v_g, 'phone', v_label || ': phone', 32, true), '[[:space:]-]', '', 'g');
    if v_phone !~ '^\+[0-9]{8,15}$' then
      perform public._public_invalid(
        v_label || ': enter the phone as + then the country code and number, 8 to 15 digits, e.g. +233551794822');
    end if;
    v_email := lower(public._public_text(v_g, 'email', v_label || ': email', 254, true));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      perform public._public_invalid(v_label || ': enter a valid email address');
    end if;
    if not v_email = any (v_emails) then
      v_emails := v_emails || v_email;
    end if;
  end loop;

  -- ---------------------------------------------------- students
  for v_i in 0 .. jsonb_array_length(v_students) - 1 loop
    v_s := v_students -> v_i;
    v_label := 'Child ' || (v_i + 1);
    if jsonb_typeof(v_s) <> 'object' then
      perform public._public_invalid(v_label || ' must be an object');
    end if;
    perform public._public_only_keys(
      v_s, array['full_name', 'date_of_birth', 'current_school', 'current_grade', 'grade_id',
                 'academic_year', 'campus_id', 'month_of_enrollment'],
      v_label);
    perform public._public_text(v_s, 'full_name', v_label || ': full name', 255, true);
    v_dob_text := public._public_text(v_s, 'date_of_birth', v_label || ': date of birth', 10, true);
    if v_dob_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      perform public._public_invalid(v_label || ': enter a valid date of birth');
    end if;
    begin
      v_dob := v_dob_text::date;
    exception when others then
      perform public._public_invalid(v_label || ': enter a valid date of birth');
    end;
    if v_dob > (clock_timestamp() at time zone 'Africa/Accra')::date or v_dob < date '1900-01-01' then
      perform public._public_invalid(v_label || ': enter a valid date of birth');
    end if;
    perform public._public_text(v_s, 'current_school', v_label || ': current school', 255, true);
    perform public._public_text(v_s, 'current_grade', v_label || ': current grade or class', 50, true);
    perform public._public_text(v_s, 'month_of_enrollment', v_label || ': month of enrolment', 50, true);

    -- Grade: an active grade id, nothing else.
    begin
      v_grade_id := public._public_text(v_s, 'grade_id', v_label || ': grade', 36, true)::uuid;
    exception when invalid_text_representation then
      perform public._public_invalid(v_label || ': choose a grade from the list');
    end;
    select g.name into v_grade_name from public.admissions_grades g
    where g.id = v_grade_id and g.is_active;
    if v_grade_name is null then
      perform public._public_invalid(v_label || ': choose a grade from the list');
    end if;

    -- Academic year: an active label, nothing else.
    v_year := public._public_text(v_s, 'academic_year', v_label || ': academic year', 20, true);
    if not exists (select 1 from public.admissions_academic_years y where y.label = v_year and y.is_active) then
      perform public._public_invalid(v_label || ': choose an academic year from the list');
    end if;

    -- Campus: optional, a campus id, and it must accept the grade.
    v_campus_id := null;
    if public._public_text(v_s, 'campus_id', v_label || ': campus', 36, false) <> '' then
      begin
        v_campus_id := (v_s ->> 'campus_id')::uuid;
      exception when invalid_text_representation then
        perform public._public_invalid(v_label || ': choose a campus from the list');
      end;
      if not exists (select 1 from public.branches b where b.id = v_campus_id) then
        perform public._public_invalid(v_label || ': choose a campus from the list');
      end if;
      if exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = v_campus_id)
         and not exists (select 1 from public.admissions_campus_grade_rules r
                         where r.branch_id = v_campus_id and r.grade_id = v_grade_id) then
        perform public._public_invalid(
          v_label || ': this campus does not take ' || v_grade_name || '. Please contact the school');
      end if;
    end if;
  end loop;

  -- ---------------------------------------------------- per-email limit
  foreach v_email in array v_emails loop
    if not public._public_rate_limit_hit(
      'inquiry_email', encode(sha256(convert_to(v_email, 'UTF8')), 'hex')
    ) then
      raise exception using errcode = 'TCS29', message = 'Too many inquiries for this email today';
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
    select g.id, g.name into v_grade_id, v_grade_name from public.admissions_grades g
    where g.id = (v_s ->> 'grade_id')::uuid;
    v_campus_id := nullif(btrim(coalesce(v_s ->> 'campus_id', '')), '')::uuid;

    insert into public.students (family_id, full_name, date_of_birth, current_school, current_grade)
    values (
      v_family_id, btrim(v_s ->> 'full_name'), (btrim(v_s ->> 'date_of_birth'))::date,
      btrim(v_s ->> 'current_school'), btrim(v_s ->> 'current_grade')
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

-- ------------------------------------------------------------ grants

revoke execute on function public._public_invalid(text) from public, anon, authenticated, service_role;
revoke execute on function public._public_only_keys(jsonb, text[], text) from public, anon, authenticated, service_role;
revoke execute on function public._public_text(jsonb, text, text, integer, boolean) from public, anon, authenticated, service_role;
revoke execute on function public.submit_inquiry(jsonb) from public, anon, authenticated;
grant execute on function public.submit_inquiry(jsonb) to service_role;
