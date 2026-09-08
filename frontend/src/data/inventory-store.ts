import { useSyncExternalStore } from "react";

import {
  DEFAULT_THRESHOLD,
  type Category,
  type Product,
  type StockMovement,
  type Unit,
} from "@/data/inventory";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

type ProductRow = Database["public"]["Tables"]["products"]["Row"];
type StockMovementRow = Database["public"]["Tables"]["stock_movements"]["Row"];
type BranchRow = Database["public"]["Tables"]["branches"]["Row"];
type StockMovementWithStaff = StockMovementRow & { staff: { name: string } | null };
type ProductWithRelations = ProductRow & {
  branches: Pick<BranchRow, "name"> | null;
  stock_movements: StockMovementWithStaff[];
};

export type NewProduct = {
  name: string;
  description: string;
  category: string;
  unit: string;
  size: string;
  cost: number | null;
  price: number | null;
  stock: number;
  threshold: number | null;
  /** shown on the opening stock-movement row created alongside the product */
  openingStockReason?: string;
};

type InventoryState = {
  products: Product[];
  defaultThreshold: number;
  branchId: string | null;
  loading: boolean;
  error: string | null;
  /** Epoch ms of the last successful load — set only on success, so a
   * failed background refresh (a flaky connection, checked mid-lookup)
   * never resets it. This is what lets a "Synced X ago" label stay honest:
   * the products shown are always exactly as of this timestamp, never
   * silently newer or older than it claims. Never read at the point a real
   * transaction is decided (POS checkout, invoice creation) — those go
   * through create_sale()/create_invoice(), which re-check stock/price/
   * cost live, server-side, every time, regardless of what this cache
   * shows on screen. */
  lastSyncedAt: number | null;
};

let state: InventoryState = {
  products: [],
  defaultThreshold: DEFAULT_THRESHOLD,
  branchId: null,
  loading: true,
  error: null,
  lastSyncedAt: null,
};

const listeners = new Set<() => void>();

function setState(next: InventoryState) {
  state = next;
  listeners.forEach((l) => l());
}

function mapMovementRow(row: StockMovementWithStaff): StockMovement {
  return {
    id: row.id,
    date: row.occurred_at,
    type: row.movement_type as StockMovement["type"],
    change: row.change,
    balance: row.balance_after,
    reason: row.reason,
    user: row.staff?.name ?? "Unknown",
  };
}

function mapProductRow(row: ProductWithRelations): Product {
  return {
    id: row.id,
    sku: row.sku,
    name: row.name,
    description: row.description,
    category: row.category as Category,
    unit: row.unit as Unit,
    size: row.size,
    cost: row.cost === null ? null : Number(row.cost),
    price: row.price === null ? null : Number(row.price),
    stock: row.stock,
    threshold: row.low_stock_threshold,
    branch: row.branches?.name ?? "",
    history: [...row.stock_movements]
      .sort((a, b) => b.occurred_at.localeCompare(a.occurred_at))
      .map(mapMovementRow),
  };
}

/** Vends p_count structurally-unique SKUs from a real Postgres sequence
 * (product_sku_seq) in one round trip — the same "nextval() is already
 * atomic under concurrency" pattern this app already uses for invoice/sale/
 * journal-entry/expense numbering. Replaces a prior client-side
 * `Math.random()` 4-digit code, which had only 9000 possible values and
 * collided for real on a 590-row import — the birthday paradox makes that
 * near-certain at that volume, not just unlucky. */
async function nextProductSkus(prefix: string, count: number): Promise<string[]> {
  const { data, error } = await supabase.rpc("next_product_skus", {
    p_prefix: prefix,
    p_count: count,
  });
  if (error) throw error;
  return data as string[];
}

let loadPromise: Promise<void> | null = null;

