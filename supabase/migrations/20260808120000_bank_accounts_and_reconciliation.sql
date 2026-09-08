-- Session 16: Bank Accounts & Reconciliation — the full module this time,
-- not Session 11's lightweight bank_deposits log. Builds directly on top
-- of two things that are already real: Session 11's bank_deposits (which
-- until now always posted to a hardcoded 1010 Cash in Bank) and Session
-- 14's ledger postings (every payment/expense/deposit that ever touches a
-- bank account already lands in journal_lines against a real GL account).
-- Reconciliation's whole job is comparing the bank's own independent
-- record (a statement) against that already-real ledger activity — it
-- never re-derives or re-enters what already happened.
--
-- ================================================== three new tables
--
-- bank_accounts: a real bank account record, each tied to exactly one
-- ledger account (`gl_account_id`, unique — two bank accounts posting to
-- the same GL account would make "whose statement does this ledger line
-- belong to" ambiguous). Deliberately NOT branch-scoped, the same
-- reasoning Session 12 gave `accounts` itself: a bank account belongs to
-- the whole legal entity, not to one branch, even once a second branch
-- exists. `gl_account_id` and `opening_balance`/`opening_balance_date` are
-- immutable once set (see the trigger below) — the same "revisit if
-- needed" caution Session 12 flagged for `accounts.code`, made concrete
-- here because a reconciliation's own math is anchored to these values;
-- changing them after even one reconciliation exists would silently
-- invalidate its tie-out.
--
-- bank_reconciliations: a two-phase session (open -> completed), the same
-- shape Session 11's day_closes established — `opening_balance` is
-- snapshotted at start time (the previous completed session's
-- statement_ending_balance, or the bank account's own opening_balance for
-- the very first session ever), never recomputed later. Only one open
-- session per bank account at a time (a partial unique index, not just app
-- discipline). Once completed, immutable — no update or delete policy
-- reaches a completed row, the same "once posted/closed, permanent" rule
-- journal_entries and day_closes both already enforce.
--
-- bank_statement_lines: what the bank statement itself says happened —
-- imported (bulk) or entered one at a time (the same RPC either way, see
-- import_bank_statement_lines below), never derived from our own ledger.
-- `status` is 'unmatched' (default, needs resolving), 'matched' (linked to
-- one specific, not-already-used journal_lines row with the identical
-- signed amount — matching is a *strict* claim), or 'cleared' (a Manager's
-- deliberate override: accepted as real bank activity with no ledger
-- counterpart to point to, e.g. a bank fee not yet expensed). The
-- resolution trigger below keeps matched_by/matched_at/reconciliation_id
-- consistent with status structurally, not by convention.
--
-- ================================================== the tie-out rule
--
-- Session 15's Trial Balance proved the ledger balances by construction;
-- this session's equivalent is complete_bank_reconciliation() refusing to
-- complete unless (a) zero statement lines dated on/before the statement
-- date remain 'unmatched' — every line has to be actively resolved one way
-- or another, never silently skipped — and (b) opening_balance + the sum
-- of every line resolved *in this session* (matched or cleared) equals the
-- entered statement_ending_balance to the cent. This is the same
-- "reconcile-by-matching" model real bank-rec software (Xero, QuickBooks
-- Online) uses today, not the older two-column "outstanding
-- checks/deposits in transit" worksheet — deliberately simpler, and
-- because every 'matched' line's amount is already asserted equal to its
-- ledger counterpart at match time, and 'cleared' lines are Manager-
-- asserted-correct, the sum only fails to tie out if the entered statement
-- balance, the account's opening balance, or the statement import itself
-- is actually wrong — exactly the class of real error this check exists to
-- catch, structurally, the same standard Session 15 used for Trial
-- Balance.
--
-- ================================================== deliberately out of scope
--
-- No new "withdrawal" transaction type. Money already leaves 1010 today
-- (a Bank-method expense credits it) and already arrives (Card/Bank
-- Transfer/Cheque payments, and now a deposit, debit it) — "matching
-- deposits and withdrawals" (the spec's own phrase) means a statement line
-- can carry either sign and still be matched against whichever existing
-- ledger activity produced it, not that this session invents a new kind of
-- transaction. Building one here would be scope no part of the ask
-- actually calls for.

-- ============================================================ bank_accounts

create table public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  account_number text not null,
  gl_account_id uuid not null references public.accounts (id) on delete restrict,
  opening_balance numeric(12, 2) not null default 0,
  opening_balance_date date not null,
  currency text not null default 'GHS',
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (gl_account_id)
);

