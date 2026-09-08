import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";

import { currency } from "@/data/dashboard";
import { invoiceTotals, lineGross, type Invoice } from "@/data/invoices";
import type { Customer } from "@/data/customers";
import type { DocumentSettings } from "@/data/settings-store";
import { INTER_BOLD_TTF_BASE64 } from "@/lib/pdf/fonts/inter-bold";
import { INTER_REGULAR_TTF_BASE64 } from "@/lib/pdf/fonts/inter-regular";

const FORMAT: Record<string, string> = { A4: "a4", A5: "a5", Letter: "letter" };

// jsPDF's built-in "helvetica"/"times"/"courier" fonts only support
// WinAnsiEncoding, a single-byte charset with no Ghana Cedi Sign (₵,
// U+20B5) — that codepoint silently truncates to its low byte (0xB5),
// which WinAnsi/Latin-1 decodes as µ (MICRO SIGN) instead of erroring.
// Confirmed live on a real invoice (INV-26090003): every "GH₵" printed as
// "GH µ". Embedding a real Unicode font sidesteps the single-byte
// encoding entirely (jsPDF embeds a custom TTF as a proper CID-keyed
// font), so this is "Inter" — the same typeface the web app already
// uses — rather than a symbol-specific workaround.
function registerPdfFonts(doc: jsPDF) {
  doc.addFileToVFS("Inter-Regular.ttf", INTER_REGULAR_TTF_BASE64);
  doc.addFont("Inter-Regular.ttf", "Inter", "normal");
  doc.addFileToVFS("Inter-Bold.ttf", INTER_BOLD_TTF_BASE64);
  doc.addFont("Inter-Bold.ttf", "Inter", "bold");
}

export async function downloadInvoicePdf(
  invoice: Invoice,
  customer: Customer | null | undefined,
  settings: DocumentSettings,
) {
  const totals = invoiceTotals(invoice);
  const doc = new jsPDF({
    unit: "mm",
    format: FORMAT[settings.invoicePaper] ?? "a4",
    orientation: "portrait",
  });
  registerPdfFonts(doc);

  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = settings.invoicePaper === "A5" ? 10 : 14;
  const right = pageWidth - margin;
  const company = settings.company;

  let y = margin;

  if (settings.logoDataUrl) {
    try {
      doc.addImage(settings.logoDataUrl, "PNG", margin, y, 18, 18);
    } catch {
      /* unsupported image, skip */
    }
  }
  const textX = settings.logoDataUrl ? margin + 22 : margin;

  doc.setFont("Inter", "bold");
  doc.setFontSize(13);
  doc.text(company.name, textX, y + 5);
  doc.setFont("Inter", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  const companyLines = [
    company.address,
    [company.phone, company.email].filter(Boolean).join(" · "),
    settings.showVatNumber && company.vatNumber ? `VAT No. ${company.vatNumber}` : "",
  ].filter(Boolean);
  companyLines.forEach((line, i) => doc.text(line, textX, y + 10 + i * 4));

  doc.setTextColor(120);
  doc.setFontSize(8);
  doc.text("INVOICE", right, y + 4, { align: "right" });
  doc.setTextColor(20);
  doc.setFont("Inter", "bold");
  doc.setFontSize(12);
  doc.text(invoice.id, right, y + 10, { align: "right" });
  doc.setFont("Inter", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  doc.text(`Date ${invoice.date}`, right, y + 15, { align: "right" });
  doc.text(`Due ${invoice.dueDate}`, right, y + 19, { align: "right" });
  doc.text(invoice.branch, right, y + 23, { align: "right" });

  y += 30;
  doc.setDrawColor(220);
  doc.line(margin, y, right, y);
  y += 6;

  doc.setTextColor(120);
  doc.setFontSize(7.5);
  doc.text("BILLED TO", margin, y);
  doc.text("AMOUNT DUE", right, y, { align: "right" });
  doc.setTextColor(20);
  doc.setFont("Inter", "bold");
  doc.setFontSize(10);
  doc.text(invoice.customerName, margin, y + 5);
  doc.setFontSize(13);
  doc.text(currency(totals.balance), right, y + 5, { align: "right" });
  doc.setFont("Inter", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  const custLines = [customer?.phone, customer?.email, customer?.address].filter(
    Boolean,
  ) as string[];
  custLines.forEach((line, i) => doc.text(line, margin, y + 10 + i * 4));
  doc.text(`${currency(totals.paid)} paid of ${currency(totals.total)}`, right, y + 10, {
    align: "right",
  });
  doc.text(`Issued by ${invoice.issuedBy}`, right, y + 14, { align: "right" });

  y += Math.max(custLines.length * 4 + 12, 20);

  autoTable(doc, {
    startY: y,
    margin: { left: margin, right: margin },
    head: [["Item", "Unit", "Qty", "Unit price", "Discount", "VAT", "Amount"]],
    body: invoice.lines.map((l) => [
      l.name,
      String(l.unit),
      String(l.quantity),
      currency(l.unitPrice),
      l.discount > 0 ? `- ${currency(l.discount)}` : "-",
      l.vat ? `${invoice.vatRate}%` : "-",
      currency(Math.max(0, lineGross(l) - l.discount)),
    ]),
    // autoTable's own theme defaults hardcode font: "helvetica" regardless
    // of the document's currently-set font (it only reads doc.setFont() to
    // restore state afterward, not to seed the table's default style) — so
    // this has to be set explicitly here too, not just via doc.setFont()
    // above, or every currency figure in the line-item table would still
    // render through the broken WinAnsi path.
    styles: {
      font: "Inter",
      fontSize: settings.invoicePaper === "A5" ? 7 : 8.5,
      cellPadding: 1.8,
    },
    headStyles: { fillColor: [27, 27, 27], textColor: 255, fontSize: 7.5 },
    columnStyles: {
      2: { halign: "right" },
      3: { halign: "right" },
      4: { halign: "right" },
      5: { halign: "center" },
      6: { halign: "right" },
    },
  });

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let ty = ((doc as any).lastAutoTable?.finalY ?? y) + 8;
  const labelX = right - 55;

  const rows: [string, string, boolean][] = [
    ["Subtotal", currency(totals.subtotal), false],
    ["Line discounts", `- ${currency(totals.lineDiscounts)}`, false],
    ["Invoice discount", `- ${currency(totals.invoiceDiscount)}`, false],
    [`VAT (${invoice.vatRate}%)`, currency(totals.vat), false],
    ["Total", currency(totals.total), true],
    ["Amount paid", `- ${currency(totals.paid)}`, false],
    ["Balance due", currency(totals.balance), true],
  ];

  rows.forEach(([label, value, strong]) => {
    if (strong) {
      doc.setDrawColor(220);
      doc.line(labelX, ty - 3.5, right, ty - 3.5);
      doc.setFont("Inter", "bold");
      doc.setTextColor(20);
    } else {
      doc.setFont("Inter", "normal");
      doc.setTextColor(90);
    }
    doc.setFontSize(9);
    doc.text(label, labelX, ty);
    doc.text(value, right, ty, { align: "right" });
    ty += 5.5;
  });

  if (invoice.notes) {
    doc.setFont("Inter", "normal");
    doc.setFontSize(8.5);
    doc.setTextColor(90);
    doc.text(doc.splitTextToSize(invoice.notes, right - margin), margin, ty + 4);
  }

  doc.save(`tcs-invoice-${invoice.id}-${invoice.date}.pdf`);
}
