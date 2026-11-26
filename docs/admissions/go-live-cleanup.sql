-- Go-live test data cleanup (admissions, slice 15; plan approved by Eyram
-- 2026-11-26). See docs/admissions/PORT-PLAN.md, "Go-live test data
-- cleanup plan".
--
-- Run by hand by Eyram in the Supabase SQL editor of the HOSTED ERP project,
-- twice (decided 2026-11-26): RUN 1 before cutover, for the test data
-- already there (committed 2026-11-26; the id list below is RUN 1's, kept as
-- the record); RUN 2 on cutover day, after the real host test, for every
-- record made after RUN 1: the hosted full test window (26 to 30 Nov) and
-- the two real host test records (new id list, same script, same guards).
-- The counter bump runs once, after RUN 2; not run yet.
-- Rehearsed locally first. Never part of a migration or seed file. Nobody
-- else runs it against hosted.
--
-- Four parts, each run on its own:
--
--   PART 1  Discovery. Read only. Run each query on its own (select it, then
--           "Run selected"), because the editor shows only the last result.
--           Paste the results back so the id list in PART 2 can be built.
--   PART 2  The id list, at the top of the PART 3 block: the one place you
--           edit. Anything not yet captured is a 'PLACEHOLDER: ...' entry,
--           and the block refuses while any is left.
--   PART 3  The cleanup: one DO block, one transaction. With
--           v_confirm_fingerprint null it is a dry run: it deletes, reports
--           the counts and a fingerprint by raising an exception, and keeps
--           nothing. Paste that fingerprint into v_confirm_fingerprint to
--           commit: it commits only if the same rows would be deleted.
--   PART 4  The counter bump and the verification queries, run last, after
--           the commit run, never inside it.
--
-- Files: every stored file of a target must be deleted through the
-- dashboard (Storage, admissions-documents) BEFORE PART 3; query F1 lists
-- them, and PART 3 refuses while any of them is still in storage.objects.
--
-- Audit rows are never touched. audit_log has no foreign key to any table
-- here (entity_id is plain text) and no table here has a delete trigger, so
-- the deletes neither conflict with nor write audit rows.
--
-- Personal data: the discovery output masks every email address (first
-- character and the first two characters of the domain only) and shows a
-- student name in full only when it is a "ZZ Test" name, so the output can
-- be pasted back safely.


-- ============================================================================
-- PART 1. DISCOVERY (read only)
-- ============================================================================

