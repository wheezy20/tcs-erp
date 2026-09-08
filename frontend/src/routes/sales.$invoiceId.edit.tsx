import { createFileRoute, Link } from "@tanstack/react-router";

import { InvoiceForm } from "@/components/sales/invoice-form";
import { useSales } from "@/data/sales-store";

export const Route = createFileRoute("/sales/$invoiceId/edit")({
  head: () => ({
    meta: [
      { title: "Edit invoice — TCS" },
      {
        name: "description",
        content: "Update invoice line items, discounts, VAT and customer details.",
      },
      { property: "og:title", content: "Edit invoice — TCS" },
      {
        property: "og:description",
        content: "Update line items, discounts and VAT on an existing invoice.",
      },
    ],
  }),
  component: EditInvoicePage,
});

function EditInvoicePage() {
  const { invoiceId } = Route.useParams();
  const { invoices } = useSales();
  const invoice = invoices.find((i) => i.id === invoiceId);

  if (!invoice) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">This invoice no longer exists</p>
        <Link to="/sales" className="mt-3 inline-block text-sm text-primary hover:underline">
          Back to invoices
        </Link>
      </div>
    );
  }

  return <InvoiceForm key={invoice.id} existing={invoice} />;
}
