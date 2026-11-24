#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/test.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/TestGenerated.x" "$TMP/generated/TestGenerated.x"

grep -q '^import xdk.test$' "$TMP/generated/TestGenerated.x"
grep -q '^import xdk.errors$' "$TMP/generated/TestGenerated.x"
grep -q 'TestSuite UserTestsSuite(UserTests target)' "$TMP/generated/TestGenerated.x"
grep -q 'List<Test> UserTestsBenchmarks(UserTests target)' "$TMP/generated/TestGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/TestGenerated.x" "$TMP/project/generated/TestGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/test.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/test.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/TestGenerated.x" "$TMP/generated2/TestGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/test.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "test_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/TestGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/TestGenerated.x"
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
        --manifest "$HERE/test.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "test_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail method_params 'AN2201' 'package app.tests
import xdk.test
class A {
    @TestCase
    void run(Int value) { }
}
static Int main() { return 0 }'

case_fail static_method 'AN2201' 'package app.tests
import xdk.test
class A {
    @TestCase
    static void run() { }
}
static Int main() { return 0 }'

case_fail unsupported_return 'AN2202' 'package app.tests
import xdk.test
class A {
    @TestCase
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail duplicate_before 'AN2203' 'package app.tests
import xdk.test
class A {
    @Before
    void one() { }
    @Before
    void two() { }
    @TestCase
    void run() { }
}
static Int main() { return 0 }'

printf '%s\n' 'package app.tests
import xdk.test
class A {
    @Before
    void setUp() { }
}
static Int main() { return 0 }' >"$TMP/warning.x"
python3 "$PLATFORM" generate --entry "$TMP/warning.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/test.manifest.json" --generated-dir "$TMP/out_warning" >"$TMP/warning.log" 2>&1
grep -q 'AN2204' "$TMP/warning.log"

echo "test_annotations: PASS"
