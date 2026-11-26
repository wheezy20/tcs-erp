// Host routing for the admissions host (admissions slice 15 A; D-15b,
// D-15g, D-15h, D-15i, D-15j). Pure: no database, no Supabase, no env.
// frontend/src/server.ts calls routeAdmissionsHost() before TanStack Start.
//
// It acts only when the request's hostname is one of PUBLIC_HOSTS. Until
// the admissions host is attached to this Worker at cutover, no request
// arrives with that hostname, so deploying this changes nothing. On the
// workers.dev staff host (and localhost) it always returns null, and the
// app behaves exactly as before.
//
// Static assets (dist/client: hashed JS and CSS, fonts, logos, favicons,
// robots.txt) are served by Cloudflare before the Worker runs, on every
// host, so they never reach this function.
//
// Every response here is a fixed page: no token, path or query is echoed,
// and nothing is read or written anywhere.

import { ADMISSIONS_HOST_COPY as COPY } from "@/modules/admissions/public-copy";

/** The public admissions host (D-15j: constants, not env). */
export const ADMISSIONS_HOST = "admissions.tcsch.edu.gh";

/** The rehearsal host (D-15i): attached to the Worker by Eyram for a short
 * hosted check before cutover, then detached. Remove this constant and its
 * entry in PUBLIC_HOSTS in the next deploy after the rehearsal. */
export const REHEARSAL_HOST = "admissions-preview.tcsch.edu.gh";

/** The staff app's origin (D-15e: workers.dev until after cutover). */
export const STAFF_ORIGIN = "https://tcs-erp.weyramkodzo.workers.dev";

const PUBLIC_HOSTS: ReadonlySet<string> = new Set([ADMISSIONS_HOST, REHEARSAL_HOST]);

/** The public pages, at TCS OS's paths (no trailing slash there). */
const PUBLIC_PAGES: ReadonlySet<string> = new Set(["/inquiry", "/apply", "/offer", "/privacy"]);

/** TCS OS's old unsubscribe path (D-15h). */
const LEGACY_UNSUBSCRIBE = /^\/api\/admissions\/unsubscribe\/[^/]+\/?$/;

/** TCS OS paths that answer 410 Gone: its whole API and its HR and finance
 * paths. */
const GONE = /^\/(?:api|hr|finance)(?:\/|$)/;

/** The hostname as the routing rules compare it: lower case (URL already
 * does that), with no port (URL drops it) and no trailing dot. */
export function requestHost(url: URL): string {
  return url.hostname.replace(/\.$/, "");
}

export function isPublicHost(url: URL): boolean {
  return PUBLIC_HOSTS.has(requestHost(url));
}

/** Null means "not handled here": TanStack Start serves the request. */
export function routeAdmissionsHost(request: Request): Response | null {
  const url = new URL(request.url);
  if (!isPublicHost(url)) return null;

  const method = request.method.toUpperCase();
  const read = method === "GET" || method === "HEAD";
  const path = url.pathname;
  const page = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;

  if (PUBLIC_PAGES.has(page)) {
    if (read) return null;
    return htmlResponse(405, method, COPY.unsupportedTitle, COPY.unsupportedBody, {
      allow: "GET, HEAD",
    });
  }

  if (path === "/") return redirect("/inquiry");

  if (path === "/admin" || path.startsWith("/admin/")) {
    return redirect(`${STAFF_ORIGIN}/admissions`);
  }

  if (LEGACY_UNSUBSCRIBE.test(path)) {
    // GET shows how to stop emails. A one-click POST (RFC 8058) gets 410:
    // the ERP can't map a TCS OS token, so it never claims an unsubscribe
    // that did not happen (D-15h).
    if (read) {
      return htmlResponse(200, method, COPY.unsubscribeTitle, COPY.unsubscribeBody, {
        "referrer-policy": "no-referrer",
      });
    }
    return htmlResponse(410, method, COPY.goneTitle, COPY.goneBody);
  }

  if (GONE.test(path)) return htmlResponse(410, method, COPY.goneTitle, COPY.goneBody);

  // Everything else, including every staff path (D-15g: 404, so the public
  // host never points at the staff app).
  return htmlResponse(404, method, COPY.notFoundTitle, COPY.notFoundBody);
}

const COMMON_HEADERS: Record<string, string> = {
  "cache-control": "no-store",
  "x-robots-tag": "noindex",
  "x-content-type-options": "nosniff",
};

function redirect(location: string): Response {
  return new Response(null, { status: 302, headers: { ...COMMON_HEADERS, location } });
}

function htmlResponse(
  status: number,
  method: string,
  title: string,
  paragraphs: readonly string[],
  extra: Record<string, string> = {},
): Response {
  return new Response(method === "HEAD" ? null : renderHostPage(title, paragraphs), {
    status,
    headers: {
      ...COMMON_HEADERS,
      "content-type": "text/html; charset=utf-8",
      "content-security-policy": "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'",
      ...extra,
    },
  });
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** A small fixed page in the TCS colours. Exported for tests. */
export function renderHostPage(title: string, paragraphs: readonly string[]): string {
  const body = paragraphs.map((p) => `      <p>${escapeHtml(p)}</p>`).join("\n");
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <title>${escapeHtml(title)} · TCS</title>
    <style>
      body { font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; background: #f3fafa; color: #1a2e2e; margin: 0; padding: 2rem 1rem; }
      main { max-width: 36rem; margin: 0 auto; background: #fff; border-radius: 0.75rem; padding: 2rem 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
      img { display: block; max-width: 220px; height: auto; margin: 0 auto 1.5rem; }
      h1 { font-size: 1.3rem; color: #005e61; margin: 0 0 1rem; }
      p { margin: 0 0 1rem; }
      a { color: #005e61; }
    </style>
  </head>
  <body>
    <main>
      <img src="/full-logo-transparent.png" alt="Treasures Christian School" />
      <h1>${escapeHtml(title)}</h1>
${body}
      <p><a href="/inquiry">${escapeHtml(COPY.enquiryLink)}</a></p>
    </main>
  </body>
</html>`;
}
