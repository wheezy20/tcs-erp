import { useState } from "react";
import { Settings2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { setDefaultThreshold } from "@/data/inventory-store";

export function ThresholdSettings({
  defaultThreshold,
  overrideCount,
}: {
  defaultThreshold: number;
  overrideCount: number;
}) {
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState(String(defaultThreshold));
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    const n = Number(value);
    if (!Number.isInteger(n) || n < 0 || n > 100000) {
      setError("Enter a whole number between 0 and 100,000.");
      return;
    }
    setSaving(true);
    try {
      await setDefaultThreshold(n);
      setError(null);
      setOpen(false);
      toast.success(`Global low-stock threshold set to ${n}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save the threshold.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) {
          setValue(String(defaultThreshold));
          setError(null);
        }
      }}
    >
      <PopoverTrigger asChild>
        <Button variant="outline" className="gap-2">
          <Settings2 className="size-4" /> Stock settings
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80 rounded-2xl p-4">
        <p className="text-sm font-semibold">Low-stock settings</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Products at or below this quantity are flagged as low stock, unless they have their own
          override.
        </p>

        <div className="mt-4 space-y-2">
          <Label htmlFor="global-threshold">Global default threshold</Label>
          <Input
            id="global-threshold"
            type="number"
            min={0}
            step={1}
            value={value}
            onChange={(e) => setValue(e.target.value)}
          />
          {error ? <p className="text-xs font-medium text-destructive">{error}</p> : null}
          <p className="text-xs text-muted-foreground">
            {overrideCount} product{overrideCount === 1 ? "" : "s"} currently override this on their
            detail page.
          </p>
        </div>

        <div className="mt-4 flex justify-end gap-2">
          <Button variant="ghost" size="sm" onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button size="sm" onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  );
}
