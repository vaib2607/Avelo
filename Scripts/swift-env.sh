#!/usr/bin/env bash

if [[ -n "${AVELO_SWIFT_ENV_LOADED:-}" ]]; then
  return 0
fi
AVELO_SWIFT_ENV_LOADED=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVELO_SWIFT_STATE_DIR="${AVELO_SWIFT_STATE_DIR:-$ROOT_DIR/.swift-dev}"
AVELO_SWIFT_HOME="${AVELO_SWIFT_HOME:-$AVELO_SWIFT_STATE_DIR/home}"
AVELO_SWIFT_TMPDIR="${AVELO_SWIFT_TMPDIR:-$AVELO_SWIFT_STATE_DIR/tmp}"
AVELO_SWIFT_CACHE_DIR="${AVELO_SWIFT_CACHE_DIR:-$AVELO_SWIFT_STATE_DIR/cache}"
AVELO_SWIFT_MODULE_CACHE="${AVELO_SWIFT_MODULE_CACHE:-$AVELO_SWIFT_CACHE_DIR/clang/ModuleCache}"
AVELO_SWIFTPM_CONFIG_DIR="${AVELO_SWIFTPM_CONFIG_DIR:-$AVELO_SWIFT_HOME/Library/org.swift.swiftpm}"
AVELO_SWIFTPM_SECURITY_DIR="${AVELO_SWIFTPM_SECURITY_DIR:-$AVELO_SWIFT_HOME/Library/org.swift.swiftpm/security}"
AVELO_SWIFTPM_CACHE_DIR="${AVELO_SWIFTPM_CACHE_DIR:-$AVELO_SWIFT_HOME/Library/Caches/org.swift.swiftpm}"
AVELO_SWIFTPM_SCRATCH_PATH="${AVELO_SWIFTPM_SCRATCH_PATH:-$ROOT_DIR/.build/swiftpm-scratch}"

mkdir -p \
  "$AVELO_SWIFT_HOME" \
  "$AVELO_SWIFT_TMPDIR" \
  "$AVELO_SWIFT_CACHE_DIR" \
  "$AVELO_SWIFT_MODULE_CACHE" \
  "$AVELO_SWIFTPM_CONFIG_DIR" \
  "$AVELO_SWIFTPM_SECURITY_DIR" \
  "$AVELO_SWIFTPM_CACHE_DIR" \
  "$AVELO_SWIFTPM_SCRATCH_PATH"

export HOME="$AVELO_SWIFT_HOME"
export CFFIXED_USER_HOME="$AVELO_SWIFT_HOME"
export TMPDIR="$AVELO_SWIFT_TMPDIR"
export XDG_CACHE_HOME="$AVELO_SWIFT_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$AVELO_SWIFT_MODULE_CACHE"

avelo_swift_permission_hint() {
  cat >&2 <<'EOF'
hint: SwiftPM tried to use a protected cache path. Avelo ships a repo-local fallback.
hint: rerun the command via `make test`, `make verify`, or `./Scripts/swiftw.sh ...`.
hint: repo-local Swift state lives under `.swift-dev/` and `.build/swiftpm-scratch/`.
EOF
}
