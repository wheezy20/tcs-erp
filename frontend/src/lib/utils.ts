import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Extracts a human-readable message from a caught error, falling back to
 * `fallback` only when the error truly has nothing usable. Deliberately not
 * `error instanceof Error ? error.message : fallback` — supabase-js's
 * PostgrestBuilder only wraps a failed request in `new PostgrestError(...)`
 * when `.throwOnError()` is used; the default `{ data, error }` return path
 * (what every `*-store.ts` mutator in this codebase uses) instead sets
 * `error` from a bare `JSON.parse(body)`, a plain object with the same
 * `message`/`details`/`hint`/`code` shape but no `Error` in its prototype
 * chain. `instanceof Error` is false for it, so every "friendly" backend
 * error message this app raises (create_account's "already in use",
 * create_sale's "Insufficient stock for %", close_day's "already closed",
 * ...) was silently replaced by the generic fallback string in every toast
 * — confirmed live via a real duplicate-account-code attempt in the
 * browser, network tab showing the correct message, toast showing the
 * fallback instead. */
export function getErrorMessage(error: unknown, fallback: string): string {
  if (
    error &&
    typeof error === "object" &&
    "message" in error &&
    typeof error.message === "string" &&
    error.message.trim() !== ""
  ) {
    return error.message;
  }
  return fallback;
}
