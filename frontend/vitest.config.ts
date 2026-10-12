import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// Unit tests for pure logic only (no DOM, no Supabase, no router). Kept
// separate from vite.config.ts so the Cloudflare and TanStack Start plugins
// never load under test. See docs/DESIGN.md, "Project layout".
export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
