#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

base='package app
import xdk.annotations

@Retention(Runtime)
@Target(TypeUse)
@annotation TU { }
class Payload { }
'

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s' "$src" >"$TMP/$name.x"
    if "$XNULL" --bootstrap --engine=mini run "$TMP/$name.x" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
        echo "typeuse negative: $name compiled" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.err"
}

case_fail mixed 'ambiguous annotation @Mixed' 'package app
import xdk.annotations
@Retention(Runtime)
@Target(TypeUse, Field)
@annotation Mixed { }
class Box { @Mixed String name }
static Int main() { return 0 }'

case_fail on_class 'AN0002' 'package app
import xdk.annotations
@Retention(Runtime)
@Target(TypeUse)
@annotation TU { }
@TU
class Box { }
static Int main() { return 0 }'

case_fail field_on_local 'annotation @ReadOnly is not allowed on Local' 'package app
import xdk.annotations
static Int main() { @ReadOnly Int x = 1; return x }'

case_fail generic_arg 'unknown field type' "${base}"'
class Box { List<@TU String> names = [] }
static Int main() { return 0 }'

case_fail expression 'annotation @TU is not allowed on Expression' "${base}"'
static Int main() { Int x = @TU 1; return x }'

case_fail duplicate 'duplicate annotation @TU (not @Repeatable)' "${base}"'
class Box { @TU @TU Payload field }
static Int main() { return 0 }'

echo "typeuse negative: PASS"
