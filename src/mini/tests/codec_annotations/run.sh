#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/codec.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/CodecGenerated.x" "$TMP/generated/CodecGenerated.x"

"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/use_codec.x" >"$TMP/use.out"
diff -u "$HERE/use_codec.out" "$TMP/use.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/codec.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/codec.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/CodecGenerated.x" "$TMP/generated2/CodecGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/codec.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "codec_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/CodecGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/CodecGenerated.x"
expect_check_fail missing

cp -R "$HERE/generated" "$TMP/extra"
printf '// extra\n' >"$TMP/extra/Extra.x"
expect_check_fail extra

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/codec.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.gen.log" 2>&1; then
        echo "codec_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.gen.log"
}

case_fail struct_target 'AN1102' 'package app.codec
import xdk.codec
@Serializable
struct S {
    Int x
}
static Int main() { return 0 }'

case_fail list_field 'AN1102' 'package app.codec
import xdk.codec
@Serializable
class Bad {
    List<String> items
}
static Int main() { return 0 }'

case_fail duplicate_serializable 'AN1101' 'package app.codec
import xdk.codec
@Serializable
@Serializable
class Dup {
}
static Int main() { return 0 }'

case_fail function_conflict 'AN1101' 'package app.codec
import xdk.codec
@Serializable
class Conflict {
    Int ConflictToJson() {
        return 1
    }
}
static Int main() { return 0 }'

echo "codec_annotations: PASS"