create or replace function public.set_bank_account_created_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger bank_accounts_set_created_by
before insert on public.bank_accounts
for each row execute function public.set_bank_account_created_by();

create trigger bank_accounts_set_updated_at
before update on public.bank_accounts
for each row execute function public.set_updated_at();

-- A bank account can only ever point at a real, Assets-category ledger
-- account — "Cash in Bank" is the obvious case, but this stays general
-- rather than hardcoding account 1010, matching the user's own "1010 or
-- wherever deposits currently post" framing.
create or replace function public.validate_bank_account_gl_link()
returns trigger language plpgsql as $$
declare
  v_category text;
begin
  select category into v_category from public.accounts where id = new.gl_account_id;
  if v_category is null then
    raise exception 'Ledger account % not found', new.gl_account_id;
  end if;
  if v_category <> 'Assets' then
    raise exception 'A bank account must be linked to an Assets-category ledger account';
  end if;
  return new;
end;
$$;

create trigger bank_accounts_validate_gl_link
before insert on public.bank_accounts
for each row execute function public.validate_bank_account_gl_link();

create or replace function public.prevent_bank_account_immutable_change()
returns trigger language plpgsql as $$
begin
  if new.gl_account_id <> old.gl_account_id then
    raise exception 'A bank account''s linked ledger account cannot be changed once created — deactivate and create a new bank account instead';
  end if;
  if new.opening_balance <> old.opening_balance or new.opening_balance_date <> old.opening_balance_date then
    raise exception 'A bank account''s opening balance is fixed at creation — changing it later would invalidate any reconciliation already tied out against it';
  end if;
  return new;
end;
$$;

create trigger bank_accounts_prevent_immutable_change
before update on public.bank_accounts
for each row execute function public.prevent_bank_account_immutable_change();

-- ===================================================== bank_reconciliations

create table public.bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  bank_account_id uuid not null references public.bank_accounts (id) on delete restrict,
  statement_date date not null,
  statement_ending_balance numeric(12, 2) not null,
  -- Snapshotted at start_bank_reconciliation() time — the previous
  -- completed session's statement_ending_balance, or the bank account's
  -- own opening_balance if this is the first session ever. Never
  -- recomputed later, the same "fixed at creation" principle as an
  -- invoice's own vat_rate.
  opening_balance numeric(12, 2) not null,
  reconciled_balance numeric(12, 2),
  difference numeric(12, 2),
  started_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_by uuid references public.staff (id) on delete restrict,
  completed_at timestamptz,
  notes text not null default '',
  check (
    (completed_at is null and reconciled_balance is null and difference is null and completed_by is null)
    or
    (completed_at is not null and reconciled_balance is not null and difference is not null and completed_by is not null)
  )
);

-- Only one open (not-yet-completed) reconciliation per bank account at a
-- time — NULLS DISTINCT doesn't apply here since completed_at IS the
-- partial-index predicate, not a column in it.
create unique index bank_reconciliations_one_open_per_account
  on public.bank_reconciliations (bank_account_id) where completed_at is null;
create index bank_reconciliations_account_date_idx
  on public.bank_reconciliations (bank_account_id, statement_date desc);

create or replace function public.set_bank_reconciliation_started_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.started_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger bank_reconciliations_set_started_by
before insert on public.bank_reconciliations
for each row execute function public.set_bank_reconciliation_started_by();

-- Forced at the trigger level for the same reason day_closes.closed_by is:
-- a raw PATCH from a legitimate Manager session could otherwise set
-- completed_by to a different Manager's uuid.
create or replace function public.set_bank_reconciliation_completed_by()
returns trigger language plpgsql as $$
begin
  if new.completed_at is not null and auth.uid() is not null then
    new.completed_by := auth.uid();
  end if;
  return new;
end;
$$;

create trigger bank_reconciliations_set_completed_by
before update on public.bank_reconciliations
for each row execute function public.set_bank_reconciliation_completed_by();

-- ==================================================== bank_statement_lines

