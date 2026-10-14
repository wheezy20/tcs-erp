-- Slice 7c: the Accountant stops reading admissions audit rows
-- (docs/admissions/PORT-PLAN.md, slice 7c; D-1b: the Accountant gets no
-- admissions access).
--
-- Before this, audit_log_select let Manager, Accountant and Auditor read
-- every row, so an Accountant could read decision outcomes by APP
-- reference, offer changes and who holds the health gate through the API.
--
-- After: Manager and Auditor read every row, as before. The Accountant
-- reads every row except the admissions ones, which are the actions
-- starting with application_ or admissions_ (9 of the 37 today). Every
-- other action, including the payroll, pay config and employee ones the
-- employee History section reads, stays visible to the Accountant.
--
-- Naming rule this relies on: every admissions audit action starts with
-- application_ or admissions_, and no other action does. The 7c probe
-- file lists all 37 actions in their two groups, so a new action fails it
-- until someone classifies it.
--
-- Policy only. No function, grant or table change; audit_log stays
-- select-only for authenticated with no write grant for anyone, and the
-- anon-executable function count stays 169.

drop policy audit_log_select on public.audit_log;

create policy audit_log_select on public.audit_log
for select
using (
  public.has_role(array['Manager', 'Auditor'])
  or (
    public.has_role(array['Accountant'])
    and not (starts_with(action, 'application_') or starts_with(action, 'admissions_'))
  )
);
