#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BOARD="$ROOT_DIR/Docs/Avelo_Release_Board.md"
QUEUE="$ROOT_DIR/Docs/Avelo_Execution_Checklist.md"
PLAN="$ROOT_DIR/Docs/Avelo_Master_Product_Execution_Plan.md"
STATUS="$ROOT_DIR/Docs/Avelo_Status_Checklist.md"
MODULES="$ROOT_DIR/Docs/Avelo_Module_Checklist.md"

CHECK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/avelo-docs-check.XXXXXX")
trap 'rm -rf "$CHECK_TMP"' EXIT HUP INT TERM

fail() {
    printf 'DOCS CHECK FAIL: %s\n' "$1" >&2
    exit 1
}

for required in "$BOARD" "$QUEUE" "$PLAN" "$STATUS" "$MODULES"; do
    [ -f "$required" ] || fail "missing required coordination document: $required"
done

awk '
    /^### P0 / { section = "P0"; next }
    /^### P1 / { section = "P1"; next }
    /^### P2 / { section = "P2"; next }
    /^### Shortcut/ { section = "" }
    section != "" && /^\| AVL-P[012]-[0-9]+ / {
        id = $2
        gsub(/^ +| +$/, "", id)
        print id
        count[section]++
    }
    END {
        printf "%d\n", count["P0"] > p0_file
        printf "%d\n", count["P1"] > p1_file
        printf "%d\n", count["P2"] > p2_file
    }
' p0_file="$CHECK_TMP/p0" p1_file="$CHECK_TMP/p1" p2_file="$CHECK_TMP/p2" "$BOARD" | sort > "$CHECK_TMP/board_ids"

for severity in P0 P1 P2; do
    severity_lower=$(printf '%s' "$severity" | tr '[:upper:]' '[:lower:]')
    actual_count=$(cat "$CHECK_TMP/$severity_lower")
    heading_count=$(sed -n "s/^### $severity .* (\([0-9][0-9]*\) .*)$/\1/p" "$BOARD")
    [ -n "$heading_count" ] || fail "$severity heading must include its unresolved count"
    [ "$actual_count" = "$heading_count" ] || fail "$severity heading says $heading_count but canonical table contains $actual_count rows"
done

duplicate_board_ids=$(uniq -d "$CHECK_TMP/board_ids" || true)
[ -z "$duplicate_board_ids" ] || fail "duplicate canonical board IDs: $duplicate_board_ids"

awk '
    /^## Current proof notes/ { exit }
    /^\| [^|]+ \| (Implementation remaining|Proof remaining|Manual acceptance remaining|Policy excluded|Closed|Open) \|/ {
        id = $2
        gsub(/^ +| +$/, "", id)
        print id
    }
' "$QUEUE" | sort > "$CHECK_TMP/queue_ids"

invalid_queue_ids=$(grep -Ev '^AVL-P[012]-[0-9]+$' "$CHECK_TMP/queue_ids" || true)
[ -z "$invalid_queue_ids" ] || fail "queue rows must use canonical AVL IDs: $invalid_queue_ids"

duplicate_queue_ids=$(uniq -d "$CHECK_TMP/queue_ids" || true)
[ -z "$duplicate_queue_ids" ] || fail "duplicate executable queue IDs: $duplicate_queue_ids"

unknown_queue_ids=$(comm -23 "$CHECK_TMP/queue_ids" "$CHECK_TMP/board_ids" || true)
[ -z "$unknown_queue_ids" ] || fail "queue IDs missing from release board: $unknown_queue_ids"

for coordinated_doc in "$PLAN" "$BOARD" "$QUEUE" "$STATUS"; do
    rg -q 'AVL-P1-045' "$coordinated_doc" || fail "V027-V029 canonical slice lost its ID in $coordinated_doc"
done
rg -q 'live filesystem is the authority for file inventory' "$MODULES" || fail "module checklist reverted to a handwritten file manifest"

printf 'DOCS CHECK PASS\n'
printf 'Canonical backlog: P0=%s P1=%s P2=%s\n' "$(cat "$CHECK_TMP/p0")" "$(cat "$CHECK_TMP/p1")" "$(cat "$CHECK_TMP/p2")"
printf 'Executable queue rows: %s\n' "$(wc -l < "$CHECK_TMP/queue_ids" | tr -d ' ')"
