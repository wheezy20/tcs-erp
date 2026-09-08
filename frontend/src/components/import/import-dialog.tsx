import { useMemo, useRef, useState, type ReactNode } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Download,
  FileSpreadsheet,
  Loader2,
  Upload,
  Info,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { downloadCsv, parseSpreadsheet, type ParsedFile } from "@/lib/import/parse";
import { cn } from "@/lib/utils";

export type RowCheck<T> = {
  value: T | null;
  errors: string[];
  /** non-blocking notes, e.g. "category capitalisation corrected" */
  notes?: string[];
};

export type ImportConfig<T> = {
  /** Dialog + template title, e.g. "products" */
  entity: string;
  description: string;
  templateFile: string;
  columns: string[];
  exampleRow: string[];
  validate: (row: Record<string, string>, accepted: T[]) => RowCheck<T>;
  onImport: (values: T[]) => void | Promise<void>;
  /** Optional extra preview column showing what a ready row actually
   * resolves to — e.g. "Create" vs. "Update existing X" — so a match
   * (expected or not) is visible in the preview, before import, not
   * discovered afterward. Rendered only for rows with no errors. */
  matchColumn?: {
    header: string;
    value: (row: T) => ReactNode;
  };
  /** Optional extra summary pills alongside the built-in ready/error/blank
   * counts, computed from the ready rows' resolved values — e.g. "3 will
   * create · 2 will update". */
  summaryPills?: (ready: T[]) => { label: string; tone?: "success" | "info" | "muted" }[];
};

type Checked<T> = { raw: Record<string, string>; check: RowCheck<T> };

