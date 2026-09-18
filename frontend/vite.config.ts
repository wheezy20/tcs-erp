import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

// Deploy target: Cloudflare Workers, via @cloudflare/vite-plugin (TanStack
// Start's current supported path — see docs/STACK.md). The plugin builds
// TanStack Start's "ssr" Vite environment into a Worker bundle; `nitro`
// is disabled because it would produce a competing server build.
// Worker settings live in ./wrangler.jsonc.
export default defineConfig({
  tanstackStart: {
    server: { entry: "server" },
  },
  nitro: false,
  plugins: [cloudflare({ viteEnvironment: { name: "ssr" } })],
  vite: {
    optimizeDeps: {
      // Vite's dev-server dependency scanner otherwise only crawls
      // whatever's reachable from the pages visited so far. The first
      // visit to a route nobody's opened yet in this dev session (e.g.
      // Payroll → Setup, which pulls in stores/components no other page
      // touches) can trigger a mid-session re-optimization: the client's
      // module map briefly points at a bundle that no longer matches the
      // server's, an import fails with a "does not provide an export"
      // SyntaxError, and the in-flight navigation is left stuck showing
      // the previous page until a hard reload re-fetches the now-correct
      // bundle. Listing every route file as a scan entry makes Vite crawl
      // the whole app's dependency graph up front at server start instead,
      // so there's no unvisited route left to trigger this later. Dev-only
      // (esbuild's dep pre-bundling doesn't exist in the production
      // Cloudflare Worker build — see docs/JOURNAL.md).
      entries: ["src/routes/**/*.tsx", "src/routes/**/*.ts"],
    },
  },
});
