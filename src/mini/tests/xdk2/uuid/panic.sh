#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.uuid
import xdk.uuid
import xdk.errors
import xdk.bytes

static Int main(String[] args) {
    String name = args.get(0)
    if name == "uuidBytes" {
        Uuid value = Uuid.fromBytes(Bytes.alloc(15))
    } else if name == "uuidParseNull" {
        Result<Uuid, Error> value = Uuid.parse(null)
    } else if name == "uuidCompareNull" {
        Uuid value = Uuid.v4().value()
        Int result = value.compare(null)
    } else if name == "ulidBytes" {
        Ulid value = Ulid.fromBytes(Bytes.alloc(15))
    } else if name == "ulidParseNull" {
        Result<Ulid, Error> value = Ulid.parse(null)
    } else if name == "ulidCompareNull" {
        Ulid value = Ulid.generate(false).value()
        Int result = value.compare(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "uuid panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "uuid panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic uuidBytes "Uuid: invalid bytes"
check_panic uuidParseNull "Uuid.parse: null text"
check_panic uuidCompareNull "Uuid.compare: null"
check_panic ulidBytes "Ulid: invalid bytes"
check_panic ulidParseNull "Ulid.parse: null text"
check_panic ulidCompareNull "Ulid.compare: null"
echo "uuid_panic: PASS"
