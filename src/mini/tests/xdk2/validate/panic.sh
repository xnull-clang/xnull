#!/bin/sh
# xdk.validate contract panics: invalid bounds, empty names, unknown fields, null errors.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/panic.x" <<'X'
import xdk.codec
import xdk.validate
static Int main(String[] args) {
    String name = args.get(0)
    if name == "minLength" {
        Rules.minLength(-1)
    } else if name == "oneOf" {
        List<String> empty = []
        Rules.oneOf(empty)
    } else if name == "error" {
        ValidationError bad = new ValidationError("", "", "m")
    } else if name == "addNull" {
        ValidationResult result = new ValidationResult()
        result.add(null)
    } else if name == "duplicate" {
        Schema schema = new Schema()
        schema.field("a", Rules.string())
        schema.field("a", Rules.string())
    } else if name == "unknownField" {
        Schema schema = new Schema()
        schema.field("a", Rules.string())
        schema.validateField("missing", Json.parse("1").value())
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || {
    cat "$TMP/build.err" >&2
    echo "validate panic: build failed" >&2
    exit 1
}

check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && {
        echo "validate panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "validate panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}

check_panic "minLength" "Rules.minLength: negative length"
check_panic "oneOf" "Rules.oneOf: empty allowed list"
check_panic "error" "ValidationError: empty code"
check_panic "addNull" "ValidationResult.add: null"
check_panic "duplicate" "Schema.field: duplicate name"
check_panic "unknownField" "Schema.validateField: unknown field"

echo "validate_panic: PASS"
