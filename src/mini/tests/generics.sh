#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
O=$(mktemp)
E=$(mktemp)
trap 'rm -f "$O" "$E" "$E.expected"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/generics.x" >"$O" 2>"$E"
printf '7\ngeneric\n9\nboxed\n' >"$E.expected"
diff -u "$E.expected" "$O" || { cat "$E" >&2; exit 1; }
echo "mini generics: PASS"
