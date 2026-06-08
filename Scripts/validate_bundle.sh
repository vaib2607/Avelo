#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/Avelo.app}"
CONTENTS_DIR="$APP_DIR/Contents"
EXECUTABLE="$CONTENTS_DIR/MacOS/Avelo"
PLIST="$CONTENTS_DIR/Info.plist"
RESOURCE="$CONTENTS_DIR/Resources/DefaultChartOfAccounts.json"

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

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
bundle_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
min_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"

echo "Bundle OK"
echo "Name: $bundle_name"
echo "Identifier: $bundle_id"
echo "Executable: $bundle_exec"
echo "Minimum macOS: $min_system"
