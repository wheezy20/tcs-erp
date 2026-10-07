-- Payroll money and hours inputs: more than 2 decimal places, or a negative
-- value, is refused, not rounded or accepted.
--
-- Decisions: Eyram, as owner, 2026-10-07 (recommended to the accountant).
-- Any payroll input that is a money amount or an hours figure must have at
-- most 2 decimal places and must not be negative, enforced in the database
-- so the form cannot be bypassed. Zero stays allowed on all seven, basic
-- salary included: the schema has allowed a zero basic salary since
-- 20260908070000 ("Basic salary must be zero or more"), e.g. for a
-- Volunteer or Intern paid only allowances. Before this, numeric(12,2) /
-- numeric(8,2) columns rounded such inputs silently on write, while
-- create_payslip computed from the exact value (e.g. 2.555 h at 40.00
-- printed "2.56h @ 40.00" beside 102.20), and fines, IOU, overtime hours
-- and rate had no check against a negative value.
--
-- The inputs, and every path that writes them:
--   employee_pay_config.basic_salary   propose_employee, propose_pay_config_change,
--                                      approve_employee, approve_pay_config
--   employee_allowances.default_amount direct insert/update (RLS, Manager/Accountant)
--   payslips.overtime_hours            create_payslip
--   payslips.overtime_rate             create_payslip
--   payslips.fines                     create_payslip
--   payslips.iou                       create_payslip
--   payslip_allowances.amount          create_payslip
--
-- A numeric(p,2) column rounds the value while coercing it to the column
-- type, before any BEFORE trigger or check constraint sees it, so a third
-- decimal cannot be detected there. These seven columns therefore become
-- plain numeric (relaxing a numeric typmod is binary-coercible: no rewrite,
-- and it cannot fail on existing rows), and:
--   * a BEFORE INSERT OR UPDATE trigger refuses NaN, infinity or an
--     out-of-range value, a negative value, and more than 2 dp, each with a
--     message the form shows, then stores round(value, 2), so stored values
--     keep scale 2 as before;
--   * check constraints are the backstop: per column value = round(value, 2)
--     and the bound the old typmod gave (below 10^10, hours below 10^6), and
--     value >= 0 (basic_salary, default_amount and payslip_allowances.amount
--     already had that check; the four payslips inputs get one here).
-- The basic-salary RPCs already refuse a negative salary with their own
-- message before inserting, so the trigger's message shows on the other paths.
-- No function body, grant or RLS policy changes. Computed payslip columns
-- (gross, tax, net, ...) keep numeric(12,2). Rate tables are out of scope.
-- Existing rows are all scale 2 already, so the new checks hold for them.

-- ============================================================ 1. trigger function

-- TG_ARGV: one 'column:Label:bound' entry per checked column.
create function public._refuse_over_2dp()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_arg text;
  v_col text;
  v_label text;
  v_bound numeric;
  v_raw text;
  v_value numeric;
  v_fix jsonb := '{}'::jsonb;
begin
  foreach v_arg in array TG_ARGV loop
    v_col := split_part(v_arg, ':', 1);
    v_label := split_part(v_arg, ':', 2);
    v_bound := split_part(v_arg, ':', 3)::numeric;
    v_raw := to_jsonb(NEW) ->> v_col;
    continue when v_raw is null;
    v_value := v_raw::numeric;
    if v_value = 'NaN'::numeric or abs(v_value) >= v_bound then
      raise exception '% is not a valid amount (got %)', v_label, v_raw
        using errcode = '22023';
    end if;
    if v_value < 0 then
      raise exception '% cannot be negative (got %)', v_label, v_raw
        using errcode = '22023';
    end if;
    if v_value <> round(v_value, 2) then
      raise exception '% must have at most 2 decimal places (got %)', v_label, v_raw
        using errcode = '22023';
    end if;
    v_fix := v_fix || jsonb_build_object(v_col, round(v_value, 2));
  end loop;
  return jsonb_populate_record(NEW, v_fix);
end;
$$;

revoke all on function public._refuse_over_2dp() from public, anon, authenticated;

-- ============================================================ 2. columns

alter table public.employee_pay_config
  alter column basic_salary type numeric,
  add constraint employee_pay_config_basic_salary_2dp
    check (basic_salary = round(basic_salary, 2) and abs(basic_salary) < 1e10);

alter table public.employee_allowances
  alter column default_amount type numeric,
  add constraint employee_allowances_default_amount_2dp
    check (default_amount = round(default_amount, 2) and abs(default_amount) < 1e10);

alter table public.payslips
  alter column overtime_hours type numeric,
  alter column overtime_rate type numeric,
  alter column fines type numeric,
  alter column iou type numeric,
  add constraint payslips_overtime_hours_2dp
    check (overtime_hours = round(overtime_hours, 2) and abs(overtime_hours) < 1e6),
  add constraint payslips_overtime_rate_2dp
    check (overtime_rate = round(overtime_rate, 2) and abs(overtime_rate) < 1e10),
  add constraint payslips_fines_2dp
    check (fines = round(fines, 2) and abs(fines) < 1e10),
  add constraint payslips_iou_2dp
    check (iou = round(iou, 2) and abs(iou) < 1e10),
  add constraint payslips_overtime_hours_check check (overtime_hours >= 0),
  add constraint payslips_overtime_rate_check check (overtime_rate >= 0),
  add constraint payslips_fines_check check (fines >= 0),
  add constraint payslips_iou_check check (iou >= 0);

alter table public.payslip_allowances
  alter column amount type numeric,
  add constraint payslip_allowances_amount_2dp
    check (amount = round(amount, 2) and abs(amount) < 1e10);

-- ============================================================ 3. triggers

create trigger employee_pay_config_inputs_2dp
  before insert or update on public.employee_pay_config
  for each row execute function public._refuse_over_2dp('basic_salary:Basic salary:1e10');

create trigger employee_allowances_inputs_2dp
  before insert or update on public.employee_allowances
  for each row execute function public._refuse_over_2dp('default_amount:Allowance amount:1e10');

create trigger payslips_inputs_2dp
  before insert or update on public.payslips
  for each row execute function public._refuse_over_2dp(
    'overtime_hours:Overtime hours:1e6',
    'overtime_rate:Overtime rate:1e10',
    'fines:Fines:1e10',
    'iou:IOU:1e10');

create trigger payslip_allowances_inputs_2dp
  before insert or update on public.payslip_allowances
  for each row execute function public._refuse_over_2dp('amount:Allowance amount:1e10');
