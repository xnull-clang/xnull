#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/csv.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/CodecGenerated.x" "$TMP/generated/CodecGenerated.x"
diff -u "$HERE/generated/CsvGenerated.x" "$TMP/generated/CsvGenerated.x"

"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/csv.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/csv.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/CodecGenerated.x" "$TMP/generated2/CodecGenerated.x"
cmp "$TMP/generated/CsvGenerated.x" "$TMP/generated2/CsvGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/csv.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "csv_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}
cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/CsvGenerated.x"
expect_check_fail drift
cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/CsvGenerated.x"
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
        --manifest "$HERE/csv.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "csv_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_warn() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/csv.manifest.json" --generated-dir "$TMP/warn_$name" >"$TMP/$name.log" 2>&1
    grep -q "$expected" "$TMP/$name.log"
}

case_fail empty_name 'AN1601' 'package app.csv
import xdk.codec
@Serializable
class A {
    @CsvName("")
    String name
}
static Int main() { return 0 }'

case_fail duplicate 'AN1602' 'package app.csv
import xdk.codec
@Serializable
class A {
    @CsvName("x")
    String a
    @CsvName("x")
    String b
}
static Int main() { return 0 }'

case_fail not_serializable 'AN1603' 'package app.csv
import xdk.codec
class A {
    @CsvName("x")
    String a
}
static Int main() { return 0 }'

case_warn unsupported 'AN1605' 'package app.csv
import xdk.codec
@Serializable
class Inner {
    String value
    Inner(String value) {
        self.value = value
    }
}
@Serializable
class A {
    String name
    Inner nested
    A(String name, Inner nested) {
        self.name = name
        self.nested = nested
    }
}
static Int main() { return 0 }'

echo "csv_annotations: PASS"
