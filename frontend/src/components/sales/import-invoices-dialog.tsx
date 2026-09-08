import { ImportDialog, type ImportConfig, type RowCheck } from "@/components/import/import-dialog";
import { useCurrentBranch } from "@/data/branch-store";
import type { NewInvoice } from "@/data/invoice-store";
import { useInventory } from "@/data/inventory-store";
import { DEFAULT_VAT_RATE, type Invoice } from "@/data/invoices";
import { addPayment, createInvoice, useSales } from "@/data/sales-store";
import { isIsoDate, matchOption, toBoolean, toNumber } from "@/lib/import/parse";

const loose = (value: string) =>
  value
    .toLowerCase()
    .replace(/[×x]/g, "x")
    .replace(/[^a-z0-9]+/g, "");

const COLUMNS = [
  "date",
  "customer name",
  "product name",
  "quantity",
  "unit price",
  "discount",
  "VAT applied",
  "amount paid",
];

const EXAMPLE = [
  "2026-07-28",
  "Kwame Asante",
  "Tile Adhesive C1 — Grey 20kg",
  "10",
  "72",
  "0",
  "Yes",
  "500",
];

type ImportRow = {
  invoice: NewInvoice;
  paidAmount: number;
};

type InvoiceKeyFields = Pick<Invoice, "date" | "customerName" | "lines">;

export function ImportInvoicesDialog() {
  const { invoices, customers } = useSales();
  const { products } = useInventory();
  const { name: branchName } = useCurrentBranch();

  const config: ImportConfig<ImportRow> = {
    entity: "invoices",
    description:
      "Each row becomes an invoice with a single line item. Nothing is saved until you confirm, and rows with errors are never imported.",
    templateFile: "tcs-sales-template.csv",
    columns: COLUMNS,
    exampleRow: EXAMPLE,
    validate: (row, accepted): RowCheck<ImportRow> => {
      const errors: string[] = [];
      const notes: string[] = [];

      const date = (row["date"] ?? "").trim();
      if (!date) errors.push("Date is required");
      else if (!isIsoDate(date)) errors.push(`Date “${date}” must be formatted YYYY-MM-DD`);

      const customerName = (row["customer name"] ?? "").trim();
      if (!customerName) errors.push("Customer name is required");
      const customer =
        customers.find((c) => c.name.trim().toLowerCase() === customerName.toLowerCase()) ??
        customers.find((c) => loose(c.name) === loose(customerName));
      // An invoice needs a real, billable customer record now that
      // customer_id is a not-null foreign key — unlike POS, which can bill a
      // walk-in with no customer at all, Sales & Invoicing always has one.
      if (customerName && !customer) {
        errors.push(
          `Customer “${customerName}” doesn't exist yet — add them under Customers first`,
        );
      } else if (customer && customer.name !== customerName) {
        notes.push(`matched “${customer.name}”`);
      }

      const productName = (row["product name"] ?? "").trim();
      if (!productName) errors.push("Product name is required");
      const product =
        products.find((p) => p.name.trim().toLowerCase() === productName.toLowerCase()) ??
        products.find((p) => loose(p.name) === loose(productName));
      if (productName && !product) errors.push(`Product “${productName}” is not in Inventory`);
      else if (product && product.name !== productName) notes.push(`matched “${product.name}”`);

      const numeric = (key: string, label: string, required: boolean) => {
        const raw = (row[key] ?? "").trim();
        if (!raw) {
          if (required) errors.push(`${label} is required`);
          return null;
        }
        const n = toNumber(raw);
        if (n === null) errors.push(`${label} “${raw}” is not a number`);
        else if (n < 0) errors.push(`${label} cannot be negative`);
        return n;
      };

      const quantity = numeric("quantity", "Quantity", true);
      if (quantity !== null && quantity <= 0) errors.push("Quantity must be greater than zero");
      const unitPrice = numeric("unit price", "Unit price", true);
      const discount = numeric("discount", "Discount", false) ?? 0;
      const paid = numeric("amount paid", "Amount paid", false) ?? 0;

      const rawVat = (row["VAT applied"] ?? "").trim();
      const vat = toBoolean(rawVat);
      if (vat === null) errors.push(`VAT applied “${rawVat}” must be Yes or No`);

      const dupKey = `${date}|${customerName.toLowerCase()}|${productName.toLowerCase()}|${quantity ?? ""}`;
      const keyOf = (invoice: InvoiceKeyFields) =>
        `${invoice.date}|${invoice.customerName.toLowerCase()}|${(invoice.lines[0]?.name ?? "").toLowerCase()}|${invoice.lines[0]?.quantity ?? ""}`;
      if (invoices.some((i) => keyOf(i) === dupKey))
        errors.push("An identical invoice already exists");
      else if (accepted.some((r) => keyOf(r.invoice) === dupKey))
        errors.push("Duplicate of an earlier row in this file");

      if (quantity !== null && unitPrice !== null && discount > quantity * unitPrice) {
        errors.push("Discount is larger than the line total");
      }

      if (errors.length > 0) return { value: null, errors, notes };

      const due = new Date(`${date}T00:00:00Z`);
      due.setUTCDate(due.getUTCDate() + 14);

      return {
        value: {
          invoice: {
            customerId: customer!.id,
            customerName: customer!.name,
            date,
            dueDate: due.toISOString().slice(0, 10),
            branch: branchName ?? "",
            notes: "Imported from spreadsheet.",
            lines: [
              {
                id: "L1",
                productId: product!.id,
                name: product!.name,
                unit: product!.unit,
                quantity: quantity!,
                unitPrice: unitPrice!,
                discount,
                vat: vat!,
              },
            ],
            invoiceDiscount: 0,
            vatRate: DEFAULT_VAT_RATE,
            // Bulk import has no per-row way to express a WHT decision —
            // nothing in this session's brief asked for one, and a WHT
            // invoice needs a deliberate, per-invoice toggle, not a
            // spreadsheet default.
            whtApplied: false,
          },
          paidAmount: paid,
        },
        errors: [],
        notes,
      };
    },
    onImport: async (values) => {
      // Sequential rather than Promise.all: each row's payment depends on
      // that row's invoice existing first. Numbering itself is now an
      // atomic server-side counter (create_invoice()), so this is no longer
      // load-bearing for uniqueness the way it was with the old client-side
      // nextInvoiceId() — just kept simple and bounded.
      for (const { invoice, paidAmount } of values) {
        const created = await createInvoice(invoice);
        if (paidAmount > 0) {
          await addPayment(created.id, {
            date: invoice.date,
            amount: paidAmount,
            method: "Cash",
            reference: "Bulk import",
          });
        }
      }
    },
  };

  return <ImportDialog config={config} />;
}
