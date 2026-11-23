#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    "$HERE/../http_annotations/m5_gate.sh"
fi
"$HERE/run.sh"

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
for n in ("01", "02", "03", "04"):
    if not re.search(rf"^\| P6-{n} \|.*implemented \(M6\.[12]\)[^|]*\|", plan, flags=re.M):
        raise SystemExit(f"m6_gate: P6-{n} not implemented")
if not re.search(r"^\| M6 \|.*implemented \(M6\.1/M6\.2\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m6_gate: M6 not implemented")
for name in ("Sql", "Param", "Row", "Column"):
    if not re.search(rf"^\| `@{name}` \|.*implemented \(M6\.2\)[^|]*\|", catalog, flags=re.M):
        raise SystemExit(f"m6_gate: @{name} not implemented")
PY
echo "m6_gate: PASS"
