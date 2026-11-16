#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
O=$(mktemp)
E=$(mktemp)
trap 'rm -f "$O" "$E" "$E.expected" /tmp/xnull-m7-sys-test.txt /tmp/xnull-m7-missing.txt' EXIT

XNULL_MINI_XDK_FULL=1 "$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/m7_sys.x" >"$O" 2>"$E"
printf '10\nalpha\nbeta\n10\ntrue\ntrue\nhi\n3\nfalse\n' >"$E.expected"
diff -u "$E.expected" "$O" || { cat "$E" >&2; exit 1; }

echo "mini m7-sys: PASS"
