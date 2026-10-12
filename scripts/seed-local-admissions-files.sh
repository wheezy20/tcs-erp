#!/usr/bin/env bash
#
# Uploads tiny invented placeholder files to the LOCAL admissions-documents
# bucket, one per demo document row in supabase/seed.sql that has a
# storage_path under demo/, so the signed "View" links on the admissions
# detail page open something while developing. Every file is the same
# generated placeholder ("Invented demo file"); nothing real is uploaded.
#
# Uses the local service_role key (the bucket has no insert policy for
# staff), so, like seed-local-dev-staff.sh, it refuses to run unless
# `supabase status` reports a 127.0.0.1 or localhost API_URL. That key is
# only ever used by this shell script, never by the frontend.
#
# Safe to re-run after every `supabase db reset` (uploads with upsert).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

STATUS=$(npx supabase status -o env 2>/dev/null || true)
API_URL=$(echo "$STATUS" | grep '^API_URL=' | cut -d'"' -f2)
SERVICE_ROLE_KEY=$(echo "$STATUS" | grep '^SERVICE_ROLE_KEY=' | cut -d'"' -f2)

if [[ -z "$API_URL" || -z "$SERVICE_ROLE_KEY" ]]; then
  echo "Could not read API_URL/SERVICE_ROLE_KEY from 'supabase status'. Is the local stack running? (npx supabase start)" >&2
  exit 1
fi

if [[ "$API_URL" != *"127.0.0.1"* && "$API_URL" != *"localhost"* ]]; then
  echo "Refusing to run: API_URL ('$API_URL') is not a local address." >&2
  echo "This script uses the service_role key, which bypasses RLS entirely. It must never run against a real project." >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A minimal one-page PDF and a 1x1 PNG, generated here so no binary lives in
# the repo.
printf '%s\n' '%PDF-1.4' \
  '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj' \
  '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj' \
  '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj' \
  '4 0 obj<</Length 52>>stream' \
  'BT /F1 14 Tf 20 50 Td (Invented demo file) Tj ET' \
  'endstream endobj' \
  '5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj' \
  'trailer<</Root 1 0 R>>' '%%EOF' > "$TMP/demo.pdf"
base64 -d > "$TMP/demo.png" <<< 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

PATHS=$(curl -sf "$API_URL/rest/v1/application_documents?select=storage_path&storage_path=like.demo/*" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" | jq -r '.[].storage_path')

if [[ -z "$PATHS" ]]; then
  echo "No demo document rows found. Run 'npx supabase db reset' first so seed.sql loads." >&2
  exit 1
fi

count=0
while IFS= read -r path; do
  case "${path,,}" in
    *.pdf) file="$TMP/demo.pdf"; type="application/pdf" ;;
    *.png) file="$TMP/demo.png"; type="image/png" ;;
    *) echo "Skipping $path (unexpected extension)" >&2; continue ;;
  esac
  curl -sf -X POST "$API_URL/storage/v1/object/admissions-documents/$path" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: $type" -H "x-upsert: true" \
    --data-binary "@$file" > /dev/null
  count=$((count + 1))
done <<< "$PATHS"

echo "Uploaded $count invented demo file(s) to the local admissions-documents bucket."
