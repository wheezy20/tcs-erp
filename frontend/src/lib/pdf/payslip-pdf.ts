import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";

import { currencyPrecise } from "@/data/dashboard";
import type { Payslip } from "@/data/payroll-store";
import type { DocumentSettings } from "@/data/settings-store";
import { INTER_BOLD_TTF_BASE64 } from "@/lib/pdf/fonts/inter-bold";
import { INTER_REGULAR_TTF_BASE64 } from "@/lib/pdf/fonts/inter-regular";
import type { PayslipDocMeta } from "@/components/print/printable-payslip";

// Same Unicode-font workaround as invoice-pdf.ts — jsPDF's built-in fonts
// can't render the Ghana Cedi sign, so embed Inter.
function registerPdfFonts(doc: jsPDF) {
  doc.addFileToVFS("Inter-Regular.ttf", INTER_REGULAR_TTF_BASE64);
  doc.addFont("Inter-Regular.ttf", "Inter", "normal");
  doc.addFileToVFS("Inter-Bold.ttf", INTER_BOLD_TTF_BASE64);
  doc.addFont("Inter-Bold.ttf", "Inter", "bold");
}

const money = (n: number) => currencyPrecise(n);

export async function downloadPayslipPdf(
  payslip: Payslip,
  meta: PayslipDocMeta,
  settings: DocumentSettings,
) {
  const doc = new jsPDF({ unit: "mm", format: "a4", orientation: "portrait" });
  registerPdfFonts(doc);

  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 14;
  const right = pageWidth - margin;
  const company = settings.company;
  let y = margin;

  doc.setFont("Inter", "bold");
  doc.setFontSize(14);
  doc.text(company.name, margin, y + 5);
  doc.setFont("Inter", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(90);
  [company.address, [company.phone, company.email].filter(Boolean).join(" · "), meta.branchName]
    .filter(Boolean)
    .forEach((line, i) => doc.text(line as string, margin, y + 10 + i * 4));

  doc.setTextColor(120);
  doc.setFontSize(8);
  doc.text("PAYSLIP", right, y + 4, { align: "right" });
  doc.setTextColor(20);
  doc.setFont("Inter", "bold");
  doc.setFontSize(12);
  doc.text(meta.periodLabel, right, y + 10, { align: "right" });

  y += 28;
  doc.setDrawColor(220);
  doc.line(margin, y, right, y);
  y += 6;

  doc.setFont("Inter", "normal");
  doc.setFontSize(9);
  doc.setTextColor(20);
  doc.text(`Employee: ${meta.staffName}`, margin, y);
  doc.text(
    `Position: ${[meta.position, meta.department].filter(Boolean).join(" · ") || "—"}`,
    margin,
    y + 5,
  );
  doc.text(
    `Bank: ${meta.bank ? `${meta.bank}${meta.accountNo ? ` · ${meta.accountNo}` : ""}` : "—"}`,
    margin,
    y + 10,
  );
  y += 18;

  const earnings: [string, string][] = [
    ["Basic salary", money(payslip.basicSalary)],
    ...payslip.allowances.map((a) => [a.allowanceTypeName, money(a.amount)] as [string, string]),
  ];
  if (payslip.overtimePay > 0) {
    earnings.push([
      `Overtime (${payslip.overtimeHours}h @ ${money(payslip.overtimeRate)})`,
      money(payslip.overtimePay),
    ]);
  }
  earnings.push(["Gross salary", money(payslip.grossSalary)]);

  const deductions: [string, string][] = [
    ["PAYE (income tax)", money(payslip.tax)],
    ["Tier 2 (5%)", money(payslip.tier2)],
    ["SSNIT (0.5%)", money(payslip.ssnit)],
  ];
  if (payslip.fines > 0) deductions.push(["Fines", money(payslip.fines)]);
  if (payslip.iou > 0) deductions.push(["IOU / advance recovery", money(payslip.iou)]);
  deductions.push(["Total deductions", money(payslip.totalDeductions)]);

  autoTable(doc, {
    startY: y,
    margin: { left: margin, right: margin },
    head: [["Earnings", "Amount"]],
    body: earnings,
    styles: { font: "Inter", fontSize: 9, cellPadding: 1.8 },
    headStyles: { fillColor: [27, 27, 27], textColor: 255, fontSize: 8 },
    columnStyles: { 1: { halign: "right" } },
    didParseCell: (data) => {
      if (data.row.index === earnings.length - 1) data.cell.styles.fontStyle = "bold";
    },
  });

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let ty = ((doc as any).lastAutoTable?.finalY ?? y) + 6;

  autoTable(doc, {
    startY: ty,
    margin: { left: margin, right: margin },
    head: [["Deductions", "Amount"]],
    body: deductions,
    styles: { font: "Inter", fontSize: 9, cellPadding: 1.8 },
    headStyles: { fillColor: [27, 27, 27], textColor: 255, fontSize: 8 },
    columnStyles: { 1: { halign: "right" } },
    didParseCell: (data) => {
      if (data.row.index === deductions.length - 1) data.cell.styles.fontStyle = "bold";
    },
  });

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ty = ((doc as any).lastAutoTable?.finalY ?? ty) + 8;

  doc.setFont("Inter", "normal");
  doc.setFontSize(9);
  doc.setTextColor(90);
  doc.text("Total earning", margin, ty);
  doc.text(money(payslip.totalEarning), right, ty, { align: "right" });
  doc.text("Taxable income", margin, ty + 5);
  doc.text(money(payslip.taxableIncome), right, ty + 5, { align: "right" });

  ty += 12;
  doc.setDrawColor(210);
  doc.setFillColor(243, 244, 246);
  doc.rect(margin, ty, right - margin, 10, "F");
  doc.setFont("Inter", "bold");
  doc.setFontSize(12);
  doc.setTextColor(20);
  doc.text("NET PAY", margin + 3, ty + 6.7);
  doc.text(money(payslip.netPay), right - 3, ty + 6.7, { align: "right" });
  ty += 10;

  // Employer contributions — shown for information only, never part of the
  // employee's net-pay math. Skipped for exempt staff / pre-20260909120000
  // payslips (ssnit_employer = 0).
  if (payslip.ssnitEmployer > 0) {
    ty += 6;
    doc.setDrawColor(200);
    doc.setLineDashPattern([1, 1], 0);
    doc.line(margin, ty, right, ty);
    doc.setLineDashPattern([], 0);
    ty += 5;
    doc.setFont("Inter", "bold");
    doc.setFontSize(8);
    doc.setTextColor(90);
    doc.text(
      `Employer contributions (paid by ${company.name || "the employer"}, not deducted from your pay)`,
      margin,
      ty,
    );
    doc.setFont("Inter", "normal");
    doc.text("SSNIT (13%)", margin, ty + 5);
    doc.text(money(payslip.ssnitEmployer), right, ty + 5, { align: "right" });
    doc.setFont("Inter", "bold");
    doc.text("Total cost of employment this month", margin, ty + 10);
    doc.text(money(payslip.grossSalary + payslip.ssnitEmployer), right, ty + 10, {
      align: "right",
    });
    ty += 10;
  }

  doc.setFont("Inter", "normal");
  doc.setFontSize(7.5);
  doc.setTextColor(140);
  doc.text(
    `Generated ${new Date(payslip.generatedAt).toLocaleString()} · system-generated, no signature required`,
    margin,
    ty + 8,
  );

  doc.save(
    `tcs-payslip-${meta.staffName.replace(/\s+/g, "-").toLowerCase()}-${meta.periodLabel.replace(/\s+/g, "-").toLowerCase()}.pdf`,
  );
}
