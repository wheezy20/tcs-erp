-- Role matrix for 20261006100000_overtime_tax_engine (concessionary
-- overtime tax: the overtime_tax_rates table, the two payslip columns, and
-- the create_payslip() / post_payroll_run() changes) and
-- 20261006110000_overtime_tax_rates_2026 (the first rate row: 18,000 /
-- 50% / 5% / 10%, effective 2026-10-01).
-- Run: ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20261006100000_overtime_tax_engine.sql
--
-- Section A: who can read and write overtime_tax_rates (the paye_bands
-- access: Manager, Accountant and Auditor read; Manager and Accountant
-- write; nobody else), the table's checks, and that exactly one row is
-- shipped, with the confirmed values (A9).
--
-- Section B: oracle cases A-O through create_payslip(), under the real
-- 2026-10-01 row (threshold 18,000, cap 50% of basic, 5% within the cap,
-- 10% above). Runs are October 2026 (K: September 2026, the month before
-- the row takes effect; K2: no row at all). Both months resolve to the
-- 2026-09-01 PAYE bands (monthly: 0-588 at 0%, next 80 at 5%, next 100 at
-- 10%, then 17.5% to 3,668). SSNIT 0.5% and Tier 2
-- 5% of basic come off before PAYE. Each case asserts gross, taxable
-- income, PAYE, overtime tax, the concession flag, total deductions and
-- net pay. Working:
--
--   A  basic 1,200, OT 400: qualifies (14,400 <= 18,000). Taxable
--      1,200 - 66 = 1,134 (OT excluded); PAYE 4 + 10 + 366 x 17.5% = 78.05;
--      OT tax 400 x 5% = 20.00 (cap 600); deductions 164.05; net 1,435.95.
--   B  basic 1,200, OT 800: OT tax 600 x 5% + 200 x 10% = 50.00;
--      deductions 194.05; net 1,805.95.
--   C  basic 1,900, OT 400: does not qualify (22,800). Taxable
--      1,900 + 400 - 104.50 = 2,195.50; PAYE 14 + 1,427.50 x 17.5% = 263.81
--      (70.00 more than 193.81 without the overtime); net 1,931.69.
--   D  basic 1,500.00, OT 300: exactly 18,000, qualifies. Taxable 1,417.50;
--      PAYE 14 + 649.50 x 17.5% = 127.66; OT tax 15.00; net 1,574.84.
--   E  basic 1,500.01, OT 300: 18,000.12, does not qualify. Taxable
--      1,800.01 - 82.50 = 1,717.51; PAYE 14 + 949.51 x 17.5% = 180.16;
--      net 1,537.35.
--   F  basic 1,200, OT 600 (exactly 50%): all at 5%, OT tax 30.00;
--      net 1,625.95.
--   G  basic 1,200, OT 601: 30.00 + 1 x 10% = 30.10; net 1,626.85.
--   H  basic 1,200, OT 0: no concession (flag false); PAYE 78.05;
--      net 1,055.95.
--   I  National Service (no SSNIT, Tier 2 or PAYE), basic 1,200, OT 400:
--      nothing deducted; taxable 1,600 recorded as before; net 1,600.00.
--   J  PAYE-exempt only, basic 1,200, OT 400: no PAYE and no OT tax;
--      taxable 1,534; deductions 66.00; net 1,534.00.
--   K  basic 1,200, OT 400, September 2026 run (before the row's
--      effective date): today's treatment. Taxable 1,534; PAYE 4 + 10 + 766 x 17.5% =
--      148.05; net 1,385.95. K2: same with no rate row at all.
--   L  basic 1,200, taxable allowance 350, OT 400: basic alone is 14,400,
--      so it qualifies (basic + allowance would be 18,600 and would not).
--      Taxable 1,200 + 350 - 66 = 1,484; PAYE 14 + 716 x 17.5% = 139.30;
--      OT tax 20.00; net 1,724.70.
--   M  basic 1,200, OT 3.5h x 40.37 = 141.295, shown on the payslip as
--      141.30. Overtime tax is worked from the shown figure: 141.30 x 5% =
--      7.065, so 7.07. (From the unrounded 141.295 it would be 7.06475, so
--      7.06: the case pins the rounding basis.) Deductions 66 + 78.05 +
--      7.07 = 151.12; gross 1,341.30; net 1,190.18.
--   N  basic 1,200.20, OT 3 x 200.05 = 600.15: cap 600.10. 600.10 x 5% =
--      30.005, so 30.01; 0.05 x 10% = 0.005, so 0.01; overtime tax 30.02
--      (rounding only the sum would give 30.01). SSNIT 6.00, Tier 2 60.01;
--      taxable 1,134.19; PAYE 14 + 366.19 x 17.5% = 78.08; deductions
--      174.11; gross 1,800.35; net 1,626.24.
--   O  basic 1,000.19, OT 2 x 250.05 = 500.10, exactly the cap
--      round(500.095) = 500.10: all at 5%, 25.005, so 25.01 (an unrounded
--      cap would give 25.00). SSNIT 5.00, Tier 2 50.01; taxable 945.18;
--      PAYE 14 + 177.18 x 17.5% = 45.01; deductions 125.03; gross
--      1,500.29; net 1,375.26.
--
-- create_payslip() is gated by require_finance_writer(), so only Manager
-- and Accountant reach the assertions; a wrong figure turns their cell into
-- "denied!".
--
-- Section C: post_payroll_run() credits overtime tax to 2330 as its own
-- line (case A alone, October 2026: Dr 5140 1,600.00, Dr 5145 156.00; Cr 2300 1,435.95,
-- Cr 2310 6.00, Cr 2310 156.00, Cr 2320 60.00, Cr 2330 78.05 PAYE,
-- Cr 2330 20.00 overtime tax; 1,756.00 each side), and a run with no
-- overtime tax has no such line. Posting is Manager-only.
--
-- Section D: posted payslips. A payslip row written with the pre-migration
-- column list reads back with overtime_tax 0 and the concession false, and
-- a posted run still refuses new and deleted payslips.

