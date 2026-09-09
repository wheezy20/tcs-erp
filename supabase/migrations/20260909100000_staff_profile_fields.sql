-- Staff profile fields (TCS ERP — Staff Overview / directory).
--
-- Adds the contact / org-placement fields the Staff Overview screen edits
-- straight onto `staff`, and moves `position` / `department` there from
-- `staff_pay_config` (where the payroll migration put them one day earlier).
--
-- Why these columns belong on `staff`, not a separate table or
-- `staff_pay_config` (see docs/DESIGN.md, "Staff identity vs pay data"):
--
--   * `phone`, `position`, `department` are current-state, one-row-per-
--     person facts — the same shape as the `name` / `email` / `role` /
--     `active` columns already on `staff`. The effective-dated pattern
--     (`staff_pay_config`, `statutory_rates`, `paye_bands`) exists for
--     values that must be reconstructed as-of a historical date. Which
--     bank an old payslip paid into matters months later; which
--     department someone sits in does not — a payslip never reads it back
--     as-of its own month (create_payslip() snapshots amounts, not
--     org placement), it only shows the *current* value for display.
--
--   * A 1:1 `staff_profiles` side table would add a join for no gain:
--     `staff` is already the identity table and is already readable by
--     every active staff member (the app shows staff names on "Recorded
--     by" / "Issued by" everywhere). A phone/position/department directory
--     for a single-campus school is no more sensitive than `staff.name`,
--     so it rides the existing `staff_select` policy. If stricter
--     per-field read control is ever needed, THAT is when to split these
--     three columns into their own table with their own select policy.
--
--   * `bank` / `account_no` deliberately STAY on `staff_pay_config`. They
--     are pay data: each payslip's `staff_pay_config_id` FK ties it to the
--     exact bank details used, and the effective-dated correction/change
--     flow already manages edits. The Staff Overview screen shows them
--     read-only and links to Pay Config. Duplicating an editable copy onto
--     `staff` would create two sources of truth that silently diverge.
--
-- RLS / grants: nothing new. `staff` already has
--   * `staff_select`  = is_active_staff()          (every active staff member reads)
--   * `staff_update`   = has_role(array['Manager']) (Manager-only writes — same
--     policy that already gates role / active changes from Settings -> Staff)
--   * `grant select, update on public.staff to authenticated`
-- so a Manager can already UPDATE these new columns and no one else can.
-- Editing staff records stays Manager-only on purpose: this is org-admin /
-- HR data, not one of the finance modules (Payroll / Accounting /
-- Expenses) the 20260909090000 split opened up to the Accountant role. A
-- dedicated HR-equivalent permission can come later (docs/CONSTRAINTS.md:
-- "don't invent a fifth role" for now).
--
-- `protect_staff_row()` (Session 20) only freezes role / active / protected
-- on a protected row — it does NOT block these columns, so a Manager can
-- still keep the protected account's contact details current.

alter table public.staff
  add column phone text,
  add column position text,
  add column department text;

-- Move the two org-placement columns off staff_pay_config. They were added
-- there in 20260908070000 (payroll) the day before this migration; the
-- table has only seed rows so far and the payslip UI already reads these
-- live rather than from a per-payslip snapshot, so there is no history to
-- preserve and no payslip semantics change.
alter table public.staff_pay_config
  drop column position,
  drop column department;
