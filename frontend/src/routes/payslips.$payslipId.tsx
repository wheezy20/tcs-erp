import { useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowLeft, Download, Printer } from "lucide-react";
import { toast } from "sonner";

import { PrintDocument } from "@/components/print/print-document";
import { PrintablePayslip, type PayslipDocMeta } from "@/components/print/printable-payslip";
import { Button } from "@/components/ui/button";
import { canViewFinancials, useAuth } from "@/data/auth-store";
import { useCurrentBranch } from "@/data/branch-store";
import { usePayroll } from "@/data/payroll-store";
import { currentConfigFor, useEmployees } from "@/data/employees-store";
import { useDocumentSettings } from "@/data/settings-store";
import { MONTHS } from "@/data/payroll-format";

export const Route = createFileRoute("/payslips/$payslipId")({
  head: () => ({ meta: [{ title: "Payslip — TCS" }] }),
  component: PayslipPage,
});

function PayslipPage() {
  const { payslipId } = Route.useParams();
  const { staff } = useAuth();
  const canView = canViewFinancials(staff?.role);
  const { payslips, runs, loading } = usePayroll();
  const { employees, configs } = useEmployees();
  const { name: branchName } = useCurrentBranch();
  const settings = useDocumentSettings();
  const [downloading, setDownloading] = useState(false);

  if (!canView) {
    return (
      <div className="flex min-h-[50vh] flex-col items-center justify-center gap-3 rounded-2xl border border-dashed px-6 py-24 text-center">
        <h2 className="text-lg font-semibold">Payslips aren't available for this role</h2>
        <p className="max-w-sm text-sm text-muted-foreground">
          Payroll is restricted to Managers, Accountants and Auditors.
        </p>
      </div>
    );
  }

  if (loading) {
    return <div className="py-16 text-center text-sm text-muted-foreground">Loading…</div>;
  }

  const payslip = payslips.find((p) => p.id === payslipId);
  if (!payslip) {
    return (
      <div className="card-surface p-10 text-center">
        <p className="text-sm font-medium">This payslip no longer exists</p>
        <Link to="/payroll" className="mt-3 inline-block text-sm text-primary hover:underline">
          Back to payroll
        </Link>
      </div>
    );
  }

  const run = runs.find((r) => r.id === payslip.payrollRunId);
  const config = currentConfigFor(configs, payslip.employeeId);
  const employee = employees.find((e) => e.id === payslip.employeeId);
  const meta: PayslipDocMeta = {
    periodLabel: run ? `${MONTHS[run.month - 1] ?? run.month} ${run.year}` : "—",
    staffName: payslip.employeeName,
    position: employee?.position ?? null,
    department: employee?.department ?? null,
    bank: config?.bank ?? null,
    accountNo: config?.accountNo ?? null,
    branchName: branchName ?? "",
  };

  async function downloadPdf() {
    setDownloading(true);
    try {
      const { downloadPayslipPdf } = await import("@/lib/pdf/payslip-pdf");
      await downloadPayslipPdf(payslip!, meta, settings);
      toast.success("Payslip downloaded as PDF");
    } catch {
      toast.error("Could not generate the PDF");
    } finally {
      setDownloading(false);
    }
  }

  return (
    <>
      <div className="print-hide mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          {run ? (
            <Link
              to="/payroll/$runId"
              params={{ runId: run.id }}
              className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
            >
              <ArrowLeft className="size-4" /> {meta.periodLabel} payroll
            </Link>
          ) : (
            <Link
              to="/payroll"
              className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
            >
              <ArrowLeft className="size-4" /> Payroll
            </Link>
          )}
          <h1 className="mt-2 text-2xl font-semibold tracking-tight">
            {payslip.employeeName} — {meta.periodLabel}
          </h1>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" className="gap-2" onClick={() => window.print()}>
            <Printer className="size-4" /> Print
          </Button>
          <Button variant="outline" className="gap-2" disabled={downloading} onClick={downloadPdf}>
            <Download className="size-4" /> {downloading ? "Preparing…" : "Download PDF"}
          </Button>
        </div>
      </div>

      <div className="card-surface p-6">
        <PrintablePayslip payslip={payslip} meta={meta} settings={settings} />
      </div>

      <PrintDocument pageSize="A4">
        <PrintablePayslip payslip={payslip} meta={meta} settings={settings} />
      </PrintDocument>
    </>
  );
}