-- probe: A1 read overtime_tax_rates
-- expect: Manager,Accountant,Auditor
delete from public.overtime_tax_rates;
insert into public.overtime_tax_rates (id, effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values ('9e270000-0000-0000-0000-0000000000c1', date '2090-01-01', 18000, 50, 5, 10);
-- as role:
do $$ begin
  if not exists (select 1 from public.overtime_tax_rates) then
    raise exception 'no rows visible';
  end if;
end $$;

-- probe: A2 insert overtime_tax_rates
-- expect: Manager,Accountant
delete from public.overtime_tax_rates;
-- as role:
insert into public.overtime_tax_rates (effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values (date '2090-01-01', 18000, 50, 5, 10);

-- probe: A3 update overtime_tax_rates
-- expect: Manager,Accountant
delete from public.overtime_tax_rates;
insert into public.overtime_tax_rates (id, effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values ('9e270000-0000-0000-0000-0000000000c1', date '2090-01-01', 18000, 50, 5, 10);
-- as role:
do $$
declare n integer;
begin
  update public.overtime_tax_rates set rate_above_cap_pct = 11;
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows updated'; end if;
end $$;

-- probe: A4 delete overtime_tax_rates
-- expect: Manager,Accountant
delete from public.overtime_tax_rates;
insert into public.overtime_tax_rates (id, effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values ('9e270000-0000-0000-0000-0000000000c1', date '2090-01-01', 18000, 50, 5, 10);
-- as role:
do $$
declare n integer;
begin
  delete from public.overtime_tax_rates;
  get diagnostics n = row_count;
  if n = 0 then raise exception '0 rows deleted'; end if;
end $$;

-- probe: A5 rejects a cap share over 100%
-- expect: none
delete from public.overtime_tax_rates;
-- as role:
insert into public.overtime_tax_rates (effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values (date '2090-01-01', 18000, 101, 5, 10);

-- probe: A6 rejects a negative rate
-- expect: none
delete from public.overtime_tax_rates;
-- as role:
insert into public.overtime_tax_rates (effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values (date '2090-01-01', 18000, 50, 5, -1);

-- probe: A7 rejects a negative threshold
-- expect: none
delete from public.overtime_tax_rates;
-- as role:
insert into public.overtime_tax_rates (effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values (date '2090-01-01', -1, 50, 5, 10);

-- probe: A8 rejects a second row for the same date
-- expect: none
delete from public.overtime_tax_rates;
insert into public.overtime_tax_rates (id, effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values ('9e270000-0000-0000-0000-0000000000c1', date '2090-01-01', 18000, 50, 5, 10);
-- as role:
insert into public.overtime_tax_rates (effective_from, qualifying_annual_basic_max,
  overtime_cap_pct_of_basic, rate_within_cap_pct, rate_above_cap_pct)
values (date '2090-01-01', 18000, 50, 5, 10);

-- probe: A9 exactly the 2026-10-01 row shipped
-- expect: anon,Attendant,Manager,Accountant,Auditor,Admissions Officer
create temp table ot_rate_rows as select string_agg(concat_ws(':', effective_from,
  qualifying_annual_basic_max, overtime_cap_pct_of_basic, rate_within_cap_pct,
  rate_above_cap_pct), ' ' order by effective_from) as rows from public.overtime_tax_rates;
grant select on ot_rate_rows to anon, authenticated;
-- as role:
do $$ begin
  if (select rows from ot_rate_rows) is distinct from '2026-10-01:18000.00:50.00:5.000:10.000' then
    raise exception 'overtime_tax_rates is %', (select rows from ot_rate_rows);
  end if;
end $$;

-- probe: B-A basic 1200, OT 400
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1600.00, 1134.00, 78.05, 20.00, true, 164.05, 1435.95) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-B basic 1200, OT 800
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 8, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (2000.00, 1134.00, 78.05, 50.00, true, 194.05, 1805.95) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-C basic 1900, OT 400, not qualifying
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (2300.00, 2195.50, 263.81, 0.00, false, 368.31, 1931.69) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-D basic 1500.00 (18,000), OT 300
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1500, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 3, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1800.00, 1417.50, 127.66, 15.00, true, 225.16, 1574.84) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-E basic 1500.01, OT 300, not qualifying
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1500.01, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 3, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1800.01, 1717.51, 180.16, 0.00, false, 262.66, 1537.35) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-F basic 1200, OT exactly 50% (600)
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 6, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1800.00, 1134.00, 78.05, 30.00, true, 174.05, 1625.95) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-G basic 1200, OT 601
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 6.01, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1801.00, 1134.00, 78.05, 30.10, true, 174.15, 1626.85) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-H basic 1200, OT 0
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 0, 0, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1200.00, 1134.00, 78.05, 0.00, false, 144.05, 1055.95) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-I National Service, OT 400
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', false, false, false);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1600.00, 1600.00, 0.00, 0.00, false, 0.00, 1600.00) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-J PAYE-exempt only, OT 400
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, false);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1600.00, 1534.00, 0.00, 0.00, false, 66.00, 1534.00) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-K September 2026, before the row
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1600.00, 1534.00, 148.05, 0.00, false, 214.05, 1385.95) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-K2 no rate row at all
-- expect: Manager,Accountant
delete from public.overtime_tax_rates;
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1600.00, 1534.00, 148.05, 0.00, false, 214.05, 1385.95) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-L basic 1200 + allowance 350, OT 400
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
insert into public.allowance_types (id, branch_id, name, taxable) values
  ('9e270000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'Overtime fixture allowance', true);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100, jsonb_build_array(jsonb_build_object('allowance_type_id', '9e270000-0000-0000-0000-0000000000b1', 'amount', 350)));
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1950.00, 1484.00, 139.30, 20.00, true, 225.30, 1724.70) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-M fractional: 3.5h x 40.37 = 141.295
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 3.5, 40.37, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1341.30, 1134.00, 78.05, 7.07, true, 151.12, 1190.18) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-N each part rounded: OT 600.15
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200.2, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 3, 200.05, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1800.35, 1134.19, 78.08, 30.02, true, 174.11, 1626.24) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: B-O cap rounded: OT 500.10 at cap
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1000.19, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
-- as role:
do $$
declare v public.payslips;
begin
  v := public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 2, 250.05, '[]'::jsonb);
  if (v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay)
     is distinct from (1500.29, 945.18, 45.01, 25.01, true, 125.03, 1375.26) then
    raise exception 'gross %, taxable %, tax %, ot tax %, concession %, deductions %, net %',
      v.gross_salary, v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession,
      v.total_deductions, v.net_pay;
  end if;
