-- Session 13: Journal Entries & General Ledger. Spec section 10, item 13:
-- "the core double-entry mechanics, manual journal entry capability, the
-- ledger view, the posting function every automated entry will call. No
-- automation yet, this session is the engine, not what drives it." Builds
-- on Session 12's Chart of Accounts (public.accounts).
--
-- ================================================== branch-scoped, unlike accounts
--
-- accounts (Session 12) was deliberately NOT branch-scoped — one company,
-- one ledger structure. journal_entries is the opposite case: each row is
-- an individual dated transactional record, the same class of table
-- CLAUDE.md's "branch_id everywhere" rule targets (products, invoices,
-- sales, expenses, ...), so branch_id lives on the entry header here, not
-- on the account definitions it posts against.
--
-- ================================================== the balance invariant
--
-- "structurally impossible to post an unbalanced entry" needs more than a
-- per-row CHECK constraint — Postgres CHECK constraints can't see sibling
-- rows, and "debits = credits" is a property of the whole entry, not any
-- one line. The real enforcement is a deferred constraint trigger
-- (check_journal_entry_balanced() below): it fires after every insert/
-- update/delete on journal_lines but doesn't actually run until the
-- transaction is about to commit, so a multi-statement insert of an
-- entry's lines can happen one at a time and only gets validated once, as
-- a whole, right before commit. This is the backstop that makes the
-- invariant real even against a direct/bypassing multi-row write, not just
-- against post_journal_entry() being well-behaved. post_journal_entry()
-- itself ALSO validates the balance before writing anything, purely for a
-- clear, specific error message ("Entry is not balanced: debits X do not
-- equal credits Y") instead of the trigger's more generic one — same
-- "RPC check is a UX nicety, the real boundary is the constraint/RLS"
-- relationship established everywhere else in this build.
create table public.journal_entry_number_counters (
  year_month text primary key,
  last_number integer not null default 0 check (last_number >= 0)
);

-- id is text ("JE-YYMM####"), not uuid — same reasoning as invoices.id/
-- sales.id: a journal entry number is a human-facing sequential business
-- identifier (shown in the ledger, referenced by reversing entries), not a
-- surrogate key.
create table public.journal_entries (
  id text primary key,
  branch_id uuid not null references public.branches (id) on delete restrict,
  entry_date date not null,
  description text not null,
  reference text,
  -- Self-reference for reversal traceability (reverse_journal_entry()
  -- below sets this). Nullable: only reversing entries have one.
  reverses_entry_id text references public.journal_entries (id) on delete restrict,
  created_by uuid not null references public.staff (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now()
);

create index journal_entries_entry_date_idx on public.journal_entries (entry_date);
create index journal_entries_branch_id_idx on public.journal_entries (branch_id);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  entry_id text not null references public.journal_entries (id) on delete restrict,
  position integer not null default 0,
  account_id uuid not null references public.accounts (id) on delete restrict,
  debit numeric(14, 2) not null default 0,
  credit numeric(14, 2) not null default 0,
  description text not null default '',
  created_at timestamptz not null default now(),
  constraint journal_lines_debit_not_negative check (debit >= 0),
  constraint journal_lines_credit_not_negative check (credit >= 0),
  -- A single line is either a debit or a credit, never both, and never
  -- neither (a zero-amount line is a do-nothing line, not a valid entry
  -- row).
  constraint journal_lines_one_sided check (not (debit > 0 and credit > 0)),
  constraint journal_lines_has_amount check (debit > 0 or credit > 0)
);

create index journal_lines_entry_id_idx on public.journal_lines (entry_id);
create index journal_lines_account_id_idx on public.journal_lines (account_id);

-- Same identity-forcing pattern as accounts.created_by/customer_discounts.
-- created_by: force from auth.uid() whenever there's a real authenticated
-- caller, leave alone only for the superuser/seed context.
create or replace function public.set_journal_entry_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger journal_entries_set_created_by
before insert on public.journal_entries
for each row execute function public.set_journal_entry_created_by();

-- The real, structural balance invariant — see the header comment above.
-- Fires once per affected row but all firings are deferred to just before
-- commit, by which point every line of a given entry has already been
-- inserted, so re-summing on each firing is redundant but never wrong.
create or replace function public.check_journal_entry_balanced()
returns trigger
language plpgsql
as $$
declare
  v_entry_id text := coalesce(new.entry_id, old.entry_id);
  v_diff numeric;
begin
  select coalesce(sum(debit), 0) - coalesce(sum(credit), 0)
  into v_diff
  from public.journal_lines
  where entry_id = v_entry_id;

  if v_diff <> 0 then
    raise exception 'Journal entry % is not balanced: debits and credits differ by %', v_entry_id, v_diff;
  end if;
  return null;
end;
$$;

create constraint trigger journal_lines_balanced
after insert or update or delete on public.journal_lines
deferrable initially deferred
for each row execute function public.check_journal_entry_balanced();

-- create-can't-overwrite discipline, same as create_invoice()/create_sale():
-- no client-supplied id, the number generated server-side from
-- journal_entry_number_counters (same on-conflict-do-update-returning
-- pattern as invoice_number_counters/sale_number_counters). Not
-- SECURITY DEFINER — same reasoning as create_invoice()/create_sale(): it
-- runs with the calling Manager's own grants+RLS, so the INSERT policies
-- below are what actually enforce "Manager can post," not just this
-- function's own has_role() check (that's the early, clearly-worded UX
-- nicety, matching require_writable_role()'s role everywhere else).
create or replace function public.post_journal_entry(
  p_date date,
  p_description text,
  p_reference text,
  p_lines jsonb,
  p_reverses_entry_id text default null
)
returns public.journal_entries
language plpgsql
as $$
declare
  v_branch_id uuid;
  v_year_month text := to_char(p_date, 'YYMM');
  v_seq integer;
  v_id text;
  v_row public.journal_entries;
  v_line_count integer;
  v_total_debit numeric;
  v_total_credit numeric;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can post a journal entry';
  end if;

  if trim(coalesce(p_description, '')) = '' then
    raise exception 'A journal entry needs a description';
  end if;

  select count(*) into v_line_count from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb));
  if v_line_count < 2 then
    raise exception 'A journal entry needs at least two lines';
  end if;

  select coalesce(sum((line ->> 'debit')::numeric), 0), coalesce(sum((line ->> 'credit')::numeric), 0)
  into v_total_debit, v_total_credit
  from jsonb_array_elements(p_lines) as line;

  -- Pre-validated here for a clean, specific error before anything is
  -- written; the deferred constraint trigger on journal_lines re-validates
  -- the same fact at commit time regardless, as the real backstop.
  if v_total_debit <> v_total_credit then
    raise exception 'Entry is not balanced: debits % do not equal credits %', v_total_debit, v_total_credit;
  end if;
  if v_total_debit = 0 then
    raise exception 'Entry has no amount';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_lines) as line
    where not exists (
      select 1 from public.accounts a where a.id = (line ->> 'account_id')::uuid
    )
  ) then
    raise exception 'One of the selected accounts no longer exists';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_lines) as line
    join public.accounts a on a.id = (line ->> 'account_id')::uuid
    where not a.is_active
  ) then
    raise exception 'One of the selected accounts is inactive and cannot be posted to';
  end if;

  select id into v_branch_id from public.branches order by created_at limit 1;

  insert into public.journal_entry_number_counters (year_month, last_number)
  values (v_year_month, 1)
  on conflict (year_month) do update set last_number = journal_entry_number_counters.last_number + 1
  returning last_number into v_seq;

  v_id := 'JE-' || v_year_month || lpad(v_seq::text, 4, '0');

  insert into public.journal_entries (id, branch_id, entry_date, description, reference, reverses_entry_id)
  values (
    v_id,
    v_branch_id,
    p_date,
    trim(p_description),
    nullif(trim(coalesce(p_reference, '')), ''),
    p_reverses_entry_id
  )
  returning * into v_row;

  insert into public.journal_lines (entry_id, position, account_id, debit, credit, description)
  select
    v_id,
    ord - 1,
    (line ->> 'account_id')::uuid,
    coalesce((line ->> 'debit')::numeric, 0),
    coalesce((line ->> 'credit')::numeric, 0),
    coalesce(line ->> 'description', '')
  from jsonb_array_elements(p_lines) with ordinality as t(line, ord);

  return v_row;
