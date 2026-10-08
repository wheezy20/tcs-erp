export type ParsedFile = {
  headers: string[];
  rows: Array<Record<string, string>>;
  /** headers in the file that are not part of the template */
  extraColumns: string[];
  /** headers the template expects but the file is missing */
  missingColumns: string[];
  /** completely empty rows that were skipped */
  blankRows: number;
  /** the spreadsheet row number of each entry in `rows` (the header is row
   * 1), so a row after a skipped blank line keeps its real number */
  rowNumbers: number[];
};

export type ParseOptions = {
  /** XLSX only: write date cells as YYYY-MM-DD instead of the file's
   * display format (e.g. "1/5/26"), the same in every time zone. Opt-in;
   * the existing importers don't use it. CSV text is never changed. */
  isoDates?: boolean;
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
  const rowNumbers: number[] = [];
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
    rowNumbers.push(r + 1);
  }

  return { headers, rows, extraColumns, missingColumns, blankRows, rowNumbers };
}

const pad2 = (n: number) => String(n).padStart(2, "0");

export async function parseSpreadsheet(
  file: File,
  expected: string[],
  options: ParseOptions = {},
): Promise<ParsedFile> {
  const isCsv = /\.csv$/i.test(file.name) || file.type === "text/csv";
  if (isCsv) {
    return fromMatrix(parseCsv(await file.text()), expected);
  }
  const XLSX = await import("xlsx");
  const workbook = options.isoDates
    ? XLSX.read(await file.arrayBuffer(), { type: "array", cellNF: true })
    : XLSX.read(await file.arrayBuffer(), { type: "array" });
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  if (options.isoDates) {
    // A date cell is a serial number with a date format. Decode the serial
    // with SheetJS's own calendar code (no time zone involved; a Date object
    // read through local getters is a day out east of UTC), honouring the
    // 1904 date system of old Mac workbooks.
    const date1904 = Boolean(workbook.Workbook?.WBProps?.date1904);
    // The browser build exports SSF by name; Node's CommonJS interop only
    // has it on the default export.
    const SSF = XLSX.SSF ?? (XLSX as unknown as { default: typeof XLSX }).default.SSF;
    for (const address of Object.keys(sheet)) {
      const cell = sheet[address] as
        { t?: string; v?: unknown; z?: string; w?: string } | undefined;
      if (address.startsWith("!") || !cell || cell.t !== "n" || typeof cell.v !== "number")
        continue;
      if (!cell.z || !SSF.is_date(cell.z)) continue;
      const d = SSF.parse_date_code(cell.v, { date1904 });
      if (!d) continue;
      cell.w = `${d.y}-${pad2(d.m)}-${pad2(d.d)}`;
    }
  }
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

/** Download a template as .xlsx with every cell typed as text (format "@"),
 * so Excel keeps leading zeros in phone numbers and IDs and doesn't turn
 * typed dates into its own date format. */
export async function downloadXlsxTemplate(filename: string, rows: string[][]) {
  const XLSX = await import("xlsx");
  const sheet = XLSX.utils.aoa_to_sheet(rows);
  const range = XLSX.utils.decode_range(sheet["!ref"] ?? "A1");
  // Type the first 200 data rows (the import limit) as text, so cells the
  // user fills in stay text too.
  for (let r = range.s.r; r <= Math.max(range.e.r, 200); r += 1) {
    for (let c = range.s.c; c <= range.e.c; c += 1) {
      const address = XLSX.utils.encode_cell({ r, c });
      const cell = sheet[address] ?? { t: "s", v: "" };
      cell.t = "s";
      cell.z = "@";
      sheet[address] = cell;
    }
  }
  sheet["!ref"] = XLSX.utils.encode_range({
    s: range.s,
    e: { r: Math.max(range.e.r, 200), c: range.e.c },
  });
  sheet["!cols"] = rows[0].map((h) => ({ wch: Math.max(12, h.length + 2) }));
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, sheet, "Employees");
  XLSX.writeFile(workbook, filename);
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
