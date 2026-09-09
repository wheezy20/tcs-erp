import { currencyPrecise } from "@/data/dashboard";
import type { Payslip } from "@/data/payroll-store";
import type { DocumentSettings } from "@/data/settings-store";

export type PayslipDocMeta = {
  periodLabel: string;
  staffName: string;
  position: string | null;
  department: string | null;
  paymentMethod: "Bank" | "Mobile Money";
  bank: string | null;
  accountNo: string | null;
  branchName: string;
};

const money = (n: number) => currencyPrecise(n);

/** A4 payslip, laid out to mirror the columns of the payroll Google Sheet
 * it replaces: Basic Salary, allowances (Extra Classes etc.), Overtime,
 * Total Earning / Gross Salary, Taxable Income, then the deduction stack
 * (Tax, Tier 2, SSNIT, Fines, IOU) and Net Pay. */
export function PrintablePayslip({
  payslip,
  meta,
  settings,
}: {
  payslip: Payslip;
  meta: PayslipDocMeta;
  settings: DocumentSettings;
}) {
  const company = settings.company;

  const earnings: [string, number][] = [
    ["Basic salary", payslip.basicSalary],
    ...payslip.allowances.map((a) => [a.allowanceTypeName, a.amount] as [string, number]),
    ...(payslip.overtimePay > 0
      ? ([
          [
            `Overtime (${payslip.overtimeHours}h @ ${money(payslip.overtimeRate)})`,
            payslip.overtimePay,
          ],
        ] as [string, number][])
      : []),
  ];

  const deductions: [string, number][] = [
    ["PAYE (income tax)", payslip.tax],
    ["Tier 2 (5%)", payslip.tier2],
    ["SSNIT (0.5%)", payslip.ssnit],
    ...(payslip.fines > 0 ? ([["Fines", payslip.fines]] as [string, number][]) : []),
    ...(payslip.iou > 0 ? ([["IOU / advance recovery", payslip.iou]] as [string, number][]) : []),
  ];

  return (
    <div
      className="printable-payslip"
      style={{
        width: "180mm",
        margin: "0 auto",
        color: "#111",
        background: "#fff",
        fontFamily: "ui-sans-serif, system-ui, sans-serif",
        fontSize: "11px",
        lineHeight: 1.5,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <div>
          <p style={{ margin: 0, fontWeight: 700, fontSize: "15px" }}>{company.name}</p>
          <p style={{ margin: 0, color: "#555" }}>{company.address}</p>
          <p style={{ margin: 0, color: "#555" }}>
            {[company.phone, company.email].filter(Boolean).join(" · ")}
          </p>
          <p style={{ margin: 0, color: "#555" }}>{meta.branchName}</p>
        </div>
        <div style={{ textAlign: "right" }}>
          <p style={{ margin: 0, fontWeight: 700, letterSpacing: "0.1em", color: "#666" }}>
            PAYSLIP
          </p>
          <p style={{ margin: 0, fontSize: "13px", fontWeight: 600 }}>{meta.periodLabel}</p>
        </div>
      </div>

      <hr style={{ border: 0, borderTop: "1px solid #ddd", margin: "12px 0" }} />

      <table style={{ width: "100%", borderCollapse: "collapse", marginBottom: "14px" }}>
        <tbody>
          <Row label="Employee" value={meta.staffName} />
          <Row
            label="Position"
            value={[meta.position, meta.department].filter(Boolean).join(" · ") || "—"}
          />
          <Row
            label={meta.paymentMethod === "Mobile Money" ? "Mobile money" : "Bank"}
            value={meta.bank ? `${meta.bank}${meta.accountNo ? ` · ${meta.accountNo}` : ""}` : "—"}
          />
        </tbody>
      </table>

      <div style={{ display: "flex", gap: "16px" }}>
        <Section title="Earnings" rows={earnings} total={["Gross salary", payslip.grossSalary]} />
        <Section
          title="Deductions"
          rows={deductions}
          total={["Total deductions", payslip.totalDeductions]}
        />
      </div>

      <table style={{ width: "100%", borderCollapse: "collapse", marginTop: "14px" }}>
        <tbody>
          <Row label="Total earning" value={money(payslip.totalEarning)} align="right" />
          <Row label="Taxable income" value={money(payslip.taxableIncome)} align="right" />
        </tbody>
      </table>

      <div
        style={{
          marginTop: "12px",
          padding: "10px 14px",
          background: "#f3f4f6",
          borderRadius: "6px",
          display: "flex",
          justifyContent: "space-between",
          fontSize: "14px",
          fontWeight: 700,
        }}
      >
        <span>NET PAY</span>
        <span>{money(payslip.netPay)}</span>
      </div>

      {payslip.ssnitEmployer > 0 && (
        <div
          style={{
            marginTop: "12px",
            paddingTop: "8px",
            borderTop: "1px dashed #ccc",
            color: "#555",
            fontSize: "9.5px",
          }}
        >
          <p style={{ margin: "0 0 2px", fontWeight: 600 }}>
            Employer contributions (paid by {company.name || "the employer"}, not deducted from your
            pay)
          </p>
          <div style={{ display: "flex", justifyContent: "space-between", maxWidth: "300px" }}>
            <span>SSNIT (13%)</span>
            <span style={{ fontVariantNumeric: "tabular-nums" }}>
              {money(payslip.ssnitEmployer)}
            </span>
          </div>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              maxWidth: "300px",
              fontWeight: 600,
            }}
          >
            <span>Total cost of employment this month</span>
            <span style={{ fontVariantNumeric: "tabular-nums" }}>
              {money(payslip.grossSalary + payslip.ssnitEmployer)}
            </span>
          </div>
        </div>
      )}

      <p style={{ marginTop: "18px", color: "#888", fontSize: "9.5px" }}>
        Generated {new Date(payslip.generatedAt).toLocaleString()}. Figures are computed and frozen
        at generation. This payslip is system-generated and does not require a signature.
      </p>
    </div>
  );
}

function Row({
  label,
  value,
  align = "left",
}: {
  label: string;
  value: string;
  align?: "left" | "right";
}) {
  return (
    <tr>
      <td style={{ padding: "2px 0", color: "#555", width: "40%" }}>{label}</td>
      <td style={{ padding: "2px 0", textAlign: align, fontWeight: align === "right" ? 600 : 400 }}>
        {value}
      </td>
    </tr>
  );
}

function Section({
  title,
  rows,
  total,
}: {
  title: string;
  rows: [string, number][];
  total: [string, number];
}) {
  return (
    <div style={{ flex: 1 }}>
      <p style={{ margin: "0 0 4px", fontWeight: 700, color: "#666" }}>{title}</p>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <tbody>
          {rows.map(([label, amount], i) => (
            <tr key={`${label}-${i}`}>
              <td style={{ padding: "3px 0", borderBottom: "1px solid #eee" }}>{label}</td>
              <td
                style={{
                  padding: "3px 0",
                  borderBottom: "1px solid #eee",
                  textAlign: "right",
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {money(amount)}
              </td>
            </tr>
          ))}
          <tr>
            <td style={{ padding: "5px 0", fontWeight: 700 }}>{total[0]}</td>
            <td
              style={{
                padding: "5px 0",
                fontWeight: 700,
                textAlign: "right",
                fontVariantNumeric: "tabular-nums",
              }}
            >
              {money(total[1])}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}