create table public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  bank_account_id uuid not null references public.bank_accounts (id) on delete restrict,
  date date not null,
  description text not null,
  -- Signed, matching the real statement's own convention: positive = money
  -- in (a deposit), negative = money out (a withdrawal/fee/charge).
  amount numeric(12, 2) not null check (amount <> 0),
  reference text not null default '',
  status text not null default 'unmatched' check (status in ('unmatched', 'matched', 'cleared')),
  matched_journal_line_id uuid references public.journal_lines (id),
  -- Why a line was cleared without a strict ledger match — a real reason
  -- (e.g. "bank fee, not yet recorded as an expense"), not optional.
  clear_note text not null default '',
  reconciliation_id uuid references public.bank_reconciliations (id),
  matched_by uuid references public.staff (id) on delete restrict,
  matched_at timestamptz,
  imported_by uuid not null default auth.uid() references public.staff (id) on delete restrict,
  created_at timestamptz not null default now(),
  -- NULLS DISTINCT (Postgres default): many lines can share a null
  -- matched_journal_line_id, but a real ledger line can only ever back one
  -- statement line — the same discipline journal_entries.source_id uses.
  unique (matched_journal_line_id),
  check ((status = 'unmatched') = (matched_by is null)),
  check ((status = 'unmatched') = (reconciliation_id is null)),
  check (status = 'matched' or matched_journal_line_id is null)
);

create index bank_statement_lines_account_status_idx
  on public.bank_statement_lines (bank_account_id, status);
create index bank_statement_lines_account_date_idx
  on public.bank_statement_lines (bank_account_id, date desc);

create or replace function public.set_statement_line_imported_by()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.imported_by := auth.uid(); end if;
  return new;
end;
$$;

create trigger bank_statement_lines_set_imported_by
before insert on public.bank_statement_lines
for each row execute function public.set_statement_line_imported_by();

-- Centralizes "matched_by/matched_at/reconciliation_id are set iff status
-- isn't unmatched" as a structural invariant every status transition goes
-- through, rather than trusting each RPC to remember to null everything
-- out on the way back to 'unmatched' (unmatch_statement_line and
-- cancel_bank_reconciliation both rely on this).
create or replace function public.set_statement_line_resolution()
returns trigger language plpgsql as $$
begin
  if new.status in ('matched', 'cleared') and old.status = 'unmatched' then
    new.matched_by := auth.uid();
    new.matched_at := now();
  elsif new.status = 'unmatched' then
    new.matched_by := null;
    new.matched_at := null;
    new.matched_journal_line_id := null;
    new.reconciliation_id := null;
    new.clear_note := '';
  end if;
  return new;
end;
$$;

create trigger bank_statement_lines_set_resolution
before update on public.bank_statement_lines
for each row execute function public.set_statement_line_resolution();

-- ============================================================ create_bank_account

-- create-can't-overwrite: no client-supplied id, a plain insert, a
-- friendly error instead of a raw unique_violation on gl_account_id —
-- matches create_account()'s own shape exactly.
create or replace function public.create_bank_account(
  p_name text, p_account_number text, p_gl_account_id uuid,
  p_opening_balance numeric, p_opening_balance_date date, p_currency text default 'GHS'
) returns public.bank_accounts language plpgsql as $$
declare
  v_row public.bank_accounts;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can add a bank account';
  end if;

  insert into public.bank_accounts (name, account_number, gl_account_id, opening_balance, opening_balance_date, currency)
  values (p_name, p_account_number, p_gl_account_id, p_opening_balance, p_opening_balance_date, coalesce(nullif(p_currency, ''), 'GHS'))
  returning * into v_row;

  return v_row;
exception
  when unique_violation then
    raise exception 'That ledger account is already linked to another bank account';
end;
$$;

grant execute on function public.create_bank_account(text, text, uuid, numeric, date, text) to authenticated;

-- ==================================================== import_bank_statement_lines

