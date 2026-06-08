#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/Mally.app}"
EXECUTABLE="$APP_DIR/Contents/MacOS/Mally"
OUTPUT_FILE="$(mktemp -t mally-selftest-XXXXXX.txt)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

APP_DIR="$(cd "$APP_DIR" && pwd)"
EXECUTABLE="$APP_DIR/Contents/MacOS/Mally"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: bundled executable missing at $EXECUTABLE" >&2
  exit 1
fi

"$ROOT_DIR/Scripts/validate_bundle.sh" "$APP_DIR" >/dev/null
"$EXECUTABLE" --self-test --self-test-output "$OUTPUT_FILE"

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "error: self-test output file missing" >&2
  exit 1
fi

if ! grep -q "SELFTEST OK" "$OUTPUT_FILE"; then
  echo "error: self-test did not report success" >&2
  cat "$OUTPUT_FILE" >&2
  exit 1
fi

cat "$OUTPUT_FILE"