end $$;

-- probe: C1 post: overtime tax credited to 2330
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100);
update public.payroll_runs set status = 'Ready for Review' where id = '9e270000-0000-0000-0000-0000000000a1';
-- as role:
do $$
declare v_entry public.journal_entries; v_lines text;
begin
  v_entry := public.post_payroll_run('9e270000-0000-0000-0000-0000000000a1');
  select string_agg(concat_ws(':', a.code, l.debit, l.credit, l.description), ' | '
           order by l.position)
    into v_lines
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  where l.entry_id = v_entry.id;
  if v_lines is distinct from '5140:1600.00:0.00:Gross pay — October 2026 | '
     '2300:0.00:1435.95:Net pay payable — October 2026 | '
     '2310:0.00:6.00:SSNIT withheld — October 2026 | '
     '5145:156.00:0.00:Employer SSNIT contribution — October 2026 | '
     '2310:0.00:156.00:Employer SSNIT contribution — October 2026 | '
     '2320:0.00:60.00:Tier 2 withheld — October 2026 | '
     '2330:0.00:78.05:PAYE withheld — October 2026 | '
     '2330:0.00:20.00:Overtime tax withheld — October 2026' then
    raise exception 'lines: %', v_lines;
  end if;
end $$;

-- probe: C2 post: no overtime tax, no extra line
-- expect: Manager
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1900, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 10, 2026);
select set_config('request.jwt.claims', json_build_object('sub',
  (select id from public.staff where role = 'Manager' and active order by id limit 1),
  'role', 'authenticated')::text, true);