-- One RPC handles both the manual "add a single line" case and a bulk CSV
-- import — the frontend just calls it with a one-element array for the
-- former, the same addProduct()/addProducts() batching precedent Sessions
-- 1-2 established. create-can't-overwrite: no client-supplied ids, a plain
-- insert per row.
create or replace function public.import_bank_statement_lines(p_bank_account_id uuid, p_lines jsonb)
returns setof public.bank_statement_lines language plpgsql as $$
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can add or import bank statement lines';
  end if;

  if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
    raise exception 'Bank account % not found', p_bank_account_id;
  end if;

  return query
  insert into public.bank_statement_lines (bank_account_id, date, description, amount, reference)
  select
    p_bank_account_id,
    (line ->> 'date')::date,
    line ->> 'description',
    (line ->> 'amount')::numeric,
    coalesce(line ->> 'reference', '')
  from jsonb_array_elements(p_lines) as line
  returning *;
end;
$$;

grant execute on function public.import_bank_statement_lines(uuid, jsonb) to authenticated;

-- ==================================================== start_bank_reconciliation

create or replace function public.start_bank_reconciliation(
  p_bank_account_id uuid, p_statement_date date, p_statement_ending_balance numeric
) returns public.bank_reconciliations language plpgsql as $$
declare
  v_opening numeric;
  v_prev public.bank_reconciliations;
  v_row public.bank_reconciliations;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can start a bank reconciliation';
  end if;

  if exists (
    select 1 from public.bank_reconciliations
    where bank_account_id = p_bank_account_id and completed_at is null
  ) then
    raise exception 'A reconciliation is already open for this bank account — complete or cancel it first';
  end if;

  select * into v_prev from public.bank_reconciliations
  where bank_account_id = p_bank_account_id and completed_at is not null
  order by statement_date desc, completed_at desc
  limit 1;

  if found then
    v_opening := v_prev.statement_ending_balance;
  else
    select opening_balance into v_opening from public.bank_accounts where id = p_bank_account_id;
    if not found then
      raise exception 'Bank account % not found', p_bank_account_id;
    end if;
  end if;

  insert into public.bank_reconciliations (bank_account_id, statement_date, statement_ending_balance, opening_balance)
  values (p_bank_account_id, p_statement_date, p_statement_ending_balance, v_opening)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.start_bank_reconciliation(uuid, date, numeric) to authenticated;

-- ==================================================== match_statement_line

-- A *strict* match: the statement line's amount must equal the ledger
-- line's own signed amount (debit - credit; every bank_accounts.gl_account_id
-- is Assets/debit-normal by the trigger above, so this is always the right
-- sign convention) to the cent. Anything looser belongs in
-- clear_statement_line() instead, deliberately a different, explicit path
-- rather than a fuzzy auto-match.
create or replace function public.match_statement_line(p_line_id uuid, p_journal_line_id uuid)
returns public.bank_statement_lines language plpgsql as $$
declare
  v_line public.bank_statement_lines;
  v_bank_gl_account uuid;
  v_jl_account_id uuid;
  v_jl_amount numeric;
  v_recon public.bank_reconciliations;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can match a bank statement line';
  end if;

  select * into v_line from public.bank_statement_lines where id = p_line_id for update;
  if not found then
    raise exception 'Statement line % not found', p_line_id;
  end if;
  if v_line.status <> 'unmatched' then
    raise exception 'This line has already been resolved — unmatch it first';
  end if;

  select * into v_recon from public.bank_reconciliations
  where bank_account_id = v_line.bank_account_id and completed_at is null
  for update;
  if not found then
    raise exception 'Start a reconciliation for this bank account before matching lines';
  end if;

  select account_id, debit - credit into v_jl_account_id, v_jl_amount
  from public.journal_lines where id = p_journal_line_id;
  if not found then
    raise exception 'Ledger line % not found', p_journal_line_id;
  end if;

  select gl_account_id into v_bank_gl_account from public.bank_accounts where id = v_line.bank_account_id;
  if v_jl_account_id <> v_bank_gl_account then
    raise exception 'That ledger line does not belong to this bank account''s ledger account';
  end if;

  if exists (select 1 from public.bank_statement_lines where matched_journal_line_id = p_journal_line_id) then
    raise exception 'That ledger line is already matched to another statement line';
  end if;

  if abs(v_jl_amount - v_line.amount) > 0.005 then
    raise exception 'Amount mismatch: statement line is %, ledger line is % — use "Mark cleared" if this is a deliberate override, not an exact match', v_line.amount, v_jl_amount;
  end if;

  update public.bank_statement_lines
  set status = 'matched', matched_journal_line_id = p_journal_line_id, reconciliation_id = v_recon.id
  where id = p_line_id
  returning * into v_line;

  return v_line;
