#!/usr/bin/env bash
# Builds the frontend for the live site and deploys it to Cloudflare Workers.
# This is the only supported way to deploy (docs/CONSTRAINTS.md, Deployment).
#
#   ./scripts/deploy-production.sh               build, check, deploy
#   ./scripts/deploy-production.sh --build-only  build and check, no deploy
#   ./scripts/deploy-production.sh --check-only  check the existing dist/ only
#
# Why it exists: the Supabase URL and anon key are baked into the bundle at
# build time (Vite reads VITE_* while building). A plain `npm run build`
# reads frontend/.env.local, which points at the LOCAL Supabase, so a
# deploy from that build sends the live site's requests to 127.0.0.1.
#
# What it does:
#   1. Reads the hosted project's URL and anon key from frontend/.env.deploy
#      (gitignored; Vite never loads a file by that name on its own). It
#      refuses anything that isn't https://<ref>.supabase.co, and any
#      service_role / secret key.
#   2. Moves every .env file Vite would load (.env, .env.local,
#      .env.production, .env.production.local) out of the way for the
#      build, so the build can't read them, and puts them back afterwards.
#   3. Builds with the hosted values passed as environment variables.
#   4. Refuses to continue if dist/client or dist/server contains the local
#      Supabase address (127.0.0.1 / localhost / [::1] / 0.0.0.0 on a
#      Supabase CLI port, 54xxx), a key from .env.local, or a Supabase CLI
#      demo key; if the hosted URL or anon key is missing from the client
#      or server bundle; or if wrangler isn't pointed at the build.
#      Bare "localhost" / "127.0.0.1" strings are listed but don't stop it:
#      supabase-js and TanStack Router contain them in every build (e.g.
#      supabase-js's own http://localhost:9999 default and its list of
#      loopback hosts), so a check on those alone would refuse every build.
#   5. Only then runs `wrangler deploy`.
#
# Needs: Node >= 22, and Cloudflare credentials (CLOUDFLARE_API_TOKEN in the
# environment, or a prior `npx wrangler login`).

set -euo pipefail

cd "$(dirname "$0")/.."  # frontend/

MODE=deploy
case "${1:-}" in
  "") ;;
  --build-only) MODE=build ;;
  --check-only) MODE=check ;;
  *) echo "Unknown option: $1 (use --build-only or --check-only)" >&2; exit 2 ;;
esac

DEPLOY_ENV=.env.deploy
HIDDEN_DIR=.env-hidden-during-deploy
VITE_ENV_FILES=(.env .env.local .env.production .env.production.local)

fail() {
  echo "" >&2
  echo "DEPLOY STOPPED: $*" >&2
  exit 1
}

# ---------------------------------------------------------------- dist checks
LOCAL_SUPABASE_RE='(127\.0\.0\.1|localhost|0\.0\.0\.0|\[::1\]|host\.docker\.internal):54[0-9]{3}'
# Base64 of '{"iss":"supabase-demo"': the start of every Supabase CLI demo key.
DEMO_KEY_MARK='eyJpc3MiOiJzdXBhYmFzZS1kZW1vIi'

