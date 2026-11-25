#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.os
import xdk.os

static OsInfo sampleInfo() {
    return new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
        "6.1.0", "x86_64", "host", "", "glibc", false)
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "infoEmptyName" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "", "1.0",
            "6.1.0", "x86_64", "host", "", "glibc", false)
    } else if name == "infoEmptyArch" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
            "6.1.0", "", "host", "", "glibc", false)
    } else if name == "infoNullVersion" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", null,
            "6.1.0", "x86_64", "host", "", "glibc", false)
    } else if name == "infoNullSession" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Unix, "TestOS", "1.0",
            "6.1.0", "x86_64", "host", null, "glibc", false)
    } else if name == "infoFamilyMismatch" {
        OsInfo info = new OsInfo(OsKind.Linux, OsFamily.Windows, "TestOS", "1.0",
            "6.1.0", "x86_64", "host", "", "glibc", false)
    } else if name == "profileEmptyName" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("", sampleInfo(), caps)
    } else if name == "profileNullInfo" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("p", null, caps)
    } else if name == "profileNullCaps" {
        OsProfile profile = new OsProfile("p", sampleInfo(), null)
    } else if name == "profileWithName" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("p", sampleInfo(), caps)
        OsProfile renamed = profile.withName("")
    } else if name == "profileMissing" {
        List<OsCapability> caps = []
        OsProfile profile = new OsProfile("p", sampleInfo(), caps)
        List<OsCapability> missing = profile.missing(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "os panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "os panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic infoEmptyName "OsInfo: empty name"
check_panic infoEmptyArch "OsInfo: empty architecture"
check_panic infoNullVersion "OsInfo: null string"
check_panic infoNullSession "OsInfo: null string"
check_panic infoFamilyMismatch "OsInfo: family does not match kind"
check_panic profileEmptyName "OsProfile: empty name"
check_panic profileNullInfo "OsProfile: null field"
check_panic profileNullCaps "OsProfile: null field"
check_panic profileWithName "OsProfile.withName: empty"
check_panic profileMissing "OsProfile.missing: null list"
echo "os_panic: PASS"
