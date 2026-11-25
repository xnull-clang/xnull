#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.time_extra
import xdk.time
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    if name == "secondsOverflow" {
        Instant value = Instant.ofEpochSeconds(9223372036854776 as Long)
    } else if name == "secondsUnderflow" {
        Long negative = 0 as Long - 9223372036854776 as Long
        Instant value = Instant.ofEpochSeconds(negative)
    } else if name == "plusNull" {
        Instant value = Instant.ofEpochMillis(0 as Long).plus(null)
    } else if name == "minusNull" {
        Instant value = Instant.ofEpochMillis(0 as Long).minus(null)
    } else if name == "beforeNull" {
        Bool value = Instant.ofEpochMillis(0 as Long).isBefore(null)
    } else if name == "afterNull" {
        Bool value = Instant.ofEpochMillis(0 as Long).isAfter(null)
    } else if name == "compareNull" {
        Int value = Instant.ofEpochMillis(0 as Long).compare(null)
    } else if name == "zoneHigh" {
        TimeZone zone = TimeZone.fixed(64800001)
    } else if name == "zoneLow" {
        TimeZone zone = TimeZone.fixed(-64800001)
    } else if name == "offsetAtNull" {
        Int value = TimeZone.utc().offsetAt(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "time panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "time panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic secondsOverflow "Instant: overflow"
check_panic secondsUnderflow "Instant: overflow"
check_panic plusNull "Instant.plus: null"
check_panic minusNull "Instant.minus: null"
check_panic beforeNull "Instant.isBefore: null"
check_panic afterNull "Instant.isAfter: null"
check_panic compareNull "Instant.compare: null"
check_panic zoneHigh "TimeZone: offset out of range"
check_panic zoneLow "TimeZone: offset out of range"
check_panic offsetAtNull "TimeZone.offsetAt: null"
echo "time_panic: PASS"
