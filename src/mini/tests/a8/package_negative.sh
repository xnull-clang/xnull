#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/buildinfo.x" <<'X'
import xdk.meta
static Int main() {
    BuildInfoBuilder b = new BuildInfoBuilder()
    BuildInfo info = b.withLanguageVersion("3.4.0").build()
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/buildinfo.x" >"$TMP/out" 2>"$TMP/err"; then
    echo "package_negative: BuildInfoBuilder missing field passed" >&2
    exit 1
fi
grep -q 'BuildInfoBuilder.build: missing field xdkVersion' "$TMP/err"
cat > "$TMP/runtimeinfo.x" <<'X'
import xdk.runtime
static Int main() {
    RuntimeInfoBuilder b = new RuntimeInfoBuilder()
    RuntimeInfo info = b.withLanguageVersion("3.4.0").build()
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/runtimeinfo.x" >"$TMP/out2" 2>"$TMP/err2"; then
    echo "package_negative: RuntimeInfoBuilder missing field passed" >&2
    exit 1
fi
grep -q 'RuntimeInfoBuilder.build: missing field xdkVersion' "$TMP/err2"
echo "package_negative: PASS"
