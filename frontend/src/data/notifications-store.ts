import { useSyncExternalStore } from "react";

import { supabase } from "@/lib/supabase";
import type { Database } from "@/lib/database.types";

export type NotificationType =
  "stock_adjustment" | "low_stock" | "overdue_invoice" | "daily_summary";

export type AppNotification = {
  id: string;
  type: NotificationType;
  title: string;
  body: string;
  link: string | null;
  createdAt: string;
  readAt: string | null;
};

type NotificationRow = Database["public"]["Tables"]["notifications"]["Row"];

function mapRow(row: NotificationRow): AppNotification {
  return {
    id: row.id,
    type: row.type as NotificationType,
    title: row.title,
    body: row.body,
    link: row.link,
    createdAt: row.created_at,
    readAt: row.read_at,
  };
}

type State = {
  notifications: AppNotification[];
  loading: boolean;
  error: string | null;
};

let state: State = { notifications: [], loading: true, error: null };

const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  listeners.forEach((l) => l());
}

async function load() {
  const { data, error } = await supabase
    .from("notifications")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw error;
  setState({ notifications: data.map(mapRow), loading: false, error: null });
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

/** Forces the next ensureLoaded() (an explicit call, or the next component
 * to subscribe) to hit the database again rather than reuse the cache. */
export async function reloadNotifications() {
  loadPromise = null;
  await ensureLoaded();
}

// notifications are recipient-scoped by RLS (recipient_id = auth.uid()), so
// unlike branch-store.ts/staff-store.ts (whose data is the same for every
// signed-in user) this module-level cache would leak the previous user's
// inbox if an Attendant signed out and a Manager signed in within the same
// tab. Piggybacking on Supabase's own auth listener — the same mechanism
// auth-store.ts already uses — resets the cache on every session change
// rather than inventing a second cross-store coordination path.
let authListenerAttached = false;
let lastUserId: string | null | undefined = undefined;

function ensureAuthListener() {
  if (authListenerAttached) return;
  authListenerAttached = true;
  supabase.auth.onAuthStateChange((_event, session) => {
    const userId = session?.user.id ?? null;
    if (userId === lastUserId) return;
    lastUserId = userId;
    if (!userId) {
      setState({ notifications: [], loading: false, error: null });
      loadPromise = null;
      return;
    }
    reloadNotifications().catch(() => {
      /* surfaced via state.error, nothing more to do here */
    });
  });
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  ensureAuthListener();
  ensureLoaded();
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

const SERVER_SNAPSHOT: State = { notifications: [], loading: true, error: null };

function getServerSnapshot() {
  return SERVER_SNAPSHOT;
}

export function useNotifications() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

export async function markNotificationRead(id: string) {
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", id)
    .is("read_at", null);
  if (error) throw error;
  await reloadNotifications();
}

export async function markAllNotificationsRead() {
  const unreadIds = state.notifications.filter((n) => !n.readAt).map((n) => n.id);
  if (unreadIds.length === 0) return;
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .in("id", unreadIds);
  if (error) throw error;
  await reloadNotifications();
}
