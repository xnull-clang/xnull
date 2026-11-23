#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    ANNOTATION_GATE_CHAIN=0 "$HERE/../annotation_platform/m0_gate.sh" >/dev/null
    ANNOTATION_GATE_CHAIN=0 "$HERE/../codec_annotations/m3_gate.sh" >/dev/null
    ANNOTATION_GATE_CHAIN=0 "$HERE/../validate_annotations/m4_gate.sh" >/dev/null
    ANNOTATION_GATE_CHAIN=0 "$HERE/../http_annotations/m5_gate.sh" >/dev/null
    ANNOTATION_GATE_CHAIN=0 "$HERE/../sql_annotations/m6_gate.sh" >/dev/null
fi
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
if ! "$HERE/run.sh" >"$LOG" 2>&1; then
    echo "m2_gate: FAIL cli_annotations" >&2
    tail -60 "$LOG" >&2
    exit 1
fi
grep -q '^cli_annotations: PASS$' "$LOG"
python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" <<'PY'
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(encoding='utf-8')
for n in (1,2,3):
    if not re.search(rf"^\| P2-0{n} \|.*\|\s*implemented[^|]*\|", text, flags=re.M):
        raise SystemExit(f"m2_gate: P2-0{n} not implemented")
if not re.search(r"^\| M2 \|.*\|\s*implemented \(pilot \+ M2\.2[^|]*\|", text, flags=re.M):
    raise SystemExit("m2_gate: M2 not implemented (pilot + M2.2)")
PY
echo "m2_gate: PASS"
