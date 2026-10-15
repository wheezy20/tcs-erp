-- Admissions slice 9a, checkpoint 2: submit_application, the public
-- Application form's write, and application_match_flags
-- (docs/admissions/PORT-PLAN.md, slice 9; D-9b, D-9c, D-9e, D-9f, D-9i and
-- D-9j decided 2026-10-13 and 2026-10-14; checkpoint 2 gates answered
-- 2026-10-15).
--
-- service_role only: the admissions-public Edge Function's "application"
-- action calls it after the origin, size, IP limit, Turnstile (action
-- "application") and global limit checks, and after it has read the
-- leading bytes of every file the parent says they uploaded.
--
--   submit_application(p_payload jsonb, p_session_token text, p_sniffed jsonb)
--     returns text: the APP reference and nothing else.
--
-- The Edge Function reports what each file's bytes are (p_sniffed: an
-- array of {reservation_id, path, kind}, kind one of pdf, jpeg, png or
-- unknown); this function decides. The database can't read stored bytes,
-- so the report has to come from the one caller that holds the service key.
-- Overwrite is off on every signed upload and the bucket has no write
-- policy, so once the bytes are read the object can't be replaced; and the
-- path in the report must equal the reservation's own path, so bytes read
-- from one object can't vouch for another.
--
-- Order inside the transaction. Every refusal before the writes writes and
-- counts nothing.
--   1. _require_public_service_caller().
--   2. public_applications_open, under a share lock (closing waits for
--      in-flight submissions). public_intake_open, the enquiries switch,
--      plays no part.
--   3. The whole payload is validated, with the slice 8b field rules and
--      the D-9d phone rule. Unknown keys are refused at every level.
--   4. The upload session is locked by the hash of its token. A session
--      already used for a submission returns that application's reference
--      and does nothing else (a double click or a retry; gate answered
--      2026-10-15). Any other closed, expired or unknown session is refused.
--   5. The 5 per guardian email per day limit (application_email) is
--      counted. A later refusal rolls the count back.
--   6. Documents. The required types come from
--      _application_required_document_types(grade), the helper the public
--      options use, so the form and the server can't disagree: the fee proof
--      for every grade (D-9e), and vaccination proof where the grade needs
--      it. Every document must name a reservation of this session that is
--      unused, not cleaned and unexpired, of the same type, at exactly the
--      reserved path; the object must exist at that path; and the reported
--      kind for that reservation and path must match the extension. Any
--      failure gives one generic message.
--   7. Matching and writes (below), the flags row, the reservations marked
--      used, and the session closed with the application it made.
--
-- Matching (TCS OS serializers.py:251-330, with the ERP's changes):
--   family     among families with a guardian whose email (stored
--              lowercased) equals a submitted one, the oldest that holds a
--              child with the same name (case-insensitive) and date of
--              birth; else the oldest such family; else a new family with
--              the submitted guardians (gate answered 2026-10-15).
--   student    same name (case-insensitive) and date of birth in that
--              family, else a new student.
--   application  for that student, same academic year and grade:
--              at inquiry: the oldest is advanced to application, keeps its
--                INQ and gains an APP (outcome inquiry_advanced);
--              past inquiry: left untouched, and a new application is made
--                at application with its own APP (outcome
--                possible_duplicate, D-9j);
--              none: a new application at application.
-- A matched family never gains or changes guardians, and a matched student
-- is never updated (D-9b). Submitted details that differ from the record
-- go into application_match_flags.differences, which staff read. Health is
-- always written to the application's own fresh row, never to the
-- snapshot, and a table check keeps health keys out of it (D-9j, closing
-- the slice 3a carry-forward). A match is never refused (D-9c), and the
-- response is the same APP reference text whatever happened.
--
-- declaration_agreed_at is set here; declaration_ip_address stays empty
-- and no IP reaches the database (D-9i).
--
-- Carry-forward from slice 5: service_role writes bypass the stage RPCs
-- and write no audit row. The flags row is the staff-visible record. The
-- APP number is taken by the applications insert or update, after every
-- check, so its counter lock is held only for the writes.
--
-- Errors use the slice 8 SQLSTATEs the Edge Function maps:
--   TCS22  invalid input; the message is safe to show, the field path is in
--          DETAIL
--   TCS03  public applications are closed
--   TCS29  the per-email limit is reached

-- ------------------------------------------------------------ session link

-- Set when a session's submission succeeds, so a repeat of the same submit
-- returns the same reference. The table keeps no API privileges.
alter table public.application_upload_sessions
  add column submitted_application_id uuid references public.applications (id) on delete set null,
  add constraint application_upload_sessions_submitted_closed_check
    check (submitted_application_id is null or closed_at is not null);

-- ------------------------------------------------------------ match flags

-- One row per publicly submitted application that matched an existing
-- family. A wholly new family gets no row.
create table public.application_match_flags (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.applications (id) on delete cascade,
  family_matched boolean not null,
  student_matched boolean not null,
  outcome text not null check (outcome in ('new_application', 'inquiry_advanced', 'possible_duplicate')),
  -- The earlier application a possible duplicate matched.
  matched_application_id uuid references public.applications (id) on delete set null,
  -- The submitted values that differ from the record: "guardians" (an
  -- array of {email, new, fields}) and "student" (field to submitted value).
  -- Nothing else, so health answers can't be stored here.
  differences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint application_match_flags_differences_check check (
    jsonb_typeof(differences) = 'object'
    and differences - array['guardians', 'student'] = '{}'::jsonb
    and (differences -> 'guardians' is null or jsonb_typeof(differences -> 'guardians') = 'array')
    and (differences -> 'student' is null
         or (jsonb_typeof(differences -> 'student') = 'object'
             and (differences -> 'student') - array[
               'gender', 'nationality', 'address', 'town_city', 'postal_code', 'country',
               'current_school', 'previous_school_location', 'current_grade_id', 'prior_schooling'
             ] = '{}'::jsonb))
  ),
  constraint application_match_flags_match_check check (
    (matched_application_id is null or outcome = 'possible_duplicate')
    and (family_matched or not student_matched)
    and (outcome = 'new_application' or student_matched)
  )
);

create index application_match_flags_matched_application_id_idx
  on public.application_match_flags (matched_application_id);

alter table public.application_match_flags enable row level security;

-- The same read set as application_documents (gate answered 2026-10-15):
-- Manager, Auditor and an Admissions Officer with the application in
-- scope. No health capability, because the table can't hold health.
create policy application_match_flags_select on public.application_match_flags
  for select using (
    public.has_role(array['Manager', 'Auditor', 'Admissions Officer'])
    and public.admissions_application_visible(application_id)
  );

revoke all on table public.application_match_flags from public, anon, authenticated, service_role;
grant select on table public.application_match_flags to authenticated;

-- ------------------------------------------------------------ helpers

-- A JSON boolean field. Absent and null read as false; anything that isn't
-- a JSON boolean is refused.
create or replace function public._public_bool(p_obj jsonb, p_key text, p_label text, p_field text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_type text := jsonb_typeof(p_obj -> p_key);
begin
  if v_type is null or v_type = 'null' then
    return false;
  elsif v_type <> 'boolean' then
    perform public._public_invalid(p_label || ': choose yes or no', p_field);
  end if;
  return (p_obj -> p_key)::boolean;
end;
$$;

-- A phone number by the D-9d rule (revised 2026-10-14), as submit_inquiry
-- checks it: +233 and exactly 9 digits, the first not 0, or another
-- country code (not starting with 0) and 8 to 15 digits in all.
create or replace function public._public_phone_ok(p_phone text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_phone ~ '^\+233[1-9][0-9]{8}$'
      or (p_phone ~ '^\+[1-9][0-9]{7,14}$' and p_phone !~ '^\+233');
$$;

-- The kind of file an extension promises.
create or replace function public._application_kind_for_extension(p_extension text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_extension when 'pdf' then 'pdf' when 'jpg' then 'jpeg' when 'jpeg' then 'jpeg'
                          when 'png' then 'png' end;
$$;

-- ------------------------------------------------------------ the RPC

create or replace function public.submit_application(
  p_payload jsonb, p_session_token text, p_sniffed jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open boolean;
  v_guardians jsonb;
  v_g jsonb;
  v_s jsonb;
  v_ec jsonb;
  v_h jsonb;
  v_docs jsonb;
  v_d jsonb;
  v_label text;
  v_path text;
  v_i integer;
  v_phone text;
  v_email text;
  v_emails text[] := '{}';
  v_relationship text;
  v_religion text;
  -- student
  v_full_name text;
  v_dob_text text;
  v_dob date;
  v_gender text;
  v_nationality text;
  v_address text;
  v_town text;
  v_postal text;
  v_country text;
  v_school text;
  v_prev_location text;
  v_current_grade_text text;
  v_current_grade_id uuid;
  v_prior text;
  v_grade_id uuid;
  v_grade_name text;
  v_year text;
  v_month text;
  v_campus_id uuid;
  -- application
  v_ec_name text;
  v_ec_relationship text;
  v_ec_phone text;
  v_has_needs boolean;
  v_needs text;
  v_has_medical boolean;
  v_medical text;
  v_has_allergies boolean;
  v_allergies text;
  v_wants_scholarship boolean;
  v_scholarship text;
  v_media boolean;
  v_signature text;
  -- documents
  v_required text[];
  v_types text[] := '{}';
  v_res_ids uuid[] := '{}';
  v_res_id uuid;
  v_res public.application_upload_reservations;
  v_kind text;
  -- session and writes
  v_session public.application_upload_sessions;
  v_family_id uuid;
  v_student_id uuid;
  v_app public.applications;
  v_matched_app_id uuid;
  v_family_matched boolean := false;
  v_student_matched boolean := false;
  v_outcome text := 'new_application';
  v_existing public.guardians;
  v_existing_student public.students;
  v_guardian_diffs jsonb := '[]'::jsonb;
  v_student_diffs jsonb := '{}'::jsonb;
  v_fields jsonb;
  v_differences jsonb;
  v_now timestamptz := clock_timestamp();
  v_doc_message constant text :=
    'A required document is missing or could not be accepted. Please choose your files again and resubmit.';
begin
  perform public._require_public_service_caller();

  -- Public applications only: the enquiries switch plays no part here.
  select public_applications_open into v_open from public.admissions_settings where id = 1 for share;
  if v_open is not true then
    raise exception using errcode = 'TCS03', message = 'Online applications are closed';
  end if;

  -- ---------------------------------------------------- shape
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    perform public._public_invalid('The application must be a JSON object', null);
  end if;
  perform public._public_only_keys(
    p_payload, array['guardians', 'student', 'campus_id', 'emergency_contact', 'health_info', 'documents',
                     'wants_scholarship_info', 'scholarship_interest_details', 'media_consent_agreed',
                     'declaration_signature_name', 'declaration_agreed'],
    'The application', null);

  -- ---------------------------------------------------- guardians
  v_guardians := p_payload -> 'guardians';
  if v_guardians is null or jsonb_typeof(v_guardians) <> 'array'
     or jsonb_array_length(v_guardians) not between 1 and 2 then
    perform public._public_invalid('Give one or two parents or guardians', 'guardians');
  end if;
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
    v_phone := public._public_text(v_g, 'phone', v_label || ': phone', 32, true, v_path || 'phone');
    if not public._public_phone_ok(v_phone) then
      perform public._public_invalid(
        v_label || ': format +233590000000, country code and number, no spaces', v_path || 'phone');
    end if;
    v_email := lower(public._public_text(v_g, 'email', v_label || ': email', 254, true, v_path || 'email'));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      perform public._public_invalid(v_label || ': enter a valid email address', v_path || 'email');
    end if;
    if not v_email = any (v_emails) then
      v_emails := v_emails || v_email;
    end if;
  end loop;

  -- ---------------------------------------------------- student
  v_s := p_payload -> 'student';
  if v_s is null or jsonb_typeof(v_s) <> 'object' then
    perform public._public_invalid('The child''s details are required', 'student');
  end if;
  v_label := 'Child';
  v_path := 'student.';
  perform public._public_only_keys(
    v_s, array['full_name', 'date_of_birth', 'gender', 'nationality', 'address', 'town_city', 'postal_code',
               'country', 'current_school', 'previous_school_location', 'current_grade_id', 'prior_schooling',
               'grade_id', 'academic_year', 'month_of_enrollment'],
    v_label, 'student');
  v_full_name := public._public_text(v_s, 'full_name', v_label || ': full name', 255, true, v_path || 'full_name');

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

  v_gender := public._public_text(v_s, 'gender', v_label || ': gender', 10, true, v_path || 'gender');
  if v_gender not in ('male', 'female') then
    perform public._public_invalid(v_label || ': choose a gender from the list', v_path || 'gender');
  end if;
  v_nationality := public._public_text(v_s, 'nationality', v_label || ': nationality', 100, true, v_path || 'nationality');
  v_address := public._public_text(v_s, 'address', v_label || ': address', 255, true, v_path || 'address');
  v_town := public._public_text(v_s, 'town_city', v_label || ': town or city', 255, true, v_path || 'town_city');
  v_postal := public._public_text(v_s, 'postal_code', v_label || ': postal code', 20, false, v_path || 'postal_code');
  v_country := public._public_text(v_s, 'country', v_label || ': country', 100, false, v_path || 'country');
  v_prev_location := public._public_text(
    v_s, 'previous_school_location', v_label || ': previous school location', 255, false,
    v_path || 'previous_school_location');

  -- Current grade or class: an active grade id, or not yet in school.
  -- Exactly one (slice 8b).
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
  v_current_grade_id := null;
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
  select g.name into v_grade_name from public.admissions_grades g where g.id = v_grade_id and g.is_active;
  if v_grade_name is null then
    perform public._public_invalid(v_label || ': choose a grade from the list', v_path || 'grade_id');
  end if;

  -- Academic year: an active label, nothing else.
  v_year := public._public_text(v_s, 'academic_year', v_label || ': academic year', 20, true, v_path || 'academic_year');
  if not exists (select 1 from public.admissions_academic_years y where y.label = v_year and y.is_active) then
    perform public._public_invalid(v_label || ': choose an academic year from the list', v_path || 'academic_year');
  end if;

  -- ---------------------------------------------------- campus
  -- Required for an application, and a campus with grade rules must accept
  -- the grade.
  begin
    v_campus_id := public._public_text(p_payload, 'campus_id', 'Campus', 36, true, 'campus_id')::uuid;
  exception when invalid_text_representation then
    perform public._public_invalid('Choose a campus from the list', 'campus_id');
  end;
  if not exists (select 1 from public.branches b where b.id = v_campus_id) then
    perform public._public_invalid('Choose a campus from the list', 'campus_id');
  end if;
  if exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = v_campus_id)
     and not exists (select 1 from public.admissions_campus_grade_rules r
                     where r.branch_id = v_campus_id and r.grade_id = v_grade_id) then
    perform public._public_invalid(
      'This campus does not take ' || v_grade_name || '. Please choose another campus or contact the school',
      'campus_id');
  end if;

  -- ---------------------------------------------------- emergency contact
  v_ec := p_payload -> 'emergency_contact';
  if v_ec is null or jsonb_typeof(v_ec) <> 'object' then
    perform public._public_invalid('An emergency contact is required', 'emergency_contact');
  end if;
  perform public._public_only_keys(v_ec, array['name', 'relationship', 'phone'], 'Emergency contact', 'emergency_contact');
  v_ec_name := public._public_text(v_ec, 'name', 'Emergency contact: name', 255, true, 'emergency_contact.name');
  v_ec_relationship := public._public_text(
    v_ec, 'relationship', 'Emergency contact: relationship', 100, true, 'emergency_contact.relationship');
  v_ec_phone := public._public_text(v_ec, 'phone', 'Emergency contact: phone', 32, true, 'emergency_contact.phone');
  if not public._public_phone_ok(v_ec_phone) then
    perform public._public_invalid(
      'Emergency contact: format +233590000000, country code and number, no spaces', 'emergency_contact.phone');
  end if;

  -- ---------------------------------------------------- health
  -- Details are kept only when the answer is yes; 2,000 characters each
  -- (D-4e).
  v_h := p_payload -> 'health_info';
  if v_h is null or jsonb_typeof(v_h) <> 'object' then
    perform public._public_invalid('The health questions are required', 'health_info');
  end if;
  perform public._public_only_keys(
    v_h, array['has_learning_or_physical_needs', 'learning_or_physical_needs_details', 'has_medical_conditions',
               'medical_conditions_details', 'has_allergies_or_dietary_requirements', 'allergies_dietary_details'],
    'Health', 'health_info');
  v_has_needs := public._public_bool(
    v_h, 'has_learning_or_physical_needs', 'Learning or physical needs', 'health_info.has_learning_or_physical_needs');
  v_needs := public._public_text(
    v_h, 'learning_or_physical_needs_details', 'Learning or physical needs: details', 2000, v_has_needs,
    'health_info.learning_or_physical_needs_details');
  v_has_medical := public._public_bool(
    v_h, 'has_medical_conditions', 'Medical conditions', 'health_info.has_medical_conditions');
  v_medical := public._public_text(
    v_h, 'medical_conditions_details', 'Medical conditions: details', 2000, v_has_medical,
    'health_info.medical_conditions_details');
  v_has_allergies := public._public_bool(
    v_h, 'has_allergies_or_dietary_requirements', 'Allergies or dietary requirements',
    'health_info.has_allergies_or_dietary_requirements');
  v_allergies := public._public_text(
    v_h, 'allergies_dietary_details', 'Allergies or dietary requirements: details', 2000, v_has_allergies,
    'health_info.allergies_dietary_details');
  if not v_has_needs then v_needs := ''; end if;
  if not v_has_medical then v_medical := ''; end if;
  if not v_has_allergies then v_allergies := ''; end if;

  -- ---------------------------------------------------- the rest
  v_wants_scholarship := public._public_bool(
    p_payload, 'wants_scholarship_info', 'Scholarship information', 'wants_scholarship_info');
  v_scholarship := public._public_text(
    p_payload, 'scholarship_interest_details', 'Scholarship interest', 10000, false, 'scholarship_interest_details');
  if not v_wants_scholarship then v_scholarship := ''; end if;
  v_media := public._public_bool(p_payload, 'media_consent_agreed', 'Media consent', 'media_consent_agreed');
  v_signature := public._public_text(
    p_payload, 'declaration_signature_name', 'Declaration: your full name as signature', 255, true,
    'declaration_signature_name');
  if not public._public_bool(p_payload, 'declaration_agreed', 'Declaration', 'declaration_agreed') then
    perform public._public_invalid('You must agree to the declaration to submit this application', 'declaration_agreed');
  end if;

  -- ---------------------------------------------------- documents (shape)
  v_docs := p_payload -> 'documents';
  if v_docs is null or jsonb_typeof(v_docs) <> 'array' or jsonb_array_length(v_docs) not between 1 and 4 then
    perform public._public_invalid(v_doc_message, 'documents');
  end if;
  for v_i in 0 .. jsonb_array_length(v_docs) - 1 loop
    v_d := v_docs -> v_i;
    if jsonb_typeof(v_d) <> 'object'
       or exists (select 1 from jsonb_object_keys(v_d) k where k not in ('document_type', 'reservation_id', 'path'))
       or jsonb_typeof(v_d -> 'document_type') is distinct from 'string'
       or jsonb_typeof(v_d -> 'reservation_id') is distinct from 'string'
       or jsonb_typeof(v_d -> 'path') is distinct from 'string'
       or (v_d ->> 'reservation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (v_d ->> 'document_type') = any (v_types) then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
    v_types := v_types || (v_d ->> 'document_type');
    v_res_ids := v_res_ids || (v_d ->> 'reservation_id')::uuid;
  end loop;
  v_required := public._application_required_document_types(v_grade_id);
  if v_required is null or not (v_types @> v_required) then
    perform public._public_invalid(v_doc_message, 'documents');
  end if;
  if p_sniffed is null or jsonb_typeof(p_sniffed) <> 'array' then
    perform public._public_invalid(v_doc_message, 'documents');
  end if;

  -- ---------------------------------------------------- session
  if p_session_token is not null and p_session_token ~ '^[0-9a-f]{64}$' then
    select * into v_session from public.application_upload_sessions
    where token_hash = encode(sha256(convert_to(p_session_token, 'UTF8')), 'hex')
    for update;
  end if;
  -- The same session already made an application: a double click or a
  -- retry. Same answer, nothing written, nothing counted.
  if v_session.id is not null and v_session.submitted_application_id is not null then
    return (select a.application_reference from public.applications a
            where a.id = v_session.submitted_application_id);
  end if;
  if v_session.id is null or v_session.closed_at is not null or v_session.expires_at <= v_now then
    raise exception using errcode = 'TCS22', detail = 'documents',
      message = 'Your upload session has expired. Please reload the page and choose your files again.';
  end if;

  -- ---------------------------------------------------- per-email limit
  -- In sorted order, so two submissions naming the same emails take the
  -- counter rows' locks (held to commit) in the same order and can't
  -- deadlock. Those locks also make two submissions sharing an email run
  -- one after the other, so the second one's family match sees the first.
  select array_agg(e order by e) into v_emails from unnest(v_emails) e;
  foreach v_email in array v_emails loop
    if not public._public_rate_limit_hit(
      'application_email', encode(sha256(convert_to(v_email, 'UTF8')), 'hex')
    ) then
      raise exception using errcode = 'TCS29', message = 'Too many applications for this email today';
    end if;
  end loop;

  -- ---------------------------------------------------- documents (binding)
  -- Every reservation of the session, locked in id order.
  perform 1 from public.application_upload_reservations r
  where r.session_id = v_session.id order by r.id for update;
  for v_i in 0 .. jsonb_array_length(v_docs) - 1 loop
    v_d := v_docs -> v_i;
    v_res := null;
    select * into v_res from public.application_upload_reservations r
    where r.id = (v_d ->> 'reservation_id')::uuid and r.session_id = v_session.id;
    if v_res.id is null
       or v_res.consumed_at is not null or v_res.cleaned_at is not null or v_res.expires_at <= v_now
       or v_res.document_type <> (v_d ->> 'document_type')
       or v_res.storage_path <> (v_d ->> 'path') then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
    if not exists (select 1 from storage.objects o
                   where o.bucket_id = 'admissions-documents' and o.name = v_res.storage_path) then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
    -- The kind the Edge Function read from this reservation's own path.
    select e ->> 'kind' into v_kind
    from jsonb_array_elements(p_sniffed) e
    where jsonb_typeof(e) = 'object'
      and e ->> 'reservation_id' = v_res.id::text
      and e ->> 'path' = v_res.storage_path
    limit 1;
    if v_kind is null or v_kind is distinct from public._application_kind_for_extension(v_res.extension) then
      perform public._public_invalid(v_doc_message, 'documents');
    end if;
  end loop;

  -- ---------------------------------------------------- family
  select f.id into v_family_id
  from public.families f
  where exists (select 1 from public.guardians g where g.family_id = f.id and g.email = any (v_emails))
  order by exists (select 1 from public.students s
                   where s.family_id = f.id and lower(btrim(s.full_name)) = lower(v_full_name)
                     and s.date_of_birth = v_dob) desc,
           f.created_at, f.id
  limit 1;

  if v_family_id is null then
    insert into public.families default values returning id into v_family_id;
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
  else
    -- Matched: the family's guardians are never added to or changed. What
    -- differs is recorded for staff.
    v_family_matched := true;
    for v_i in 0 .. jsonb_array_length(v_guardians) - 1 loop
      v_g := v_guardians -> v_i;
      v_email := lower(btrim(v_g ->> 'email'));
      v_existing := null;
      select * into v_existing from public.guardians g
      where g.family_id = v_family_id and g.email = v_email
      order by g.id limit 1;
      if v_existing.id is null then
        v_guardian_diffs := v_guardian_diffs || jsonb_build_array(jsonb_build_object(
          'email', v_email, 'new', true,
          'fields', jsonb_build_object(
            'surname', btrim(v_g ->> 'surname'), 'first_name', btrim(v_g ->> 'first_name'),
            'relationship', btrim(v_g ->> 'relationship'), 'religion', btrim(v_g ->> 'religion'),
            'address', btrim(v_g ->> 'address'), 'town_city', btrim(v_g ->> 'town_city'),
            'phone', btrim(v_g ->> 'phone'))));
      else
        select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_fields
        from (values
          ('surname', btrim(v_g ->> 'surname'), v_existing.surname),
          ('first_name', btrim(v_g ->> 'first_name'), v_existing.first_name),
          ('relationship', btrim(v_g ->> 'relationship'), v_existing.relationship),
          ('religion', btrim(v_g ->> 'religion'), v_existing.religion),
          ('address', btrim(v_g ->> 'address'), v_existing.address),
          ('town_city', btrim(v_g ->> 'town_city'), v_existing.town_city),
          ('phone', btrim(v_g ->> 'phone'), v_existing.phone)
        ) as d (k, v, old)
        where d.v is distinct from d.old;
        if v_fields <> '{}'::jsonb then
          v_guardian_diffs := v_guardian_diffs || jsonb_build_array(jsonb_build_object(
            'email', v_email, 'new', false, 'fields', v_fields));
        end if;
      end if;
    end loop;
  end if;

  -- ---------------------------------------------------- student
  select * into v_existing_student from public.students s
  where s.family_id = v_family_id and lower(btrim(s.full_name)) = lower(v_full_name) and s.date_of_birth = v_dob
  order by s.id limit 1;
  if v_existing_student.id is null then
    insert into public.students
      (family_id, full_name, date_of_birth, gender, nationality, address, town_city, postal_code, country,
       current_school, previous_school_location, current_grade, current_grade_id, prior_schooling)
    values (
      v_family_id, v_full_name, v_dob, v_gender, v_nationality, v_address, v_town, v_postal, v_country,
      v_school, v_prev_location, '', v_current_grade_id, nullif(v_prior, '')
    )
    returning id into v_student_id;
  else
    -- Matched: never updated. What differs is recorded for staff.
    v_student_matched := true;
    v_student_id := v_existing_student.id;
    select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_student_diffs
    from (values
      ('gender', v_gender, v_existing_student.gender),
      ('nationality', v_nationality, v_existing_student.nationality),
      ('address', v_address, v_existing_student.address),
      ('town_city', v_town, v_existing_student.town_city),
      ('postal_code', v_postal, v_existing_student.postal_code),
      ('country', v_country, v_existing_student.country),
      ('current_school', v_school, v_existing_student.current_school),
      ('previous_school_location', v_prev_location, v_existing_student.previous_school_location),
      ('current_grade_id', v_current_grade_id::text, v_existing_student.current_grade_id::text),
      ('prior_schooling', nullif(v_prior, ''), v_existing_student.prior_schooling)
    ) as d (k, v, old)
    where d.v is distinct from d.old;
  end if;

  -- ---------------------------------------------------- application
  v_app := null;
  if v_student_matched then
    -- An inquiry for the same year and grade is advanced, the oldest first,
    -- re-checked under its row lock.
    select * into v_app from public.applications a
    where a.student_id = v_student_id and a.academic_year = v_year
      and a.year_group_applied_for = v_grade_name and a.stage = 'inquiry'
    order by a.created_at, a.id
    limit 1
    for update;
    if v_app.id is null then
      select a.id into v_matched_app_id from public.applications a
      where a.student_id = v_student_id and a.academic_year = v_year
        and a.year_group_applied_for = v_grade_name
      order by a.created_at desc, a.id desc
      limit 1;
    end if;
  end if;

  if v_app.id is not null then
    v_outcome := 'inquiry_advanced';
    update public.applications set
      stage = 'application',
      month_of_enrollment = v_month,
      branch_id = v_campus_id,
      wants_scholarship_info = v_wants_scholarship,
      scholarship_interest_details = v_scholarship,
      declaration_signature_name = v_signature,
      declaration_agreed = true,
      declaration_agreed_at = v_now,
      declaration_ip_address = null,
      media_consent_agreed = v_media
    where id = v_app.id
    returning * into v_app;
  else
    if v_matched_app_id is not null then
      v_outcome := 'possible_duplicate';
    end if;
    insert into public.applications
      (student_id, stage, academic_year, year_group_applied_for, month_of_enrollment, branch_id,
       wants_scholarship_info, scholarship_interest_details, declaration_signature_name,
       declaration_agreed, declaration_agreed_at, declaration_ip_address, media_consent_agreed)
    values (
      v_student_id, 'application', v_year, v_grade_name, v_month, v_campus_id,
      v_wants_scholarship, v_scholarship, v_signature, true, v_now, null, v_media
    )
    returning * into v_app;
  end if;

  insert into public.application_emergency_contacts (application_id, name, relationship, phone)
  values (v_app.id, v_ec_name, v_ec_relationship, v_ec_phone);

  -- Always the application's own fresh row (D-9j).
  insert into public.application_health_info
    (application_id, has_learning_or_physical_needs, learning_or_physical_needs_details,
     has_medical_conditions, medical_conditions_details,
     has_allergies_or_dietary_requirements, allergies_dietary_details)
  values (v_app.id, v_has_needs, v_needs, v_has_medical, v_medical, v_has_allergies, v_allergies);

  insert into public.application_documents (application_id, document_type, storage_path, status, uploaded_at)
  select v_app.id, r.document_type, r.storage_path, 'pending_review', v_now
  from public.application_upload_reservations r
  where r.id = any (v_res_ids)
  order by array_position(v_res_ids, r.id);

  update public.application_upload_reservations set consumed_at = v_now where id = any (v_res_ids);
  update public.application_upload_sessions
  set closed_at = v_now, submitted_application_id = v_app.id
  where id = v_session.id;

  if v_family_matched then
    v_differences := '{}'::jsonb;
    if jsonb_array_length(v_guardian_diffs) > 0 then
      v_differences := v_differences || jsonb_build_object('guardians', v_guardian_diffs);
    end if;
    if v_student_diffs <> '{}'::jsonb then
      v_differences := v_differences || jsonb_build_object('student', v_student_diffs);
    end if;
    insert into public.application_match_flags
      (application_id, family_matched, student_matched, outcome, matched_application_id, differences)
    values (v_app.id, true, v_student_matched, v_outcome, v_matched_app_id, v_differences);
  end if;

  return v_app.application_reference;
end;
$$;

-- ------------------------------------------------------------ grants

revoke execute on function public._public_bool(jsonb, text, text, text) from public, anon, authenticated, service_role;
revoke execute on function public._public_phone_ok(text) from public, anon, authenticated, service_role;
revoke execute on function public._application_kind_for_extension(text) from public, anon, authenticated, service_role;
revoke execute on function public.submit_application(jsonb, text, jsonb) from public, anon, authenticated;
grant execute on function public.submit_application(jsonb, text, jsonb) to service_role;
