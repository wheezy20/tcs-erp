import { Plus, RefreshCcw } from "lucide-react";

import { ImportDialog, type ImportConfig, type RowCheck } from "@/components/import/import-dialog";
import {
  addProducts,
  updateProducts,
  type NewProduct,
  type ProductUpdate,
  useInventory,
} from "@/data/inventory-store";
import { useDocumentSettings } from "@/data/settings-store";
import { matchOption, toNumber } from "@/lib/import/parse";

const COLUMNS = [
  "name",
  "description",
  "size",
  "unit",
  "category",
  "cost price",
  "selling price",
  "quantity in stock",
  "low stock threshold",
];

const EXAMPLE = [
  "Matt Emulsion Paint — Off White",
  "Smooth matte finish, water-based, interior use",
  "20L bucket",
  "Litres",
  "Paint",
  "42",
  "68",
  "120",
  "30",
];

const slug = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

/** A row either creates a brand-new product or, when its name matches one
 * that already exists, updates that product instead — the re-import-a-
 * spreadsheet-of-found-cost-prices case. `name` is carried on both variants
 * purely so validate() can detect a duplicate name within the same file
 * regardless of which mode it resolved to. `existingName` (update only) is
 * the matched product's own stored name, kept distinct from the imported
 * row's `name` — matching is case/punctuation-insensitive, so the two can
 * legitimately differ, and the preview needs to show what was actually
 * matched, not just echo the file's own spelling back. */
type ProductImportRow =
  | { mode: "create"; name: string; product: NewProduct }
  | { mode: "update"; name: string; existingName: string; id: string; patch: ProductUpdate };

