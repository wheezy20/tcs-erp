import { useState } from "react";
import { Check, ChevronsUpDown } from "lucide-react";

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
import { type Product } from "@/data/inventory";
import { cn } from "@/lib/utils";

/** Same match — name, SKU, category, size, case-insensitive substring — as
 * ProductGrid (POS checkout) and the Inventory list's own search box. Kept
 * here as the one shared definition rather than copied a third time. */
export function matchesProductQuery(product: Product, query: string) {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return (
    product.name.toLowerCase().includes(q) ||
    product.sku.toLowerCase().includes(q) ||
    product.category.toLowerCase().includes(q) ||
    product.size.toLowerCase().includes(q)
  );
}

/** A real search-filtered product picker — replaces a plain <Select>, whose
 * built-in type-ahead only matches from the start of an option's own
 * rendered text (so typing a SKU, category, or size never found anything).
 * Used by invoice-form.tsx's line items and purchasing.new.tsx's line
 * items — both needed the identical fix, so this is the one shared
 * implementation rather than two near-duplicates. */
export function ProductSearchSelect({
  products,
  value,
  onSelect,
  optionLabel,
  isOptionDisabled,
  disabledHint,
  placeholder = "Choose from inventory",
}: {
  products: Product[];
  value: string | null;
  onSelect: (product: Product) => void;
  /** The full "Name — price/cost / unit" line shown both in the trigger
   * (once selected) and in each list row — matches what the <Select> this
   * replaces already showed, just now reachable by search too. */
  optionLabel: (product: Product) => string;
  isOptionDisabled?: (product: Product) => boolean;
  disabledHint?: string;
  placeholder?: string;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const selected = products.find((p) => p.id === value) ?? null;
  const filtered = products.filter((p) => matchesProductQuery(p, query));

  return (
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
          className="w-full justify-between rounded-xl font-normal"
        >
          <span className={cn("truncate text-left", !selected && "text-muted-foreground")}>
            {selected ? optionLabel(selected) : placeholder}
          </span>
          <ChevronsUpDown className="ml-2 size-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[var(--radix-popover-trigger-width)] min-w-72 p-0" align="start">
        <Command shouldFilter={false}>
          <CommandInput
            value={query}
            onValueChange={setQuery}
            placeholder="Search by name, SKU, category or size…"
          />
          <CommandList>
            <CommandEmpty>No products match this search.</CommandEmpty>
            <CommandGroup>
              {filtered.map((p) => {
                const disabled = isOptionDisabled?.(p) ?? false;
                return (
                  <CommandItem
                    key={p.id}
                    value={p.id}
                    disabled={disabled}
                    title={disabled ? disabledHint : undefined}
                    onSelect={() => {
                      if (disabled) return;
                      onSelect(p);
                      setOpen(false);
                      setQuery("");
                    }}
                  >
                    <Check className={cn("size-4", p.id === value ? "opacity-100" : "opacity-0")} />
                    <span className={cn(disabled && "text-muted-foreground")}>
                      {optionLabel(p)}
                    </span>
                  </CommandItem>
                );
              })}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