end;
$$;

grant execute on function public.post_journal_entry(date, text, text, jsonb, text) to authenticated;

-- "A mistake gets corrected with a reversing entry, not a change to
-- history" — this is the sanctioned correction path, not just a
-- documented convention: journal_entries/journal_lines have no update or
-- delete policy at all (see below), so this is the only way to walk back a
-- posted entry. Composes post_journal_entry() rather than duplicating its
-- validation/numbering logic — swaps every line's debit and credit and
-- posts that as a brand new entry, referencing the original via
-- reverses_entry_id. One reversal per entry (checked below): a second
-- reversal attempt would leave the ledger ambiguous about which reversal
-- is "the" correction, and nothing in this session's scope calls for
-- partial/multiple reversals of one entry.
create or replace function public.reverse_journal_entry(
  p_entry_id text,
  p_date date default current_date,
  p_description text default null
)
returns public.journal_entries
language plpgsql
as $$
declare
  v_original public.journal_entries;
  v_lines jsonb;
  v_desc text;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can reverse a journal entry';
  end if;

  select * into v_original from public.journal_entries where id = p_entry_id;
  if not found then
    raise exception 'Journal entry % does not exist', p_entry_id;
  end if;

  if exists (select 1 from public.journal_entries where reverses_entry_id = p_entry_id) then
    raise exception 'Journal entry % has already been reversed', p_entry_id;
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'account_id', account_id,
      'debit', credit,
      'credit', debit,
      'description', description
    )
    order by position
  )
  into v_lines
  from public.journal_lines
  where entry_id = p_entry_id;

  v_desc := coalesce(nullif(trim(p_description), ''), 'Reversal of ' || p_entry_id || ' — ' || v_original.description);

  return public.post_journal_entry(p_date, v_desc, v_original.reference, v_lines, p_entry_id);
