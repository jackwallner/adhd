#!/usr/bin/env bash
# Upload listing metadata. Screenshots are uploaded only when requested.
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

python3 scripts/validate-metadata.py
if [[ -z "${ASC_APP_VERSION:-}" ]]; then
  eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
fi

FASTLANE="$ROOT/scripts/fastlane-bin.sh"
"$FASTLANE" upload_metadata
if [[ "${UPLOAD_SCREENSHOTS:-false}" == "true" ]]; then
  "$FASTLANE" upload_screenshots
fi
