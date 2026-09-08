import { currency } from "@/data/dashboard";
import { invoiceTotals, lineGross, type Invoice } from "@/data/invoices";
import type { Customer } from "@/data/customers";
import {
  PAPER_WIDTH_MM,
  type CompanyDetails,
  type DocumentSettings,
  type InvoicePaper,
} from "@/data/settings-store";

export type PrintableInvoiceProps = {
  invoice: Invoice;
  customer?: Customer | null;
  settings: DocumentSettings;
  /** override the paper size, used by the Settings preview */
  paper?: InvoicePaper;
};

export function PrintableInvoice({ invoice, customer, settings, paper }: PrintableInvoiceProps) {
  const size = paper ?? settings.invoicePaper;
  const totals = invoiceTotals(invoice);
  const company: CompanyDetails = settings.company;
  const compact = size === "A5";

  return (
    <div
      className="printable-invoice"
      style={{
        width: `${PAPER_WIDTH_MM[size] - 24}mm`,
        margin: "0 auto",
        color: "#111",
        background: "#fff",
        fontFamily: "Inter, system-ui, sans-serif",
        fontSize: compact ? "9px" : "11px",
        lineHeight: 1.45,
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          gap: "16px",
          borderBottom: "1px solid #ddd",
          paddingBottom: compact ? "10px" : "14px",
        }}
      >
        <div style={{ display: "flex", gap: "10px", alignItems: "flex-start" }}>
          {settings.logoDataUrl && (
            <img
              src={settings.logoDataUrl}
              alt=""
              style={{ height: compact ? "28px" : "38px", objectFit: "contain" }}
            />
          )}
          <div>
            <p style={{ fontSize: compact ? "13px" : "16px", fontWeight: 600, margin: 0 }}>
              {company.name}
            </p>
            <p style={{ margin: "2px 0 0", color: "#555" }}>{company.address}</p>
            <p style={{ margin: 0, color: "#555" }}>
              {company.phone}
              {company.email ? ` · ${company.email}` : ""}
            </p>
            {settings.showVatNumber && company.vatNumber && (
              <p style={{ margin: 0, color: "#555" }}>VAT No. {company.vatNumber}</p>
            )}
          </div>
        </div>
        <div style={{ textAlign: "right" }}>
          <p
            style={{
              margin: 0,
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              color: "#777",
            }}
          >
            Invoice
          </p>
          <p style={{ margin: "2px 0 0", fontSize: compact ? "13px" : "15px", fontWeight: 600 }}>
            {invoice.id}
          </p>
          <p style={{ margin: 0, color: "#555" }}>Date {invoice.date}</p>
          <p style={{ margin: 0, color: "#555" }}>Due {invoice.dueDate}</p>
          <p style={{ margin: 0, color: "#555" }}>{invoice.branch}</p>
        </div>
      </div>

      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          gap: "16px",
          borderBottom: "1px solid #ddd",
          padding: compact ? "10px 0" : "14px 0",
        }}
      >
        <div>
          <p
            style={{
              margin: 0,
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              color: "#777",
            }}
          >
            Billed to
          </p>
          <p style={{ margin: "2px 0 0", fontWeight: 600 }}>{invoice.customerName}</p>
          {customer && (
            <>
              <p style={{ margin: 0, color: "#555" }}>{customer.phone}</p>
              {customer.email && <p style={{ margin: 0, color: "#555" }}>{customer.email}</p>}
              {customer.address && <p style={{ margin: 0, color: "#555" }}>{customer.address}</p>}
            </>
          )}
        </div>
        <div style={{ textAlign: "right" }}>
          <p
            style={{
              margin: 0,
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              color: "#777",
            }}
          >
            Amount due
          </p>
          <p style={{ margin: "2px 0 0", fontSize: compact ? "14px" : "18px", fontWeight: 600 }}>
            {currency(totals.balance)}
          </p>
          <p style={{ margin: 0, color: "#555" }}>
            {currency(totals.paid)} paid of {currency(totals.total)}
          </p>
          <p style={{ margin: 0, color: "#555" }}>Issued by {invoice.issuedBy}</p>
        </div>
      </div>

      <table style={{ width: "100%", borderCollapse: "collapse", margin: "10px 0" }}>
        <thead>
          <tr style={{ textAlign: "left", color: "#777" }}>
            <th style={th}>Item</th>
            <th style={th}>Unit</th>
            <th style={{ ...th, textAlign: "right" }}>Qty</th>
            <th style={{ ...th, textAlign: "right" }}>Unit price</th>
            <th style={{ ...th, textAlign: "right" }}>Discount</th>
            <th style={{ ...th, textAlign: "center" }}>VAT</th>
            <th style={{ ...th, textAlign: "right" }}>Amount</th>
          </tr>
        </thead>
        <tbody>
          {invoice.lines.map((l) => (
            <tr key={l.id}>
              <td style={{ ...td, fontWeight: 500 }}>{l.name}</td>
              <td style={{ ...td, color: "#555" }}>{l.unit}</td>
              <td style={{ ...td, textAlign: "right" }}>{l.quantity}</td>
              <td style={{ ...td, textAlign: "right" }}>{currency(l.unitPrice)}</td>
              <td style={{ ...td, textAlign: "right", color: "#555" }}>
                {l.discount > 0 ? `− ${currency(l.discount)}` : "—"}
              </td>
              <td style={{ ...td, textAlign: "center", color: "#555" }}>
                {l.vat ? `${invoice.vatRate}%` : "—"}
              </td>
              <td style={{ ...td, textAlign: "right", fontWeight: 500 }}>
                {currency(Math.max(0, lineGross(l) - l.discount))}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <div style={{ width: "62mm" }}>
          <TotalRow label="Subtotal" value={currency(totals.subtotal)} />
          <TotalRow label="Line discounts" value={`− ${currency(totals.lineDiscounts)}`} />
          <TotalRow label="Invoice discount" value={`− ${currency(totals.invoiceDiscount)}`} />
          <TotalRow label={`VAT (${invoice.vatRate}%)`} value={currency(totals.vat)} />
          <TotalRow label="Total" value={currency(totals.total)} strong />
          <TotalRow label="Amount paid" value={`− ${currency(totals.paid)}`} />
          <TotalRow label="Balance due" value={currency(totals.balance)} strong />
        </div>
      </div>

      {invoice.notes && <p style={{ marginTop: "10px", color: "#555" }}>{invoice.notes}</p>}

      {settings.tax.vatNote && (
        <p style={{ marginTop: "8px", color: "#777" }}>{settings.tax.vatNote}</p>
      )}

      <p style={{ marginTop: "12px", textAlign: "center", color: "#777" }}>
        Thank you for your business. Payment is due by {invoice.dueDate}.
      </p>
    </div>
  );
}

const th: React.CSSProperties = {
  padding: "6px 6px 6px 0",
  borderBottom: "1px solid #ddd",
  fontWeight: 500,
  textTransform: "uppercase",
  letterSpacing: "0.06em",
  fontSize: "0.85em",
};

const td: React.CSSProperties = {
  padding: "5px 6px 5px 0",
  borderBottom: "1px solid #eee",
  verticalAlign: "top",
};

function TotalRow({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        padding: "3px 0",
        borderTop: strong ? "1px solid #ddd" : undefined,
        fontWeight: strong ? 600 : 400,
        color: strong ? "#111" : "#555",
      }}
    >
      <span>{label}</span>
      <span>{value}</span>
    </div>
  );
}
