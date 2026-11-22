#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
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
if not re.search(r"^\| M2 \|.*\|\s*implemented \(pilot\)[^|]*\|", text, flags=re.M):
    raise SystemExit("m2_gate: M2 not implemented (pilot)")
PY
echo "m2_gate: PASS"
