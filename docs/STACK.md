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
- Package manager: the repo has both `bun.lock` and `package-lock.json`
  present (inherited from Wilelik's transition history) — confirm which
  one is actually in use before installing anything, to avoid two
  divergent lockfiles.

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

Not yet decided for production. A `vercel.json` exists in
`frontend/`, inherited from Wilelik's own deployment — whether TCS ERP
actually deploys to Vercel, or gets folded into TCS OS's existing Google
Cloud Run setup once merged, is an open question (see PLANNING.md /
CONSTRAINTS.md).