end;
$$;

grant execute on function public.match_statement_line(uuid, uuid) to authenticated;

-- ==================================================== clear_statement_line

create or replace function public.clear_statement_line(p_line_id uuid, p_note text default '')
returns public.bank_statement_lines language plpgsql as $$
declare
  v_line public.bank_statement_lines;
  v_recon public.bank_reconciliations;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can mark a bank statement line cleared';
  end if;
  if coalesce(trim(p_note), '') = '' then
    raise exception 'A reason is required to clear a line without a ledger match';
  end if;

  select * into v_line from public.bank_statement_lines where id = p_line_id for update;
  if not found then
    raise exception 'Statement line % not found', p_line_id;
  end if;
  if v_line.status <> 'unmatched' then
    raise exception 'This line has already been resolved — unmatch it first';
  end if;

  select * into v_recon from public.bank_reconciliations
  where bank_account_id = v_line.bank_account_id and completed_at is null
  for update;
  if not found then
    raise exception 'Start a reconciliation for this bank account before clearing lines';
  end if;

  update public.bank_statement_lines
  set status = 'cleared', clear_note = trim(p_note), reconciliation_id = v_recon.id
  where id = p_line_id
  returning * into v_line;

  return v_line;
end;
$$;

grant execute on function public.clear_statement_line(uuid, text) to authenticated;

-- ==================================================== unmatch_statement_line

create or replace function public.unmatch_statement_line(p_line_id uuid)
returns public.bank_statement_lines language plpgsql as $$
declare
  v_line public.bank_statement_lines;
  v_recon public.bank_reconciliations;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can unmatch a bank statement line';
  end if;

  select * into v_line from public.bank_statement_lines where id = p_line_id for update;
  if not found then
    raise exception 'Statement line % not found', p_line_id;
  end if;
  if v_line.status = 'unmatched' then
    raise exception 'This line is already unmatched';
  end if;

  select * into v_recon from public.bank_reconciliations where id = v_line.reconciliation_id;
  if v_recon.completed_at is not null then
    raise exception 'This line was resolved under a completed reconciliation and can no longer be changed';
  end if;

  update public.bank_statement_lines
  set status = 'unmatched'
  where id = p_line_id
  returning * into v_line;

  return v_line;
end;
$$;

grant execute on function public.unmatch_statement_line(uuid) to authenticated;

-- ==================================================== complete_bank_reconciliation

-- Structurally can't complete unless it ties out — see the block comment
-- at the top of this migration.
create or replace function public.complete_bank_reconciliation(p_reconciliation_id uuid)
returns public.bank_reconciliations language plpgsql as $$
declare
  v_recon public.bank_reconciliations;
  v_unresolved integer;
  v_resolved_sum numeric;
  v_reconciled numeric;
  v_diff numeric;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can complete a bank reconciliation';
  end if;

  select * into v_recon from public.bank_reconciliations where id = p_reconciliation_id for update;
  if not found then
    raise exception 'Reconciliation % not found', p_reconciliation_id;
  end if;
  if v_recon.completed_at is not null then
    raise exception 'This reconciliation is already completed';
  end if;

  select count(*) into v_unresolved from public.bank_statement_lines
  where bank_account_id = v_recon.bank_account_id
    and date <= v_recon.statement_date
    and status = 'unmatched';

  if v_unresolved > 0 then
    raise exception '% statement line(s) on or before % are still unmatched — match or clear every line before completing this reconciliation', v_unresolved, v_recon.statement_date;
  end if;

  select coalesce(sum(amount), 0) into v_resolved_sum from public.bank_statement_lines
  where reconciliation_id = p_reconciliation_id and status in ('matched', 'cleared');

  v_reconciled := v_recon.opening_balance + v_resolved_sum;
  v_diff := round(v_recon.statement_ending_balance - v_reconciled, 2);

  if abs(v_diff) > 0.005 then
    raise exception 'Reconciliation does not tie out: statement balance % vs reconciled balance % (difference %) — check the statement ending balance and every resolved line', v_recon.statement_ending_balance, v_reconciled, v_diff;
  end if;

  update public.bank_reconciliations
  set reconciled_balance = v_reconciled, difference = v_diff, completed_at = now()
  where id = p_reconciliation_id
  returning * into v_recon;

  return v_recon;
