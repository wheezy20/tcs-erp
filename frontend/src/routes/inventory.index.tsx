import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { AlertTriangle, PackageSearch, Search } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { AddProductDialog } from "@/components/inventory/add-product-dialog";
import { ProductThumb } from "@/components/inventory/product-thumb";
import { StockBadge } from "@/components/inventory/stock-badge";
import { ThresholdSettings } from "@/components/inventory/threshold-settings";
import { ImportProductsDialog } from "@/components/inventory/import-products-dialog";
import { CostMissingBadge } from "@/components/inventory/cost-missing-badge";
import { PriceMissingBadge } from "@/components/inventory/price-missing-badge";
import { ExportMenu } from "@/components/export-menu";
import { SortableTh } from "@/components/sortable-th";
import { SyncStatus } from "@/components/sync-status";
import { useCurrentBranch } from "@/data/branch-store";
import { type Product } from "@/data/inventory";
import { useDocumentSettings } from "@/data/settings-store";
import {
  effectiveThreshold,
  hasCost,
  hasPrice,
  reloadInventory,
  stockStatus,
  useInventory,
} from "@/data/inventory-store";
import { currency } from "@/data/dashboard";
import { cn } from "@/lib/utils";
import { useSort } from "@/lib/use-sort";

type InventorySortKey = "name" | "cost" | "price" | "stock";

const inventorySortAccessors: Record<InventorySortKey, (p: Product) => string | number> = {
  name: (p) => p.name,
  // Missing cost/price sorts as the lowest possible value, so ascending
  // groups "not recorded" products first rather than scattering them
  // wherever a bare 0 would happen to land.
  cost: (p) => p.cost ?? -Infinity,
  price: (p) => p.price ?? -Infinity,
  stock: (p) => p.stock,
};

export const Route = createFileRoute("/inventory/")({
  head: () => ({
    meta: [
      { title: "Inventory — TCS" },
      {
        name: "description",
        content:
          "Track paint, tiles, PVC panels, wallpaper and hardware stock with low-stock thresholds and unit pricing.",
      },
      { property: "og:title", content: "Inventory — TCS" },
      {
        property: "og:description",
        content: "Products, units, cost and selling prices, stock levels and low-stock alerts.",
      },
    ],
  }),
  component: InventoryPage,
});

