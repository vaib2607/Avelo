#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-dist/Avelo.app}"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 2
fi

INFO="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"

echo "Captured UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "Hardware: $(sysctl -n hw.model) / $(sysctl -n machdep.cpu.brand_string) / $(sysctl -n hw.memsize) bytes"
echo "App: $(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
echo "Identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
echo "Build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
echo "Executable SHA-256: $(shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"

echo "Code signature:"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E '^(Identifier|Format|CodeDirectory|Signature|Authority|TeamIdentifier|Runtime Version)=' || true

echo "Strict signature verification:"
if codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1; then echo PASS; else echo FAIL; fi

echo "Gatekeeper assessment:"
if spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1; then echo PASS; else echo FAIL; fi

echo "Stapled ticket:"
if xcrun stapler validate "$APP_PATH" 2>&1; then echo PASS; else echo FAIL; fi

echo "Available signing identities:"
security find-identity -v -p codesigning 2>&1
