#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
ANNOTATION_GATE_CHAIN=0 "$HERE/../annotation_platform/m0_gate.sh"
"$HERE/run.sh"
grep -q '| M16.4 |.*implemented (M16.4)' "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md"
echo "m16_4_gate: PASS"
