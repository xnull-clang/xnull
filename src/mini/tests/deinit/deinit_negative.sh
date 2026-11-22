#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if "$XNULL" --bootstrap --engine=mini run "$TMP/$name.x" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
        echo "deinit negative: $name compiled" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.err"
}

case_fail param 'deinit cannot have parameters' 'package app
class R { deinit(Int x) { } }
static Int main() { return 0 }'
case_fail ret 'deinit cannot declare a return type' 'package app
class R { Void deinit() { } }
static Int main() { return 0 }'
case_fail static 'deinit cannot be static' 'package app
class R { static deinit() { } }
static Int main() { return 0 }'
case_fail vis 'deinit cannot have a visibility modifier' 'package app
class R { public deinit() { } }
static Int main() { return 0 }'
case_fail dup 'duplicate deinit' 'package app
class R { deinit() { } deinit() { } }
static Int main() { return 0 }'
case_fail struct 'deinit is only allowed in class' 'package app
struct R { deinit() { } }
static Int main() { return 0 }'
case_fail enum 'deinit is only allowed in class' 'package app
enum R { deinit() { } }
static Int main() { return 0 }'
case_fail protocol 'deinit is only allowed in class' 'package app
protocol R { deinit(); }
static Int main() { return 0 }'
case_fail call 'deinit cannot be called explicitly' 'package app
class R { deinit() { } }
static Int main() { R r = new R(); r.deinit(); return 0 }'

echo "deinit negative: PASS"
