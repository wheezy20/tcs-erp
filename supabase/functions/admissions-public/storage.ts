// The two Storage API calls the upload actions need (admissions slice 9a),
// with plain fetch and the service role key, so index.ts and the local
// integration test run exactly the same code. No Deno globals and no npm
// imports, like handler.ts.
//
//   signUpload  POST /object/upload/sign/<bucket>/<path> with no x-upsert
//               header, so the signed upload is overwrite-off: once a file
//               is at that path, a second upload is refused (KeyAlreadyExists),
//               whatever header the uploader sends. The token lasts 2 hours
//               (Storage's fixed lifetime) and is bound to that one path.
//   remove      DELETE /object/<bucket> with the paths as prefixes. A path
//               with no file is not an error.
//   readHead    GET /object/authenticated/<bucket>/<path> with a Range
//               header for the first n bytes (206), or the start of a full
//               body (200), reading no more than n bytes and cancelling the
//               rest. 5 second timeout. Used by the application byte check.
import type { StorageDeps } from "./handler.ts";

export const ADMISSIONS_BUCKET = "admissions-documents";
export const READ_HEAD_TIMEOUT_MS = 5000;

export function makeStorage(
  fetchImpl: typeof fetch,
  supabaseUrl: string,
  serviceRoleKey: string,
  bucket = ADMISSIONS_BUCKET,
): StorageDeps {
  const headers = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };
  return {
    signUpload: async (path) => {
      const res = await fetchImpl(
        `${supabaseUrl}/storage/v1/object/upload/sign/${bucket}/${path}`,
        { method: "POST", headers, body: "{}" },
      );
      if (!res.ok) throw new Error(`sign answered ${res.status}`);
      const body: unknown = await res.json();
      const b = (typeof body === "object" && body !== null ? body : {}) as {
        token?: unknown;
        url?: unknown;
      };
      // Older Storage versions return only the URL, with the token in it.
      const token =
        typeof b.token === "string"
          ? b.token
          : typeof b.url === "string"
            ? (new URL(b.url, "http://x").searchParams.get("token") ?? "")
            : "";
      if (token === "") throw new Error("sign returned no token");
      return { token };
    },
    remove: async (paths) => {
      const res = await fetchImpl(
        `${supabaseUrl}/storage/v1/object/${bucket}`,
        {
          method: "DELETE",
          headers,
          body: JSON.stringify({ prefixes: paths }),
        },
      );
      if (!res.ok) throw new Error(`remove answered ${res.status}`);
    },
    readHead: async (path, n) => {
      const res = await fetchImpl(
        `${supabaseUrl}/storage/v1/object/authenticated/${bucket}/${path}`,
        {
          method: "GET",
          headers: {
            apikey: serviceRoleKey,
            Authorization: `Bearer ${serviceRoleKey}`,
            Range: `bytes=0-${n - 1}`,
          },
          signal: AbortSignal.timeout(READ_HEAD_TIMEOUT_MS),
        },
      );
      if ((res.status !== 206 && res.status !== 200) || !res.body) {
        await res.body?.cancel().catch(() => {});
        throw new Error(`read answered ${res.status}`);
      }
      const reader = res.body.getReader();
      const out = new Uint8Array(n);
      let got = 0;
      while (got < n) {
        const { done, value } = await reader.read();
        if (done) break;
        const take = Math.min(value.byteLength, n - got);
        out.set(value.subarray(0, take), got);
        got += take;
      }
      await reader.cancel().catch(() => {});
      return out.subarray(0, got);
    },
  };
}
