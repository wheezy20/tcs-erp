import { Upload } from "lucide-react";

import { Button } from "@/components/ui/button";
import { ImportDialog, type ImportConfig } from "@/components/import/import-dialog";
import { importEmployees, previewEmployeeImport } from "@/data/employees-store";

// Bulk upload of employees (20261009100000). Every check — required
// fields, money, dates, Yes/No flags, lists, duplicates, the example row —
// is done by the database (preview_employee_import / import_employees).
// This file only holds the template: column headers, the key the database
// expects for each, and one example row. Only Name is required; every other
// column may be left blank and filled in by hand after the upload. Each imported row becomes a
// Pending Approval proposal, exactly as "Propose employee" makes one.

const COLUMNS: [header: string, key: string][] = [
  ["Name (required)", "name"],
  ["Preferred name", "preferred_name"],
  ["Phone", "phone"],
  ["Gender", "gender"],
  ["Date of birth", "date_of_birth"],
  ["National ID", "national_id"],
  ["Personal email", "personal_email"],
  ["School email", "school_email"],
  ["Position", "position"],
  ["Department", "department"],
  ["Employment type", "employment_type"],
  ["Start date", "start_date"],
  ["Probation end date", "probation_end_date"],
  ["Contract end date", "contract_end_date"],
  ["SSNIT number", "ssnit_number"],
  ["TIN number", "tin_number"],
  ["Church denomination", "church_denomination"],
  ["Emergency contact name", "emergency_contact_name"],
  ["Emergency contact phone", "emergency_contact_phone"],
  ["Residential address", "residential_address"],
  ["Basic salary", "basic_salary"],
  ["Payment method", "payment_method"],
  ["Bank or network", "bank"],
  ["Account or wallet number", "account_no"],
  ["Effective from", "effective_from"],
  ["Pays SSNIT", "pays_ssnit"],
  ["Pays Tier 2", "pays_tier2"],
  ["Pays PAYE", "pays_paye"],
];

// Invented values. The database refuses this row if it's uploaded
// unchanged ("Delete the example row before uploading"), by its name:
// keep `name` in step with c_example_name in _employee_import_check()
// (20261009100000), which compares it upper-cased.
const EXAMPLE: Record<string, string> = {
  name: "Example Employee - Delete This Row",
  phone: "0240000000",
  gender: "Female",
  date_of_birth: "1990-01-31",
  personal_email: "example@example.com",
  position: "Administrator",
  department: "Administration",
  employment_type: "Full-Time",
  start_date: "2026-11-01",
  basic_salary: "2500.00",
  payment_method: "Bank",
  bank: "GCB Bank",
  account_no: "0000000000",
  effective_from: "2026-11-01",
  pays_ssnit: "Yes",
  pays_tier2: "Yes",
  pays_paye: "Yes",
};

export function ImportEmployeesDialog() {
  const config: ImportConfig<never> = {
    entity: "employees",
    description:
      "Add many employees from a spreadsheet. Only Name is required; leave any other column blank and fill it in by hand later. Every row is checked first and nothing is saved until you confirm; if any row has a problem, fix the file and upload it again. Each employee is created as a proposal for a Manager to approve, with their pay as a proposed pay config. Dates are YYYY-MM-DD. Employment type is Full-Time, Part-Time, Contract, Volunteer, Intern or National Service. Pay details need a basic salary. Pays SSNIT, Tier 2 and PAYE are Yes or No; left blank on a row with a salary they count as Yes, with a warning. National Service staff should be entered as No, No, No: the employment type never sets these. Staff logins and standing allowances are added by hand afterwards.",
    templateFile: "tcs-employees-template.xlsx",
    columns: COLUMNS.map(([header]) => header),
    exampleRow: COLUMNS.map(([, key]) => EXAMPLE[key] ?? ""),
    remote: {
      keys: COLUMNS.map(([, key]) => key),
      parseOptions: { isoDates: true },
      xlsxTemplate: true,
      check: previewEmployeeImport,
      importRows: async (rows) => {
        const { created, withPayConfig } = await importEmployees(rows);
        return `${created} employee${created === 1 ? "" : "s"} proposed (${withPayConfig} with pay) — waiting for Manager approval`;
      },
    },
  };

  return (
    <ImportDialog
      config={config}
      trigger={
        <Button variant="outline">
          <Upload className="size-4" /> Import employees
        </Button>
      }
    />
  );
}
