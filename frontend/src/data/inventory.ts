export type Unit =
  "Litres" | "Boxes" | "Pieces" | "Rolls" | "Bags" | "Metres" | "Sheets" | "Buckets";

export const UNITS: Unit[] = [
  "Litres",
  "Boxes",
  "Pieces",
  "Rolls",
  "Bags",
  "Metres",
  "Sheets",
  "Buckets",
];

export type Category = "Paint" | "Tiles" | "PVC Panels" | "Wallpaper" | "Adhesives" | "Hardware";

export const CATEGORIES: Category[] = [
  "Paint",
  "Tiles",
  "PVC Panels",
  "Wallpaper",
  "Adhesives",
  "Hardware",
];

export type StockMovement = {
  id: string;
  date: string;
  type: "Sale" | "Purchase" | "Adjustment" | "Return" | "Void";
  change: number;
  balance: number;
  reason: string;
  user: string;
};

export type Product = {
  id: string;
  sku: string;
  name: string;
  description: string;
  category: Category;
  unit: Unit;
  size: string;
  /** null means cost price hasn't been recorded yet — never treat as 0, see
   * `hasCost()` in inventory-store.ts for the pattern every cost-derived
   * calculation should follow. */
  cost: number | null;
  /** null means selling price hasn't been recorded yet — never treat as 0.
   * Unlike cost, this isn't just a reporting gap: `hasPrice()` (inventory-
   * store.ts) gates every add-to-cart/add-to-invoice-line path, and
   * create_sale()/create_invoice()/update_invoice() enforce the same rule
   * server-side, since a missing price defaulting to zero would mean
   * actually giving stock away for free. */
  price: number | null;
  stock: number;
  /** null means "use the global default threshold" */
  threshold: number | null;
  branch: string;
  history: StockMovement[];
};

export const DEFAULT_THRESHOLD = 20;
