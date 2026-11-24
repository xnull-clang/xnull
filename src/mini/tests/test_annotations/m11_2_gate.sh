#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    ANNOTATION_GATE_CHAIN=0 "$HERE/../annotation_platform/m0_gate.sh"
fi
"$HERE/run.sh"
python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
if not re.search(r"^\| M11\.2 \|.*implemented \(M11\.2\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m11_2_gate: M11.2 not implemented")
for name in ("TestCase", "Before", "After", "Benchmark"):
    line = next((row for row in catalog.splitlines()
                 if row.startswith("| `@" + name + "` |")), None)
    if line is None or "implemented (M11.2)" not in line:
        raise SystemExit("m11_2_gate: @" + name + " not implemented")
PY
echo "m11_2_gate: PASS"