end;
$$;

grant execute on function public.complete_bank_reconciliation(uuid) to authenticated;

-- ==================================================== cancel_bank_reconciliation

-- The one sanctioned way to undo an open (never-completed) session that
-- was started by mistake — resets every line it had resolved back to
-- unmatched (the resolution trigger nulls the rest), then removes the
-- session itself, so the account's "only one open session" constraint
-- doesn't leave it permanently stuck. A completed session has no
-- equivalent — that's permanent, the same as everywhere else in this build.
create or replace function public.cancel_bank_reconciliation(p_reconciliation_id uuid)
returns void language plpgsql as $$
declare
  v_recon public.bank_reconciliations;
begin
  perform public.require_writable_role();
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can cancel a bank reconciliation';
  end if;

  select * into v_recon from public.bank_reconciliations where id = p_reconciliation_id for update;
  if not found then
    raise exception 'Reconciliation % not found', p_reconciliation_id;
  end if;
  if v_recon.completed_at is not null then
    raise exception 'A completed reconciliation cannot be cancelled';
  end if;

  update public.bank_statement_lines
  set status = 'unmatched'
  where reconciliation_id = p_reconciliation_id;

  delete from public.bank_reconciliations where id = p_reconciliation_id;
end;
$$;

grant execute on function public.cancel_bank_reconciliation(uuid) to authenticated;

-- ============================================================ bank_deposits

-- bank_deposits always posted to a hardcoded 1010 before this session —
-- it now says which real bank account received the deposit, and
-- post_bank_deposit_journal_entry() (below) reads that account's own
-- gl_account_id instead of hardcoding the account code. bank_deposits has
-- no existing rows in any environment this migration runs against (seed.sql
-- never inserted any — Session 11's own note), so this can go straight to
-- not null with no backfill.
alter table public.bank_deposits
  add column bank_account_id uuid references public.bank_accounts (id) on delete restrict;

alter table public.bank_deposits
  alter column bank_account_id set not null;

drop function if exists public.record_bank_deposit(uuid, numeric, date, text, text, text);

create or replace function public.record_bank_deposit(
  p_branch_id uuid,
  p_bank_account_id uuid,
  p_amount numeric,
  p_date date,
  p_source text,
  p_reference text default '',
  p_note text default ''
)
returns public.bank_deposits
language plpgsql
as $$
declare
  v_row public.bank_deposits;
begin
  if not public.has_role(array['Manager']) then
    raise exception 'Only a Manager can record a bank/mobile money deposit';
  end if;
  if p_amount <= 0 then
    raise exception 'Deposit amount must be greater than zero';
  end if;
  if p_source not in ('Cash', 'Mobile Money') then
    raise exception 'Invalid deposit source';
  end if;
  if not exists (select 1 from public.bank_accounts where id = p_bank_account_id) then
    raise exception 'Bank account % not found', p_bank_account_id;
  end if;

  insert into public.bank_deposits (branch_id, bank_account_id, amount, date, source, reference, note)
  values (p_branch_id, p_bank_account_id, p_amount, p_date, p_source, coalesce(p_reference, ''), coalesce(p_note, ''))
  returning * into v_row;

  perform public.post_bank_deposit_journal_entry(v_row.id);
  return v_row;
end;
$$;

grant execute on function public.record_bank_deposit(uuid, uuid, numeric, date, text, text, text) to authenticated;

-- Unchanged signature — post_bank_deposit_journal_entry(uuid) keeps its
-- existing EXECUTE grant across this CREATE OR REPLACE.
create or replace function public.post_bank_deposit_journal_entry(p_deposit_id uuid)
returns public.journal_entries
security definer
set search_path = public
language plpgsql
as $$
declare
  v_deposit public.bank_deposits;
  v_source_account uuid;
  v_bank_gl_account uuid;
  v_lines jsonb;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id;
  if not found then
    raise exception 'Deposit % not found', p_deposit_id;
  end if;

  select gl_account_id into v_bank_gl_account from public.bank_accounts where id = v_deposit.bank_account_id;

  v_source_account := case v_deposit.source
    when 'Cash' then public.account_id_by_code('1000')
    when 'Mobile Money' then public.account_id_by_code('1020')
  end;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', v_bank_gl_account,
      'debit', v_deposit.amount, 'credit', 0, 'description', 'Deposit — ' || v_deposit.source
    ),
    jsonb_build_object(
      'account_id', v_source_account,
      'debit', 0, 'credit', v_deposit.amount, 'description', 'Deposit — ' || v_deposit.source
    )
  );

  return public._post_journal_entry_rows(
    v_deposit.branch_id, v_deposit.date, 'Bank/Mobile Money deposit', p_deposit_id::text,
    v_lines, 'bank_deposits', p_deposit_id::text
  );
