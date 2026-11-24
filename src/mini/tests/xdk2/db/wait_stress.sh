#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
CACHE=${XNULL_CACHE_DIR:-$ROOT/.cache/xnull}/db_wait_stress
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$CACHE"
KEY=$(cat "$HERE/db.x" "$HERE/db.out" "$HERE/MemoryFixture.x" "$ROOT/src/xdk/db/Db.x" | shasum -a 256 | awk '{print $1}')
BIN="$CACHE/db-$KEY"
if [ ! -x "$BIN" ]; then
    "$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/db.x" -o "$TMP/db" >"$TMP/build.log" 2>&1 || {
        cat "$TMP/build.log" >&2
        exit 1
    }
    cp "$TMP/db" "$BIN.part.$$"
    chmod +x "$BIN.part.$$"
    mv "$BIN.part.$$" "$BIN"
fi
# 20 independent runs, at most 10 concurrent so the gate stays under the
# wall-clock budget while also adding scheduling pressure.
round=1
while [ "$round" -le 20 ]; do
    pids=""
    batch=1
    while [ "$batch" -le 10 ] && [ "$round" -le 20 ]; do
        "$BIN" >"$TMP/out.$round" &
        pids="$pids $!"
        round=$((round + 1))
        batch=$((batch + 1))
    done
    for pid in $pids; do
        if ! wait "$pid"; then
            echo "db_wait_stress: run failed" >&2
            exit 1
        fi
    done
done
round=1
while [ "$round" -le 20 ]; do
    if ! diff -u "$HERE/db.out" "$TMP/out.$round" >"$TMP/diff.log"; then
        cat "$TMP/diff.log" >&2
        echo "db_wait_stress: failed at round $round" >&2
        exit 1
    fi
    round=$((round + 1))
done
echo "db_wait_stress: PASS (20/20)"
