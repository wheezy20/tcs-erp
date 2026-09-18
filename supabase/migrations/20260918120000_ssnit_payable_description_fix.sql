-- 2310 SSNIT Payable's account description is stale (TCS ERP — ledger
-- clarity fix from a walkthrough finding).
--
-- post_payroll_run() has posted both the employee withholding AND the
-- employer's 13% contribution to 2310 since 20260909120000_payslip_
-- employer_ssnit.sql, distinguished only by each journal_lines row's own
-- `description` — but the account's own description (shown on the Chart
-- of Accounts page) still only mentioned the employee side, making the
-- account look narrower than it actually is to anyone reading the COA
-- without also knowing to open individual posted lines.
--
-- Not splitting into a second account (e.g. 2311) to represent the
-- employer portion: SSNIT payable is one real liability to one creditor
-- (SSNIT), settled in one monthly remittance — splitting it by cost
-- origin rather than by creditor would mean "what do we owe SSNIT this
-- month" is no longer a single account balance, and there's no existing
-- report in this app that sums accounts back together for exactly that
-- purpose. The per-line description already correctly distinguishes the
-- two portions (see the code fix in payroll.$runId.tsx making that
-- description actually render on the posted-run card, which is the one
-- place it wasn't already visible — the General Ledger and Journal
-- Entries list both already show it). This migration only corrects the
-- account-level text to stop implying the account is employee-only.
update public.accounts
set description = 'SSNIT withheld from employee pay, plus the employer''s matching 13% contribution — both credited here, owed to SSNIT as one combined liability. See each posted line''s own description to tell the employee vs. employer portion apart.'
where code = '2310';
