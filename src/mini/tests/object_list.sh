#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
O=$(mktemp)
E=$(mktemp)
trap 'rm -f "$O" "$E"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/object_list.x" >"$O" 2>"$E"
printf '2\nb\nx,y\ntrue\n2\nb\n' >"$E.expected"
if ! diff -u "$E.expected" "$O"; then
  cat "$E" >&2
  rm -f "$E.expected"
  exit 1
fi
rm -f "$E.expected"
echo "mini object_list: PASS"
