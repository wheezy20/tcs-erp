import { currencyPrecise } from "@/data/dashboard";
import { MONTHS } from "@/data/payroll-format";
import type { Payslip } from "@/data/payroll-store";
import { formatDate } from "@/data/settings-store";
import type { PayslipAdvanceLine } from "@/data/staff-advances-store";

// Display helpers for staff advances (20261008100000), shared by the
// advances screens, the printed payslip and the payslip PDF.

const money = (n: number) => currencyPrecise(n);

/** Shown wherever an advance is proposed or approved. */
export const ACCOUNT_1350_NOTE =
  "Approval posts the payout: Dr 1350 Advances to Staff / Cr the payout account. Account 1350 is not yet confirmed by the accountant. Don't also record this advance as a “Staff advances” expense, or it will be posted twice.";

export function monthLabel(isoDate: string) {
  const [y, m] = isoDate.split("-");
  return `${MONTHS[Number(m) - 1] ?? m} ${y}`;
}

/** The deduction rows for payslips.iou: one per staff advance repayment
 * (with the balance remaining), or the plain IOU line. A payslip never has
 * both (create_payslip refuses a manual IOU when an advance is deducted). */
export function iouDeductionRows(
  payslip: Payslip,
  lines: PayslipAdvanceLine[] | undefined,
): [string, number][] {
  if (lines && lines.length > 0) {
    return lines.map((l) => [
      `Staff advance of ${money(l.advanceAmount)} (${formatDate(l.disbursedOn)})` +
        (l.amount < l.instalmentDue ? `, instalment ${money(l.instalmentDue)}` : "") +
        ` — balance remaining ${money(l.balanceAfter)}`,
      l.amount,
    ]);
  }
  return payslip.iou > 0 ? [["IOU / advance recovery", payslip.iou]] : [];
}
