#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-core}"
case "$MODE" in
  core)
    MILLION=0
    MILLION_BATCHED=0
    MILLION_COUNT=0
    MILLION_PROGRESS_STEP=10000
    ;;
  million)
    MILLION=1
    MILLION_BATCHED=1
    MILLION_COUNT=500000
    MILLION_PROGRESS_STEP=25000
    ;;
  million-fast)
    MILLION=1
    MILLION_BATCHED=1
    MILLION_COUNT=10000
    MILLION_PROGRESS_STEP=500
    ;;
  million-100k)
    MILLION=1
    MILLION_BATCHED=1
    MILLION_COUNT=100000
    MILLION_PROGRESS_STEP=5000
    ;;
  million-500k)
    MILLION=1
    MILLION_BATCHED=1
    MILLION_COUNT=500000
    MILLION_PROGRESS_STEP=25000
    ;;
  million-tiny)
    MILLION=1
    MILLION_BATCHED=1
    MILLION_COUNT=2000
    MILLION_PROGRESS_STEP=250
    ;;
  *)
    echo "usage: $0 [core|million|million-100k|million-500k|million-fast|million-tiny]" >&2
    exit 2
    ;;
esac

FILTER="BenchmarkSuiteTests"
if [[ "$MODE" != "core" ]]; then
  FILTER="BenchmarkSuiteTests/testMillionVoucherStressSuite"
fi

BENCH_HOME="$ROOT_DIR/.build/benchmark-home-$MODE"
SCRATCH_DIR="$BENCH_HOME/.scratch-$MODE"
rm -rf "$BENCH_HOME/.tmp" "$BENCH_HOME/.cache/clang/ModuleCache"
mkdir -p "$BENCH_HOME/.cache/clang/ModuleCache" "$BENCH_HOME/.swiftpm" "$BENCH_HOME/.tmp" "$BENCH_HOME/Desktop" "$SCRATCH_DIR"

HOME="$BENCH_HOME" \
TMPDIR="$BENCH_HOME/.tmp" \
XDG_CACHE_HOME="$BENCH_HOME/.cache" \
CLANG_MODULE_CACHE_PATH="$BENCH_HOME/.cache/clang/ModuleCache" \
AVELO_BENCHMARK_OUTPUT_DIR="$BENCH_HOME/Desktop" \
AVELO_BENCHMARK_TMP_DIR="$BENCH_HOME/.tmp" \
AVELO_BENCHMARK="${AVELO_BENCHMARK:-1}" \
AVELO_BENCHMARK_MILLION="${AVELO_BENCHMARK_MILLION:-$MILLION}" \
AVELO_BENCHMARK_MILLION_BATCHED="${AVELO_BENCHMARK_MILLION_BATCHED:-$MILLION_BATCHED}" \
AVELO_BENCHMARK_MILLION_COUNT="${AVELO_BENCHMARK_MILLION_COUNT:-$MILLION_COUNT}" \
AVELO_BENCHMARK_MILLION_PROGRESS_STEP="${AVELO_BENCHMARK_MILLION_PROGRESS_STEP:-$MILLION_PROGRESS_STEP}" \
swift test --disable-sandbox --scratch-path "$SCRATCH_DIR" --filter "$FILTER"
