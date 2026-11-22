#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
for pair in \
    "src/xdk/graph/Graph.x:xdk/lib/xdk/graph/Graph.x" \
    "src/xdk/linalg/Linalg.x:xdk/lib/xdk/linalg/Linalg.x"; do
    left=${pair%%:*}
    right=${pair#*:}
    cmp -s "$ROOT/$left" "$ROOT/$right" || {
        echo "mirror_check: drift: $left != $right" >&2
        exit 1
    }
done
echo "mirror_check: PASS"
