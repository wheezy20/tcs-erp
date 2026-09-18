-- Receipts bucket: private + role-scoped RLS (TCS ERP, security fix from
-- a walkthrough finding).
--
-- The `receipts` bucket has been `public = true` since it was created
-- (20260802100000), from before this app had any auth/RLS at all.
-- 20260803120000 tightened storage *writes* to `authenticated` only but
-- explicitly left `public` alone. That's the actual bug: a `public = true`
-- Supabase Storage bucket serves downloads through an endpoint that
-- bypasses `storage.objects` RLS entirely, so the write policy's SELECT
-- coverage was always dead code — every receipt has been readable by
-- anyone with the (guessable-format, `<uuid>.<ext>`) object path, no
-- session required, via `getPublicUrl()`'s plain unsigned URL.
--
-- Fix: flip the bucket private, and replace the one blanket
-- `for all to authenticated` policy with command-scoped policies mirroring
-- `expenses_select`/`expenses_insert`/`expenses_update`/`expenses_delete`
-- exactly (same role sets, same has_role() predicate) — a receipt is
-- exactly as sensitive as the expense row it belongs to. Reads
-- (Manager/Accountant/Auditor) now happen through
-- `supabase.storage.from('receipts').createSignedUrls(paths, 3600)` from
-- the frontend's own authenticated client (expenses-store.ts) — Storage's
-- signed-URL generation is itself gated by this SELECT policy, so the
-- client can only ever get a signed URL for a receipt it's actually
-- RLS-permitted to read. No edge function needed: that's reserved in this
-- codebase for operations that genuinely require the service_role key
-- (see supabase/functions/invite-staff), which signing a URL the caller
-- already has read access to does not.
--
-- No data migration needed — existing objects keep their paths; only how
-- they're reached changes.

update storage.buckets set public = false where id = 'receipts';

drop policy if exists "receipts_full_access" on storage.objects;
drop policy if exists "receipts_staff_access" on storage.objects;

create policy "receipts_select" on storage.objects
for select
to authenticated
using (bucket_id = 'receipts' and public.has_role(array['Manager', 'Accountant', 'Auditor']));

create policy "receipts_insert" on storage.objects
for insert
to authenticated
with check (bucket_id = 'receipts' and public.has_role(array['Manager', 'Accountant']));

create policy "receipts_update" on storage.objects
for update
to authenticated
using (bucket_id = 'receipts' and public.has_role(array['Manager', 'Accountant']))
with check (bucket_id = 'receipts' and public.has_role(array['Manager', 'Accountant']));

create policy "receipts_delete" on storage.objects
for delete
to authenticated
using (bucket_id = 'receipts' and public.has_role(array['Manager', 'Accountant']));
