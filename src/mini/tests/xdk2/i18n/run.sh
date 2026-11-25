#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/i18n.x" -o "$TMP/i18n" >"$TMP/build.log" 2>&1
python3 - "$TMP/i18n" "$TMP/run.out" <<'PY'
import subprocess
import sys
try:
    with open(sys.argv[2], "wb") as out:
        subprocess.run([sys.argv[1]], stdout=out, stderr=subprocess.PIPE, timeout=5, check=True)
except subprocess.TimeoutExpired:
    print("i18n: watchdog timeout (5s)", file=sys.stderr)
    sys.exit(1)
PY
diff -u "$HERE/i18n.out" "$TMP/run.out"
echo "i18n: PASS"
