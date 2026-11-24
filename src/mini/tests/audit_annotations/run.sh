#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/audit.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/AuditGenerated.x" "$TMP/generated/AuditGenerated.x"

grep -q '^import xdk.audit$' "$TMP/generated/AuditGenerated.x"
grep -q '^import xdk.runtime$' "$TMP/generated/AuditGenerated.x"
grep -q 'errorKindName(result.error().kind())' "$TMP/generated/AuditGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/AuditGenerated.x" "$TMP/project/generated/AuditGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/audit.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/audit.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/AuditGenerated.x" "$TMP/generated2/AuditGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/audit.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "audit_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/AuditGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/AuditGenerated.x"
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
        --manifest "$HERE/audit.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "audit_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail bad_return 'AN2101' 'package app.audit
import xdk.audit
class A {
    @Audited("a")
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail empty_action 'AN2102' 'package app.audit
import xdk.audit
class A {
    @Audited("")
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail type_target 'AN2103' 'package app.audit
import xdk.audit
@Audited("a")
class A { }
static Int main() { return 0 }'

case_fail static_method 'AN2104' 'package app.audit
import xdk.audit
class A {
    @Audited("a")
    static Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail function_param 'AN2105' 'package app.audit
import xdk.audit
class A {
    @Audited("a")
    Result<Int, Error> run(Int(Int) callback) { return Ok(1) }
}
static Int main() { return 0 }'

echo "audit_annotations: PASS"
