-- Post a payroll run to the Accounting ledger (TCS ERP — Payroll follow-up).
--
-- Resolves the TODO left in 20260908070000_payroll_schema.sql
-- (near payroll_runs.status / create_payroll_run): posting a run now
-- creates ONE aggregated journal entry — total gross to salary expense,
-- credits to the statutory-liability and recovery accounts for everything
-- withheld, and the net to a payable awaiting disbursement — and flips
-- payroll_runs.status Draft -> Posted, atomically.
--
-- Same shape as every other poster (see 20260807100000_auto_posting_
-- integration.sql): a SECURITY DEFINER function that builds a jsonb line
-- array and calls the private _post_journal_entry_rows(), with
-- source_table/source_id set so the (source_table, source_id) unique
-- constraint makes a double-post structurally impossible. Aggregates the
-- whole run into one entry, the same way post_day_close_journal_entry()
-- rolls a day of till activity into one — not one entry per payslip.
--
-- Kept an explicit Manager/Accountant action (a button + this RPC), never
-- auto-posted on create_payslip(), matching the "don't silently touch the
-- ledger" discipline the rest of Accounting follows.
--
-- ---------------------------------------------------------------------
-- New accounts. accounts.created_by is nullable since
-- 20260819090000_seed_gap_accounts_expense_categories.sql, so new chart
-- rows go in the migration (idempotent) rather than seed.sql, which never
-- runs on a real deployment — same as the WHT account 1150. is_postable
-- defaults true.
--
--   2310 SSNIT Payable                  — employee SSNIT withheld, owed to SSNIT
--   2320 Provident Fund (Tier 2) Payable — employee Tier 2 withheld, owed to the trustee
--   2330 PAYE Payable                    — PAYE withheld, owed to GRA
--   4910 Staff Fines Recovered           — fines deducted from pay, kept visible
--                                          separately from 4900 Other Income
--
-- NOTE — employer SSNIT (13%) is NOT posted here. create_payslip() only
-- computes and snapshots the employee side, so there is no stored figure
-- to post. This entry therefore understates true staffing cost by the
-- employer's 13% SSNIT contribution. Tracked in docs/CONSTRAINTS.md's
-- go-live checklist; the fix is to add an employer-contribution figure to
-- the payslip computation and then extend this function.
-- ---------------------------------------------------------------------
insert into public.accounts (code, name, category, subtype, description)
values
  ('2310', 'SSNIT Payable', 'Liabilities', 'Current Liability',
   'Employee SSNIT contributions withheld from payroll, owed to SSNIT.'),
  ('2320', 'Provident Fund (Tier 2) Payable', 'Liabilities', 'Current Liability',
   'Employee Tier 2 provident fund contributions withheld from payroll, owed to the scheme trustee.'),
  ('2330', 'PAYE Payable', 'Liabilities', 'Current Liability',
   'PAYE income tax withheld from staff pay, owed to the Ghana Revenue Authority.'),
  ('4910', 'Staff Fines Recovered', 'Revenue', 'Revenue',
   'Fines and penalties deducted from staff pay. Kept separate from 4900 Other Income for visibility into recovery.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- post_payroll_run(): the only path that posts a run.
--
-- Aggregates over every payslip in the run:
--   G     = sum(gross_salary)   = sum(basic + overtime + allowances)
--   SSNIT = sum(ssnit)          (employee side)
--   TIER2 = sum(tier2)          (employee side)
--   PAYE  = sum(tax)
--   FINES = sum(fines)
--   IOU   = sum(iou)
--   NET   = sum(net_pay)        = G - SSNIT - TIER2 - PAYE - FINES - IOU
--
-- Entry (statutory / recovery lines are omitted when their total is 0 —
-- a zero-amount journal line violates journal_lines_has_amount):
--   Dr 5140 Salaries & Wages Expense            G
--   Cr 2300 Salaries & Wages Payable            NET   (accrued, not yet disbursed)
--   Cr 2310 SSNIT Payable                       SSNIT
--   Cr 2320 Provident Fund (Tier 2) Payable     TIER2
--   Cr 2330 PAYE Payable                        PAYE
--   Cr 1350 Advances to Staff                   IOU   (repayment reduces the asset —
--                                                      closes the loop post_expense_
--                                                      journal_entry() opens by debiting
--                                                      1350 for "Staff advances")
--   Cr 4910 Staff Fines Recovered               FINES
-- Balanced by construction: credits sum to G.
--
-- Manager/Accountant only (require_finance_writer(), same as the other
-- finance RPCs post-20260909090000). Draft runs only. Atomic: the entry
-- and the status flip commit together or not at all.
-- ---------------------------------------------------------------------
create or replace function public.post_payroll_run(p_run_id uuid)
returns public.journal_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs;
  v_entry_date date;
  v_period text;
  v_count integer := 0;
  v_gross numeric := 0;
  v_ssnit numeric := 0;
  v_tier2 numeric := 0;
  v_paye numeric := 0;
  v_fines numeric := 0;
  v_iou numeric := 0;
  v_net numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_entry public.journal_entries;
begin
  -- Split-role model (20260909090000): Manager + Accountant write the
  -- finance modules (Payroll, Accounting, Expenses); Auditor is read-only.
  perform public.require_finance_writer();

  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'Payroll run % not found', p_run_id;
  end if;
  if v_run.status <> 'Draft' then
    raise exception 'Payroll run % is already posted', p_run_id;
  end if;

  select
    count(*),
    coalesce(sum(gross_salary), 0),
    coalesce(sum(ssnit), 0),
    coalesce(sum(tier2), 0),
    coalesce(sum(tax), 0),
    coalesce(sum(fines), 0),
    coalesce(sum(iou), 0),
    coalesce(sum(net_pay), 0)
  into v_count, v_gross, v_ssnit, v_tier2, v_paye, v_fines, v_iou, v_net
  from public.payslips
  where payroll_run_id = p_run_id;

  if v_count = 0 then
    raise exception 'Payroll run % has no payslips to post', p_run_id;
  end if;
  if v_net <= 0 then
    raise exception 'Total net pay for run % must be positive to post (got %)', p_run_id, v_net;
  end if;

  -- Last calendar day of the run's month — pay is accrued at period end.
  v_entry_date := (make_date(v_run.year, v_run.month, 1) + interval '1 month' - interval '1 day')::date;
  v_period := to_char(make_date(v_run.year, v_run.month, 1), 'FMMonth YYYY');

  v_lines := v_lines
    || jsonb_build_object(
      'account_id', public.account_id_by_code('5140'),
      'debit', v_gross, 'credit', 0, 'description', 'Gross pay — ' || v_period
    )
    || jsonb_build_object(
      'account_id', public.account_id_by_code('2300'),
      'debit', 0, 'credit', v_net, 'description', 'Net pay payable — ' || v_period
    );

  if v_ssnit > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2310'),
      'debit', 0, 'credit', v_ssnit, 'description', 'SSNIT withheld — ' || v_period
    );
  end if;
  if v_tier2 > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2320'),
      'debit', 0, 'credit', v_tier2, 'description', 'Tier 2 withheld — ' || v_period
    );
  end if;
  if v_paye > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('2330'),
      'debit', 0, 'credit', v_paye, 'description', 'PAYE withheld — ' || v_period
    );
  end if;
  if v_iou > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('1350'),
      'debit', 0, 'credit', v_iou, 'description', 'Staff advance recovery — ' || v_period
    );
  end if;
  if v_fines > 0 then
    v_lines := v_lines || jsonb_build_object(
      'account_id', public.account_id_by_code('4910'),
      'debit', 0, 'credit', v_fines, 'description', 'Staff fines recovered — ' || v_period
    );
  end if;

  v_entry := public._post_journal_entry_rows(
    v_run.branch_id,
    v_entry_date,
    'Payroll — ' || v_period,
    p_run_id::text,
    v_lines,
    'payroll_runs',
    p_run_id::text
  );

  update public.payroll_runs
  set status = 'Posted', posted_at = now()
  where id = p_run_id;

  return v_entry;
end;
$$;

grant execute on function public.post_payroll_run(uuid) to authenticated;
grant execute on function public.post_payroll_run(uuid) to service_role;

-- create_payslip() already refuses a non-Draft run ("Payroll run % is
-- already posted and cannot take new payslips"), delete_payslip() already
-- refuses one, payroll_runs_delete RLS already requires status = 'Draft',
-- and payroll_runs has no UPDATE grant or policy for authenticated — so a
-- Posted run is already fully immutable through every path. Nothing to add
-- here; this comment records that it was checked.
