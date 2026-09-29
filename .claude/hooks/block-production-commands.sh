#!/usr/bin/env bash
#
# PreToolUse hook (Bash): blocks commands with production side effects that
# Eyram runs by hand — pushing code, pushing schema, deploying, and the
# production-Manager bootstrap. See CLAUDE.md's slice loop. Exit 2 blocks the
# tool call and shows the message on stderr to Claude.
#
# Matches only in command position (start of the command, or after ; && ||
# | ( $( or a newline), and ignores heredoc bodies, so a commit message,
# grep pattern, or file content that merely mentions "git push" isn't
# blocked. It's a backstop for CLAUDE.md's production-step gate, not a
# sandbox: `bash -c "..."` or an alias would get past it.

set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Drop heredoc bodies first: they're data (file contents, SQL, docs text),
# not commands, and routinely mention these command names.
cmd=$(printf '%s\n' "$cmd" | awk '
  skip != "" { t = $0; if (strip) sub(/^\t+/, "", t); if (t == skip) skip = ""; next }
  { print }
  match($0, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) {
    tag = substr($0, RSTART, RLENGTH)
    strip = (tag ~ /^<<-/)
    sub(/^<<-?[[:space:]]*["\047]?/, "", tag); sub(/["\047]$/, "", tag)
    skip = tag
  }')

# Newlines separate commands just like ';'. Collapse other whitespace so
# oddly spaced commands still match.
norm=$(printf '%s' "$cmd" | tr '\n\t' '; ' | tr -s ' ')

start='(^|[;&|(]|\$\()[[:space:]]*'
prefix='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((sudo|env|npx|bunx|pnpm|exec|bash|sh|time)[[:space:]]+)*'

blocked=(
  "git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-;&|[:space:]][^[:space:]]*)?)*[[:space:]]+push([^A-Za-z0-9_-]|$)|git push"
  "supabase[[:space:]]+db[[:space:]]+push|supabase db push"
  "supabase[[:space:]]+db[[:space:]]+reset[^;&|]*--(linked|db-url)|supabase db reset against a remote project"
  "supabase[[:space:]]+(functions[[:space:]]+deploy|secrets[[:space:]]+set)|supabase functions deploy / secrets set"
  "wrangler[[:space:]]+(versions[[:space:]]+)?deploy|wrangler deploy"
  "[A-Za-z0-9_./~-]*bootstrap-production-manager\.sh|bootstrap-production-manager.sh"
)

for entry in "${blocked[@]}"; do
  pattern="${entry%|*}"
  label="${entry##*|}"
  if [[ "$norm" =~ ${start}${prefix}${pattern} ]]; then
    echo "Blocked by .claude/hooks/block-production-commands.sh: '$label' has production side effects and is run by Eyram only. Stop and hand this step to Eyram with the exact command to run." >&2
    exit 2
  fi
done

exit 0
