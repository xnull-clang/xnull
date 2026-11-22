#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
MINI="$ROOT/src/mini/bin/mini"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$MINI" --dump-annotations "$HERE/source.x" --xdk-root "$ROOT/src/xdk" >"$TMP/actual.json"
diff -u "$HERE/expected.json" "$TMP/actual.json"

# Field order / IR version / symbols / no absolute paths.
grep -q '"irVersion":2,"declarations":' "$TMP/actual.json"
grep -q '"symbols":{"types":' "$TMP/actual.json"
"$MINI" --dump-annotations "$HERE/source.x" --xdk-root "$ROOT/src/xdk" >"$TMP/actual2.json"
cmp "$TMP/actual.json" "$TMP/actual2.json"
printf '%s\n' '{"irVersion":1,"declarations":[],"uses":[]}' > "$TMP/v1.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["irVersion"] == 1 and "symbols" not in d' "$TMP/v1.json"
if grep -q "$ROOT" "$TMP/actual.json"; then
    echo "annotation_ir: absolute path leaked into JSON" >&2
    exit 1
fi

cat > "$TMP/unknown.x" <<'X'
package app
@Unknown
class Device { }
static Int main() { return 0 }
X
if "$MINI" --sema "$TMP/unknown.x" --xdk-root "$ROOT/src/xdk" >"$TMP/u.log" 2>&1; then
    echo "annotation_ir: unknown annotation accepted" >&2
    exit 1
fi
grep -q 'unknown annotation' "$TMP/u.log"

cat > "$TMP/wrong.x" <<'X'
package app
import xdk.annotations
@Target(Field)
@annotation OnlyField { }
@OnlyField
class Device { }
static Int main() { return 0 }
X
if "$MINI" --sema "$TMP/wrong.x" --xdk-root "$ROOT/src/xdk" >"$TMP/w.log" 2>&1; then
    echo "annotation_ir: wrong target accepted" >&2
    exit 1
fi
grep -q 'AN0002' "$TMP/w.log"

echo "annotation_ir: PASS"
