#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
PROCESSOR="$ROOT/src/toolchain/processors/auth_processor.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/AuthGenerated.x" "$TMP/generated/AuthGenerated.x"
grep -q 'UserApi_apiKeyOnlyAuthorized(UserApi target, Principal principal, Int id)' "$TMP/generated/AuthGenerated.x"
grep -q 'authentication scheme required: jwt' "$TMP/generated/AuthGenerated.x"
grep -q 'missing role: admin' "$TMP/generated/AuthGenerated.x"
grep -q 'missing permission: user:read' "$TMP/generated/AuthGenerated.x"
grep -q 'missing claim: tenant' "$TMP/generated/AuthGenerated.x"
if grep -q 'UserApi_openAuthorized' "$TMP/generated/AuthGenerated.x"; then
    echo "auth_annotations: AllowAnonymous was wrapped" >&2
    exit 1
fi

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/AuthGenerated.x" "$TMP/project/generated/AuthGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$HERE/generated" >/dev/null
python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/AuthGenerated.x" "$TMP/generated2/AuthGenerated.x"

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/auth.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "auth_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail empty_role 'AN2702' 'package app.authneg
import xdk.auth
class A {
    @RequireRole("")
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail static_method 'AN2703' 'package app.authneg
import xdk.auth
class A {
    @RequireRole("admin")
    static Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

case_fail bad_return 'AN2703' 'package app.authneg
import xdk.auth
class A {
    @RequireRole("admin")
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail allow_conflict 'AN2704' 'package app.authneg
import xdk.auth
class A {
    @AllowAnonymous
    @RequireRole("admin")
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

# Synthetic IR for target-level diagnostics that the compiler rejects earlier.
synthetic() {
    name="$1"
    code="$2"
    target="$3"
    cat >"$TMP/$name.ir" <<JSON
{"irVersion":2,"declarations":[],"uses":[{"name":"X","resolvedName":"$code","target":"$target","targetName":"app.X#f","arguments":[{"kind":"string","text":"x"}],"line":1,"col":1,"repeatIndex":1}],"symbols":{"types":[]}}
JSON
    mkdir -p "$TMP/$name.out"
    python3 "$PROCESSOR" --phase Generate --ir "$TMP/$name.ir" --out "$TMP/$name.out" >/dev/null 2>&1
    grep -q "$name" "$TMP/$name.out/diagnostics.json"
}
synthetic AN2701 'xdk.auth.Auth' Field
synthetic AN2706 'xdk.auth.AllowAnonymous' Type
synthetic AN2707 'xdk.auth.RequireRole' Type

printf '%s\n' 'package app.authneg
import xdk.auth
class A {
    @RequireRole("admin")
    @RequireRole("admin")
    Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }' >"$TMP/warn.x"
python3 "$PLATFORM" generate --entry "$TMP/warn.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$TMP/warn_out" >"$TMP/warn.log" 2>&1
grep -q 'AN2705' "$TMP/warn.log"
test "$(grep -c 'hasRole("admin")' "$TMP/warn_out/AuthGenerated.x")" -eq 1

echo "auth_annotations: PASS"