select 1 from public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100);
update public.payroll_runs set status = 'Ready for Review' where id = '9e270000-0000-0000-0000-0000000000a1';
-- as role:
do $$
declare v_entry public.journal_entries; v_lines text;
begin
  v_entry := public.post_payroll_run('9e270000-0000-0000-0000-0000000000a1');
  select string_agg(concat_ws(':', a.code, l.debit, l.credit, l.description), ' | '
           order by l.position)
    into v_lines
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  where l.entry_id = v_entry.id;
  if v_lines is distinct from '5140:2300.00:0.00:Gross pay — October 2026 | '
     '2300:0.00:1931.69:Net pay payable — October 2026 | '
     '2310:0.00:9.50:SSNIT withheld — October 2026 | '
     '5145:247.00:0.00:Employer SSNIT contribution — October 2026 | '
     '2310:0.00:247.00:Employer SSNIT contribution — October 2026 | '
     '2320:0.00:95.00:Tier 2 withheld — October 2026 | '
     '2330:0.00:263.81:PAYE withheld — October 2026' then
    raise exception 'lines: %', v_lines;
  end if;
end $$;

-- probe: D1 pre-migration posted payslip reads unchanged
-- expect: Manager,Accountant,Auditor
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 2090);
insert into public.payslips (id, payroll_run_id, employee_id, employee_pay_config_id,
  basic_salary, overtime_hours, overtime_rate, overtime_pay, total_allowances,
  total_earning, gross_salary, taxable_income, tax, tier2, ssnit, ssnit_employer,
  fines, iou, total_deductions, net_pay)
select '9e270000-0000-0000-0000-0000000000d1', '9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', c.id, 1200, 4, 100, 400, 0, 1600, 1600, 1534, 148.05,
  60, 6, 156, 0, 0, 214.05, 1385.95
from public.employee_pay_config c where c.employee_id = '9e270000-0000-0000-0000-000000000001';
update public.payroll_runs set status = 'Posted', posted_at = now() where id = '9e270000-0000-0000-0000-0000000000a1';
-- as role:
do $$
declare v public.payslips;
begin
  select * into v from public.payslips where payroll_run_id = '9e270000-0000-0000-0000-0000000000a1';
  if v.id is null then raise exception 'no rows visible'; end if;
  if (v.taxable_income, v.tax, v.overtime_tax, v.overtime_concession, v.total_deductions,
      v.net_pay) is distinct from (1534.00, 148.05, 0.00, false, 214.05, 1385.95) then
    raise exception 'posted payslip reads %', v;
  end if;
end $$;

-- probe: D2 create_payslip into a posted run
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 2090);
update public.payroll_runs set status = 'Posted', posted_at = now() where id = '9e270000-0000-0000-0000-0000000000a1';
-- as role:
select public.create_payslip('9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', 4, 100);

-- probe: D3 delete_payslip on a posted run
-- expect: none
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e270000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Overtime Fixture', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from,
  pays_ssnit, pays_tier2, pays_paye) values
  ('9e270000-0000-0000-0000-000000000001', 1200, date '2026-01-01', true, true, true);
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e270000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 2090);
insert into public.payslips (id, payroll_run_id, employee_id, employee_pay_config_id,
  basic_salary, overtime_hours, overtime_rate, overtime_pay, total_allowances,
  total_earning, gross_salary, taxable_income, tax, tier2, ssnit, ssnit_employer,
  fines, iou, total_deductions, net_pay)
select '9e270000-0000-0000-0000-0000000000d1', '9e270000-0000-0000-0000-0000000000a1', '9e270000-0000-0000-0000-000000000001', c.id, 1200, 4, 100, 400, 0, 1600, 1600, 1534, 148.05,
  60, 6, 156, 0, 0, 214.05, 1385.95
from public.employee_pay_config c where c.employee_id = '9e270000-0000-0000-0000-000000000001';
update public.payroll_runs set status = 'Posted', posted_at = now() where id = '9e270000-0000-0000-0000-0000000000a1';
-- as role:
select public.delete_payslip('9e270000-0000-0000-0000-0000000000d1');
