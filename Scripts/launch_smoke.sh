#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/Mally.app}"
WAIT_SECONDS="${WAIT_SECONDS:-15}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: app bundle not found at $APP_DIR" >&2
  exit 1
fi

APP_DIR="$(cd "$APP_DIR" && pwd)"
APP_NAME="$(basename "$APP_DIR" .app)"
EXECUTABLE="$APP_DIR/Contents/MacOS/Mally"

"$ROOT_DIR/Scripts/validate_bundle.sh" "$APP_DIR" >/dev/null

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: executable missing at $EXECUTABLE" >&2
  exit 1
fi

"$EXECUTABLE" >/dev/null 2>&1 &
pid=$!

deadline=$((SECONDS + WAIT_SECONDS))
while [[ $SECONDS -lt $deadline ]]; do
  if kill -0 "$pid" 2>/dev/null; then
    break
  fi
  sleep "$POLL_INTERVAL"
done

if ! kill -0 "$pid" 2>/dev/null; then
  echo "error: $APP_NAME did not appear in the process list within ${WAIT_SECONDS}s" >&2
  exit 1
fi

sleep 2

if ! kill -0 "$pid" 2>/dev/null; then
  echo "error: $APP_NAME exited immediately after launch" >&2
  wait "$pid" 2>/dev/null || true
  exit 1
fi

kill "$pid" >/dev/null 2>&1 || true

quit_deadline=$((SECONDS + WAIT_SECONDS))
while [[ $SECONDS -lt $quit_deadline ]]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
    echo "Launch smoke OK"
    echo "App: $APP_DIR"
    exit 0
  fi
  sleep "$POLL_INTERVAL"
done

kill -KILL "$pid" >/dev/null 2>&1 || true

kill_deadline=$((SECONDS + WAIT_SECONDS))
while [[ $SECONDS -lt $kill_deadline ]]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
    echo "Launch smoke OK"
    echo "App: $APP_DIR"
    echo "Note: app required forced termination after smoke launch."
    exit 0
  fi
  sleep "$POLL_INTERVAL"
done

echo "error: $APP_NAME did not stop after smoke launch" >&2
exit 1
