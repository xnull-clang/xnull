#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cache.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/CacheGenerated.x" "$TMP/generated/CacheGenerated.x"

grep -q '^import xdk.cache$' "$TMP/generated/CacheGenerated.x"
grep -q '^import xdk.errors$' "$TMP/generated/CacheGenerated.x"
grep -q 'String key = "u:"' "$TMP/generated/CacheGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/CacheGenerated.x" "$TMP/project/generated/CacheGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cache.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cache.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/CacheGenerated.x" "$TMP/generated2/CacheGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/cache.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "cache_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/CacheGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/CacheGenerated.x"
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
        --manifest "$HERE/cache.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "cache_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail bad_return 'AN2001' 'package app.cache
import xdk.cache
class A {
    @Cacheable("x")
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail two_annotations 'AN2002' 'package app.cache
import xdk.cache
class A {
    @Cacheable("x")
    @CacheEvict("x")
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail type_target 'AN2003' 'package app.cache
import xdk.cache
@Cacheable("x")
class A { }
static Int main() { return 0 }'

case_fail empty_value 'AN2004' 'package app.cache
import xdk.cache
class A {
    @Cacheable("")
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

echo "cache_annotations: PASS"
