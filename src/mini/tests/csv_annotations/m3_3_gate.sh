#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
"$HERE/run.sh"
python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
if not re.search(r"^\| M3\.3 \|.*\|\s*implemented[^|]*\|", plan, flags=re.M):
    raise SystemExit("m3_3_gate: M3.3 not implemented")
PY
echo "m3_3_gate: PASS"
