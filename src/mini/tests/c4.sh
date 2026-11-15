#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
O=$(mktemp)
E=$(mktemp)
trap 'rm -f "$O" "$E" "$E.expected"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/features.x" >"$O" 2>"$E"
printf 'x=1.5 bits=243\nnone\n3\n' >"$E.expected"
diff -u "$E.expected" "$O" || { cat "$E" >&2; exit 1; }
"$ROOT/src/mini/bin/mini" --sema "$HERE/throw.x" >/dev/null
echo "mini c4: PASS"
