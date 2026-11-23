#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/extension.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/ExtensionGenerated.x" "$TMP/generated/ExtensionGenerated.x"

"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/extension.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/ExtensionGenerated.x" "$TMP/generated2/ExtensionGenerated.x"

! grep -q 'Constructor' "$ROOT/src/toolchain/annotation_platform.py"
! grep -q '"double"' "$ROOT/src/toolchain/annotation_platform.py"
! grep -q '"array"' "$ROOT/src/toolchain/annotation_platform.py"

printf '%s\n' 'package app.ext
import xdk.annotations
@Retention(Source)
@Target(Constructor)
@annotation Widen {
    final Double factor = 0.0
    final String[] tags = []
}
@Widen(1.5, ["a"])
class BadTarget {
}
static Int main() { return 0 }' >"$TMP/bad_target.x"
if python3 "$PLATFORM" generate --entry "$TMP/bad_target.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/extension.manifest.json" --generated-dir "$TMP/out_bad_target" >"$TMP/bad_target.log" 2>&1; then
    echo "annotation_extension: unknown target accepted" >&2
    exit 1
fi
grep -q AN1501 "$TMP/bad_target.log"

printf '%s\n' 'package app.ext
import xdk.annotations
@Retention(Source)
@Target(Constructor)
@annotation Widen {
    final Double factor = 0.0
    final String[] tags = []
}
class BadKind {
    BadKind(Bool flag) { }
    @Widen(true, ["a"])
    BadKind(Bool flag, Double value) { }
}
static Int main() { return 0 }' >"$TMP/bad_kind.x"
if python3 "$PLATFORM" generate --entry "$TMP/bad_kind.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/extension.manifest.json" --generated-dir "$TMP/out_bad_kind" >"$TMP/bad_kind.log" 2>&1; then
    echo "annotation_extension: unknown value kind accepted" >&2
    exit 1
fi
grep -q AN1501 "$TMP/bad_kind.log"

echo "annotation_extension: PASS"
