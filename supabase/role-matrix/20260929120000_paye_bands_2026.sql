-- Role matrix for 20260929120000_paye_bands_2026 (the 2026 PAYE band set,
-- effective 2026-09-01). No RPC or RLS change: these probes drive the
-- existing create_payslip() end to end and check its snapshotted tax and
-- net pay, so they prove the engine picks the band set by payroll month.
-- Run: ./scripts/seed-local-dev-staff.sh
--      ./scripts/role-matrix.sh supabase/role-matrix/20260929120000_paye_bands_2026.sql
--
-- Cross-check figures (Eyram, 2026-09-29). Basic salary only, no overtime,
-- allowances, fines or IOU; SSNIT 0.5% + Tier 2 5% of basic come off before
-- PAYE:
--   Emmanuel Ansah  basic 6,500 -> taxable 6,142.50 -> PAYE 1,140.13, net 5,002.37
--   Abena           basic 1,900 -> taxable 1,795.50 -> PAYE   193.81, net 1,601.69
--   Yaw             basic 1,700 -> taxable 1,606.50 -> PAYE   160.74, net 1,445.76
-- Under the old 2025-01-01 set (an August 2026 run), the same three give
-- PAYE 1,134.13 / 204.96 / 171.89 and net 5,008.37 / 1,590.54 / 1,434.61.
-- Emmanuel's 5,008.37 is the TCS OS payroll parity figure
-- (docs/CONSTRAINTS.md), so the August probe also holds the old engine to
-- a result verified outside this repo.
--
-- create_payslip() is gated by require_finance_writer(), so only Manager
-- and Accountant get as far as the assertions; anon and the other roles
-- are stopped by that guard before any payslip is written.
-- A wrong figure turns their cell into "denied!".

-- probe: new 2026-09-01 set present, old set untouched
-- expect: Manager,Accountant,Auditor
-- as role:
do $$ begin
  if (select string_agg(concat_ws(':', lower_bound, upper_bound, rate), ' ' order by band_order)
      from public.paye_bands where effective_from = date '2026-09-01')
     is distinct from
     '0.00:588.00:0.000 588.00:668.00:5.000 668.00:768.00:10.000 768.00:3668.00:17.500 '
     '3668.00:19668.00:25.000 19668.00:50000.00:30.000 50000.00:35.000' then
    raise exception '2026-09-01 band set is not the confirmed GRA 2026 set';
  end if;
  if (select string_agg(concat_ws(':', lower_bound, upper_bound, rate), ' ' order by band_order)
      from public.paye_bands where effective_from = date '2025-01-01')
     is distinct from
     '0.00:490.00:0.000 490.00:600.00:5.000 600.00:730.00:10.000 730.00:3896.67:17.500 '
     '3896.67:19896.67:25.000 19896.67:50000.00:30.000 50000.00:35.000' then
    raise exception '2025-01-01 band set has changed';
  end if;
end $$;

-- probe: September 2026 payslips use the 2026 bands
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e260000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Emmanuel Ansah', 'Active'),
  ('9e260000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Abena', 'Active'),
  ('9e260000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Yaw', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from) values
  ('9e260000-0000-0000-0000-000000000001', 6500, date '2026-01-01'),
  ('9e260000-0000-0000-0000-000000000002', 1900, date '2026-01-01'),
  ('9e260000-0000-0000-0000-000000000003', 1700, date '2026-01-01');
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e260000-0000-0000-0000-0000000000a9', '00000000-0000-0000-0000-000000000001', 9, 2026);
-- as role:
do $$
declare
  v_run constant uuid := '9e260000-0000-0000-0000-0000000000a9';
  v public.payslips;
begin
  v := public.create_payslip(v_run, '9e260000-0000-0000-0000-000000000001');
  if (v.taxable_income, v.tax, v.net_pay) is distinct from (6142.50, 1140.13, 5002.37) then
    raise exception 'Emmanuel Sep 2026: taxable %, tax %, net %', v.taxable_income, v.tax, v.net_pay;
  end if;
  v := public.create_payslip(v_run, '9e260000-0000-0000-0000-000000000002');
  if (v.taxable_income, v.tax, v.net_pay) is distinct from (1795.50, 193.81, 1601.69) then
    raise exception 'Abena Sep 2026: taxable %, tax %, net %', v.taxable_income, v.tax, v.net_pay;
  end if;
  v := public.create_payslip(v_run, '9e260000-0000-0000-0000-000000000003');
  if (v.taxable_income, v.tax, v.net_pay) is distinct from (1606.50, 160.74, 1445.76) then
    raise exception 'Yaw Sep 2026: taxable %, tax %, net %', v.taxable_income, v.tax, v.net_pay;
  end if;
end $$;

-- probe: August 2026 payslips still use the old bands
-- expect: Manager,Accountant
insert into public.employees (id, branch_id, name, employment_status) values
  ('9e260000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Emmanuel Ansah', 'Active'),
  ('9e260000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Abena', 'Active'),
  ('9e260000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Yaw', 'Active');
insert into public.employee_pay_config (employee_id, basic_salary, effective_from) values
  ('9e260000-0000-0000-0000-000000000001', 6500, date '2026-01-01'),
  ('9e260000-0000-0000-0000-000000000002', 1900, date '2026-01-01'),
  ('9e260000-0000-0000-0000-000000000003', 1700, date '2026-01-01');
insert into public.payroll_runs (id, branch_id, month, year) values
  ('9e260000-0000-0000-0000-0000000000a8', '00000000-0000-0000-0000-000000000001', 8, 2026);
-- as role:
do $$
declare
  v_run constant uuid := '9e260000-0000-0000-0000-0000000000a8';
  v public.payslips;
begin
  v := public.create_payslip(v_run, '9e260000-0000-0000-0000-000000000001');
  if (v.taxable_income, v.tax, v.net_pay) is distinct from (6142.50, 1134.13, 5008.37) then
    raise exception 'Emmanuel Aug 2026: taxable %, tax %, net %', v.taxable_income, v.tax, v.net_pay;
  end if;
  v := public.create_payslip(v_run, '9e260000-0000-0000-0000-000000000002');
  if (v.taxable_income, v.tax, v.net_pay) is distinct from (1795.50, 204.96, 1590.54) then
    raise exception 'Abena Aug 2026: taxable %, tax %, net %', v.taxable_income, v.tax, v.net_pay;
  end if;
  v := public.create_payslip(v_run, '9e260000-0000-0000-0000-000000000003');
  if (v.taxable_income, v.tax, v.net_pay) is distinct from (1606.50, 171.89, 1434.61) then
    raise exception 'Yaw Aug 2026: taxable %, tax %, net %', v.taxable_income, v.tax, v.net_pay;
  end if;
end $$;
