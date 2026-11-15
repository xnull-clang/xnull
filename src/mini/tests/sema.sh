#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
MINI="$ROOT/src/mini/mini"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$MINI" --sema "$HERE/sema_good.x" > "$TMP"
grep -q '^sema ok$' "$TMP"

if "$MINI" --sema "$HERE/sema_undef.x" > "$TMP" 2>&1; then
    echo "expected undefined-symbol failure" >&2; exit 1
fi
grep -q 'SEM-001.*undefined symbol: missing' "$TMP"

if "$MINI" --sema "$HERE/sema_type.x" > "$TMP" 2>&1; then
    echo "expected type failure" >&2; exit 1
fi
grep -q 'SEM-003.*cannot initialize Int with String' "$TMP"

if "$MINI" --sema "$HERE/sema_arity.x" > "$TMP" 2>&1; then
    echo "expected arity failure" >&2; exit 1
fi
grep -q 'SEM-004.*expects 2 arguments, got 1' "$TMP"

echo "mini sema: PASS"
