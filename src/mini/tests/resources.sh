#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
"$XNULL" --bootstrap --engine=mini run-project "$HERE/resources" > "$TMP" 2>"$TMP.err" || {
  cat "$TMP.err" >&2; exit 1
}
printf 'true\nhello resource\n1\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"
echo "mini resources: PASS"
