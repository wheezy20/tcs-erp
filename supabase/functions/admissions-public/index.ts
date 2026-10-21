// admissions-public entry point (admissions slice 8). All logic is in
// handler.ts; this file only wires the real pieces:
//
//   - secrets, read once per request from the function's environment:
//       TURNSTILE_SECRET_KEY        Cloudflare Turnstile secret for the ERP widget
//       IP_HASH_KEY                 HMAC key for per-IP rate limit keys (32+ chars)
//       ADMISSIONS_ALLOWED_ORIGINS  comma-separated exact origins
//       ADMISSIONS_LEAD_ORIGINS     the marketing site's exact origins, which may
//                                   call only pdf_gate (slice 13; optional:
//                                   unset refuses pdf_gate)
//     Set with `supabase secrets set` on hosted; locally from the gitignored
//     supabase/functions/.env. None of them is logged or returned.
//   - SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, injected by Supabase into
//     every Edge Function. The service role key stays here; the browser
//     calls this function with no key of its own beyond the public one.
//   - fetch for Turnstile's siteverify, with a timeout.
//   - Storage for the upload actions (slice 9a), from storage.ts: signing
//     one overwrite-off upload to an exact path in the private
//     admissions-documents bucket, and deleting swept files. Both use the
//     service role, which bypasses the bucket's lack of a write policy.
//   - EdgeRuntime.waitUntil, so the upload sweep runs after the response.
//
// verify_jwt = false (supabase/config.toml): visitors aren't signed in.
import { createClient } from "npm:@supabase/supabase-js@2";

import {
  handle,
  loadConfig,
  makeTurnstileVerifier,
  type RpcResult,
} from "./handler.ts";
import { makeStorage } from "./storage.ts";

const verifyTurnstile = makeTurnstileVerifier(fetch);

declare const EdgeRuntime:
  { waitUntil: (work: Promise<unknown>) => void } | undefined;

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const config =
    supabaseUrl && serviceRoleKey ? loadConfig((n) => Deno.env.get(n)) : null;

  const admin =
    config && supabaseUrl && serviceRoleKey
      ? createClient(supabaseUrl, serviceRoleKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        })
      : null;

  return handle(req, {
    config: admin ? config : null,
    verifyTurnstile,
    rpc: async (fn, args): Promise<RpcResult> => {
      const { data, error } = await admin!.rpc(fn, args);
      return {
        data,
        error: error
          ? { code: error.code, message: error.message, details: error.details }
          : null,
      };
    },
    log: (outcome) =>
      console.log(JSON.stringify({ fn: "admissions-public", outcome })),
    storage:
      supabaseUrl && serviceRoleKey
        ? makeStorage(fetch, supabaseUrl, serviceRoleKey)
        : undefined,
    defer: (work) => {
      if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
      else void work;
    },
  });
});
