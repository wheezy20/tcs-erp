import { currency } from "@/data/dashboard";
import {
  discountAmount,
  lineGross,
  lineNet,
  lineTaxable,
  posTotals,
  type PosLine,
  type PosPayment,
  type VatMode,
  type Discount,
} from "@/data/pos";
import { useDocumentSettings } from "@/data/settings-store";

export type ReceiptSale = {
  id: string;
  date: string;
  time: string;
  customerName: string;
  cashier: string;
  branch: string;
  lines: PosLine[];
  saleDiscount: Discount;
  vatMode: VatMode;
  vatRate: number;
  payments: PosPayment[];
  /** Optional checkout note — rendered only when non-empty. */
  notes?: string;
};

export function ReceiptPreview({ sale }: { sale: ReceiptSale }) {
  const totals = posTotals(sale);
  const { company, showVatNumber } = useDocumentSettings();

  return (
    <div className="rounded-2xl border border-dashed border-border bg-card px-5 py-6 font-mono text-xs">
      <div className="text-center">
        <p className="text-sm font-semibold uppercase tracking-wide">{company.name}</p>
        <p className="mt-0.5 text-muted-foreground">{sale.branch}</p>
        <p className="text-muted-foreground">{company.address}</p>
        {showVatNumber && company.vatNumber && (
          <p className="text-muted-foreground">VAT No. {company.vatNumber}</p>
        )}
      </div>

      <div className="mt-4 space-y-0.5 border-y border-dashed border-border py-3 text-muted-foreground">
        <div className="flex justify-between">
          <span>Receipt</span>
          <span className="text-foreground">{sale.id}</span>
        </div>
        <div className="flex justify-between">
          <span>Date</span>
          <span className="text-foreground">
            {sale.date} {sale.time}
          </span>
        </div>
        <div className="flex justify-between">
          <span>Customer</span>
          <span className="text-foreground">{sale.customerName}</span>
        </div>
        <div className="flex justify-between">
          <span>Served by</span>
          <span className="text-foreground">{sale.cashier}</span>
        </div>
      </div>

      <ul className="space-y-2 py-3">
        {sale.lines.map((line) => {
          const gross = lineGross(line);
          const disc = discountAmount(line.discount, gross, line.quantity);
          return (
            <li key={line.id}>
              <div className="flex justify-between gap-3">
                <span className="min-w-0 flex-1 truncate">{line.name}</span>
                <span>{currency(lineNet(line))}</span>
              </div>
              <div className="flex justify-between text-muted-foreground">
                <span>
                  {line.quantity} {String(line.unit).toLowerCase()} × {currency(line.unitPrice)}
                  {lineTaxable(line, sale.vatMode) ? " · VAT" : ""}
                </span>
                {disc > 0 && <span>-{currency(disc)}</span>}
              </div>
            </li>
          );
        })}
        {sale.lines.length === 0 && <li className="text-muted-foreground">No items yet</li>}
      </ul>

      <div className="space-y-1 border-t border-dashed border-border pt-3">
        <Row label="Subtotal" value={currency(totals.subtotal)} />
        {totals.saleDiscount > 0 && (
          <Row label="Sale discount" value={`-${currency(totals.saleDiscount)}`} />
        )}
        <Row label={`VAT (${sale.vatRate}%)`} value={currency(totals.vat)} />
        <div className="flex justify-between border-t border-dashed border-border pt-2 text-sm font-semibold">
          <span>TOTAL</span>
          <span>{currency(totals.total)}</span>
        </div>
        {sale.payments.map((p) => (
          <Row key={p.id} label={p.method} value={currency(p.amount)} />
        ))}
        {totals.balance > 0 && <Row label="Balance due" value={currency(totals.balance)} />}
        {totals.change > 0 && <Row label="Change" value={currency(totals.change)} />}
      </div>

      {sale.notes?.trim() && (
        <div className="mt-3 border-t border-dashed border-border pt-3">
          <p className="text-muted-foreground">Note</p>
          <p className="whitespace-pre-wrap text-foreground">{sale.notes.trim()}</p>
        </div>
      )}

      <p className="mt-4 text-center text-muted-foreground">
        Thank you for shopping with {company.name}. Goods returnable within 7 days with this
        receipt.
      </p>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between text-muted-foreground">
      <span>{label}</span>
      <span className="text-foreground">{value}</span>
    </div>
  );
}