export function ImportDialog<T>({
  config,
  trigger,
}: {
  config: ImportConfig<T>;
  trigger?: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [fileName, setFileName] = useState("");
  const [parsed, setParsed] = useState<ParsedFile | null>(null);
  const [parseError, setParseError] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const reset = () => {
    setParsed(null);
    setFileName("");
    setParseError("");
    if (inputRef.current) inputRef.current.value = "";
  };

  const checked = useMemo<Checked<T>[]>(() => {
    if (!parsed) return [];
    const accepted: T[] = [];
    return parsed.rows.map((raw) => {
      const check = config.validate(raw, accepted);
      if (check.value && check.errors.length === 0) accepted.push(check.value);
      return { raw, check };
    });
  }, [parsed, config]);

  const validRows = checked.filter((r) => r.check.errors.length === 0);
  const errorRows = checked.filter((r) => r.check.errors.length > 0);
  const readyValues = validRows.map((r) => r.check.value as T);

  const handleFile = async (file: File) => {
    setBusy(true);
    setParseError("");
    try {
      const result = await parseSpreadsheet(file, config.columns);
      setFileName(file.name);
      setParsed(result);
    } catch {
      setParsed(null);
      setParseError("We couldn't read that file. Save it as .csv or .xlsx and try again.");
    } finally {
      setBusy(false);
    }
  };

  const confirmImport = async () => {
    setBusy(true);
    try {
      await config.onImport(readyValues);
      const noun =
        readyValues.length === 1
          ? config.entity.replace(/ies$/, "y").replace(/s$/, "")
          : config.entity;
      toast.success(`Imported ${readyValues.length} ${noun}`, {
        description: errorRows.length
          ? `${errorRows.length} row${errorRows.length === 1 ? "" : "s"} skipped because of errors.`
          : "All rows passed validation.",
      });
      reset();
      setOpen(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Import failed.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) reset();
      }}
    >
      <DialogTrigger asChild>
        {trigger ?? (
          <Button variant="outline" className="rounded-xl">
            <Upload className="size-4" /> Import
          </Button>
        )}
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] gap-0 overflow-hidden p-0 sm:max-w-4xl">
        <DialogHeader className="border-b p-6">
          <DialogTitle className="capitalize">Import {config.entity}</DialogTitle>
          <DialogDescription>{config.description}</DialogDescription>
        </DialogHeader>

        <div className="max-h-[60vh] space-y-6 overflow-y-auto p-6">
          <section className="space-y-3">
            <StepHeading step={1} title="Download the template" />
            <div className="flex flex-wrap items-center gap-3 rounded-2xl border bg-muted/40 p-4">
              <FileSpreadsheet className="size-5 text-muted-foreground" />
              <div className="min-w-40 flex-1">
                <p className="text-sm font-medium">{config.templateFile}</p>
                <p className="text-xs text-muted-foreground">
                  {config.columns.join(", ")} — includes one example row.
                </p>
              </div>
              <Button
                variant="outline"
                className="rounded-xl"
                onClick={() =>
                  downloadCsv(config.templateFile, [config.columns, config.exampleRow])
                }
              >
                <Download className="size-4" /> Download template
              </Button>
            </div>
          </section>

          <section className="space-y-3">
            <StepHeading step={2} title="Upload your file" />
            <div className="flex flex-wrap items-center gap-3 rounded-2xl border border-dashed p-4">
              <input
                ref={inputRef}
                type="file"
                accept=".csv,.xlsx,.xls,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) void handleFile(file);
                }}
              />
              <div className="min-w-40 flex-1">
                <p className="text-sm font-medium">{fileName || "No file selected"}</p>
                <p className="text-xs text-muted-foreground">
                  CSV or Excel (.xlsx, .xls), parsed in your browser.
                </p>
              </div>
              <Button
                className="rounded-xl"
                onClick={() => inputRef.current?.click()}
                disabled={busy}
              >
                {busy ? <Loader2 className="size-4 animate-spin" /> : <Upload className="size-4" />}
                {fileName ? "Choose another file" : "Choose file"}
              </Button>
            </div>
            {parseError && <Callout tone="error">{parseError}</Callout>}
          </section>

          {parsed && (
            <section className="space-y-3">
              <StepHeading step={3} title="Preview and validate" />

              <div className="flex flex-wrap gap-2">
                <Pill tone={validRows.length ? "success" : "muted"}>
                  <CheckCircle2 className="size-3.5" /> {validRows.length} row
                  {validRows.length === 1 ? "" : "s"} ready
                </Pill>
                <Pill tone={errorRows.length ? "error" : "muted"}>
                  <AlertTriangle className="size-3.5" /> {errorRows.length} row
                  {errorRows.length === 1 ? "" : "s"} with errors
                </Pill>
                {parsed.blankRows > 0 && (
                  <Pill tone="muted">
                    <Info className="size-3.5" /> {parsed.blankRows} blank row
                    {parsed.blankRows === 1 ? "" : "s"} skipped
                  </Pill>
                )}
                {parsed.extraColumns.length > 0 && (
                  <Pill tone="warning">
                    <Info className="size-3.5" /> Ignored extra column
                    {parsed.extraColumns.length === 1 ? "" : "s"}: {parsed.extraColumns.join(", ")}
                  </Pill>
                )}
                {config.summaryPills?.(readyValues).map((p, i) => (
                  <Pill key={i} tone={p.tone ?? "muted"}>
                    {p.label}
                  </Pill>
                ))}
              </div>

              {parsed.missingColumns.length > 0 && (
                <Callout tone="error">
                  Missing column{parsed.missingColumns.length === 1 ? "" : "s"}:{" "}
                  {parsed.missingColumns.join(", ")}. Rows depending on them will fail validation.
                </Callout>
              )}

              {checked.length === 0 ? (
                <Callout tone="warning">This file has no data rows.</Callout>
              ) : (
                <div className="overflow-x-auto rounded-2xl border">
                  <table className="w-full text-sm">
                    <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                      <tr>
                        <th className="px-3 py-2 font-medium">#</th>
                        <th className="px-3 py-2 font-medium">Status</th>
                        {config.matchColumn && (
                          <th className="whitespace-nowrap px-3 py-2 font-medium">
                            {config.matchColumn.header}
                          </th>
                        )}
                        {config.columns.map((c) => (
                          <th key={c} className="whitespace-nowrap px-3 py-2 font-medium">
                            {c}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody className="divide-y">
                      {checked.map((row, index) => {
                        const failed = row.check.errors.length > 0;
                        return (
                          <tr key={index} className={cn(failed && "bg-destructive/5")}>
                            <td className="px-3 py-2 align-top text-xs text-muted-foreground">
                              {index + 2}
                            </td>
                            <td className="w-64 min-w-56 px-3 py-2 align-top">
                              {failed ? (
                                <span className="text-xs font-medium text-destructive">
                                  {row.check.errors.join(" · ")}
                                </span>
                              ) : row.check.notes?.length ? (
                                <span className="text-xs font-medium text-[color:var(--warning-foreground)] dark:text-[color:var(--warning)]">
                                  Ready · {row.check.notes.join(" · ")}
                                </span>
                              ) : (
                                <span className="text-xs font-medium text-primary">Ready</span>
                              )}
                            </td>
                            {config.matchColumn && (
                              <td className="whitespace-nowrap px-3 py-2 align-top text-xs">
                                {!failed && row.check.value ? (
                                  config.matchColumn.value(row.check.value)
                                ) : (
                                  <span className="text-muted-foreground">—</span>
                                )}
                              </td>
                            )}
                            {config.columns.map((c) => (
                              <td key={c} className="whitespace-nowrap px-3 py-2 align-top">
                                {row.raw[c] || <span className="text-muted-foreground">—</span>}
                              </td>
                            ))}
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          )}
        </div>

        <DialogFooter className="gap-2 border-t p-6">
          <Button
            variant="ghost"
            className="rounded-xl"
            onClick={() => {
              reset();
              setOpen(false);
            }}
          >
            Cancel
          </Button>
          <Button
            className="rounded-xl"
            onClick={confirmImport}
            disabled={validRows.length === 0 || busy}
          >
            {busy
              ? "Importing…"
              : `Import ${validRows.length} valid row${validRows.length === 1 ? "" : "s"}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function StepHeading({ step, title }: { step: number; title: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className="flex size-6 items-center justify-center rounded-lg bg-primary/15 text-xs font-semibold text-primary">
        {step}
      </span>
      <h3 className="text-sm font-semibold">{title}</h3>
    </div>
  );
}

function Pill({
  tone,
  children,
}: {
  tone: "success" | "error" | "warning" | "info" | "muted";
  children: ReactNode;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-xl px-2.5 py-1 text-xs font-medium",
        tone === "success" && "bg-accent text-accent-foreground",
        tone === "error" && "bg-destructive/10 text-destructive",
        tone === "warning" &&
          "bg-[color:var(--warning)]/15 text-[color:var(--warning-foreground)] dark:text-[color:var(--warning)]",
        tone === "info" && "bg-primary/10 text-primary",
        tone === "muted" && "bg-muted text-muted-foreground",
      )}
    >
      {children}
    </span>
  );
}

function Callout({ tone, children }: { tone: "error" | "warning"; children: ReactNode }) {
  return (
    <p
      className={cn(
        "rounded-xl px-3 py-2 text-sm",
        tone === "error" && "bg-destructive/10 text-destructive",
        tone === "warning" &&
          "bg-[color:var(--warning)]/15 text-[color:var(--warning-foreground)] dark:text-[color:var(--warning)]",
      )}
    >
      {children}
    </p>
  );
}
