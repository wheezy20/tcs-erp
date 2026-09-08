import { ImportDialog, type ImportConfig, type RowCheck } from "@/components/import/import-dialog";
import { addCustomers, useCustomers, type NewCustomer } from "@/data/customer-store";

const COLUMNS = ["name", "phone", "email", "address"];
const EXAMPLE = [
  "Akosua Frimpong",
  "+233 24 000 1122",
  "akosua@example.com",
  "12 Osu Badu St, Accra",
];

const digits = (value: string) => value.replace(/\D/g, "").slice(-9);

export function ImportCustomersDialog() {
  const { customers } = useCustomers();

  const config: ImportConfig<NewCustomer> = {
    entity: "customers",
    description:
      "Bring in your contact list from a spreadsheet. Nothing is saved until you confirm, and rows with errors are never imported.",
    templateFile: "tcs-customers-template.csv",
    columns: COLUMNS,
    exampleRow: EXAMPLE,
    validate: (row, accepted): RowCheck<NewCustomer> => {
      const errors: string[] = [];
      const notes: string[] = [];

      const name = (row["name"] ?? "").trim();
      if (!name) errors.push("Name is required");

      const phone = (row["phone"] ?? "").trim();
      if (!phone) errors.push("Phone is required");
      else if (digits(phone).length < 9) errors.push(`Phone “${phone}” is not a valid number`);

      const email = (row["email"] ?? "").trim();
      if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        errors.push(`Email “${email}” is not valid`);
      }

      const address = (row["address"] ?? "").trim();
      if (!address) notes.push("no address given");

      const phoneKey = digits(phone);
      const nameKey = name.toLowerCase();
      const clash = (list: Array<{ name: string; phone: string }>) =>
        list.some((c) => digits(c.phone) === phoneKey || c.name.toLowerCase() === nameKey);
      if (name && clash(customers))
        errors.push("A customer with this name or phone already exists");
      else if (name && clash(accepted)) errors.push("Duplicate of an earlier row in this file");

      if (errors.length > 0) return { value: null, errors, notes };

      return {
        value: { name, phone, email, address },
        errors: [],
        notes,
      };
    },
    onImport: (values) => addCustomers(values),
  };

  return <ImportDialog config={config} />;
}
