import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

// The one real (Supabase-backed) piece of Settings' Notifications section —
// see CLAUDE.md's Data layer entry for Session 18: a third narrow exception
// to "Settings stays local", alongside vat_rate and expense_categories,
// because notify_low_stock()/notify_overdue_invoices()/
// notify_daily_sales_summary() (the Postgres triggers/functions that decide
// whether to actually fire a notification) need a trustworthy source for
// "is this alert type on" that a localStorage value could never be. Every
// other Settings section is untouched and still local.
export type NotificationSettings = {
  lowStockAlerts: boolean;
  overdueInvoiceAlerts: boolean;
  dailySalesSummary: boolean;
};

type State = {
  settings: NotificationSettings | null;
  loading: boolean;
  error: string | null;
};

let state: State = { settings: null, loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

async function load() {
  const { data, error } = await supabase
    .from("business_settings")
    .select("low_stock_alerts_enabled, overdue_invoice_alerts_enabled, daily_sales_summary_enabled")
    .eq("id", 1)
    .single();
  if (error) throw error;
  setState({
    settings: {
      lowStockAlerts: data.low_stock_alerts_enabled,
      overdueInvoiceAlerts: data.overdue_invoice_alerts_enabled,
      dailySalesSummary: data.daily_sales_summary_enabled,
    },
    loading: false,
    error: null,
  });
}

let loadPromise: Promise<void> | null = null;

function ensureLoaded() {
  if (!loadPromise) {
    loadPromise = load().catch((err) => {
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

const SERVER_SNAPSHOT: State = { settings: null, loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

export function useNotificationSettings() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

/** RLS's business_settings_update policy is Manager-only and is the real
 * boundary — the Settings UI just disables the switches for anyone else so
 * the request is never attempted, same relationship as setStaffRole(). */
export async function updateNotificationSettings(patch: Partial<NotificationSettings>) {
  const dbPatch: Database["public"]["Tables"]["business_settings"]["Update"] = {};
  if (patch.lowStockAlerts !== undefined) dbPatch.low_stock_alerts_enabled = patch.lowStockAlerts;
  if (patch.overdueInvoiceAlerts !== undefined)
    dbPatch.overdue_invoice_alerts_enabled = patch.overdueInvoiceAlerts;
  if (patch.dailySalesSummary !== undefined)
    dbPatch.daily_sales_summary_enabled = patch.dailySalesSummary;

  const { error } = await supabase.from("business_settings").update(dbPatch).eq("id", 1);
  if (error) throw error;
  await reload();
}
