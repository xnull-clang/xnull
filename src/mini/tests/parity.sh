#!/bin/sh
# Selected legacy/mini parity matrix (D6).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
cleanup() { rm -rf "$D"; }
trap cleanup EXIT

cases='
src/examples/hello.x
src/examples/ast-seed.x
src/examples/classes.x
src/examples/defer-cleanup.x
src/examples/objlist.x
src/examples/result-try.x
src/mini/tests/array.x
src/mini/tests/flow.x
src/mini/tests/class_basic.x
src/mini/tests/object_list.x
src/mini/tests/xdk_errors.x
src/mini/tests/xdk_sys.x
src/mini/tests/xdk_meta.x
src/mini/tests/xdk_runtime.x
src/mini/tests/codegen_hello.x
src/mini/tests/project/src/main/x/main.x
'

fail=0
n=0
for rel in $cases; do
    [ -f "$ROOT/$rel" ] || { echo "parity: missing $rel" >&2; exit 1; }
    name=$(printf '%s' "$rel" | tr '/.' '__')
    n=$((n + 1))
    for engine in legacy mini; do
        out="$D/$name.$engine"
        "$XNULL" --bootstrap --engine="$engine" build "$ROOT/$rel" -o "$out.bin" \
            >"$out.build.out" 2>"$out.build.err" || {
            echo "parity: $rel [$engine] build failed" >&2
            cat "$out.build.err" >&2
            fail=1
            break 2
        }
        set +e
        "$out.bin" >"$out.stdout" 2>"$out.stderr"
        echo $? >"$out.exit"
        set -e
    done
    if ! cmp -s "$D/$name.legacy.stdout" "$D/$name.mini.stdout"; then
        echo "parity: $rel stdout differs" >&2
        diff -u "$D/$name.legacy.stdout" "$D/$name.mini.stdout" >&2 || true
        fail=1
    fi
    if ! cmp -s "$D/$name.legacy.stderr" "$D/$name.mini.stderr"; then
        echo "parity: $rel stderr differs" >&2
        diff -u "$D/$name.legacy.stderr" "$D/$name.mini.stderr" >&2 || true
        fail=1
    fi
    if ! cmp -s "$D/$name.legacy.exit" "$D/$name.mini.exit"; then
        echo "parity: $rel exit differs: $(cat "$D/$name.legacy.exit") / $(cat "$D/$name.mini.exit")" >&2
        fail=1
    fi
done

echo "mini parity: cases=$n diff=$fail"
[ "$fail" -eq 0 ]
