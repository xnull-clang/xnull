#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
MINI=$(mktemp)
LEGACY=$(mktemp)
trap 'rm -f "$TMP" "$MINI" "$LEGACY"' EXIT

# Base Sys: source-level compatibility surface used by the CLI.
"$XNULL" --bootstrap --engine=mini run-project "$HERE/resources" > "$TMP" 2>"$TMP.err" || {
  cat "$TMP.err" >&2; exit 1
}
printf 'true\nhello resource\n1\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"
echo "mini resources base: PASS"

# Full Sys: complete Resource.x subunit (exists/size/read/text/list + error paths).
XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini run-project "$HERE/resources_full" > "$MINI" 2>"$MINI.err" || {
  cat "$MINI.err" >&2; exit 1
}
XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=legacy run-project "$HERE/resources_full" > "$LEGACY" 2>"$LEGACY.err" || {
  cat "$LEGACY.err" >&2; exit 1
}
printf 'true\nfalse\nfalse\n15\ntrue\ntrue\n3\ntrue\ntrue\ntrue\nhello resource\n\ntrue\n3\n1\n' > "$TMP.exp"
diff -u "$TMP.exp" "$MINI"
diff -u "$TMP.exp" "$LEGACY"
diff -u "$MINI" "$LEGACY"
echo "mini resources full: PASS"

# Full Sys + Context: cancelled operations return Err, not data.
XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini run-project "$HERE/resources_cancel" > "$TMP" 2>"$TMP.err" || {
  cat "$TMP.err" >&2; exit 1
}
printf 'true\ntrue\ntrue\ntrue\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"
echo "mini resources cancel: PASS"

echo "mini resources: PASS"
