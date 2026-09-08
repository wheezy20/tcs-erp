import { createFileRoute } from "@tanstack/react-router";

import { InvoiceForm } from "@/components/sales/invoice-form";

export const Route = createFileRoute("/sales/new")({
  head: () => ({
    meta: [
      { title: "New invoice — TCS" },
      {
        name: "description",
        content:
          "Create an invoice: pick a customer, add inventory line items, apply discounts and VAT, and log a payment.",
      },
      { property: "og:title", content: "New invoice — TCS" },
      { property: "og:description", content: "Build an invoice with discounts, VAT and payments." },
    ],
  }),
  // Optional deep-link from a customer deposit's "Fulfil with an invoice"
  // action — the form pre-selects that customer and applies the deposit as
  // a payment once the invoice is created.
  validateSearch: (search: Record<string, unknown>): { depositId?: string } => ({
    depositId: typeof search.depositId === "string" ? search.depositId : undefined,
  }),
  component: SalesNewPage,
});

function SalesNewPage() {
  const { depositId } = Route.useSearch();
  return <InvoiceForm depositId={depositId} />;
}
