-- PAYE bands for GRA's "Year of Assessment 2026" (gra.gov.gh PAYE page),
-- effective 1 September 2026. Confirmed by Eyram on 2026-09-29 and
-- checked against the GRA page the same day (docs/JOURNAL.md).
--
-- A new effective-dated set, not an edit: the 2025-01-01 set stays exactly
-- as it is, so payslips for August 2026 and earlier keep computing (and
-- keep their snapshotted figures) under it. create_payslip()
-- (20260909130000_employees_and_approval_workflow.sql) already picks the
-- set with the latest effective_from on or before the first day of the
-- payroll run's month, so a run for 2026-09 onward picks this set up with
-- no function change.
--
-- Monthly figures, like the 2025-01-01 set: first 588 at 0%, next 80 at
-- 5%, next 100 at 10%, next 2,900 at 17.5%, next 16,000 at 25%, next
-- 30,332 at 30%, exceeding 50,000 at 35%. Unlike the Year 2024 table, the
-- band widths here sum exactly to GRA's stated 50,000 top threshold.
--
-- Hand cross-checks the engine reproduces (supabase/role-matrix/
-- 20260929120000_paye_bands_2026.sql): taxable 1,795.50 -> 193.81,
-- 1,606.50 -> 160.74, 6,142.50 -> 1,140.13.
insert into public.paye_bands (effective_from, lower_bound, upper_bound, rate, band_order)
values
  (date '2026-09-01', 0, 588, 0, 1),
  (date '2026-09-01', 588, 668, 5, 2),
  (date '2026-09-01', 668, 768, 10, 3),
  (date '2026-09-01', 768, 3668, 17.5, 4),
  (date '2026-09-01', 3668, 19668, 25, 5),
  (date '2026-09-01', 19668, 50000, 30, 6),
  (date '2026-09-01', 50000, null, 35, 7)
on conflict (effective_from, band_order) do nothing;
