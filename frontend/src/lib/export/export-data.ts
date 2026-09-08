import { TODAY } from "@/data/dashboard";

export type ExportFormat = "csv" | "xlsx";

export type ExportColumn<T> = {
  /** Human readable header, matching the UI label. */
  header: string;
  value: (row: T) => string | number;
};

export type ExportSheet<T = never> = {
  /** Sheet name in Excel / section title in CSV. */
  name: string;
  columns: ExportColumn<T>[];
  rows: T[];
};

/** Turns applied filters into a filename-safe slug, e.g. "paint-low-stock". */
export function filterSlug(parts: Array<string | null | undefined | false>) {
  return parts
    .filter((p): p is string => Boolean(p && p.trim()))
    .map((p) =>
      p
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, ""),
    )
    .filter(Boolean)
    .join("-")
    .slice(0, 60);
}

/** tcs-inventory-paint-2026-07-28.csv */
export function buildFilename(base: string, filters: Array<string | null | undefined | false>) {
  const slug = filterSlug(filters);
  return ["tcs", base, slug, TODAY()].filter(Boolean).join("-");
}

const escapeCsv = (value: string | number) => {
  const text = String(value ?? "");
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function toCsv(sheets: ExportSheet<any>[]) {
  const blocks = sheets.map((sheet) => {
    const lines: string[] = [];
    if (sheets.length > 1) lines.push(escapeCsv(sheet.name));
    lines.push(sheet.columns.map((c) => escapeCsv(c.header)).join(","));
    for (const row of sheet.rows) {
      lines.push(sheet.columns.map((c) => escapeCsv(c.value(row))).join(","));
    }
    if (sheet.rows.length === 0) lines.push("");
    return lines.join("\r\n");
  });
  return blocks.join("\r\n\r\n");
}

function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

/**
 * Writes the given sheets to a CSV or Excel file and triggers a browser download.
 * Returns the filename that was produced.
 */
export async function exportSheets(
  format: ExportFormat,
  baseName: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  sheets: ExportSheet<any>[],
) {
  if (format === "csv") {
    const filename = `${baseName}.csv`;
    // BOM keeps accents and the GH₵ sign readable when opened in Excel.
    download(new Blob(["\uFEFF", toCsv(sheets)], { type: "text/csv;charset=utf-8" }), filename);
    return filename;
  }

  const XLSX = await import("xlsx");
  const workbook = XLSX.utils.book_new();
  for (const sheet of sheets) {
    const aoa = [
      sheet.columns.map((c) => c.header),
      ...sheet.rows.map((row) => sheet.columns.map((c) => c.value(row))),
    ];
    const worksheet = XLSX.utils.aoa_to_sheet(aoa);
    worksheet["!cols"] = sheet.columns.map((c) => ({
      wch: Math.min(
        42,
        Math.max(
          c.header.length + 2,
          ...sheet.rows.slice(0, 200).map((row) => String(c.value(row)).length + 2),
        ),
      ),
    }));
    XLSX.utils.book_append_sheet(workbook, worksheet, sheet.name.slice(0, 31) || "Sheet1");
  }
  const filename = `${baseName}.xlsx`;
  const out = XLSX.write(workbook, { bookType: "xlsx", type: "array" }) as ArrayBuffer;
  download(
    new Blob([out], {
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    }),
    filename,
  );
  return filename;
}
