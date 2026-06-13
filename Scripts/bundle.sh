#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(cd "$ROOT_DIR" && swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/Avelo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_NAME="Avelo"
EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
SEED_RESOURCE="$ROOT_DIR/Avelo/Resources/Seed/DefaultChartOfAccounts.json"
ENTITLEMENTS_FILE="$ROOT_DIR/Avelo/Avelo.entitlements"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: expected built executable at $EXECUTABLE_PATH" >&2
  echo "hint: run 'swift build -c $CONFIGURATION' first" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$SEED_RESOURCE" "$RESOURCES_DIR/DefaultChartOfAccounts.json"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Avelo</string>
  <key>CFBundleIdentifier</key>
  <string>com.avelo.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Avelo</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0-rc1</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"

echo "Created $APP_DIR"
