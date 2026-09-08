import { useSyncExternalStore } from "react";

import type { Discount, HeldSale, PosLine, PosPayment, VatMode } from "@/data/pos";
import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

type HeldSaleRow = Database["public"]["Tables"]["held_sales"]["Row"];
type HeldSaleRowWithStaff = HeldSaleRow & { staff: { name: string } | null };

export type NewHeldSale = {
  customerId: string | null;
  customerName: string;
  lines: PosLine[];
  saleDiscount: Discount;
  vatMode: VatMode;
  payments: PosPayment[];
};

type State = {
  heldSales: HeldSale[];
  loading: boolean;
  error: string | null;
};

let state: State = { heldSales: [], loading: true, error: null };
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

// lines/payments are stored as plain jsonb, verbatim in PosLine[]/
// PosPayment[]'s own shape — see the migration's header comment for why —
// so there's no per-field remapping the way sale_lines/sale_payments (real
// relational tables) need; only the two real numeric/text columns
// (sale_discount_mode/value) need the usual PostgREST numeric-as-string
// coercion every other store already does.
function mapHeldSaleRow(row: HeldSaleRowWithStaff): HeldSale {
  return {
    id: row.id,
    customerId: row.customer_id,
    customerName: row.customer_name,
    lines: row.lines as unknown as PosLine[],
    saleDiscount: {
      mode: row.sale_discount_mode as Discount["mode"],
      value: Number(row.sale_discount_value),
    },
    vatMode: row.vat_mode as VatMode,
    payments: row.payments as unknown as PosPayment[],
    heldBy: row.staff?.name ?? "Unknown",
    heldAt: row.created_at,
  };
}

let loadPromise: Promise<void> | null = null;

async function loadHeldSales() {
  // Oldest-held first — the customer who's been waiting longest surfaces at
  // the top of the list, same reasoning a physical order-ticket rail would.
  const { data, error } = await supabase
    .from("held_sales")
    .select("*, staff(name)")
    .order("created_at", { ascending: true });
  if (error) throw error;
  setState({
    heldSales: (data as HeldSaleRowWithStaff[]).map(mapHeldSaleRow),
    loading: false,
    error: null,
  });
}

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = loadHeldSales().catch((err) => {
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

async function reload() {
  loadPromise = null;
  await ensureLoaded();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

const SERVER_SNAPSHOT: State = { heldSales: [], loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

/** Every held sale currently on record — shared across every staff member
 * signed in at the branch, not scoped to whoever created them (RLS's
 * held_sales_select is "any active staff", not held_by-scoped). No
 * polling — matches this codebase's "no realtime/polling anywhere"
 * convention; the list refreshes on hold/resume/discard and via a manual
 * reload for a busy till checking what a coworker parked. */
export function useHeldSales() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

export async function reloadHeldSales() {
  await reload();
}

async function getBranchId(): Promise<string> {
  // Every other store fetches its own branch_id for writes (see
  // getBranchId() in inventory-store.ts, pos-store.ts, etc.) rather than
  // sharing one across stores — same precedent, applied here.
  const { data, error } = await supabase.from("branches").select("id").limit(1).single();
  if (error) throw error;
  return data.id;
}

/** Plain insert — no RPC, no server-side numbering or total computation,
 * since a held sale is never itself an economic event to validate or
 * price. held_by is forced server-side by held_sales_set_held_by(), never
 * trusted from this payload. */
export async function holdSale(draft: NewHeldSale): Promise<void> {
  const branchId = await getBranchId();
  const { error } = await supabase.from("held_sales").insert({
    branch_id: branchId,
    customer_id: draft.customerId,
    customer_name: draft.customerName,
    lines: draft.lines as unknown as Database["public"]["Tables"]["held_sales"]["Insert"]["lines"],
    sale_discount_mode: draft.saleDiscount.mode,
    sale_discount_value: draft.saleDiscount.value,
    vat_mode: draft.vatMode,
    payments:
      draft.payments as unknown as Database["public"]["Tables"]["held_sales"]["Insert"]["payments"],
  });
  if (error) throw error;
  await reload();
}

/** Atomically removes a held sale and returns exactly what it held —
 * DELETE ... RETURNING via PostgREST rather than a dedicated RPC, since the
 * DELETE's own row-level locking already makes "only one caller can resume
 * a given held sale" atomic for free: two staff racing to resume the same
 * row will have exactly one succeed, the other seeing zero rows deleted
 * (surfaced here as a clear "no longer available" error, not a silent
 * no-op) rather than both loading the same draft into two separate carts. */
export async function resumeHeldSale(id: string): Promise<HeldSale> {
  const { data, error } = await supabase
    .from("held_sales")
    .delete()
    .eq("id", id)
    .select("*, staff(name)")
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    throw new Error(
      "This held sale is no longer available — it may have already been resumed or discarded.",
    );
  }
  await reload();
  return mapHeldSaleRow(data as HeldSaleRowWithStaff);
}

/** Abandons a held sale with no intent to resume it — a plain RLS-gated
 * delete, no dedicated RPC needed (no invariant beyond can_write() to
 * protect, same precedent as customer_discounts.active). */
export async function discardHeldSale(id: string): Promise<void> {
  const { error } = await supabase.from("held_sales").delete().eq("id", id);
  if (error) throw error;
  await reload();
}
