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
});
