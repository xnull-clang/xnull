#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    "$HERE/../validate_annotations/m4_gate.sh"
fi
"$HERE/run.sh"

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
if not re.search(r"^\| P5-01 \|.*implemented \(M5\.1 subset\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m5_gate: P5-01 subset not implemented")
for n in ("02", "03", "04"):
    if not re.search(rf"^\| P5-{n} \|.*implemented \(M5\.2\)[^|]*\|", plan, flags=re.M):
        raise SystemExit(f"m5_gate: P5-{n} not implemented")
if not re.search(r"^\| M5 \|.*implemented \(M5\.1/M5\.2\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m5_gate: M5 not implemented")
for name in ("HttpRoute", "Header", "Query", "Body"):
    if not re.search(rf"^\| `@{name}` \|.*implemented \(M5\.2\)[^|]*\|", catalog, flags=re.M):
        raise SystemExit(f"m5_gate: @{name} not implemented")
if not re.search(r"^\| `@StatusCode` \|.*\|\s*planned[^|]*\|", catalog, flags=re.M):
    raise SystemExit("m5_gate: @StatusCode must stay planned")
PY
echo "m5_gate: PASS"
