import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PRESET_LABELS, presetRange, type RangePreset } from "@/data/reports";

/** Shared by Profit & Loss and Cash Flow — both are over-a-range reports.
 * Same preset vocabulary Phase 1's Reports page already uses
 * (data/reports.ts's presetRange()/PRESET_LABELS), so "This month" means
 * the same date span everywhere in the app rather than a second definition
 * that could drift from the first. */
export function DateRangeFilter({
  preset,
  from,
  to,
  onChange,
}: {
  preset: RangePreset;
  from: string;
  to: string;
  onChange: (next: { preset: RangePreset; from: string; to: string }) => void;
}) {
  return (
    <div className="card-surface flex flex-wrap items-end gap-3 p-4">
      <div className="flex flex-wrap gap-1.5">
        {PRESET_LABELS.map((p) => (
          <Button
            key={p.id}
            size="sm"
            variant={preset === p.id ? "default" : "ghost"}
            className="h-9 rounded-xl"
            onClick={() => onChange({ preset: p.id, ...presetRange(p.id) })}
          >
            {p.label}
          </Button>
        ))}
      </div>
      <div className="ml-auto flex flex-wrap items-end gap-3">
        <div>
          <label className="text-xs font-medium text-muted-foreground" htmlFor="pl-from">
            From
          </label>
          <div className="mt-1">
            <Input
              id="pl-from"
              type="date"
              value={from}
              onChange={(e) => onChange({ preset: "custom", from: e.target.value, to })}
              className="h-9 w-40 rounded-xl"
            />
          </div>
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground" htmlFor="pl-to">
            To
          </label>
          <div className="mt-1">
            <Input
              id="pl-to"
              type="date"
              value={to}
              onChange={(e) => onChange({ preset: "custom", from, to: e.target.value })}
              className="h-9 w-40 rounded-xl"
            />
          </div>
        </div>
      </div>
    </div>
  );
}
