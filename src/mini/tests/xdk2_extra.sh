#!/bin/sh
# Slower S2 gates kept out of xdk2.sh to preserve its 120s budget.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for gate in \
    "$HERE/mirror_check.sh" \
    "$HERE/core_annotations.sh" \
    "$HERE/a8/a8_core.sh" \
    "$HERE/a8/a8_packages.sh" \
    "$HERE/a8/a8_builder.sh" \
    "$HERE/doc_gates.sh" \
    "$HERE/functional_empty/run.sh" \
    "$HERE/generic_field/run.sh" \
    "$HERE/deinit/deinit.sh" \
    "$HERE/typeuse/typeuse.sh" \
    "$HERE/xdk2/annotations_cross_package/cross_package.sh" \
    "$HERE/xdk2/graph/graph_negative.sh" \
    "$HERE/xdk2/linalg/linalg_negative.sh"; do
    [ -x "$gate" ] || { echo "xdk2_extra: missing gate: $gate" >&2; exit 1; }
    if ! out=$("$gate" 2>&1); then
        printf '%s\n' "$out" >&2
        echo "xdk2_extra: gate failed: $gate" >&2
        exit 1
    fi
    printf '%s\n' "$out"
    case "$out" in
        *PASS*) ;;
        *) echo "xdk2_extra: gate produced no PASS marker: $gate" >&2; exit 1 ;;
    esac
done
echo "xdk2_extra: PASS"
