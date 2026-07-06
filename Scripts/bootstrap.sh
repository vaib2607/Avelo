#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTW="$ROOT_DIR/Scripts/swiftw.sh"

log_step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

fail_with_hint() {
  local message="$1"
  echo "error: $message" >&2
  exit 1
}

require_command() {
  local name="$1"
  local hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    fail_with_hint "$name is missing. $hint"
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail_with_hint "Avelo currently builds on macOS only."
fi

log_step "1/5" "Verifying local toolchain"
require_command xcode-select "Install Xcode Command Line Tools with 'xcode-select --install'."
require_command swift "Install Xcode 15+ Command Line Tools, then reopen the shell."
require_command codesign "Install Xcode Command Line Tools so the app bundle can be signed."
if ! xcode-select -p >/dev/null 2>&1; then
  fail_with_hint "xcode-select is not configured. Run 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer' or 'xcode-select --install'."
fi
swift --version | rg -m1 'Swift version'
echo "What you should see: an Apple Swift 5.9+ version line."

log_step "2/5" "Building the debug package with repo-local SwiftPM caches"
"$SWIFTW" build
echo "What you should see: 'Build complete!' and no blocking permission errors about ModuleCache, org.swift.swiftpm, or sandbox_apply."

log_step "3/5" "Running the full test suite"
"$SWIFTW" test
echo "What you should see: the AveloTests suite finishes cleanly."

log_step "4/5" "Assembling the signed local app bundle"
"$ROOT_DIR/Scripts/bundle.sh" release
echo "What you should see: 'Created $ROOT_DIR/dist/Avelo.app'."

log_step "5/5" "Next step"
cat <<EOF
Bootstrap complete.

Next commands:
  open "$ROOT_DIR/dist/Avelo.app"
  make verify

What you should see:
  - the bundled app opens locally
  - \`make verify\` runs the repo proof set (rule audit, tests, bundle, validation, self-test)
EOF
