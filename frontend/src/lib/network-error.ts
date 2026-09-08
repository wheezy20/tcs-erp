/** True when `error` is a genuine network-level failure — the request never
 * reached the server at all (offline, DNS failure, connection reset, a
 * flaky connection dropping mid-request) — as opposed to a real response
 * *from* the server (a validation error, a business-rule rejection, an RLS
 * denial, an insufficient-stock raise). Getting this wrong in the "network
 * error" direction is the worse failure mode — it would hide a real
 * rejection behind a misleading "check your connection" message — so both
 * signals below have to agree, not just one.
 *
 * supabase-js's default (non-`throwOnError`) path resolves a fetch-level
 * failure to an error object shaped like a real PostgrestError
 * (`message`/`details`/`hint`/`code`) but with `code` left as an empty
 * string — confirmed by reading `@supabase/postgrest-js`'s own `.catch()`
 * handler in `PostgrestBuilder.then()`, which is what every mutator in this
 * codebase hits via the shared `if (error) throw error` pattern. A genuine
 * Postgres/PostgREST error always carries a real SQLSTATE-derived code
 * (`"23505"` a unique violation, `"P0001"` a plain `raise exception`,
 * `"42501"` an RLS denial, ...) — `code` being empty is never legitimate,
 * so it's the structural signal; the message pattern is belt-and-braces
 * for the common wordings across browsers ("Failed to fetch" in Chromium,
 * "NetworkError when attempting to fetch resource" in Firefox, "Load
 * failed" in Safari). */
export function isNetworkError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const code = "code" in error ? String((error as { code?: unknown }).code ?? "") : "";
  if (code !== "") return false;
  const message =
    "message" in error && typeof (error as { message?: unknown }).message === "string"
      ? (error as { message: string }).message
      : "";
  return /fetch|networkerror|network request failed|load failed|network connection|err_internet_disconnected|err_network|err_connection/i.test(
    message,
  );
}
