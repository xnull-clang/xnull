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
        echo "builder_negative: $name compiled" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.err"
}

case_fail struct 'AN0021' 'package app
@Builder
struct Bad { Int x }
static Int main() { return 0 }'

case_fail generic 'AN0025' 'package app
@Builder
class Box<T> {
    final T value
    Box(T value0) { self.value = value0 }
}
static Int main() { return 0 }'

case_fail exists 'AN0024' 'package app
@Builder
class ServerConfig {
    final String host
    ServerConfig(String host) { self.host = host }
}
class ServerConfigBuilder { }
static Int main() { return 0 }'

case_fail ctor 'AN0022' 'package app
@Builder
class Bad {
    String host
    Int port
    Bad(Int port0, String host0) { self.host = host0; self.port = port0 }
}
static Int main() { return 0 }'

if "$XNULL" --bootstrap --engine=mini run "$HERE/builder_missing.x" >"$TMP/missing.out" 2>"$TMP/missing.err"; then
    echo "builder_negative: missing field build passed" >&2
    exit 1
fi
grep -q 'ServerConfigBuilder.build: missing field port' "$TMP/missing.err"
echo "builder_negative: PASS"