function InventoryPage() {
  const { products, defaultThreshold, lastSyncedAt } = useInventory();
  const { name: branchName } = useCurrentBranch();
  const settingsCategories = useDocumentSettings().inventory.categories;
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<string>("all");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return products.filter((p) => {
      const matchesQuery =
        !q ||
        p.name.toLowerCase().includes(q) ||
        p.sku.toLowerCase().includes(q) ||
        p.category.toLowerCase().includes(q) ||
        p.size.toLowerCase().includes(q);
      const matchesCategory = category === "all" || p.category === category;
      return matchesQuery && matchesCategory;
    });
  }, [products, query, category]);

  const { sortKey, sortDirection, toggleSort, sorted } = useSort<Product, InventorySortKey>(
    filtered,
    inventorySortAccessors,
  );

  const lowStock = products.filter((p) => stockStatus(p, defaultThreshold) !== "In stock");
  // Products missing a cost price are excluded from this total rather than
  // treated as costing 0 — silently including them would understate stock
  // value at cost. missingCostCount is what makes that exclusion visible
  // instead of just a quietly-smaller number.
  const stockValue = products.reduce((sum, p) => (hasCost(p) ? sum + p.cost * p.stock : sum), 0);
  const missingCostCount = products.filter((p) => !hasCost(p)).length;
  const overrideCount = products.filter((p) => p.threshold !== null).length;
  // "Unconfirmed" is a real, selectable unit (settings-store.ts's default
  // seed list), not a null state — this count is what keeps a product left
  // on it from quietly getting forgotten, the same role the cost/price
  // "missing" badges play for those two fields.
  const unconfirmedUnitCount = products.filter((p) => (p.unit as string) === "Unconfirmed").length;

  return (
    <>
      <PageHeader
        title="Inventory"
        description={`Products, units, pricing and stock levels at the ${branchName ?? "…"}.`}
        actions={
          <>
            <ThresholdSettings defaultThreshold={defaultThreshold} overrideCount={overrideCount} />
            <ExportMenu
              baseName="inventory"
              filters={[category !== "all" ? category : null, query]}
              summary={`${filtered.length} of ${products.length} products, as filtered`}
              disabled={filtered.length === 0}
              getSheets={() => [
                {
                  name: "Inventory",
                  // Column headers/order match import-products-dialog.tsx's
                  // template exactly (name, description, size, unit,
                  // category, cost price, selling price, quantity in
                  // stock, low stock threshold) — a round trip (export,
                  // edit prices/categories in a spreadsheet, re-import)
                  // has to work with zero manual reformatting, not just
                  // produce a human-readable report. cost price/selling
                  // price/low stock threshold export as a genuinely blank
                  // cell when unset (never a placeholder string like "Not
                  // recorded"), matching exactly what the import parser
                  // itself treats as "leave unchanged" on an update row —
                  // low stock threshold in particular exports the raw
                  // per-product override (null → blank), not
                  // effectiveThreshold()'s resolved value, since exporting
                  // the resolved number would silently convert every
                  // product still following the global default into an
                  // explicit override the moment the file is re-imported
                  // unedited. SKU/Status/Branch are kept as trailing,
                  // reference-only columns after the template's own nine —
                  // import already tolerates and ignores extra columns
                  // (a non-blocking "ignored extra column" pill), so they
                  // help a human editing the spreadsheet without breaking
                  // the round trip.
                  columns: [
                    { header: "name", value: (p: Product) => p.name },
                    { header: "description", value: (p: Product) => p.description },
                    { header: "size", value: (p: Product) => p.size },
                    { header: "unit", value: (p: Product) => p.unit },
                    { header: "category", value: (p: Product) => p.category },
                    { header: "cost price", value: (p: Product) => p.cost ?? "" },
                    { header: "selling price", value: (p: Product) => p.price ?? "" },
                    { header: "quantity in stock", value: (p: Product) => p.stock },
                    {
                      header: "low stock threshold",
                      value: (p: Product) => p.threshold ?? "",
                    },
                    { header: "SKU", value: (p: Product) => p.sku },
                    {
                      header: "Status",
                      value: (p: Product) => stockStatus(p, defaultThreshold),
                    },
                    { header: "Branch", value: (p: Product) => p.branch },
                  ],
                  rows: filtered,
                },
              ]}
            />
            <ImportProductsDialog />
            <AddProductDialog />
          </>
        }
      />

      <SyncStatus lastSyncedAt={lastSyncedAt} onRefresh={reloadInventory} className="-mt-3 mb-4" />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <SummaryCard
          label="Products tracked"
          value={String(products.length)}
          hint={`Across ${settingsCategories.length} categories`}
        />
        <SummaryCard
          label="Needs restocking"
          value={String(lowStock.length)}
          hint={`At or below threshold (default ${defaultThreshold})`}
          tone={lowStock.length > 0 ? "warning" : "default"}
        />
        <SummaryCard
          label="Stock value at cost"
          value={currency(stockValue)}
          hint={
            missingCostCount > 0
              ? `Excludes ${missingCostCount} product${missingCostCount === 1 ? "" : "s"} with no cost price recorded`
              : "Total on-hand valuation"
          }
          tone={missingCostCount > 0 ? "warning" : "default"}
        />
        <SummaryCard
          label="Unconfirmed units"
          value={String(unconfirmedUnitCount)}
          hint={
            unconfirmedUnitCount > 0
              ? "Products still using the placeholder unit — set a real one"
              : "No products left on the placeholder unit"
          }
          tone={unconfirmedUnitCount > 0 ? "warning" : "default"}
        />
      </div>

      {lowStock.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center gap-2 rounded-2xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm">
          <AlertTriangle className="size-4 text-amber-600 dark:text-amber-400" />
          <span className="font-medium text-amber-800 dark:text-amber-300">
            {lowStock.length} product{lowStock.length === 1 ? "" : "s"} need attention:
          </span>
          <span className="text-amber-800/80 dark:text-amber-300/80">
            {lowStock.map((p) => p.name).join(", ")}
          </span>
        </div>
      )}

      <div className="card-surface mt-6 overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-56 flex-1 sm:max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by product, SKU, category or size"
              className="h-10 rounded-xl pl-9"
              maxLength={80}
            />
          </div>
          <Select value={category} onValueChange={setCategory}>
            <SelectTrigger className="h-10 w-48 rounded-xl">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All categories</SelectItem>
              {settingsCategories.map((c) => (
                <SelectItem key={c} value={c}>
                  {c}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-6 py-16 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-muted">
              <PackageSearch className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No products match your filters</p>
            <p className="text-sm text-muted-foreground">Try another name, SKU or category.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <SortableTh<InventorySortKey>
                    label="Product"
                    sortKeyValue="name"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                  />
                  <th className="px-5 py-3 font-medium">Unit</th>
                  <th className="px-5 py-3 font-medium">Category</th>
                  <SortableTh<InventorySortKey>
                    label="Cost price"
                    sortKeyValue="cost"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                    align="right"
                  />
                  <SortableTh<InventorySortKey>
                    label="Selling price"
                    sortKeyValue="price"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                    align="right"
                  />
                  <SortableTh<InventorySortKey>
                    label="In stock"
                    sortKeyValue="stock"
                    activeKey={sortKey}
                    direction={sortDirection}
                    onSort={toggleSort}
                    align="right"
                  />
                  <th className="px-5 py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {sorted.map((p) => {
                  const status = stockStatus(p, defaultThreshold);
                  return (
                    <tr
                      key={p.id}
                      className={cn(
                        "group hover:bg-muted/40",
                        status !== "In stock" && "bg-amber-500/[0.06]",
                      )}
                    >
                      <td className="px-5 py-3">
                        <div className="flex items-center gap-3">
                          <ProductThumb category={p.category} />
                          <div className="min-w-0">
                            <Link
                              to="/inventory/$productId"
                              params={{ productId: p.id }}
                              className="font-medium group-hover:text-primary"
                            >
                              {p.name}
                            </Link>
                            <p className="text-xs text-muted-foreground">
                              {p.sku} · {p.branch}
                            </p>
                          </div>
                        </div>
                      </td>
                      <td className="px-5 py-3">
                        <span className="text-muted-foreground">{p.unit}</span>
                        <p className="text-xs text-muted-foreground/70">{p.size}</p>
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">{p.category}</td>
                      <td className="px-5 py-3 text-right tabular-nums text-muted-foreground">
                        {hasCost(p) ? currency(p.cost) : <CostMissingBadge />}
                      </td>
                      <td className="px-5 py-3 text-right font-medium tabular-nums">
                        {hasPrice(p) ? currency(p.price) : <PriceMissingBadge />}
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums">
                        {p.stock.toLocaleString("en-GH")}
                        <p className="text-xs text-muted-foreground">
                          min {effectiveThreshold(p, defaultThreshold)}
                          {p.threshold !== null ? " · custom" : ""}
                        </p>
                      </td>
                      <td className="px-5 py-3">
                        <StockBadge status={status} />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function SummaryCard({
  label,
  value,
  hint,
  tone = "default",
}: {
  label: string;
  value: string;
  hint: string;
  tone?: "default" | "warning";
}) {
  return (
    <div className="card-surface p-5">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p
        className={cn(
          "mt-2 text-2xl font-semibold tracking-tight",
          tone === "warning" && "text-amber-600 dark:text-amber-400",
        )}
      >
        {value}
      </p>
      <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
