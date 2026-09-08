import { useState } from "react";
import { Download, Loader2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  buildFilename,
  exportSheets,
  type ExportFormat,
  type ExportSheet,
} from "@/lib/export/export-data";

export type ExportMenuProps = {
  /** Filename stem, e.g. "inventory" → tcs-inventory-2026-07-28.csv */
  baseName: string;
  /** Applied filters, folded into the filename. */
  filters?: Array<string | null | undefined | false>;
  /** Human readable summary of what is being exported, shown in the menu. */
  summary?: string;
  /** Built lazily so the export always reflects what is on screen right now. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  getSheets: () => ExportSheet<any>[];
  disabled?: boolean;
  variant?: "outline" | "ghost" | "secondary";
  size?: "default" | "sm";
};

export function ExportMenu({
  baseName,
  filters = [],
  summary,
  getSheets,
  disabled,
  variant = "outline",
  size = "default",
}: ExportMenuProps) {
  const [busy, setBusy] = useState<ExportFormat | null>(null);

  const run = async (format: ExportFormat) => {
    setBusy(format);
    try {
      const sheets = getSheets();
      const count = sheets.reduce((sum, s) => sum + s.rows.length, 0);
      // Give the spinner a beat so the loading state is visible on small exports.
      await new Promise((resolve) => setTimeout(resolve, 350));
      const filename = await exportSheets(format, buildFilename(baseName, filters), sheets);
      toast.success(`${filename} is ready`, {
        description: `${count} row${count === 1 ? "" : "s"} exported${
          summary ? ` · ${summary}` : ""
        }.`,
      });
    } catch {
      toast.error("Export failed", { description: "Something went wrong generating the file." });
    } finally {
      setBusy(null);
    }
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant={variant}
          size={size}
          className="gap-2"
          disabled={disabled || busy !== null}
        >
          {busy ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
          {busy ? "Preparing…" : "Export"}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuLabel className="font-normal text-muted-foreground">
          {summary ?? "Exports what is on screen"}
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={() => void run("csv")}>CSV (.csv)</DropdownMenuItem>
        <DropdownMenuItem onSelect={() => void run("xlsx")}>Excel (.xlsx)</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
