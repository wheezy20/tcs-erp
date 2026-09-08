import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Mail, MapPin, Phone } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { ExportMenu } from "@/components/export-menu";
import { currency, currencyPrecise } from "@/data/dashboard";
import { invoiceTotals, type Invoice, type InvoicePayment } from "@/data/invoices";
import { useSales } from "@/data/sales-store";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/customers/$customerId")({
  head: () => ({
    meta: [
      { title: "Customer details — TCS Customers" },
      {
        name: "description",
        content: "Contact details, balance, orders and payment history for a TCS customer.",
      },
      { property: "og:title", content: "Customer details — TCS Customers" },
      {
        property: "og:description",
        content: "Contact details, balance, orders and payment history for a TCS customer.",
      },
    ],
  }),
  component: CustomerProfile,
});

function itemsSummary(invoice: Invoice) {
  return invoice.lines.map((l) => `${l.name} x${l.quantity}`).join(", ");
}

function CustomerProfile() {
  const { customerId } = Route.useParams();
  const { customers, invoices } = useSales();
  const customer = customers.find((c) => c.id === customerId);

  if (!customer) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">This customer no longer exists</p>
        <Link to="/customers" className="mt-3 inline-block text-sm text-primary hover:underline">
          Back to customers
        </Link>
      </div>
    );
  }

  // Derived from real invoices (Session 3) rather than stored on the
  // customer record — see the "orders" note in the customers migration.
  const orders = invoices
    .filter((i) => i.customerId === customerId)
    .slice()
    .sort((a, b) => (a.date < b.date ? 1 : -1));
  const payments = orders.flatMap((i) => i.payments).sort((a, b) => (a.date < b.date ? 1 : -1));

  return (
    <>
      <Link
        to="/customers"
        className="mb-4 inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="size-4" /> Back to customers
      </Link>

      <PageHeader
        title={customer.name}
        description={`${customer.type} customer · Customer since ${customer.since}`}
        actions={
          <>
            <ExportMenu
              baseName="customer"
              filters={[customer.name]}
              summary={`${orders.length} orders · ${payments.length} payments`}
              disabled={orders.length === 0 && payments.length === 0}
              getSheets={() => [
                {
                  name: "Recent orders",
                  columns: [
                    { header: "Invoice", value: (i: Invoice) => i.id },
                    { header: "Date", value: (i: Invoice) => formatDate(i.date) },
                    { header: "Items", value: (i: Invoice) => itemsSummary(i) },
                    { header: "Status", value: (i: Invoice) => invoiceTotals(i).status },
                    { header: "Total (GHS)", value: (i: Invoice) => invoiceTotals(i).total },
                  ],
                  rows: orders,
                },
                {
                  name: "Payment history",
                  columns: [
                    { header: "Date", value: (p: InvoicePayment) => formatDate(p.date) },
                    { header: "Reference", value: (p: InvoicePayment) => p.reference },
                    { header: "Method", value: (p: InvoicePayment) => p.method },
                    { header: "Amount (GHS)", value: (p: InvoicePayment) => p.amount },
                  ],
                  rows: payments,
                },
              ]}
            />
            <Button variant="outline">Record payment</Button>
            <Button>New invoice</Button>
          </>
        }
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="card-surface p-5">
          <h2 className="text-base font-semibold">Contact information</h2>
          <ul className="mt-4 space-y-3 text-sm">
            <li className="flex items-start gap-3">
              <Phone className="mt-0.5 size-4 text-muted-foreground" />
              <span className="tabular-nums">{customer.phone}</span>
            </li>
            <li className="flex items-start gap-3">
              <Mail className="mt-0.5 size-4 text-muted-foreground" />
              <span className="break-all">{customer.email || "—"}</span>
            </li>
            <li className="flex items-start gap-3">
              <MapPin className="mt-0.5 size-4 text-muted-foreground" />
              <span>{customer.address || "—"}</span>
            </li>
          </ul>
        </div>

        <div className="card-surface p-5">
          <p className="text-sm text-muted-foreground">Outstanding balance</p>
          <p
            className={cn(
              "mt-2 text-3xl font-semibold tracking-tight",
              customer.balance > 0 ? "text-destructive" : "text-foreground",
            )}
          >
            {currency(customer.balance)}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            {customer.balance > 0 ? "Owed on part-paid or unpaid invoices" : "All invoices settled"}
          </p>
        </div>

        <div className="card-surface p-5">
          <p className="text-sm text-muted-foreground">Lifetime purchases</p>
          <p className="mt-2 text-3xl font-semibold tracking-tight">
            {currency(customer.lifetime)}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            {orders.length} order{orders.length === 1 ? "" : "s"} on file
          </p>
        </div>
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="border-b px-5 py-4">
          <h2 className="text-base font-semibold">Recent orders</h2>
          <p className="text-sm text-muted-foreground">Latest invoices raised for this customer</p>
        </div>
        {orders.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-muted-foreground">No orders yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Invoice</th>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 font-medium">Items</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 text-right font-medium">Total</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {orders.map((invoice) => {
                  const totals = invoiceTotals(invoice);
                  return (
                    <tr key={invoice.id} className="hover:bg-muted/40">
                      <td className="px-5 py-3 font-medium">
                        <Link
                          to="/sales/$invoiceId"
                          params={{ invoiceId: invoice.id }}
                          className="hover:text-primary"
                        >
                          {invoice.id}
                        </Link>
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">
                        {formatDate(invoice.date)}
                      </td>
                      <td className="max-w-xs truncate px-5 py-3 text-muted-foreground">
                        {itemsSummary(invoice)}
                      </td>
                      <td className="px-5 py-3">
                        <span
                          className={cn(
                            "inline-flex rounded-lg px-2 py-0.5 text-xs font-medium",
                            totals.status === "Paid"
                              ? "bg-accent text-accent-foreground"
                              : totals.status === "Partly paid"
                                ? "bg-[color:var(--warning)]/15 text-[color:var(--warning-foreground)] dark:text-[color:var(--warning)]"
                                : "bg-destructive/10 text-destructive",
                          )}
                        >
                          {totals.status}
                        </span>
                      </td>
                      <td className="px-5 py-3 text-right font-medium tabular-nums">
                        {currency(totals.total)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="card-surface mt-6 overflow-hidden">
        <div className="border-b px-5 py-4">
          <h2 className="text-base font-semibold">Payment history</h2>
          <p className="text-sm text-muted-foreground">
            Includes partial payments against invoices
          </p>
        </div>
        {payments.length === 0 ? (
          <p className="px-5 py-10 text-center text-sm text-muted-foreground">
            No payments recorded yet.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-5 py-3 font-medium">Date</th>
                  <th className="px-5 py-3 font-medium">Reference</th>
                  <th className="px-5 py-3 font-medium">Method</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {payments.map((p) => (
                  <tr key={p.id} className="hover:bg-muted/40">
                    <td className="px-5 py-3">{formatDate(p.date)}</td>
                    <td className="px-5 py-3 text-muted-foreground">{p.reference}</td>
                    <td className="px-5 py-3">{p.method}</td>
                    <td className="px-5 py-3 text-right font-medium tabular-nums">
                      {currencyPrecise(p.amount)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function formatDate(value: string) {
  return new Date(value).toLocaleDateString("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}
