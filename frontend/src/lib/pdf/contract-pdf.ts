import { jsPDF } from "jspdf";

import type { Employee, PayConfig } from "@/data/employees-store";
import type { CompanyDetails } from "@/data/settings-store";

// Contract/letter generation (Phase 4 of the HR expansion) uses jsPDF's
// `.html()` render mode instead of invoice-pdf.ts's hand-positioned
// `doc.text()`/`autoTable()` — appropriate for prose of unpredictable
// length rather than a known tabular structure. `.html()` rasterizes a
// real DOM node via html2canvas (already present as jsPDF's own
// transitive dependency, confirmed in node_modules — no new install)
// and embeds the result as an image, which sidesteps invoice-pdf.ts's
// GH₵-glyph problem entirely: that file has to embed a custom Unicode
// TTF because jsPDF's built-in vector fonts can't render U+20B5, but a
// rasterized screenshot of the browser's own rendering has no such
// limitation — the browser already draws ₵ correctly before capture.

export type MergeData = Record<string, string>;

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(`${iso}T00:00:00`).toLocaleDateString("en-GB", {
    day: "2-digit",
    month: "long",
    year: "numeric",
  });
}

function monthsBetween(start: string | null, end: string | null): string {
  if (!start || !end) return "—";
  const s = new Date(`${start}T00:00:00`);
  const e = new Date(`${end}T00:00:00`);
  const months = (e.getFullYear() - s.getFullYear()) * 12 + (e.getMonth() - s.getMonth());
  return String(Math.max(months, 0));
}

/** Every merge field any of the four templates can reference — the
 * categories differ only in which of these their prose actually uses,
 * not in what's technically available (see docs/DESIGN.md). */
export function buildDocumentMergeData(
  employee: Employee,
  payConfig: PayConfig | undefined,
  company: CompanyDetails,
): MergeData {
  return {
    company_name: company.name,
    company_address: company.address,
    company_phone: company.phone,
    company_email: company.email,
    issue_date: formatDate(new Date().toISOString().slice(0, 10)),
    employee_name: employee.name,
    position: employee.position ?? "—",
    department: employee.department ?? "—",
    employment_type: employee.employmentType ?? "—",
    start_date: formatDate(employee.startDate),
    probation_end_date: formatDate(employee.probationEndDate),
    contract_end_date: employee.contractEndDate
      ? formatDate(employee.contractEndDate)
      : "Open-ended",
    probation_duration_months: monthsBetween(employee.startDate, employee.probationEndDate),
    basic_salary: payConfig
      ? payConfig.basicSalary.toLocaleString("en-GH", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })
      : "—",
    payment_method: payConfig?.paymentMethod ?? "—",
    qualifications:
      employee.qualifications && employee.qualifications.length > 0
        ? employee.qualifications.join(", ")
        : "—",
  };
}

export function mergeTemplate(htmlBody: string, data: MergeData): string {
  return htmlBody.replace(/\{\{(\w+)\}\}/g, (_match, key: string) => data[key] ?? "");
}

/** Renders already-merged HTML to a PDF Blob via an off-screen DOM node.
 * Always produces a Blob for upload — this feature has no "download only,
 * never stored" path, unlike a one-off invoice: every generated document
 * is a persistent record from its first commit (same reasoning as the
 * receipts-bucket / onboarding-documents fix applied to storage).
 *
 * `oklch()` workaround: this app's global stylesheet defines its theme
 * colors as `oklch()` custom properties (styles.css `:root`), which
 * html2canvas's CSS color parser can't handle — confirmed live, toast:
 * "Attempting to parse an unsupported color function 'oklch'". Tried
 * isolating the render target in its own `<iframe>` first, but jsPDF's
 * `.html()` doesn't actually render where you put the source element: it
 * clones it and re-parents the clone into the *real* `document.body`
 * before calling html2canvas (see `Worker.prototype.toContainer` in
 * jspdf's own source), and html2canvas then clones the *entire* document
 * again internally — so the app's own oklch-themed page is always in
 * scope regardless of where the original element lived. The fix has to
 * happen inside that clone: `onclone` is html2canvas's own hook for
 * exactly this, called with the cloned document just before rendering —
 * used here to force every color-related property to plain, parseable
 * values, since none of this feature's own template HTML uses Tailwind
 * classes or these custom properties at all (it's plain tags and inline
 * styles), so neutralizing them has no visible effect on the letter
 * itself. */
export async function renderMergedHtmlToPdfBlob(html: string): Promise<Blob> {
  const container = document.createElement("div");
  container.style.position = "fixed";
  container.style.left = "-10000px";
  container.style.top = "0";
  container.style.width = "700px";
  container.innerHTML = html;
  document.body.appendChild(container);

  try {
    const doc = new jsPDF({ unit: "pt", format: "a4" });
    await doc.html(container, {
      x: 40,
      y: 40,
      width: 515,
      windowWidth: 700,
      html2canvas: {
        onclone: (clonedDoc: Document) => {
          const style = clonedDoc.createElement("style");
          style.textContent = `
            *, *::before, *::after {
              color: #111111 !important;
              background-color: #ffffff !important;
              border-color: #cccccc !important;
              outline-color: transparent !important;
              box-shadow: none !important;
              text-decoration-color: currentColor !important;
            }
          `;
          clonedDoc.head.appendChild(style);
        },
      },
    });
    return doc.output("blob");
  } finally {
    document.body.removeChild(container);
  }
}
