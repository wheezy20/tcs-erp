-- Fixes from real onboarding-review usage (the priority "blind review" bug
-- itself is frontend-only — no schema change — see docs/JOURNAL.md).
--
-- 1. "ID Copy" -> "National ID", matching employees.national_id's own
--    naming. Renaming a live catalog row + its document_type value.
--
-- This failed against production on first attempt (rolled back cleanly,
-- transactional) with a check constraint violation on the rename UPDATE.
-- The first fix attempt (widen the constraint, then rename) was still
-- wrong: the "widened" constraint dropped 'ID Copy' from the allowed list
-- entirely (replaced by 'National ID'), so *adding* that constraint
-- itself fails immediately against any pre-existing 'ID Copy' row —
-- Postgres validates a new CHECK against every existing row unless
-- declared NOT VALID, and swapping one allowed value for another is
-- still not a superset of what's already there. There is no ordering of
-- "swap the constraint" + "rename the data" that works in one step; it's
-- an expand/migrate/contract, same as any live enum-value rename:
--   1. Expand the constraint to accept BOTH 'ID Copy' and 'National ID'
--      at once (a true superset of old and new).
--   2. Rename the data — now legal under the expanded constraint either
--      way.
--   3. Contract the constraint back down, dropping 'ID Copy' now that no
--      row uses it.
-- Neither bug was caught by a fresh `db reset` locally, because every
-- employee_documents row used in testing was inserted after all
-- migrations had already applied — the constraint was already in its
-- final state by the time anything named 'ID Copy' existed, so this
-- transition was never actually exercised. Verified this time against a
-- local DB seeded with a real pre-existing 'ID Copy' row before this
-- migration runs (via `supabase migration up`, which applies a single
-- pending migration the same way `db push` does, rather than a full
-- reset).
alter table public.employee_documents drop constraint employee_documents_document_type_check;
alter table public.employee_documents add constraint employee_documents_document_type_check
  check (document_type in (
    'ID Copy', 'National ID', 'SSNIT Card', 'TIN Copy', 'Academic Certs', 'Passport Photos',
    'Guarantor Form', 'Medical Clearance', 'Background Check', 'Other'
  ));

update public.onboarding_checklist_items set name = 'National ID' where name = 'ID Copy';
update public.employee_documents set document_type = 'National ID' where document_type = 'ID Copy';

alter table public.employee_documents drop constraint employee_documents_document_type_check;
alter table public.employee_documents add constraint employee_documents_document_type_check
  check (document_type in (
    'National ID', 'SSNIT Card', 'TIN Copy', 'Academic Certs', 'Passport Photos',
    'Guarantor Form', 'Medical Clearance', 'Background Check', 'Other'
  ));

-- 2. Gender becomes a Male/Female dropdown on the public onboarding form
--    specifically (the anon-writable path gets the stricter check;
--    employees.gender itself, edited by HR through HrDetailsSection,
--    stays free text — out of scope here, see docs/DESIGN.md).
alter table public.employee_onboarding_submissions
  add constraint employee_onboarding_submissions_gender_check
  check (gender is null or gender in ('Male', 'Female'));

-- 3. National ID / SSNIT Card / TIN Copy: completing the checklist item
--    now accepts EITHER a document already on file OR a typed number —
--    some people have lost the physical card but still know the number.
--    Which one was actually provided is recorded, not inferred.
alter table public.onboarding_checklist_items
  add column accepts_number_in_lieu boolean not null default false;

update public.onboarding_checklist_items
set accepts_number_in_lieu = true
where name in ('National ID', 'SSNIT Card', 'TIN Copy');

alter table public.employee_onboarding_tasks
  add column provided_via text check (provided_via in ('document', 'number')),
  add column provided_number text;

-- toggle_onboarding_task(): argument list changed (two new trailing
-- optional params) -> drop before recreate.
drop function if exists public.toggle_onboarding_task(uuid, boolean);

create or replace function public.toggle_onboarding_task(
  p_task_id uuid,
  p_completed boolean,
  p_provided_via text default null,
  p_provided_number text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_derived boolean;
  v_accepts_number boolean;
  v_item_name text;
  v_employee_id uuid;
  v_number text;
begin
  perform public.require_finance_writer();

  select i.is_derived, i.accepts_number_in_lieu, i.name, t.employee_id
    into v_is_derived, v_accepts_number, v_item_name, v_employee_id
  from public.employee_onboarding_tasks t
  join public.onboarding_checklist_items i on i.id = t.checklist_item_id
  where t.id = p_task_id;

  if v_employee_id is null then
    raise exception 'Onboarding task not found.';
  end if;
  if v_is_derived then
    raise exception 'This item is tracked automatically and can''t be toggled by hand.';
  end if;

  -- Unchecking always clears how it was satisfied — if it's redone later,
  -- that's a fresh choice of document-or-number, not a stale leftover.
  if not p_completed then
    update public.employee_onboarding_tasks
    set completed = false, completed_at = null, completed_by = null,
        provided_via = null, provided_number = null
    where id = p_task_id;
    return;
  end if;

  if v_accepts_number then
    if p_provided_via is null or p_provided_via not in ('document', 'number') then
      raise exception 'Choose whether this was satisfied by a document or a typed number.';
    end if;

    if p_provided_via = 'number' then
      v_number := nullif(trim(p_provided_number), '');
      if v_number is null then
        raise exception 'Type the number, or choose "document" if one was uploaded instead.';
      end if;

      -- Bonus of recording it here: HR doesn't have to type the same
      -- number a second time into HR Details.
      update public.employees
      set national_id = case when v_item_name = 'National ID' then v_number else national_id end,
          ssnit_number = case when v_item_name = 'SSNIT Card' then v_number else ssnit_number end,
          tin_number = case when v_item_name = 'TIN Copy' then v_number else tin_number end
      where id = v_employee_id;
    else
      if not exists (
        select 1 from public.employee_documents
        where employee_id = v_employee_id and document_type = v_item_name
      ) then
        raise exception 'No % document is on file yet for this employee — upload one first, or record the number instead.', v_item_name;
      end if;
    end if;

    update public.employee_onboarding_tasks
    set completed = true, completed_at = now(), completed_by = auth.uid(),
        provided_via = p_provided_via,
        provided_number = case when p_provided_via = 'number' then v_number else null end
    where id = p_task_id;
  else
    update public.employee_onboarding_tasks
    set completed = true, completed_at = now(), completed_by = auth.uid()
    where id = p_task_id;
  end if;
end;
$$;

grant execute on function public.toggle_onboarding_task(uuid, boolean, text, text)
  to authenticated, service_role;
