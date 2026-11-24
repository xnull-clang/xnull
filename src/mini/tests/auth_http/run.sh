#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/AuthGenerated.x" "$TMP/generated/AuthGenerated.x"
mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/AuthGenerated.x" "$TMP/project/generated/AuthGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"
python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$HERE/generated" >/dev/null
python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/auth.manifest.json" --generated-dir "$TMP/generated2" >/dev/null 2>&1
cmp "$TMP/generated/AuthGenerated.x" "$TMP/generated2/AuthGenerated.x"
echo "auth_http: PASS"
