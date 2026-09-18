-- PAYE bands sourced directly from GRA's published schedule (TCS ERP —
-- go-live checklist item, docs/CONSTRAINTS.md).
--
-- The 20260908070000 seed rows were already exactly GRA's real monthly
-- figures for every band except the top two — this migration corrects
-- only those, it isn't a wholesale replacement.
--
-- paye_bands stores MONTHLY thresholds, confirmed against create_payslip()
-- (20260909130000_employees_and_approval_workflow.sql): v_taxable_income
-- is built directly from employee_pay_config.basic_salary (a monthly
-- figure) plus monthly overtime/allowances minus monthly SSNIT/Tier2, and
-- compared straight against paye_bands.lower_bound/upper_bound with no
-- annualization step anywhere in the loop. GRA's published figures below
-- are already monthly, so no conversion was needed.
--
-- GRA's own table (gra.gov.gh, labeled "Year 2024") has an internal
-- rounding inconsistency: summing every band's own published width
-- arithmetically reaches an upper bound of 50,416.67 (which is where the
-- original placeholder got that figure from), but the table's own
-- top-band row is explicitly labeled "Exceeding 50,000.00". Confirmed
-- with Eyram: 50,000 is authoritative here — GRA's literal stated
-- threshold, not the arithmetic sum. The 30% band now runs 19,896.67 ->
-- 50,000 and the 35% band starts exactly at 50,000, so every taxable
-- cedi is still covered by exactly one band with no gap or overlap —
-- this narrows the 30% band by GHS 416.67 relative to the old
-- placeholder, it doesn't leave anything uncovered.
--
-- Not yet re-confirmed against any GRA revision published after the
-- "Year 2024" table this was sourced from (docs/CONSTRAINTS.md).
update public.paye_bands
set upper_bound = 50000
where effective_from = date '2025-01-01' and band_order = 6 and upper_bound = 50416.67;

update public.paye_bands
set lower_bound = 50000
where effective_from = date '2025-01-01' and band_order = 7 and lower_bound = 50416.67;
