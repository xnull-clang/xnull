#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    "$HERE/../sql_annotations/m6_gate.sh"
fi
"$HERE/run.sh"

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" "$ROOT/docs/design/solutions/db/README.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
readme = Path(sys.argv[3]).read_text(encoding="utf-8")
if not re.search(r"^\| M6\.5 \|.*implemented \(M6\.5\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m6_5_gate: M6.5 not implemented")
for name in ("Entity", "Table", "Id", "Transactional"):
    if not re.search(rf"^\| `@{name}` \|.*implemented \(M6\.5\)[^|]*\|", catalog, flags=re.M):
        raise SystemExit(f"m6_5_gate: @{name} not implemented")
if "M6.5" not in readme:
    raise SystemExit("m6_5_gate: db README missing M6.5 status")
PY
echo "m6_5_gate: PASS"
