// admissions-worker entry point (admissions slice 12). All logic is in
// handler.ts; this file only wires the real pieces:
//
//   - SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, injected by Supabase into
//     every Edge Function, for the worker RPCs and the Storage API.
//   - The mail configuration, read once per request from the function's
//     secrets (see loadMailConfig in handler.ts): MAIL_MODE, RESEND_API_KEY,
//     MAIL_FROM, MAIL_REPLY_TO, ADMISSIONS_STAFF_EMAIL, ERP_BASE_URL and
//     MAIL_DAILY_CEILING (plus RESEND_API_BASE in local test mode only).
//     Set on hosted with `supabase secrets set`; none is logged or returned.
//     MAIL_MODE unset means mail is off.
//   - fetch for Resend, with a timeout, and Storage for the sweep, reusing
//     admissions-public's storage.ts.
//
// verify_jwt = false (supabase/config.toml): pg_net calls it with the
// worker secret header instead of a JWT; handler.ts checks that header
// before doing anything.
import { createClient } from "npm:@supabase/supabase-js@2";

import { makeStorage } from "../admissions-public/storage.ts";
import {
  handle,
  loadMailConfig,
  mailRequested,
  makeResendSender,
  type RpcResult,
} from "./handler.ts";

const send = makeResendSender(fetch);

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "unavailable" }), {
      status: 503,
    });
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const mail = loadMailConfig((n) => Deno.env.get(n));
  return handle(req, {
    rpc: async (fn, args): Promise<RpcResult> => {
      const { data, error } = await admin.rpc(fn, args);
      return {
        data,
        error: error
          ? { code: error.code, message: error.message, details: error.details }
          : null,
      };
    },
    mail,
    mailMisconfigured: mail === null && mailRequested((n) => Deno.env.get(n)),
    send,
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    log: (outcome) =>
      console.log(JSON.stringify({ fn: "admissions-worker", outcome })),
    storage: makeStorage(fetch, supabaseUrl, serviceRoleKey),
  });
});
