export type ParsedFile = {
  headers: string[];
  rows: Array<Record<string, string>>;
  /** headers in the file that are not part of the template */
  extraColumns: string[];
  /** headers the template expects but the file is missing */
  missingColumns: string[];
  /** completely empty rows that were skipped */
  blankRows: number;
};

const normalise = (value: string) => value.trim().toLowerCase().replace(/\s+/g, " ");

/** Parse a CSV string, handling quoted fields and CRLF. */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
      continue;
    }
    if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (char !== "\r") {
      field += char;
    }
  }
  row.push(field);
  rows.push(row);
  while (rows.length > 0 && rows[rows.length - 1].every((c) => c.trim() === "")) rows.pop();
  return rows;
}

function fromMatrix(matrix: unknown[][], expected: string[]): ParsedFile {
  const headerRow = (matrix[0] ?? []).map((h) => String(h ?? "").trim());
  const expectedByKey = new Map(expected.map((c) => [normalise(c), c]));

  const headers = headerRow;
  const extraColumns = headerRow.filter((h) => h && !expectedByKey.has(normalise(h)));
  const missingColumns = expected.filter(
    (c) => !headerRow.some((h) => normalise(h) === normalise(c)),
  );

  const rows: Array<Record<string, string>> = [];
  let blankRows = 0;

  for (let r = 1; r < matrix.length; r += 1) {
    const cells = matrix[r] ?? [];
    const values = cells.map((c) => String(c ?? "").trim());
    if (values.every((v) => v === "")) {
      blankRows += 1;
      continue;
    }
    const record: Record<string, string> = {};
    headerRow.forEach((header, index) => {
      const key = expectedByKey.get(normalise(header));
      if (key) record[key] = values[index] ?? "";
    });
    rows.push(record);
  }

  return { headers, rows, extraColumns, missingColumns, blankRows };
}

export async function parseSpreadsheet(file: File, expected: string[]): Promise<ParsedFile> {
  const isCsv = /\.csv$/i.test(file.name) || file.type === "text/csv";
  if (isCsv) {
    return fromMatrix(parseCsv(await file.text()), expected);
  }
  const XLSX = await import("xlsx");
  const workbook = XLSX.read(await file.arrayBuffer(), { type: "array" });
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const matrix = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    blankrows: true,
    raw: false,
  });
  return fromMatrix(matrix, expected);
}

export function buildCsv(rows: string[][]) {
  return rows
    .map((row) =>
      row.map((cell) => (/[",\n]/.test(cell) ? `"${cell.replace(/"/g, '""')}"` : cell)).join(","),
    )
    .join("\n");
}

export function downloadCsv(filename: string, rows: string[][]) {
  const blob = new Blob([buildCsv(rows)], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

/** Number parsing that tolerates currency symbols, spaces and thousands separators. */
export function toNumber(value: string): number | null {
  const cleaned = value.replace(/[₵$GHS\s,]/gi, "").trim();
  if (cleaned === "") return null;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

/** Match a value against a list of allowed options, ignoring case and spacing. */
export function matchOption<T extends string>(value: string, options: readonly T[]): T | null {
  const key = normalise(value);
  return options.find((o) => normalise(o) === key) ?? null;
}

export function toBoolean(value: string): boolean | null {
  const key = normalise(value);
  if (["yes", "y", "true", "1"].includes(key)) return true;
  if (["no", "n", "false", "0", ""].includes(key)) return false;
  return null;
}

export function isIsoDate(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value.trim()) && !Number.isNaN(Date.parse(value.trim()));
}
