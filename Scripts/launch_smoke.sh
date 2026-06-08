#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/Avelo.app}"

"$ROOT_DIR/Scripts/validate_bundle.sh" "$APP_DIR" >/dev/null
"$ROOT_DIR/Scripts/bundle_selftest.sh" "$APP_DIR"

echo "Launch smoke OK"
echo "App: $APP_DIR"