end;
$$;

-- ============================================================ RLS

-- Bank Accounts & Reconciliation isn't in Attendant's spec-granted module
-- list — same tier as Accounting/Reports/Expenses: Manager full
-- read/write, Accountant/Auditor read-only, Attendant none. Deletes are
-- narrower than the shallow "Manager, full stop" default elsewhere:
-- reconciliations and statement lines lock down once they carry real
-- resolved history (a completed reconciliation, a matched/cleared line),
-- the same "an audit record its own most-privileged user can quietly
-- delete isn't trustworthy" principle audit_log and journal_entries
-- already established — cancel_bank_reconciliation() is the sanctioned
-- undo for a session that's still open, not a bare DELETE bypassing that.
alter table public.bank_accounts enable row level security;

create policy bank_accounts_select on public.bank_accounts
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy bank_accounts_insert on public.bank_accounts
  for insert with check (public.has_role(array['Manager']));
create policy bank_accounts_update on public.bank_accounts
  for update using (public.has_role(array['Manager']));
create policy bank_accounts_delete on public.bank_accounts
  for delete using (public.has_role(array['Manager']));

revoke all on public.bank_accounts from anon;
grant select, insert, update, delete on public.bank_accounts to authenticated;
grant select, insert, update, delete on public.bank_accounts to service_role;

alter table public.bank_reconciliations enable row level security;

create policy bank_reconciliations_select on public.bank_reconciliations
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy bank_reconciliations_insert on public.bank_reconciliations
  for insert with check (public.has_role(array['Manager']));
-- USING gates which rows a Manager can start updating (must currently be
-- open) — WITH CHECK must be given explicitly and deliberately narrower
-- than USING here, or Postgres defaults it to the same expression, which
-- would then also apply to the NEW row and block the exact open->completed
-- transition (completed_at is null becomes false) this policy exists to
-- allow in the first place. Caught live: complete_bank_reconciliation()'s
-- own UPDATE failed with a bare 42501 until this was split out.
create policy bank_reconciliations_update on public.bank_reconciliations
  for update
  using (public.has_role(array['Manager']) and completed_at is null)
  with check (public.has_role(array['Manager']));
create policy bank_reconciliations_delete on public.bank_reconciliations
  for delete using (public.has_role(array['Manager']) and completed_at is null);

revoke all on public.bank_reconciliations from anon;
grant select, insert, update, delete on public.bank_reconciliations to authenticated;
grant select, insert, update, delete on public.bank_reconciliations to service_role;

alter table public.bank_statement_lines enable row level security;

create policy bank_statement_lines_select on public.bank_statement_lines
  for select using (public.has_role(array['Manager', 'Accountant/Auditor']));
create policy bank_statement_lines_insert on public.bank_statement_lines
  for insert with check (public.has_role(array['Manager']));
-- A raw PATCH bypassing match_statement_line()'s amount-equality check is
-- an accepted, documented gap, not an oversight: only Manager reaches this
-- policy at all (the same role section 6 already grants unrestricted write
-- access "on every model, everything"), and the identity/consistency
-- invariants that matter (who/when resolved it, matched_by iff status) are
-- still trigger-enforced regardless of which path performs the update —
-- the same class of tradeoff already accepted for products.cost's
-- visibility to Attendant.
create policy bank_statement_lines_update on public.bank_statement_lines
  for update using (public.has_role(array['Manager']));
create policy bank_statement_lines_delete on public.bank_statement_lines
  for delete using (public.has_role(array['Manager']) and status = 'unmatched');

revoke all on public.bank_statement_lines from anon;
grant select, insert, update, delete on public.bank_statement_lines to authenticated;
grant select, insert, update, delete on public.bank_statement_lines to service_role;
