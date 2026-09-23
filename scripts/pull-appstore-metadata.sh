#!/usr/bin/env bash
# Snapshot local metadata, then pull the current App Store Connect listing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: set ASC_API_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH" >&2
  exit 1
fi

if [[ -d fastlane/metadata ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="fastlane/metadata.bak.$STAMP"
  cp -R fastlane/metadata "$BACKUP"
  echo "snapshot: $BACKUP"
fi

TEMP_KEY="$(mktemp -t asc_api_key.XXXXXX.json)"
trap 'rm -f "$TEMP_KEY"' EXIT
python3 - "$ASC_API_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" "$TEMP_KEY" <<'PY'
import json
import sys
from pathlib import Path

key_id, issuer_id, key_path, output = sys.argv[1:5]
key_contents = Path(key_path).read_text(encoding="utf-8")
with open(output, "w", encoding="utf-8") as handle:
    json.dump(
        {"key_id": key_id, "issuer_id": issuer_id, "key": key_contents, "in_house": False},
        handle,
    )
PY

FASTLANE="$ROOT/scripts/fastlane-bin.sh"
"$FASTLANE" deliver download_metadata \
  --api_key_path "$TEMP_KEY" \
  --app_identifier "com.jackwallner.adhd" \
  --metadata_path ./fastlane/metadata \
  --force true \
  --skip_screenshots true \
  "$@"
