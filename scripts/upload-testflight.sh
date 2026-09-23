#!/usr/bin/env bash
# Upload an existing archive using the signed-in Xcode account.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/NextCue.xcarchive}"
STAGING="$ROOT/build/upload-staging"
OPTIONS="$ROOT/AppStoreUploadOptions.plist"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  echo "Create it with ./scripts/testflight.sh" >&2
  exit 1
fi

if [[ ! -f "$OPTIONS" ]]; then
  echo "error: missing $OPTIONS" >&2
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STAGING" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates
