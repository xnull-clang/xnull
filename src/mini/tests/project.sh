#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for engine in mini auto legacy; do
  "$XNULL" --bootstrap --engine="$engine" run-project "$HERE/project" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
  }
  grep -q '^project ok$' "$TMP"
done
echo "mini project: PASS"
