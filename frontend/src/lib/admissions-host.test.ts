import { describe, expect, it } from "vitest";

import {
  ADMISSIONS_HOST,
  REHEARSAL_HOST,
  STAFF_ORIGIN,
  renderHostPage,
  routeAdmissionsHost,
} from "@/lib/admissions-host";
import {
  ADMISSIONS_HOST_COPY,
  PRIVACY_PAGE_COPY,
  PRIVACY_POLICY,
} from "@/modules/admissions/public-copy";

const TOKEN = "f3c1d2e4b5a69788aabbccddeeff00112233445566778899";

function req(host: string, path: string, method = "GET"): Request {
  return new Request(`https://${host}${path}`, { method });
}

function route(path: string, method = "GET", host = ADMISSIONS_HOST) {
  return routeAdmissionsHost(req(host, path, method));
}

const DASHES = /[\u2013\u2014]/;

describe("admissions host routing (slice 15 A)", () => {
  it("passes the public pages through, with or without a trailing slash and with a query", () => {
    for (const path of [
      "/inquiry",
      "/inquiry/",
      "/apply",
      "/apply/",
      "/apply?resume=abc",
      "/offer",
      "/offer/",
      "/privacy",
      "/privacy/",
    ]) {
      expect(route(path), path).toBeNull();
      expect(route(path, "HEAD"), path).toBeNull();
    }
  });

  it("refuses other methods on the public pages with 405", () => {
    for (const method of ["POST", "PUT", "DELETE", "PATCH"]) {
      const res = route("/apply", method)!;
      expect(res.status, method).toBe(405);
      expect(res.headers.get("allow")).toBe("GET, HEAD");
    }
  });

  it("does not treat look-alike paths as public pages", () => {
    for (const path of ["/inquiry/x", "/applyx", "/apply//", "/Offer", "/privacy.html"]) {
      expect(route(path)?.status, path).toBe(404);
    }
  });

  it("redirects / to /inquiry with no query carried", async () => {
    for (const path of ["/", "/?token=abc"]) {
      const res = route(path)!;
      expect(res.status).toBe(302);
      expect(res.headers.get("location")).toBe("/inquiry");
    }
  });

  it("redirects /admin and below to the staff host's admissions page", () => {
    for (const path of ["/admin", "/admin/", "/admin/admissions/application/5/change/?x=1"]) {
      const res = route(path)!;
      expect(res.status, path).toBe(302);
      expect(res.headers.get("location")).toBe(`${STAFF_ORIGIN}/admissions`);
    }
    expect(route("/administrator")?.status).toBe(404);
  });

  it("shows the static notice at the old unsubscribe path, and never echoes the token", async () => {
    for (const path of [
      `/api/admissions/unsubscribe/${TOKEN}/`,
      `/api/admissions/unsubscribe/${TOKEN}`,
    ]) {
      const res = route(path)!;
      expect(res.status, path).toBe(200);
      expect(res.headers.get("referrer-policy")).toBe("no-referrer");
      const body = await res.text();
      expect(body).not.toContain(TOKEN);
      for (const p of ADMISSIONS_HOST_COPY.unsubscribeBody) {
        expect(body).toContain(p);
      }
    }
    const head = route(`/api/admissions/unsubscribe/${TOKEN}/`, "HEAD")!;
    expect(head.status).toBe(200);
    expect(head.body).toBeNull();
  });

  it("answers a one-click unsubscribe POST with 410, never a fake success (D-15h)", async () => {
    const res = route(`/api/admissions/unsubscribe/${TOKEN}/`, "POST")!;
    expect(res.status).toBe(410);
    expect(await res.text()).not.toContain(TOKEN);
  });

  it("answers 410 for the old TCS OS API, HR and finance paths, any method", () => {
    const paths = [
      "/api/admissions/inquiries/",
      "/api/admissions/applications/",
      "/api/admissions/quick-interest/",
      "/api/admissions/pdf-gate/admissions-overview/",
      "/api/admissions/upload-url/",
      `/api/admissions/offers/${TOKEN}/respond/`,
      "/api/admissions/application-drafts/",
      `/api/admissions/application-drafts/${TOKEN}/`,
      "/api/admissions/internal/send-campaign-batch/",
      "/api/admissions/unsubscribe/",
      "/api/admissions/unsubscribe/a/b/",
      "/api",
      "/hr/",
      "/hr/payslips/1/",
      "/finance",
      "/finance/x",
    ];
    for (const path of paths) {
      for (const method of ["GET", "POST"]) {
        expect(route(path, method)?.status, `${method} ${path}`).toBe(410);
      }
    }
  });

  it("answers 404 for every staff path and anything else (D-15g)", () => {
    for (const path of [
      "/login",
      "/accept-invite",
      "/admissions",
      "/admissions/settings",
      "/payroll",
      "/employees",
      "/audit-log",
      `/onboarding/${TOKEN}`,
      "/hrx",
      "/apix",
      "/nothing",
    ]) {
      expect(route(path)?.status, path).toBe(404);
    }
  });

  it("leaves every other host alone: workers.dev, localhost and look-alikes", () => {
    const hosts = [
      new URL(STAFF_ORIGIN).host,
      "localhost:8080",
      "127.0.0.1:8787",
      `${ADMISSIONS_HOST}.evil.test`,
      `x${ADMISSIONS_HOST}`,
      `www.${ADMISSIONS_HOST}`,
      "tcsch.edu.gh",
    ];
    for (const host of hosts) {
      for (const path of ["/", "/login", "/admin", "/api/admissions/inquiries/", "/payroll"]) {
        expect(routeAdmissionsHost(req(host, path)), `${host}${path}`).toBeNull();
      }
    }
  });

  it("matches the admissions host in any case, with a port or a trailing dot", () => {
    for (const host of [
      "ADMISSIONS.TCSCH.EDU.GH",
      `${ADMISSIONS_HOST}:443`,
      `${ADMISSIONS_HOST}:8787`,
      `${ADMISSIONS_HOST}.`,
    ]) {
      expect(routeAdmissionsHost(req(host, "/login"))?.status, host).toBe(404);
      expect(routeAdmissionsHost(req(host, "/inquiry")), host).toBeNull();
    }
  });

  it("applies the same rules on the rehearsal host (D-15i)", () => {
    expect(route("/inquiry", "GET", REHEARSAL_HOST)).toBeNull();
    expect(route("/", "GET", REHEARSAL_HOST)?.status).toBe(302);
    expect(route("/payroll", "GET", REHEARSAL_HOST)?.status).toBe(404);
    expect(route("/api/admissions/inquiries/", "POST", REHEARSAL_HOST)?.status).toBe(410);
  });

  it("marks every answer no-store and noindex; HEAD gets no body", async () => {
    for (const [path, method] of [
      ["/", "GET"],
      ["/admin", "GET"],
      ["/payroll", "GET"],
      ["/hr/", "GET"],
      [`/api/admissions/unsubscribe/${TOKEN}/`, "GET"],
      ["/apply", "POST"],
    ]) {
      const res = route(path, method)!;
      expect(res.headers.get("cache-control"), path).toBe("no-store");
      expect(res.headers.get("x-robots-tag"), path).toBe("noindex");
    }
    expect(route("/payroll", "HEAD")!.body).toBeNull();
    const page = route("/payroll")!;
    expect(page.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(page.headers.get("content-security-policy")).toContain("default-src 'none'");
  });

  it("escapes the page text and has no dashes in any host copy", () => {
    expect(renderHostPage("<b>", ["a & b"])).toContain("&lt;b&gt;");
    expect(renderHostPage("t", ["a & b"])).toContain("a &amp; b");
    const all = JSON.stringify(ADMISSIONS_HOST_COPY) + renderHostPage("t", ["p"]);
    expect(all).not.toMatch(DASHES);
  });
});

describe("the privacy page link (slice 15 B)", () => {
  it("is relative, so it works on every host", () => {
    expect(PRIVACY_POLICY.url).toBe("/privacy");
  });

  it("says it is a placeholder while it is one, with no dashes", () => {
    if (PRIVACY_PAGE_COPY.placeholder) {
      expect(PRIVACY_PAGE_COPY.placeholderNotice).toMatch(/placeholder/i);
    }
    expect(JSON.stringify(PRIVACY_PAGE_COPY)).not.toMatch(DASHES);
  });
});
