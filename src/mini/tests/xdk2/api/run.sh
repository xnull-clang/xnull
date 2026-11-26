#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$XNULL" --bootstrap --engine=mini build "$HERE/api.x" -o "$TMP/api" >"$TMP/build.log" 2>&1
python3 - "$TMP/api" "$TMP/run.out" <<'PY'
import subprocess, sys
try:
    with open(sys.argv[2], "wb") as out:
        subprocess.run([sys.argv[1]], stdout=out, stderr=subprocess.PIPE, timeout=5, check=True)
except subprocess.TimeoutExpired:
    print("api: watchdog timeout (5s)", file=sys.stderr); sys.exit(1)
PY
diff -u "$HERE/api.out" "$TMP/run.out"
echo "api: PASS"