-- D0. Which project is this? Read before anything else.
--     Hosted: anon_functions = 171 and has_rls_auto_enable = true (the
--     platform's rls_auto_enable()). A fresh local reset shows 170 and false.
select current_database() as database,
       (select count(*) from public.applications) as applications_rows,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')) as anon_functions,
       exists (select 1 from pg_proc where proname = 'rls_auto_enable') as has_rls_auto_enable,
       now() as checked_at;

-- D1. The three switches now, and every time they changed.
select 'now' as row_kind, null::timestamptz as occurred_at,
       jsonb_build_object('public_intake_open', s.public_intake_open,
                          'public_applications_open', s.public_applications_open,
                          'public_leads_open', s.public_leads_open) as value
from public.admissions_settings s
union all
select 'change', a.occurred_at,
       jsonb_build_object('before', a.before, 'after', a.after)
from public.audit_log a
where a.action = 'admissions_settings_changed'
order by row_kind desc, occurred_at;

-- D2. Every enquiry and application.
select a.created_at,
       coalesce(a.application_reference, a.inquiry_reference) as reference,
       a.inquiry_reference, a.application_reference, a.stage, a.id as application_id,
       case when s.full_name ilike 'ZZ Test%' then s.full_name
            else upper(left(s.full_name, 1)) || '. (not a ZZ Test name)' end as student,
       s.student_id, s.family_id,
       (select string_agg(left(g.email, 1) || '***@' || left(split_part(g.email, '@', 2), 2) || '***', ', ' order by g.email)
        from public.guardians g where g.family_id = s.family_id) as guardian_emails_masked,
       (select count(*) from public.applications a2 join public.students s2 on s2.id = a2.student_id
        where s2.family_id = s.family_id and a2.id <> a.id) as other_applications_in_family,
       (select count(*) from public.application_documents d where d.application_id = a.id) as documents,
       (select count(*) from public.application_offers o where o.application_id = a.id) as offers,
       (select string_agg(m.outcome || coalesce(' matched ' || m.matched_application_id::text, ''), '; ')
        from public.application_match_flags m where m.application_id = a.id) as match_flags
from public.applications a
join public.students s on s.id = a.student_id
order by a.created_at;

-- D3. Every stored file in admissions-documents and what it belongs to.
select o.created_at, o.name as storage_path,
       coalesce(ad.application_reference, ad.inquiry_reference) as document_of,
       coalesce(asess.application_reference, asess.inquiry_reference) as upload_session_became,
       r.session_id, r.consumed_at, r.cleaned_at,
       case when d.id is null and r.id is null then 'unknown file' else null end as note
from storage.objects o
left join public.application_documents d on d.storage_path = o.name
left join public.applications ad on ad.id = d.application_id
left join public.application_upload_reservations r on r.storage_path = o.name
left join public.application_upload_sessions us on us.id = r.session_id
left join public.applications asess on asess.id = us.submitted_application_id
where o.bucket_id = 'admissions-documents'
order by o.created_at;

-- D4. Every saved application draft.
select d.created_at, d.id as draft_id, d.expires_at, d.submitted_at,
       coalesce(a.application_reference, a.inquiry_reference) as became,
       case when d.email is null then null
            else left(d.email, 1) || '***@' || left(split_part(d.email, '@', 2), 2) || '***' end as email_masked,
       (select count(*) from public.application_draft_links l where l.draft_id = d.id) as links,
       (select string_agg(l.id::text, ', ') from public.application_draft_links l where l.draft_id = d.id) as link_ids,
       (select count(*) from public.admissions_email_outbox o where o.draft_id = d.id) as emails
from public.application_drafts d
left join public.applications a on a.id = d.submitted_application_id
order by d.created_at;

-- D5. Every lead. "captured by the ERP" means capture_lead wrote its
--     lead:<id> staff alert; an imported lead has no ERP email row at all.
select l.created_at, l.id as lead_id, upper(left(l.name, 1)) || '.' as name_initial,
       case when l.email is null then null
            else left(l.email, 1) || '***@' || left(split_part(l.email, '@', 2), 2) || '***' end as email_masked,
       l.source, l.consent_to_marketing, l.bulk_email_unsubscribed_at,
       case when exists (select 1 from public.admissions_email_outbox o
                         where o.event_key = 'lead:' || l.id and o.kind = 'lead_staff')
            then 'captured by the ERP' else 'no ERP email, likely imported' end as origin,
       (select count(*) from public.admissions_email_outbox o where o.lead_id = l.id) as emails
from public.admissions_leads l
order by l.created_at;

-- D6. Every offer and its links.
select o.sent_at, o.id as offer_id,
       coalesce(a.application_reference, a.inquiry_reference) as reference, a.stage,
       o.response, o.response_source, o.responded_at, o.expires_at, o.link_generation,
       (select string_agg(k.id::text || ' (gen ' || k.generation
                          || case when k.revoked_at is null then '' else ', revoked' end || ')', ', '
                          order by k.issued_at)
        from public.application_offer_links k where k.offer_id = o.id) as link_ids,
       (select count(*) from public.admissions_email_outbox x where x.offer_id = o.id) as emails
from public.application_offers o
join public.applications a on a.id = o.application_id
order by o.sent_at nulls first;

-- D7. Every outbox row, by kind and status, with what it belongs to.
--     Also answers the open "1 email waiting, 2 held back" question.
select x.created_at, x.id as outbox_id, x.kind, x.status, x.attempts, x.sent_at,
       (select string_agg(coalesce(a.application_reference, a.inquiry_reference, a.id::text), ', ')
        from public.applications a where a.id = any(x.application_ids)) as applications,
       cardinality(x.application_ids) as application_ids_count,
       x.draft_id, x.offer_id, x.lead_id,
       case when x.recipient_email is null then null
            else left(x.recipient_email, 1) || '***@' || left(split_part(x.recipient_email, '@', 2), 2) || '***' end as recipient_masked
from public.admissions_email_outbox x
order by x.created_at;

-- D7b. The same rows counted by kind and status.
select kind, status, count(*) from public.admissions_email_outbox
group by kind, status order by kind, status;

-- F1. The stored files PART 3 needs gone first. Run it after the PART 3
--     id list is filled in: paste the same v_refs list here. It lists every
--     document file of a target application and every file reserved by a
--     target's upload session that is still in storage. Back each one up,
--     delete them in the dashboard (Storage, admissions-documents), then
--     run F1 again: it must return no rows.
with refs(ref) as (
  select unnest(array[
    -- RUN 1 (2026-11-26 list). For RUN 2, replace with RUN 2's v_refs.
    'INQ-2026-0001', 'INQ-2026-0002', 'INQ-2026-0003', 'INQ-2026-0004',
    'INQ-2026-0005', 'INQ-2026-0006', 'INQ-2026-0007',
    'APP-2026-0001', 'APP-2026-0002', 'APP-2026-0003', 'APP-2026-0004',
    'APP-2026-0005'
  ]::text[])
), t as (
  select a.id from public.applications a
  where a.inquiry_reference in (select ref from refs)
     or a.application_reference in (select ref from refs)
), paths as (
  select d.storage_path as path, 'document' as kind from public.application_documents d
  where d.application_id in (select id from t)
  union
  select r.storage_path, 'upload reservation' from public.application_upload_reservations r
  join public.application_upload_sessions us on us.id = r.session_id
  where us.submitted_application_id in (select id from t)
)
select p.path, p.kind, o.created_at as stored_at
from paths p join storage.objects o on o.bucket_id = 'admissions-documents' and o.name = p.path
order by p.path;


-- ============================================================================
-- PART 2 AND PART 3. THE ID LIST AND THE CLEANUP (one DO block)
-- ============================================================================
--
-- Step 1: fill in the lists from the discovery output. Replace each
--         PLACEHOLDER entry; use an empty list, '{}', for a kind with
--         nothing to delete. The block refuses while any PLACEHOLDER is left.
-- Step 2: run the block with v_confirm_fingerprint null (dry run). It always
--         ends with an error that starts "DRY RUN OK". Nothing is kept. Read
--         the counts.
-- Step 3: paste the fingerprint from that message into
--         v_confirm_fingerprint and run the block again. That is the only
--         change between the two runs. It commits only if it would delete
--         exactly the same rows; otherwise it refuses and keeps nothing.
--
-- Any refusal or error rolls back everything the block did. The editor may
-- show only "Success. No rows returned" for the commit run: no error means it
-- committed. Part 4 confirms it.

do $cleanup$
declare
  -- ======================== PART 2: THE ID LIST ===========================
  -- RUN 1 COMMITTED on hosted 2026-11-26 with this list (fingerprint
  -- 43b0ea756feb853d92365293e546a04d). Rerunning it refuses at "not found".
  -- Filled 2026-11-26 for RUN 1 (the pre cutover test data) from the hosted
  -- discovery output. Every row D2, D6 and D7 showed is listed; of D5, the
  -- four slice 13 test leads are listed and the three imported leads are
  -- protected below.
  --
  -- RUN 2 (cutover day): every id below is gone, so replace the lists, do
  -- not add to them. Run D2 to D7 again: everything they show except the
  -- three protected leads (and any real lead captured after RUN 1) was made
  -- after RUN 1, in the hosted full test window or by the two real host
  -- test records. List every such reference in v_refs, its drafts, offers,
  -- offer links and outbox rows, and the test leads in v_lead_ids ('{}'
  -- for a kind with none). Keep v_protected_lead_ids as it is.
  -- Then F1 with the new v_refs, the files, the dry run, the commit, exactly
  -- as in RUN 1. Same script, same guards.
  --
  -- Enquiry and application references (INQ-... or APP-...), one per record.
  -- RUN 1: all 12 from D2 (D2 showed 12 rows).
  v_refs text[] := array[
    'INQ-2026-0001',
    'INQ-2026-0002',
    'INQ-2026-0003',
    'APP-2026-0001',
    'INQ-2026-0004',
    'APP-2026-0002',
    'APP-2026-0003',
    'INQ-2026-0005',
    'INQ-2026-0006',
    'INQ-2026-0007',
    'APP-2026-0004',
    'APP-2026-0005'
  ];
  -- Saved application drafts (application_drafts.id). Their links go with
  -- them. RUN 1: none (D4 returned no rows).
  v_draft_ids text[] := '{}';
  -- Offers (application_offers.id) and every one of their links.
  -- RUN 1: the one offer of APP-2026-0005 and its three links (D6).
  v_offer_ids text[] := array[
    '282bf51d-509e-4663-adcf-039e52c0be37'
  ];
  v_offer_link_ids text[] := array[
    '61572bfe-74fc-4c65-ae4a-2ad1585cce20',
    'c3ec9a45-ade6-4bf9-849c-39664fc449ec',
    'ecb4bd7f-8483-4bd3-8ce5-5c3d6e4aa91f'
  ];
  -- Test leads. RUN 1: the four slice 13 hosted test leads (D5, "captured
  -- by the ERP").
  v_lead_ids text[] := array[
    '88f6d4fc-7b3b-4e67-a7b6-b749152a3b38',
    'db02ef82-1770-4a8c-aa95-9c562bac74af',
    'beb25834-6c29-4fcf-8138-80d641dbdf4a',
    '0270d733-7ffc-47ed-a6dd-5401b5d2f138'
  ];
  -- Every outbox row of the targets (D7): confirmations, staff alerts,
  -- draft_resume, offer, offer_staff, pdf_gate and lead_staff rows.
  -- RUN 1: all 23 rows D7 showed (D7b totals 23).
  v_outbox_ids text[] := array[
    -- INQ-2026-0005
    'ccea635b-829e-4672-a934-74ed9183fc51',
    'ec943a72-cf37-40fd-98c4-6d2e6465b202',
    -- INQ-2026-0006
    'c3561bc1-83c1-45c9-bef4-f982becd8fb4',
    'f7a6be23-fcdc-43a8-971c-0b89ffdb9e40',
    -- INQ-2026-0007
    '02832851-1dfe-4748-b661-3a6b8d19dd2d',
    '1a9ec903-503b-4519-9ba2-a1500bb5698c',
    -- APP-2026-0004
    '627124a2-41b2-4e52-b58b-32fb67549014',
    'ef64def6-0c84-4745-900d-41ac2bc0bc62',
    -- lead 88f6d4fc
    '1a181657-e6f3-4690-853b-01f660483867',
    'ce65fd8f-3e63-4c57-a8cb-8176c7777ede',
    -- lead db02ef82
    '75b5b0b1-8114-4a90-bcae-1487bc226a1f',
    'c376dedb-9509-484c-8715-af2030357636',
    -- lead beb25834
    'db28cedd-6a2e-4de2-bd8c-469ada65575c',
    '37dad528-51cf-4c06-8d46-5880d473b038',
    -- lead 0270d733
    '270b589e-c073-46a4-9b4f-f257eb2f0990',
    '83c58013-3ff1-4ca7-b004-fc4a2f631a66',
    -- APP-2026-0005 confirmations and staff alert
    '575d0936-7119-4b75-8467-fc16ea21cef3',
    '57cd8901-96e2-469e-adbe-83df2745deb7',
    '8968e126-a2ee-448f-9f5d-ff1812066808',
    -- APP-2026-0005 offer emails (offer 282bf51d)
    'db2ab35e-5d57-41d7-9e6e-168cf6957421',
    'dbec88f3-ea77-4e69-8ff4-bc5d6990f9d3',
    '34c36d1d-2b1b-4cfb-bd12-a7a6a3875a48',
    'e0f9cec9-10de-47c1-9e2e-145bd298b064'
  ];
  -- The imported real leads, from D5 ("no ERP email, likely imported").
  -- Never deleted: the block refuses if any of these is listed above, or is
  -- missing. Keep these three for RUN 2.
  v_protected_lead_ids text[] := array[
    '1de8c442-ae64-485f-9a98-721b9d73a558',
    '829bda67-4bd3-46d8-9e6a-76c8e1ade09a',
    '66d63190-413a-421f-b7b2-3d7be5b97c60'
  ];
  -- The date the ERP started taking leads on hosted (slice 13 rollout).
  -- Every test lead must be on or after it; imported leads are older.
  v_lead_capture_start constant timestamptz := '2026-10-22 00:00:00+00';
  -- ======================== THE COMMIT SWITCH =============================
  -- null = dry run. Paste the fingerprint from the dry run message to commit.
  v_confirm_fingerprint text := null;
  -- ========================================================================

  v_all text[];
  v_bad text;
  v_n integer;
  v_apps uuid[];
  v_drafts uuid[];
  v_offers uuid[];
  v_offer_links uuid[];
  v_leads uuid[];
  v_outbox uuid[];
  v_protected uuid[];
  v_families uuid[];
  v_students uuid[];
  v_guardians uuid[];
  v_documents uuid[];
  v_sessions uuid[];
  v_reservations uuid[];
  v_draft_links uuid[];
  v_paths text[];
  v_derived uuid[];
  v_fingerprint text;
  v_counts jsonb := '{}'::jsonb;
begin
  -- 1. No placeholder left.
  v_all := v_refs || v_draft_ids || v_offer_ids || v_offer_link_ids || v_lead_ids
           || v_outbox_ids || v_protected_lead_ids;
  select string_agg(x, ' | ') into v_bad from unnest(v_all) x where x ilike 'PLACEHOLDER%';
  if v_bad is not null then
    raise exception 'REFUSED: the id list still has placeholders: %', v_bad;
  end if;
  if (select count(*) from unnest(v_refs) r) <> (select count(distinct r) from unnest(v_refs) r) then
    raise exception 'REFUSED: a reference is listed twice';
  end if;

  v_drafts := v_draft_ids::uuid[];
  v_offers := v_offer_ids::uuid[];
  v_offer_links := v_offer_link_ids::uuid[];
  v_leads := v_lead_ids::uuid[];
  v_outbox := v_outbox_ids::uuid[];
  v_protected := v_protected_lead_ids::uuid[];

  -- 2. Both intake switches closed (the lead switch is not part of this).
  if (select count(*) from public.admissions_settings) <> 1
     or exists (select 1 from public.admissions_settings
                where public_intake_open or public_applications_open) then
    raise exception 'REFUSED: close the enquiry and application switches first';
  end if;

  -- 3. Every listed reference and id exists, exactly once.
  select string_agg(r, ', ') into v_bad from unnest(v_refs) r
  where (select count(*) from public.applications a
         where a.inquiry_reference = r or a.application_reference = r) <> 1;
  if v_bad is not null then
    raise exception 'REFUSED: not found exactly once in applications: %', v_bad;
  end if;
  v_apps := array(select a.id from public.applications a
                  where a.inquiry_reference = any(v_refs) or a.application_reference = any(v_refs));
  if cardinality(v_apps) <> cardinality(v_refs) then
    raise exception 'REFUSED: two listed references name the same application';
  end if;

  select string_agg(x::text, ', ') into v_bad from unnest(v_drafts) x
  where not exists (select 1 from public.application_drafts d where d.id = x);
  if v_bad is not null then raise exception 'REFUSED: draft not found: %', v_bad; end if;
  select string_agg(x::text, ', ') into v_bad from unnest(v_offers) x
  where not exists (select 1 from public.application_offers o where o.id = x);
  if v_bad is not null then raise exception 'REFUSED: offer not found: %', v_bad; end if;
  select string_agg(x::text, ', ') into v_bad from unnest(v_offer_links) x
  where not exists (select 1 from public.application_offer_links k where k.id = x);
  if v_bad is not null then raise exception 'REFUSED: offer link not found: %', v_bad; end if;
  select string_agg(x::text, ', ') into v_bad from unnest(v_leads) x
  where not exists (select 1 from public.admissions_leads l where l.id = x);
  if v_bad is not null then raise exception 'REFUSED: lead not found: %', v_bad; end if;
  select string_agg(x::text, ', ') into v_bad from unnest(v_outbox) x
  where not exists (select 1 from public.admissions_email_outbox o where o.id = x);
  if v_bad is not null then raise exception 'REFUSED: outbox row not found: %', v_bad; end if;
  select string_agg(x::text, ', ') into v_bad from unnest(v_protected) x
  where not exists (select 1 from public.admissions_leads l where l.id = x);
  if v_bad is not null then raise exception 'REFUSED: protected lead not found: %', v_bad; end if;

  -- 4. Real leads: two locks.
  select string_agg(x::text, ', ') into v_bad from unnest(v_leads) x where x = any(v_protected);
  if v_bad is not null then
    raise exception 'REFUSED: an imported real lead is on the delete list: %', v_bad;
  end if;
  select string_agg(l.id::text, ', ') into v_bad from public.admissions_leads l
  where l.id = any(v_leads)
    and (l.created_at < v_lead_capture_start
         or not exists (select 1 from public.admissions_email_outbox o
                        where o.event_key = 'lead:' || l.id and o.kind = 'lead_staff'));
  if v_bad is not null then
    raise exception 'REFUSED: lead not captured by the ERP (imported, or older than %): %',
      v_lead_capture_start, v_bad;
  end if;

  -- 5. Nothing enrolled, no student ID used, no accepted offer.
  select string_agg(coalesce(a.application_reference, a.inquiry_reference), ', ') into v_bad
  from public.applications a join public.students s on s.id = a.student_id
  where a.id = any(v_apps) and (a.stage = 'enrolled' or s.student_id is not null);
  if v_bad is not null then
    raise exception 'REFUSED: enrolled or holding a student ID, decide separately: %', v_bad;
  end if;
  select string_agg(coalesce(a.application_reference, a.inquiry_reference), ', ') into v_bad
  from public.application_offers o join public.applications a on a.id = o.application_id
  where (o.application_id = any(v_apps) or o.id = any(v_offers)) and o.response = 'accepted';
  if v_bad is not null then
    raise exception 'REFUSED: offer on % is accepted: correct it to declined first, then rerun', v_bad;
  end if;

  -- 6. Families: every application in a target family is a target, and no
  --    target guardian email appears in any other family.
  v_families := array(select distinct s.family_id from public.students s
                      join public.applications a on a.student_id = s.id where a.id = any(v_apps));
  select string_agg(distinct coalesce(a.application_reference, a.inquiry_reference, a.id::text), ', ')
    into v_bad
  from public.applications a join public.students s on s.id = a.student_id
  where s.family_id = any(v_families) and not (a.id = any(v_apps));
  if v_bad is not null then
    raise exception 'REFUSED: a target family also holds an application not on the list: %', v_bad;
  end if;
  select string_agg(distinct left(g2.email, 2) || '***', ', ') into v_bad
  from public.guardians g1 join public.guardians g2
    on lower(g2.email) = lower(g1.email) and not (g2.family_id = any(v_families))
  where g1.family_id = any(v_families) and g1.email is not null;
  if v_bad is not null then
    raise exception 'REFUSED: a target guardian email also appears in another family: %', v_bad;
  end if;
  select string_agg(s.student_id, ', ') into v_bad from public.students s
  where s.family_id = any(v_families) and s.student_id is not null;
  if v_bad is not null then
    raise exception 'REFUSED: a target family holds a student with a student ID, decide separately: %', v_bad;
  end if;
  select string_agg(s.id::text, ', ') into v_bad from public.students s
  where s.family_id = any(v_families)
    and not exists (select 1 from public.applications a where a.student_id = s.id);
  if v_bad is not null then
    raise exception 'REFUSED: a target family holds a student with no application, decide separately: %', v_bad;
  end if;
  v_students := array(select s.id from public.students s where s.family_id = any(v_families));
  v_guardians := array(select g.id from public.guardians g where g.family_id = any(v_families));

  -- 7. No match flag on another application points at a target.
  select string_agg(f.application_id::text, ', ') into v_bad from public.application_match_flags f
  where f.matched_application_id = any(v_apps) and not (f.application_id = any(v_apps));
  if v_bad is not null then
    raise exception 'REFUSED: a match flag on another application points at a target: %', v_bad;
  end if;

  -- 8. Listed equals derived, both ways.
  v_derived := array(select o.id from public.application_offers o where o.application_id = any(v_apps));
  if not (v_derived @> v_offers and v_offers @> v_derived) then
    raise exception 'REFUSED: offers listed % but the targets have %', v_offers, v_derived;
  end if;
  v_derived := array(select k.id from public.application_offer_links k where k.offer_id = any(v_offers));
  if not (v_derived @> v_offer_links and v_offer_links @> v_derived) then
    raise exception 'REFUSED: offer links listed % but the offers have %', v_offer_links, v_derived;
  end if;
  select string_agg(d.id::text, ', ') into v_bad from public.application_drafts d
  where (d.submitted_application_id = any(v_apps) and not (d.id = any(v_drafts)))
     or (d.id = any(v_drafts) and d.submitted_application_id is not null
         and not (d.submitted_application_id = any(v_apps)));
  if v_bad is not null then
    raise exception 'REFUSED: draft list and target applications disagree: %', v_bad;
  end if;
  v_derived := array(select o.id from public.admissions_email_outbox o
                     where o.application_ids && v_apps or o.draft_id = any(v_drafts)
                        or o.offer_id = any(v_offers) or o.lead_id = any(v_leads));
  if not (v_derived @> v_outbox and v_outbox @> v_derived) then
    raise exception 'REFUSED: outbox rows listed but not derived: %; derived but not listed: %',
      array(select unnest(v_outbox) except select unnest(v_derived)),
      array(select unnest(v_derived) except select unnest(v_outbox));
  end if;
  select string_agg(o.id::text, ', ') into v_bad from public.admissions_email_outbox o
  where o.id = any(v_outbox)
    and (o.status = 'sending'
         or exists (select 1 from unnest(o.application_ids) x where not (x = any(v_apps))));
  if v_bad is not null then
    raise exception 'REFUSED: outbox row being sent now, or naming a non target application: %', v_bad;
  end if;

  -- 9. Files: none left in storage for any target document or reservation.
  v_documents := array(select d.id from public.application_documents d where d.application_id = any(v_apps));
  v_sessions := array(select us.id from public.application_upload_sessions us
                      where us.submitted_application_id = any(v_apps));
  v_reservations := array(select r.id from public.application_upload_reservations r
                          where r.session_id = any(v_sessions));
  v_paths := array(select d.storage_path from public.application_documents d where d.id = any(v_documents)
                   union
                   select r.storage_path from public.application_upload_reservations r
                   where r.id = any(v_reservations));
  select count(*), min(o.name) into v_n, v_bad from storage.objects o
  where o.bucket_id = 'admissions-documents' and o.name = any(v_paths);
  if v_n > 0 then
    raise exception 'REFUSED: % target file(s) still in storage, for example %. Delete them in the dashboard first (query F1)',
      v_n, v_bad;
  end if;
  v_draft_links := array(select l.id from public.application_draft_links l where l.draft_id = any(v_drafts));

  -- The fingerprint: every row id this run deletes, sorted.
  select md5(string_agg(x, ',' order by x)) into v_fingerprint from (
    select 'application:' || unnest(v_apps)::text x
    union all select 'draft:' || unnest(v_drafts)::text
    union all select 'draft_link:' || unnest(v_draft_links)::text
    union all select 'offer:' || unnest(v_offers)::text
    union all select 'offer_link:' || unnest(v_offer_links)::text
    union all select 'lead:' || unnest(v_leads)::text
    union all select 'outbox:' || unnest(v_outbox)::text
    union all select 'document:' || unnest(v_documents)::text
    union all select 'session:' || unnest(v_sessions)::text
    union all select 'reservation:' || unnest(v_reservations)::text
    union all select 'student:' || unnest(v_students)::text
    union all select 'guardian:' || unnest(v_guardians)::text
    union all select 'family:' || unnest(v_families)::text
  ) f;

  -- Deletes, in key order. Each count must match what was derived.
  delete from public.admissions_email_outbox where id = any(v_outbox);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_outbox) then raise exception 'REFUSED: outbox deleted %, expected %', v_n, cardinality(v_outbox); end if;
  v_counts := v_counts || jsonb_build_object('admissions_email_outbox', v_n);

  delete from public.application_offer_links where id = any(v_offer_links);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_offer_links) then raise exception 'REFUSED: offer links deleted %, expected %', v_n, cardinality(v_offer_links); end if;
  v_counts := v_counts || jsonb_build_object('application_offer_links', v_n);

  delete from public.application_offers where id = any(v_offers);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_offers) then raise exception 'REFUSED: offers deleted %, expected %', v_n, cardinality(v_offers); end if;
  v_counts := v_counts || jsonb_build_object('application_offers', v_n);

  delete from public.application_draft_links where id = any(v_draft_links);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_draft_links) then raise exception 'REFUSED: draft links deleted %, expected %', v_n, cardinality(v_draft_links); end if;
  v_counts := v_counts || jsonb_build_object('application_draft_links', v_n);

  delete from public.application_drafts where id = any(v_drafts);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_drafts) then raise exception 'REFUSED: drafts deleted %, expected %', v_n, cardinality(v_drafts); end if;
  v_counts := v_counts || jsonb_build_object('application_drafts', v_n);

  delete from public.admissions_leads where id = any(v_leads);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_leads) then raise exception 'REFUSED: leads deleted %, expected %', v_n, cardinality(v_leads); end if;
  v_counts := v_counts || jsonb_build_object('admissions_leads', v_n);

  delete from public.application_documents where id = any(v_documents);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_documents) then raise exception 'REFUSED: documents deleted %, expected %', v_n, cardinality(v_documents); end if;
  v_counts := v_counts || jsonb_build_object('application_documents', v_n);

  delete from public.application_upload_reservations where id = any(v_reservations);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_reservations) then raise exception 'REFUSED: reservations deleted %, expected %', v_n, cardinality(v_reservations); end if;
  v_counts := v_counts || jsonb_build_object('application_upload_reservations', v_n);

  delete from public.application_upload_sessions where id = any(v_sessions);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_sessions) then raise exception 'REFUSED: upload sessions deleted %, expected %', v_n, cardinality(v_sessions); end if;
  v_counts := v_counts || jsonb_build_object('application_upload_sessions', v_n);

  -- Rows that go with an application by cascade, counted for the report.
  v_counts := v_counts || jsonb_build_object(
    'with_their_application', jsonb_build_object(
      'application_notes', (select count(*) from public.application_notes x where x.application_id = any(v_apps)),
      'application_decisions', (select count(*) from public.application_decisions x where x.application_id = any(v_apps)),
      'application_health_info', (select count(*) from public.application_health_info x where x.application_id = any(v_apps)),
      'application_emergency_contacts', (select count(*) from public.application_emergency_contacts x where x.application_id = any(v_apps)),
      'application_match_flags', (select count(*) from public.application_match_flags x where x.application_id = any(v_apps))));

  delete from public.applications where id = any(v_apps);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_apps) then raise exception 'REFUSED: applications deleted %, expected %', v_n, cardinality(v_apps); end if;
  v_counts := v_counts || jsonb_build_object('applications', v_n);

  delete from public.students where id = any(v_students);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_students) then raise exception 'REFUSED: students deleted %, expected %', v_n, cardinality(v_students); end if;
  v_counts := v_counts || jsonb_build_object('students', v_n);

  delete from public.families where id = any(v_families);
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_families) then raise exception 'REFUSED: families deleted %, expected %', v_n, cardinality(v_families); end if;
  v_counts := v_counts || jsonb_build_object('families', v_n, 'guardians_with_their_family', cardinality(v_guardians));

  -- After: nothing listed remains, the protected leads are all still there.
  if exists (select 1 from public.applications a
             where a.inquiry_reference = any(v_refs) or a.application_reference = any(v_refs))
     or exists (select 1 from public.guardians g where g.id = any(v_guardians)) then
    raise exception 'REFUSED: a target is still present after the deletes';
  end if;
  if (select count(*) from public.admissions_leads l where l.id = any(v_protected)) <> cardinality(v_protected) then
    raise exception 'REFUSED: a protected lead would be lost';
  end if;

  if v_confirm_fingerprint is null then
    raise exception 'DRY RUN OK, nothing was kept. fingerprint=% counts=%', v_fingerprint, v_counts;
  end if;
  if v_confirm_fingerprint <> v_fingerprint then
    raise exception 'REFUSED: fingerprint % does not match this run (%). Something changed since the dry run; run the dry run again',
      v_confirm_fingerprint, v_fingerprint;
  end if;
  raise notice 'COMMITTED. fingerprint=% counts=%', v_fingerprint, v_counts;
end
$cleanup$;


-- ============================================================================
-- PART 4. AFTER THE COMMIT RUN (run each on its own)
-- ============================================================================

-- V1. Run D2, D4, D5, D6 and D7 again: no target row remains, and the
--     imported real leads are still listed (D5, "no ERP email").
-- V2. Run F1 again with the same list: no rows.
-- V3. Switches still closed: run D1.
-- V4. In the staff app, the application list shows no test record and the
--     Audit Log page still loads with the kept rows.

-- COUNTER BUMP. Run only after RUN 2's commit run and V1 to V4, not after
-- RUN 1. Separate from
-- the cleanup on purpose, and commented out so running the whole file can
-- never reach it: select the four lines below (without the leading "-- ")
-- and run them on their own. It only ever raises a counter, so running it
-- twice is harmless. The next real references are INQ-2026-0101 and
-- APP-2026-0101 (or higher, if a counter is already past 101). The keys are
-- the 2026 counters: if cutover slips into 2027, stop and ask first.
--
-- insert into public.admissions_reference_counters as c (key, next_value)
-- values ('INQ-2026', 101), ('APP-2026', 101)
-- on conflict (key) do update set next_value = greatest(c.next_value, 101)
-- returning key, next_value;
