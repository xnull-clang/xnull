#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
diff -qr -x annotations -x execution -x xdk2-packages.tsv     "$ROOT/src/xdk" "$ROOT/xdk/lib/xdk" >/dev/null || {
    echo "mirror_check: src/xdk and xdk/lib/xdk differ" >&2
    exit 1
}
echo "mirror_check: PASS"
