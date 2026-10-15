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
import type { StorageDeps } from "./handler.ts";

export const ADMISSIONS_BUCKET = "admissions-documents";

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
  };
}
