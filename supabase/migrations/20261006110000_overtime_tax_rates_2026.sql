-- The first overtime_tax_rates row: GRA's concessionary overtime rule, in
-- effect for payroll months from October 2026.
--
-- Figures and effective date confirmed by Eyram on 2026-10-06, after TCS's
-- accountant approved the concession (accountant approval reported by
-- Eyram; the written copy is to be saved, docs/CONSTRAINTS.md):
--   * qualifying: basic salary x 12 not more than GHS 18,000;
--   * overtime up to 50% of monthly basic salary taxed at 5%;
--   * overtime above 50% of monthly basic salary taxed at 10%.
--
-- A data row, not a code change: create_payslip()
-- (20261006100000_overtime_tax_engine.sql) picks the row with the latest
-- effective_from on or before the first day of the payroll month. Months
-- before October 2026 have no row and keep today's treatment. Payslips
-- already generated are snapshots and are not recomputed; a Draft payslip
-- for October 2026 or later picks this up only if it is deleted and
-- generated again.
insert into public.overtime_tax_rates (
  effective_from, qualifying_annual_basic_max, overtime_cap_pct_of_basic,
  rate_within_cap_pct, rate_above_cap_pct
)
values (date '2026-10-01', 18000, 50, 5, 10)
on conflict (effective_from) do nothing;
