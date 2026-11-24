#!/bin/sh
# Slower S2 gates kept out of xdk2.sh to preserve its 120s budget.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for gate in \
    "$HERE/mirror_check.sh" \
    "$HERE/annotation_ir/run.sh" \
    "$HERE/annotation_platform/run.sh" \
    "$HERE/core_annotations.sh" \
    "$HERE/a8/a8_packages.sh" \
    "$HERE/a8/a8_delegate.sh" \
    "$HERE/doc_gates.sh" \
    "$HERE/functional_empty/run.sh" \
    "$HERE/generic_field/run.sh" \
    "$HERE/deinit/deinit.sh" \
    "$HERE/typeuse/typeuse.sh" \
    "$HERE/xdk2/annotations_cross_package/cross_package.sh" \
    "$HERE/xdk2/graph/graph_negative.sh" \
    "$HERE/xdk2/linalg/linalg_negative.sh" \
    "$HERE/xdk2/validate/panic.sh" \
    "$HERE/xdk2/http/panic.sh" \
    "$HERE/xdk2/sql/panic.sh" \
    "$HERE/xdk2/runtime_health/panic.sh" \
    "$HERE/xdk2/db/panic.sh" \
    "$HERE/xdk2/db/fixture_check.sh" \
    "$HERE/xdk2/db/wait_stress.sh" \
    "$HERE/xdk2/resilience/panic.sh" \
    "$HERE/xdk2/cache/panic.sh" \
    "$HERE/xdk2/audit/panic.sh" \
    "$HERE/xdk2/metrics/panic.sh" \
    "$HERE/xdk2/trace/panic.sh" \
    "$HERE/xdk2/crypto/panic.sh" \
    "$HERE/xdk2/jwt/panic.sh" \
    "$HERE/xdk2/auth/panic.sh" \
    "$HERE/xdk2/test/panic.sh"; do
    [ -x "$gate" ] || { echo "xdk2_extra: missing gate: $gate" >&2; exit 1; }
    gate_start=$(date +%s)
    if ! out=$("$gate" 2>&1); then
        printf '%s\n' "$out" >&2
        echo "xdk2_extra: gate failed: $gate" >&2
        exit 1
    fi
    printf '%s\n' "$out"
    gate_end=$(date +%s)
    echo "xdk2_extra: time=$((gate_end - gate_start))s gate=$(basename "$gate")"
    case "$out" in
        *PASS*) ;;
        *) echo "xdk2_extra: gate produced no PASS marker: $gate" >&2; exit 1 ;;
    esac
done
echo "xdk2_extra: PASS"
