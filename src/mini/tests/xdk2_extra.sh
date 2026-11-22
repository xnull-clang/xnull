#!/bin/sh
# Slower S2 gates kept out of xdk2.sh to preserve its 120s budget.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for gate in \
    "$HERE/functional_empty/run.sh" \
    "$HERE/deinit/deinit.sh" \
    "$HERE/typeuse/typeuse.sh" \
    "$HERE/xdk2/annotations_cross_package/cross_package.sh"; do
    [ -x "$gate" ] || { echo "xdk2_extra: missing gate: $gate" >&2; exit 1; }
    "$gate"
done
echo "xdk2_extra: PASS"
