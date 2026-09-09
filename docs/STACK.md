# TCS ERP — Stack

## Frontend

- **TanStack Start** + **TanStack Router** (file-based routing under
  `frontend/src/routes/`) — routes are generated into `routeTree.gen.ts`;
  never hand-edit that file.
- **React** + **TypeScript**
- **Tailwind CSS**
- **shadcn/ui** (new-york style) — see `frontend/components.json` for
  aliases; components live grouped by domain under
  `frontend/src/components/`.
- **Vite** for dev/build.
- Package manager: **npm** (`frontend/package-lock.json` is the lockfile).
  Resolved 2026-09-08 — `bun.lock` was stale from before the rebrand and
  has been deleted along with `bunfig.toml`. Use `npm`, not `bun`.

## Backend

- **Supabase** (Postgres 17) — schema lives entirely in
  `supabase/migrations/`, applied in order.
- **No client-side business logic for anything financial.** Every
  calculation (invoice totals, tax, payroll) happens in `plpgsql`
  functions inside the database. The client calls a function and
  displays what comes back — it never computes a total or a tax figure
  itself. This is a hard convention carried over from Wilelik, not a
  style preference.
- **Row-Level Security (RLS)** enforces role-based access per table.
  Roles currently defined on `staff.role`: `Attendant`, `Manager`,
  `Accountant/Auditor` (will need extending for school-specific roles in
  later phases).
- **Supabase Auth** — invite-only. No public signup; new staff accounts
  are created via `supabase.auth.admin.inviteUserByEmail()`, either from
  the in-app Settings (Manager only) or the one-time
  `scripts/bootstrap-production-manager.sh` script for the very first
  Manager account.
- **Supabase Storage** — a `receipts` bucket holds expense proof-of-
  purchase images (3MB limit, image MIME types only).

## Repo & tooling

- GitHub: `github.com/wheezy20/tcs-erp` (private).
- Local dev machine: Ubuntu 22.04, VS Code with the Claude Code
  extension — this is the primary way the ERP gets built, via
  conversational prompts rather than upfront spec documents.
- A `conda` environment (`datasci`, Python 3.11) also exists on this
  machine but is unrelated to this project — that's for Eyram's MSc/data
  science work.

## Hosting

**Frontend → Cloudflare Workers**, via `@cloudflare/vite-plugin` (TanStack
Start's current supported deploy path). `frontend/vite.config.ts` runs
`cloudflare({ viteEnvironment: { name: "ssr" } })` and disables Nitro;
`frontend/wrangler.jsonc` holds the Worker settings (name `tcs-erp`,
`nodejs_compat`, `main: src/server.ts`, assets from `dist/client`).

- Build: `cd frontend && npm ci && npm run build` → emits `dist/client/`
  (static assets) + `dist/server/` (`index.js` Worker bundle +
  `wrangler.json`).
- Deploy: `npx wrangler deploy` from `frontend/` (auto-detects the build
  output). Needs **Node ≥ 22** and a Cloudflare API token in CI.
- `wrangler deploy --dry-run` validates the config/bundle with no
  Cloudflare account.
- The old Vercel setup (`frontend/vercel.json`, `nitro` dep, Nitro
  `preset: "vercel"`) has been removed.

`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` are **build-time**
variables (Vite inlines them into the bundle) — they must be set in the
environment of the Cloudflare build step, not as Worker runtime secrets.
See CONSTRAINTS.md / DESIGN.md.

Backend stays on hosted Supabase (its own dedicated TCS project — see
CONSTRAINTS.md). The eventual fold-in to TCS OS's Cloud Run setup is still
a known future event (PLANNING.md), not affected by this.
