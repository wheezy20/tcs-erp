import html2canvas from "html2canvas";
import { jsPDF } from "jspdf";

import type { Employee, PayConfig } from "@/data/employees-store";
import type { CompanyDetails } from "@/data/settings-store";

// Contract/letter generation (Phase 4 of the HR expansion) rasterizes a
// real DOM node and embeds the result as an image — appropriate for prose
// of unpredictable length rather than a known tabular structure, and it
// sidesteps invoice-pdf.ts's GH₵-glyph problem entirely: that file has to
// embed a custom Unicode TTF because jsPDF's built-in vector fonts can't
// render U+20B5, but a rasterized screenshot of the browser's own
// rendering has no such limitation — the browser already draws ₵
// correctly before capture.
//
// This calls html2canvas directly (declared as a real dependency, not
// left as jsPDF's undeclared transitive one) and does the PDF placement
// itself via doc.addImage(), rather than using jsPDF's own `.html()`
// convenience method. That method's internal `Worker.prototype.
// toContainer` unconditionally wraps whatever you give it in jsPDF's own
// hidden overlay div, hardcoded to `position: fixed; left: -100000px`
// (see jspdf's own dist/jspdf.es.js) — fine for its default *vector*
// text-embedding mode where a `CanvasRenderingContext2D`-shaped shim
// records draw calls and jsPDF's Context2d translates them into PDF
// operators. But that shim's translate/transform handling doesn't cancel
// out html2canvas's own internal `ctx.translate(-x, -y)` compensation for
// the target element's on-page position, so the whole -100000px overlay
// offset leaks straight into the emitted PDF coordinates: confirmed by
// inspecting the raw content stream of a "blank" generated PDF, which
// contained real BT/Tj text operators in the right fill color, just all
// positioned around x=-7317pt — off the left edge of an A4 page, hence
// genuinely blank on open, not a rendering artifact. Calling html2canvas
// ourselves against a real `<canvas>` avoids the shim (and the bug)
// entirely: html2canvas's raster path is the well-tested standard use
// case and handles arbitrary source-element positioning correctly.

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

const PDF_MARGIN_PT = 40;

/** Renders already-merged HTML to a PDF Blob via an off-screen DOM node,
 * rasterized with html2canvas and placed into the PDF with doc.addImage()
 * — see the module-level comment for why this bypasses jsPDF's own
 * `.html()` method. Always produces a Blob for upload — this feature has
 * no "download only, never stored" path, unlike a one-off invoice: every
 * generated document is a persistent record from its first commit (same
 * reasoning as the receipts-bucket / onboarding-documents fix applied to
 * storage).
 *
 * Paginates a tall render across multiple A4 pages by slicing the
 * rendered canvas into page-height chunks — contracts can run longer
 * than one page even though letters typically don't.
 *
 * `oklch()` workaround: this app's global stylesheet defines its theme
 * colors as `oklch()` custom properties (styles.css `:root`), which
 * html2canvas's CSS color parser can't handle — confirmed live, toast:
 * "Attempting to parse an unsupported color function 'oklch'". `onclone`
 * is html2canvas's own hook for this, called with the cloned document
 * (html2canvas always clones the whole document to compute layout,
 * regardless of where the source element lives) right before rendering —
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
    const canvas = await html2canvas(container, {
      windowWidth: 700,
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
    });

    const doc = new jsPDF({ unit: "pt", format: "a4" });
    const imageWidthPt = doc.internal.pageSize.getWidth() - PDF_MARGIN_PT * 2;
    const pageHeightPt = doc.internal.pageSize.getHeight() - PDF_MARGIN_PT * 2;
    const pxPerPt = canvas.width / imageWidthPt;
    const pageHeightPx = pageHeightPt * pxPerPt;

    let renderedPx = 0;
    let firstPage = true;
    while (renderedPx < canvas.height) {
      const sliceHeightPx = Math.min(pageHeightPx, canvas.height - renderedPx);
      const pageCanvas = document.createElement("canvas");
      pageCanvas.width = canvas.width;
      pageCanvas.height = sliceHeightPx;
      const ctx = pageCanvas.getContext("2d");
      if (!ctx) throw new Error("Could not get 2D context for PDF page slice");
      ctx.drawImage(
        canvas,
        0,
        renderedPx,
        canvas.width,
        sliceHeightPx,
        0,
        0,
        canvas.width,
        sliceHeightPx,
      );

      if (!firstPage) doc.addPage();
      doc.addImage(
        pageCanvas.toDataURL("image/png"),
        "PNG",
        PDF_MARGIN_PT,
        PDF_MARGIN_PT,
        imageWidthPt,
        sliceHeightPx / pxPerPt,
      );
      renderedPx += sliceHeightPx;
      firstPage = false;
    }

    return doc.output("blob");
  } finally {
    document.body.removeChild(container);
  }
}
