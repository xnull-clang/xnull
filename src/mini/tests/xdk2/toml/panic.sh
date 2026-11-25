#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.toml
import xdk.toml
import xdk.codec
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    TomlOptions options = new TomlOptions()
    if name == "parseNull" {
        Result<JsonValue, Error> value = Toml.parse(null)
    } else if name == "parseOptionsNull" {
        Result<JsonValue, Error> value = Toml.parseWithOptions("a = 1", null)
    } else if name == "parseTextNull" {
        Result<JsonValue, Error> value = Toml.parseWithOptions(null, options)
    } else if name == "stringifyNull" {
        Result<String, Error> value = Toml.stringify(null)
    } else if name == "stringifyOptionsNull" {
        Result<String, Error> value = Toml.stringifyWithOptions(Json.object(), null)
    } else if name == "stringifyValueNull" {
        Result<String, Error> value = Toml.stringifyWithOptions(null, options)
    } else if name == "depthZero" {
        options.maxDepth(0)
    } else if name == "depthNegative" {
        options.maxDepth(-1)
    } else if name == "bytesZero" {
        options.maxBytes(0 as Long)
    } else if name == "bytesNegative" {
        options.maxBytes(-1 as Long)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "toml panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "toml panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic parseNull "Toml.parse: null argument"
check_panic parseOptionsNull "Toml.parse: null argument"
check_panic parseTextNull "Toml.parse: null argument"
check_panic stringifyNull "Toml.stringify: null argument"
check_panic stringifyOptionsNull "Toml.stringify: null argument"
check_panic stringifyValueNull "Toml.stringify: null argument"
check_panic depthZero "TomlOptions.maxDepth: must be positive"
check_panic depthNegative "TomlOptions.maxDepth: must be positive"
check_panic bytesZero "TomlOptions.maxBytes: must be positive"
check_panic bytesNegative "TomlOptions.maxBytes: must be positive"
echo "toml_panic: PASS"
