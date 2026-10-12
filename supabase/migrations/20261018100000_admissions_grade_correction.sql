-- Admissions slice 7b1: grade correction, the token hash column grant, and
-- the audit action list for 7b (docs/admissions/PORT-PLAN.md, slice 7b,
-- split into 7b1 and 7b2; plan approved 2026-10-12).
--
-- Grade correction (D-6h): an application whose applied-for grade resolves
--   to no admissions grade (an unbanded grade like "Grade 11", a legacy
--   value like "2027", or free text) can never be enrolled, because
--   mark_enrolled needs a student ID classification. correct_application_grade
--   lets a Manager replace such a grade with one from admissions_grades.
--   Only an unrecognised grade can be corrected (the narrow rule): changing
--   a recognised grade would move the application between officer scopes,
--   capacity counts and student ID classifications, which is a different
--   feature. The new grade must be accepted by the application's campus
--   (admissions_campus_grade_rules: a campus with rows accepts only those
--   grades, a campus with none accepts every grade), which covers Annex.
--   Refused once enrolled.
--
-- Audit: application_grade_corrected, signed-in actor only, carrying the
--   application reference, the new grade and the old grade as entered
--   (truncated to 50 characters). The old grade is the one audit payload
--   that carries applicant-typed free text (DESIGN.md). No names, notes or
--   health data.
--
--   The list also gains admissions_academic_year_changed now, so the CHECK
--   changes once for all of slice 7b and the golden payroll suite runs once.
--   Its trigger comes with the academic year RPCs in slice 7b2. The list
--   goes from 35 to 37 values.
--
-- Offers: authenticated could select every column of application_offers,
--   token_hash included. The table grant becomes a column grant without
--   token_hash, so a signed-in select of token_hash is refused. The RLS
--   policy is unchanged, and application_offer_status (security_invoker)
--   reads only granted columns. Any column added to application_offers later
--   needs its own explicit grant (DESIGN.md).
--
-- No anon surface: the new function is revoked from public and anon.

-- ------------------------------------------------------------ audit actions

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
  'employees_imported',
  'application_stage_changed', 'application_document_status_changed',
  'application_decision_changed', 'admissions_capacity_changed',
  'application_offer_changed', 'admissions_settings_changed',
  'application_grade_corrected', 'admissions_academic_year_changed'
]));

-- ------------------------------------------------------------ offers column grant

revoke select on table public.application_offers from authenticated;
grant select (id, application_id, sent_at, expires_at, response, responded_at)
  on table public.application_offers to authenticated;

-- ------------------------------------------------------------ grade correction

-- Manager only. Checks, in order: role, scope, arguments, then under the
-- application row lock: found again, stage, the narrow rule, campus rules.
--
-- Locks only the application. Of the 6b lock order (application, decision,
-- offer, student, counter) it needs only the first: it reads and writes
-- nothing in the decision, offer, student or counter rows, so taking those
-- locks would add hold time and no safety. Every path that reads the grade
-- for enrolment (mark_enrolled) locks the application first and reads the
-- grade from its own locked row, so the two serialise on that lock. If a
-- later rule here reads the decision or the offer, lock them after the
-- application, in the 6b order.
create or replace function public.correct_application_grade(p_application_id uuid, p_grade_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff;
  v_app public.applications;
  v_grade public.admissions_grades;
begin
  v_staff := public._require_admissions_writer();
  if v_staff.role <> 'Manager' then
    raise exception 'Only a Manager can correct an application''s grade';
  end if;
  if p_application_id is null or not public.admissions_application_visible(p_application_id) then
    raise exception 'Application not found';
  end if;
  select * into v_grade from public.admissions_grades where id = p_grade_id and is_active;
  if p_grade_id is null or not found then
    raise exception 'Grade not found';
  end if;
  if v_grade.classification_code is null then
    raise exception 'That grade has no student ID classification yet';
  end if;

  select * into v_app from public.applications where id = p_application_id for update;
  if not found or not public.admissions_grade_visible(v_app.year_group_applied_for) then
    raise exception 'Application not found';
  end if;
  if v_app.stage = 'enrolled' then
    raise exception 'An enrolled application''s grade can''t be corrected';
  end if;
  if public._admissions_grade_id(v_app.year_group_applied_for) is not null then
    raise exception 'This is already a recognised grade; only an unrecognised grade can be corrected';
  end if;
  if v_app.branch_id is not null
     and exists (select 1 from public.admissions_campus_grade_rules r where r.branch_id = v_app.branch_id)
     and not exists (select 1 from public.admissions_campus_grade_rules r
                     where r.branch_id = v_app.branch_id and r.grade_id = v_grade.id) then
    raise exception 'This campus doesn''t accept %', v_grade.name;
  end if;

  update public.applications set year_group_applied_for = v_grade.name
  where id = p_application_id
  returning * into v_app;

  return jsonb_build_object(
    'year_group_applied_for', v_app.year_group_applied_for,
    'grade_band', v_grade.band,
    'stage', v_app.stage
  );
end;
$$;

-- application_grade_corrected, only for a signed-in actor, when the grade
-- changes. The old grade as entered is the one piece of applicant-typed text
-- in an audit payload (DESIGN.md), truncated to 50 characters.
create or replace function public.audit_application_grade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_branch uuid;
begin
  if v_actor is null or old.year_group_applied_for is not distinct from new.year_group_applied_for then
    return null;
  end if;
  v_branch := coalesce(new.branch_id, (select branch_id from public.staff where id = v_actor));
  if v_branch is null then return null; end if;
  insert into public.audit_log (branch_id, actor_id, action, entity_table, entity_id, before, after)
  values (
    v_branch, v_actor, 'application_grade_corrected', 'applications', new.id::text,
    jsonb_build_object('year_group_applied_for', left(old.year_group_applied_for, 50)),
    jsonb_build_object('year_group_applied_for', new.year_group_applied_for,
                       'application_reference', new.application_reference)
  );
  return null;
end;
$$;

create trigger applications_audit_grade
  after update of year_group_applied_for on public.applications
  for each row execute function public.audit_application_grade();

-- ------------------------------------------------------------ grants

revoke execute on function public.audit_application_grade() from public, anon, authenticated;

revoke execute on function public.correct_application_grade(uuid, uuid) from public, anon;
grant execute on function public.correct_application_grade(uuid, uuid) to authenticated, service_role;
