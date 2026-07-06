#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/Scripts/swift-env.sh"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <swift-subcommand> [args...]" >&2
  exit 2
fi

CMD=(swift "$@")
case "$1" in
  build|test|package)
    CMD+=(--disable-sandbox --scratch-path "$AVELO_SWIFTPM_SCRATCH_PATH")
    ;;
esac

STDOUT_FILE="$(mktemp -t avelo-swift-stdout-XXXXXX.txt)"
STDERR_FILE="$(mktemp -t avelo-swift-stderr-XXXXXX.txt)"
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE"' EXIT

set +e
"${CMD[@]}" >"$STDOUT_FILE" 2>"$STDERR_FILE"
STATUS=$?
set -e

cat "$STDOUT_FILE"
cat "$STDERR_FILE" >&2

if [[ $STATUS -ne 0 ]] && rg -q 'Operation not permitted|ModuleCache|org\.swift\.swiftpm|unable to load standard library' "$STDERR_FILE"; then
  echo >&2
  avelo_swift_permission_hint
fi

exit $STATUS
