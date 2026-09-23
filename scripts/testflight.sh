#!/usr/bin/env bash
# Build and upload Next Cue to TestFlight.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT_YML="$ROOT/project.yml"
ARCHIVE="$ROOT/build/NextCue.xcarchive"
ASC_APP_ID="6815023447"

CURRENT_BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
echo "==> App Store Connect app $ASC_APP_ID"
echo "==> Bump build $CURRENT_BUILD -> $NEXT_BUILD"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\")$CURRENT_BUILD/\1$NEXT_BUILD/" "$PROJECT_YML"

echo "==> Generate Xcode project"
xcodegen generate

echo "==> Resolve package dependencies"
xcodebuild -resolvePackageDependencies -project NextCue.xcodeproj -scheme NextCue

rm -rf "$ARCHIVE"
echo "==> Archive Release"
xcodebuild -project NextCue.xcodeproj \
  -scheme NextCue \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

echo "==> Upload to TestFlight"
"$ROOT/scripts/upload-testflight.sh" "$ARCHIVE"

git add "$PROJECT_YML"
if ! git diff --cached --quiet -- "$PROJECT_YML"; then
  git commit --only -m "chore: bump build $CURRENT_BUILD to $NEXT_BUILD for TestFlight" -- "$PROJECT_YML"
fi
echo "==> Build $NEXT_BUILD uploaded"
