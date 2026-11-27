#!/bin/sh
# T0 core end-to-end gate: the core layer must work as one program.
# This gate is intentionally spec-first: xdk_core.out is the contract, not a
# snapshot of current behavior. Never weaken the program or the expected output
# to make it pass; fix the implementation.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
TMPERR="$TMP.err"
trap 'rm -f "$TMP" "$TMPERR" "$TMP.io" "$TMP.io.out" "$TMP.io.err" "$TMP.io.build"' EXIT

if ! XDK_CORE_PROBE=core-env "$XNULL" --bootstrap --engine=mini run "$HERE/xdk_core.x" >"$TMP" 2>"$TMPERR"; then
    cat "$TMPERR" >&2
    exit 1
fi

if ! diff -u "$HERE/xdk_core.out" "$TMP"; then
    echo "xdk core: FAIL (spec mismatch)" >&2
    exit 1
fi

"$XNULL" --bootstrap --engine=mini build "$HERE/xdk_io_2x.x" -o "$TMP.io" >"$TMP.io.build" 2>&1
if ! "$TMP.io" >"$TMP.io.out" 2>"$TMP.io.err"; then
    cat "$TMP.io.err" >&2
    exit 1
fi
if ! diff -u "$HERE/xdk_io_2x.out" "$TMP.io.out"; then
    echo "xdk io 2.x: FAIL (spec mismatch)" >&2
    exit 1
fi
"$HERE/type_is/run.sh"
"$HERE/generic_lambda/run.sh"
"$HERE/generic_lambda2/run.sh"

echo "xdk core: PASS"
