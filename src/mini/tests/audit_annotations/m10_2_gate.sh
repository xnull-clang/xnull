#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    ANNOTATION_GATE_CHAIN=0 "$HERE/../cache_annotations/m8_4_gate.sh"
    ANNOTATION_GATE_CHAIN=0 "$HERE/../annotation_platform/m0_gate.sh"
fi
"$HERE/run.sh"
python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
if not re.search(r"^\| M10\.2 \|.*implemented \(M10\.2\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m10_2_gate: M10.2 not implemented")
if not re.search(r"^\| `@Audited` \|.*implemented \(M10\.2\)[^|]*\|", catalog, flags=re.M):
    raise SystemExit("m10_2_gate: @Audited not implemented")
PY
echo "m10_2_gate: PASS"
