#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/storage.x" -o "$TMP/storage" >"$TMP/build.log" 2>&1
python3 - "$TMP/storage" "$TMP/run.out" <<'PY'
import subprocess
import sys
try:
    with open(sys.argv[2], "wb") as out:
        subprocess.run([sys.argv[1]], stdout=out, stderr=subprocess.PIPE, timeout=5, check=True)
except subprocess.TimeoutExpired:
    print("storage: watchdog timeout (5s)", file=sys.stderr)
    sys.exit(1)
PY
diff -u "$HERE/storage.out" "$TMP/run.out"
echo "storage: PASS"