export function ImportProductsDialog() {
  const { products } = useInventory();
  // Settings' editable category/unit lists are the single source of truth
  // for what's valid — the same one the Inventory page's category filter
  // and the Add Product dialog already read from, not the static union in
  // data/inventory.ts (which only seeds Settings' defaults on first run and
  // has no way to see anything a Manager has since added there, like a new
  // "Security & Fencing" category).
  const { inventory } = useDocumentSettings();
  const CATEGORIES = inventory.categories;
  const UNITS = inventory.units;

  const config: ImportConfig<ProductImportRow> = {
    entity: "products",
    description:
      "Bring in your product list from a spreadsheet. A name that doesn't match an existing product creates a new one; a name that does match updates its description, size, cost, price, category, unit, and threshold instead — stock is never touched by import. Nothing is saved until you confirm, and rows with errors are never imported.",
    templateFile: "tcs-inventory-template.csv",
    columns: COLUMNS,
    exampleRow: EXAMPLE,
    // Which existing product a row matched to, and how many rows will
    // create vs. update, both surfaced in the preview — so an unexpected
    // match is visible before Import is clicked, not discovered after.
    matchColumn: {
      header: "Match",
      value: (row) =>
        row.mode === "update" ? (
          <span className="inline-flex items-center gap-1 font-medium text-[color:var(--warning-foreground)] dark:text-[color:var(--warning)]">
            <RefreshCcw className="size-3" /> Update “{row.existingName}”
          </span>
        ) : (
          <span className="inline-flex items-center gap-1 font-medium text-primary">
            <Plus className="size-3" /> New product
          </span>
        ),
    },
    summaryPills: (ready) => [
      {
        label: `${ready.filter((r) => r.mode === "create").length} will create`,
        tone: "success",
      },
      {
        label: `${ready.filter((r) => r.mode === "update").length} will update`,
        tone: "info",
      },
    ],
    validate: (row, accepted): RowCheck<ProductImportRow> => {
      const errors: string[] = [];
      const notes: string[] = [];

      const name = (row["name"] ?? "").trim();
      if (!name) errors.push("Name is required");

      // Optional on both create and update rows, matching the manual Add
      // Product dialog's own treatment of these two fields (also optional
      // there, with the same fallback text on create) — length-capped the
      // same way too, since this is the same data landing in the same
      // columns either way.
      const rawDescription = (row["description"] ?? "").trim();
      if (rawDescription.length > 400) errors.push("Description must be 400 characters or fewer");

      const rawSize = (row["size"] ?? "").trim();
      if (rawSize.length > 60) errors.push("Pack size must be 60 characters or fewer");

      const rawUnit = (row["unit"] ?? "").trim();
      const unit = matchOption(rawUnit, UNITS);
      if (!rawUnit) errors.push("Unit is required");
      else if (!unit) errors.push(`Unit “${rawUnit}” is not one of ${UNITS.join(", ")}`);
      else if (unit !== rawUnit) notes.push(`unit read as “${unit}”`);

      const rawCategory = (row["category"] ?? "").trim();
      const category = matchOption(rawCategory, CATEGORIES);
      if (!rawCategory) errors.push("Category is required");
      else if (!category)
        errors.push(`Category “${rawCategory}” is not one of ${CATEGORIES.join(", ")}`);
      else if (category !== rawCategory) notes.push(`category read as “${category}”`);

      const key = slug(name);
      const existing = key ? products.find((p) => slug(p.name) === key) : undefined;
      if (key && accepted.some((r) => slug(r.name) === key)) {
        errors.push("Duplicate of an earlier row in this file");
      }

      const numeric = (key: string, label: string, required = true) => {
        const raw = (row[key] ?? "").trim();
        if (!raw) {
          if (required) errors.push(`${label} is required`);
          return null;
        }
        const n = toNumber(raw);
        if (n === null) errors.push(`${label} “${raw}” is not a number`);
        else if (n < 0) errors.push(`${label} cannot be negative`);
        return n;
      };

      // Optional — a product can be created (or updated) with cost price
      // genuinely unknown rather than forced to a placeholder. Every
      // cost-derived figure downstream (margin, valuation, COGS postings)
      // flags this rather than silently treating it as 0.
      const cost = numeric("cost price", "Cost price", false);
      // Also optional, but with stronger downstream consequences than cost
      // — a product created (or left) with no selling price is
      // structurally blocked from being added to a POS sale or invoice
      // line (hasPrice() gates the picker client-side, create_sale()/
      // create_invoice()/update_invoice() reject it server-side) rather
      // than just flagged in a report the way a missing cost is.
      const price = numeric("selling price", "Selling price", false);
      // Optional on both create and update rows — blank on a create row is
      // a real, valid value (no stock on hand yet), not an error; blank on
      // an update row means "leave stock alone," same as before.
      const stock = numeric("quantity in stock", "Quantity in stock", false);
      const threshold = numeric("low stock threshold", "Low stock threshold", false);

      if (existing && (row["quantity in stock"] ?? "").trim()) {
        notes.push("quantity in stock ignored — stock isn't changed by import");
      }

      if (cost === null) {
        notes.push(
          existing
            ? "cost price blank — existing cost price left unchanged"
            : "cost price not provided — margin and valuation will flag this product as incomplete until it's set",
        );
      }

      if (price === null) {
        notes.push(
          existing
            ? "selling price blank — existing selling price left unchanged"
            : "selling price not provided — this product can't be sold or invoiced until one is set",
        );
      }

      // Same "blank on an update row means leave it as is, not clear it"
      // rule as cost/stock above — only relevant once there's an existing
      // value that could be silently wiped by a blank spreadsheet cell.
      if (existing && !rawDescription) {
        notes.push("description blank — existing description left unchanged");
      }
      if (existing && !rawSize) {
        notes.push("size blank — existing pack size left unchanged");
      }

      if (errors.length > 0) return { value: null, errors, notes };

      if (existing) {
        return {
          value: {
            mode: "update",
            name,
            existingName: existing.name,
            id: existing.id,
            // A blank cost/price/description/size cell on an update row
            // means "leave it as is," not "clear it" — ProductUpdate
            // treats an undefined key as untouched, same as the "quantity
            // in stock ignored" precedent just above for stock.
            patch: {
              category: category!,
              unit: unit!,
              cost: cost === null ? undefined : cost,
              price: price === null ? undefined : price,
              threshold,
              description: rawDescription || undefined,
              size: rawSize || undefined,
            },
          },
          errors: [],
          notes: [`will update existing product “${existing.name}”`, ...notes],
        };
      }

      return {
        value: {
          mode: "create",
          name,
          product: {
            name,
            // Same fallback text the manual Add Product dialog uses for a
            // blank description/size, so a product's provenance (typed by
            // hand vs. imported) can't be told apart from these two fields
            // alone.
            description: rawDescription || "No description added yet.",
            category: category!,
            unit: unit!,
            size: rawSize || "—",
            cost,
            price,
            // A blank stock cell on a create row is a real, valid value —
            // no stock on hand yet — not an error, so it defaults to 0
            // rather than being required.
            stock: stock ?? 0,
            threshold,
            openingStockReason: "Opening stock — bulk import",
          },
        },
        errors: [],
        notes,
      };
    },
    onImport: async (values) => {
      const creates = values
        .filter((v): v is Extract<ProductImportRow, { mode: "create" }> => v.mode === "create")
        .map((v) => v.product);
      const updates = values
        .filter((v): v is Extract<ProductImportRow, { mode: "update" }> => v.mode === "update")
        .map((v) => ({ id: v.id, patch: v.patch }));
      await Promise.all([addProducts(creates), updateProducts(updates)]);
    },
  };

  return <ImportDialog config={config} />;
}
