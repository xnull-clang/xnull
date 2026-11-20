#!/bin/sh
# Resource embedding through the mini single-file `--resources` surface.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

run_case() {
    name=$1 mode=$2 expected=$3
    src="$HERE/$name/src/main/x/main.x"
    res="$HERE/$name/src/main/resources"
    if [ "$mode" = full ]; then
        XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini build "$src" --resources "$res" -o "$D/$name" >"$D/$name.build" 2>"$D/$name.err" || {
            cat "$D/$name.err" >&2; exit 1
        }
    else
        XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine=mini build "$src" --resources "$res" -o "$D/$name" >"$D/$name.build" 2>"$D/$name.err" || {
            cat "$D/$name.err" >&2; exit 1
        }
    fi
    "$D/$name" >"$D/$name.out" 2>"$D/$name.run.err" || {
        cat "$D/$name.run.err" >&2; exit 1
    }
    printf '%s' "$expected" > "$D/$name.exp"
    diff -u "$D/$name.exp" "$D/$name.out"
    echo "PASS resource $name [$mode]"
}

run_case resources base 'true
hello resource
1
'
run_case resources_full full 'true
false
false
15
true
true
3
true
true
true
hello resource

true
3
1
'
run_case resources_cancel full 'true
true
true
true
true
'

echo "mini resources: PASS"
