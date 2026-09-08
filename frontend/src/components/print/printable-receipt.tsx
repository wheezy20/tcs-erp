import { currency } from "@/data/dashboard";
import { discountAmount, lineGross, lineNet, lineTaxable, posTotals } from "@/data/pos";
import type { ReceiptSale } from "@/components/pos/receipt-preview";
import { PAPER_WIDTH_MM, type DocumentSettings, type ReceiptPaper } from "@/data/settings-store";

export function PrintableReceipt({
  sale,
  settings,
  paper,
}: {
  sale: ReceiptSale;
  settings: DocumentSettings;
  paper?: ReceiptPaper;
}) {
  const size = paper ?? settings.receiptPaper;
  const totals = posTotals(sale);
  const company = settings.company;
  const isThermal = size !== "A4";
  const width = isThermal ? PAPER_WIDTH_MM[size] - 8 : 100;
  const fontSize = size === "58mm" ? "8.5px" : "10px";

  return (
    <div
      className="printable-receipt"
      style={{
        width: `${width}mm`,
        margin: isThermal ? "0" : "0 auto",
        color: "#111",
        background: "#fff",
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        fontSize,
        lineHeight: 1.4,
      }}
    >
      <div style={{ textAlign: "center" }}>
        {settings.logoDataUrl && (
          <img
            src={settings.logoDataUrl}
            alt=""
            style={{ height: "28px", objectFit: "contain", marginBottom: "4px" }}
          />
        )}
        <p style={{ margin: 0, fontWeight: 700, letterSpacing: "0.08em" }}>
          {company.name.toUpperCase()}
        </p>
        <p style={{ margin: 0 }}>{company.address}</p>
        <p style={{ margin: 0 }}>{company.phone}</p>
        {settings.showVatNumber && company.vatNumber && (
          <p style={{ margin: 0 }}>VAT No. {company.vatNumber}</p>
        )}
        <p style={{ margin: 0 }}>{sale.branch}</p>
      </div>

      <Divider />
      <Line label="Receipt" value={sale.id} />
      <Line label="Date" value={`${sale.date} ${sale.time}`} />
      <Line label="Customer" value={sale.customerName} />
      <Line label="Served by" value={sale.cashier} />
      <Divider />

      {sale.lines.map((line) => {
        const disc = discountAmount(line.discount, lineGross(line), line.quantity);
        return (
          <div key={line.id} style={{ marginBottom: "3px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", gap: "6px" }}>
              <span>{line.name}</span>
              <span>{currency(lineNet(line))}</span>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", color: "#555" }}>
              <span>
                {line.quantity} {String(line.unit).toLowerCase()} × {currency(line.unitPrice)}
                {lineTaxable(line, sale.vatMode) ? " · VAT" : ""}
              </span>
              {disc > 0 && <span>-{currency(disc)}</span>}
            </div>
          </div>
        );
      })}
      {sale.lines.length === 0 && <p style={{ margin: 0, color: "#555" }}>No items</p>}

      <Divider />
      <Line label="Subtotal" value={currency(totals.subtotal)} />
      {totals.lineDiscounts > 0 && (
        <Line label="Item discounts" value={`-${currency(totals.lineDiscounts)}`} />
      )}
      {totals.saleDiscount > 0 && (
        <Line label="Sale discount" value={`-${currency(totals.saleDiscount)}`} />
      )}
      <Line label={`VAT (${sale.vatRate}%)`} value={currency(totals.vat)} />
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          borderTop: "1px dashed #999",
          marginTop: "3px",
          paddingTop: "3px",
          fontWeight: 700,
        }}
      >
        <span>TOTAL</span>
        <span>{currency(totals.total)}</span>
      </div>

      <Divider />
      <p style={{ margin: "0 0 2px", color: "#555" }}>
        {sale.payments.length > 1 ? "Split payment" : "Payment"}
      </p>
      {sale.payments.map((p) => (
        <Line key={p.id} label={p.method} value={currency(p.amount)} />
      ))}
      <Line label="Paid" value={currency(totals.paid)} />
      {totals.balance > 0 && <Line label="Balance due" value={currency(totals.balance)} />}
      {totals.change > 0 && <Line label="Change" value={currency(totals.change)} />}

      {sale.notes?.trim() && (
        <>
          <Divider />
          <p style={{ margin: "0 0 2px", color: "#555" }}>Note</p>
          <p style={{ margin: 0, whiteSpace: "pre-wrap" }}>{sale.notes.trim()}</p>
        </>
      )}

      {settings.tax.vatNote && (
        <p style={{ marginTop: "8px", textAlign: "center", color: "#777" }}>
          {settings.tax.vatNote}
        </p>
      )}
      <p style={{ marginTop: "8px", textAlign: "center", color: "#555" }}>
        Thank you for shopping with {company.name}.
      </p>
      <p style={{ margin: 0, textAlign: "center", color: "#555" }}>
        Goods returnable within 7 days with this receipt.
      </p>
    </div>
  );
}

function Divider() {
  return <div style={{ borderTop: "1px dashed #999", margin: "5px 0" }} />;
}

function Line({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", gap: "6px" }}>
      <span style={{ color: "#555" }}>{label}</span>
      <span>{value}</span>
    </div>
  );
}
