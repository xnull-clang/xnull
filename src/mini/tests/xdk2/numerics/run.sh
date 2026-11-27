#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/numerics.x" -o "$TMP/numerics" >"$TMP/build.log" 2>&1
python3 - "$TMP/numerics" "$TMP/run.out" <<'PY'
import subprocess
import sys
try:
    with open(sys.argv[2], "wb") as out:
        subprocess.run([sys.argv[1]], stdout=out, stderr=subprocess.PIPE, timeout=5, check=True)
except subprocess.TimeoutExpired:
    print("numerics: watchdog timeout (5s)", file=sys.stderr)
    sys.exit(1)
PY
diff -u "$HERE/numerics.out" "$TMP/run.out"
echo "numerics: PASS"

"$XNULL" --bootstrap --engine=mini build "$HERE/transcendental.x" -o "$TMP/transcendental" >"$TMP/build2.log" 2>&1
python3 - "$TMP/transcendental" "$TMP/transcendental.out" <<'PY'
import subprocess
import sys
try:
    with open(sys.argv[2], "wb") as out:
        subprocess.run([sys.argv[1]], stdout=out, stderr=subprocess.PIPE, timeout=5, check=True)
except subprocess.TimeoutExpired:
    print("numerics transcendental: watchdog timeout (5s)", file=sys.stderr)
    sys.exit(1)
PY
diff -u "$HERE/transcendental.out" "$TMP/transcendental.out"
echo "numerics transcendental: PASS"
