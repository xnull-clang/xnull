#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/resilience.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/ResilienceGenerated.x" "$TMP/generated/ResilienceGenerated.x"

grep -q '^import xdk.resilience$' "$TMP/generated/ResilienceGenerated.x"
grep -q '^import xdk.errors$' "$TMP/generated/ResilienceGenerated.x"
grep -q 'circuit=svc threshold=2' "$TMP/generated/ResilienceGenerated.x"
grep -q 'rate=svc permits=1 perMillis=1000' "$TMP/generated/ResilienceGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/ResilienceGenerated.x" "$TMP/project/generated/ResilienceGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/resilience.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/resilience.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/ResilienceGenerated.x" "$TMP/generated2/ResilienceGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/resilience.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "resilience_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/ResilienceGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/ResilienceGenerated.x"
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
        --manifest "$HERE/resilience.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "resilience_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail bad_return 'AN1901' 'package app.svc
import xdk.resilience
import xdk.errors
class A {
    @Retryable(3, 1)
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail two_policies 'AN1902' 'package app.svc
import xdk.resilience
import xdk.errors
class A {
    @Retryable(3, 1)
    @TimeoutPolicy(10)
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail function_param 'AN1903' 'package app.svc
import xdk.resilience
import xdk.errors
class A {
    @Retryable(3, 1)
    Result<Int, Error> run(Int(Int) callback) { return Ok(1) }
}
static Int main() { return 0 }'

case_fail static_method 'AN1903' 'package app.svc
import xdk.resilience
import xdk.errors
class A {
    @Retryable(3, 1)
    static Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail type_target 'AN1904' 'package app.svc
import xdk.resilience
@Retryable(3, 1)
class A {
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

echo "resilience_annotations: PASS"
