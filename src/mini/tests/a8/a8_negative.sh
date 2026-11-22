#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if "$XNULL" --bootstrap --engine=mini run "$TMP/$name.x" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
        echo "a8_negative: $name compiled" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.err"
}

case_fail nonfinal 'AN0021' 'package app
@Value
class Bad {
    Int x
    Bad(Int x0) { self.x = x0 }
}
static Int main() { return 0 }'

case_fail struct 'AN0021' 'package app
@Value
struct Bad {
    Int x
}
static Int main() { return 0 }'

case_fail conflict 'AN0023' 'package app
@Data
class Bad {
    Int x
    Bad(Int x0) { self.x = x0 }
    String toString() { return "x" }
}
static Int main() { return 0 }'

case_fail ctor 'AN0022' 'package app
@Data
class Bad {
    Int x
    String y
    Bad(String y0, Int x0) { self.x = x0; self.y = y0 }
}
static Int main() { return 0 }'

echo "a8_negative: PASS"
