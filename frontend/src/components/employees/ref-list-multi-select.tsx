import { useState } from "react";
import { Check, ChevronsUpDown, X } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

/** A multi-select picker backed by a school-editable reference list
 * (qualifications) — same Command+Popover combobox shape as
 * ProductSearchSelect, generalized to more than one selection. Adding a
 * genuinely new option isn't done here, on purpose: none of the existing
 * single-select reference pickers (RefListSelect, for positions/
 * departments) support that inline either — a new entry is added on the
 * Payroll Setup page's RefListSection, same place positions/departments
 * already are, and this component just picks from what's active there.
 * A stored value no longer in the active list still round-trips as a
 * badge, flagged "(not in list)" — same convention as RefListSelect. */
export function RefListMultiSelect({
  options,
  value,
  onChange,
  placeholder = "Select…",
  disabled,
}: {
  options: string[];
  value: string[];
  onChange: (v: string[]) => void;
  placeholder?: string;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const filtered = options.filter((o) => o.toLowerCase().includes(query.toLowerCase()));
  const legacy = value.filter((v) => !options.includes(v));

  function toggle(option: string) {
    if (value.includes(option)) onChange(value.filter((v) => v !== option));
    else onChange([...value, option]);
  }

  return (
    <div className="space-y-2">
      <Popover
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) setQuery("");
        }}
      >
        <PopoverTrigger asChild>
          <Button
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            disabled={disabled}
            className="w-full justify-between rounded-xl font-normal"
          >
            <span
              className={cn("truncate text-left", value.length === 0 && "text-muted-foreground")}
            >
              {value.length > 0 ? `${value.length} selected` : placeholder}
            </span>
            <ChevronsUpDown className="ml-2 size-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent
          className="w-[var(--radix-popover-trigger-width)] min-w-72 p-0"
          align="start"
        >
          <Command shouldFilter={false}>
            <CommandInput value={query} onValueChange={setQuery} placeholder="Search…" />
            <CommandList>
              <CommandEmpty>No matches.</CommandEmpty>
              <CommandGroup>
                {filtered.map((option) => (
                  <CommandItem key={option} value={option} onSelect={() => toggle(option)}>
                    <Check
                      className={cn("size-4", value.includes(option) ? "opacity-100" : "opacity-0")}
                    />
                    {option}
                  </CommandItem>
                ))}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
      {value.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {value.map((v) => (
            <Badge
              key={v}
              variant={legacy.includes(v) ? "outline" : "secondary"}
              className="gap-1 pr-1"
            >
              {v}
              {legacy.includes(v) ? " (not in list)" : ""}
              {!disabled && (
                <button
                  type="button"
                  onClick={() => toggle(v)}
                  className="ml-0.5 rounded-full hover:bg-black/10"
                >
                  <X className="size-3" />
                </button>
              )}
            </Badge>
          ))}
        </div>
      )}
    </div>
  );
}
