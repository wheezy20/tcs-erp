import { useRef } from "react";
import { Search } from "lucide-react";

import { ProductThumb } from "@/components/inventory/product-thumb";
import { PriceMissingBadge } from "@/components/inventory/price-missing-badge";
import { matchesProductQuery } from "@/components/product-search-select";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { currency } from "@/data/dashboard";
import { type Product } from "@/data/inventory";
import { useDocumentSettings } from "@/data/settings-store";
import { effectiveThreshold, hasPrice } from "@/data/inventory-store";
import { cn } from "@/lib/utils";

/**
 * Search-first product picker for POS checkout.
 *
 * The full catalogue grid no longer renders on load — a cashier lands on a
 * single prominent search box and nothing else. Tiles appear only once
 * there's something to narrow by: a typed query, or a category selected
 * from the pills below the box (kept as a secondary "browse without typing"
 * path, not a replacement for search).
 *
 * Deliberately no "recent / frequently sold" default shortlist: that would
 * be a real feature (a ranking window over usePosSales(), its own
 * correctness surface) and this change is scoped to decluttering how a
 * product gets found, not adding one. The category pills already give a
 * one-tap browse path for a cashier who'd rather scan than type.
 *
 * Nothing about how a line gets added changes — a tap still calls
 * onSelect(product) → the same addProduct() path as before.
 */
export function ProductGrid({
  products,
  defaultThreshold,
  query,
  onQueryChange,
  category,
  onCategoryChange,
  onSelect,
}: {
  products: Product[];
  defaultThreshold: number;
  query: string;
  onQueryChange: (value: string) => void;
  category: string;
  onCategoryChange: (value: string) => void;
  onSelect: (product: Product) => void;
}) {
  const docSettings = useDocumentSettings();
  const searchRef = useRef<HTMLInputElement>(null);
  // Same matcher (name / SKU / category / size, case-insensitive substring)
  // used by the invoice/PO product combobox and the topbar search.
  const filtered = products.filter(
    (p) => matchesProductQuery(p, query) && (category === "all" || p.category === category),
  );
  // Show results once the cashier has given us something to narrow by.
  const browsing = query.trim() !== "" || category !== "all";

  function pick(product: Product) {
    onSelect(product);
    // Drop the query + its results so the panel goes back to the prompt,
    // then hand the cursor straight back to the box for the next item. The
    // refocus isn't optional: a mouse click just moved focus onto this
    // tile, which is about to unmount. The category pill is a deliberate
    // persistent filter and is left untouched.
    onQueryChange("");
    searchRef.current?.focus();
  }

  return (
    <div className="flex min-w-0 flex-col gap-4">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3.5 top-1/2 size-[18px] -translate-y-1/2 text-muted-foreground" />
        <Input
          ref={searchRef}
          value={query}
          onChange={(e) => onQueryChange(e.target.value)}
          placeholder="Search products by name, SKU, category or size…"
          className="h-12 pl-11 text-base"
          aria-label="Search products"
          autoFocus
        />
      </div>

      <div className="flex flex-wrap gap-2">
        {["all", ...docSettings.inventory.categories].map((c) => (
          <button
            key={c}
            type="button"
            onClick={() => onCategoryChange(c)}
            className={cn(
              "rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              category === c
                ? "border-primary bg-primary text-primary-foreground"
                : "border-border bg-card text-muted-foreground hover:text-foreground",
            )}
          >
            {c === "all" ? "All products" : c}
          </button>
        ))}
      </div>

      {!browsing ? (
        <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-border px-6 py-16 text-center">
          <div className="flex size-11 items-center justify-center rounded-2xl bg-muted">
            <Search className="size-5 text-muted-foreground" />
          </div>
          <p className="text-sm font-medium">Search for a product to add it</p>
          <p className="max-w-xs text-sm text-muted-foreground">
            Start typing a name, SKU, category or size — or pick a category above to browse.
          </p>
        </div>
      ) : filtered.length === 0 ? (
        <p className="rounded-2xl border border-dashed border-border py-12 text-center text-sm text-muted-foreground">
          No products match this search.
        </p>
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            {filtered.length} {filtered.length === 1 ? "product" : "products"}
            {category !== "all" ? ` in ${category}` : ""}
          </p>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-4">
            {filtered.map((product) => {
              const out = product.stock <= 0;
              const low = !out && product.stock <= effectiveThreshold(product, defaultThreshold);
              const noPrice = !hasPrice(product);
              return (
                <button
                  key={product.id}
                  type="button"
                  disabled={out || noPrice}
                  onClick={() => pick(product)}
                  title={
                    noPrice ? "No selling price set — can't be sold until one is added" : undefined
                  }
                  className={cn(
                    "card-surface flex flex-col gap-3 p-3 text-left transition-all",
                    out || noPrice
                      ? "cursor-not-allowed opacity-55"
                      : "hover:-translate-y-0.5 hover:border-primary/50 hover:shadow-lg",
                  )}
                >
                  <div className="flex items-start justify-between gap-2">
                    <ProductThumb category={product.category} className="size-12" />
                    {low && (
                      <Badge
                        variant="outline"
                        className="border-amber-500/40 text-amber-600 dark:text-amber-400"
                      >
                        Low
                      </Badge>
                    )}
                    {out && <Badge variant="outline">Out</Badge>}
                  </div>
                  <div className="min-w-0">
                    <p className="line-clamp-2 text-sm font-medium leading-snug">{product.name}</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {product.stock} {product.unit.toLowerCase()} in stock
                    </p>
                  </div>
                  {noPrice ? (
                    <PriceMissingBadge className="mt-auto" />
                  ) : (
                    <p className="mt-auto text-base font-semibold">{currency(product.price)}</p>
                  )}
                </button>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