end;
$$;

grant execute on function public.reverse_journal_entry(text, date, text) to authenticated;

alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.journal_entry_number_counters enable row level security;

-- Same shape as accounts (Session 12): Accounting isn't in Attendant's
-- granted module list, so Attendant gets none of select/insert on any of
-- these three tables (not just a read restriction), Accountant/Auditor is
-- read-only, Manager can post. No update/delete policy exists on
-- journal_entries or journal_lines for ANY role, Manager included — see
-- the grants comment below for why that's not an oversight.
do $$
declare
  t text;
  tables text[] := array['journal_entries', 'journal_lines', 'journal_entry_number_counters'];
begin
  foreach t in array tables loop
    execute format(
      'create policy %I_select on public.%I for select using (public.has_role(array[''Manager'',''Accountant/Auditor'']))',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert with check (public.has_role(array[''Manager'']))',
      t, t
    );
  end loop;
end;
$$;

-- journal_entry_number_counters is the one table of the three that needs
-- an update path at all (the on-conflict-do-update inside
-- post_journal_entry()) — it's a plain technical counter, not a sensitive
-- ledger record, same treatment as invoice_number_counters/
-- sale_number_counters.
create policy journal_entry_number_counters_update on public.journal_entry_number_counters
for update
using (public.has_role(array['Manager']))
with check (public.has_role(array['Manager']));

-- No update/delete grant on journal_entries or journal_lines for anyone,
-- including service_role — a narrower version of the audit_log exception
-- to "service_role always gets full CRUD, it already bypasses RLS so
-- withholding the grant buys nothing." That reasoning holds for INSERT
-- here (there's no SECURITY DEFINER trigger guarding it the way
-- audit_log's does, so a normal grant is exactly what post_journal_entry()
-- needs to work under the calling Manager's own role), but "once posted,
-- immutable, no exception" is the entire point of this session, and
-- service_role's RLS bypass would otherwise make that false against any
-- local script authenticated as it — there is no legitimate reason any
-- tooling script needs to edit or delete a posted journal entry either.
revoke all on public.journal_entries, public.journal_lines from anon;
grant select, insert on public.journal_entries, public.journal_lines to authenticated;
grant select, insert on public.journal_entries, public.journal_lines to service_role;

revoke all on public.journal_entry_number_counters from anon;
grant select, insert, update on public.journal_entry_number_counters to authenticated;
grant select, insert, update on public.journal_entry_number_counters to service_role;
