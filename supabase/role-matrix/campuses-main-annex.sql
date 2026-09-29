-- Role matrix for slice 1 (campuses, docs/admissions/PORT-PLAN.md). No RLS or
-- RPC change: proves two branch rows don't change who reads branches, and that
-- the database's own branch pickers resolve to Main (the oldest row) once
-- Annex exists.
-- Run: npx supabase db reset && ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/campuses-main-annex.sql
--
-- Named for the seed decision it verifies (D-1a), not a migration: slice 1
-- has no migration.
--
-- The no-op UPDATE in each setup writes a new version of Main's tuple at a
-- later line pointer (a HOT update still does), so a sequential scan now
-- reaches Annex first and an unordered `limit 1` would return Annex. That is
-- what gives the handle_new_staff_signup and post_journal_entry probes teeth:
-- they fail if either function ever loses its `order by created_at`. The
-- oldest-branch probe orders explicitly, so for it the UPDATE only documents
-- the precondition; it's a sanity check of the rule getSchoolBranchId() uses.

-- probe: branches select (Main and Annex both visible)
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
do $$ begin
  if (select count(*) from public.branches where name in ('Main', 'Annex')) <> 2 then
    raise exception 'expected Main and Annex both visible';
  end if;
end $$;

-- probe: oldest-branch rule resolves to Main
-- expect: Attendant,Manager,Accountant,Auditor,Admissions Officer
update public.branches set default_low_stock_threshold = default_low_stock_threshold where name = 'Main';
-- as role:
do $$ begin
  if (select name from public.branches order by created_at asc limit 1) is distinct from 'Main' then
    raise exception 'oldest branch is not Main';
  end if;
end $$;

-- probe: handle_new_staff_signup puts a new staff row on Main
-- expect: Attendant,Manager,Accountant,Auditor
update public.branches set default_low_stock_threshold = default_low_stock_threshold where name = 'Main';
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('9e000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'probe-campus@tcs.test', '{"name":"Probe","role":"Attendant"}');
-- as role:
do $$ begin
  if (select b.name from public.staff s join public.branches b on b.id = s.branch_id
      where s.id = '9e000000-0000-0000-0000-000000000001') is distinct from 'Main' then
    raise exception 'new staff not on Main';
  end if;
end $$;

-- probe: post_journal_entry posts to Main
-- expect: Manager,Accountant
update public.branches set default_low_stock_threshold = default_low_stock_threshold where name = 'Main';
-- as role:
do $$
declare v public.journal_entries;
begin
  v := public.post_journal_entry(current_date, 'campus probe', '',
    jsonb_build_array(
      jsonb_build_object('account_id', (select id from public.accounts where code = '1000'), 'debit', 1, 'credit', 0, 'description', ''),
      jsonb_build_object('account_id', (select id from public.accounts where code = '3000'), 'debit', 0, 'credit', 1, 'description', '')),
    null);
  if (select name from public.branches where id = v.branch_id) is distinct from 'Main' then
    raise exception 'journal entry not on Main';
  end if;
end $$;
