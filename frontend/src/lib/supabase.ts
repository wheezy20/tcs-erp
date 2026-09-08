import { createClient } from "@supabase/supabase-js";

import type { Database } from "@/lib/database.types";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY. Copy the values from `npx supabase status` into frontend/.env.local.",
  );
}

// supabase-js always constructs a realtime client, even though nothing here
// opens a channel, and that constructor throws immediately on Node < 22
// (no native WebSocket global) unless a transport is supplied. `SSR` keeps
// the `ws` import out of the browser bundle entirely.
const transport =
  import.meta.env.SSR && typeof WebSocket === "undefined"
    ? ((await import("ws")).default as unknown as typeof WebSocket)
    : undefined;

export const supabase = createClient<Database>(url, anonKey, {
  realtime: { transport },
});