# The value of KEY in FILE, without executing the file.
read_value_from() {
  local file="$1" name="$2" line
  [[ -f "$file" ]] || return 0
  line=$(grep -E "^$name=" "$file" | tail -1 || true)
  line="${line#*=}"
  # Surrounding whitespace, then one pair of quotes, is dropped; anything
  # else odd is refused rather than glued into the value (e.g. an inline
  # "# comment").
  line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  line="${line%\"}"; line="${line#\"}"
  line="${line%\'}"; line="${line#\'}"
  if [[ "$line" =~ [[:space:]#] ]]; then
    fail "$name in $file contains a space or '#'. Use plain NAME=value lines, no inline comments."
  fi
  printf '%s' "$line"
}

check_dist() {
  local url="$1" key="$2" local_key="$3"

  [[ -d dist/client && -d dist/server ]] || fail "dist/client or dist/server is missing. Build first."

  if grep -rIqE "$LOCAL_SUPABASE_RE" dist/client dist/server; then
    echo "Local Supabase address found in the build:" >&2
    grep -rIoE ".{0,40}$LOCAL_SUPABASE_RE.{0,40}" dist/client dist/server | head -10 >&2 || true
    fail "the build contains the local Supabase address. Never deploy it."
  fi
  if grep -rIqF "$DEMO_KEY_MARK" dist/client dist/server; then
    grep -rIlF "$DEMO_KEY_MARK" dist/client dist/server | head -5 >&2 || true
    fail "the build contains a Supabase CLI demo key (a local key). Never deploy it."
  fi
  if [[ -n "$local_key" ]] && grep -rIqF "$local_key" dist/client dist/server; then
    grep -rIlF "$local_key" dist/client dist/server | head -5 >&2 || true
    fail "the build contains the anon key from .env.local (the local key). Never deploy it."
  fi

  if [[ -n "$url" ]]; then
    grep -rIqF "$url" dist/client || fail "the client bundle does not contain $url."
    grep -rIqF "$url" dist/server || fail "the server bundle does not contain $url."
    grep -rIqF "$key" dist/client || fail "the client bundle does not contain the anon key from $DEPLOY_ENV."
    grep -rIqF "$key" dist/server || fail "the server bundle does not contain the anon key from $DEPLOY_ENV."
  fi

  local other
  other=$(grep -rIoE '.{0,30}(127\.0\.0\.1|localhost).{0,30}' dist/client dist/server | grep -cvE "$LOCAL_SUPABASE_RE" || true)
  echo "Note: $other bare localhost/127.0.0.1 mention(s) remain inside library code (expected; not a Supabase address)."

  [[ -f .wrangler/deploy/config.json ]] \
    && grep -qF 'dist/server/wrangler.json' .wrangler/deploy/config.json \
    || fail ".wrangler/deploy/config.json does not point wrangler at dist/server/wrangler.json, so wrangler would not deploy this build."

  echo "dist/ checked: no local address$([[ -n "$url" ]] && echo ", hosted URL and anon key present"), wrangler points at the build."
}

if [[ "$MODE" == check ]]; then
  check_dist "" "" "$(read_value_from .env.local VITE_SUPABASE_ANON_KEY)"
  exit 0
fi

# ---------------------------------------------------------------- hosted values
[[ -f "$DEPLOY_ENV" ]] || fail "frontend/$DEPLOY_ENV is missing. Create it with two lines:
  VITE_SUPABASE_URL=https://<project-ref>.supabase.co
  VITE_SUPABASE_ANON_KEY=<the hosted project's anon (public) key>
(Supabase Dashboard -> Project Settings -> API. Never the service_role key.)"

URL=$(read_value_from "$DEPLOY_ENV" VITE_SUPABASE_URL)
KEY=$(read_value_from "$DEPLOY_ENV" VITE_SUPABASE_ANON_KEY)
LOCAL_KEY=$(read_value_from .env.local VITE_SUPABASE_ANON_KEY)

[[ "$URL" =~ ^https://[a-z0-9]{20}\.supabase\.co$ ]] \
  || fail "VITE_SUPABASE_URL in $DEPLOY_ENV must be https://<20-character project ref>.supabase.co (got '$URL')."
[[ -n "$KEY" ]] || fail "VITE_SUPABASE_ANON_KEY is empty in $DEPLOY_ENV."

case "$KEY" in
  sb_secret_*) fail "VITE_SUPABASE_ANON_KEY is a secret key. Use the anon / publishable key." ;;
  sb_publishable_*) ;;
  *.*.*)
    payload=$(printf '%s' "$KEY" | cut -d. -f2 | tr '_-' '/+')
    while (( ${#payload} % 4 )); do payload="$payload="; done
    role=$(printf '%s' "$payload" | base64 -d 2>/dev/null | grep -oE '"role" *: *"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"' || true)
    [[ "$role" == anon ]] || fail "VITE_SUPABASE_ANON_KEY has role '${role:-unknown}', not 'anon'. Never bake in a service_role key."
    ;;
  *) fail "VITE_SUPABASE_ANON_KEY doesn't look like a Supabase anon or publishable key." ;;
esac

node_major=$(node -p 'process.versions.node.split(".")[0]')
(( node_major >= 22 )) || fail "Node >= 22 is required (found $(node -v))."

# ---------------------------------------------------------------- build
if [[ -e "$HIDDEN_DIR" ]]; then fail "$HIDDEN_DIR exists from an interrupted run. Move its files back into frontend/ first."; fi

restore_env_files() {
  if [[ -d "$HIDDEN_DIR" ]]; then
    for f in "$HIDDEN_DIR"/.env*; do
      if [[ -e "$f" ]]; then mv "$f" .; fi
    done
    rmdir "$HIDDEN_DIR"
  fi
}
trap restore_env_files EXIT
trap 'exit 130' INT TERM  # Ctrl-C or kill still exits through the EXIT trap

mkdir "$HIDDEN_DIR"
for f in "${VITE_ENV_FILES[@]}"; do
  if [[ -e "$f" ]]; then mv "$f" "$HIDDEN_DIR/"; fi
done

echo "Building for $URL (local .env files set aside for the build)..."
rm -rf dist
VITE_SUPABASE_URL="$URL" VITE_SUPABASE_ANON_KEY="$KEY" npx vite build --mode production

restore_env_files
trap - EXIT INT TERM

check_dist "$URL" "$KEY" "$LOCAL_KEY"

if [[ "$MODE" == build ]]; then
  echo "Build only: not deploying."
  exit 0
fi

# ---------------------------------------------------------------- deploy
echo "Deploying to Cloudflare Workers..."
npx wrangler deploy
