import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Download, Mail, MapPin, Pencil, Phone, Printer } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { PrintDocument } from "@/components/print/print-document";
import { PrintableInvoice } from "@/components/print/printable-invoice";
import { useDocumentSettings } from "@/data/settings-store";

import { InvoiceStatusBadge } from "@/components/sales/invoice-status-badge";
import { RecordPaymentDialog } from "@/components/sales/record-payment-dialog";
import { VoidTransactionDialog } from "@/components/void-transaction-dialog";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/data/auth-store";
import { currency } from "@/data/dashboard";
import { invoiceTotals, lineGross } from "@/data/invoices";
import { useSales, voidInvoice } from "@/data/sales-store";

export const Route = createFileRoute("/sales/$invoiceId/")({
  head: ({ params }) => ({
    meta: [
      { title: `Invoice ${params.invoiceId} — TCS` },
      {
        name: "description",
        content: `Line items, VAT, discounts, payments log and remaining balance for invoice ${params.invoiceId}.`,
      },
      { property: "og:title", content: `Invoice ${params.invoiceId} — TCS` },
      {
        property: "og:description",
        content: "Printable invoice with payment history and outstanding balance.",
      },
    ],
  }),
  component: InvoiceDetailPage,
});

function InvoiceDetailPage() {
  const { invoiceId } = Route.useParams();
  const { invoices, customers } = useSales();
  const { staff } = useAuth();
  const isManager = staff?.role === "Manager";
  const settings = useDocumentSettings();
  const [downloading, setDownloading] = useState(false);
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

  const customer = customers.find((c) => c.id === invoice.customerId);
  const totals = invoiceTotals(invoice);

  return (
    <>
      <div className="print-hide mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <Link
            to="/sales"
            className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
          >
            <ArrowLeft className="size-4" /> All invoices
          </Link>
          <div className="mt-2 flex flex-wrap items-center gap-3">
            <h1 className="text-2xl font-semibold tracking-tight md:text-3xl">{invoice.id}</h1>
            {invoice.voidedAt ? (
              <span className="inline-flex items-center rounded-full bg-destructive/10 px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wide text-destructive">
                Voided
              </span>
            ) : (
              <InvoiceStatusBadge status={totals.status} />
            )}
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            Issued {invoice.date} · Due {invoice.dueDate} · {invoice.branch}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" className="gap-2" onClick={() => window.print()}>
            <Printer className="size-4" /> Print invoice
          </Button>
          <Button
            variant="outline"
            className="gap-2"
            disabled={downloading}
            onClick={async () => {
              setDownloading(true);
              try {
                // Lazy — the embedded PDF fonts add ~400KB, only worth
                // loading when someone actually clicks this (same pattern
                // as export-data.ts's `await import("xlsx")`).
                const { downloadInvoicePdf } = await import("@/lib/pdf/invoice-pdf");
                await downloadInvoicePdf(invoice, customer, settings);
                toast.success(`Invoice ${invoice.id} downloaded as PDF`);
              } catch {
                toast.error("Could not generate the PDF");
              } finally {
                setDownloading(false);
              }
            }}
          >
            <Download className="size-4" /> {downloading ? "Preparing…" : "Download PDF"}
          </Button>
          {!invoice.voidedAt && (
            <>
              <Button asChild variant="outline" className="gap-2">
                <Link to="/sales/$invoiceId/edit" params={{ invoiceId: invoice.id }}>
                  <Pencil className="size-4" /> Edit
                </Link>
              </Button>
              <RecordPaymentDialog
                invoiceId={invoice.id}
                balance={totals.balance}
                storeCreditBalance={customer?.storeCreditBalance ?? 0}
              />
              {isManager && (
                <VoidTransactionDialog
                  kind="invoice"
                  id={invoice.id}
                  onVoid={(reason) => voidInvoice(invoice.id, reason)}
                />
              )}
            </>
          )}
        </div>
      </div>

      {invoice.voidedAt && (
        <div className="print-hide mb-6 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm">
          <span className="font-semibold text-destructive">This invoice was voided</span>
          {invoice.voidedBy ? ` by ${invoice.voidedBy}` : ""} on{" "}
          {new Date(invoice.voidedAt).toLocaleDateString()}. Its ledger entries were reversed and
          nothing is owed.
          {invoice.voidReason ? (
            <span className="mt-1 block text-muted-foreground">Reason: {invoice.voidReason}</span>
          ) : null}
        </div>
      )}

      <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
        <div className="space-y-6">
          <section className="card-surface print-sheet p-6">
            <div className="flex flex-wrap items-start justify-between gap-6 border-b pb-6">
              <div>
                <p className="text-lg font-semibold">Treasures Christian School</p>
                <p className="mt-1 text-sm text-muted-foreground">{invoice.branch}</p>
                <p className="text-sm text-muted-foreground">
                  Spintex Road, Accra · +233 30 279 1100
                </p>
              </div>
              <div className="text-right">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">Invoice</p>
                <p className="text-lg font-semibold">{invoice.id}</p>
                <p className="text-sm text-muted-foreground">Date {invoice.date}</p>
                <p className="text-sm text-muted-foreground">Due {invoice.dueDate}</p>
              </div>
            </div>

            <div className="grid gap-6 border-b py-6 sm:grid-cols-2">
              <div>
                <p className="text-xs uppercase tracking-wide text-muted-foreground">Billed to</p>
                <Link
                  to="/customers/$customerId"
                  params={{ customerId: invoice.customerId }}
                  className="mt-1 inline-block text-base font-medium hover:text-primary"
                >
                  {invoice.customerName}
                </Link>
                {customer && (
                  <div className="mt-2 space-y-1 text-sm text-muted-foreground">
                    <p className="flex items-center gap-2">
                      <Phone className="size-3.5" /> {customer.phone}
                    </p>
                    {customer.email && (
                      <p className="flex items-center gap-2">
                        <Mail className="size-3.5" /> {customer.email}
                      </p>
                    )}
                    {customer.address && (
                      <p className="flex items-center gap-2">
                        <MapPin className="size-3.5" /> {customer.address}
                      </p>
                    )}
                  </div>
                )}
              </div>
              <div className="sm:text-right">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">Amount due</p>
                <p className="mt-1 text-2xl font-semibold tabular-nums">
                  {currency(totals.balance)}
                </p>
                <p className="text-sm text-muted-foreground">
                  {currency(totals.paid)} paid of {currency(totals.total)}
                </p>
                <p className="mt-2 text-sm text-muted-foreground">Issued by {invoice.issuedBy}</p>
              </div>
            </div>

            <div className="overflow-x-auto py-2">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="py-3 pr-4 font-medium">Item</th>
                    <th className="py-3 pr-4 font-medium">Unit</th>
                    <th className="py-3 pr-4 text-right font-medium">Qty</th>
                    <th className="py-3 pr-4 text-right font-medium">Unit price</th>
                    <th className="py-3 pr-4 text-right font-medium">Discount</th>
                    <th className="py-3 pr-4 text-center font-medium">VAT</th>
                    <th className="py-3 text-right font-medium">Amount</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {invoice.lines.map((l) => (
                    <tr key={l.id}>
                      <td className="py-3 pr-4">
                        {l.productId ? (
                          <Link
                            to="/inventory/$productId"
                            params={{ productId: l.productId }}
                            className="font-medium hover:text-primary print-plain"
                          >
                            {l.name}
                          </Link>
                        ) : (
                          <span className="font-medium">{l.name}</span>
                        )}
                      </td>
                      <td className="py-3 pr-4 text-muted-foreground">{l.unit}</td>
                      <td className="py-3 pr-4 text-right tabular-nums">{l.quantity}</td>
                      <td className="py-3 pr-4 text-right tabular-nums">{currency(l.unitPrice)}</td>
                      <td className="py-3 pr-4 text-right tabular-nums text-muted-foreground">
                        {l.discount > 0 ? `− ${currency(l.discount)}` : "—"}
                      </td>
                      <td className="py-3 pr-4 text-center text-muted-foreground">
                        {l.vat ? `${invoice.vatRate}%` : "—"}
                      </td>
                      <td className="py-3 text-right font-medium tabular-nums">
                        {currency(Math.max(0, lineGross(l) - l.discount))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="mt-6 flex justify-end border-t pt-6">
              <dl className="w-full max-w-xs space-y-2 text-sm">
                <Row label="Subtotal" value={currency(totals.subtotal)} />
                <Row label="Line discounts" value={`− ${currency(totals.lineDiscounts)}`} muted />
                <Row
                  label="Invoice discount"
                  value={`− ${currency(totals.invoiceDiscount)}`}
                  muted
                />
                <Row label={`VAT (${invoice.vatRate}%)`} value={currency(totals.vat)} muted />
                <div className="flex items-center justify-between border-t pt-3 text-base font-semibold">
                  <span>Total</span>
                  <span className="tabular-nums">{currency(totals.total)}</span>
                </div>
                {invoice.whtApplied && (
                  <Row
                    label={`Withholding tax (${invoice.whtRate}%) — receivable, not revenue lost`}
                    value={currency(invoice.whtAmount)}
                    muted
                  />
                )}
                <Row label="Amount paid" value={`− ${currency(totals.paid)}`} muted />
                <div className="flex items-center justify-between border-t pt-3 text-base font-semibold">
                  <span>Balance due</span>
                  <span className="tabular-nums">{currency(totals.balance)}</span>
                </div>
              </dl>
            </div>

            {invoice.notes && (
              <p className="mt-6 rounded-2xl bg-muted/50 px-4 py-3 text-sm text-muted-foreground">
                {invoice.notes}
              </p>
            )}
          </section>

          <section className="card-surface print-hide overflow-hidden">
            <div className="border-b p-5">
              <h2 className="text-sm font-semibold">Payments log</h2>
              <p className="text-sm text-muted-foreground">
                Every payment recorded against this invoice.
              </p>
            </div>
            {invoice.payments.length === 0 ? (
              <p className="px-5 py-10 text-center text-sm text-muted-foreground">
                No payments recorded yet.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                    <tr>
                      <th className="px-5 py-3 font-medium">Date</th>
                      <th className="px-5 py-3 font-medium">Method</th>
                      <th className="px-5 py-3 font-medium">Reference</th>
                      <th className="px-5 py-3 text-right font-medium">Amount</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {invoice.payments.map((p) => (
                      <tr key={p.id}>
                        <td className="px-5 py-3 text-muted-foreground">{p.date}</td>
                        <td className="px-5 py-3 text-muted-foreground">{p.method}</td>
                        <td className="px-5 py-3 text-muted-foreground">{p.reference}</td>
                        <td className="px-5 py-3 text-right font-medium tabular-nums">
                          {currency(p.amount)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </div>

        <aside className="print-hide space-y-6">
          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">Payment summary</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <Row label="Invoice total" value={currency(totals.total)} />
              <Row label="Amount paid" value={currency(totals.paid)} muted />
              <div className="flex items-center justify-between border-t pt-3 font-semibold">
                <span>Remaining</span>
                <span className="tabular-nums">{currency(totals.balance)}</span>
              </div>
            </dl>
            <div className="mt-4 h-2 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-primary"
                style={{
                  width: `${totals.total > 0 ? Math.min(100, (totals.paid / totals.total) * 100) : 0}%`,
                }}
              />
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              {totals.total > 0 ? Math.round((totals.paid / totals.total) * 100) : 0}% settled
            </p>
          </section>

          {customer && (
            <section className="card-surface p-5">
              <h2 className="text-sm font-semibold">Customer</h2>
              <p className="mt-3 text-base font-medium">{customer.name}</p>
              <p className="text-sm text-muted-foreground">
                {customer.type} · since {customer.since}
              </p>
              <dl className="mt-4 space-y-2 text-sm">
                <Row label="Account balance" value={currency(customer.balance)} muted />
                <Row label="Lifetime purchases" value={currency(customer.lifetime)} muted />
              </dl>
              <Button asChild variant="outline" className="mt-4 w-full">
                <Link to="/customers/$customerId" params={{ customerId: customer.id }}>
                  View customer profile
                </Link>
              </Button>
            </section>
          )}
        </aside>
      </div>

      <PrintDocument
        pageSize={settings.invoicePaper === "Letter" ? "letter" : settings.invoicePaper}
        margin={settings.invoicePaper === "A5" ? "10mm" : "12mm"}
      >
        <PrintableInvoice invoice={invoice} customer={customer} settings={settings} />
      </PrintDocument>
    </>
  );
}

function Row({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <dt className={muted ? "text-muted-foreground" : ""}>{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}