async function loadInventory() {
  const [branchResult, productsResult] = await Promise.all([
    supabase.from("branches").select("*").limit(1).single(),
    supabase
      .from("products")
      .select("*, branches(name), stock_movements(*, staff(name))")
      .order("name"),
  ]);

  if (branchResult.error) throw branchResult.error;
  if (productsResult.error) throw productsResult.error;

  setState({
    products: (productsResult.data as ProductWithRelations[]).map(mapProductRow),
    defaultThreshold: branchResult.data.default_low_stock_threshold,
    branchId: branchResult.data.id,
    loading: false,
    error: null,
    lastSyncedAt: Date.now(),
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadInventory().catch((err) => {
      loadPromise = null;
      setState({
        ...state,
        loading: false,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    });
  }
  return loadPromise;
}

/** Forces the next mutator to refetch even if inventory was already loaded once. */
async function reload() {
  loadPromise = null;
  await ensureLoaded();
}

/** Exported so a manual "Refresh" action (SyncStatus) can trigger the same
 * real reload a mutator would — same failure behavior too: a failed
 * refresh attempt (network still down) leaves `products`/`lastSyncedAt`
 * exactly as they were, per loadInventory()'s success-only write. Matches
 * `invoice-store.ts`'s own `reloadInvoices()` precedent — a thin,
 * domain-named wrapper around the module's internal `reload()`, not a bare
 * exported `reload` that could collide with another store's own. */
export async function reloadInventory() {
  await reload();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

export function useInventory() {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

async function getBranchId(): Promise<string> {
  await ensureLoaded();
  if (!state.branchId) throw new Error("No branch is configured yet.");
  return state.branchId;
}

export async function setDefaultThreshold(value: number) {
  const branchId = await getBranchId();
  const { error } = await supabase
    .from("branches")
    .update({ default_low_stock_threshold: value })
    .eq("id", branchId);
  if (error) throw error;
  await reload();
}

export async function addProduct(input: NewProduct) {
  const branchId = await getBranchId();
  const [sku] = await nextProductSkus("NEW", 1);

  const { data: inserted, error } = await supabase
    .from("products")
    .insert({
      branch_id: branchId,
      sku,
      name: input.name,
      description: input.description,
      category: input.category,
      unit: input.unit,
      size: input.size,
      cost: input.cost,
      price: input.price,
      stock: input.stock,
      low_stock_threshold: input.threshold,
    })
    .select()
    .single();
  if (error) throw error;

  const { error: movementError } = await supabase.from("stock_movements").insert({
    product_id: inserted.id,
    branch_id: branchId,
    movement_type: "Adjustment",
    change: input.stock,
    balance_after: input.stock,
    reason: input.openingStockReason ?? "Opening stock on product creation",
  });
  if (movementError) throw movementError;

  await reload();
}

/** Bulk variant for the spreadsheet import flow — one reload instead of one per row. */
export async function addProducts(inputs: NewProduct[]) {
  if (inputs.length === 0) return;
  const branchId = await getBranchId();
  const skus = await nextProductSkus("IMP", inputs.length);

  const { data: inserted, error } = await supabase
    .from("products")
    .insert(
      inputs.map((input, i) => ({
        branch_id: branchId,
        sku: skus[i],
        name: input.name,
        description: input.description,
        category: input.category,
        unit: input.unit,
        size: input.size,
        cost: input.cost,
        price: input.price,
        stock: input.stock,
        low_stock_threshold: input.threshold,
      })),
    )
    .select();
  if (error) throw error;

  const { error: movementError } = await supabase.from("stock_movements").insert(
    inserted.map((row, i) => ({
      product_id: row.id,
      branch_id: branchId,
      movement_type: "Adjustment" as const,
      change: inputs[i].stock,
      balance_after: inputs[i].stock,
      reason: inputs[i].openingStockReason ?? "Opening stock — bulk import",
    })),
  );
  if (movementError) throw movementError;

  await reload();
}

export type ProductUpdate = {
  // Deliberately excluded from every import row's patch (import matches an
  // existing product by name, so the field it matched on can't also be the
  // field it rewrites) but not from ProductUpdate itself — the Edit Product
  // screen is a direct, name-independent edit (keyed by product id, not by
  // name), so it has no equivalent match-key conflict and is the one caller
  // allowed to set this. import-products-dialog.tsx must keep never putting
  // `name` in the patches it builds; nothing about this type change enforces
  // that for it — it's convention, the same way it always was before name
  // existed on this type at all.
  name?: string;
  category?: string;
  unit?: string;
  cost?: number | null;
  price?: number | null;
  threshold?: number | null;
  description?: string;
  size?: string;
};

function updatePayload(patch: ProductUpdate) {
  // Keys left undefined are dropped by JSON.stringify, so a caller can send
  // a partial patch and only the fields it actually sets get touched.
  // stock is deliberately not settable here at all: it has its own
  // dedicated, audit-trailed path (adjustStock()'s logged stock_movements
  // trail) that no patch may bypass. sku is likewise never settable — it's
  // system-generated (next_product_skus()) and must stay that way now that
  // it's genuinely unique, not something any edit path can override.
  return {
    name: patch.name,
    category: patch.category,
    unit: patch.unit,
    cost: patch.cost,
    price: patch.price,
    low_stock_threshold: patch.threshold,
    description: patch.description,
    size: patch.size,
  };
}

export async function updateProduct(id: string, patch: ProductUpdate) {
  const { error } = await supabase.from("products").update(updatePayload(patch)).eq("id", id);
  if (error) throw error;
  await reload();
}

/** Bulk variant for the spreadsheet import flow — one reload instead of one
 * per row. PostgREST has no multi-row "different values per row" update, so
 * this is still one request per row, just run concurrently with a shared
 * reload at the end. */
export async function updateProducts(updates: { id: string; patch: ProductUpdate }[]) {
  if (updates.length === 0) return;
  const results = await Promise.all(
    updates.map(({ id, patch }) =>
      supabase.from("products").update(updatePayload(patch)).eq("id", id),
    ),
  );
  const failed = results.find((r) => r.error);
  if (failed?.error) throw failed.error;
  await reload();
}

export async function setProductThreshold(id: string, threshold: number | null) {
  const { error } = await supabase
    .from("products")
    .update({ low_stock_threshold: threshold })
    .eq("id", id);
  if (error) throw error;
  await reload();
}

export async function adjustStock(id: string, newQuantity: number, reason: string) {
  const { error } = await supabase.rpc("adjust_product_stock", {
    p_product_id: id,
    p_new_stock: newQuantity,
    p_reason: reason,
  });
  if (error) throw error;
  await reload();
}

/** Manager-only, enforced server-side by delete_product() — the only way a
 * product can ever be removed. Blocks (with a specific reason) if the
 * product has any stock movements, sale lines, invoice lines, purchase
 * order lines, or return/exchange records against it, so a hard delete can
 * never silently orphan real transaction history. */
export async function deleteProduct(id: string) {
  const { error } = await supabase.rpc("delete_product", { p_id: id });
  if (error) throw error;
  await reload();
}

/** false means cost price was never recorded for this product — every
 * cost-derived figure (margin, valuation, COGS) is incomplete until it's
 * set. Never substitute 0 for a missing cost; check this first instead. A
 * type guard (not just a boolean check) so callers get `cost: number`
 * narrowed automatically rather than needing their own `!`/`??`. */
export function hasCost<T extends Pick<Product, "cost">>(
  product: T,
): product is T & { cost: number } {
  return product.cost !== null;
}

/** false means no selling price was ever recorded for this product. Unlike
 * `hasCost()`, this isn't just a reporting concern — every add-to-cart/
 * add-to-invoice-line path must check this before letting a product be
 * added at all, since a missing price defaulting to 0 would mean actually
 * giving stock away for free. The real, unbypassable enforcement is
 * server-side (create_sale()/create_invoice()/update_invoice() all reject
 * a line referencing an unpriced product); this is the client-side check
 * so the block is visible immediately, not just after a failed request. */
export function hasPrice<T extends Pick<Product, "price">>(
  product: T,
): product is T & { price: number } {
  return product.price !== null;
}

export type StockStatus = "In stock" | "Low stock" | "Out of stock";

export function effectiveThreshold(product: Product, defaultThreshold: number) {
  return product.threshold ?? defaultThreshold;
}

export function stockStatus(product: Product, defaultThreshold: number): StockStatus {
  if (product.stock <= 0) return "Out of stock";
  if (product.stock <= effectiveThreshold(product, defaultThreshold)) return "Low stock";
  return "In stock";
}
