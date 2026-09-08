import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { TODAY } from "@/data/dashboard";

/** Shared by Trial Balance and Balance Sheet — both are point-in-time
 * reports ("as of a chosen date"), unlike Profit & Loss/Cash Flow which
 * need a range (see DateRangeFilter). */
export function AsOfDateFilter({
  value,
  onChange,
}: {
  value: string;
  onChange: (next: string) => void;
}) {
  return (
    <div className="card-surface flex flex-wrap items-end gap-3 p-4">
      <div>
        <label className="text-xs font-medium text-muted-foreground" htmlFor="as-of-date">
          As of
        </label>
        <div className="mt-1">
          <Input
            id="as-of-date"
            type="date"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            className="h-9 w-44 rounded-xl"
          />
        </div>
      </div>
      <Button
        size="sm"
        variant={value === TODAY() ? "default" : "ghost"}
        className="h-9 rounded-xl"
        onClick={() => onChange(TODAY())}
      >
        Today
      </Button>
    </div>
  );
}
