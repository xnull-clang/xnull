#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    ANNOTATION_GATE_CHAIN=0 "$HERE/../validate_annotations/m4_gate.sh"
    ANNOTATION_GATE_CHAIN=0 "$HERE/../annotation_platform/m0_gate.sh"
fi
"$HERE/run.sh"

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
if not re.search(r"^\| M8\.2 \|.*implemented \(M8\.2\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m8_2_gate: M8.2 not implemented")
for name in ("Retryable", "CircuitBreakerPolicy", "RateLimit", "TimeoutPolicy"):
    if not re.search(rf"^\| `@{name}` \|.*implemented \(M8\.2\)[^|]*\|", catalog, flags=re.M):
        raise SystemExit(f"m8_2_gate: @{name} not implemented")
PY
echo "m8_2_gate: PASS"
