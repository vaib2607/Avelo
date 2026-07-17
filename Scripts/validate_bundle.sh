#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/Avelo.app}"
CONTENTS_DIR="$APP_DIR/Contents"
EXECUTABLE="$CONTENTS_DIR/MacOS/Avelo"
PLIST="$CONTENTS_DIR/Info.plist"
RESOURCE="$CONTENTS_DIR/Resources/DefaultChartOfAccounts.json"
VERSION_FILE="$ROOT_DIR/ReleaseVersion.env"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: app bundle not found at $APP_DIR" >&2
  exit 1
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: executable missing at $EXECUTABLE" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "error: Info.plist missing at $PLIST" >&2
  exit 1
fi

if [[ ! -f "$RESOURCE" ]]; then
  echo "error: seed resource missing at $RESOURCE" >&2
  exit 1
fi

plutil -lint "$PLIST" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

# shellcheck disable=SC1090
source "$VERSION_FILE"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
bundle_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
min_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

if [[ "$bundle_version" != "$AVELO_VERSION" || "$bundle_build" != "$AVELO_BUILD" ]]; then
  echo "error: bundle version $bundle_version ($bundle_build) does not match ReleaseVersion.env $AVELO_VERSION ($AVELO_BUILD)" >&2
  exit 1
fi

echo "Bundle OK"
echo "Name: $bundle_name"
echo "Identifier: $bundle_id"
echo "Executable: $bundle_exec"
echo "Minimum macOS: $min_system"
echo "Version: $bundle_version ($bundle_build)"
