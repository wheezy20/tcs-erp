import { currency } from "@/data/dashboard";
import type { DayClose } from "@/data/end-of-day-store";
import type { DocumentSettings } from "@/data/settings-store";

export function PrintableDayClose({
  row,
  settings,
  branchName,
}: {
  row: DayClose;
  settings: DocumentSettings;
  branchName: string;
}) {
  const company = settings.company;

  return (
    <div
      className="printable-day-close"
      style={{
        width: "182mm",
        margin: "0 auto",
        color: "#111",
        background: "#fff",
        fontFamily: "Inter, system-ui, sans-serif",
        fontSize: "11px",
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
          paddingBottom: "14px",
        }}
      >
        <div style={{ display: "flex", gap: "10px", alignItems: "flex-start" }}>
          {settings.logoDataUrl && (
            <img
              src={settings.logoDataUrl}
              alt=""
              style={{ height: "38px", objectFit: "contain" }}
            />
          )}
          <div>
            <p style={{ fontSize: "16px", fontWeight: 600, margin: 0 }}>{company.name}</p>
            <p style={{ margin: "2px 0 0", color: "#555" }}>{company.address}</p>
            <p style={{ margin: 0, color: "#555" }}>{branchName}</p>
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
            End of Day Reconciliation
          </p>
          <p style={{ margin: "4px 0 0", fontSize: "15px", fontWeight: 600 }}>{row.businessDate}</p>
          <p style={{ margin: 0, color: "#555" }}>
            Closed by {row.closedBy} ·{" "}
            {row.closedAt &&
              new Date(row.closedAt).toLocaleString("en-GB", {
                day: "2-digit",
                month: "short",
                hour: "2-digit",
                minute: "2-digit",
              })}
          </p>
        </div>
      </div>

      <Section title="Sales by payment method">
        <KV label="Cash — POS" value={currency(row.posCashSales ?? 0)} />
        <KV label="Cash — invoices" value={currency(row.invoiceCashSales ?? 0)} />
        <KV label="Cash — total" value={currency(row.cashSales ?? 0)} bold />
        <KV label="Mobile Money (POS + invoices)" value={currency(row.mobileMoneySales ?? 0)} />
        <KV label="Card" value={currency(row.cardSales ?? 0)} />
        <KV label="Bank transfer (POS + invoices)" value={currency(row.bankTransferSales ?? 0)} />
        <KV label="Cheque — invoices" value={currency(row.invoiceChequeSales ?? 0)} />
        <KV label="VAT collected" value={currency(row.vatCollected ?? 0)} />
        <KV label="Discounts given" value={currency(row.discountsGiven ?? 0)} />
      </Section>

      <Section title="Cash reconciliation">
        <KV label="Opening float" value={currency(row.openingFloat)} />
        <KV label="Cash sales" value={currency(row.cashSales ?? 0)} />
        <KV label="Cash refunds" value={`-${currency(row.cashRefunds ?? 0)}`} />
        <KV label="Cash expenses" value={`-${currency(row.cashExpenses ?? 0)}`} />
        <KV label="Cash deposits (banked)" value={`-${currency(row.cashDeposits ?? 0)}`} />
        <KV label="Expected cash" value={currency(row.expectedCash ?? 0)} bold />
        <KV label="Counted cash" value={currency(row.countedCash ?? 0)} bold />
        <KV
          label="Cash variance"
          value={`${(row.cashVariance ?? 0) > 0 ? "+" : ""}${currency(row.cashVariance ?? 0)}`}
          bold
        />
      </Section>

      <Section title="Manual tally cross-check">
        <KV label="System sales total" value={currency(row.systemSalesTotal ?? 0)} />
        <KV label="Manual sales total" value={currency(row.manualSalesTotal ?? 0)} />
        <KV
          label="Tally sales variance"
          value={`${(row.tallySalesVariance ?? 0) > 0 ? "+" : ""}${currency(row.tallySalesVariance ?? 0)}`}
        />
        <KV label="System transactions" value={String(row.systemTransactionCount ?? 0)} />
        <KV label="Manual transactions" value={String(row.manualTransactionCount ?? 0)} />
        <KV
          label="Tally count variance"
          value={`${(row.tallyCountVariance ?? 0) > 0 ? "+" : ""}${row.tallyCountVariance ?? 0}`}
        />
      </Section>

      {row.notes && (
        <div style={{ marginTop: "14px", paddingTop: "10px", borderTop: "1px solid #ddd" }}>
          <p
            style={{
              margin: 0,
              color: "#777",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
              fontSize: "9px",
            }}
          >
            Note
          </p>
          <p style={{ margin: "4px 0 0" }}>{row.notes}</p>
        </div>
      )}

      <p style={{ marginTop: "18px", color: "#999", fontSize: "9px" }}>
        Opening float confirmed by {row.openingConfirmedBy} at{" "}
        {new Date(row.openingConfirmedAt).toLocaleTimeString("en-GB", {
          hour: "2-digit",
          minute: "2-digit",
        })}
        . This figure is locked and cannot be edited once closed.
      </p>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ marginTop: "16px" }}>
      <p style={{ margin: "0 0 6px", fontWeight: 600, fontSize: "11.5px" }}>{title}</p>
      <div style={{ display: "flex", flexDirection: "column", gap: "3px" }}>{children}</div>
    </div>
  );
}

function KV({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between" }}>
      <span style={{ color: "#555" }}>{label}</span>
      <span style={{ fontWeight: bold ? 700 : 400 }}>{value}</span>
    </div>
  );
}
